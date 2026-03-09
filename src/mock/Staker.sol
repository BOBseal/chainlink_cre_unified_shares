// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract MockStake is Ownable {;

    // token address to mockAPY
    mapping(address=> uint) public YieldRates; // 1 == 1% APY
    mapping(address => bool) public isSupported;
    
    constructor() 
    Ownable(msg.sender)
    {}

    function setYieldRates(address[] tokens , uint[] rates) public onlyOwner{
        require(tokens.length == rates.length , "Length mismatch");
        for(uint i = 0 ; i < tokens.length ; i++){
            YieldRates[tokens[i]] = rates[i];
            isSupported[tokens[i]] = true;
        }
    }
}