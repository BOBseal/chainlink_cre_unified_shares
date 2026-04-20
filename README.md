# Chainlink CRE Unified Shares Vault

A sophisticated multi-collateral vault system for managing unified share tokens with Chainlink Automation integration. This repository implements multiple vault architectures: **ERC20-based shares** (`CSE20`), **ERC721-based shares** (`CSE721`), and **ERC1155-based shares** (`CSE1155`), all backed by a central `VaultCore` contract.

## 📋 Table of Contents

- [Overview](#overview)
- [Architecture](#architecture)
- [Core Concepts](#core-concepts)
- [Contract Variants](#contract-variants)
- [Deployment](#deployment)
- [Deposit Flow](#deposit-flow)
- [Withdrawal Flow](#withdrawal-flow)
- [Integration with Chainlink CRE](#integration-with-chainlink-cre)
- [Setup & Installation](#setup--installation)
- [Usage Guide](#usage-guide)
- [API Reference](#api-reference)
- [Security Considerations](#security-considerations)

---

## Overview

This project provides a **multi-collateral vault system** that enables:

- **Unified Share Tokens**: Accept deposits in multiple ERC20 collateral tokens and issue unified share tokens in ERC20, ERC721, or ERC1155 standards
- **Immutable Redemption Ratios**: Lock the original collateral composition at deposit time — redemptions always use the original ratio, regardless of current pool state
- **Chainlink CRE Integration**: Automated deposit and withdrawal orchestration via Chainlink Automation (formerly Keeper Network) with the Chainlink Runtime Environment
- **Three Token Standards**:
  - `CSE20`: ERC20 shares (transferrable like standard tokens)
  - `CSE721`: ERC721 shares (NFT-like, unique token per deposit)
  - `CSE1155`: ERC1155 shares (batch-aware, semi-fungible tokens)
- **Centralized Asset Management**: All assets are held in `VaultCore`, with CSE contracts managing tokenization

### Key Features

✅ **Immutable collateral ratios** locked at deposit  
✅ **Multiple collateral support** (ERC20 tokens)  
✅ **Transferrable shares** with consistent redemption  
✅ **Chainlink CRE integration** for trustless automation  
✅ **Per-user batch tracking** to avoid expensive loops  
✅ **Gas-optimized** mappings & nested structures  
✅ **Modular architecture** with separate tokenization contracts  

---

## Architecture

### System Overview

```
┌─────────────────────────────────────────────────────────────┐
│         Chainlink Automation (CRE)                          │
│   Consensus Layer - Orchestrates Deposits & Withdrawals    │
└──────────────────────┬──────────────────────────────────────┘
                       │
                       │ Signed Reports
                       ▼
┌─────────────────────────────────────────────────────────────┐
│         ReceiverTemplate (Abstract)                         │
│  • Validates forwarder address & workflow identity          │
│  • Decodes metadata (workflowId, owner, name)               │
│  • Routes to _processReport() implementation                │
└──────────────────────┬──────────────────────────────────────┘
                       │
          ┌────────────┴────────────┬────────────┐
          ▼                         ▼            ▼
    ┌──────────────┐         ┌──────────────┐ ┌──────────────┐
    │     CSE20    │         │    CSE721    │ │   CSE1155    │
    │   (ERC20)    │         │   (ERC721)   │ │  (ERC1155)   │
    │Share Tokens  │         │Share Tokens  │ │Share Tokens  │
    └──────────────┘         └──────────────┘ └──────────────┘
         │                        │            │
         └────────────────────────┼────────────┘
                                  ▼
                         ┌──────────────┐
                         │   VaultCore  │
                         │  (Asset      │
                         │   Holder)    │
                         └──────────────┘
                              │
                              ▼
                         ┌──────────────────────────────────┐
                         │ ERC20 Collateral Tokens          │
                         │ (USDC, USDT, DAI, WETH, etc.)    │
                         └──────────────────────────────────┘
```

### Contract Hierarchy

```
                    IReceiver (interface)
                          ▲
                          │
                    ReceiverTemplate
                    (Abstract, Ownable)
                          ▲
         ┌────────────────┴──────────────────┬────────────────┐
         │                                   │                │
        CSE20                             CSE721           CSE1155
    (ERC20, ReceiverTemplate)     (ReceiverTemplate)  (ReceiverTemplate)
         │                                   │                │
         ├─ _mintShares()                   ├─ _mintToken()   ├─ _mintBatch()
         ├─ _withdrawShares()               ├─ _withdrawToken() ├─ _withdrawBatch()
         ├─ _processReport()                ├─ _processReport() ├─ _processReport()
         └─ Events & State                  └─ Events & State └─ Events & State
                                   │
                                   ▼
                              VaultCore
                           (Ownable, SafeERC20)
                              │
                              ├─ deposit()
                              ├─ withdraw()
                              └─ setAllowed()
```

---

## Core Concepts

### 1. Deposit Batches

When a user deposits multiple ERC20 collaterals, a **DepositBatch** struct is created to permanently record:

```solidity
struct DepositBatch {
    address[] collateralTokens;    // E.g., [USDC, WETH, DAI]
    uint256[] collateralAmounts;   // E.g., [1000e6, 10e18, 500e18]
    uint256 sharesMinted;          // Total shares issued for this batch
    uint256 depositTimestamp;      // Immutable record of when deposited
    address initiatingUser;        // Original depositor
}
```

### 2. Immutable Redemption Ratios

Redemption is calculated **per batch** using the **original** collateral composition:

```
Redeemed Amount per Collateral = (SharesToBurn / BatchTotalShares) × OriginalAmount
```

**Example:**
- Deposit batch: 1000 USDC + 10 WETH → 100 shares
- User burns 50 shares → receives: 500 USDC + 5 WETH
- This is true regardless of current vault balances or price movements

### 3. Share Transfer Behavior

- **ERC20 Variant**: Shares transfer like standard ERC20 tokens; recipient can redeem using any batch mixed with shares
- **ERC1155 Variant**: Shares are tokenIds linked to specific batches; transfers are batch-aware

---

## Contract Variants

### VaultCore (Central Asset Holder)

**File**: `src/vaultcore/core.sol`

- Central contract that holds all ERC20 collateral assets
- Uses permissioned access control via `allowed` mapping
- Only allowed contracts can deposit/withdraw assets
- Best for: Centralized asset management and security

**Constructor**:
```solidity
constructor()
```

**Key Methods**:
- `setAllowed(address vault, bool status)` - Grant/revoke vault permissions (owner only)
- `deposit(address from, address token, uint amount)` - Transfer tokens from user to vault
- `withdraw(address to, address token, uint amount)` - Transfer tokens from vault to user

---

### CSE20 (ERC20 Share Tokenization)

**File**: `src/CSE20.sol`

- Issues ERC20 share tokens for multi-collateral deposits
- Supports multiple independent tokenizers (vaults) per deployer
- Each tokenizer has its own share token and collateral configuration
- Best for: Traditional fungible share tokens

**Constructor**:
```solidity
constructor(address _trustedForwarder, address _core)
```

**Key Methods**:
- `deployTokenizer(string name, string symbol, address[] collaterals)` - Create new ERC20 share token
- `setCollaterals(uint256 vaultId, address[] collaterals)` - Update supported collaterals
- `getVaultInfo(uint256 vaultId)` - View vault details
- `getUserTokenizerIds(address user)` - Get user's deployed vaults

---

### CSE721 (ERC721 Share Tokenization)

**File**: `src/CSE721.sol`

- Issues unique ERC721 tokens for each deposit batch
- Each token represents a specific collateral deposit
- Immutable redemption ratios locked per token
- Best for: NFT-like share ownership

**Constructor**:
```solidity
constructor(address _trustedForwarder, address _core, string memory _name, string memory _symbol)
```

**Key Methods**:
- `getDepositToken(uint256 tokenId)` - View deposit details for a token
- `_mintToken(address user, address[] collaterals, uint256[] amounts)` - Internal mint function
- `_withdrawToken(address user, uint256 tokenId, address receiver)` - Internal withdrawal function

---

### CSE1155 (ERC1155 Share Tokenization)

**File**: `src/CSE1155.sol`

- Issues ERC1155 tokens for batch-based share management
- Semi-fungible tokens with batch-specific tracking
- Supports multiple shares per token ID
- Best for: Batch-aware share management

**Constructor**:
```solidity
constructor(address _trustedForwarder, address _core, string memory _uri)
```

**Key Methods**:
- `getBatch(uint256 tokenId)` - View batch details
- `_mintBatch(address user, address[] collaterals, uint256[] amounts, uint256 sharesToMint)` - Internal mint function
- `_withdrawBatch(address user, uint256 tokenId, uint256 sharesToBurn)` - Internal withdrawal function

---

## Deployment

The repository includes a deployment script that deploys all contracts and sets up permissions:

**Script**: `script/Deploy.s.sol`

**Environment Variables** (via `.env`):
- `TRUSTED_FORWARD` - Chainlink forwarder address
- `PRIVATE_KEY` - Deployer private key
- `CSE721_NAME` - ERC721 token name (optional)
- `CSE721_SYMBOL` - ERC721 token symbol (optional)
- `CSE1155_URI` - ERC1155 metadata URI (optional)

**Run Deployment**:
```bash
source .env
forge script script/Deploy.s.sol --broadcast --rpc-url $RPC_URL --private-key $PRIVATE_KEY
```

The script deploys:
1. `VaultCore` - Central asset holder
2. `CSE20` - ERC20 tokenization
3. `CSE721` - ERC721 tokenization  
4. `CSE1155` - ERC1155 tokenization
5. Sets `VaultCore.setAllowed()` for all CSE contracts

## Deposit Flow

### Phase 1: Off-Chain (User → Chainlink CRE)

```
User (Wallet/DApp)
    │
    ├─ Approve collaterals to vault
    │  (USDC.approve(vault, 1000e6))
    │  (WETH.approve(vault, 10e18))
    │
    ├─ Submit deposit request to Chainlink CRE
    │  (via Automation workflow)
    │
    └─ Wait for CRE consensus
```

### Phase 2: On-Chain (Vault Processing)

```
Chainlink Forwarder
    │
    ├─ Verify report signature & metadata
    │  (workflowId, workflowOwner, workflowName)
    │
    ▼
ReceiverTemplate.onReport()
    │
    ├─ Security checks (forwarder, author, workflow name)
    │
    ▼
Vault._processReport()
    │
    ├─ Decode tokenId from report[0:32]
    │  (tokenId == 0 means deposit)
    │
    ├─ Decode (user, collaterals[], amounts[], sharesToMint)
    │
    ├─ Call _validateDeposit() hook (user-customizable)
    │
    ▼
_depositCollaterals()
    │
    ├─ Loop through collaterals:
    │  │
    │  ├─ Transfer collateral from user to vault
    │  │  (IERC20(token).safeTransferFrom(user, vault, amount))
    │  │
    │  └─ Update collateralBalance[token] += amount
    │
    ├─ Create/store DepositBatch
    │
    ├─ Record batch ID for user
    │  (userBatches[user].push(batchId))
    │
    ├─ Mint shares to user
    │  (ERC20: _mint(user, sharesToMint))
    │  (ERC1155: shareToken.mint(user, batchId, sharesToMint))
    │
    └─ Emit DepositProcessed event
```

### Detailed Flow Diagram (ERC20)

```
START: _depositCollaterals()
  │
  ├─ Validate inputs
  │  ├─ user != address(0) ✓
  │  ├─ collaterals.length == amounts.length ✓
  │  ├─ At least 1 collateral ✓
  │  └─ sharesToMint > 0 ✓
  │
  ├─ LOOP: Transfer collaterals
  │  │
  │  ├─ [i=0] USDC: safeTransferFrom(user, vault, 1000e6)
  │  │   └─ collateralBalance[USDC] += 1000e6
  │  │
  │  ├─ [i=1] WETH: safeTransferFrom(user, vault, 10e18)
  │  │   └─ collateralBalance[WETH] += 10e18
  │  │
  │  └─ [i=2] DAI: safeTransferFrom(user, vault, 500e18)
  │      └─ collateralBalance[DAI] += 500e18
  │
  ├─ Create DepositBatch(id=1)
  │  ├─ collateralTokens = [USDC, WETH, DAI]
  │  ├─ collateralAmounts = [1000e6, 10e18, 500e18]
  │  ├─ sharesMinted = 100
  │  ├─ depositTimestamp = block.timestamp
  │  └─ initiatingUser = user
  │
  ├─ userBatches[user].push(1)
  │
  ├─ _mint(user, 100)
  │  └─ User's ERC20 balance += 100
  │
  ├─ totalSharesIssued += 100
  │
  ├─ Emit DepositProcessed(user, 1, [USDC, WETH, DAI], [1000e6, 10e18, 500e18], 100)
  │
  └─ RETURN batchId=1

END
```

---

## Withdrawal Flow

### Phase 1: Off-Chain (User → Chainlink CRE)

```
User (Wallet/DApp)
    │
    ├─ Select batch ID to redeem from
    │  (e.g., batchId = 1)
    │
    ├─ Specify shares to burn
    │  (e.g., 50 shares)
    │
    ├─ Submit withdrawal request
    │
    └─ Wait for CRE consensus
```

### Phase 2: On-Chain (Vault Processing)

```
Chainlink Forwarder
    │
    ├─ Verify report
    │
    ▼
ReceiverTemplate.onReport()
    │
    ├─ Security checks
    │
    ▼
Vault._processReport()
    │
    ├─ Decode tokenId from report[0:32]
    │  (tokenId != 0 means withdrawal)
    │
    ├─ Decode (user, sharesToBurn, receiver)
    │
    ├─ Call _validateWithdrawal() hook
    │
    ▼
_withdrawFromBatch() / _withdrawFromTokenId()
    │
    ├─ Verify user has enough shares
    │
    ├─ Load batch from storage
    │
    ├─ Calculate redemption amounts (per collateral):
    │  │
    │  └─ For each collateral[i]:
    │     amount[i] = (sharesToBurn / batchTotalShares) × originalAmount[i]
    │
    ├─ Burn shares from user
    │
    ├─ Transfer collaterals to receiver
    │
    ├─ Update collateralBalance
    │
    └─ Emit WithdrawalProcessed event
```

### Detailed Flow Diagram (Withdrawal)

```
START: _withdrawFromBatch(user=0xABC..., batchId=1, sharesToBurn=50, receiver=0xXYZ...)
  │
  ├─ Validate inputs
  │  ├─ user != address(0) ✓
  │  ├─ receiver != address(0) ✓
  │  ├─ sharesToBurn > 0 ✓
  │  └─ user.balance[shares] >= 50 ✓
  │
  ├─ Load batch 1 from storage
  │  └─ collaterals = [USDC, WETH, DAI]
  │     amounts = [1000e6, 10e18, 500e18]
  │     sharesMinted = 100
  │
  ├─ LOOP: Calculate redemption amounts
  │  │
  │  ├─ [i=0] USDC: (50 / 100) × 1000e6 = 500e6
  │  │
  │  ├─ [i=1] WETH: (50 / 100) × 10e18 = 5e18
  │  │
  │  └─ [i=2] DAI: (50 / 100) × 500e18 = 250e18
  │
  ├─ _burn(user, 50)
  │  └─ User's ERC20 balance -= 50
  │
  ├─ LOOP: Transfer collaterals to receiver
  │  │
  │  ├─ [i=0] USDC.safeTransfer(receiver, 500e6)
  │  │   └─ collateralBalance[USDC] -= 500e6
  │  │
  │  ├─ [i=1] WETH.safeTransfer(receiver, 5e18)
  │  │   └─ collateralBalance[WETH] -= 5e18
  │  │
  │  └─ [i=2] DAI.safeTransfer(receiver, 250e18)
  │      └─ collateralBalance[DAI] -= 250e18
  │
  ├─ Emit WithdrawalProcessed(user, 50, [USDC, WETH, DAI], [500e6, 5e18, 250e18])
  │
  └─ RETURN ([USDC, WETH, DAI], [500e6, 5e18, 250e18])

END
```

---

## Integration with Chainlink CRE

The CSE contracts are designed to work seamlessly with Chainlink Runtime Environment (CRE) for automated deposit and withdrawal operations. Each CSE contract inherits from `ReceiverTemplate` and implements `_processReport()` to handle CRE-triggered operations.

### RWA Token Contracts

The system uses specialized RWA (Real World Asset) token contracts that implement the **IERC-7943** standard, providing regulatory compliance features:

#### uRWA20 (ERC-20 RWA Tokens)
- **File**: `src/rwa/uRWA20.sol`
- **Standard**: IERC-7943 Fungible
- **Features**: Whitelisting, token freezing, forced transfers
- **Roles**: Admin, Minter, Burner, Freezer, Whitelist, Force Transfer
- **Used by**: CSE20 for share tokenization

#### uRWA721 (ERC-721 RWA Tokens)
- **File**: `src/rwa/uRWA721.sol`
- **Standard**: IERC-7943 Non-Fungible
- **Features**: Whitelisting, token freezing, forced transfers
- **Roles**: Admin, Minter, Burner, Freezer, Whitelist, Force Transfer
- **Used by**: CSE721 for share tokenization

#### uRWA1155 (ERC-1155 RWA Tokens)
- **File**: `src/rwa/uRWA1155.sol`
- **Standard**: IERC-7943 Multi-Token
- **Features**: Whitelisting, token freezing, forced transfers
- **Roles**: Admin, Minter, Burner, Freezer, Whitelist, Force Transfer
- **Used by**: CSE1155 for share tokenization

### CRE Report Processing

Each CSE contract processes CRE reports through the `_processReport()` method. Reports are encoded with action codes and parameters:

#### CSE20 Action Codes
- **Action 1**: Deploy Tokenizer (create new ERC20 share vault)
- **Action 2**: Deposit (mint shares via VaultCore)
- **Action 3**: Withdraw (burn shares and redeem collateral)
- **Action 4**: Operator Call (role changes on RWA tokens)
- **Action 5**: Document Action (add/update/remove documents)

#### CSE721 Action Codes
- **Action 1**: Deposit Mint (create new ERC721 token)
- **Action 2**: Withdraw (burn token and redeem collateral)
- **Action 3**: Operator Call (role changes on RWA tokens)
- **Action 4**: Document Action (add/update/remove documents)

#### CSE1155 Action Codes
- **Action 1**: Deposit Mint (mint ERC1155 shares)
- **Action 2**: Deposit Existing (add to existing batch)
- **Action 3**: Withdraw (burn shares and redeem collateral)
- **Action 4**: Operator Call (role changes on RWA tokens)
- **Action 5**: Document Action (add/update/remove documents)

### Report Encoding Examples (TypeScript/ethers.js)

#### CSE20: Deploy Tokenizer
```typescript
function encodeCSE20DeployTokenizer(
  name: string,
  symbol: string,
  collaterals: string[]
): string {
  const abiCoder = ethers.AbiCoder.defaultAbiCoder();
  return abiCoder.encode(
    ['uint8', 'string', 'string', 'address[]'],
    [1, name, symbol, collaterals]
  );
}
```

#### CSE20: Deposit (Mint Shares)
```typescript
function encodeCSE20Deposit(
  vaultId: bigint,
  user: string,
  collaterals: string[],
  amounts: bigint[],
  sharesToMint: bigint
): string {
  const abiCoder = ethers.AbiCoder.defaultAbiCoder();
  return abiCoder.encode(
    ['uint8', 'uint256', 'address', 'address[]', 'uint256[]', 'uint256'],
    [2, vaultId, user, collaterals, amounts, sharesToMint]
  );
}
```

#### CSE721: Deposit Mint
```typescript
function encodeCSE721DepositMint(
  user: string,
  collaterals: string[],
  amounts: bigint[]
): string {
  const abiCoder = ethers.AbiCoder.defaultAbiCoder();
  return abiCoder.encode(
    ['uint8', 'address', 'address[]', 'uint256[]'],
    [1, user, collaterals, amounts]
  );
}
```

#### CSE1155: Deposit Mint
```typescript
function encodeCSE1155DepositMint(
  user: string,
  collaterals: string[],
  amounts: bigint[],
  sharesToMint: bigint
): string {
  const abiCoder = ethers.AbiCoder.defaultAbiCoder();
  return abiCoder.encode(
    ['uint8', 'address', 'address[]', 'uint256[]', 'uint256'],
    [1, user, collaterals, amounts, sharesToMint]
  );
}
```

### CRE Workflow Integration

1. **User Request**: User submits deposit/withdrawal request to CRE workflow
2. **CRE Validation**: CRE validates request and aggregates oracle reports
3. **Report Generation**: CRE encodes operation parameters into report
4. **Forwarder Call**: CRE calls CSE contract via trusted forwarder
5. **Processing**: CSE contract validates and executes operation
6. **Asset Movement**: VaultCore handles collateral transfers
7. **Token Minting/Burning**: RWA token contracts mint/burn shares

### Security Features

- **Forwarder Verification**: Only accepts calls from configured Chainlink forwarder
- **Action Code Validation**: Ensures operation type is valid
- **Access Control**: RWA tokens use role-based permissions
- **Immutable Ratios**: Deposit ratios locked at creation time
- **Whitelist Enforcement**: RWA tokens can restrict transfers to compliant addresses
- **Freeze Capability**: Tokens can be frozen for regulatory compliance

---

## RWA Token Features (IERC-7943)

The share tokens implement the **IERC-7943** standard for Real World Assets, providing enterprise-grade compliance features:

### Core RWA Features

✅ **Whitelisting**: Restrict token transfers to approved addresses only  
✅ **Token Freezing**: Temporarily lock tokens for compliance reasons  
✅ **Forced Transfers**: Regulatory seizure capabilities  
✅ **Role-Based Access**: Granular permissions for different operations  
✅ **Event Logging**: Comprehensive audit trail for all operations  

### Access Control Roles

| Role | Description | Permissions |
|------|-------------|-------------|
| **DEFAULT_ADMIN_ROLE** | Contract administration | Grant/revoke all roles |
| **MINTER_ROLE** | Token creation | Mint new tokens |
| **BURNER_ROLE** | Token destruction | Burn existing tokens |
| **FREEZING_ROLE** | Compliance freezing | Freeze/unfreeze tokens |
| **WHITELIST_ROLE** | Address management | Add/remove whitelisted addresses |
| **FORCE_TRANSFER_ROLE** | Regulatory actions | Force transfer frozen tokens |

### Compliance Functions

#### Whitelist Management
```solidity
// Add address to whitelist
rwaToken.setWhitelist(account, true);

// Check whitelist status
bool allowed = rwaToken.canTransact(account);
```

#### Token Freezing
```solidity
// Freeze tokens (ERC20)
rwaToken.setFrozenTokens(account, amount);

// Freeze specific token (ERC721)
rwaToken.setFrozenToken(account, tokenId, true);

// Check frozen status
uint256 frozen = rwaToken.getFrozenTokens(account);
```

#### Forced Transfers
```solidity
// Regulatory seizure (requires FORCE_TRANSFER_ROLE)
bool success = rwaToken.forcedTransfer(from, to, amount);
```

### Integration with CSE Contracts

- **CSE20**: Deploys uRWA20 tokens for each tokenizer vault
- **CSE721**: Deploys uRWA721 tokens for unique share ownership
- **CSE1155**: Deploys uRWA1155 tokens for batch-based shares
- **Operator Calls**: CSE contracts can execute role changes and compliance actions via CRE reports

---

## Setup & Installation

### Prerequisites

- **Solidity**: 0.8.20+
- **Foundry**: Latest version
- **Node.js**: 18+
- **Dependencies**: OpenZeppelin Contracts v5.5.0, Forge Std

### Installation

```bash
# Clone repository
git clone https://github.com/yourusername/chainlink_cre_unified_shares.git
cd chainlink_cre_unified_shares

# Install dependencies
forge install

# Build contracts
forge build

# Run tests (if available)
forge test -vv
```

### Project Structure

```
chainlink_cre_unified_shares/
├── src/
│   ├── CSE20.sol                      # ERC20 share tokenization
│   ├── CSE721.sol                     # ERC721 share tokenization
│   ├── CSE1155.sol                    # ERC1155 share tokenization
│   ├── vaultcore/
│   │   └── core.sol                   # Central asset holder (VaultCore)
│   ├── dependencies/
│   │   ├── Receiver.sol               # CRE report receiver template
│   │   └── IReceiver.sol              # CRE receiver interface
│   └── rwa/
│       ├── uRWA20.sol                 # ERC20 RWA token (IERC-7943 compliant)
│       ├── uRWA721.sol                # ERC721 RWA token (IERC-7943 compliant)
│       ├── uRWA1155.sol               # ERC1155 RWA token (IERC-7943 compliant)
│       ├── interfaces/
│       │   └── IERC7943.sol           # RWA token standard interface
│       ├── modules/                   # Modular RWA token components
│       │   ├── erc20/                 # ERC20 RWA modules
│       │   └── erc1155/               # ERC1155 RWA modules
│       └── mocks/                     # Mock contracts for testing
├── script/
│   └── Deploy.s.sol                   # Deployment script for all contracts
├── lib/
│   ├── forge-std/                     # Foundry standard library
│   └── openzeppelin-contracts/        # OpenZeppelin Contracts
├── test/                              # Test files (if any)
├── foundry.toml                       # Foundry configuration
├── .env.example                       # Environment variables template
└── README.md                          # This file
```

---

## Usage Guide

### Environment Setup

1. **Copy environment template:**
   ```bash
   cp .env.example .env
   ```

2. **Configure `.env` file:**
   ```bash
   # Required
   TRUSTED_FORWARD=0xYourChainlinkForwarderAddress
   PRIVATE_KEY=0xYourDeployerPrivateKey
   
   # Optional (defaults provided)
   CSE721_NAME=CSE721 Share Token
   CSE721_SYMBOL=CSE721
   CSE1155_URI=https://example.com/metadata/{id}.json
   
   # Network
   RPC_URL=https://rpc.sepolia.org
   ```

### Deployment

**Deploy all contracts using the script:**
```bash
source .env
forge script script/Deploy.s.sol --broadcast --rpc-url $RPC_URL --private-key $PRIVATE_KEY --verify
```

**Expected output:**
```
VaultCore: 0x...
CSE20: 0x...
CSE721: 0x...
CSE1155: 0x...
```

### Post-Deployment Setup

After deployment, the contracts are automatically configured:
- `VaultCore` permissions are set for all CSE contracts
- CSE contracts reference the deployed `VaultCore`
- Ready for Chainlink CRE integration

### Contract Interaction Examples

#### CSE20 (ERC20 Shares)
```solidity
// Deploy a new ERC20 share token
CSE20 cse20 = CSE20(deployedCSE20Address);
uint256 vaultId = cse20.deployTokenizer("MyShares", "MSHARE", [usdcAddress, wethAddress]);
```

#### CSE721 (ERC721 Shares)  
```solidity
// Mint an ERC721 share token
CSE721 cse721 = CSE721(deployedCSE721Address);
// Call via CRE or directly for testing
```

#### CSE1155 (ERC1155 Shares)
```solidity
// Mint ERC1155 share tokens
CSE1155 cse1155 = CSE1155(deployedCSE1155Address);
// Call via CRE or directly for testing
```
    {}
}
```

### 3. Configure Vault

### Chainlink CRE Integration

The CSE contracts are designed to work with Chainlink Runtime Environment (CRE) for automated deposit and withdrawal operations:

1. **User submits deposit request** to CRE workflow
2. **CRE validates and aggregates** reports from multiple oracles  
3. **CRE calls contract methods** via `_processReport()` with signed data
4. **Contract processes** deposit/withdrawal and mints/burns shares

### Example CRE Report Processing

```solidity
// CRE report format (simplified)
bytes memory report = abi.encode(
    uint8 actionCode,      // 1=deposit, 2=withdraw, etc.
    address user,
    address[] collaterals,
    uint256[] amounts,
    uint256 shares
);

// Contract processes via CRE forwarder
cseContract.processReport(report);
```

---

## API Reference

## API Reference

### VaultCore

#### State Variables

| Name | Type | Visibility | Description |
|------|------|------------|-------------|
| `allowed` | `mapping(address => bool)` | public | Permissioned contracts that can deposit/withdraw |

#### Functions

##### `setAllowed(address vault, bool status)`
- **Access**: `external onlyOwner`
- **Purpose**: Grant/revoke deposit/withdraw permissions

##### `deposit(address from, address token, uint amount)`
- **Access**: `external onlyAllowed`
- **Purpose**: Transfer ERC20 tokens from user to vault

##### `withdraw(address to, address token, uint amount)`
- **Access**: `external onlyAllowed`
- **Purpose**: Transfer ERC20 tokens from vault to user

---

### CSE20 (ERC20 Shares)

#### State Variables

| Name | Type | Visibility | Description |
|------|------|------------|-------------|
| `core` | `VaultCore` | public | Reference to asset holder |
| `tokenizers` | `mapping(uint256 => TokenizerVault)` | public | Vault configurations |
| `tokenizerId` | `uint256` | public | Next vault ID counter |

#### Functions

##### `deployTokenizer(string name, string symbol, address[] collaterals)`
- **Access**: `public`
- **Returns**: `vaultId`
- **Purpose**: Create new ERC20 share token vault

##### `setCollaterals(uint256 vaultId, address[] collaterals)`
- **Access**: `public` (vault deployer only)
- **Purpose**: Update supported collateral tokens

##### `getVaultInfo(uint256 vaultId)`
- **Access**: `public view`
- **Returns**: `(shareToken, deployer, collaterals[], totalShares, isActive)`

##### `getUserTokenizerIds(address user)`
- **Access**: `public view`
- **Returns**: `vaultId[]`

---

### CSE721 (ERC721 Shares)

#### State Variables

| Name | Type | Visibility | Description |
|------|------|------------|-------------|
| `core` | `VaultCore` | public | Reference to asset holder |
| `rwaToken` | `uRWA721` | public | ERC721 token contract |
| `depositTokens` | `mapping(uint256 => DepositToken721)` | public | Token deposit data |

#### Functions

##### `getDepositToken(uint256 tokenId)`
- **Access**: `public view`
- **Returns**: `DepositToken721 struct`

---

### CSE1155 (ERC1155 Shares)

#### State Variables

| Name | Type | Visibility | Description |
|------|------|------------|-------------|
| `core` | `VaultCore` | public | Reference to asset holder |
| `rwaToken` | `uRWA1155Metadata` | public | ERC1155 token contract |
| `depositBatches` | `mapping(uint256 => DepositBatch1155)` | internal | Batch deposit data |

#### Functions

##### `getBatch(uint256 tokenId)`
- **Access**: `public view`
- **Returns**: `DepositBatch1155 struct`

---

## Security Considerations

### 1. **Immutable Ratios**
Once a batch is created, collateral ratios are permanently locked. This prevents:
- Liquidity attacks
- Flash loan exploits
- Price oracle manipulation

### 2. **Access Control**
- Only the **owner** (typically CRE operator) can call deposit/withdrawal
- All state-changing operations validated through `ReceiverTemplate`
- Chainlink Forwarder signature verification mandatory

### 3. **SafeERC20 Usage**
All token transfers use OpenZeppelin's `SafeERC20` to handle:
- Non-standard ERC20 implementations
- Revert-on-failure detection
- Return value validation

### 4. **Reentrancy Protection**
- External calls to ERC20 tokens are made after state updates
- ERC4626-inspired design minimizes reentrancy surface

### 5. **Input Validation**
- Array length mismatches caught with `require()`
- Zero addresses rejected
- Zero amounts rejected
- Batch IDs validated before use

### 6. **Audit Recommendations**
- Consider formal verification for immutable ratio calculations
- Audit `ReceiverTemplate` CRE integration thoroughly
- Test extensively with large collateral arrays (gas limits)
- Validate Chainlink Forwarder address configuration post-deployment

---

## Events

### DepositProcessed
```solidity
event DepositProcessed(
    address indexed user,
    uint256 indexed batchId,        // or tokenId for ERC1155
    address[] collaterals,
    uint256[] amounts,
    uint256 sharesIssued
);
```

### WithdrawalProcessed
```solidity
event WithdrawalProcessed(
    address indexed user,
    uint256 shares,                 // or sharesiBurned
    address[] collaterals,
    uint256[] amounts
);
```

### CollateralAdded
```solidity
event CollateralAdded(address indexed token);
```

---

## Examples

### Example 1: 3-Collateral Deposit (ERC20)

**Scenario**: User deposits 1000 USDC + 10 WETH + 500 DAI

```
Initial State:
  - User USDC balance: 1000e6
  - User WETH balance: 10e18
  - User DAI balance: 500e18

Deposit Request:
  {
    user: "0xAlice",
    collaterals: ["0xUSDC", "0xWETH", "0xDAI"],
    amounts: ["1000e6", "10e18", "500e18"],
    sharesToMint: "100e18"
  }

After Deposit (via CRE):
  - Batch #1 created:
    * collaterals = [USDC, WETH, DAI]
    * amounts = [1000e6, 10e18, 500e18]
    * sharesMinted = 100
    * timestamp = block.timestamp
    * initiatingUser = 0xAlice

  - State Updates:
    * vault.collateralBalance[USDC] += 1000e6
    * vault.collateralBalance[WETH] += 10e18
    * vault.collateralBalance[DAI] += 500e18
    * Alice's share balance += 100

Future Redemption (50 shares):
  - USDC redeemed: (50 / 100) × 1000e6 = 500e6
  - WETH redeemed: (50 / 100) × 10e18 = 5e18
  - DAI redeemed: (50 / 100) × 500e18 = 250e18
  
  Regardless of current vault ratios!
```

### Example 2: ERC1155 Batch Management

```solidity
// Deposit creates tokenId = 1
vault._depositCollaterals(..);  // mints 100 shares of tokenId 1

// User can hold multiple batches
vault._depositCollaterals(..);  // mints 50 shares of tokenId 2
vault._depositCollaterals(..);  // mints 75 shares of tokenId 3

// User's ERC1155 balances:
// - tokenId 1: 100 shares
// - tokenId 2: 50 shares
// - tokenId 3: 75 shares

// Query user's tokenIds:
uint256[] memory tokenIds = vault.getUserBatches(user);
// Returns: [1, 2, 3]
```

---

## Contributing

Contributions are welcome! Please:

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

---

## License

This project is licensed under the **MIT License** — see the LICENSE file for details.

---

## Support

For questions or issues:

- **GitHub Issues**: Open an issue on the repository
- **Email**: Contact the maintainers
- **Discussions**: Use GitHub Discussions for questions

---

## Acknowledgments

- **OpenZeppelin Contracts**: ERC20, ERC1155, Ownable implementations
- **Chainlink Automation**: CRE infrastructure and Forwarder contract
- **Foundry**: Development and testing framework
- **Solmate**: Gas-optimized reference patterns

---

**Last Updated**: February 2026  
**Version**: 1.0.0
