// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ReceiverTemplate} from "./dependencies/Receiver.sol";
import {VaultCore} from "./vaultcore/core.sol";
import {uRWA721} from "./rwa/uRWA721.sol";

contract CSE721 is ReceiverTemplate {
    uint8 public constant actionCodeDepositMint = 1;
    uint8 public constant actionCodeWithdraw = 2;
    uint8 public constant actionCodeOperatorCall = 3; // operator call code for role change of minted RWA tokens
    uint8 public constant actionCodeDocumentAction = 4; // document action code for adding/updating/removing documents of minted RWA tokens

    VaultCore public core;
    uRWA721 public rwaToken;

    struct DepositToken721 {
        address[] collateralTokens;
        uint256[] collateralAmounts;
        uint256 depositTimestamp;
        address initiatingUser;
        bool exists;
    }

    mapping(uint256 => DepositToken721) public depositTokens;
    uint256 public tokenCounter = 1;

    event DepositProcessed(
        address indexed user,
        uint256 indexed tokenId,
        address[] collaterals,
        uint256[] amounts
    );

    event WithdrawalProcessed(
        address indexed user,
        uint256 indexed tokenId,
        address indexed receiver,
        address[] collaterals,
        uint256[] amounts
    );

    constructor(
        address _trustedFwd,
        address _core,
        string memory _name,
        string memory _symbol
    ) ReceiverTemplate(_trustedFwd) {
        core = VaultCore(_core);
        rwaToken = new uRWA721(_name, _symbol, address(this));
    }

    function getDepositToken(uint256 _tokenId) external view returns (DepositToken721 memory) {
        return depositTokens[_tokenId];
    }

    function _mintToken(
        address _user,
        address[] memory _collaterals,
        uint256[] memory _amounts
    ) internal virtual returns (uint256 tokenId) {
        require(_user != address(0), "Invalid user address");
        require(_collaterals.length == _amounts.length, "Array length mismatch");
        require(_collaterals.length > 0, "Must deposit at least one collateral");

        for (uint256 i = 0; i < _collaterals.length; ++i) {
            require(_collaterals[i] != address(0), "Invalid collateral address");
            require(_amounts[i] > 0, "Amount must be greater than 0");
            bool success = core.deposit(_user, _collaterals[i], _amounts[i]);
            if (!success) {
                revert();
            }
        }

        tokenId = tokenCounter;
        DepositToken721 storage deposit = depositTokens[tokenId];
        deposit.collateralTokens = _collaterals;
        deposit.collateralAmounts = _amounts;
        deposit.depositTimestamp = block.timestamp;
        deposit.initiatingUser = _user;
        deposit.exists = true;

        rwaToken.safeMint(_user, tokenId);
        tokenCounter++;

        emit DepositProcessed(_user, tokenId, _collaterals, _amounts);
        return tokenId;
    }

    function _withdrawToken(
        address _user,
        uint256 _tokenId,
        address _receiver
    ) internal virtual returns (address[] memory collaterals, uint256[] memory amounts) {
        require(_user != address(0), "Invalid user");
        require(_receiver != address(0), "Invalid receiver");
        require(depositTokens[_tokenId].exists, "Invalid tokenId");
        require(rwaToken.ownerOf(_tokenId) == _user, "Insufficient share ownership");

        DepositToken721 storage deposit = depositTokens[_tokenId];
        collaterals = deposit.collateralTokens;
        amounts = deposit.collateralAmounts;

        rwaToken.burn(_tokenId);
        delete depositTokens[_tokenId];

        for (uint256 i = 0; i < collaterals.length; ++i) {
            if (amounts[i] > 0) {
                bool success = core.withdraw(_receiver, collaterals[i], amounts[i]);
                if (!success) {
                    revert();
                }
            }
        }

        emit WithdrawalProcessed(_user, _tokenId, _receiver, collaterals, amounts);
        return (collaterals, amounts);
    }

    function _processReport(bytes calldata report) internal virtual override {
        require(report.length >= 32);
        uint8 action = abi.decode(report[0:32], (uint8));

        if (action == actionCodeDepositMint) {
            (, address user, address[] memory collaterals, uint256[] memory amounts) =
                abi.decode(report, (uint8, address, address[], uint256[]));
            _mintToken(user, collaterals, amounts);
        } else if (action == actionCodeWithdraw) {
            (, address user, uint256 tokenId, address receiver) =
                abi.decode(report, (uint8, address, uint256, address));
            _withdrawToken(user, tokenId, receiver);
        } else if (action == actionCodeOperatorCall) {
            (, address shareToken, address operator, bytes32 role) =
                abi.decode(report, (uint8, address, address, bytes32));
            require(shareToken == address(rwaToken), "Invalid share token");
            require(operator != address(0), "Invalid operator");
            require(role != keccak256("DEFAULT_ADMIN_ROLE"), "Cannot transfer admin role");
            require(role != keccak256("MINTER_ROLE"), "Cannot transfer minter role");
            require(role != keccak256("BURNER_ROLE"), "Cannot transfer burner role");
            uRWA721(shareToken).grantRole(role, operator);
        } else if (action == actionCodeDocumentAction) {
            revert("Document actions not supported for ERC721 shares");
        }
    }
}
