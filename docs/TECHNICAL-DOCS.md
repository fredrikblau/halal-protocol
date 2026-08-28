# HALAL DAO - TECHNICAL DOCUMENTATION

**Version**: 1.1.0
**Date**: August 24, 2026
**Network**: Arbitrum (Sepolia & Mainnet)
**Status**: Unaudited reference implementation | 196 tests passing (185 unit/configuration + 11 invariants) | Not production-ready

---

## Table of Contents

1. [Contract Overview](#contract-overview)
2. [Architecture & Design](#architecture--design)
3. [Deployment Instructions](#deployment-instructions)
4. [Governance Parameters](#governance-parameters)
5. [Security Specifications](#security-specifications)
6. [API Reference](#api-reference)
7. [Testing & Verification](#testing--verification)
8. [Mainnet Checklist](#mainnet-checklist)

---

## Contract Overview

### 5 Core First-Party Smart Contracts

The contracts are separate, immutable-by-design modules under `contracts/src/`:

#### 1. **HalalToken.sol** - Governance Token
- **Type**: ERC20 with Voting Rights
- **Genesis supply**: 10M HLC (fixed allocation; PSM issuance is additional and reserve-backed)
- **Distribution**: 6M team vesting + 4M treasury vesting
- **Features**:
  - ERC20Votes (snapshot-based voting)
  - ERC20Permit (gas-less approvals)
  - AccessControl (MINTER_ROLE and accounting-aware BURNER_ROLE)
  - Only the PSM or another DAO-approved accounting module may burn HLC; public self-burn is
    intentionally disabled so redemption credit cannot be stranded.

#### 2. **HalalVesting.sol** - Vesting Wallet
- **Type**: Custom linear vesting contract with optional revocation
- **Instances**: 2 (team + treasury)
- **Features**:
  - Team: 6M HLC, 4-year vesting, 1-year cliff
  - Treasury: 4M HLC, 3-year vesting
  - Revoke capability (DAO only)
  - Multi-sig beneficiaries

#### 3. **HalalPSM.sol** - Peg Stability Module
- **Type**: Oracle-Driven Stablecoin
- **Peg**: 1 HLC ≈ 1 reserve unit at the current CPI-adjusted rate
- **Features**:
  - DAI ↔ HLC conversions
  - Bounded `UPDATER_ROLE` CPI submissions; an oracle integration is deployment work
  - Monthly CPI adjustments
  - Emergency manual override
  - Rate bounds (0.1 to 2.0)

#### 4. **HalalDAO.sol** - Governance Governor
- **Type**: OpenZeppelin Governor
- **Features**:
  - Voting with HLC tokens
  - Snapshot-based (prevents flash loans)
  - Timelock integration (2-day delay)
  - Multi-target proposals
  - Chain-dependent voting period (about one week on Arbitrum by default; configure per chain)
  - 4% quorum requirement

#### 5. **HalalTimelock.sol** - Execution Delay
- **Type**: TimelockController
- **Delay**: 2 days (172,800 seconds)
- **Features**:
  - Safety window for community
  - Exit time if unpopular
  - No admin bypass

### Optional integration module: `CPIReportAdapter.sol`

The optional adapter uses EIP-712 signatures and a configurable quorum before forwarding a report
to `HalalPSM`. It is not part of the five-contract core deployment. See
[`docs/CPI-ADAPTER-SPEC.md`](CPI-ADAPTER-SPEC.md) for its trust assumptions and deployment review.
  - Integrates with Governor

---

## Architecture & Design

### System Diagram

```
┌─────────────────────────────────────────────────┐
│         HLC TOKEN HOLDERS (Voting Power)        │
└──────────────────┬──────────────────────────────┘
                   │
                   ↓
         ┌─────────────────────┐
         │   HalalDAO Governor │
         │  (OpenZeppelin DAO) │
         └──────────┬──────────┘
                    │
         ┌──────────┴──────────┐
         ↓                     ↓
    ┌─────────────┐    ┌──────────────┐
    │ HalalDAO    │    │Timelock      │
    │ Voting      │    │2-day delay   │
    │ (configured) │    │(execution)   │
    └──────┬──────┘    └───────┬──────┘
           │                   │
           └───────────────────┤
                               ↓
           ┌─────────────────────────────┐
           │  Protocol Contract Targets  │
           ├─────────────────────────────┤
           │ • HalalToken (mint)         │
           │ • HalalPSM (CPI update)     │
           │ • Vesting (revoke)          │
           │ • Any future contracts      │
           └─────────────────────────────┘
```

### Proposal Lifecycle

```
1. PROPOSE (no fixed duration)
   └─→ Create proposal with: targets, values, calldatas, description
   └─→ Snapshot voting power at block N-1
   └─→ State: PENDING

2. VOTING (chain-dependent; about one week on Arbitrum by default)
   └─→ HLC holders vote FOR/AGAINST/ABSTAIN
   └─→ Voting power = balance at snapshot block
   └─→ State: ACTIVE

3. VOTING ENDS (at the configured end block)
   └─→ Check: for > against? votes ≥ 4%?
   └─→ If YES → State: SUCCEEDED
   └─→ If NO → State: DEFEATED

4. QUEUE (if SUCCEEDED)
   └─→ Send to timelock
   └─→ 2-day countdown starts
   └─→ State: QUEUED

5. SAFETY WINDOW (2 days)
   └─→ Community can review
   └─→ Holders can migrate if unpopular
   └─→ No execution possible yet

6. EXECUTE (after the 2-day default timelock delay)
   └─→ Call function on target contract
   └─→ Protocol parameter updated
   └─→ State: EXECUTED

Total Timeline: voting period configured for the target chain + 2 days delay
```

---

## Deployment Instructions

For the operational acceptance, monitoring, updater rotation, and incident procedures that follow
deployment, see [`OPERATOR-RUNBOOK.md`](OPERATOR-RUNBOOK.md).

### Prerequisites

```bash
# 1. Install Foundry
curl -L https://foundry.paradigm.xyz | bash && source ~/.bashrc

# 2. Clone repository & install dependencies
git clone https://github.com/fredrikblau/halal-protocol.git
cd halal-protocol/contracts
forge install

# 3. Create .env file
cat > .env << 'EOF'
PRIVATE_KEY=0x<your_deployer_private_key>
RPC_URL=https://sepolia.arbitrum.io/rpc
EXPECTED_CHAIN_ID=421614
RESERVE_TOKEN=0x<existing_reserve_token_address>
TEAM_BENEFICIARY=0x<team_multisig_address>
TREASURY_BENEFICIARY=0x<treasury_multisig_address>
# Optional: a reviewed oracle relayer to receive UPDATER_ROLE at deployment
CPI_UPDATER=0x<oracle_relayer_or_consumer_address>
EOF
```

### Arbitrum Sepolia Testnet Deployment

```bash
# 1. Test locally
forge test -vvv
# Expected: 196/196 tests passing ✓

# 2. Fund wallet with testnet ETH on Arbitrum Sepolia
# Visit: https://sepoliafaucet.com

# 3. Deploy all contracts
forge script script/Deploy.s.sol:DeployHalalSystem \
  --rpc-url $RPC_URL \
  --private-key $PRIVATE_KEY \
  --broadcast

# 4. Independently verify wiring (read-only; do not use --broadcast)
RPC_URL="$RPC_URL" EXPECTED_CHAIN_ID=421614 TIMELOCK=0x<timelock> TOKEN=0x<token> TEAM_VESTING=0x<team_vesting> \
TREASURY_VESTING=0x<treasury_vesting> DAO=0x<dao> PSM=0x<psm> \
RESERVE_TOKEN=0x<reserve_token> TEAM_BENEFICIARY=0x<team_multisig> \
TREASURY_BENEFICIARY=0x<treasury_multisig> DEPLOYER_ADDRESS=0x<deployer> \
../scripts/verify-deployment.sh

# 5. Verify on Arbiscan
# Visit: https://sepolia.arbiscan.io
# Check each contract address from deploy output
```

The verifier compares each vesting contract's immutable `totalAllocation` and vesting policy with
the token's declared team or treasury allocation, so operators can rerun it after legitimate
vesting releases.

### Expected Deploy Output

```
HalalTimelock:       0xABC...123
HalalToken (HLC):    0xDEF...456
Team Vesting:        0xGHI...789
Treasury Vesting:    0xJKL...012
HalalDAO:            0xMNO...345
HalalPSM:            0xPQR...678

All roles transferred to the DAO. Deployer retains zero privileged access.
PSM has PARAM_ROLE granted to the DAO only. Set `CPI_UPDATER` during deployment to bootstrap a
reviewed oracle relayer directly; otherwise grant `UPDATER_ROLE` via governance before relying on
`updateCPI()`.
```

### Mainnet Deployment

```bash
# Same as testnet, but update .env:
RPC_URL=https://arb1.arbitrum.io/rpc

# Then run:
forge script script/Deploy.s.sol:DeployHalalSystem \
  --rpc-url $RPC_URL \
  --private-key $PRIVATE_KEY \
  --broadcast
```

---

## Governance Parameters

### Voting Configuration

| Parameter | Value | Arbitrum Mainnet | Reasoning |
|-----------|-------|------------------|-----------|
| Voting Delay | 1 block | chain-dependent | Immediate voting start |
| Voting Period | 2,419,200 blocks on Arbitrum; 50,400 elsewhere | ~1 week on Arbitrum at 250ms blocks | Override after checking the target chain's observed cadence |
| Proposal Threshold | 100 HLC | 100 HLC | Prevents spam proposals |
| Quorum | 4% | 400,000 HLC | Low bar for participation |
| Timelock Delay | 2 days | 172,800 seconds | Safety window |

### Block Time Calculations (Arbitrum)

```
Arbitrum L2 blocks are much faster than Ethereum L1 blocks. At an approximate 0.25-second cadence,
50,400 blocks is only about 3.5 hours, which is too short for a default governance review window.
For approximately one week on Arbitrum, use:
1 week = 604,800 seconds
604,800 / 0.25 = 2,419,200 blocks

The deployment script selects 2,419,200 automatically on Arbitrum One and Arbitrum Sepolia. Set
`VOTING_PERIOD_BLOCKS` explicitly when deploying to another chain or when the observed cadence differs.
```

### Corrected Parameters for Arbitrum

```solidity
// Deployment value on Arbitrum (the script selects this automatically):
GovernorSettings(
    1,              // 1 block voting delay (~0.25s)
    2_419_200,      // ~1 week (604,800s / 0.25s per block)
    100e18          // 100 HLC proposal threshold
)
GovernorVotesQuorumFraction(4)  // 4% quorum
```

### DAO Powers (What Can Be Voted On)

#### 1. Update CPI Rate
```solidity
dao.propose(
    [psm],
    [0],
    [psm.mockCPI(newCPI)],
    "Apply a governance-approved CPI override"
)
```
**Effect**: Applies a DAO-approved manual override within the 0.1–2.0 bounds. Routine reports use
`updateCPIWithTimestamp(reportedCPI, reportedAt)` from a separately granted `UPDATER_ROLE` account
and are rate, cadence, reserve-adequacy, freshness, and replay limited. The original
`updateCPI(reportedCPI)` remains available for compatibility.

#### 2. Switch CPI Source
```solidity
dao.propose(
    [psm],
    [0],
    [psm.setSource(newJavaScript)],
    "Switch to China CPI tracking"
)
```
**Effect**: Changes oracle data source (US CPI → China CPI, etc.)

#### 3. Grant a Module Minting Permission
```solidity
dao.propose(
    [token],
    [0],
    [token.grantRole(token.MINTER_ROLE(), module)],
    "Authorize a reviewed HLC minter module"
)
```
**Effect**: Authorizes the named module to mint HLC. The default timelock is not granted
`MINTER_ROLE`, so this proposal does not itself create tokens.

#### 4. Revoke Team Vesting
```solidity
dao.propose(
    [teamVesting],
    [0],
    [teamVesting.revoke()],
    "EMERGENCY: Revoke team vesting"
)
```
**Effect**: Returns unvested tokens to DAO treasury (very high bar to pass)

#### 5. Release Treasury Vesting (permissionless)
```solidity
treasuryVesting.release()
```
**Caller**: Anyone. **Effect**: vested tokens are sent to the configured treasury beneficiary;
the caller cannot redirect them. A DAO proposal is not required.

#### 6. Adjust Parameters (Future Deployment)

The current `HalalDAO` deployment uses non-upgradeable Governor settings. Changing the voting
delay, voting period, proposal threshold, or quorum requires deploying and wiring a new DAO.

---

## Security Specifications

### Access Control Matrix

| Contract | Function | Caller | Via |
|----------|----------|--------|-----|
| HalalToken | `mint()` | PSM / DAO | MINTER_ROLE |
| HalalToken | `burn()` | BURNER_ROLE module | Accounting-aware claim retirement |
| HalalToken | `transfer()` | Anyone | ERC20 balance ownership |
| HalalPSM | `updateCPI(uint256)` | UPDATER_ROLE relayer | Compatibility path; role granted by governance |
| HalalPSM | `updateCPIWithTimestamp(uint256,uint256)` | UPDATER_ROLE relayer | Preferred freshness/replay-protected path |
| HalalPSM | `setSource()` | DAO | Proposal |
| HalalPSM | `depositWithMinHlcOut(uint256,uint256)` | Anyone | Public, slippage-bounded |
| HalalPSM | `withdrawWithMinReserveOut(uint256,uint256)` | Anyone | Public, slippage-bounded |
| HalalPSM | `depositWithMinHlcOutAndDeadline(uint256,uint256,uint256)` | Anyone | Public, slippage- and deadline-bounded; preferred for new integrations |
| HalalPSM | `withdrawWithMinReserveOutAndDeadline(uint256,uint256,uint256)` | Anyone | Public, slippage- and deadline-bounded; preferred for new integrations |
| HalalPSM | `depositWithPermit(uint256,uint256,uint256,uint8,bytes32,bytes32)` | Anyone | EIP-2612 reserve approval + bounded deposit; reserve token must support permits |
| HalalPSM | `withdrawWithPermit(uint256,uint256,uint256,uint8,bytes32,bytes32)` | Anyone | EIP-2612 HLC approval + bounded withdrawal |
| HalalPSM | `transferRedeemable(address,uint256)` | Anyone | Moves PSM HLC and its redemption credit atomically |
| HalalPSM | `transferRedeemableWithPermit(address,uint256,uint256,uint8,bytes32,bytes32)` | Anyone | EIP-2612 HLC approval + atomic credit transfer |
| HalalPSM | `cancelRedeemable(uint256)` | Anyone | Irreversibly burns HLC and retires matching credit |
| HalalPSM | `cancelRedeemableWithPermit(uint256,uint256,uint8,bytes32,bytes32)` | Anyone | EIP-2612 HLC approval + irreversible claim retirement |
| HalalPSM | `depositReserve()` | DAO | Proposal |
| HalalPSM | `withdrawReserve(address,uint256)` | DAO | Proposal; only reserve surplus |
| HalalPSM | `setMinUpdateInterval(uint256)` | DAO | Proposal; value must be positive |
| HalalVesting | `release()` | Anyone | Tokens always go to the beneficiary |
| HalalVesting | `revoke()` | DAO | Proposal |
| HalalDAO | `propose()` | 100+ HLC | Voting |
| HalalDAO | `castVote()` | HLC holder | Voting |
| HalalDAO | `queue()` | Anyone | State |
| HalalDAO | `execute()` | Anyone | State |

### Security Features

#### 1. No Centralized Admin
✓ All contracts owned by DAO (not person)
✓ No owner backdoor functions
✓ All privileged changes require governance vote
✓ 2-day delay prevents instant attacks

#### 2. Snapshot Voting
✓ Voting power = balance at block N-1
✓ Prevents flash loan attacks
✓ Prevents front-running
✓ Enables delegation

#### 3. Timelock Protection
✓ 2-day delay before execution
✓ Community can respond to unpopular proposals
✓ Allows migration if governance captured
✓ No admin bypass possible

#### 4. Oracle Safety
✓ Bounded CPI updater role; oracle integration must be deployed and governed
✓ Rate bounds prevent outliers (0.1 to 2.0)
✓ Manual override (`mockCPI`) for emergencies
✓ Can switch data sources via vote

#### 5. Vesting Safety
✓ Multi-sig beneficiaries (not single person)
✓ Cliff prevents instant token release
✓ Revoke function for emergencies
✓ Treasury controlled by multisig

### Known Risks & Mitigations

| Risk | Mitigation |
|------|-----------|
| **Flash Loan Attack** | Snapshot voting at block N-1 blocks these |
| **Governance Capture** | 2-day timelock allows exit for community |
| **Low Participation** | 4% quorum is intentionally low to encourage voting |
| **Instant Changes** | No possible without 2-day delay |
| **Oracle Failure** | Manual override via `mockCPI()` + can switch source |
| **Governance Capture** | Timelock provides notice, but cannot prevent a captured DAO from executing valid proposals |
| **Reentrancy** | No callbacks, safe transfer patterns only |

---

## API Reference

### HalalToken

```solidity
// Read-only
function balanceOf(address account) external view returns (uint256)
function totalSupply() external view returns (uint256)
function allowance(address owner, address spender) external view returns (uint256)
function getVotes(address account) external view returns (uint256)
function getPastVotes(address account, uint256 blockNumber) external view returns (uint256)
function MINTER_ROLE() external view returns (bytes32)
function BURNER_ROLE() external view returns (bytes32)

// State-changing
function transfer(address to, uint256 amount) external returns (bool)
function approve(address spender, uint256 amount) external returns (bool)
function transferFrom(address from, address to, uint256 amount) external returns (bool)
function permit(address owner, address spender, uint256 value, uint256 deadline, uint8 v, bytes32 r, bytes32 s) external
function mint(address to, uint256 amount) external onlyRole(MINTER_ROLE)
function burn(uint256 amount) external onlyRole(BURNER_ROLE)
```

### HalalPSM

```solidity
// Read-only
function cpiRate() external view returns (uint256)
function previousCPI() external view returns (uint256)
function reserveRequired() external view returns (uint256)
function reserveSurplus() external view returns (int256)
function redeemableBalance(address account) external view returns (uint256)
function previewDeposit(uint256 reserveAmount) external view returns (uint256)
function previewWithdraw(uint256 hlcAmount) external view returns (uint256)

// State-changing
function depositWithMinHlcOut(uint256 reserveAmount, uint256 minHlcOut) external
function withdrawWithMinReserveOut(uint256 hlcAmount, uint256 minReserveOut) external
function depositWithMinHlcOutAndDeadline(uint256 reserveAmount, uint256 minHlcOut, uint256 deadline) external
function withdrawWithMinReserveOutAndDeadline(uint256 hlcAmount, uint256 minReserveOut, uint256 deadline) external
function depositWithPermit(uint256 reserveAmount, uint256 minHlcOut, uint256 deadline, uint8 v, bytes32 r, bytes32 s) external
function withdrawWithPermit(uint256 hlcAmount, uint256 minReserveOut, uint256 deadline, uint8 v, bytes32 r, bytes32 s) external
function transferRedeemable(address to, uint256 hlcAmount) external
function transferRedeemableWithPermit(address to, uint256 hlcAmount, uint256 deadline, uint8 v, bytes32 r, bytes32 s) external
function cancelRedeemable(uint256 hlcAmount) external // Burns HLC; returns no reserve
function cancelRedeemableWithPermit(uint256 hlcAmount, uint256 deadline, uint8 v, bytes32 r, bytes32 s) external // Permit + burn; returns no reserve
// `deposit(uint256)` and `withdraw(uint256)` remain as unbounded compatibility methods.
function depositReserve(uint256 amount) external onlyRole(PARAM_ROLE)
function withdrawReserve(address to, uint256 amount) external onlyRole(PARAM_ROLE)
function updateCPI(uint256 reportedCPI) external onlyRole(UPDATER_ROLE)
function updateCPIWithTimestamp(uint256 reportedCPI, uint256 reportedAt) external onlyRole(UPDATER_ROLE)
// Rejects future, replayed, and reports older than MAX_REPORT_AGE (90 days).
function setSource(string calldata newSource) external onlyRole(PARAM_ROLE)
function setMinUpdateInterval(uint256 newInterval) external onlyRole(PARAM_ROLE) // Must be > 0
function mockCPI(uint256 newCPI) external onlyRole(PARAM_ROLE)  // Manual emergency override
```

### HalalDAO

```solidity
// Read-only
function proposalThreshold() external view returns (uint256)  // 100 HLC
function votingDelay() external view returns (uint256)  // 1 block
function votingPeriod() external view returns (uint256)  // chain-specific deployment value
function quorumNumerator() external view returns (uint256)  // 4%
function state(uint256 proposalId) external view returns (ProposalState)
function proposalSnapshot(uint256 proposalId) external view returns (uint256)

// State-changing
function propose(address[] targets, uint256[] values, bytes[] calldatas, string description) external returns (uint256)
function castVote(uint256 proposalId, uint8 support) external  // 1=FOR, 0=AGAINST, 2=ABSTAIN
function castVoteWithReason(uint256 proposalId, uint8 support, string reason) external
function castVoteBySig(uint256 proposalId, uint8 support, uint8 v, bytes32 r, bytes32 s) external
function queue(address[] targets, uint256[] values, bytes[] calldatas, bytes32 descriptionHash) external
function execute(address[] targets, uint256[] values, bytes[] calldatas, bytes32 descriptionHash) external
```

---

## Testing & Verification

The stateful PSM properties and their deliberate scope are documented in
[`INVARIANTS.md`](INVARIANTS.md). Run them separately with
`forge test --match-path test/HalalPSMInvariant.t.sol` when reviewing accounting changes.

### Run Test Suite

```bash
# Run all tests
forge test -vvv

# Run specific test
forge test --match test_FullProposalFlow -vv

# With gas report
forge build --gas-report

# Coverage
forge coverage
```

### Expected Test Results

```
✓ test_InitialState
✓ test_VestingInitialized
✓ test_CreateProposal_UpdateCPI
✓ test_CreateProposal_GrantMinterRole
✓ test_CastVote_For
✓ test_FullProposalFlow
✓ test_DAO_ControlsPSM_AfterTakeover
✓ test_TimelockPreventsImmediateExecution
✓ test_TeamVestingRevocable
✓ test_TreasuryVestingNonRevocable
✓ 185 unit/configuration tests plus 11 stateful PSM invariants covering the core contracts, governance flows, and adversarial reserve boundaries

Total: 196 tests passing ✓
```

### Verify on Arbiscan

1. Visit: `https://sepolia.arbiscan.io/address/0xYOUR_DAO_ADDRESS`
2. Click "Contract" tab
3. Verify:
   - ✓ DAO/timelock roles are held by the expected contracts (not your wallet)
   - ✓ Verified source and deployed bytecode match the intended contract
   - ✓ Voting parameters and proposal flow are active

---

## Mainnet Checklist

### Before Deployment

- [ ] All 196 tests passing locally, including the stateful invariants
- [ ] Gas estimates reviewed & acceptable
- [ ] No compiler warnings
- [ ] Code review completed
- [ ] Architecture reviewed
- [ ] Independent security audit completed and published

### Sepolia Testing

- [ ] Deploy to Arbitrum Sepolia testnet
- [ ] Verify all 6 contracts on Arbiscan
- [ ] Create first proposal (e.g., mock CPI)
- [ ] Vote on proposal (need 100+ HLC)
- [ ] Wait the configured voting period (or use `vm.roll` in test)
- [ ] Queue in timelock (2 days)
- [ ] Execute proposal (verify it worked)
- [ ] Test PSM: deposit DAI → receive HLC
- [ ] Test PSM: withdraw HLC → receive DAI

### Before Mainnet

- [ ] Team multisig addresses verified
- [ ] Treasury multisig addresses verified
- [ ] Chainlink Functions subscription created & funded
- [ ] DAI reserves prepared (recommend 2M DAI minimum)
- [ ] Community aware of governance launch
- [ ] Discord/Telegram governance channel created
- [ ] Documentation finalized
- [ ] Governance announcement prepared

### Mainnet Deployment

```bash
# Update .env for mainnet
RPC_URL=https://arb1.arbitrum.io/rpc

# Deploy
forge script script/Deploy.s.sol:DeployHalalSystem \
  --rpc-url $RPC_URL \
  --private-key $PRIVATE_KEY \
  --broadcast

# Verify
# Visit: https://arbiscan.io
# Check each contract (should auto-verify)
```

### Post-Deployment

- [ ] Announce DAO is live
- [ ] Create first governance proposal
- [ ] Start community discussion
- [ ] Monitor for issues
- [ ] Update frontend/UI with DAO links
- [ ] Begin regular CPI updates (monthly)

---

## File Structure

```
contracts/
├── src/ (five core contracts plus the optional CPI report adapter)
├── script/ (deployment and proposal examples)
└── test/ (Foundry tests and mocks)

app/
└── src/ (Next.js dApp)

docs/
├── DAO-Guide.md (governance guide)
├── Architecture.md (system reference)
├── WHITEPAPER.md (protocol rationale)
└── DESIGN-DECISIONS.md (implementation deviations)
```

---

## Quick Command Reference

```bash
# Compile
forge build

# Test
forge test -vvv

# Deploy to Arbitrum Sepolia
forge script Deploy.s.sol:DeployHalalSystem \
  --rpc-url https://sepolia.arbitrum.io/rpc \
  --private-key $PRIVATE_KEY \
  --broadcast

# Deploy to Mainnet
forge script Deploy.s.sol:DeployHalalSystem \
  --rpc-url https://arb1.arbitrum.io/rpc \
  --private-key $PRIVATE_KEY \
  --broadcast

# Create proposal
forge script Examples.s.sol:ExampleProposal_UpdateCPI \
  --rpc-url $RPC_URL \
  --private-key $PRIVATE_KEY \
  --broadcast

# Gas report
forge build --gas-report

# Coverage
forge coverage
```

---

## Production Deployment Timeline

```
Day 1:     Deploy to Arbitrum Sepolia, test locally
Day 2-3:   Manual proposal cycle testing
Day 4-7:   Community feedback & security review
Day 8:     Final preparations
Day 9:     Deploy to Arbitrum mainnet
Day 10+:   Live DAO governance 🚀
```

---

## Support & Documentation

- **Code**: See `contracts/src/` for implementation details
- **Tests**: See `contracts/test/` for usage examples and invariants
- **Deployment**: Follow `contracts/script/Deploy.s.sol`
- **Governance**: See `docs/DAO-Guide.md` for the complete guide
- **Reference**: See `docs/Architecture.md` for system diagrams

---

## Version Info

```
Version: 1.1.0
Date: August 24, 2026
Network: Arbitrum (Sepolia & Mainnet targets)
Solidity: ^0.8.24
Foundry: Latest
Status: Unaudited reference implementation; not production-ready
Tests: 97 (All Passing)
Security: No independent audit completed
```

---

**Status**: Unaudited reference implementation; do not use with meaningful funds until the launch
checklist and independent security review are complete.
