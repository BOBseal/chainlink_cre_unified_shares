// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC1155} from "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import {ERC1155Holder} from "@openzeppelin/contracts/token/ERC1155/utils/ERC1155Holder.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {ReceiverTemplate} from "./dependencies/Receiver.sol";
import {VaultCore} from "./vaultcore/core.sol";
import {uRWA1155Metadata} from "./rwa/modules/erc1155/uRWA1155Metadata.sol";

contract CSE1155 is ReceiverTemplate , ERC1155Holder{

    uint8 public constant actionCodeDepositMint = 1;
    uint8 public constant actionCodeDepositExisting = 2;
    uint8 public constant actionCodeWithdraw = 3;
    uint8 public constant actionCodeOperatorCall = 4; // operator call code for role change of minted RWA tokens
    uint8 public constant actionCodeDocumentAction = 5; // document action code for adding/updating/removing documents of minted RWA tokens
    
    VaultCore public core;
    uRWA1155Metadata public rwaToken;

    struct DepositBatch1155 {
        address[] collateralTokens;      // List of collateral ERC20 token addresses
        uint256[] collateralAmounts;     // Original amounts deposited
        uint256 sharesMinted;            // Total shares issued for this tokenId
        uint256 depositTimestamp;        // When deposit was made
        address initiatingUser;          // Original depositor
    }
    
    /// @dev Stores deposit batches by tokenId (share id)
    mapping(uint256 => DepositBatch1155) internal depositBatches;
    uint256 public tokenCounter = 1;

    /// @dev Total shares ever issued across all tokenIds
    uint256 public totalSharesIssued = 0;

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

    constructor(
        address _trustedFwd,
        address _core ,
        string memory _uri
        )
    ReceiverTemplate(_trustedFwd)
    {
        core = VaultCore(_core);
        rwaToken = new uRWA1155Metadata(_uri, address(this));
    }

    function getBatch (uint256 tokenId) external view returns (DepositBatch1155 memory) {
        return depositBatches[tokenId];
    }

    /**
     * @dev Process deposit of multiple ERC20 collaterals and mint ERC1155 shares
     * @param _user recipient of minted share
     * @param _collaterals array of ERC20 token addresses
     * @param _amounts array of amounts per collateral
     * @param _sharesToMint amount of share tokens to mint (ERC1155 amount)
     * @return tokenId minted
     */
    function _mintBatch(
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
            bool success = core.deposit(_user, _collaterals[i], _amounts[i]);
            if (!success) {
                revert();
            }
        }

        tokenId = tokenCounter;
        DepositBatch1155 storage batch = depositBatches[tokenId];
        batch.collateralTokens = _collaterals;
        batch.collateralAmounts = _amounts;
        batch.sharesMinted = _sharesToMint;
        batch.depositTimestamp = block.timestamp;
        batch.initiatingUser = _user;

        // Mint ERC1155 share tokens for this deposit batch (external share contract)
        rwaToken.mint(_user, tokenId, _sharesToMint);
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

        DepositBatch1155 storage batch = depositBatches[_tokenId];

        require(batch.sharesMinted > 0, "Invalid tokenId - batch does not exist");
        require(_user == batch.initiatingUser, "Only batch initiator can deposit to existing batch");
        require(_collaterals.length == _amounts.length, "Array length mismatch");
        require(_collaterals.length == batch.collateralTokens.length, "Array length mismatch with batch collaterals");

        uint256 collateralLength = _collaterals.length;

        // Transfer ERC20 collaterals from user to vault
        for (uint256 i = 0; i < collateralLength; ++i) {
            require(_amounts[i] > 0, "Amount must be greater than 0");
            require(_collaterals[i] == batch.collateralTokens[i], "Collateral token mismatch");
            bool success = core.deposit(_user, _collaterals[i], _amounts[i]);
            if (!success) {
                revert();
            }
            // Update batch with new accumulated amounts
            batch.collateralAmounts[i] += _amounts[i];
        }

        // Update batch shares and emit event
        batch.sharesMinted += _sharesToMint;
        totalSharesIssued += _sharesToMint;

        // Mint new ERC1155 share tokens
        rwaToken.mint(_user, _tokenId, _sharesToMint);

        emit DepositProcessed(_user, _tokenId, _collaterals, _amounts, _sharesToMint);
    }

    function _withdrawFromBatch(
        address _user,
        uint256 _tokenId,
        uint256 _sharesToBurn,
        address _receiver
    ) internal virtual returns (address[] memory collaterals, uint256[] memory amounts) {
        require(_user != address(0), "Invalid user");
        require(_receiver != address(0), "Invalid receiver");
        require(_sharesToBurn > 0, "Burn amount must be greater than 0");
        require(rwaToken.balanceOf(_user, _tokenId) >= _sharesToBurn, "Insufficient share balance");

        DepositBatch1155 storage batch = depositBatches[_tokenId];
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
        rwaToken.burnFrom(_user, _tokenId, _sharesToBurn);

        // Deduct shares from batch
        batch.sharesMinted -= _sharesToBurn;

        // Transfer ERC20 collaterals to receiver
        for (uint256 i = 0; i < collateralLength; ++i) {
            // Update batch with new accumulated amounts
            batch.collateralAmounts[i] -= amounts[i];
            bool success = core.withdraw(_receiver, batch.collateralTokens[i], amounts[i]);
            if (!success) {
                revert();
            }
        }

        emit WithdrawalProcessed(_user, _tokenId, _sharesToBurn, collaterals, amounts);
        return (collaterals, amounts);
    }

    function _processReport(bytes calldata report) internal virtual override {
        require(report.length>= 32);
        uint8 action = abi.decode(report[0:32], (uint8));

        if (action == actionCodeDepositMint) {
            (, address user, address[] memory collaterals, uint256[] memory amounts, uint256 sharesToMint) =
                abi.decode(report, (uint8, address, address[], uint256[], uint256));
            _mintBatch(user, collaterals, amounts, sharesToMint);
        } else if (action == actionCodeDepositExisting) {
            (, address user, uint256 tokenId, address[] memory collaterals, uint256[] memory amounts, uint256 sharesToMint) =
                abi.decode(report, (uint8, address, uint256, address[], uint256[], uint256));
            _depositToExistingBatch(user, tokenId, collaterals, amounts, sharesToMint);
        } else if (action == actionCodeWithdraw) {
            (, address user, uint256 tokenId, uint256 sharesToBurn, address receiver) =
                abi.decode(report, (uint8, address, uint256, uint256, address));
            _withdrawFromBatch(user, tokenId, sharesToBurn, receiver);
        } else if (action == actionCodeOperatorCall) {
            (, address shareToken, address operator, bytes32 role) =
                abi.decode(report, (uint8, address, address, bytes32));
            require(shareToken == address(rwaToken), "Invalid share token");
            require(operator != address(0), "Invalid operator");
            require(role != keccak256("DEFAULT_ADMIN_ROLE"), "Cannot transfer admin role");
            require(role != keccak256("MINTER_ROLE"), "Cannot transfer minter role");
            require(role != keccak256("BURNER_ROLE"), "Cannot transfer burner role");
            uRWA1155Metadata(shareToken).grantRole(role, operator);
        } else if (action == actionCodeDocumentAction) {
            (, address shareToken, uint256 tokenId, bytes32 docName, string memory docUri, bytes32 docHash, bool isRemoval) =
                abi.decode(report, (uint8, address, uint256, bytes32, string, bytes32, bool));
            require(shareToken == address(rwaToken), "Invalid share token");
            if (isRemoval) {
                uRWA1155Metadata(shareToken).removeDocument(docName, tokenId);
            } else {
                uRWA1155Metadata(shareToken).setDocument(tokenId, docName, docUri, docHash);
            }
        }
    }

    function supportsInterface(bytes4 interfaceId) public view virtual override(ERC1155Holder , ReceiverTemplate) returns (bool) {
        return super.supportsInterface(interfaceId);
    }
}
