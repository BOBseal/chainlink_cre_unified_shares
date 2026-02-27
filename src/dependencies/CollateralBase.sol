// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

contract CollateralBase is ERC20 , Ownable {
    address public immutable deployer;
    
    error NotDeployer();

    constructor(
        string memory name,
        string memory symbol,
        address owner,
        address _deployer
        )
        ERC20(name,symbol)
        Ownable(owner)
        {
            deployer = _deployer;
        }
    modifier onlyDeployer(){
        require(msg.sender == deployer,NotDeployer());
        _;
    }
    
    function getDeployer() public view returns(address){
        return deployer;
    }

    function mint(address to , uint256 amount) public onlyDeployer {
        _mint(to,amount);
    }

    function burn (address from , uint256 amount) public onlyDeployer{
        _burn(from , amount);
    }
}