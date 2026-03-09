// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title ApproveMockErc20
 * @notice Approval script for Mock ERC20 tokens to be spent by Vault contract
 * @dev Approves the Vault contract to transfer mock ERC20 tokens from the deployer's wallet
 *
 * Usage:
 *   forge script script/ApproveMockErc20.s.sol:ApproveMockErc20 \
 *     --rpc-url $RPC_URL \
 *     --private-key $PRIVATE_KEY \
 *     --broadcast -vvv
 *
 *   For Ethereum Sepolia (example):
 *   forge script script/ApproveMockErc20.s.sol:ApproveMockErc20 \
 *     --rpc-url https://eth-sepolia.g.alchemy.com/v2/u9QAFjJ6qbQ8MEEg6loku \
 *     --private-key YOUR_PRIVATE_KEY \
 *     --broadcast -vvv
 */
contract ApproveMockErc20 is Script {
    
    // ============================================================================
    // Token Addresses (Sepolia Deployment)
    // ============================================================================
    address constant MOCK_WETH = 0x686f670889750c611D2BFff89951b687ed5f92A6;
    address constant MOCK_WBTC = 0xB9990a0E50B7c355Ade30c5470fb50dE106385e9;
    address constant MOCK_LINK = 0xDe9660bf486Bcb9921A4a6C87443B45D52639849;
    
    // ============================================================================
    // Vault Address
    // ============================================================================
    address constant VAULT = 0xd6513a2ee1297a59B857cc3c79523b4C64e4EfCa;
    
    // ============================================================================
    // Approval Amount (max uint256 for unlimited approvals)
    // ============================================================================
    uint256 constant APPROVAL_AMOUNT = type(uint256).max;
    
    // ============================================================================
    // Run Function
    // ============================================================================
    
    function run() external {
        address deployer = msg.sender;
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        console.log("=====================================");
        console.log("Approving Mock ERC20 Tokens");
        console.log("=====================================");
        console.log("Deployer Address:", deployer);
        console.log("Vault Address:", VAULT);
        console.log("Approval Amount: Unlimited (max uint256)");
        console.log("");
        
        vm.startBroadcast(deployerKey);
        
        // Approve mockWETH
        console.log("Approving mockWETH...");
        require(
            IERC20(MOCK_WETH).approve(VAULT, APPROVAL_AMOUNT),
            "mockWETH approval failed"
        );
        console.log("[SUCCESS] mockWETH approved");
        
        // Approve mockWBTC
        console.log("Approving mockWBTC...");
        require(
            IERC20(MOCK_WBTC).approve(VAULT, APPROVAL_AMOUNT),
            "mockWBTC approval failed"
        );
        console.log("[SUCCESS] mockWBTC approved");
        
        // Approve mockLINK
        console.log("Approving mockLINK...");
        require(
            IERC20(MOCK_LINK).approve(VAULT, APPROVAL_AMOUNT),
            "mockLINK approval failed"
        );
        console.log("[SUCCESS] mockLINK approved");
        
        vm.stopBroadcast();
        
        // ============================================================================
        // Summary
        // ============================================================================
        
        console.log("");
        console.log("=====================================");
        console.log("All Approvals Complete!");
        console.log("=====================================");
        console.log("Token Approvals:");
        console.log("  mockWETH (0x686f670889750c611D2BFff89951b687ed5f92A6)");
        console.log("  mockWBTC (0xB9990a0E50B7c355Ade30c5470fb50dE106385e9)");
        console.log("  mockLINK (0xDe9660bf486Bcb9921A4a6C87443B45D52639849)");
        console.log("");
        console.log("Approved for Vault: ", VAULT);
        console.log("Approval Amount: Unlimited");
        console.log("=====================================");
    }
}
