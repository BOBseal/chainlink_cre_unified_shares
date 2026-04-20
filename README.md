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

### Report Format

All vault operations are triggered via **Chainlink CRE reports**. The vault's `_processReport()` method decodes reports using a **boolean flag** to determine the operation type.

#### Report Structure
```solidity
// All reports include: isDeposit (bool), tokenId (uint256), and operation-specific parameters
```

#### New Batch Deposit Report
```solidity
// isDeposit = true, tokenId = 0
// abi.encode(true, uint256(0), address user, address[] collaterals, uint256[] amounts, uint256 sharesToMint)
```

#### Deposit to Existing Batch Report
```solidity
// isDeposit = true, tokenId > 0
// abi.encode(true, uint256(tokenId), address user, address[] collaterals, uint256[] amounts, uint256 sharesToMint)
```

#### Withdrawal Report
```solidity
// isDeposit = false, tokenId > 0
// abi.encode(false, uint256(tokenId), address user, uint256 sharesToBurn, address receiver)
```

### Report Encoding Examples (TypeScript/ethers.js)

#### New Batch Deposit
```typescript
import { ethers } from 'ethers';

function encodeNewBatchDeposit(
  user: string,
  collaterals: string[],
  amounts: bigint[],
  sharesToMint: bigint
): string {
  const abiCoder = ethers.AbiCoder.defaultAbiCoder();
  return abiCoder.encode(
    ['bool', 'uint256', 'address', 'address[]', 'uint256[]', 'uint256'],
    [true, 0n, user, collaterals, amounts, sharesToMint]
  );
}

// Example usage:
const report = encodeNewBatchDeposit(
  '0x1234567890123456789012345678901234567890',
  ['0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48', '0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2'],
  [ethers.parseUnits('1000', 6), ethers.parseUnits('10', 18)],
  ethers.parseUnits('100', 18)
);
```

#### Deposit to Existing Batch
```typescript
function encodeDepositToExistingBatch(
  tokenId: bigint,
  user: string,
  collaterals: string[],
  amounts: bigint[],
  sharesToMint: bigint
): string {
  const abiCoder = ethers.AbiCoder.defaultAbiCoder();
  return abiCoder.encode(
    ['bool', 'uint256', 'address', 'address[]', 'uint256[]', 'uint256'],
    [true, tokenId, user, collaterals, amounts, sharesToMint]
  );
}

// Example usage - deposit to batch 2 with same ratio:
const report = encodeDepositToExistingBatch(
  2n,
  '0x1234567890123456789012345678901234567890',
  ['0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48', '0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2'],
  [ethers.parseUnits('1000', 6), ethers.parseUnits('10', 18)],
  ethers.parseUnits('100', 18)
);
```

#### Withdrawal
```typescript
function encodeWithdrawal(
  tokenId: bigint,
  user: string,
  sharesToBurn: bigint,
  receiver: string
): string {
  const abiCoder = ethers.AbiCoder.defaultAbiCoder();
  return abiCoder.encode(
    ['bool', 'uint256', 'address', 'uint256', 'address'],
    [false, tokenId, user, sharesToBurn, receiver]
  );
}

// Example usage - withdraw from batch 2:
const report = encodeWithdrawal(
  2n,
  '0x1234567890123456789012345678901234567890',
  ethers.parseUnits('50', 18),
  '0x0987654321098765432109876543210987654321'
);
```

#### TokenizerFactory Report Encoding (Action Code Pattern)

TokenizerFactory uses action codes (uint8) to determine operations: `0` = MintShares, `1` = DepositExisting, `2` = RedeemShares

```typescript
// ===== TOKENIZER FACTORY ENCODINGS =====

// Action Code 0: Mint Shares (create new batch)
function encodeTokenizerMintShares(
  vaultId: bigint,
  user: string,
  collaterals: string[],
  amounts: bigint[],
  sharesToMint: bigint
): string {
  const abiCoder = ethers.AbiCoder.defaultAbiCoder();
  return abiCoder.encode(
    ['uint256', 'uint8', 'address', 'address[]', 'uint256[]', 'uint256'],
    [vaultId, 0, user, collaterals, amounts, sharesToMint]
  );
}

// Example: Deploy vault, then mint shares
const mintReport = encodeTokenizerMintShares(
  1n, // vaultId
  '0x1234567890123456789012345678901234567890',
  ['0xUsdc', '0xWeth'],
  [ethers.parseUnits('1000', 6), ethers.parseUnits('5', 18)],
  ethers.parseUnits('100', 18)
);

// Action Code 1: Deposit to Existing Batch
function encodeTokenizerDepositExisting(
  vaultId: bigint,
  batchId: bigint,
  user: string,
  collaterals: string[],
  amounts: bigint[],
  sharesToMint: bigint
): string {
  const abiCoder = ethers.AbiCoder.defaultAbiCoder();
  return abiCoder.encode(
    ['uint256', 'uint8', 'uint256', 'address', 'address[]', 'uint256[]', 'uint256'],
    [vaultId, 1, batchId, user, collaterals, amounts, sharesToMint]
  );
}

// Example: Deposit more to existing batch maintaining ratio
const depositExistingReport = encodeTokenizerDepositExisting(
  1n, // vaultId
  1n, // batchId
  '0x1234567890123456789012345678901234567890',
  ['0xUsdc', '0xWeth'],
  [ethers.parseUnits('1000', 6), ethers.parseUnits('5', 18)],
  ethers.parseUnits('100', 18)
);

// Action Code 2: Redeem Shares
function encodeTokenizerRedeemShares(
  vaultId: bigint,
  batchId: bigint,
  user: string,
  sharesToBurn: bigint,
  receiver: string
): string {
  const abiCoder = ethers.AbiCoder.defaultAbiCoder();
  return abiCoder.encode(
    ['uint256', 'uint8', 'uint256', 'address', 'uint256', 'address'],
    [vaultId, 2, batchId, user, sharesToBurn, receiver]
  );
}

// Example: Withdraw from batch
const redeemReport = encodeTokenizerRedeemShares(
  1n, // vaultId
  1n, // batchId
  '0x1234567890123456789012345678901234567890',
  ethers.parseUnits('50', 18),
  '0x0987654321098765432109876543210987654321'
);
```

### Report Processing Logic

The `_processReport()` function determines the operation as follows:

```
┌─ Check isDeposit flag
├─ TRUE (deposit operations)
│  ├─ Check tokenId
│  ├─ tokenId == 0 → New batch deposit (creates new batch)
│  └─ tokenId > 0 → Deposit to existing batch
│
└─ FALSE (withdrawal)
   └─ tokenId > 0 → Withdraw from batch
```

### Metadata Structure

Chainlink Forwarder provides metadata for verification:

```solidity
struct Metadata {
    bytes32 workflowId;      // Unique workflow identifier
    bytes10 workflowName;    // Workflow name (40-bit truncated for gas)
    address workflowOwner;   // Workflow author (CRE operator)
}
```

The vault validates:
1. **Forwarder**: Only accept reports from configured Chainlink Forwarder
2. **Workflow ID**: Optional verification of specific workflow
3. **Workflow Owner**: Optional verification of operator identity
4. **Workflow Name**: Optional name check (requires owner validation)

### Setup Chainlink CRE Integration

```solidity
// During deployment
vault = new MultiCollateralVault("Unified Share", "USHARE", 0xChainlinkForwarderAddress);

// Post-deployment: configure workflow expectations
vault.setExpectedAuthor(0xWorkflowOwnerAddress);
vault.setExpectedWorkflowId(0xWorkflowIdBytes32);
vault.setExpectedWorkflowName("my-workflow");
```

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
│   │   └── core.sol                   # Central asset holder
│   ├── dependencies/
│   │   ├── Receiver.sol               # CRE report receiver template
│   │   └── IReceiver.sol              # CRE receiver interface
│   └── rwa/
│       ├── uRWA20.sol                 # ERC20 RWA token implementation
│       ├── uRWA721.sol                # ERC721 RWA token implementation
│       └── uRWA1155.sol               # ERC1155 RWA token implementation
├── script/
│   └── Deploy.s.sol                   # Deployment script
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
