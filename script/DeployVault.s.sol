// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {Vault} from "../src/Vault.sol";

/**
 * @title DeployVault
 * @notice Deployment script for Vault.sol with CRE integration
 * @dev Deploys the Vault contract and configures CRE (Chainlink Runtime Environment) permissions
 *
 * Usage:
 *   For Simulation (Ethereum Sepolia):
 *   forge script script/DeployVault.s.sol:DeployVault --rpc-url $RPC_URL --broadcast --verify
 *
 *   With environment variables:
 *   forge script script/DeployVault.s.sol:DeployVault \
 *     --rpc-url $RPC_URL \
 *     --private-key $PRIVATE_KEY \
 *     --broadcast \
 *     --verify \
 *     -vvv
 */
contract DeployVault is Script {
    // ============================================================================
    // Constants - CRE Forwarder Addresses
    // ============================================================================
    // Note: Update these addresses based on your target network
    // See: https://docs.chain.link/cre/guides/workflow/using-evm-client/forwarder-directory

    // Ethereum Sepolia - For Testing/Simulation
    address constant SEPOLIA_MOCK_FORWARDER = 0x15fC6ae953E024d975e77382eEeC56A9101f9F88;
    address constant SEPOLIA_KEYSTONE_FORWARDER = 0xF8344CFd5c43616a4366C34E3EEE75af79a74482;

    // Ethereum Mainnet (uncomment if deploying to mainnet)
    // address constant MAINNET_KEYSTONE_FORWARDER = 0x...; // Add actual mainnet address

    // ============================================================================
    // Vault Configuration
    // ============================================================================
    string constant VAULT_URI = "ipfs://"; // Update with your IPFS URI or metadata URL

    // ============================================================================
    // State Variables
    // ============================================================================
    Vault public vault;
    address public deployerAddress;
    address public forwarderAddress;

    // ============================================================================
    // Setup and Execution
    // ============================================================================

    function setUp() public {
        // Get deployer address from environment variable or use default
        deployerAddress = vm.envOr("DEPLOYER_ADDRESS", msg.sender);
    }

    function run() public {
        // Get private key from environment
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        
        // Determine which forwarder to use based on environment
        bool isSimulation = vm.envOr("USE_MOCK_FORWARDER", false);
        forwarderAddress = isSimulation ? SEPOLIA_MOCK_FORWARDER : SEPOLIA_KEYSTONE_FORWARDER;

        console.log("========================================");
        console.log("Deploying Vault with CRE Integration");
        console.log("========================================");
        console.log("Deployer Address:", deployerAddress);
        console.log("Forwarder Address:", forwarderAddress);
        console.log("Is Simulation:", isSimulation);
        console.log("Vault URI:", VAULT_URI);
        console.log("----------------------------------------");

        // Start broadcasting transactions with the deployer's private key
        vm.startBroadcast(deployerKey);

        // Deploy the Vault contract
        vault = new Vault(VAULT_URI, forwarderAddress);

        console.log("[OK] Vault deployed at:", address(vault));
        console.log("  Contract: Vault");
        console.log("  Owner: ", msg.sender);
        console.log("  Forwarder: ", forwarderAddress);

        // Configure CRE permissions immediately after deployment
        console.log("");
        console.log("Configuring CRE Permissions:");
        console.log("----------------------------------------");
        configureCREPermissions();

        vm.stopBroadcast();

        // Print post-deployment information
        printDeploymentInfo();
    }

    /**
     * @notice Configures CRE security permissions after deployment
     * @dev These configurations are optional but recommended for production
     *
     * The following can be configured:
     * - expectedWorkflowId: Restrict to a specific workflow (highest security)
     * - expectedAuthor: Restrict to workflows from a specific owner
     * - expectedWorkflowName: Restrict by workflow name (requires author validation)
     */
    function configureCREPermissions() internal {
        console.log("");
        console.log("Configuring CRE Permissions:");
        console.log("----------------------------------------");

        // Example: Set expected workflow author (replace with your workflow owner address)
        address expectedAuthor = vm.envOr("WORKFLOW_AUTHOR", address(0));
        if (expectedAuthor != address(0)) {
            vault.setExpectedAuthor(expectedAuthor);
            console.log("[OK] Set expected author:", expectedAuthor);
        }

        // Example: Set expected workflow ID (replace with your workflow ID)
        bytes32 expectedWorkflowId = vm.envOr("WORKFLOW_ID", bytes32(0));
        if (expectedWorkflowId != bytes32(0)) {
            vault.setExpectedWorkflowId(expectedWorkflowId);
            console.log("[OK] Set expected workflow ID:", vm.toString(expectedWorkflowId));
        }

        // Example: Set expected workflow name (requires author to be set first)
        string memory expectedWorkflowName = vm.envOr("WORKFLOW_NAME", string(""));
        if (bytes(expectedWorkflowName).length > 0 && expectedAuthor != address(0)) {
            vault.setExpectedWorkflowName(expectedWorkflowName);
            console.log("[OK] Set expected workflow name:", expectedWorkflowName);
        }

        console.log("----------------------------------------");
    }

    /**
     * @notice Prints comprehensive deployment information and next steps
     */
    function printDeploymentInfo() internal view {
        console.log("");
        console.log("========================================");
        console.log("[SUCCESS] Deployment & Setup Complete!");
        console.log("========================================");
        console.log("");
        console.log("Contract Address: ", address(vault));
        console.log("Network: Ethereum Sepolia");
        console.log("Forwarder: ", vault.getForwarderAddress());
        if (vault.getExpectedWorkflowId() != bytes32(0)) {
            console.log("Workflow ID: ", vm.toString(vault.getExpectedWorkflowId()));
        }
        if (vault.getExpectedAuthor() != address(0)) {
            console.log("Workflow Author: ", vault.getExpectedAuthor());
        }
        console.log("");
        console.log("Configuration Summary:");
        console.log("----------------------------------------");
        console.log("[OK] Vault contract deployed");
        console.log("[OK] Forwarder configured");
        if (vault.getExpectedWorkflowId() != bytes32(0)) {
            console.log("[OK] Workflow ID validation enabled");
        }
        if (vault.getExpectedAuthor() != address(0)) {
            console.log("[OK] Workflow author validation enabled");
        }
        console.log("");
        console.log("Next Steps:");
        console.log("----------------------------------------");
        console.log("1. Update your CRE workflow config.json:");
        console.log("   \"receiver_address\": \"", address(vault), "\"");
        console.log("");
        console.log("2. Test your workflow:");
        console.log("   cre workflow simulate");
        console.log("");
        console.log("3. Deploy to production:");
        console.log("   cre workflow deploy");
        console.log("");
        console.log("Resources:");
        console.log("----------------------------------------");
        console.log("CRE Documentation:");
        console.log("  https://docs.chain.link/cre/guides/workflow/using-evm-client/onchain-write/building-consumer-contracts");
        console.log("");
        console.log("Forwarder Directory:");
        console.log("  https://docs.chain.link/cre/guides/workflow/using-evm-client/forwarder-directory");
        console.log("========================================");
    }
}
