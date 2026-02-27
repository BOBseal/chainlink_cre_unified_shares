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
    uint8 constant ACTION_MINT_SHARES = 3;
    uint8 constant ACTION_DEPOSIT_EXISTING = 4;
    uint8 constant ACTION_REDEEM_SHARES = 5;

    constructor(
        string memory _uri,
        address _trustedForwarder
    )
    Alternative1155Vault(_uri)
    ReceiverTemplate(_trustedForwarder)
    {

    }


    function _processReport(bytes calldata report) internal virtual override {
        
    }

}