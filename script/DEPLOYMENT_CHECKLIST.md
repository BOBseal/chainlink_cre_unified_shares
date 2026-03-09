# Vault Deployment Checklist

Use this checklist to ensure your Vault contract is properly deployed and configured for CRE integration.

## Pre-Deployment

- [ ] **Review Vault Contract**
  - Verify [src/Vault.sol](../src/Vault.sol) logic is correct
  - Check all action handlers match your CRE workflow output

- [ ] **Set Up Environment**
  - [ ] Install Foundry: `curl -L https://foundry.paradigm.xyz | bash`
  - [ ] Clone repository and navigate to project
  - [ ] Run `forge install` to fetch dependencies
  - [ ] Create `.env` file from `.env.example`

- [ ] **Configure Credentials**
  - [ ] Set `RPC_URL` to Ethereum Sepolia RPC endpoint
  - [ ] Set `PRIVATE_KEY` to your deployment wallet
  - [ ] Verify account has sufficient ETH for gas

- [ ] **Review Security Settings**
  - [ ] Decide on security model:
    - [ ] Forwarder only (basic)
    - [ ] Forwarder + Workflow ID (recommended for single workflow)
    - [ ] Forwarder + Workflow Author (for multiple workflows)

## Deployment

- [ ] **Deploy Vault Contract**
  ```bash
  forge script script/DeployVault.s.sol:DeployVault \
    --rpc-url $RPC_URL \
    --private-key $PRIVATE_KEY \
    --broadcast \
    -vvv
  ```
  - [ ] Deployment successful
  - [ ] Contract address logged
  - [ ] Save contract address: `export VAULT_ADDRESS=0x...`

- [ ] **Verify Deployment**
  ```bash
  ./vault-deploy.sh status --vault $VAULT_ADDRESS
  ```
  - [ ] Vault address displayed correctly
  - [ ] Forwarder address is correct (MockForwarder or KeystoneForwarder)
  - [ ] Owner address is your account

## Configuration (For Testing)

If using MockForwarder for simulation:

- [ ] **Skip Metadata Validations**
  - MockForwarder doesn't provide workflow metadata
  - Do NOT configure: `setExpectedWorkflowId()`, `setExpectedAuthor()`, `setExpectedWorkflowName()`

- [ ] **Configure Report Handlers**
  - [ ] Verify action code mappings in Vault contract
  - [ ] Test each action type in simulation:
    - [ ] ACTION_MINT_SHARES_ERC20
    - [ ] ACTION_DEPLOY_ERC20
    - [ ] ACTION_REDEEM_SHARES_ERC20
    - [ ] ACTION_MINT_SHARES_1155
    - [ ] ACTION_DEPOSIT_EXISTING_1155
    - [ ] ACTION_REDEEM_SHARES_1155

## CRE Workflow Setup

- [ ] **Create Workflow Configuration**
  - [ ] Create or update `config.json` with:
    ```json
    {
      "evm_write": {
        "target_address": "0xVaultAddress...",
        "target_chain_id": 11155111,
        "contract_name": "Vault"
      }
    }
    ```
  - [ ] Verify target address matches deployed Vault
  - [ ] Use correct chain ID (11155111 for Sepolia)

- [ ] **Implement Report Encoding**
  - [ ] Use `VaultReportEncoder.sol` for encoding examples
  - [ ] Encode reports with correct action code and parameters
  - [ ] Validate report structure matches Vault expectations
  - [ ] Test encoding logic in JavaScript/TypeScript:
    ```javascript
    const report = ethers.AbiCoder.defaultAbiCoder().encode(
      ['uint8', 'uint256', 'address', 'address[]', 'uint256[]', 'uint256'],
      [0, vaultId, user, collaterals, amounts, sharesToMint]
    );
    ```

- [ ] **Test with Simulation**
  ```bash
  cre workflow simulate
  ```
  - [ ] Simulation runs without errors
  - [ ] Reports are correctly encoded
  - [ ] Vault processes reports successfully
  - [ ] State changes are correct

## Production Transition

When ready to move from testing to production:

- [ ] **Switch to Production Forwarder**
  - [ ] Get production KeystoneForwarder address for your network
  - [ ] See [Forwarder Directory](https://docs.chain.link/cre/guides/workflow/using-evm-client/forwarder-directory)
  - [ ] Option A: Update existing contract
    ```bash
    ./vault-deploy.sh update-forwarder \
      --vault $VAULT_ADDRESS \
      --forwarder 0xF8344CFd5c43616a4366C34E3EEE75af79a74482
    ```
  - [ ] Option B: Deploy new instance
    ```bash
    export USE_MOCK_FORWARDER=false
    forge script script/DeployVault.s.sol:DeployVault \
      --rpc-url $RPC_URL \
      --private-key $PRIVATE_KEY \
      --broadcast \
      -vvv
    ```

- [ ] **Configure Security Validations**
  ```bash
  export VAULT_ADDRESS=0x...
  export WORKFLOW_ID=0x...     # Your production workflow ID
  export WORKFLOW_AUTHOR=0x... # Your address
  
  forge script script/SetupVaultCRE.s.sol:SetupVaultCRE \
    --rpc-url $RPC_URL \
    --private-key $PRIVATE_KEY \
    --broadcast \
    -vvv
  ```
  - [ ] Forwarder updated to production address
  - [ ] Workflow ID configured (if using single workflow)
  - [ ] Workflow author configured (if using multiple workflows)
  - [ ] Status confirmed: `./vault-deploy.sh status --vault $VAULT_ADDRESS`

- [ ] **Deploy CRE Workflow to Production**
  - [ ] Update workflow configuration with production Vault address
  - [ ] Deploy workflow: `cre workflow deploy`
  - [ ] Verify workflow ID matches configured validation

- [ ] **Verify End-to-End**
  - [ ] Workflow executes successfully
  - [ ] Reports are sent to Vault
  - [ ] Vault processes reports correctly
  - [ ] State changes occur as expected

## Post-Deployment

- [ ] **Contract Verification (Optional)**
  ```bash
  export ETHERSCAN_KEY=your_api_key
  export CONTRACT_ADDRESS=$VAULT_ADDRESS
  ./vault-deploy.sh verify
  ```
  - [ ] Contract verified on Etherscan
  - [ ] Source code publicly available

- [ ] **Documentation**
  - [ ] Document Vault contract address
  - [ ] Document workflow ID(s)
  - [ ] Document owner address
  - [ ] Keep emergency contact information for forwarder updates

- [ ] **Monitoring**
  - [ ] Set up monitoring for Vault events
  - [ ] Track report processing
  - [ ] Monitor for failed transactions
  - [ ] Alert on permission violations

- [ ] **Security Review**
  - [ ] Review security configuration
  - [ ] Verify all permission checks are in place
  - [ ] Confirm forwarder address is correct
  - [ ] Audit enabled validation rules

## Troubleshooting

If deployment fails:

- [ ] **Check RPC Connection**
  ```bash
  cast call $VAULT_ADDRESS "owner()" --rpc-url $RPC_URL
  ```

- [ ] **Verify Credentials**
  - [ ] Private key is valid
  - [ ] Account has sufficient ETH
  - [ ] Private key is from correct network

- [ ] **Validate Contract**
  ```bash
  forge build
  ```

- [ ] **Check Forwarder Address**
  - [ ] Use correct forwarder for network
  - [ ] MockForwarder for testing
  - [ ] KeystoneForwarder for production

- [ ] **Review Logs**
  - [ ] Check forge script output for errors
  - [ ] Review transaction receipt on Etherscan
  - [ ] Verify contract code at deployed address

## Security Checklist

- [ ] **Never expose PRIVATE_KEY**
  - [ ] Add `.env` to `.gitignore`
  - [ ] Use `.env.local` for sensitive values
  - [ ] Use secure key management for production

- [ ] **Verify Forwarder Address**
  - [ ] Double-check addresses before deployment
  - [ ] Use official Chainlink documentation sources
  - [ ] Never accept addresses from untrusted sources

- [ ] **Test Permission Validations**
  - [ ] Attempt calls from invalid senders (should fail)
  - [ ] Attempt calls with invalid workflow ID (should fail)
  - [ ] Attempt calls with invalid author (should fail)

- [ ] **Monitor Deployed Contract**
  - [ ] Watch for `SecurityWarning` events
  - [ ] Monitor forwarder updates
  - [ ] Alert on validation failures

## Resources

- **Deployment Guide:** [DEPLOYMENT_GUIDE.md](DEPLOYMENT_GUIDE.md)
- **Scripts README:** [README.md](README.md)
- **CRE Documentation:** https://docs.chain.link/cre
- **Building Consumer Contracts:** https://docs.chain.link/cre/guides/workflow/using-evm-client/onchain-write/building-consumer-contracts
- **Forwarder Directory:** https://docs.chain.link/cre/guides/workflow/using-evm-client/forwarder-directory

---

**Print this checklist and check off items as you progress through deployment.**

Estimated time: 30-60 minutes for complete deployment and testing.
