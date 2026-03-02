pragma solidity ^0.8.0;

import {Alternative1155Vault} from "./dependencies/alternative1155.sol";
import "./dependencies/TokenizerFactory.sol";
import {ReceiverTemplate} from "./dependencies/Receiver.sol";

contract Vault is Alternative1155Vault,TokenizerFactory,ReceiverTemplate{

    // Action codes 20
    uint8 constant ACTION_MINT_SHARES_ERC20 = 0;
    uint8 constant ACTION_DEPOSIT_EXISTING_ERC20 = 1;
    uint8 constant ACTION_REDEEM_SHARES_ERC20 = 2;
    // Action codes 1155
    uint8 constant ACTION_MINT_SHARES_1155 = 3;
    uint8 constant ACTION_DEPOSIT_EXISTING_1155 = 4;
    uint8 constant ACTION_REDEEM_SHARES_1155 = 5;

    constructor(
        string memory _uri,
        address _trustedForwarder
    )
    Alternative1155Vault(_uri)
    ReceiverTemplate(_trustedForwarder)
    {

    }


    function _processReport(bytes calldata report) internal virtual override {
        require(report.length >= 32, "Report too short");
        (uint8 _actionCode) = abi.decode(report[0:32], (uint8));
        
        if(_actionCode == ACTION_MINT_SHARES_ERC20){
            // report layout: [vaultId, actionCode, user, collaterals[], amounts[], sharesToMint]
            ( ,uint256 vaultId, address user, address[] memory collaterals, uint256[] memory amounts, uint256 sharesToMint) = 
                abi.decode(report, ( uint8, uint256, address, address[], uint256[], uint256));
            // TokenizerFactory expects the deployer as `user` and performs the collateral transfer
            _depositAndMintShares(vaultId, user, collaterals, amounts, sharesToMint);
        }

        if(_actionCode == ACTION_REDEEM_SHARES_ERC20){
            // new factory signature no longer uses batchId; layout: [vaultId, actionCode, user, sharesToBurn, receiver]
            ( , uint256 vaultId, address user, uint256 sharesToBurn, address receiver) = 
                abi.decode(report, ( uint8,uint256, address, uint256, address));
            _redeemShares(vaultId, user, sharesToBurn, receiver);
        }

        if(_actionCode == ACTION_MINT_SHARES_1155){
            ( , , address user, address[] memory collaterals, uint256[] memory amounts, uint256 sharesToMint) = 
            abi.decode(report, (uint8, uint256, address, address[], uint256[], uint256));
            _validateDepositERC1155(collaterals, amounts, sharesToMint);
            _depositCollaterals(user, collaterals, amounts, sharesToMint);
        }

        if(_actionCode == ACTION_DEPOSIT_EXISTING_1155){
            ( ,uint tokenId , address user, address[] memory collaterals, uint256[] memory amounts, uint256 sharesToMint) = 
            abi.decode(report, (uint8, uint256, address, address[], uint256[], uint256));
            _validateDepositERC1155(collaterals, amounts, sharesToMint);
            _depositToExistingBatch(user, tokenId, collaterals, amounts, sharesToMint);
        }

        if(_actionCode == ACTION_REDEEM_SHARES_1155){
            ( , uint tokenId, address user, uint256 sharesToBurn, address receiver) = 
            abi.decode(report, (uint8, uint256, address, uint256, address));
            _validateWithdrawalERC1155(user, tokenId, sharesToBurn);
            _withdrawFromTokenId(user, tokenId, sharesToBurn, receiver);
        }
    } 

}