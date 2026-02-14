// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {ReceiverTemplate} from "./Receiver.sol";
/**
 * @title ERC4626MultiCollateralVault
 * @dev A minimal, customizable multi-collateral vault for unified share tokens.
 * 
 * Implements share token functionality for multi-collateral deposits with immutable
 * redemption ratios based on original deposit composition. Share tokens are fully
 * transferrable (ERC20) while maintaining redemption ratios across holders.
 * 
 * Design Principles:
 * - Original deposit ratios are locked and immutable
 * - Shares are transferrable like standard ERC20
 * - Redemption based on original collateral mix, not current pool state
 * - All holders (original depositors & transferees) receive same ratios
 * - Ownership controls: CRE (Chainlink Runtime Environment) handles all state-changing operations
 */
abstract contract MultiCollateralVault is ERC20, Ownable , ReceiverTemplate {
    using SafeERC20 for IERC20;
    using Math for uint256;

    /*//////////////////////////////////////////////////////////////
                            TYPES & STATE
    //////////////////////////////////////////////////////////////*/

    /// @dev Represents a user's deposit batch with immutable ratio
    struct DepositBatch {
        address[] collateralTokens;      // List of collateral types
        uint256[] collateralAmounts;     // Original amounts deposited
        uint256 sharesMinted;            // Total shares issued for this batch
        uint256 depositTimestamp;        // When deposit was made
        address initiatingUser;          // Original depositor
    }

    /// @dev Tracks collateral holdings in the vault
    mapping(address => uint256) public collateralBalance;  // [tokenAddress => totalAmount]

    /// @dev Stores deposit batches by batch ID
    mapping(uint256 => DepositBatch) public depositBatches;
    uint256 public batchCounter = 1;

    /// @dev Maps user address to their batch IDs for historical tracking
    mapping(address => uint256[]) public userBatches;

    /// @dev Total shares ever issued
    uint256 public totalSharesIssued = 0;

    /// @dev List of supported collateral tokens
    IERC20[] public supportedCollaterals;

    /*//////////////////////////////////////////////////////////////
                            EVENTS
    //////////////////////////////////////////////////////////////*/

    event DepositProcessed(
        address indexed user,
        uint256 indexed batchId,
        address[] collaterals,
        uint256[] amounts,
        uint256 sharesIssued
    );

    event WithdrawalProcessed(
        address indexed user,
        uint256 shares,
        address[] collaterals,
        uint256[] amounts
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
        for (uint256 i = 0; i < supportedCollaterals.length; i++) {
            require(supportedCollaterals[i] != _token, "Collateral already supported");
        }
        supportedCollaterals.push(_token);
        emit CollateralAdded(address(_token));
    }

    /**
     * @dev Get all supported collaterals
     */
    function getSupportedCollaterals() public view returns (IERC20[] memory) {
        return supportedCollaterals;
    }

    /**
     * @dev Get count of supported collaterals
     */
    function collateralCount() public view returns (uint256) {
        return supportedCollaterals.length;
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
    ) internal virtual returns (uint256 batchId) {
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

        // Create immutable deposit batch
        batchId = batchCounter;
        DepositBatch storage batch = depositBatches[batchId];
        batch.collateralTokens = _collaterals;
        batch.collateralAmounts = _amounts;
        batch.sharesMinted = _sharesToMint;
        batch.depositTimestamp = block.timestamp;
        batch.initiatingUser = _user;

        // Track batch for user
        userBatches[_user].push(batchId);

        // Mint shares
        _mint(_user, _sharesToMint);
        totalSharesIssued += _sharesToMint;
        batchCounter++;

        emit DepositProcessed(_user, batchId, _collaterals, _amounts, _sharesToMint);

        return batchId;
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
     * @param _batchId ID of the batch to redeem from
     * @param _sharesToBurn Number of shares to burn
     * @param _receiver Address to send collaterals to
     */
    function _withdrawFromBatch(
        address _user,
        uint256 _batchId,
        uint256 _sharesToBurn,
        address _receiver
    ) internal virtual returns (address[] memory collaterals, uint256[] memory amounts) {
        require(_user != address(0), "Invalid user");
        require(_receiver != address(0), "Invalid receiver");
        require(_sharesToBurn > 0, "Burn amount must be greater than 0");
        require(balanceOf(_user) >= _sharesToBurn, "Insufficient share balance");

        DepositBatch storage batch = depositBatches[_batchId];
        require(batch.sharesMinted > 0, "Invalid batch ID");

        // Calculate redemption amounts based on original ratio
        uint256 collateralLength = batch.collateralTokens.length;
        collaterals = new address[](collateralLength);
        amounts = new uint256[](collateralLength);

        for (uint256 i = 0; i < collateralLength; ++i) {
            collaterals[i] = batch.collateralTokens[i];
            // Redemption ratio: (sharesToBurn / totalSharesInBatch) × originalAmount
            amounts[i] = (_sharesToBurn * batch.collateralAmounts[i]) / batch.sharesMinted;
            require(amounts[i] > 0, "Redemption amount too small");
        }

        // Burn shares
        _burn(_user, _sharesToBurn);

        // Transfer collaterals out
        for (uint256 i = 0; i < collateralLength; ++i) {
            IERC20(collaterals[i]).safeTransfer(_receiver, amounts[i]);
            collateralBalance[collaterals[i]] -= amounts[i];
        }

        emit WithdrawalProcessed(_user, _sharesToBurn, collaterals, amounts);

        return (collaterals, amounts);
    }

    /*//////////////////////////////////////////////////////////////
                    CRE REPORT PROCESSING
    //////////////////////////////////////////////////////////////*/

    /// @dev _processReport is called by ReceiverTemplate.onReport after security checks.
    /// Report format: leading uint256 `batchId` followed by ABI-encoded payload.
    /// - If `batchId == 0` then this is a deposit: abi.encode(uint256(0), address user, address[] collaterals, uint256[] amounts, uint256 sharesToMint)
    /// - If `batchId != 0` then this is a redeem: abi.encode(uint256(batchId), address user, uint256 sharesToBurn, address receiver)
    function _processReport(bytes calldata report) internal virtual override {
        require(report.length >= 32, "Empty report");

        uint256 batchId = abi.decode(report[0:32], (uint256));

        if (batchId == 0) {
            ( , address user, address[] memory collaterals, uint256[] memory amounts, uint256 sharesToMint) = abi.decode(report, (uint256, address, address[], uint256[], uint256));
            _validateDeposit(collaterals, amounts, sharesToMint);
            _depositCollaterals(user, collaterals, amounts, sharesToMint);
            return;
        } else {
            // Redeem path
            ( , address user2, uint256 sharesToBurn, address receiver) = abi.decode(report, (uint256, address, uint256, address));
            _validateWithdrawal(user2, batchId, sharesToBurn);
            _withdrawFromBatch(user2, batchId, sharesToBurn, receiver);
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
     * @dev Get deposit batch details
     */
    function getBatchDetails(uint256 _batchId)
        public
        view
        returns (
            address[] memory collaterals,
            uint256[] memory amounts,
            uint256 shares,
            uint256 timestamp,
            address depositor
        )
    {
        DepositBatch storage batch = depositBatches[_batchId];
        return (
            batch.collateralTokens,
            batch.collateralAmounts,
            batch.sharesMinted,
            batch.depositTimestamp,
            batch.initiatingUser
        );
    }

    /**
     * @dev Get all batch IDs for a user
     */
    function getUserBatches(address _user) public view returns (uint256[] memory) {
        return userBatches[_user];
    }

    /**
     * @dev Calculate redemption amounts for a given batch and share amount
     */
    function previewBatchRedemption(uint256 _batchId, uint256 _sharesToBurn)
        public
        view
        returns (address[] memory collaterals, uint256[] memory amounts)
    {
        DepositBatch storage batch = depositBatches[_batchId];
        require(batch.sharesMinted > 0, "Invalid batch ID");

        uint256 collateralLength = batch.collateralTokens.length;
        collaterals = new address[](collateralLength);
        amounts = new uint256[](collateralLength);

        for (uint256 i = 0; i < collateralLength; i++) {
            collaterals[i] = batch.collateralTokens[i];
            amounts[i] = (_sharesToBurn * batch.collateralAmounts[i]) / batch.sharesMinted;
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
    function _validateWithdrawal(address _user, uint256 _batchId, uint256 _sharesToBurn)
        internal
        view
        virtual
    {}
}
