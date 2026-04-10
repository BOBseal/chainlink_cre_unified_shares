// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {ReceiverTemplate} from "./dependencies/Receiver.sol";
import {VaultCore} from "./vaultcore/core.sol";
import {uRWA20Metadata} from "./rwa/modules/erc20/uRWA20Metadata.sol";

contract CSE20 is ReceiverTemplate {
    uint8 public constant actionCodeDeploy = 1;
    uint8 public constant actionCodeDeposit = 2;
    uint8 public constant actionCodeWithdraw = 3;
    uint8 public constant actionCodeOperatorCall = 4; // operator call code for role change of minted RWA tokens
    uint8 public constant actionCodeDocumentAction = 5; // document action code for adding/updating/removing documents of minted RWA tokens

    VaultCore public core;
    
    struct TokenizerVault {
        address shareToken;              // CollateralBase ERC20 token
        address deployer;                // User who deployed this tokenizer (only one can mint/deposit)
        address[] supportedCollaterals;  // Array of accepted collateral tokens
        mapping(address => uint256) collateralBalance;  // Current held per collateral
        uint256 totalSharesIssued;       // Total shares ever issued
        bool isActive;                   // Whether this vault is active
    }
    
    /// @dev Maps tokenizer vault ID to vault data
    mapping(uint256 => TokenizerVault) public tokenizers;
    uint256 public tokenizerId = 1;

    /// @dev Maps share token address to vault ID for quick lookup
    mapping(address => uint256) public shareTokenToVault;

    /// @dev Maps user address to their deployed tokenizers
    mapping(address => uint256[]) public userTokenizers;

    event TokenizerDeployed(
        uint256 indexed vaultId,
        address indexed deployer,
        address indexed shareToken,
        string name,
        string symbol
    );

    event CollateralAdded(
        uint256 indexed vaultId,
        address[] collaterals
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

    constructor(
        address _trustedFwd,
        address _core
    )
    ReceiverTemplate(_trustedFwd)
    {
        core = VaultCore(_core);
    }

    function getCollateralBalance(uint256 _vaultId, address _token)
        external
        view
        returns (uint256)
    {
        return tokenizers[_vaultId].collateralBalance[_token];
    }

    function getUserTokenizerIds(address _user)
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
            address[] memory collaterals,
            uint256 totalSharesIssued,
            bool isActive
        )
    {
        TokenizerVault storage vault = tokenizers[_vaultId];
        return (
            vault.shareToken,
            vault.deployer,
            vault.supportedCollaterals,
            vault.totalSharesIssued,
            vault.isActive
        );
    }

    function setCollaterals(uint256 _vaultId, address[] memory _collaterals) public {
        TokenizerVault storage vault = tokenizers[_vaultId];
        require(vault.isActive, "Vault not found or inactive");
        require(msg.sender == vault.deployer, "Only deployer can add collaterals");
        _setCollaterals(_vaultId, _collaterals);    
        emit CollateralAdded(_vaultId, _collaterals);
    }

    function _setCollaterals(uint256 _vaultId, address[] memory _collaterals) internal {
        TokenizerVault storage vault = tokenizers[_vaultId];
        vault.supportedCollaterals = _collaterals;
    }

    function _deployTokenizer(
        string memory _name,
        string memory _symbol,
        address[] memory _collaterals,
        address _deployer
    ) internal returns(uint256 vaultId, address shareToken)
    {
        require(_collaterals.length > 0, "Must add at least one collateral");
        require(bytes(_name).length > 0, "Name cannot be empty");
        require(bytes(_symbol).length > 0, "Symbol cannot be empty");

        vaultId = tokenizerId;
        tokenizerId++;

        // Deploy the share token with user as owner and factory as deployer
        shareToken = address(new uRWA20Metadata(_name, _symbol, address(this)));

        // Initialize vault
        TokenizerVault storage vault = tokenizers[vaultId];
        vault.shareToken = shareToken;
        vault.deployer = _deployer;
        vault.supportedCollaterals = _collaterals;
        vault.totalSharesIssued = 0;
        vault.isActive = true;

        // Map share token to vault
        shareTokenToVault[shareToken] = vaultId;

        // Track user's tokenizers
        userTokenizers[_deployer].push(vaultId);

        emit TokenizerDeployed(vaultId, _deployer, shareToken, _name, _symbol);
        return (vaultId , shareToken);
    }

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
            require(_collaterals[i] != address(0));
            if(IERC20(_collaterals[i]).balanceOf(_user) < _amounts[i]){
                revert();
            }
            _validateCollateral(vault, _collaterals[i]);
            bool success = core.deposit(_user, _collaterals[i], _amounts[i]);
            if (!success) {
                revert();
            }
            vault.collateralBalance[_collaterals[i]] += _amounts[i];
        }

        vault.totalSharesIssued += _sharesToMint;

        // Mint share tokens using CollateralBase
        uRWA20Metadata(vault.shareToken).mint(_user, _sharesToMint);

        emit DepositProcessed(_vaultId, _user, _collaterals, _amounts, _sharesToMint);
    }

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
        vault.totalSharesIssued -= _sharesToBurn;
        uRWA20Metadata(vault.shareToken).burnFrom(_user, _sharesToBurn);

        // Transfer collaterals to receiver
        for (uint256 i = 0; i < collateralLength; ++i) {
            if (amounts[i] > 0) {
                vault.collateralBalance[collaterals[i]] -= amounts[i];
                bool success = core.withdraw(_receiver,collaterals[i],amounts[i]);
                if (!success) {
                    revert();
                }
            }
        }

        emit WithdrawalProcessed(_vaultId, _user, _sharesToBurn, collaterals, amounts);
    }

    function _processReport(bytes calldata report) internal virtual override {
        require(report.length>= 32);
        uint8 action = abi.decode(report[0:32], (uint8));
        if(action == actionCodeDeploy){
            (,string memory name , string memory symbol , address[] memory collaterals, address _deployer) =
            abi.decode (report, (uint8, string, string, address[], address));
            (uint _id,) = _deployTokenizer(name, symbol, collaterals, _deployer);
            _setCollaterals(_id, collaterals);
        }
        if(action == actionCodeDeposit){
            (,uint256 vaultId , address user, address[] memory collaterals, uint256[] memory amounts, uint256 sharesToMint) =
            abi.decode (report, (uint8, uint256, address, address[], uint256[], uint256));
            _depositAndMintShares(vaultId, user, collaterals, amounts, sharesToMint);
        }
        if(action == actionCodeWithdraw){
            (,uint256 vaultId , address user, uint256 sharesToBurn, address receiver) =
            abi.decode (report, (uint8, uint256, address, uint256, address));
            _redeemShares(vaultId, user, sharesToBurn, receiver);
        }
        if(action == actionCodeOperatorCall){
            (,address shareToken, address operator, bytes32 role) =
            abi.decode (report, (uint8, address, address, bytes32));
            require(shareTokenToVault[shareToken] != 0, "Invalid share token");
            require(operator != address(0), "Invalid operator");
            require(role != keccak256("DEFAULT_ADMIN_ROLE"),"Cannot transfer admin role");
            require(role != keccak256("MINTER_ROLE"),"Cannot transfer minter role");
            require(role != keccak256("BURNER_ROLE"),"Cannot transfer burner role");
            uRWA20Metadata(shareToken).grantRole(role, operator);
        }
        if(action == actionCodeDocumentAction){
            (,address shareToken, bytes32 docName, string memory docUri, bytes32 docHash, bool isRemoval) =
            abi.decode (report, (uint8, address, bytes32, string, bytes32, bool));
            require(shareTokenToVault[shareToken] != 0, "Invalid share token");
            if(isRemoval){
                uRWA20Metadata(shareToken).removeDocument(docName);
            } else {
                uRWA20Metadata(shareToken).setDocument(docName, docUri, docHash);
            }
        }
    }

    function _validateCollateral(TokenizerVault storage vault, address _collateral) internal view {
        for (uint256 i = 0; i < vault.supportedCollaterals.length; i++) {
            if (vault.supportedCollaterals[i] == _collateral) {
                return;
            }
        }
        revert("Unsupported collateral");
    }

}
