// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {Vault} from "../src/Vault.sol";

/**
 * @title SetupVaultCRE
 * @notice Setup script for configuring Vault with CRE security permissions
 * @dev Configures forwarder address and optional workflow validation
 *
 * This script should be run AFTER deploying the Vault contract.
 * It allows you to update CRE permissions without redeploying.
 *
 * Usage:
 *   Basic setup (update forwarder only):
 *   forge script script/SetupVaultCRE.s.sol:SetupVaultCRE --rpc-url $RPC_URL --broadcast
 *
 *   With all CRE permissions:
 *   WORKFLOW_ID=0x... \
 *   WORKFLOW_AUTHOR=0x... \
 *   WORKFLOW_NAME="my_workflow" \
 *   forge script script/SetupVaultCRE.s.sol:SetupVaultCRE \
 *     --rpc-url $RPC_URL \
 *     --private-key $PRIVATE_KEY \
 *     --broadcast \
 *     -vvv
 *
 * Environment Variables (optional):
 *   VAULT_ADDRESS          - Address of deployed Vault contract (required)
 *   FORWARDER_ADDRESS      - Keystone Forwarder address (uses production default if not set)
 *   WORKFLOW_ID            - Expected workflow ID (bytes32)
 *   WORKFLOW_AUTHOR        - Expected workflow author/owner address
 *   WORKFLOW_NAME          - Expected workflow name (string, requires author to be set)
 *   USE_MOCK_FORWARDER     - Set to "true" for MockForwarder (simulation), defaults to false
 */
contract SetupVaultCRE is Script {
    // ============================================================================
    // CRE Forwarder Addresses
    // ============================================================================

    // Ethereum Sepolia
    address constant SEPOLIA_MOCK_FORWARDER = 0x15fC6ae953E024d975e77382eEeC56A9101f9F88;
    address constant SEPOLIA_KEYSTONE_FORWARDER = 0xF8344CFd5c43616a4366C34E3EEE75af79a74482;

    // Ethereum Mainnet (update with actual addresses)
    // address constant MAINNET_KEYSTONE_FORWARDER = 0x...;

    // ============================================================================
    // Configuration Variables
    // ============================================================================
    Vault public vault;
    address public vaultAddress;
    address public forwarderAddress;
    address public workflowAuthor;
    bytes32 public workflowId;
    string public workflowName;

    function run() public {
        // Get Vault contract address from environment
        vaultAddress = vm.envAddress("VAULT_ADDRESS");
        require(vaultAddress != address(0), "VAULT_ADDRESS not set");

        vault = Vault(vaultAddress);

        // Determine forwarder address (defaults to production KeystoneForwarder)
        bool useMockForwarder = vm.envOr("USE_MOCK_FORWARDER", false);
        if (useMockForwarder) {
            forwarderAddress = SEPOLIA_MOCK_FORWARDER;
            console.log("[INFO] Using MockForwarder for testing/simulation");
        } else {
            forwarderAddress = vm.envOr("FORWARDER_ADDRESS", SEPOLIA_KEYSTONE_FORWARDER);
            console.log("[INFO] Using production KeystoneForwarder");
        }

        // Load optional workflow permissions from environment
        workflowAuthor = vm.envOr("WORKFLOW_AUTHOR", address(0));
        workflowId = vm.envOr("WORKFLOW_ID", bytes32(0));
        workflowName = vm.envOr("WORKFLOW_NAME", string(""));

        console.log("========================================");
        console.log("Setting up Vault CRE Permissions");
        console.log("========================================");
        console.log("Vault Address:", vaultAddress);
        console.log("Forwarder Address:", forwarderAddress);
        console.log("Use Mock Forwarder:", useMockForwarder);
        console.log("----------------------------------------");

        vm.startBroadcast();

        // Update forwarder address
        updateForwarder();

        // Configure workflow permissions if provided
        configureWorkflowPermissions();

        vm.stopBroadcast();

        // Print final status
        printConfigurationStatus();
    }

    /**
     * @notice Updates the Keystone Forwarder address
     * @dev This is the primary security mechanism for the Vault
     */
    function updateForwarder() internal {
        address currentForwarder = vault.getForwarderAddress();

        if (currentForwarder != forwarderAddress) {
            vault.setForwarderAddress(forwarderAddress);
            console.log("[OK] Forwarder address updated");
            console.log("  From:", currentForwarder);
            console.log("  To:  ", forwarderAddress);
        } else {
            console.log("[OK] Forwarder address unchanged:", forwarderAddress);
        }
    }

    /**
     * @notice Configures optional workflow-level permissions
     * @dev For production, recommend setting workflow ID for maximum security
     */
    function configureWorkflowPermissions() internal {
        console.log("");
        console.log("Configuring Workflow Permissions:");
        console.log("----------------------------------------");

        // Configure workflow ID if provided
        if (workflowId != bytes32(0)) {
            bytes32 currentWorkflowId = vault.getExpectedWorkflowId();
            if (currentWorkflowId != workflowId) {
                vault.setExpectedWorkflowId(workflowId);
                console.log("[OK] Workflow ID configured:", vm.toString(workflowId));
            } else {
                console.log("[OK] Workflow ID unchanged");
            }
        } else {
            console.log("[INFO] Workflow ID not configured (optional)");
        }

        // Configure workflow author if provided
        if (workflowAuthor != address(0)) {
            address currentAuthor = vault.getExpectedAuthor();
            if (currentAuthor != workflowAuthor) {
                vault.setExpectedAuthor(workflowAuthor);
                console.log("[OK] Workflow author configured:", workflowAuthor);
            } else {
                console.log("[OK] Workflow author unchanged");
            }
        } else {
            console.log("[INFO] Workflow author not configured (optional)");
        }

        // Configure workflow name if provided (requires author to be set)
        if (bytes(workflowName).length > 0) {
            if (workflowAuthor != address(0)) {
                vault.setExpectedWorkflowName(workflowName);
                console.log("[OK] Workflow name configured:", workflowName);
            } else {
                console.log("[WARN] Workflow name not set - requires WORKFLOW_AUTHOR to be configured");
            }
        } else {
            console.log("[INFO] Workflow name not configured (optional)");
        }

        console.log("----------------------------------------");
    }

    /**
     * @notice Prints the current configuration status
     */
    function printConfigurationStatus() internal view {
        console.log("");
        console.log("========================================");
        console.log("Configuration Status");
        console.log("========================================");
        console.log("");
        console.log("Vault Address:", vaultAddress);
        console.log("");
        console.log("Security Configuration:");
        console.log("  Forwarder: ", vault.getForwarderAddress());
        console.log("  Author:    ", vault.getExpectedAuthor());
        console.log("  Workflow ID:", vm.toString(vault.getExpectedWorkflowId()));
        console.log("");
        console.log("Next Steps:");
        console.log("----------------------------------------");
        console.log("1. Update your CRE workflow config.json:");
        console.log("   {");
        console.log("     \"evm_write\": {");
        console.log("       \"target_address\": \"", vaultAddress, "\",");
        console.log("       \"target_chain_id\": 11155111");
        console.log("     }");
        console.log("   }");
        console.log("");
        console.log("2. Test the integration:");
        console.log("   cre workflow simulate");
        console.log("");
        console.log("3. For production deployment:");
        console.log("   - Update FORWARDER_ADDRESS to production KeystoneForwarder");
        console.log("   - Re-run this script with updated environment variables");
        console.log("");
        console.log("Resources:");
        console.log("----------------------------------------");
        console.log("CRE Documentation:");
        console.log("  https://docs.chain.link/cre/guides/workflow/using-evm-client/onchain-write/building-consumer-contracts");
        console.log("");
        console.log("Security Considerations:");
        console.log("  https://docs.chain.link/cre/guides/workflow/using-evm-client/onchain-write/building-consumer-contracts#7-security-considerations");
        console.log("========================================");
    }
}
