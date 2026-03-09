// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {CollateralBase} from "../src/mock/mockErc20.sol";

/**
 * @title DeployMockErc20
 * @notice Deployment script for Mock ERC20 tokens (mockWETH, mockWBTC, mockLINK)
 * @dev Deploys three mock ERC20 tokens with specified names and symbols
 *
 * Usage:
 *   forge script script/DeployMockErc20.s.sol:DeployMockErc20 --rpc-url $RPC_URL --broadcast -vvv
 *
 *   With private key:
 *   forge script script/DeployMockErc20.s.sol:DeployMockErc20 \
 *     --rpc-url $RPC_URL \
 *     --private-key $PRIVATE_KEY \
 *     --broadcast \
 *     -vvv
 *
 *   For Ethereum Sepolia (example):
 *   forge script script/DeployMockErc20.s.sol:DeployMockErc20 \
 *     --rpc-url https://sepolia.infura.io/v3/YOUR_INFURA_KEY \
 *     --private-key YOUR_PRIVATE_KEY \
 *     --broadcast \
 *     -vvv
 */
contract DeployMockErc20 is Script {
    
    // ============================================================================
    // State Variables
    // ============================================================================
    
    CollateralBase public mockWETH;
    CollateralBase public mockWBTC;
    CollateralBase public mockLINK;
    
    address public deployerAddress;
    
    // ============================================================================
    // Deployment Function
    // ============================================================================
    
    function run() external {
        // Get deployer address
        deployerAddress = msg.sender;
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        console.log("=====================================");
        console.log("Deploying Mock ERC20 Tokens");
        console.log("=====================================");
        console.log("Deployer Address:", deployerAddress);
        
        // Start broadcasting transactions
        vm.startBroadcast(deployerKey);
        
        // Deploy mockWETH
        mockWETH = new CollateralBase("mockWETH", "mWETH");
        console.log("mockWETH deployed at:", address(mockWETH));
        
        // Deploy mockWBTC
        mockWBTC = new CollateralBase("mockWBTC", "mWBTC");
        console.log("mockWBTC deployed at:", address(mockWBTC));
        
        // Deploy mockLINK
        mockLINK = new CollateralBase("mockLINK", "mLINK");
        console.log("mockLINK deployed at:", address(mockLINK));
        
        vm.stopBroadcast();
        
        // ============================================================================
        // Summary
        // ============================================================================
        
        console.log("");
        console.log("=====================================");
        console.log("Deployment Complete!");
        console.log("=====================================");
        console.log("Mock ERC20 Tokens Deployed:");
        console.log("  mockWETH (mWETH):", address(mockWETH));
        console.log("  mockWBTC (mWBTC):", address(mockWBTC));
        console.log("  mockLINK (mLINK):", address(mockLINK));
        console.log("");
        console.log("Token Details:");
        console.log("  Initial Supply per Token: 1,000,000,000");
        console.log("  Decimals: 18");
        console.log("  Owner: ", deployerAddress);
        console.log("=====================================");
    }
}
