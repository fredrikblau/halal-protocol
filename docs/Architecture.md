# Halal DAO: Complete Architecture & Integration Reference

![Halal DAO governance workflow](governance_flow.svg)

## Five-minute contributor map

If this repository is new to you, follow one value-and-control path before reading the full
reference below. Start a disposable system with `./scripts/local-demo.sh` (or run `make app-smoke`
for a non-interactive check), then use these files as the map:

| Stage | What happens | Start with |
| --- | --- | --- |
| 1. Reserve deposit | A user deposits the configured reserve asset into the PSM; the PSM mints HLC and records the redeemable claim. | [`HalalPSM.sol`](../contracts/src/HalalPSM.sol), [`HalalPSM.t.sol`](../contracts/test/HalalPSM.t.sol) |
| 2. CPI report | An updater or signed adapter submits a bounded, fresh CPI report; the PSM accepts it only when its replay, cadence, and reserve-health checks pass. | [`CPIReportAdapter.sol`](../contracts/src/CPIReportAdapter.sol), [`CPI-ADAPTER-SPEC.md`](CPI-ADAPTER-SPEC.md) |
| 3. Redemption | A holder withdraws reserve against HLC or retires a matching redeemable claim; ordinary HLC transfers intentionally do not transfer PSM claim ownership. | [`HalalPSM.sol`](../contracts/src/HalalPSM.sol), [`Treasury.md`](Treasury.md) |
| 4. Governance | HLC voting power moves a proposal through Governor, quorum, queue, and the timelock before privileged protocol state changes. | [`HalalDAO.sol`](../contracts/src/HalalDAO.sol), [`DAO-Guide.md`](DAO-Guide.md) |
| 5. Operations and UI | Read-only scripts and the Next.js app expose wiring, CPI freshness, reserve coverage, adapter alignment, and deployment evidence. | [`check-deployment-health.sh`](../scripts/check-deployment-health.sh), [`app/src/app/health`](../app/src/app/health), [`OPERATOR-RUNBOOK.md`](OPERATOR-RUNBOOK.md) |

For a focused first contribution, choose a path in [`CONTRIBUTOR-MAP.md`](CONTRIBUTOR-MAP.md), run
the smallest relevant test, and read [`DESIGN-DECISIONS.md`](DESIGN-DECISIONS.md) before assuming
that a planning document describes current behavior. Solidity changes require extra review because
the reference contracts are immutable and unaudited; security findings belong in the private
reporting process in [`SECURITY.md`](../SECURITY.md).

## System Architecture Diagram

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                          HALAL GOVERNANCE SYSTEM                            │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  ┌──────────────────────┐                                                   │
│  │   HLC Token Holders  │  (Voting Power)                                   │
│  └──────────┬───────────┘                                                   │
│             │                                                               │
│             ├─→ Own HLC (snapshot-based voting)                             │
│             ├─→ Can propose (100 HLC minimum)                              │
│             └─→ Can vote FOR/AGAINST/ABSTAIN                               │
│                                                                             │
│  ┌──────────────────────────────────────────────────────────┐               │
│  │              PROPOSAL LIFECYCLE                          │               │
│  ├──────────────────────────────────────────────────────────┤               │
│  │                                                          │               │
│  │  1. PENDING (1 block)                                   │               │
│  │     └─→ Voting snapshot at block N                      │               │
│  │                                                          │               │
│  │  2. ACTIVE (chain-dependent / ~1 week on Arbitrum)     │               │
│  │     └─→ HLC holders vote                                │               │
│  │     └─→ Quorum: 4% of supply                           │               │
│  │                                                          │               │
│  │  3. SUCCEEDED (if for > against)                        │               │
│  │     └─→ Can queue in timelock                           │               │
│  │                                                          │               │
│  │  4. QUEUED (2 days / timelock delay)                    │               │
│  │     └─→ Proposal locked for safety review               │               │
│  │     └─→ Community can exit if unpopular                 │               │
│  │                                                          │               │
│  │  5. EXECUTED (after timelock)                           │               │
│  │     └─→ Function called on target contract              │               │
│  │     └─→ Protocol parameter updated                      │               │
│  │                                                          │               │
│  └──────────────────────────────────────────────────────────┘               │
│                                                                             │
│  ┌──────────────────────────────────────────────────────────┐               │
│  │        DAO CONTROLS THESE CONTRACTS                      │               │
│  ├──────────────────────────────────────────────────────────┤               │
│  │                                                          │               │
│  │  ✓ HalalToken (HLC)                                     │               │
│  │    ├─→ Can mint (for incentives, if voted)             │               │
│  │    ├─→ PSM-controlled accounting-aware burn              │               │
│  │    └─→ Privileged roles: Timelock/DAO                  │               │
│  │                                                          │               │
│  │  ✓ HalalPSM (Peg Stability Module)                      │               │
│  │    ├─→ Updater role submits bounded CPI readings       │               │
│  │    ├─→ DAO controls source and manual overrides        │               │
│  │    ├─→ DAO controls reserve top-ups/withdrawals        │               │
│  │    └─→ No owner shortcut or upgrade path               │               │
│  │                                                          │               │
│  │  ✓ Team Vesting (6M HLC)                                │               │
│  │    ├─→ 4-year vesting with 1-year cliff                │               │
│  │    ├─→ DAO can revoke through governance               │               │
│  │    └─→ DAO may revoke unvested team tokens             │               │
│  │                                                          │               │
│  │  ✓ Treasury Vesting (4M HLC)                            │               │
│  │    ├─→ 3-year vesting                                  │               │
│  │    ├─→ Treasury can claim vested tokens                │               │
│  │    └─→ DAO is the vesting contract's control address   │               │
│  │                                                          │               │
│  └──────────────────────────────────────────────────────────┘               │
│                                                                             │
│  ┌──────────────────────────────────────────────────────────┐               │
│  │        GOVERNANCE SMART CONTRACTS                        │               │
│  ├──────────────────────────────────────────────────────────┤               │
│  │                                                          │               │
│  │  HalalDAO.sol (Governor)                                │               │
│  │  ├─→ OpenZeppelin Governor implementation               │               │
│  │  ├─→ ERC20Votes (snapshot-based voting)                │               │
│  │  ├─→ GovernorSettings (params: delay, period, etc)     │               │
│  │  ├─→ GovernorCountingSimple (FOR/AGAINST/ABSTAIN)      │               │
│  │  ├─→ GovernorTimelockControl (2-day delay)             │               │
│  │  └─→ Functions:                                         │               │
│  │      ├─ propose()      → Create proposal                │               │
│  │      ├─ castVote()     → Vote                            │               │
│  │      ├─ queue()        → Send to timelock                │               │
│  │      └─ execute()      → Execute after timelock         │               │
│  │                                                          │               │
│  │  HalalTimelock.sol (2-day Executor)                     │               │
│  │  ├─→ TimelockController (2 days / 172,800 sec)         │               │
│  │  ├─→ Prevents instant changes                           │               │
│  │  ├─→ Functions:                                         │               │
│  │      ├─ schedule()  → Add to timelock                    │               │
│  │      ├─ execute()   → Execute after delay                │               │
│  │      └─ cancel()    → Only if a canceller role is        │               │
│  │                      explicitly granted                  │               │
│  │  └─→ Final deployment grants no canceller/guardian role  │               │
│  │                                                          │               │
│  └──────────────────────────────────────────────────────────┘               │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## Contract Call Flow: "Update CPI" Proposal

```
Step 1: PROPOSE (by 100+ HLC holder)
┌─────────────────────────────────────────────┐
│ dao.propose(                                │
│   targets: [PSM],                          │
│   values: [0],                             │
│   calldatas: [psm.mockCPI(newCPI)],       │
│   description: "Update CPI"                │
│ )                                          │
└────────┬────────────────────────────────────┘
         │
         ↓ Proposal created with snapshot of voting power
         
Step 2: VOTE (1 block to configured period)
┌─────────────────────────────────────────────┐
│ dao.castVote(                               │
│   proposalId: 1,                           │
│   support: 1  // 1=FOR, 0=AGAINST, 2=ABSTAIN│
│ )                                          │
└────────┬────────────────────────────────────┘
         │
         ↓ Votes aggregated by ERC20Votes
         ↓ After the configured period, check: for > against AND votes ≥ 4%?
         
Step 3: QUEUE (if SUCCEEDED)
┌─────────────────────────────────────────────┐
│ dao.queue(                                  │
│   targets, values, calldatas, descriptionHash│
│ )                                          │
└────────┬────────────────────────────────────┘
         │
         ↓ Transferred to HalalTimelock.sol
         ↓ Starts 2-day countdown
         
Step 4: EXECUTE (after 2 days)
┌─────────────────────────────────────────────┐
│ dao.execute(                                │
│   targets, values, calldatas, descriptionHash│
│ )                                          │
└────────┬────────────────────────────────────┘
         │
         ↓ Timelock executes: psm.mockCPI(newCPI)
         ↓ PSM rate updated through a DAO-approved manual override
         ↓ Proposal moves to EXECUTED state

Result: CPI rate is updated; the purchasing-power target changes subject to oracle quality and reserve health.
```

---

## Access Control Matrix

| Function | Called By | Through |
|----------|-----------|---------|
| **HalalToken** | | |
| `mint()` | PSM and governance-approved modules | MINTER_ROLE; the default DAO/timelock is not itself a minter |
| `burn()` | PSM or DAO-approved accounting module | BURNER_ROLE |
| `transfer()` | Anyone | ERC20 balance ownership |
| **HalalPSM** | | |
| `updateCPI(uint256)` | UPDATER_ROLE relayer | Compatibility path; governance grants role |
| `updateCPIWithTimestamp(uint256,uint256)` | UPDATER_ROLE relayer | Preferred freshness/replay-protected path |
| `setSource()` | DAO only | Proposal vote |
| `depositWithMinHlcOut(uint256,uint256)` | Anyone | Slippage-bounded public function |
| `withdrawWithMinReserveOut(uint256,uint256)` | Anyone | Slippage-bounded public function |
| `depositWithMinHlcOutAndDeadline(uint256,uint256,uint256)` | Anyone | Slippage- and deadline-bounded; preferred for new integrations |
| `withdrawWithMinReserveOutAndDeadline(uint256,uint256,uint256)` | Anyone | Slippage- and deadline-bounded; preferred for new integrations |
| `transferRedeemable(address,uint256)` | Anyone | Atomic HLC + redemption-credit transfer |
| `cancelRedeemable(uint256)` | Anyone | Burns HLC and retires matching redemption credit |
| `cancelRedeemableWithPermit(uint256,uint256,uint8,bytes32,bytes32)` | Anyone | EIP-2612 HLC approval + claim retirement |
| `depositReserve()` | DAO only | Proposal vote |
| `withdrawReserve(address,uint256)` | DAO only | Proposal vote; surplus only |
| `setMinUpdateInterval(uint256)` | DAO only | Proposal vote; positive interval |
| `mockCPI(uint256)` | DAO only | Emergency/manual override |
| **Team Vesting** | | |
| `release()` | Anyone | Beneficiary's tokens |
| `revoke()` | DAO only | Proposal vote |
| **Treasury Vesting** | | |
| `release()` | Anyone | Beneficiary's tokens |
| `revoke()` | DAO only | Proposal vote |
| **HalalDAO** | | |
| `propose()` | 100+ HLC | Anyone |
| `castVote()` | Any HLC holder | Voting power |
| `queue()` | Anyone | State=SUCCEEDED |
| `execute()` | Anyone | State=QUEUED + 2 days |

---

## Test Coverage Summary

```
Foundry test suite (199 tests: 183 unit/configuration + 16 stateful invariants)

✓ Initialization Tests
  ├─ test_InitialState                    → 10M HLC in vesting
  ├─ test_VestingInitialized              → Correct durations
  └─ test_TokenHasVotes                   → ERC20Votes working

✓ Proposal Creation Tests
  ├─ test_CreateProposal_UpdateCPI        → Valid proposal
  ├─ test_CreateProposal_GrantMinterRole   → Role change through governance
  ├─ test_FailProposal_BelowThreshold     → 50 HLC < 100 threshold
  └─ test_MultiTargetProposal             → 2+ targets

✓ Voting Tests
  ├─ test_CastVote_For                    → Vote FOR
  ├─ test_CastVote_Against                → Vote AGAINST
  ├─ test_CastVote_Abstain                → Vote ABSTAIN
  ├─ test_CastVote_Duplicate              → Revert on double vote
  └─ test_VotingPeriod                    → Voting window

✓ Execution Tests
  ├─ test_FullProposalFlow                → Create→Vote→Queue→Execute
  ├─ test_ProposalState_Transitions       → PENDING→ACTIVE→SUCCEEDED→QUEUED→EXECUTED
  ├─ test_TimelockPreventsImmediateExecution → Can't execute before 2 days
  └─ test_TimelockDelay                   → Exact 2-day delay

✓ DAO Control Tests
  ├─ test_DAO_ControlsPSM_AfterTakeover   → PSM functions via vote
  ├─ test_DAO_ControlsToken               → Can mint via vote
  ├─ test_DAO_ControlsVesting             → Can revoke via vote
  └─ role-wiring tests                     → Privileged roles handed to timelock/DAO

✓ Governance Parameter Tests
  ├─ test_ProposalThreshold               → 100 HLC
  ├─ test_Quorum                          → 4%
  ├─ test_VotingDelay                     → 1 block
  ├─ test_VotingPeriod                    → configured deployment value
  └─ test_TimelockDelay                   → 172,800 seconds (2 days)

✓ Edge Cases
  ├─ test_ZeroVotes                       → Proposal fails below quorum
  ├─ test_ProposalCancellation            → Can cancel before execution
  ├─ test_VotingPowerSnapshot             → Snapshot prevents front-running
  └─ test_EmergencyExecute                → Can revoke if needed
```

---

## Deployment Gas Estimates

Based on `forge build --gas-report`:

| Contract | Deploy Gas | Notes |
|----------|-----------|-------|
| HalalToken | ~780,000 | ERC20 + Votes |
| HalalVesting | ~220,000 | Per wallet |
| HalalPSM | see `forge snapshot` | CPI updater role and DAO controls |
| HalalDAO | ~650,000 | Governor + overrides |
| HalalTimelock | ~480,000 | TimelockController |
| **Total** | **~3M gas** | ≈ $30-50 USD on Arbitrum |

---

## Files Generated

| File | Size | Purpose |
|------|------|---------|
| `contracts/src/` | First-party protocol contracts |
| `contracts/test/` | 199 tests (183 unit/configuration + 16 stateful PSM invariants) and fixtures |
| `contracts/script/` | Deployment and proposal examples |
| `app/src/` | Next.js frontend |
| `docs/` | Protocol and operational documentation |

---

## Security Considerations

### Strengths ✓
- **No centralized admin**: All privileged changes go through DAO votes only
- **2-day timelock**: Prevents flash loan attacks and allows exit
- **Snapshot voting**: Fixes voting power at the proposal snapshot and limits flash-loan-style voting
- **Low quorum (4%)**: Encourages participation, while making governance-capture risk an explicit operational concern
- **Multi-sig beneficiaries**: Vesting controlled by teams, not single person

### Risks & Mitigations

**Risk**: Governance capture (51% voting)
- *Mitigation*: 2-day timelock allows affected users to move funds
- *Mitigation*: Community can propose counter-votes

**Risk**: Low participation
- *Mitigation*: 4% quorum is low, easy to pass proposals
- *Mitigation*: Can be adjusted via governance if needed

**Risk**: CPI oracle fails
- *Mitigation*: `mockCPI()` function allows manual override
- *Mitigation*: Vesting contracts work regardless of CPI updates

**Risk**: Timelock too restrictive
- *Mitigation*: Can propose to lower delay (requires community vote)
- *Mitigation*: Emergency proposals can still execute after delay

---

## Next Steps for You

### Immediate (This Week)
1. **Test locally**: `forge test -vvv` ✓ (199/199 should pass)
2. **Deploy to Arbitrum Sepolia**: `forge script script/Deploy.s.sol:DeployHalalSystem --rpc-url $RPC_URL --private-key $PRIVATE_KEY --broadcast`
3. **Create test proposal**: Use Examples.s.sol or the non-broadcasting CPI adapter handoff template

### Medium-term (Next 2 Weeks)
4. **Get an independent security audit** before any meaningful-funds deployment
5. **Create governance docs** for community
6. **Set up Discord/Telegram** governance channel

### Before Mainnet
7. **Run mainnet simulation** (fork testing)
8. **Community feedback** on governance params
9. **Deploy to Arbitrum mainnet** (same code)

---

## Quick Reference: Key Parameters

```solidity
// Voting
VOTING_DELAY = 1 block (immediate)
VOTING_PERIOD = 2,419,200 blocks on Arbitrum (~1 week at 250ms); 50,400 elsewhere unless overridden
PROPOSAL_THRESHOLD = 100e18 HLC
QUORUM_NUMERATOR = 4 (percent)

// Timelock
MIN_DELAY = 2 days (172,800 seconds)

// Vesting
TEAM_VESTING = 6M HLC, 4-year with 1-year cliff
TREASURY_VESTING = 4M HLC, 3-year

// PSM
CPI_PRECISION = 1,000,000 (1.0 = 1,000,000)
CPI_RANGE = 100,000 to 2,000,000 (0.1 to 2.0)
```

---

## Support & Documentation

- **Code**: See [3] for test examples
- **Deployment**: See [4] for scripts
- **Governance**: See [6] for complete guide
- **Checklist**: See [7] for launch phases

---

**Status**: Unaudited reference implementation; not production-ready
**Network**: Arbitrum (Sepolia & Mainnet)
**Last Updated**: August 24, 2026
**Version**: 1.0.0 reference snapshot

This repository provides an auditable starting point for a CPI-indexed stablecoin DAO. Complete
independent review, deployment rehearsal, and operational governance work before using real funds.
