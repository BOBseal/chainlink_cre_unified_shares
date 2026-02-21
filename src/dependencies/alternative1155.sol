// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC1155} from "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {ReceiverTemplate} from "./Receiver.sol";

/**
 * @title ERC4626MultiCollateralVault1155
 * @dev Multi-collateral vault using ERC1155 tokens for collateral.
 *
 * This mirrors the design of `MultiCollateralVault` but accepts ERC1155
 * collateral items. Each collateral entry is a (contract, id, amount) tuple
 * and deposit batches record those tuples immutably for ratio-based
 * redemption.
 */
/// @notice Minimal ERC1155 share token controlled by the vault (owner)
contract ERC1155Shares is ERC1155, Ownable {
    constructor(string memory uri_) ERC1155(uri_) Ownable(msg.sender) {}

    function mint(address to, uint256 id, uint256 amount) external onlyOwner {
        _mint(to, id, amount, "");
    }

    function burn(address from, uint256 id, uint256 amount) external onlyOwner {
        _burn(from, id, amount);
    }
}

abstract contract Alternative1155Vault is ReceiverTemplate {
    using Math for uint256;
    using SafeERC20 for IERC20;

    ERC1155Shares public shareToken;

    /*//////////////////////////////////////////////////////////////
                            TYPES & STATE
    //////////////////////////////////////////////////////////////*/

    struct DepositBatch {
        address[] collateralTokens;      // List of collateral ERC20 token addresses
        uint256[] collateralAmounts;     // Original amounts deposited
        uint256 sharesMinted;            // Total shares issued for this tokenId
        uint256 depositTimestamp;        // When deposit was made
        address initiatingUser;          // Original depositor
    }

    /// @dev Tracks collateral holdings in the vault: tokenAddress => totalAmount
    mapping(address => uint256) public collateralBalance;

    /// @dev Stores deposit batches by tokenId (share id)
    mapping(uint256 => DepositBatch) public depositBatches;
    uint256 public tokenCounter = 1;

    /// @dev Total shares ever issued across all tokenIds
    uint256 public totalSharesIssued = 0;

    /*//////////////////////////////////////////////////////////////
                            EVENTS
    //////////////////////////////////////////////////////////////*/

    event DepositProcessed(
        address indexed user,
        uint256 indexed tokenId,
        address[] collaterals,
        uint256[] amounts,
        uint256 sharesIssued
    );

    event WithdrawalProcessed(
        address indexed user,
        uint256 tokenId,
        uint256 sharesBurned,
        address[] collaterals,
        uint256[] amounts
    );

    /*//////////////////////////////////////////////////////////////
                        INITIALIZATION
    //////////////////////////////////////////////////////////////*/

    /// @param _uri ERC1155 metadata URI (can be empty)
    constructor(
        string memory _uri,
        address _trustedForwarder
    ) ReceiverTemplate(_trustedForwarder) {
        shareToken = new ERC1155Shares(_uri);
    }

    /*//////////////////////////////////////////////////////////////
                    COLLATERAL MANAGEMENT
    //////////////////////////////////////////////////////////////*/

    // Collateral management is intentionally minimal; supported tokens can be
    // validated by overriding `_validateDeposit` if needed.

    /*//////////////////////////////////////////////////////////////
                    DEPOSIT LOGIC (Called by CRE)
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev _collaterals: array of ERC1155 contract addresses
     * @dev _ids: array of token ids (one per collateral entry)
     * @dev _amounts: array of amounts per (contract,id)
     */
    /**
     * @dev Process deposit of multiple ERC20 collaterals and mint ERC1155 shares
     * @param _user recipient of minted shares
     * @param _collaterals array of ERC20 token addresses
     * @param _amounts array of amounts per collateral
     * @param _sharesToMint amount of share tokens to mint (ERC1155 amount)
     * @return tokenId minted
     */
    function _depositCollaterals(
        address _user,
        address[] memory _collaterals,
        uint256[] memory _amounts,
        uint256 _sharesToMint
    ) internal virtual returns (uint256 tokenId) {
        require(_user != address(0), "Invalid user address");
        require(_collaterals.length == _amounts.length, "Array length mismatch");
        require(_collaterals.length > 0, "Must deposit at least one collateral");
        require(_sharesToMint > 0, "Shares must be greater than 0");

        // Transfer ERC20 collaterals from user to vault
        for (uint256 i = 0; i < _collaterals.length; ++i) {
            require(_amounts[i] > 0, "Amount must be greater than 0");
            IERC20(_collaterals[i]).safeTransferFrom(_user, address(this), _amounts[i]);
            collateralBalance[_collaterals[i]] += _amounts[i];
        }

        tokenId = tokenCounter;
        DepositBatch storage batch = depositBatches[tokenId];
        batch.collateralTokens = _collaterals;
        batch.collateralAmounts = _amounts;
        batch.sharesMinted = _sharesToMint;
        batch.depositTimestamp = block.timestamp;
        batch.initiatingUser = _user;

        // Mint ERC1155 share tokens for this deposit batch (external share contract)
        shareToken.mint(_user, tokenId, _sharesToMint);
        totalSharesIssued += _sharesToMint;
        tokenCounter++;

        emit DepositProcessed(_user, tokenId, _collaterals, _amounts, _sharesToMint);

        return tokenId;
    }

    /**
     * @dev Allow the batch initiator to deposit additional collateral to an existing batch
     * while maintaining the original collateral ratios. CRE calculates the shares offchain.
     * @param _user recipient of minted shares
     * @param _tokenId The share token ID (batch ID) to deposit into
     * @param _collaterals array of ERC20 token addresses
     * @param _amounts Array of additional amounts per collateral
     * @param _sharesToMint amount of share tokens to mint (calculated by CRE)
     */
    function _depositToExistingBatch(
        address _user,
        uint256 _tokenId,
        address[] memory _collaterals,
        uint256[] memory _amounts,
        uint256 _sharesToMint
    ) internal virtual {
        require(_user != address(0), "Invalid user address");
        require(_sharesToMint > 0, "Shares must be greater than 0");

        DepositBatch storage batch = depositBatches[_tokenId];

        require(batch.sharesMinted > 0, "Invalid tokenId - batch does not exist");
        require(_user == batch.initiatingUser, "Only batch initiator can deposit to existing batch");
        require(_collaterals.length == _amounts.length, "Array length mismatch");
        require(_collaterals.length == batch.collateralTokens.length, "Array length mismatch with batch collaterals");

        uint256 collateralLength = _collaterals.length;

        // Transfer ERC20 collaterals from user to vault
        for (uint256 i = 0; i < collateralLength; ++i) {
            require(_amounts[i] > 0, "Amount must be greater than 0");
            require(_collaterals[i] == batch.collateralTokens[i], "Collateral token mismatch");
            IERC20(_collaterals[i]).safeTransferFrom(_user, address(this), _amounts[i]);
            collateralBalance[_collaterals[i]] += _amounts[i];

            // Update batch with new accumulated amounts
            batch.collateralAmounts[i] += _amounts[i];
        }

        // Update batch shares and emit event
        batch.sharesMinted += _sharesToMint;
        totalSharesIssued += _sharesToMint;

        // Mint new ERC1155 share tokens
        shareToken.mint(_user, _tokenId, _sharesToMint);

        emit DepositProcessed(_user, _tokenId, _collaterals, _amounts, _sharesToMint);
    }

    /*//////////////////////////////////////////////////////////////
                    WITHDRAWAL LOGIC (Called by CRE)
    //////////////////////////////////////////////////////////////*/

    function _withdrawFromTokenId(
        address _user,
        uint256 _tokenId,
        uint256 _sharesToBurn,
        address _receiver
    ) internal virtual returns (address[] memory collaterals, uint256[] memory amounts) {
        require(_user != address(0), "Invalid user");
        require(_receiver != address(0), "Invalid receiver");
        require(_sharesToBurn > 0, "Burn amount must be greater than 0");
        require(shareToken.balanceOf(_user, _tokenId) >= _sharesToBurn, "Insufficient share balance");

        DepositBatch storage batch = depositBatches[_tokenId];
        require(batch.sharesMinted > 0, "Invalid tokenId");

        uint256 collateralLength = batch.collateralTokens.length;
        collaterals = new address[](collateralLength);
        amounts = new uint256[](collateralLength);

        for (uint256 i = 0; i < collateralLength; ++i) {
            collaterals[i] = batch.collateralTokens[i];
            amounts[i] = (_sharesToBurn * batch.collateralAmounts[i]) / batch.sharesMinted;
            require(amounts[i] > 0, "Redemption amount too small");
        }

        // Burn ERC1155 share tokens from user (via share contract)
        shareToken.burn(_user, _tokenId, _sharesToBurn);

        // Deduct shares from batch
        batch.sharesMinted -= _sharesToBurn;

        // Transfer ERC20 collaterals to receiver
        for (uint256 i = 0; i < collateralLength; ++i) {
            IERC20(collaterals[i]).safeTransfer(_receiver, amounts[i]);
            collateralBalance[collaterals[i]] -= amounts[i];
        }

        emit WithdrawalProcessed(_user, _tokenId, _sharesToBurn, collaterals, amounts);

        return (collaterals, amounts);
    }

    // ERC1155 transfer hooks can be overridden if specific share-id rebalancing
    // or tracking is required. By default, transfers are standard ERC1155.

    /*//////////////////////////////////////////////////////////////
                    CRE REPORT PROCESSING
    //////////////////////////////////////////////////////////////*/

    /// Report format for new batch deposit (isDeposit=true, tokenId=0):
    /// abi.encode(true, uint256(0), address user, address[] collaterals, uint256[] amounts, uint256 sharesToMint)
    /// Report format for deposit to existing batch (isDeposit=true, tokenId>0):
    /// abi.encode(true, uint256(tokenId), address user, address[] collaterals, uint256[] amounts, uint256 sharesToMint)
    /// Report format for withdrawal (isDeposit=false, tokenId>0):
    /// abi.encode(false, uint256(tokenId), address user, uint256 sharesToBurn, address receiver)
    function _processReport(bytes calldata report) internal virtual override {
        require(report.length >= 64, "Report too short");

        (bool isDeposit, uint256 tokenId) = abi.decode(report[0:64], (bool, uint256));

        if (isDeposit) {
            // Deposit operations (new batch or existing batch)
            ( , , address user, address[] memory collaterals, uint256[] memory amounts, uint256 sharesToMint) = abi.decode(report, (bool, uint256, address, address[], uint256[], uint256));
            _validateDeposit(collaterals, amounts, sharesToMint);

            if (tokenId == 0) {
                // New batch deposit
                _depositCollaterals(user, collaterals, amounts, sharesToMint);
            } else {
                // Deposit to existing batch
                _depositToExistingBatch(user, tokenId, collaterals, amounts, sharesToMint);
            }
        } else {
            // Withdrawal
            ( , , address user, uint256 sharesToBurn, address receiver) = abi.decode(report, (bool, uint256, address, uint256, address));
            _validateWithdrawal(user, tokenId, sharesToBurn);
            _withdrawFromTokenId(user, tokenId, sharesToBurn, receiver);
        }
    }

    /*//////////////////////////////////////////////////////////////
                        ACCOUNTING LOGIC
    //////////////////////////////////////////////////////////////*/

    function getCollateralBalance(address _token) public view returns (uint256) {
        return collateralBalance[_token];
    }

    function getBatchDetails(uint256 _tokenId)
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
        DepositBatch storage batch = depositBatches[_tokenId];
        return (
            batch.collateralTokens,
            batch.collateralAmounts,
            batch.sharesMinted,
            batch.depositTimestamp,
            batch.initiatingUser
        );
    }

    function previewBatchRedemption(uint256 _tokenId, uint256 _sharesToBurn)
        public
        view
        returns (address[] memory collaterals, uint256[] memory amounts)
    {
        DepositBatch storage batch = depositBatches[_tokenId];
        require(batch.sharesMinted > 0, "Invalid tokenId");

        uint256 collateralLength = batch.collateralTokens.length;
        collaterals = new address[](collateralLength);
        amounts = new uint256[](collateralLength);

        for (uint256 i = 0; i < collateralLength; i++) {
            collaterals[i] = batch.collateralTokens[i];
            amounts[i] = (_sharesToBurn * batch.collateralAmounts[i]) / batch.sharesMinted;
        }

        return (collaterals, amounts);
    }

    /**
     * @dev Preview the shares that would be minted for a deposit to an existing batch
     * @param _tokenId The batch token ID
     * @param _amounts Array of deposit amounts per collateral
     * @return sharesToMint Amount of shares that would be minted
     */
    function previewDepositToExistingBatch(uint256 _tokenId, uint256[] memory _amounts)
        public
        view
        returns (uint256 sharesToMint)
    {
        DepositBatch storage batch = depositBatches[_tokenId];
        require(batch.sharesMinted > 0, "Invalid tokenId - batch does not exist");
        require(_amounts.length == batch.collateralTokens.length, "Array length mismatch with batch collaterals");
        require(_amounts[0] > 0, "Amount must be greater than 0");

        // Calculate shares based on the ratio of new deposit to original deposit
        sharesToMint = (_amounts[0] * batch.sharesMinted) / batch.collateralAmounts[0];

        return sharesToMint;
    }

    /*//////////////////////////////////////////////////////////////
                        OVERRIDE HOOKS
    //////////////////////////////////////////////////////////////*/

    function _validateDeposit(
        address[] memory _collaterals,
        uint256[] memory _amounts,
        uint256 _sharesToMint
    ) internal view virtual {}

    function _validateWithdrawal(address _user, uint256 _tokenId, uint256 _sharesToBurn)
        internal
        view
        virtual
    {}

    // Note: `supportsInterface` is inherited from `ReceiverTemplate`.
}