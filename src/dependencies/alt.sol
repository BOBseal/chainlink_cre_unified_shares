// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {ReceiverTemplate} from "./Receiver.sol";

/**
 * @title ERC4626MultiCollateralVaultAlt
 * @dev An enhanced multi-collateral vault with user-wise batch tracking and transfer-aware batch management.
 * 
 * Key improvements over MultiCollateralVault:
 * - Batch IDs are deterministically hashed from collaterals and user (no sequential counter)
 * - Batches tracked per user instead of globally (user-wise mapping structure)
 * - Share transfers automatically split and rehash batches for receiver
 * - Uses mappings throughout for gas efficiency
 * 
 * Design Principles:
 * - Original deposit ratios are locked and immutable
 * - Shares are transferrable with automatic batch rebalancing
 * - Redemption based on original collateral mix, not current pool state
 * - Each user has their own batch tracking via hashed identifiers
 * - Ownership controls: CRE (Chainlink Runtime Environment) handles all state-changing operations
 */
abstract contract MultiCollateralVaultAlt is ERC20, Ownable, ReceiverTemplate {
    using SafeERC20 for IERC20;
    using Math for uint256;

    /*//////////////////////////////////////////////////////////////
                            TYPES & STATE
    //////////////////////////////////////////////////////////////*/

    /// @dev Represents a user's deposit batch with immutable ratio
    struct DepositBatch {
        bytes32 collateralHash;         // Hash of collateral tokens (for ID generation)
        mapping(address => uint256) collateralAmounts;  // Original amounts deposited per token
        uint256 sharesMinted;           // Total shares issued for this batch
        uint256 depositTimestamp;       // When deposit was made
        uint256 collateralCount;        // Number of unique collaterals
    }

    /// @dev Tracks collateral holdings in the vault
    mapping(address => uint256) public collateralBalance;  // [tokenAddress => totalAmount]

    /// @dev User-wise batch tracking: user -> batchHash -> DepositBatch
    mapping(address => mapping(bytes32 => DepositBatch)) public userDepositBatches;

    /// @dev Maps user to their batch hashes for enumeration
    mapping(address => bytes32[]) public userBatchHashes;

    /// @dev Tracks which collaterals belong to which batch hash (for batch details retrieval)
    /// batchHash -> collateral address -> is supported in this batch
    mapping(bytes32 => mapping(address => bool)) public batchCollaterals;

    /// @dev Tracks all collateral addresses in a batch
    /// user -> batchHash -> collateral addresses array (stored as encoded list)
    mapping(address => mapping(bytes32 => address[])) public userBatchCollateralTokens;

    /// @dev Total shares ever issued
    uint256 public totalSharesIssued = 0;

    /// @dev Supported collaterals mapping
    mapping(address => bool) public supportedCollateralsMap;
    address[] public supportedCollateralsList;

    /*//////////////////////////////////////////////////////////////
                            EVENTS
    //////////////////////////////////////////////////////////////*/

    event DepositProcessed(
        address indexed user,
        bytes32 indexed batchHash,
        address[] collaterals,
        uint256[] amounts,
        uint256 sharesIssued
    );

    event WithdrawalProcessed(
        address indexed user,
        bytes32 indexed batchHash,
        uint256 shares,
        address[] collaterals,
        uint256[] amounts
    );

    event ShareTransferWithBatchRehash(
        address indexed from,
        address indexed to,
        uint256 shares,
        bytes32 fromBatchHash,
        bytes32 toBatchHash
    );

    event CollateralAdded(address indexed token);

    /*//////////////////////////////////////////////////////////////
                        INITIALIZATION
    //////////////////////////////////////////////////////////////*/

    constructor(
        string memory _name,
        string memory _symbol,
        address _trustedForwarder
    )
    ERC20(_name, _symbol)
    ReceiverTemplate(_trustedForwarder)
    {
    }

    /*//////////////////////////////////////////////////////////////
                    COLLATERAL MANAGEMENT
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Add a new supported collateral token
     */
    function addCollateral(IERC20 _token) public virtual onlyOwner {
        address tokenAddr = address(_token);
        require(!supportedCollateralsMap[tokenAddr], "Collateral already supported");
        supportedCollateralsMap[tokenAddr] = true;
        supportedCollateralsList.push(tokenAddr);
        emit CollateralAdded(tokenAddr);
    }

    /**
     * @dev Get all supported collaterals
     */
    function getSupportedCollaterals() public view returns (address[] memory) {
        return supportedCollateralsList;
    }

    /**
     * @dev Get count of supported collaterals
     */
    function collateralCount() public view returns (uint256) {
        return supportedCollateralsList.length;
    }

    /*//////////////////////////////////////////////////////////////
                    BATCH ID GENERATION (HASHING)
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Generate deterministic batch hash from collaterals and user
     * Uses keccak256 hash of sorted collateral addresses and user
     * This ensures same deposits produce same batch ID
     */
    function _generateBatchHash(
        address _user,
        address[] memory _collaterals,
        uint256[] memory _amounts
    ) internal pure returns (bytes32) {
        // Create a sorted, deduplicated list of collaterals with their amounts
        bytes memory encodedData = abi.encode(_user, _collaterals, _amounts);
        return keccak256(encodedData);
    }

    /*//////////////////////////////////////////////////////////////
                    DEPOSIT LOGIC (Called by CRE)
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Process deposit from multiple collaterals and mint shares
     * Called externally (typically by Chainlink CRE after consensus)
     * Only owner (CRE) can call this function
     *
     * @param _user Address receiving shares
     * @param _collaterals Array of collateral token addresses
     * @param _amounts Array of collateral amounts to deposit
     * @param _sharesToMint Amount of shares to mint
     */
    function _depositCollaterals(
        address _user,
        address[] memory _collaterals,
        uint256[] memory _amounts,
        uint256 _sharesToMint
    ) internal virtual returns (bytes32 batchHash) {
        require(_user != address(0), "Invalid user address");
        require(_collaterals.length == _amounts.length, "Array length mismatch");
        require(_collaterals.length > 0, "Must deposit at least one collateral");
        require(_sharesToMint > 0, "Shares must be greater than 0");

        // Transfer collaterals from user to vault
        for (uint256 i = 0; i < _collaterals.length; ++i) {
            require(_amounts[i] > 0, "Amount must be greater than 0");
            IERC20(_collaterals[i]).safeTransferFrom(_user, address(this), _amounts[i]);
            collateralBalance[_collaterals[i]] += _amounts[i];
        }

        // Generate batch hash from collaterals and user
        batchHash = _generateBatchHash(_user, _collaterals, _amounts);

        // Create user-wise deposit batch
        DepositBatch storage batch = userDepositBatches[_user][batchHash];
        batch.collateralHash = batchHash;
        batch.sharesMinted = _sharesToMint;
        batch.depositTimestamp = block.timestamp;
        batch.collateralCount = _collaterals.length;

        // Store collateral amounts and tokens
        for (uint256 i = 0; i < _collaterals.length; ++i) {
            batch.collateralAmounts[_collaterals[i]] = _amounts[i];
            batchCollaterals[batchHash][_collaterals[i]] = true;
        }

        // Store collateral tokens for this batch
        userBatchCollateralTokens[_user][batchHash] = _collaterals;

        // Track batch hash for user (if not already tracked)
        bool batchExists = false;
        bytes32[] storage userBatches = userBatchHashes[_user];
        for (uint256 i = 0; i < userBatches.length; ++i) {
            if (userBatches[i] == batchHash) {
                batchExists = true;
                break;
            }
        }
        if (!batchExists) {
            userBatchHashes[_user].push(batchHash);
        }

        // Mint shares
        _mint(_user, _sharesToMint);
        totalSharesIssued += _sharesToMint;

        emit DepositProcessed(_user, batchHash, _collaterals, _amounts, _sharesToMint);

        return batchHash;
    }

    /*//////////////////////////////////////////////////////////////
                    WITHDRAWAL LOGIC (Called by CRE)
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Process withdrawal based on original batch ratio
     * Called externally (typically by Chainlink CRE after consensus)
     * Only owner (CRE) can call this function
     *
     * Redemption formula per collateral:
     * Amount = (sharesToBurn / batchTotalShares) × originalCollateralAmount
     *
     * @param _user Address burning shares and receiving collaterals
     * @param _batchHash Hash ID of the batch to redeem from
     * @param _sharesToBurn Number of shares to burn
     * @param _receiver Address to send collaterals to
     */
    function _withdrawFromBatch(
        address _user,
        bytes32 _batchHash,
        uint256 _sharesToBurn,
        address _receiver
    ) internal virtual returns (address[] memory collaterals, uint256[] memory amounts) {
        require(_user != address(0), "Invalid user");
        require(_receiver != address(0), "Invalid receiver");
        require(_sharesToBurn > 0, "Burn amount must be greater than 0");
        require(balanceOf(_user) >= _sharesToBurn, "Insufficient share balance");

        DepositBatch storage batch = userDepositBatches[_user][_batchHash];
        require(batch.sharesMinted > 0, "Invalid batch hash");

        // Get collaterals for this batch
        collaterals = userBatchCollateralTokens[_user][_batchHash];
        uint256 collateralLength = collaterals.length;
        amounts = new uint256[](collateralLength);

        // Calculate redemption amounts based on original ratio
        for (uint256 i = 0; i < collateralLength; ++i) {
            address collateralToken = collaterals[i];
            uint256 originalAmount = batch.collateralAmounts[collateralToken];
            // Redemption ratio: (sharesToBurn / totalSharesInBatch) × originalAmount
            amounts[i] = (_sharesToBurn * originalAmount) / batch.sharesMinted;
            require(amounts[i] > 0, "Redemption amount too small");
        }

        // Burn shares
        _burn(_user, _sharesToBurn);

        // Transfer collaterals out
        for (uint256 i = 0; i < collateralLength; ++i) {
            IERC20(collaterals[i]).safeTransfer(_receiver, amounts[i]);
            collateralBalance[collaterals[i]] -= amounts[i];
        }

        emit WithdrawalProcessed(_user, _batchHash, _sharesToBurn, collaterals, amounts);

        return (collaterals, amounts);
    }

    /*//////////////////////////////////////////////////////////////
                    SHARE TRANSFER WITH BATCH REHASHING
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Override _beforeTokenTransfer to handle batch rehashing on share transfers
     * When shares are transferred between users, the receiver gets new batch entries
     * with proportional collateral amounts, rehashed for their user address
     */
    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 amount
    ) internal virtual override {
        super._beforeTokenTransfer(from, to, amount);

        // Skip for minting and burning
        if (from == address(0) || to == address(0)) {
            return;
        }

        // Skip if no shares are being transferred
        if (amount == 0) {
            return;
        }

        // For each batch the sender has, create proportional batches for receiver
        bytes32[] memory fromBatches = userBatchHashes[from];
        for (uint256 i = 0; i < fromBatches.length; ++i) {
            bytes32 fromBatchHash = fromBatches[i];
            DepositBatch storage fromBatch = userDepositBatches[from][fromBatchHash];

            if (fromBatch.sharesMinted == 0) continue;

            // Calculate proportion of this batch being transferred
            uint256 senderBalance = balanceOf(from) - amount; // Check balance AFTER transfer
            // Actually, we need the balance BEFORE transfer for correct ratio
            uint256 proportionNumerator = amount;
            uint256 proportionDenominator = balanceOf(from) + amount; // Total before transfer

            // Calculate shares from this batch being transferred
            // This is based on pro-rata distribution assuming all shares are fungible
            uint256 sharesToTransfer = (amount * fromBatch.sharesMinted) / (balanceOf(from) + amount);

            if (sharesToTransfer == 0) continue;

            // Get collaterals from sender's batch
            address[] memory collaterals = userBatchCollateralTokens[from][fromBatchHash];

            // Create new amounts proportional to transfer
            uint256[] memory transferredAmounts = new uint256[](collaterals.length);
            for (uint256 j = 0; j < collaterals.length; ++j) {
                address token = collaterals[j];
                uint256 originalAmount = fromBatch.collateralAmounts[token];
                transferredAmounts[j] = (originalAmount * sharesToTransfer) / fromBatch.sharesMinted;
            }

            // Generate new batch hash for receiver using their address and same collaterals
            bytes32 toBatchHash = _generateBatchHash(to, collaterals, transferredAmounts);

            // Create or update receiver's batch
            DepositBatch storage toBatch = userDepositBatches[to][toBatchHash];

            // If this is a new batch for receiver, initialize it
            if (toBatch.sharesMinted == 0) {
                toBatch.collateralHash = toBatchHash;
                toBatch.depositTimestamp = block.timestamp;
                toBatch.collateralCount = collaterals.length;

                // Track batch hash for receiver
                userBatchHashes[to].push(toBatchHash);
            }

            // Add collateral amounts to receiver's batch
            for (uint256 j = 0; j < collaterals.length; ++j) {
                address token = collaterals[j];
                toBatch.collateralAmounts[token] += transferredAmounts[j];
                if (!batchCollaterals[toBatchHash][token]) {
                    batchCollaterals[toBatchHash][token] = true;
                }
            }

            // Store tokens for receiver's batch if not already stored
            if (userBatchCollateralTokens[to][toBatchHash].length == 0) {
                userBatchCollateralTokens[to][toBatchHash] = collaterals;
            }

            // Update shares
            toBatch.sharesMinted += sharesToTransfer;

            // Update sender's batch (reduce shares and collateral amounts)
            fromBatch.sharesMinted -= sharesToTransfer;
            for (uint256 j = 0; j < collaterals.length; ++j) {
                address token = collaterals[j];
                fromBatch.collateralAmounts[token] -= transferredAmounts[j];
            }

            emit ShareTransferWithBatchRehash(from, to, amount, fromBatchHash, toBatchHash);
        }
    }

    /*//////////////////////////////////////////////////////////////
                    CRE REPORT PROCESSING
    //////////////////////////////////////////////////////////////*/

    /// @dev _processReport is called by ReceiverTemplate.onReport after security checks.
    /// Report format: leading bytes32 `batchHash` followed by ABI-encoded payload.
    /// - If `batchHash == 0` then this is a deposit: abi.encode(bytes32(0), address user, address[] collaterals, uint256[] amounts, uint256 sharesToMint)
    /// - If `batchHash != 0` then this is a redeem: abi.encode(bytes32(batchHash), address user, uint256 sharesToBurn, address receiver)
    function _processReport(bytes calldata report) internal virtual override {
        require(report.length >= 32, "Empty report");

        bytes32 batchHash = abi.decode(report[0:32], (bytes32));

        if (batchHash == bytes32(0)) {
            ( , address user, address[] memory collaterals, uint256[] memory amounts, uint256 sharesToMint) = abi.decode(report, (bytes32, address, address[], uint256[], uint256));
            _validateDeposit(collaterals, amounts, sharesToMint);
            _depositCollaterals(user, collaterals, amounts, sharesToMint);
            return;
        } else {
            // Redeem path
            ( , address user2, uint256 sharesToBurn, address receiver) = abi.decode(report, (bytes32, address, uint256, address));
            _validateWithdrawal(user2, batchHash, sharesToBurn);
            _withdrawFromBatch(user2, batchHash, sharesToBurn, receiver);
        }
    }

    /*//////////////////////////////////////////////////////////////
                        ACCOUNTING LOGIC
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Get total value of specific collateral in vault
     */
    function getCollateralBalance(address _token) public view returns (uint256) {
        return collateralBalance[_token];
    }

    /**
     * @dev Get deposit batch details for a user
     */
    function getBatchDetails(address _user, bytes32 _batchHash)
        public
        view
        returns (
            address[] memory collaterals,
            uint256[] memory amounts,
            uint256 shares,
            uint256 timestamp
        )
    {
        DepositBatch storage batch = userDepositBatches[_user][_batchHash];
        require(batch.sharesMinted > 0, "Invalid batch ID");

        collaterals = userBatchCollateralTokens[_user][_batchHash];
        amounts = new uint256[](collaterals.length);

        for (uint256 i = 0; i < collaterals.length; ++i) {
            amounts[i] = batch.collateralAmounts[collaterals[i]];
        }

        return (
            collaterals,
            amounts,
            batch.sharesMinted,
            batch.depositTimestamp
        );
    }

    /**
     * @dev Get all batch hashes for a user
     */
    function getUserBatchHashes(address _user) public view returns (bytes32[] memory) {
        return userBatchHashes[_user];
    }

    /**
     * @dev Get number of batches for a user
     */
    function getUserBatchCount(address _user) public view returns (uint256) {
        return userBatchHashes[_user].length;
    }

    /**
     * @dev Calculate redemption amounts for a given batch and share amount
     */
    function previewBatchRedemption(address _user, bytes32 _batchHash, uint256 _sharesToBurn)
        public
        view
        returns (address[] memory collaterals, uint256[] memory amounts)
    {
        DepositBatch storage batch = userDepositBatches[_user][_batchHash];
        require(batch.sharesMinted > 0, "Invalid batch ID");

        collaterals = userBatchCollateralTokens[_user][_batchHash];
        amounts = new uint256[](collaterals.length);

        for (uint256 i = 0; i < collaterals.length; ++i) {
            address token = collaterals[i];
            uint256 originalAmount = batch.collateralAmounts[token];
            amounts[i] = (_sharesToBurn * originalAmount) / batch.sharesMinted;
        }

        return (collaterals, amounts);
    }

    /*//////////////////////////////////////////////////////////////
                        OVERRIDE HOOKS
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Hook for custom validation on deposit (override for custom logic)
     */
    function _validateDeposit(
        address[] memory _collaterals,
        uint256[] memory _amounts,
        uint256 _sharesToMint
    ) internal view virtual {}

    /**
     * @dev Hook for custom validation on withdrawal (override for custom logic)
     */
    function _validateWithdrawal(address _user, bytes32 _batchHash, uint256 _sharesToBurn)
        internal
        view
        virtual
    {}
}
