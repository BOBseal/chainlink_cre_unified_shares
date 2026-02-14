# MultiCollateralVaultAlt (alt.sol) - Comprehensive Documentation

## Overview

The `alt.sol` contract implements an enhanced multi-collateral vault system with advanced user-wise batch tracking and automatic share transfer batch rehashing. This contract builds upon the foundational `MultiCollateralVault.sol` with significant architectural improvements for better user isolation, transfer safety, and gas efficiency.

**Contract Name:** `MultiCollateralVaultAlt`  
**File Location:** `src/dependencies/alt.sol`  
**Inherits From:** `ERC20`, `Ownable`, `ReceiverTemplate`  
**License:** MIT

---

## Key Architectural Improvements

### 1. **Hashed Batch ID System**

#### Traditional Approach (MultiCollateralVault)
- Sequential batch IDs using a counter: `batchCounter = 1, 2, 3, ...`
- No relationship between batch ID and its content
- Batch discovery requires iteration through all historic batches

#### Enhanced Approach (alt.sol)
- **Deterministic Hashing:** Batch IDs are generated as `keccak256` hashes of:
  - User address
  - Collateral token addresses
  - Collateral deposit amounts
  
```solidity
batchHash = keccak256(abi.encode(_user, _collaterals, _amounts))
```

**Benefits:**
- Same deposits by same user generate same batch hash (idempotency)
- Batch ID inherently encodes its composition
- Reduces storage requirements (bytes32 vs uint256 counter)
- Enables efficient batch lookup without enumeration
- Deterministic for off-chain verification

---

### 2. **User-Wise Batch Tracking**

#### Traditional Approach
```solidity
mapping(uint256 => DepositBatch) public depositBatches;  // Global registry
mapping(address => uint256[]) public userBatches;         // User pointer
```
**Issue:** All batches stored globally, user must reference by index into array

#### Enhanced Approach
```solidity
mapping(address => mapping(bytes32 => DepositBatch)) public userDepositBatches;
mapping(address => bytes32[]) public userBatchHashes;
```

**Structure:**
```
User1 Address
  └── BatchHash1 -> DepositBatch {collaterals, amounts, shares}
  └── BatchHash2 -> DepositBatch {collaterals, amounts, shares}
  └── BatchHash3 -> DepositBatch {collaterals, amounts, shares}

User2 Address
  └── BatchHash4 -> DepositBatch {collaterals, amounts, shares}
  └── BatchHash5 -> DepositBatch {collaterals, amounts, shares}
```

**Benefits:**
- Complete isolation between users' batches
- Direct access without enumeration: `userDepositBatches[user][batchHash]`
- Privacy: One user cannot inspect another's batch details
- Prevents cross-user batch ID collisions
- Enables concurrent deposits by multiple users

---

### 3. **Automatic Share Transfer Batch Rehashing**

#### The Problem
When Alice transfers shares to Bob, the original batch link is lost:
- Bob receives shares but doesn't know their original collateral composition
- Bob cannot withdraw with the original ratio
- Share transfers break the immutability contract

#### The Solution: `_update` Override (OpenZeppelin v5.5.0+)

The contract overrides the `_update` hook, which is called by `transfer()`, `transferFrom()`, `_mint()`, and `_burn()` in modern OpenZeppelin ERC20 implementations.

When shares are transferred from user A to user B:

**Step 1: Capture Balance Before Transfer**
```solidity
uint256 senderBalanceBeforeTransfer = balanceOf(from);
```

**Step 2: Calculate Proportional Distribution**
```
For each batch that sender has:
  - Shares transferred = (amount × senderBatchShares) / senderBalanceBeforeTransfer
  - Proportional collaterals = (shares transferred / batch shares) × original amounts
```

**Step 3: Generate New Batch Hash for Receiver**
```solidity
newBatchHash = keccak256(abi.encode(receiver, collaterals, proportionalAmounts))
```

**Step 4: Update Ledgers and Call Super**
- Create/update receiver's batch with new hash
- Calculate and store proportional collateral amounts
- Update sender's batch (reduce shares and collaterals)
- Call `super._update()` to execute the actual token transfer
- Emit rehash event for transparency

**Example Flow:**
```
Alice's Batch:
├─ DAI: 1000
├─ USDC: 500
└─ Shares: 100

Alice transfers 50 shares to Bob:

Alice's Updated Batch:
├─ DAI: 500 (50% reduction)
├─ USDC: 250 (50% reduction)
└─ Shares: 50

Bob's New Batch (rehashed):
├─ DAI: 500 (proportional)
├─ USDC: 250 (proportional)
└─ Shares: 50
```

---

## State Management & Data Structures

### Core Mappings

#### 1. DepositBatch Structure
```solidity
struct DepositBatch {
    bytes32 collateralHash;         // Hash identifier of collaterals
    mapping(address => uint256) collateralAmounts;  // Per-token amounts
    uint256 sharesMinted;           // Shares in this batch
    uint256 depositTimestamp;       // Deposit timestamp
    uint256 collateralCount;        // Number of unique collaterals
}
```

**Why per-token mappings?**
- Dynamic collateral allocation without array overhead
- O(1) access to specific token amounts
- Reduces memory operations during transfers
- Gas-efficient batch rebalancing

#### 2. User Batch Tracking
```solidity
// Direct batch lookup: user -> batchHash -> batch details
mapping(address => mapping(bytes32 => DepositBatch)) public userDepositBatches;

// User's batch enumeration list
mapping(address => bytes32[]) public userBatchHashes;

// Batch collateral membership
mapping(address => mapping(bytes32 => address[])) public userBatchCollateralTokens;

// Quick membership check
mapping(bytes32 => mapping(address => bool)) public batchCollaterals;
```

#### 3. Collateral Management
```solidity
// Global collateral tracking
mapping(address => uint256) public collateralBalance;

// Supported collateral registry (uses mapping for O(1) lookup)
mapping(address => bool) public supportedCollateralsMap;
address[] public supportedCollateralsList;
```

---

## Core Functions

### Deposit Flow: `_depositCollaterals()`

**Called by:** CRE (Chainlink Runtime Environment) via `_processReport()`  
**Access:** Internal, triggered only via verified reports

**Process:**
```
1. Validate inputs (non-zero user, matching array lengths, positive amounts)
2. Transfer collaterals from user to vault
3. Update global collateral balance tracking
4. Generate deterministic batch hash:
   - keccak256(abi.encode(user, collaterals, amounts))
5. Create user-specific DepositBatch structure
   - Store collateral amounts in per-token mappings
   - Record deposit timestamp and collateral count
6. Register batch hash in userBatchHashes[user]
7. Mint ERC20 shares to user
8. Update totalSharesIssued counter
9. Emit DepositProcessed event
```

**Return Value:** `bytes32 batchHash`

---

### Withdrawal Flow: `_withdrawFromBatch()`

**Called by:** CRE via `_processReport()`  
**Access:** Internal, requires valid batch hash

**Process:**
```
1. Validate inputs (valid user, receiver, burn amount, balance check)
2. Retrieve batch details: userDepositBatches[user][batchHash]
3. Calculate redemption amounts per collateral:
   - For each collateral in batch:
   - amount = (sharesToBurn / batchTotalShares) × originalAmount
4. Burn shares from user
5. Transfer collaterals to receiver
6. Update global collateral balances
7. Emit WithdrawalProcessed event
```

**Key Property:** Redemption is based on **original batch composition**, not current vault state

---

### Share Transfer Batch Rehashing: `_beforeTokenTransfer()`

**Triggered By:** Standard ERC20 transfers (transfer, transferFrom)  
**Scope:** Only for wallet-to-wallet transfers (skips mints/burns)

**Detailed Process:**

```solidity
function _beforeTokenTransfer(address from, address to, uint256 amount)

For each source batch from sender:
  
  A. Calculate Transfer Proportion:
     - sharesToTransfer = (amount × batchShares) / (senderBalance + amount)
     - This distributes shares pro-rata across all sender's batches
  
  B. Calculate Proportional Collaterals:
     For each collateral in sender's batch:
       - transferAmount = (sharesToTransfer × originalAmount) / batchShares
  
  C. Generate Receiver's New Batch Hash:
     - newHash = keccak256(abi.encode(receiver, collaterals, proportionalAmounts))
     - This ensures receiver's batch is distinct from sender's
  
  D. Update Receiver's Batch:
     - Create or fetch: userDepositBatches[receiver][newHash]
     - Add proportional amounts to receiver's collateralAmounts[token]
     - Register batch hash in userBatchHashes[receiver]
     - Update batch metadata (timestamp, count)
  
  E. Update Sender's Batch:
     - Reduce sharesMinted by sharesToTransfer
     - Reduce each collateralAmount[token] by proportional amount
     - Batch remains active if shares > 0
  
  F. Emit Event:
     - ShareTransferWithBatchRehash(from, to, amount, fromHash, toHash)
```

**Critical Property:** The receiver's batch operations are **isolated** from the sender's

---

## Collateral Management

### Adding Supported Collaterals
```solidity
function addCollateral(IERC20 _token) public onlyOwner
```

**Access:** Owner only (CRE)  
**Validation:** Prevents duplicate collateral registration  
**Storage:** Updated in both mapping and list for O(1) and enumeration support

### Retrieving Collaterals
```solidity
// Get all supported collateral addresses
function getSupportedCollaterals() public view returns (address[])

// Get count
function collateralCount() public view returns (uint256)
```

---

## Batch Query Functions

### 1. Get Batch Details
```solidity
function getBatchDetails(address _user, bytes32 _batchHash)
  returns (address[] collaterals, uint256[] amounts, uint256 shares, uint256 timestamp)
```

**Returns:**
- Collateral token addresses in batch
- Original deposit amounts per token
- Total shares minted
- Deposit timestamp

### 2. Get User's All Batch Hashes
```solidity
function getUserBatchHashes(address _user) returns (bytes32[])
```

Allows enumeration of all batches for a user.

### 3. Get Batch Count
```solidity
function getUserBatchCount(address _user) returns (uint256)
```

Quick way to check number of active batches without array iteration.

### 4. Preview Redemption
```solidity
function previewBatchRedemption(address _user, bytes32 _batchHash, uint256 _sharesToBurn)
  returns (address[] collaterals, uint256[] amounts)
```

**Purpose:** Off-chain preview of exact collaterals and amounts before withdrawal  
**No state changes** - safe to call from frontend

---

## Event Emissions

### 1. DepositProcessed
```solidity
event DepositProcessed(
    address indexed user,
    bytes32 indexed batchHash,
    address[] collaterals,
    uint256[] amounts,
    uint256 sharesIssued
)
```
**When:** New deposit batch created  
**Indexing:** User and batch hash for filtering

### 2. WithdrawalProcessed
```solidity
event WithdrawalProcessed(
    address indexed user,
    bytes32 indexed batchHash,
    uint256 shares,
    address[] collaterals,
    uint256[] amounts
)
```
**When:** Shares redeemed from batch  
**Includes:** Actual collaterals and amounts distributed

### 3. ShareTransferWithBatchRehash
```solidity
event ShareTransferWithBatchRehash(
    address indexed from,
    address indexed to,
    uint256 shares,
    bytes32 fromBatchHash,
    bytes32 toBatchHash
)
```
**When:** Shares transferred between wallets with batch rehashing  
**Tracks:** Original batch hash and receiver's new batch hash

### 4. CollateralAdded
```solidity
event CollateralAdded(address indexed token)
```
**When:** New collateral type registered  
**Impact:** Affects future deposit eligibility

---

## Report Processing & CRE Integration

### Report Format

The contract processes two types of CRE reports via `_processReport()`:

#### Type 1: Deposit Report (batchHash = 0)
```solidity
abi.encode(
    uint256(0),           // Indicator: 0 = deposit
    address user,         // Recipient of shares
    address[] collaterals,// Token addresses to deposit
    uint256[] amounts,    // Amounts per token
    uint256 sharesToMint  // Shares to issue
)
```

#### Type 2: Redemption Report (batchHash ≠ 0)
```solidity
abi.encode(
    bytes32 batchHash,    // User's batch to redeem from
    address user,         // Share holder burning shares
    uint256 sharesToBurn, // Shares to burn
    address receiver      // Collateral recipient
)
```

### Validation Hooks

The contract provides override hooks for custom validation:

```solidity
function _validateDeposit(
    address[] memory _collaterals,
    uint256[] memory _amounts,
    uint256 _sharesToMint
) internal view virtual {}

function _validateWithdrawal(
    address _user,
    bytes32 _batchHash,
    uint256 _sharesToBurn
) internal view virtual {}
```

**Use Cases:**
- Enforce minimum deposit amounts
- Verify authorized collateral combinations
- Rate limiting or quota checks
- Cross-chain state verification

---

## Gas Efficiency Considerations

### 1. **Mapping-Based Storage**
- Uses mappings instead of arrays where possible
- O(1) access instead of O(n) iteration
- Reduced storage overhead

### 2. **Hashed Batch IDs**
- bytes32 hashing vs. uint256 counters
- Saves slot space compared to storing full collateral arrays

### 3. **No Duplicate User Registration**
```solidity
bool batchExists = false;
for (uint256 i = 0; i < userBatches.length; ++i) {
    if (userBatches[i] == batchHash) {
        batchExists = true;
        break;
    }
}
if (!batchExists) {
    userBatchHashes[_user].push(batchHash);
}
```
Prevents storing same batch hash multiple times

### 4. **SafeERC20 Usage**
Uses battle-tested SafeERC20 for secure token transfers with revert protection.

---

## Security Considerations

### 1. **Immutable Original Ratios**
- Original deposit amounts stored in `collateralAmounts` mapping
- Never modified during transfers or after deposit
- Ensures fair redemption regardless of vault state changes

### 2. **User Isolation**
- User-wise batch tracking prevents cross-user interference
- Each batch hash is unique per user
- No shared state between different users' batches

### 3. **Share Balance Verification**
```solidity
require(balanceOf(_user) >= _sharesToBurn, "Insufficient share balance");
```
Prevents over-redemption through ERC20 balance check

### 4. **Access Control**
- All state-changing operations protected by `onlyOwner` or CRE report verification
- Deposits and withdrawals only via CRE consensus
- Collateral additions only by owner

### 5. **Safe Transfer Hooks**
- `_beforeTokenTransfer()` processes before state changes
- No reentrancy risk due to internal-only state updates
- SafeERC20 prevents token callback exploits

---

## Comparison: alt.sol vs. MultiCollateralVault.sol

| Feature | MultiCollateralVault | alt.sol |
|---------|----------------------|---------|
| **Batch ID Type** | Sequential uint256 | Hashed bytes32 |
| **Batch Storage** | Global mapping | User-wise nested mapping |
| **Batch Lookup** | O(n) enumeration | O(1) direct access |
| **Share Transfers** | No special handling | Auto-rehashing w/ proportional distribution |
| **Transfer Transparency** | No event on transfer | ShareTransferWithBatchRehash event |
| **User Privacy** | All batches visible | Isolated per-user batches |
| **Gas Efficiency** | Standard arrays | Optimized mappings |
| **Collateral Tracking** | Arrays in struct | Per-token mappings |
| **Idempotency** | Different hash each time | Same inputs → same hash |

---

## Migration Guide

### From MultiCollateralVault to alt.sol

**Breaking Changes:**
1. **Batch ID format:** `uint256` → `bytes32`
2. **Batch lookup:** `depositBatches[id]` → `userDepositBatches[user][hash]`
3. **User batch retrieval:** `userBatches[user]` → `userBatchHashes[user]`
4. **Report payload:** First uint256 → First bytes32

**Gradual Migration:**
- Deploy alt.sol alongside MultiCollateralVault
- New deposits use alt.sol
- Old vault remains for legacy batch access
- Users can opt-in to migration by transferring shares

---

## Example Usage Flows

### Flow 1: Complete Deposit & Withdrawal

```
1. User Alice approves 1000 DAI, 500 USDC to vault
2. CRE generates deposit report (batchHash=0)
3. Alice receives 100 shares
   └─ Batch created with hash: keccak256(Alice, [DAI, USDC], [1000, 500])
4. Alice later calls transfer to send 50 shares to Bob
   └─ System creates: keccak256(Bob, [DAI, USDC], [500, 250])
   └─ Bob now has 50 shares redeemable for DAI:500, USDC:250
5. Bob calls withdraw with 50 shares, gets DAI:500, USDC:250
```

### Flow 2: Multi-Batch Accumulation

```
1. Alice deposits: [DAI:1000, USDC:500] → Batch1 (hash: H1), 100 shares
2. Alice deposits: [DAI:500, USDC:250] → Batch2 (hash: H2), 50 shares
3. Alice transfers 75 shares to Charlie
   └─ 50 shares from Batch1 → Charlie Batch1 (hash: H1')
   └─ 25 shares from Batch2 → Charlie Batch2 (hash: H2')
4. Charlie now has two batches with proportional collaterals
```

### Flow 3: Batch Query for UI

```
1. Frontend calls: getUserBatchHashes(alice)
   └─ Returns: [0xabc..., 0xdef...]
2. For each hash, call: getBatchDetails(alice, hash)
   └─ Returns: collaterals, amounts, shares, timestamp
3. User can preview any withdrawal: previewBatchRedemption(alice, hash, sharesToBurn)
```

---

## Future Enhancements

1. **Batch Metadata:** Store custom data (swap providers, fees, notes)
2. **Tiered Ownership:** Multiple CRE instances with different permissions
3. **Batch Merging:** Combine multiple batches into one
4. **Batch Splitting:** Partition a batch for partial transfers
5. **Collateral Rebalancing:** Update batch composition for fee optimization
6. **Governance:** Decentralized collateral management

---

## Conclusion

The `MultiCollateralVaultAlt` contract provides a robust, user-centric approach to multi-collateral vault management with:

- **Deterministic Hashing:** Immutable batch identity tied to composition
- **User Isolation:** Complete separation of batch tracking by user
- **Automatic Transfer Rehashing:** Seamless share transfers with collateral preservation
- **Gas Efficiency:** Mapping-based storage and O(1) lookups
- **CRE Integration:** Full compatibility with Chainlink Runtime Environment

This makes it ideal for scenarios requiring complex multi-asset management, fair distribution across transfers, and privacy-aware user batch tracking.
