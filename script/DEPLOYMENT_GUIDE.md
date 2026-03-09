# Vault Deployment & CRE Setup Guide

This directory contains scripts to deploy the `Vault.sol` contract and configure it for Chainlink Runtime Environment (CRE) integration.

## Overview

The Vault contract inherits from `ReceiverTemplate`, making it compatible with CRE workflows. The contract receives reports from CRE workflows via the Chainlink `KeystoneForwarder` and processes them through the `_processReport()` function.

For detailed information about building CRE consumer contracts, see:
https://docs.chain.link/cre/guides/workflow/using-evm-client/onchain-write/building-consumer-contracts

## Quick Start (5 Minutes)

### Single Command: Deploy & Setup

```bash
# Deploy Vault with CRE configuration all-in-one:
export RPC_URL=https://sepolia.infura.io/v3/YOUR_INFURA_KEY
export PRIVATE_KEY=0x...

# Optional: Set CRE permissions (or leave empty for just forwarder setup)
export WORKFLOW_ID=0x...
export WORKFLOW_AUTHOR=0x...
export WORKFLOW_NAME="my_workflow"

# Deploy everything at once
forge script script/DeployVault.s.sol:DeployVault \
  --rpc-url $RPC_URL \
  --private-key $PRIVATE_KEY \
  --broadcast \
  -vvv
```

**Done!** Your Vault is deployed and configured. No separate setup step needed.

## Detailed Setup Instructions

### Prerequisites

- Foundry installed: https://book.getfoundry.sh
- RPC URL for Ethereum Sepolia (for testing)
- Private key for deployment account
- Optional: Etherscan API key for verification

### Environment Variables

Create a `.env` file or export environment variables:

```bash
# Required for deployment
RPC_URL=https://sepolia.infura.io/v3/YOUR_INFURA_KEY
PRIVATE_KEY=0x...

# Optional: CRE workflow configuration (set if you want automatic configuration)
WORKFLOW_ID=0x...    # Your CRE workflow ID (bytes32)
WORKFLOW_AUTHOR=0x...  # Address of workflow owner
WORKFLOW_NAME="workflow_name"  # Workflow name (string)

# Optional: Forwarder addresses
FORWARDER_ADDRESS=0xF8344CFd5c43616a4366C34E3EEE75af79a74482  # Sepolia KeystoneForwarder
USE_MOCK_FORWARDER=false  # Set to true for MockForwarder (simulation)
```

### Complete One-Step Deployment

The new unified script handles everything in one command:

```bash
# Load environment variables
source .env

# Deploy Vault with automatic CRE configuration
WORKFLOW_ID=0x... \
WORKFLOW_AUTHOR=0x... \
WORKFLOW_NAME="my_workflow" \
forge script script/DeployVault.s.sol:DeployVault \
  --rpc-url $RPC_URL \
  --private-key $PRIVATE_KEY \
  --broadcast \
  -vvv
```

**Output:**
```
✓ Vault deployed at: 0x1234...
  Contract: Vault
  Owner: 0x5678...
  Forwarder: 0xF8344CFd5c43616a4366C34E3EEE75af79a74482
  
✓ Set expected author: 0x...
✓ Set expected workflow ID: 0x...
✓ Set expected workflow name: my_workflow

✅ Deployment & Setup Complete!
```

That's it! No separate setup step needed.

## Security Configuration

### Forwarder Security (Required)

The Vault contract requires a `KeystoneForwarder` address at deployment. This is the primary security mechanism.

**Forwarder Addresses by Network:**

- **Ethereum Sepolia (Testing)**
  - MockForwarder: `0x15fC6ae953E024d975e77382eEeC56A9101f9F88`
  - KeystoneForwarder: `0xF8344CFd5c43616a4366C34E3EEE75af79a74482`

- **Ethereum Mainnet** (See [Forwarder Directory](https://docs.chain.link/cre/guides/workflow/using-evm-client/forwarder-directory))

### Optional Permission Layers

After deployment, add additional security checks:

#### 1. Workflow ID Validation (Highest Security for Single Workflow)

```bash
export WORKFLOW_ID=0x... # Your CRE workflow ID

forge script script/SetupVaultCRE.s.sol:SetupVaultCRE \
  --rpc-url $RPC_URL \
  --private-key $PRIVATE_KEY \
  --broadcast
```

This ensures only reports from your specific workflow can update the contract.

#### 2. Workflow Author Validation (Multi-Workflow Setup)

```bash
export WORKFLOW_AUTHOR=0x... # Your wallet address

forge script script/SetupVaultCRE.s.sol:SetupVaultCRE \
  --rpc-url $RPC_URL \
  --private-key $PRIVATE_KEY \
  --broadcast
```

This allows multiple workflows owned by you to update the contract.

#### 3. Workflow Name Validation (Requires Author)

```bash
export WORKFLOW_AUTHOR=0x...
export WORKFLOW_NAME="my_workflow"

forge script script/SetupVaultCRE.s.sol:SetupVaultCRE \
  --rpc-url $RPC_URL \
  --private-key $PRIVATE_KEY \
  --broadcast
```

**Important:** Workflow name validation requires author validation to be set.

## Testing with CRE Simulation

### 1. Create a CRE Workflow (config.json)

```json
{
  "evm_write": {
    "target_address": "0x1234...",  // Your Vault address
    "target_chain_id": 11155111,
    "contract_name": "Vault"
  }
}
```

### 2. Simulate Workflow Execution

```bash
cre workflow simulate
```

**Note:** During simulation with MockForwarder, do NOT configure:
- `setExpectedWorkflowId()`
- `setExpectedAuthor()`
- `setExpectedWorkflowName()`

The MockForwarder doesn't provide metadata for these validations. Configure permissions after transitioning to production.

## Transitioning to Production

### Option 1: Deploy New Instance with Production Forwarder

```bash
export FORWARDER_ADDRESS=0xF8344CFd5c43616a4366C34E3EEE75af79a74482  # Production
export USE_MOCK_FORWARDER=false

forge script script/DeployVault.s.sol:DeployVault \
  --rpc-url $RPC_URL \
  --private-key $PRIVATE_KEY \
  --broadcast \
  -vvv
```

### Option 2: Update Existing Contract's Forwarder

```bash
export VAULT_ADDRESS=0x...  # Your existing Vault address
export FORWARDER_ADDRESS=0xF8344CFd5c43616a4366C34E3EEE75af79a74482

forge script script/SetupVaultCRE.s.sol:SetupVaultCRE \
  --rpc-url $RPC_URL \
  --private-key $PRIVATE_KEY \
  --broadcast \
  -vvv
```

Then configure additional security checks as needed.

## Vault Contract Actions

The Vault contract processes CRE reports with the following action codes:

```solidity
// ERC20 Tokenizer Actions
ACTION_MINT_SHARES_ERC20 = 0      // Mint ERC20 shares from collateral
ACTION_DEPLOY_ERC20 = 1           // Deploy new ERC20 tokenizer
ACTION_REDEEM_SHARES_ERC20 = 2    // Redeem ERC20 shares

// ERC1155 Actions
ACTION_MINT_SHARES_1155 = 3       // Mint ERC1155 shares from collateral
ACTION_DEPOSIT_EXISTING_1155 = 4  // Deposit to existing ERC1155 batch
ACTION_REDEEM_SHARES_1155 = 5     // Redeem ERC1155 shares
```

Each action expects a different report format. Ensure your CRE workflow encodes reports correctly.

## Report Format Examples

### ERC20 Share Minting

```solidity
// Report encoding:
(uint8 actionCode, uint256 vaultId, address user, 
 address[] collaterals, uint256[] amounts, uint256 sharesToMint)
```

### ERC20 Tokenizer Deployment

```solidity
// Report encoding:
(uint8 actionCode, string name, string symbol, 
 address[] collaterals, address user)
```

### ERC1155 Minting

```solidity
// Report encoding:
(uint8 actionCode, uint256 unused, address user, 
 address[] collaterals, uint256[] amounts, uint256 sharesToMint)
```

For more details, see the `_processReport()` function in [Vault.sol](../src/Vault.sol).

## Troubleshooting

### "VAULT_ADDRESS not set"

The SetupVaultCRE script requires the Vault contract address. Set it as an environment variable:

```bash
export VAULT_ADDRESS=0x...
```

### "Forwarder validation failed"

If reports are being rejected:

1. Verify the forwarder address is correct for your network
2. Check that the Vault is using the correct forwarder:
   ```bash
   cast call $VAULT_ADDRESS "getForwarderAddress()" --rpc-url $RPC_URL
   ```

### Simulation fails with metadata validation errors

During simulation, MockForwarder doesn't provide workflow metadata. Remove or clear these configurations:

```bash
# Temporarily clear validations for simulation
forge script -c script/SetupVaultCRE.s.sol:SetupVaultCRE \
  --constructor-args "address(0)" \
  --rpc-url $RPC_URL \
  --private-key $PRIVATE_KEY \
  --broadcast
```

Or redeploy with MockForwarder without metadata validations set.

## Additional Resources

- **CRE Documentation**: https://docs.chain.link/cre/guides/workflow/using-evm-client/onchain-write/building-consumer-contracts
- **ReceiverTemplate**: https://github.com/smartcontractkit/chainlink/blob/develop/contracts/src/v0.8/cre/receiver_template.sol
- **Forwarder Directory**: https://docs.chain.link/cre/guides/workflow/using-evm-client/forwarder-directory
- **IReceiver Interface**: https://docs.chain.link/cre/guides/workflow/using-evm-client/onchain-write/building-consumer-contracts#21-implement-the-ireceiver-interface
- **Security Considerations**: https://docs.chain.link/cre/guides/workflow/using-evm-client/onchain-write/building-consumer-contracts#7-security-considerations

## Support

For issues or questions:
- Chainlink Documentation: https://docs.chain.link
- Discord: https://discord.gg/aSK4zew
- GitHub Issues: https://github.com/smartcontractkit/chainlink/issues
