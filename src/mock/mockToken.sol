// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

contract CollateralBase is ERC20 , Ownable {
    
    error NotDeployer();

    constructor(
        string memory name,
        string memory symbol,
        )
        ERC20(name,symbol)
        Ownable(msg.sender)
        {
            
        }
}