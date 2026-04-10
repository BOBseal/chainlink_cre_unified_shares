// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
//import {ReceiverTemplate} from "../dependencies/Receiver.sol";

/// External Balance Manager for Multiple Vaults to store and manage their assets through a single contract
/// Aimed to Reduce Contract Size and Costs of Deployment and Upgardes for Vaults.
/// Able to be used by CRE for utilisation of Protocol Owned Assets for Yield.
contract VaultCore is Ownable{
    using SafeERC20 for IERC20;

    mapping(address => bool) public allowed;
    
    event Deposited(address indexed vault,address indexed from ,address indexed token, uint amount);
    event Withdrawn(address indexed vault,address indexed from ,address indexed token, uint amount);

    error notAllowed();

    constructor() 
    Ownable(msg.sender)
    {}

    modifier onlyAllowed(){
        require(allowed[msg.sender], notAllowed());
        _;
    }

    function setAllowed (address _vault , bool _status) external onlyOwner{
        allowed[_vault] = _status;
    }

    function deposit(address _from,address _token, uint _amount) external onlyAllowed returns(bool) {
        IERC20(_token).safeTransferFrom(_from, address(this), _amount);
        emit Deposited(msg.sender,_from, _token, _amount);
        return true;
    }

    function withdraw (address _to , address _token , uint _amount) external onlyAllowed returns(bool) {
        IERC20(_token).safeTransfer(_to, _amount);
        emit Withdrawn(msg.sender , _to , _token , _amount);
        return true;
    }
}