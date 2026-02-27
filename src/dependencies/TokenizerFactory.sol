// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {CollateralBase} from "./CollateralBase.sol";
import {ReceiverTemplate} from "./Receiver.sol";

/**
 * @title TokenizerFactory
 * @dev Factory for deploying collateralized ERC20 share tokens with CRE-controlled operations.
 * 
 * Each deployed share token has its own:
 * - Custom collateral pools (ERC20 tokens accepted as collateral)
 * - Immutable redemption ratios based on original deposit composition
 * - Batch-based tracking for users to maintain consistent redemption ratios
 * - CRE-controlled operations via action codes (uint8)
 * 
 * Action Codes:
 * - 0 (MINT_SHARES): Create new batch and mint shares
 * - 1 (DEPOSIT_EXISTING): Deposit more collateral to existing batch and mint shares
 * - 2 (REDEEM_SHARES): Burn shares and withdraw collateral
 */
contract TokenizerFactory {
    using SafeERC20 for IERC20;
    using Math for uint256;

    /*//////////////////////////////////////////////////////////////
                            TYPES & STATE
    //////////////////////////////////////////////////////////////*/

    /// @dev Represents a user's deposit batch with immutable collateral ratio
    struct DepositBatch20 {
        address[] collateralTokens;      // List of collateral types
        uint256[] collateralAmounts;     // Original amounts deposited
        uint256 sharesMinted;            // Total shares issued for this batch
        uint256 depositTimestamp;        // When deposit was made
        address initiatingUser;          // Original depositor
    }

    /// @dev Represents a deployed tokenizer vault instance
    struct TokenizerVault {
        address shareToken;              // CollateralBase ERC20 token
        address deployer;                // User who deployed this tokenizer
        address[] supportedCollaterals;  // Array of accepted collateral tokens
        mapping(address => uint256) collateralBalance;  // Total held per collateral
        mapping(uint256 => DepositBatch20) depositBatches;  // Batches by ID
        uint256 batchCounter;            // Next batch ID
        uint256 totalSharesIssued;       // Cumulative shares minted
        bool isActive;                   // Whether this vault is active
    }

    /// @dev Maps tokenizer vault ID to vault data
    mapping(uint256 => TokenizerVault) public tokenizers;
    uint256 public tokenizerId = 0;

    /// @dev Maps share token address to vault ID for quick lookup
    mapping(address => uint256) public shareTokenToVault;

    /// @dev Maps user address to their deployed tokenizers
    mapping(address => uint256[]) public userTokenizers;

    /*//////////////////////////////////////////////////////////////
                            EVENTS
    //////////////////////////////////////////////////////////////*/

    event TokenizerDeployed(
        uint256 indexed vaultId,
        address indexed deployer,
        address indexed shareToken,
        string name,
        string symbol
    );

    event CollateralAdded(
        uint256 indexed vaultId,
        address indexed collateral
    );

    event DepositProcessed(
        uint256 indexed vaultId,
        address indexed user,
        uint256 indexed batchId,
        address[] collaterals,
        uint256[] amounts,
        uint256 sharesIssued
    );

    event DepositToExistingProcessed(
        uint256 indexed vaultId,
        address indexed user,
        uint256 indexed batchId,
        address[] collaterals,
        uint256[] amounts,
        uint256 sharesIssued
    );

    event WithdrawalProcessed(
        uint256 indexed vaultId,
        address indexed user,
        uint256 indexed batchId,
        uint256 sharesBurned,
        address[] collaterals,
        uint256[] amounts
    );

    /*//////////////////////////////////////////////////////////////
                        INITIALIZATION
    //////////////////////////////////////////////////////////////*/

    constructor() {}

    /*//////////////////////////////////////////////////////////////
                    DEPLOYMENT & FACTORY LOGIC
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Deploy a new collateralized share token
     * @param _name Name of the share token
     * @param _symbol Symbol of the share token
     * @param _collaterals Initial array of supported collateral tokens
     * @return vaultId The ID of the deployed tokenizer
     * @return shareToken The address of the deployed share token
     */
    function deployTokenizer(
        string memory _name,
        string memory _symbol,
        address[] memory _collaterals
    ) external returns (uint256 vaultId, address shareToken) {
        require(_collaterals.length > 0, "Must add at least one collateral");
        require(bytes(_name).length > 0, "Name cannot be empty");
        require(bytes(_symbol).length > 0, "Symbol cannot be empty");

        vaultId = tokenizerId;
        tokenizerId++;

        // Deploy the share token with user as owner and factory as deployer
        shareToken = address(new CollateralBase(_name, _symbol, msg.sender, address(this)));

        // Initialize vault
        TokenizerVault storage vault = tokenizers[vaultId];
        vault.shareToken = shareToken;
        vault.deployer = msg.sender;
        vault.supportedCollaterals = _collaterals;
        vault.batchCounter = 1;
        vault.totalSharesIssued = 0;
        vault.isActive = true;

        // Map share token to vault
        shareTokenToVault[shareToken] = vaultId;

        // Track user's tokenizers
        userTokenizers[msg.sender].push(vaultId);

        emit TokenizerDeployed(vaultId, msg.sender, shareToken, _name, _symbol);

        return (vaultId, shareToken);
    }

    /**
     * @dev Add a new supported collateral token to a vault
     * @param _vaultId The vault ID
     * @param _collateral The collateral token address to add
     */
    function addCollateral(uint256 _vaultId, address _collateral) external {
        TokenizerVault storage vault = tokenizers[_vaultId];
        require(vault.isActive, "Vault not found or inactive");
        require(msg.sender == vault.deployer, "Only deployer can add collaterals");
        require(_collateral != address(0), "Invalid collateral address");

        // Check if already exists
        for (uint256 i = 0; i < vault.supportedCollaterals.length; i++) {
            require(vault.supportedCollaterals[i] != _collateral, "Collateral already supported");
        }

        vault.supportedCollaterals.push(_collateral);
        emit CollateralAdded(_vaultId, _collateral);
    }

    /*//////////////////////////////////////////////////////////////
                    DEPOSIT LOGIC (Called by CRE)
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Mint new shares in a vault (create new batch)
     * Called by CRE via _processReport
     * @param _vaultId Vault ID
     * @param _user User receiving shares
     * @param _collaterals Array of collateral tokens
     * @param _amounts Array of collateral amounts
     * @param _sharesToMint Amount of shares to mint
     */
    function _mintShares(
        uint256 _vaultId,
        address _user,
        address[] memory _collaterals,
        uint256[] memory _amounts,
        uint256 _sharesToMint
    ) internal {
        require(_user != address(0), "Invalid user address");
        require(_collaterals.length == _amounts.length, "Array length mismatch");
        require(_collaterals.length > 0, "Must deposit at least one collateral");
        require(_sharesToMint > 0, "Shares must be greater than 0");

        TokenizerVault storage vault = tokenizers[_vaultId];
        require(vault.isActive, "Vault not found or inactive");

        // Transfer collaterals from user to vault
        for (uint256 i = 0; i < _collaterals.length; ++i) {
            require(_amounts[i] > 0, "Amount must be greater than 0");
            _validateCollateral(vault, _collaterals[i]);
            IERC20(_collaterals[i]).safeTransferFrom(_user, address(this), _amounts[i]);
            vault.collateralBalance[_collaterals[i]] += _amounts[i];
        }

        // Create new batch
        uint256 batchId = vault.batchCounter;
        DepositBatch20 storage batch = vault.depositBatches[batchId];
        batch.collateralTokens = _collaterals;
        batch.collateralAmounts = _amounts;
        batch.sharesMinted = _sharesToMint;
        batch.depositTimestamp = block.timestamp;
        batch.initiatingUser = _user;

        vault.batchCounter++;
        vault.totalSharesIssued += _sharesToMint;

        // Mint share tokens using CollateralBase
        CollateralBase(vault.shareToken).mint(_user, _sharesToMint);

        emit DepositProcessed(_vaultId, _user, batchId, _collaterals, _amounts, _sharesToMint);
    }

    /**
     * @dev Deposit more collateral to existing batch and mint additional shares
     * Called by CRE via _processReport
     * @param _vaultId Vault ID
     * @param _batchId Batch ID to deposit into
     * @param _user User depositing (must be batch initiator)
     * @param _collaterals Array of collateral tokens
     * @param _amounts Array of collateral amounts
     * @param _sharesToMint Amount of new shares to mint
     */
    function _depositToExisting(
        uint256 _vaultId,
        uint256 _batchId,
        address _user,
        address[] memory _collaterals,
        uint256[] memory _amounts,
        uint256 _sharesToMint
    ) internal {
        require(_user != address(0), "Invalid user address");
        require(_sharesToMint > 0, "Shares must be greater than 0");

        TokenizerVault storage vault = tokenizers[_vaultId];
        require(vault.isActive, "Vault not found or inactive");

        DepositBatch20 storage batch = vault.depositBatches[_batchId];
        require(batch.sharesMinted > 0, "Invalid batch ID");
        require(_user == batch.initiatingUser, "Only batch initiator can deposit to existing batch");
        require(_collaterals.length == batch.collateralTokens.length, "Collateral count mismatch");

        // Transfer collaterals and validate ratios
        for (uint256 i = 0; i < _collaterals.length; ++i) {
            require(_amounts[i] > 0, "Amount must be greater than 0");
            require(_collaterals[i] == batch.collateralTokens[i], "Collateral token mismatch");
            
            IERC20(_collaterals[i]).safeTransferFrom(_user, address(this), _amounts[i]);
            vault.collateralBalance[_collaterals[i]] += _amounts[i];
            batch.collateralAmounts[i] += _amounts[i];
        }

        // Update batch and vault state
        batch.sharesMinted += _sharesToMint;
        vault.totalSharesIssued += _sharesToMint;

        // Mint share tokens
        CollateralBase(vault.shareToken).mint(_user, _sharesToMint);

        emit DepositToExistingProcessed(_vaultId, _user, _batchId, _collaterals, _amounts, _sharesToMint);
    }

    /*//////////////////////////////////////////////////////////////
                    WITHDRAWAL LOGIC (Called by CRE)
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Redeem shares and withdraw collateral
     * Called by CRE via _processReport
     * @param _vaultId Vault ID
     * @param _batchId Batch ID to redeem from
     * @param _user User redeeming shares
     * @param _sharesToBurn Amount of shares to burn
     * @param _receiver Address receiving collateral
     */
    function _redeemShares(
        uint256 _vaultId,
        uint256 _batchId,
        address _user,
        uint256 _sharesToBurn,
        address _receiver
    ) internal {
        require(_user != address(0), "Invalid user");
        require(_receiver != address(0), "Invalid receiver");
        require(_sharesToBurn > 0, "Burn amount must be greater than 0");

        TokenizerVault storage vault = tokenizers[_vaultId];
        require(vault.isActive, "Vault not found or inactive");

        DepositBatch20 storage batch = vault.depositBatches[_batchId];
        require(batch.sharesMinted > 0, "Invalid batch ID");

        // Check user has sufficient shares
        require(
            ERC20(vault.shareToken).balanceOf(_user) >= _sharesToBurn,
            "Insufficient share balance"
        );

        // Calculate collateral amounts to return
        uint256 collateralLength = batch.collateralTokens.length;
        address[] memory collaterals = new address[](collateralLength);
        uint256[] memory amounts = new uint256[](collateralLength);

        for (uint256 i = 0; i < collateralLength; ++i) {
            collaterals[i] = batch.collateralTokens[i];
            amounts[i] = (_sharesToBurn * batch.collateralAmounts[i]) / batch.sharesMinted;
            require(amounts[i] > 0, "Redemption amount too small");
        }

        // Burn shares and update batch
        CollateralBase(vault.shareToken).burn(_user, _sharesToBurn);
        batch.sharesMinted -= _sharesToBurn;

        // Transfer collaterals to receiver
        for (uint256 i = 0; i < collateralLength; ++i) {
            IERC20(collaterals[i]).safeTransfer(_receiver, amounts[i]);
            vault.collateralBalance[collaterals[i]] -= amounts[i];
        }

        emit WithdrawalProcessed(_vaultId, _user, _batchId, _sharesToBurn, collaterals, amounts);
    }

    /*//////////////////////////////////////////////////////////////
                    CRE REPORT PROCESSING
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Process reports from Chainlink CRE
     * Report format: abi.encode(uint256 vaultId, uint8 actionCode, bool isDeposit, uint256 batchId, ...)
     * 
     * Action codes:
     * 0 (MINT_SHARES): abi.encode(vaultId, 0, address user, address[] collaterals, uint256[] amounts, uint256 sharesToMint)
     * 1 (DEPOSIT_EXISTING): abi.encode(vaultId, 1, uint256 batchId, address user, address[] collaterals, uint256[] amounts, uint256 sharesToMint)
     * 2 (REDEEM_SHARES): abi.encode(vaultId, 2, uint256 batchId, address user, uint256 sharesToBurn, address receiver)
     */
    /*
    function _processReport(bytes calldata report) internal virtual override {
        require(report.length >= 32, "Report too short");

        (uint256 vaultId, uint8 actionCode) = abi.decode(report[0:64], (uint256, uint8));

        if (actionCode == ACTION_MINT_SHARES) {
            // New batch deposit
            ( , , address user, address[] memory collaterals, uint256[] memory amounts, uint256 sharesToMint) = 
                abi.decode(report, (uint256, uint8, address, address[], uint256[], uint256));
            _validateDeposit(collaterals, amounts, sharesToMint);
            _mintShares(vaultId, user, collaterals, amounts, sharesToMint);
        } else if (actionCode == ACTION_DEPOSIT_EXISTING) {
            // Deposit to existing batch
            ( , , uint256 batchId, address user, address[] memory collaterals, uint256[] memory amounts, uint256 sharesToMint) = 
                abi.decode(report, (uint256, uint8, uint256, address, address[], uint256[], uint256));
            _validateDeposit(collaterals, amounts, sharesToMint);
            _depositToExisting(vaultId, batchId, user, collaterals, amounts, sharesToMint);
        } else if (actionCode == ACTION_REDEEM_SHARES) {
            // Withdrawal
            ( , , uint256 batchId, address user, uint256 sharesToBurn, address receiver) = 
                abi.decode(report, (uint256, uint8, uint256, address, uint256, address));
            _validateWithdrawal(user, batchId, sharesToBurn);
            _redeemShares(vaultId, batchId, user, sharesToBurn, receiver);
        } else {
            revert("Invalid action code");
        }
    }
    */
    /*//////////////////////////////////////////////////////////////
                        HELPER FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Validate that a collateral token is supported in the vault
     */
    function _validateCollateral(TokenizerVault storage vault, address _collateral) internal view {
        for (uint256 i = 0; i < vault.supportedCollaterals.length; i++) {
            if (vault.supportedCollaterals[i] == _collateral) {
                return;
            }
        }
        revert("Unsupported collateral");
    }

    /**
     * @dev Override hook for custom deposit validation
     */
    function _validateDepositERC20(
        address[] memory _collaterals,
        uint256[] memory _amounts,
        uint256 _sharesToMint
    ) internal virtual {}

    /**
     * @dev Override hook for custom withdrawal validation
     */
    function _validateWithdrawalERC20(address _user, uint256 _batchId, uint256 _sharesToBurn)
        internal virtual {}

    /*//////////////////////////////////////////////////////////////
                        ACCOUNTING & VIEWS
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Get all collaterals for a vault
     */
    function getSupportedCollaterals(uint256 _vaultId) 
        external 
        view 
        returns (address[] memory) 
    {
        return tokenizers[_vaultId].supportedCollaterals;
    }

    /**
     * @dev Get collateral balance in a vault
     */
    function getCollateralBalance(uint256 _vaultId, address _token) 
        external 
        view 
        returns (uint256) 
    {
        return tokenizers[_vaultId].collateralBalance[_token];
    }

    /**
     * @dev Get batch details
     */
    function getBatchDetails(uint256 _vaultId, uint256 _batchId)
        external
        view
        returns (
            address[] memory collaterals,
            uint256[] memory amounts,
            uint256 shares,
            uint256 timestamp,
            address depositor
        )
    {
        DepositBatch20 storage batch = tokenizers[_vaultId].depositBatches[_batchId];
        return (
            batch.collateralTokens,
            batch.collateralAmounts,
            batch.sharesMinted,
            batch.depositTimestamp,
            batch.initiatingUser
        );
    }

    /**
     * @dev Preview collateral amounts for redemption
     */
    function previewRedemption(uint256 _vaultId, uint256 _batchId, uint256 _sharesToBurn)
        external
        view
        returns (address[] memory collaterals, uint256[] memory amounts)
    {
        DepositBatch20 storage batch = tokenizers[_vaultId].depositBatches[_batchId];
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

    /**
     * @dev Get user's deployed tokenizers
     */
    function getUserTokenizers(address _user) 
        external 
        view 
        returns (uint256[] memory) 
    {
        return userTokenizers[_user];
    }

    /**
     * @dev Get vault info
     */
    function getVaultInfo(uint256 _vaultId)
        external
        view
        returns (
            address shareToken,
            address deployer,
            uint256 batchCounter,
            uint256 totalSharesIssued,
            bool isActive
        )
    {
        TokenizerVault storage vault = tokenizers[_vaultId];
        return (
            vault.shareToken,
            vault.deployer,
            vault.batchCounter,
            vault.totalSharesIssued,
            vault.isActive
        );
    }
}
