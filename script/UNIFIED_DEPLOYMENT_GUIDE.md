# Unified Vault Deployment & CRE Setup Guide

## Overview

The `DeployVault.s.sol` script now handles **both deployment AND setup in a single command**. No more running separate scripts!

## One Command: Deploy + Configure

```bash
# Single command that does everything:
WORKFLOW_ID=0x... \
WORKFLOW_AUTHOR=0x... \
WORKFLOW_NAME="my_workflow" \
forge script script/DeployVault.s.sol:DeployVault \
  --rpc-url $RPC_URL \
  --private-key $PRIVATE_KEY \
  --broadcast \
  -vvv
```

That's it! The script will:
1. ✅ Deploy the Vault contract
2. ✅ Set the Keystone Forwarder address
3. ✅ Configure workflow ID validation (if WORKFLOW_ID provided)
4. ✅ Configure workflow author validation (if WORKFLOW_AUTHOR provided)
5. ✅ Configure workflow name validation (if WORKFLOW_NAME provided)
6. ✅ Display final configuration summary

## Environment Variables

### Required
- `RPC_URL` - Your Ethereum RPC endpoint
- `PRIVATE_KEY` - Your deployment wallet private key

### Optional (CRE Configuration)
- `WORKFLOW_ID` - Your CRE workflow ID (bytes32)
- `WORKFLOW_AUTHOR` - Workflow owner address
- `WORKFLOW_NAME` - Workflow name (string)

### Optional (Network Configuration)
- `USE_MOCK_FORWARDER` - Set to `true` for testing with MockForwarder
- `FORWARDER_ADDRESS` - Custom forwarder address (auto-detected if not set)

## Examples

### Example 1: Minimal Deployment (Forwarder Only)

```bash
export RPC_URL=https://sepolia.infura.io/v3/YOUR_KEY
export PRIVATE_KEY=0x...

forge script script/DeployVault.s.sol:DeployVault \
  --rpc-url $RPC_URL \
  --private-key $PRIVATE_KEY \
  --broadcast \
  -vvv
```

**Output:**
```
✓ Vault deployed at: 0x1234...
  Forwarder: 0xF8344CFd5c43616a4366C34E3EEE75af79a74482

✅ Deployment & Setup Complete!
```

### Example 2: Full Configuration (All Validations)

```bash
export RPC_URL=https://sepolia.infura.io/v3/YOUR_KEY
export PRIVATE_KEY=0x...
export WORKFLOW_ID=0xabcd1234...
export WORKFLOW_AUTHOR=0x5678...
export WORKFLOW_NAME="my_workflow"

forge script script/DeployVault.s.sol:DeployVault \
  --rpc-url $RPC_URL \
  --private-key $PRIVATE_KEY \
  --broadcast \
  -vvv
```

**Output:**
```
✓ Vault deployed at: 0x1234...
  Forwarder: 0xF8344CFd5c43616a4366C34E3EEE75af79a74482
  Workflow ID: 0xabcd1234...
  Workflow Author: 0x5678...

Configuration Summary:
✓ Vault contract deployed
✓ Forwarder configured
✓ Workflow ID validation enabled
✓ Workflow author validation enabled

✅ Deployment & Setup Complete!
```

### Example 3: Testing with MockForwarder

```bash
export RPC_URL=https://sepolia.infura.io/v3/YOUR_KEY
export PRIVATE_KEY=0x...
export USE_MOCK_FORWARDER=true

forge script script/DeployVault.s.sol:DeployVault \
  --rpc-url $RPC_URL \
  --private-key $PRIVATE_KEY \
  --broadcast \
  -vvv
```

**Note:** With MockForwarder (for testing), do NOT set WORKFLOW_ID, WORKFLOW_AUTHOR, or WORKFLOW_NAME. The MockForwarder doesn't provide this metadata. Configure these only after switching to production KeystoneForwarder.

## What Gets Configured?

### Layer 1: Forwarder (Always)
- ✅ Automatically set during deployment
- ✅ Validates only the Keystone Forwarder can call your contract
- ✅ Basic security enabled by default

### Layer 2: Workflow ID (Optional)
- 🔧 Set via `WORKFLOW_ID` environment variable
- ✅ Restricts to specific workflow
- ✅ Use for single-workflow scenarios (highest security)

### Layer 3: Workflow Author (Optional)
- 🔧 Set via `WORKFLOW_AUTHOR` environment variable
- ✅ Restricts to workflows from specific owner
- ✅ Use for multiple workflows from same owner

### Layer 4: Workflow Name (Optional)
- 🔧 Set via `WORKFLOW_NAME` environment variable
- ⚠️ Requires `WORKFLOW_AUTHOR` to also be set
- ✅ Additional validation layer

## Error Handling

### "PRIVATE_KEY not set"
Export your private key:
```bash
export PRIVATE_KEY=0x...
```

### "Forwarder validation requires metadata validation to be enabled"
If setting WORKFLOW_NAME, you must also set WORKFLOW_AUTHOR:
```bash
export WORKFLOW_AUTHOR=0x...
export WORKFLOW_NAME="my_workflow"
```

### Contract deployed but configuration failed?
The script is atomic - if configuration fails, the deployment succeeds but setup is incomplete. Use the separate `SetupVaultCRE.s.sol` script to configure later:

```bash
VAULT_ADDRESS=0x... \
WORKFLOW_AUTHOR=0x... \
forge script script/SetupVaultCRE.s.sol:SetupVaultCRE \
  --rpc-url $RPC_URL \
  --private-key $PRIVATE_KEY \
  --broadcast \
  -vvv
```

## Next Steps After Deployment

1. **Update CRE Workflow Configuration**
   ```json
   {
     "evm_write": {
       "target_address": "0x...",  // Use the address from output
       "target_chain_id": 11155111
     }
   }
   ```

2. **Test with CRE Simulation**
   ```bash
   cre workflow simulate
   ```

3. **For Production**
   - If you used MockForwarder for testing, update to production KeystoneForwarder:
     ```bash
     ./vault-deploy.sh update-forwarder \
       --vault 0x... \
       --forwarder 0xF8344CFd5c43616a4366C34E3EEE75af79a74482
     ```
   - Deploy your CRE workflow:
     ```bash
     cre workflow deploy
     ```

## Security Best Practices

### For Testing (Simulation)
```bash
# Deploy with MockForwarder, no validation
export USE_MOCK_FORWARDER=true
forge script script/DeployVault.s.sol:DeployVault --broadcast
```

### For Production (Recommended)
```bash
# Deploy with KeystoneForwarder and workflow validation
export WORKFLOW_ID=0x...
export WORKFLOW_AUTHOR=0x...
forge script script/DeployVault.s.sol:DeployVault --broadcast
```

### Production Scenario 1: Single Workflow
```bash
# Restrict contract to ONE specific workflow (highest security)
export WORKFLOW_ID=0x123abc...
forge script script/DeployVault.s.sol:DeployVault --broadcast
```

### Production Scenario 2: Multiple Workflows (Same Owner)
```bash
# Restrict to multiple workflows from your address
export WORKFLOW_AUTHOR=0x5678...
forge script script/DeployVault.s.sol:DeployVault --broadcast
```

## Comparison: Old vs New Process

### Old Process (Two Commands)
```bash
# Step 1: Deploy
forge script script/DeployVault.s.sol:DeployVault --broadcast

# Step 2: Setup (separate command)
VAULT_ADDRESS=0x... \
forge script script/SetupVaultCRE.s.sol:SetupVaultCRE --broadcast

# Total time: ~2 minutes
```

### New Process (One Command)
```bash
# One command: deploy + setup
WORKFLOW_ID=0x... \
WORKFLOW_AUTHOR=0x... \
forge script script/DeployVault.s.sol:DeployVault --broadcast

# Total time: ~1 minute
```

## Still Need to Update Permissions Later?

If you deployed without configuration or want to add/change permissions:

```bash
# Use the dedicated setup script for existing contracts
VAULT_ADDRESS=0x... \
WORKFLOW_ID=0x... \
forge script script/SetupVaultCRE.s.sol:SetupVaultCRE --broadcast
```

## Troubleshooting

### Script executed but no configuration applied
Check you're exporting environment variables before running the script:
```bash
export WORKFLOW_ID=0x...
export WORKFLOW_AUTHOR=0x...
# Then run the script
forge script ...
```

### "Invalid forwarder address"
Ensure you're using the correct forwarder for your network:
- Sepolia MockForwarder: `0x15fC6ae953E024d975e77382eEeC56A9101f9F88`
- Sepolia KeystoneForwarder: `0xF8344CFd5c43616a4366C34E3EEE75af79a74482`

### Configuration didn't stick?
Verify it was applied:
```bash
./vault-deploy.sh status --vault 0x...
```

## Technical Details

The unified script works by:
1. Creating a new Vault instance with forwarder address
2. Running configuration methods in the same transaction batch
3. All changes are atomic (all succeed or all fail together)
4. No need to deploy separately and then configure

This is more efficient than two separate scripts because:
- ✅ Single transaction batch instead of two
- ✅ Faster execution
- ✅ No need to wait between deployment and configuration
- ✅ Less prone to configuration being forgotten

---

**For detailed information:** See [DEPLOYMENT_GUIDE.md](DEPLOYMENT_GUIDE.md)
**For complete reference:** See [README.md](README.md)
