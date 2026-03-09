# Vault.sol Deploy & CRE Setup Scripts - Summary

This package includes comprehensive scripts and tools for deploying the `Vault.sol` contract and integrating it with Chainlink Runtime Environment (CRE).

## 📦 Files Created

### 1. **DeployVault.s.sol** - Unified Deploy & Setup Script
- **Location:** `script/DeployVault.s.sol`
- **Purpose:** Deploy Vault contract AND configure CRE integration in one command
- **Features:**
  - Automatic forwarder address detection (MockForwarder for testing, KeystoneForwarder for production)
  - Automatic CRE permission configuration (optional via environment variables)
  - Both deployment and setup happen in a single transaction batch
  - Comprehensive logging showing final configuration
  - Environment variable support for easy automation

**Usage (Deploy + Setup):**
```bash
WORKFLOW_ID=0x... \
WORKFLOW_AUTHOR=0x... \
forge script script/DeployVault.s.sol:DeployVault \
  --rpc-url $RPC_URL \
  --private-key $PRIVATE_KEY \
  --broadcast \
  -vvv
```

### 2. **SetupVaultCRE.s.sol** - Configuration Script
- **Location:** `script/SetupVaultCRE.s.sol`
- **Purpose:** Configure CRE security permissions after deployment
- **Features:**
  - Update forwarder address without redeploying
  - Configure workflow ID validation
  - Configure workflow author/owner validation
  - Configure workflow name validation
  - Full status reporting

**Usage:**
```bash
VAULT_ADDRESS=0x... \
WORKFLOW_ID=0x... \
WORKFLOW_AUTHOR=0x... \
forge script script/SetupVaultCRE.s.sol:SetupVaultCRE \
  --rpc-url $RPC_URL \
  --private-key $PRIVATE_KEY \
  --broadcast \
  -vvv
```

### 3. **VaultReportEncoder.sol** - Report Encoding Utilities
- **Location:** `script/VaultReportEncoder.sol`
- **Purpose:** Helper functions for encoding CRE reports
- **Functions:**
  - `encodeMintSharesERC20()` - Encode share minting
  - `encodeDeployERC20()` - Encode tokenizer deployment
  - `encodeRedeemSharesERC20()` - Encode share redemption
  - `encodeMintShares1155()` - Encode ERC1155 creation
  - `encodeDepositExisting1155()` - Encode ERC1155 deposit
  - `encodeRedeemShares1155()` - Encode ERC1155 redemption

**Usage:** Reference implementations for report encoding in CRE workflows

### 4. **vault-deploy.sh** - Helper Shell Script
- **Location:** `script/vault-deploy.sh`
- **Purpose:** Convenient CLI for common deployment operations
- **Commands:**
  - `deploy` - Deploy the Vault contract
  - `setup` - Configure CRE permissions
  - `verify` - Verify on Etherscan
  - `status` - Check configuration
  - `update-forwarder` - Update forwarder address

**Usage:**
```bash
./vault-deploy.sh deploy
./vault-deploy.sh setup --vault 0x... --workflow-author 0x...
./vault-deploy.sh status --vault 0x...
```

### 5. **DEPLOYMENT_GUIDE.md** - Comprehensive Documentation
- **Location:** `script/DEPLOYMENT_GUIDE.md`
- **Contents:**
  - Quick start guide
  - Detailed setup instructions
  - Security configuration options
  - CRE simulation testing
  - Production transition guide
  - Troubleshooting tips
  - Additional resources

## 🚀 Quick Start

### Step 1: Deploy Vault Contract
```bash
export RPC_URL=https://sepolia.infura.io/v3/YOUR_INFURA_KEY
export PRIVATE_KEY=0x...

forge script script/DeployVault.s.sol:DeployVault \
  --rpc-url $RPC_URL \
  --private-key $PRIVATE_KEY \
  --broadcast \
  -vvv

# Save the deployed address
export VAULT_ADDRESS=0x...
```

### Step 2: Configure CRE Permissions
```bash
export WORKFLOW_AUTHOR=0x...  # Your wallet address
export WORKFLOW_ID=0x...      # Your CRE workflow ID

forge script script/SetupVaultCRE.s.sol:SetupVaultCRE \
  --rpc-url $RPC_URL \
  --private-key $PRIVATE_KEY \
  --broadcast \
  -vvv
```

### Step 3: Test with CRE Simulation
```bash
cre workflow simulate
```

### Step 4: Deploy to Production
When ready to deploy to production:
1. Update forwarder to production KeystoneForwarder
2. Add security validations
3. Update CRE workflow configuration

## 🔐 Security Architecture

The Vault contract implements a multi-layer security model as recommended by Chainlink:

### Layer 1: Forwarder Address (Required)
- **Purpose:** Ensures only the Chainlink KeystoneForwarder can call the contract
- **Configured at:** Contract deployment
- **Configured by:** Constructor parameter

### Layer 2: Workflow ID (Optional, Recommended)
- **Purpose:** Restrict to specific CRE workflow
- **Best for:** Single workflow scenarios
- **Configured by:** `setExpectedWorkflowId(bytes32)`

### Layer 3: Workflow Author (Optional)
- **Purpose:** Restrict to workflows owned by specific address
- **Best for:** Multi-workflow scenarios from same owner
- **Configured by:** `setExpectedAuthor(address)`

### Layer 4: Workflow Name (Optional)
- **Purpose:** Restrict to specific workflow name
- **Requires:** Workflow author validation enabled
- **Configured by:** `setExpectedWorkflowName(string)`

## 📋 Vault Contract Actions

The Vault processes CRE reports with the following action codes:

```
0 - ACTION_MINT_SHARES_ERC20       Mint ERC20 shares from collateral
1 - ACTION_DEPLOY_ERC20            Deploy new ERC20 tokenizer
2 - ACTION_REDEEM_SHARES_ERC20     Redeem ERC20 shares
3 - ACTION_MINT_SHARES_1155        Mint ERC1155 shares from collateral
4 - ACTION_DEPOSIT_EXISTING_1155   Deposit to existing ERC1155 batch
5 - ACTION_REDEEM_SHARES_1155      Redeem ERC1155 shares
```

See [VaultReportEncoder.sol](VaultReportEncoder.sol) for encoding examples.

## 🔗 Integration with CRE Workflow

### In your CRE workflow config.json:
```json
{
  "evm_write": {
    "target_address": "0x1234...",  // Your Vault address
    "target_chain_id": 11155111,
    "contract_name": "Vault"
  }
}
```

### In your CRE workflow output:
```javascript
// Encode the report using VaultReportEncoder functions
const report = ethers.AbiCoder.defaultAbiCoder().encode(
  ['uint8', 'uint256', 'address', 'address[]', 'uint256[]', 'uint256'],
  [0, vaultId, user, collaterals, amounts, sharesToMint]
);

return {
  target_address: "0xVaultAddress...",
  report_data: report
};
```

## 🌐 Network Configuration

### Ethereum Sepolia (Testing)
- **Mock Forwarder:** `0x15fC6ae953E024d975e77382eEeC56A9101f9F88`
- **Keystone Forwarder:** `0xF8344CFd5c43616a4366C34E3EEE75af79a74482`
- **Chain ID:** 11155111

For other networks, see the [Forwarder Directory](https://docs.chain.link/cre/guides/workflow/using-evm-client/forwarder-directory).

## 📚 Documentation References

- **CRE Building Consumer Contracts:** https://docs.chain.link/cre/guides/workflow/using-evm-client/onchain-write/building-consumer-contracts
- **ReceiverTemplate:** Base contract for CRE integration
- **Forwarder Directory:** Network-specific forwarder addresses
- **Security Considerations:** https://docs.chain.link/cre/guides/workflow/using-evm-client/onchain-write/building-consumer-contracts#7-security-considerations

## ⚙️ Environment Variables

### Required
- `RPC_URL` - RPC endpoint URL
- `PRIVATE_KEY` - Private key for signing transactions

### Optional (for deployment)
- `VAULT_ADDRESS` - Deployed Vault address (for setup script)
- `WORKFLOW_ID` - CRE workflow ID (bytes32)
- `WORKFLOW_AUTHOR` - Workflow owner address
- `WORKFLOW_NAME` - Workflow name (string)
- `FORWARDER_ADDRESS` - Custom forwarder address
- `ETHERSCAN_KEY` - For contract verification

## 🧪 Testing & Simulation

### 1. Deploy with MockForwarder (Simulation)
```bash
export USE_MOCK_FORWARDER=true
forge script script/DeployVault.s.sol:DeployVault \
  --rpc-url $RPC_URL \
  --private-key $PRIVATE_KEY \
  --broadcast
```

### 2. Test with CRE Simulation
```bash
cre workflow simulate
```

**Important:** Do NOT configure metadata validations (workflow ID, author, name) during simulation. The MockForwarder doesn't provide this metadata.

### 3. Transition to Production
```bash
export USE_MOCK_FORWARDER=false
forge script script/SetupVaultCRE.s.sol:SetupVaultCRE \
  --rpc-url $RPC_URL \
  --private-key $PRIVATE_KEY \
  --broadcast
```

## 🛠️ Troubleshooting

### "VAULT_ADDRESS not set"
Export the Vault address from Step 1:
```bash
export VAULT_ADDRESS=0x...
```

### "Forwarder validation failed"
Check that the forwarder address is correct:
```bash
./vault-deploy.sh status --vault $VAULT_ADDRESS
```

### Simulation fails with metadata errors
MockForwarder doesn't provide metadata. Either:
1. Clear validations for simulation
2. Use production forwarder address after testing

## 📝 Additional Notes

- **Make script executable:**
  ```bash
  chmod +x script/vault-deploy.sh
  ```

- **View script output:**
  Deployment scripts provide detailed logging of all actions and next steps.

- **Verify deployment:**
  ```bash
  ./vault-deploy.sh status --vault $VAULT_ADDRESS
  ```

- **Update forwarder later:**
  ```bash
  ./vault-deploy.sh update-forwarder --vault $VAULT_ADDRESS --forwarder 0x...
  ```

## 📞 Support

- **Chainlink Docs:** https://docs.chain.link
- **Discord:** https://discord.gg/aSK4zew
- **GitHub:** https://github.com/smartcontractkit/chainlink

---

**Created:** March 7, 2026
**Vault Contract:** [src/Vault.sol](../src/Vault.sol)
**Complete Guide:** [DEPLOYMENT_GUIDE.md](DEPLOYMENT_GUIDE.md)
