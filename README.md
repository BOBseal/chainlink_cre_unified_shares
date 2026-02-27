# Chainlink CRE Unified Shares Vault

A sophisticated multi-collateral vault system for managing unified share tokens with Chainlink Automation integration. This repository implements two vault architectures: **ERC20-based shares** (`MultiCollateralVault`) and **ERC1155-based shares** (`Alternative1155Vault`).

## 📋 Table of Contents

- [Overview](#overview)
- [Architecture](#architecture)
- [Core Concepts](#core-concepts)
- [Contract Variants](#contract-variants)
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

- **Unified Share Tokens**: Accept deposits in multiple ERC20 collateral tokens and issue a single unified share token
- **Immutable Redemption Ratios**: Lock the original collateral composition at deposit time — redemptions always use the original ratio, regardless of current pool state
- **Chainlink CRE Integration**: Automated deposit and withdrawal orchestration via Chainlink Automation (formerly Keeper Network) with the Chainlink Runtime Environment
- **Two Token Standards**:
  - `MultiCollateralVault`: ERC20 shares (transferrable like standard tokens)
  - `Alternative1155Vault`: ERC1155 shares (batch-aware, per-tokenId tracking)

### Key Features

✅ **Immutable collateral ratios** locked at deposit  
✅ **Multiple collateral support** (ERC20 tokens)  
✅ **Transferrable shares** with consistent redemption  
✅ **Chainlink CRE integration** for trustless automation  
✅ **Per-user batch tracking** to avoid expensive loops  
✅ **Gas-optimized** mappings & nested structures  

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
          ┌────────────┴────────────┐
          ▼                         ▼
    ┌──────────────┐         ┌──────────────┐
    │ERC4626Multi  │         │Alternative   │
    │Collateral    │         │1155Vault     │
    │Vault (ERC20) │         │              │
    │Share Tokens  │         │ERC1155 Share │
    │              │         │TokenIds      │
    └──────────────┘         └──────────────┘
         │                        │
         │ Holds                  │ Holds
         ▼                        ▼
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
         ┌────────────────┴──────────────────┐
         │                                   │
    MultiCollateralVault              Alternative1155Vault
    (ERC20, Ownable, ReceiverTemplate) (ReceiverTemplate)
         │                                   │
         ├─ _depositCollaterals()           ├─ _depositCollaterals()
         ├─ _withdrawFromBatch()            ├─ _withdrawFromTokenId()
         ├─ _processReport()                ├─ ERC1155Shares (nested)
         └─ Events & State                  └─ Events & State
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

### MultiCollateralVault (ERC20 Shares)

**File**: `src/dependencies/MultiCollateralVault.sol`

- Inherits from `ERC20` (`OpenZeppelin`)
- Single unified share token symbol
- Shares are transferrable like any ERC20
- Best for: Simple, traditional multi-asset pools

**Constructor**:
```solidity
constructor(string memory _name, string memory _symbol, address _trustedForwarder)
```

**Key Methods**:
- `_depositCollaterals(address user, address[] collaterals, uint256[] amounts, uint256 sharesToMint)`
- `_withdrawFromBatch(address user, uint256 batchId, uint256 sharesToBurn, address receiver)`
- `getBatchDetails(uint256 batchId)` - View original deposit composition
- `getUserBatches(address user)` - Get all batch IDs for a user

---

### Alternative1155Vault (ERC1155 Shares)

**File**: `src/dependencies/alternative1155.sol`

- Shares are **ERC1155 token IDs**, each mapped to a deposit batch
- Includes nested `ERC1155Shares` contract (owned by vault)
- Best for: NFT-like share ownership, batch-specific tracking

**Constructor**:
```solidity
constructor(string memory _uri, address _trustedForwarder)
```

**Key Methods**:
- `_depositCollaterals(address user, address[] collaterals, uint256[] amounts, uint256 sharesToMint)`
- `_withdrawFromTokenId(address user, uint256 tokenId, uint256 sharesToBurn, address receiver)`
- `shareToken` - Public reference to the `ERC1155Shares` contract

---

### TokenizerFactory (Multi-Vault ERC20 Shares Factory)

**File**: `src/dependencies/TokenizerFactory.sol`

- **Factory Pattern**: Users deploy multiple independent collateralized ERC20 vaults
- Each vault has its own `CollateralBase` share token and custom collateral pools
- Uses **action codes (uint8)** to determine CRE operations
- Best for: Decentralized share creation, multi-pool management

**Constructor**:
```solidity
constructor(address _trustedForwarder)
```

**Key Features**:
- Users deploy their own share tokens with custom collaterals
- Action codes (uint8):
  - `0`: Mint Shares (create new batch deposit)
  - `1`: Deposit Existing (add collateral to existing batch)
  - `2`: Redeem Shares (burn shares and withdraw collateral)
- Batch-based tracking with immutable redemption ratios
- CRE fully controls all operations

**Key Methods**:
- `deployTokenizer(string name, string symbol, address[] collaterals)` - Deploy new vault
- `addCollateral(uint256 vaultId, address collateral)` - Add supported collateral
- `_mintShares(uint256 vaultId, address user, address[] collaterals, uint256[] amounts, uint256 sharesToMint)` - Create new batch
- `_depositToExisting(uint256 vaultId, uint256 batchId, address user, address[] collaterals, uint256[] amounts, uint256 sharesToMint)` - Add to existing batch
- `_redeemShares(uint256 vaultId, uint256 batchId, address user, uint256 sharesToBurn, address receiver)` - Burn and withdraw
- `getBatchDetails(uint256 vaultId, uint256 batchId)` - View batch composition
- `previewRedemption(uint256 vaultId, uint256 batchId, uint256 sharesToBurn)` - Preview collateral return
- `getUserTokenizers(address user)` - Get user's deployed vaults

**CRE Report Format**:

#### Mint Shares (Action Code 0)
```solidity
// Create new batch and mint shares
abi.encode(uint256 vaultId, uint8(0), address user, address[] collaterals, uint256[] amounts, uint256 sharesToMint)
```

#### Deposit Existing (Action Code 1)
```solidity
// Deposit to existing batch maintaining original ratio
abi.encode(uint256 vaultId, uint8(1), uint256 batchId, address user, address[] collaterals, uint256[] amounts, uint256 sharesToMint)
```

#### Redeem Shares (Action Code 2)
```solidity
// Burn shares and withdraw collateral
abi.encode(uint256 vaultId, uint8(2), uint256 batchId, address user, uint256 sharesToBurn, address receiver)
```

---

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
│   ├── Vault.sol                      # Main entry point
│   ├── dependencies/
│   │   ├── MultiCollateralVault.sol   # ERC20-based shares
│   │   ├── Alternative1155Vault.sol   # ERC1155-based shares
│   │   ├── Receiver.sol               # CRE report receiver
│   │   ├── Receiver.sol               # User helper contract
│   │   └── MultiCollateralVaultAlt.sol # Alternative implementation
│   └── interfaces/
│       └── IReceiver.sol               # CRE receiver interface
├── lib/
│   ├── forge-std/                     # Foundry standard library
│   └── openzeppelin-contracts/        # OpenZeppelin Contracts
├── test/                              # Test files (if any)
├── foundry.toml                       # Foundry configuration
└── README.md                          # This file
```

---

## Usage Guide

### 1. Deploy a MultiCollateralVault (ERC20 Shares)

```solidity
pragma solidity ^0.8.20;
import {MultiCollateralVault} from "./src/dependencies/MultiCollateralVault.sol";

contract MyVault is MultiCollateralVault {
    constructor(address _trustedForwarder)
        MultiCollateralVault("Unified Share", "USHARE", _trustedForwarder)
    {}
}
```

**Deployment:**
```bash
forge create src/MyVault.sol:MyVault \
  --constructor-args 0xChainlinkForwarderAddress \
  --rpc-url $RPC_URL \
  --private-key $PRIVATE_KEY
```

### 2. Deploy an Alternative1155Vault (ERC1155 Shares)

```solidity
pragma solidity ^0.8.20;
import {Alternative1155Vault} from "./src/dependencies/alternative1155.sol";

contract MyNFTVault is Alternative1155Vault {
    constructor(address _trustedForwarder)
        Alternative1155Vault("https://api.example.com/metadata/", _trustedForwarder)
    {}
}
```

### 3. Configure Vault

```solidity
// As owner (typically CRE operator)

// Add supported collateral tokens
vault.addCollateral(IERC20(0xUSDC));
vault.addCollateral(IERC20(0xWETH));
vault.addCollateral(IERC20(0xDAI));

// Configure Chainlink CRE validation
vault.setExpectedAuthor(0xCREOperatorAddress);
vault.setExpectedWorkflowId(0xYourWorkflowId);
```

### 4. User Deposits (Off-Chain)

```javascript
// User-side (e.g., smart contract or DApp)

const deposit = {
  user: "0xUserAddress",
  collaterals: ["0xUSDC", "0xWETH", "0xDAI"],
  amounts: ["1000e6", "10e18", "500e18"],
  sharesToMint: "100e18"
};

// Send to Chainlink CRE workflow
// CRE will aggregate reports and trigger vault._processReport()
```

### 5. Query Vault State

```solidity
// View user's batches
uint256[] memory batchIds = vault.getUserBatches(userAddress);

// Get batch details
(
  address[] memory collaterals,
  uint256[] memory amounts,
  uint256 shares,
  uint256 timestamp,
  address depositor
) = vault.getBatchDetails(batchId);

// Preview redemption
(
  address[] memory redeemCollaterals,
  uint256[] memory redeemAmounts
) = vault.previewBatchRedemption(batchId, sharesToBurn);

// Check collateral balance
uint256 usdcBalance = vault.getCollateralBalance(USDC);
```

---

## API Reference

### MultiCollateralVault

#### State Variables

| Name | Type | Visibility | Description |
|------|------|------------|-------------|
| `collateralBalance` | `mapping(address => uint256)` | public | Total held per collateral token |
| `depositBatches` | `mapping(uint256 => DepositBatch)` | public | Batch storage by ID |
| `batchCounter` | `uint256` | public | Next batch ID |
| `userBatches` | `mapping(address => uint256[])` | public | Batches per user |
| `totalSharesIssued` | `uint256` | public | Cumulative shares minted |
| `supportedCollaterals` | `IERC20[]` | public | List of allowed tokens |

#### Functions

##### `addCollateral(IERC20 _token)`
- **Access**: `onlyOwner`
- **Purpose**: Register new collateral token
- **Emits**: `CollateralAdded`

##### `_depositCollaterals(address user, address[] collaterals, uint256[] amounts, uint256 sharesToMint)`
- **Access**: `internal virtual`
- **Purpose**: Process deposit (called by CRE)
- **Returns**: `batchId`

##### `_withdrawFromBatch(address user, uint256 batchId, uint256 sharesToBurn, address receiver)`
- **Access**: `internal virtual`
- **Purpose**: Process withdrawal (called by CRE)
- **Returns**: `(collaterals, amounts)`

##### `getBatchDetails(uint256 batchId)`
- **Access**: `public view`
- **Returns**: `(collaterals[], amounts[], shares, timestamp, depositor)`

##### `getUserBatches(address user)`
- **Access**: `public view`
- **Returns**: `batchId[]`

##### `previewBatchRedemption(uint256 batchId, uint256 sharesToBurn)`
- **Access**: `public view`
- **Returns**: `(collaterals[], amounts[])`

##### `_validateDeposit(address[] collaterals, uint256[] amounts, uint256 sharesToMint)`
- **Access**: `internal view virtual`
- **Purpose**: Override for custom deposit validation

##### `_validateWithdrawal(address user, uint256 batchId, uint256 sharesToBurn)`
- **Access**: `internal view virtual`
- **Purpose**: Override for custom withdrawal validation

---

### Alternative1155Vault

Same as MultiCollateralVault, with these differences:

#### State Variables

| Name | Type | Visibility | Description |
|------|------|------------|-------------|
| `shareToken` | `ERC1155Shares` | public | ERC1155 share token contract |

#### Functions

Identical to `MultiCollateralVault`, except:
- Batches identified by **tokenId** instead of `batchId`
- Share operations use `shareToken.mint()` / `burn()` / `balanceOf()`
- Method names: `_withdrawFromTokenId()` instead of `_withdrawFromBatch()`

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
