// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {CollateralBase} from "./CollateralBase.sol";

/**
 * @title TokenizerFactory
 * @dev Factory for deploying collateralized ERC20 share tokens with CRE-controlled operations.
 * 
 * Each deployed share token:
 * - Belongs to a single deployer (creator)
 * - Has custom collateral pools (ERC20 tokens accepted as collateral)
 * - Tracks total collateral composition (no batches)
 * - Only deployer can mint shares or deposit collateral
 * - CRE-controlled operations via action codes (uint8)
 * 
 * Action Codes:
 * - 0 (MINT_SHARES): Mint shares (deployer only)
 * - 1 (DEPOSIT_COLLATERAL): Deposit collateral and mint shares (deployer only)
 * - 2 (REDEEM_SHARES): Burn shares and withdraw proportional collateral
 */
contract TokenizerFactory {
    using SafeERC20 for IERC20;
    using Math for uint256;

    /*//////////////////////////////////////////////////////////////
                            TYPES & STATE
    //////////////////////////////////////////////////////////////*/

    /// @dev Represents a deployed tokenizer vault instance
    struct TokenizerVault {
        address shareToken;              // CollateralBase ERC20 token
        address deployer;                // User who deployed this tokenizer (only one can mint/deposit)
        address[] supportedCollaterals;  // Array of accepted collateral tokens
        mapping(address => uint256) collateralBalance;  // Current held per collateral
        mapping(address => uint256) collateralDeposited;  // Cumulative amounts deposited per collateral
        uint256 totalSharesIssued;       // Total shares ever issued
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
        address indexed deployer,
        address[] collaterals,
        uint256[] amounts,
        uint256 sharesIssued
    );

    event WithdrawalProcessed(
        uint256 indexed vaultId,
        address indexed user,
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
                    DEPOSIT LOGIC (CRE-controlled, Deployer Only)
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Deposit collateral and mint shares (deployer only)
     * Called by CRE via processReport
     * @param _vaultId Vault ID
     * @param _user User receiving shares (must be vault deployer)
     * @param _collaterals Array of collateral tokens
     * @param _amounts Array of collateral amounts
     * @param _sharesToMint Amount of shares to mint
     */
    function _depositAndMintShares(
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
        require(_user == vault.deployer, "Only vault deployer can mint shares");

        // Transfer collaterals from user to vault
        for (uint256 i = 0; i < _collaterals.length; ++i) {
            require(_amounts[i] > 0, "Amount must be greater than 0");
            _validateCollateral(vault, _collaterals[i]);
            IERC20(_collaterals[i]).safeTransferFrom(_user, address(this), _amounts[i]);
            vault.collateralBalance[_collaterals[i]] += _amounts[i];
            vault.collateralDeposited[_collaterals[i]] += _amounts[i];
        }

        vault.totalSharesIssued += _sharesToMint;

        // Mint share tokens using CollateralBase
        CollateralBase(vault.shareToken).mint(_user, _sharesToMint);

        emit DepositProcessed(_vaultId, _user, _collaterals, _amounts, _sharesToMint);
    }

    /*//////////////////////////////////////////////////////////////
                    WITHDRAWAL LOGIC (CRE-controlled)
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Redeem shares and withdraw collateral proportionally
     * Called by CRE via processReport
     * @param _vaultId Vault ID
     * @param _user User redeeming shares
     * @param _sharesToBurn Amount of shares to burn
     * @param _receiver Address receiving collateral
     */
    function _redeemShares(
        uint256 _vaultId,
        address _user,
        uint256 _sharesToBurn,
        address _receiver
    ) internal {
        require(_user != address(0), "Invalid user");
        require(_receiver != address(0), "Invalid receiver");
        require(_sharesToBurn > 0, "Burn amount must be greater than 0");

        TokenizerVault storage vault = tokenizers[_vaultId];
        require(vault.isActive, "Vault not found or inactive");
        require(vault.totalSharesIssued > 0, "No shares issued");

        // Check user has sufficient shares
        require(
            ERC20(vault.shareToken).balanceOf(_user) >= _sharesToBurn,
            "Insufficient share balance"
        );

        // Calculate proportional collateral amounts to return
        uint256 collateralLength = vault.supportedCollaterals.length;
        address[] memory collaterals = new address[](collateralLength);
        uint256[] memory amounts = new uint256[](collateralLength);

        for (uint256 i = 0; i < collateralLength; ++i) {
            collaterals[i] = vault.supportedCollaterals[i];
            amounts[i] = (_sharesToBurn * vault.collateralBalance[collaterals[i]]) / vault.totalSharesIssued;
        }

        // Burn shares
        CollateralBase(vault.shareToken).burn(_user, _sharesToBurn);
        vault.totalSharesIssued -= _sharesToBurn;

        // Transfer collaterals to receiver
        for (uint256 i = 0; i < collateralLength; ++i) {
            if (amounts[i] > 0) {
                IERC20(collaterals[i]).safeTransfer(_receiver, amounts[i]);
                vault.collateralBalance[collaterals[i]] -= amounts[i];
            }
        }

        emit WithdrawalProcessed(_vaultId, _user, _sharesToBurn, collaterals, amounts);
    }

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

    /*//////////////////////////////////////////////////////////////
                        VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function getSupportedCollaterals(uint256 _vaultId)
        external
        view
        returns (address[] memory)
    {
        return tokenizers[_vaultId].supportedCollaterals;
    }

    function getCollateralBalance(uint256 _vaultId, address _token)
        external
        view
        returns (uint256)
    {
        return tokenizers[_vaultId].collateralBalance[_token];
    }

    function previewRedemption(uint256 _vaultId, uint256 _sharesToBurn)
        external
        view
        returns (address[] memory collaterals, uint256[] memory amounts)
    {
        TokenizerVault storage vault = tokenizers[_vaultId];
        require(vault.totalSharesIssued > 0, "No shares issued");

        uint256 collateralLength = vault.supportedCollaterals.length;
        collaterals = new address[](collateralLength);
        amounts = new uint256[](collateralLength);

        for (uint256 i = 0; i < collateralLength; i++) {
            collaterals[i] = vault.supportedCollaterals[i];
            amounts[i] = (_sharesToBurn * vault.collateralBalance[collaterals[i]]) / vault.totalSharesIssued;
        }

        return (collaterals, amounts);
    }

    function getUserTokenizers(address _user)
        external
        view
        returns (uint256[] memory)
    {
        return userTokenizers[_user];
    }

    function getVaultInfo(uint256 _vaultId)
        external
        view
        returns (
            address shareToken,
            address deployer,
            uint256 totalSharesIssued,
            bool isActive
        )
    {
        TokenizerVault storage vault = tokenizers[_vaultId];
        return (
            vault.shareToken,
            vault.deployer,
            vault.totalSharesIssued,
            vault.isActive
        );
    }
}
