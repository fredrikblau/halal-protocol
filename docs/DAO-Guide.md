# Halal DAO Implementation Guide

## Overview

This is the operational guide for the Halal (HLC) stablecoin DAO. The protocol remains unaudited;
read [`SECURITY.md`](../SECURITY.md) before using real funds. It includes:

- **HalalDAO.sol** - OpenZeppelin Governor with voting
- **HalalTimelock.sol** - 2-day execution delay
- **Full Test Suite** - 197 tests (184 unit/configuration tests plus 13 stateful PSM invariants) covering the core workflows
- **Deployment Script** - One-command setup
- **Example Proposals** - Ready-to-use proposal templates

---

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    HALAL GOVERNANCE                         │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  HLC Holders (Voting Power)                                │
│         ↓                                                   │
│  Create Proposal (100 HLC minimum)                         │
│         ↓                                                   │
│  Voting Period (chain-dependent snapshot-based)            │
│         ↓                                                   │
│  IF (For > Against) AND (Votes ≥ 4% quorum)               │
│         ↓                                                   │
│  Queue in Timelock (2 days)                                │
│         ↓                                                   │
│  Execute on Target Contract (Token, PSM, Vesting, etc)    │
│         ↓                                                   │
│  DAO Now Controls All Protocol Parameters ✓                │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

---

## Governance Parameters

| Parameter | Value | Rationale |
|-----------|-------|-----------|
| Voting Delay | 1 block | Immediate voting after proposal |
| Voting Period | 2,419,200 blocks on Arbitrum (~1 week) | 50,400 elsewhere; override after checking the target chain |
| Proposal Threshold | 100 HLC | Prevents spam proposals |
| Quorum | 4% | Low bar for community engagement |
| Timelock Delay | 2 days | Safety window to exit if unpopular |

---

## DAO Powers

### 1. **Update CPI Rate**
```solidity
targets: [PSM]
call: psm.mockCPI(newCPI)
effect: DAO-approved manual override, bounded to 0.1–2.0 but not subject to the updater interval/step limit
```

Routine oracle reports should use `psm.updateCPIWithTimestamp(reportedCPI, reportedAt)` from a
separately granted `UPDATER_ROLE` account; reports must be monotonic, no more than 90 days old,
and not from the future. The first report can be accepted immediately; later reports must advance
the on-chain watermark and observe the configured cadence. The account may be bootstrapped with
`CPI_UPDATER` or granted later by governance. `updateCPI(reportedCPI)` remains as a compatibility
path.

### 2. **Switch CPI Source**
```solidity
targets: [PSM]
call: psm.setSource(newJS)
effect: Switch from US CPI → China CPI (or other)
```

### 3. **Hand Off Routine CPI Reporting to the Quorum Adapter**

Prepare the governance calldata with the non-broadcasting helper:

```bash
export PSM=0x...
export CPI_ADAPTER=0x...
export TIMELOCK=0x...
export CPI_SOURCE='BLS:CUUR0000SA0'
export EXPECTED_CPI_SOURCE_ID=0x...
export OLD_CPI_UPDATER=0x... # optional; revoke after the adapter is granted

forge script script/PrepareCPIAdapterHandoff.s.sol:PrepareCPIAdapterHandoff \
  --rpc-url "$RPC_URL"
```

The output contains three zero-value actions when `OLD_CPI_UPDATER` is set:

1. `PSM.grantRole(UPDATER_ROLE, CPI_ADAPTER)`
2. `PSM.setSource(CPI_SOURCE)`
3. `PSM.revokeRole(UPDATER_ROLE, OLD_CPI_UPDATER)`

The script checks that the adapter points to the selected PSM, is owned by the selected timelock,
and carries the expected `sourceId`; it never broadcasts. Review the signer threshold and signer
addresses before submitting the returned arrays through the DAO. The handoff builder has a decodeability test in
`CPIReportAdapter.t.sol`.

### 4. **Grant a Module Minting Permission**
```solidity
targets: [Token]
call: token.grantRole(token.MINTER_ROLE(), module)
effect: Authorize a separately reviewed module to mint HLC; the DAO/timelock is not itself a minter
```

### 5. **Revoke Team Vesting**
```solidity
targets: [TeamVesting]
call: teamVesting.revoke()
effect: Emergency return of unvested tokens to DAO treasury
```

### 6. **Release Treasury Vesting (no proposal required)**
```solidity
call: treasuryVesting.release()
caller: beneficiary, multisig operator, or any third party
effect: vested tokens are sent to the configured treasury beneficiary
```

`release()` is intentionally permissionless because the tokens always go to the configured
beneficiary. A DAO proposal is only needed for DAO-controlled actions such as revoking the
revocable team schedule.

### 7. **Change Governance Parameters** (future deployment)

The current non-upgradeable `HalalDAO` keeps its voting delay, voting period, proposal threshold,
and quorum settings in the deployed Governor. Changing them requires deploying and wiring a new
DAO through a planned migration.

---

## Deployment Instructions

### Prerequisites
```bash
# Install Foundry
curl -L https://foundry.paradigm.xyz | bash
source ~/.bashrc
foundryup

# Clone your project
git clone <your-repo>
cd halal-protocol/contracts
forge install

# Set environment variables
cat > .env << 'EOF'
PRIVATE_KEY=0x...                    # Your deployer private key
RPC_URL=https://sepolia.arbitrum.io/rpc
EXPECTED_CHAIN_ID=421614
RESERVE_TOKEN=0x...                   # Existing DAI/USDC reserve token
TEAM_BENEFICIARY=0x...               # Team multisig
TREASURY_BENEFICIARY=0x...           # Treasury multisig
EOF
```

### Step 1: Deploy on Arbitrum Sepolia
```bash
source .env

forge script script/Deploy.s.sol:DeployHalalSystem \
  --rpc-url $RPC_URL \
  --private-key $PRIVATE_KEY \
  --broadcast
```

**Output:**
```
HalalTimelock:       0xABC...123
HalalToken (HLC):    0xDEF...456
Team Vesting:        0xGHI...789
Treasury Vesting:    0xJKL...012
HalalDAO:            0xMNO...345
HalalPSM:            0xPQR...678

All roles transferred to the DAO. Deployer retains zero privileged access.
PSM has PARAM_ROLE granted to the DAO only. A reviewed oracle relayer may be bootstrapped with the
deployment script's optional `CPI_UPDATER` variable; otherwise grant `UPDATER_ROLE` via governance
before relying on `updateCPI()`.
```

### Step 2: Run Full Test Suite
```bash
forge test -vvv

# Output should show:
# ✓ test_InitialState
# ✓ test_CreateProposal_UpdateCPI
# ✓ test_CastVote_For
# ✓ test_FullProposalFlow
# ✓ test_DAO_ControlsPSM_AfterTakeover
# ... (197 tests: 184 unit/configuration + 13 invariants) ...
```

### Step 3: Verify on Arbiscan
Visit: `https://sepolia.arbiscan.io/address/0xMNO...345`
- Check the "Contract" tab and verify the deployed bytecode/source and role configuration

---

## Creating Your First Proposal

### Via Frontend
```
1. Connect wallet with HLC tokens
2. Click "New Proposal"
3. Fill in:
   - Target: PSM address
   - Function: updateCPIWithTimestamp(reportedCPI, reportedAt)
   - Title: "Update CPI rate"
   - Description: "Monthly CPI adjustment with a source timestamp"
4. Click "Propose"
```

### Via Script
```bash
# Update .env with DAO_ADDRESS, PSM_ADDRESS
forge script script/Examples.s.sol:ExampleProposal_UpdateCPI \
  --rpc-url $RPC_URL \
  --private-key $PRIVATE_KEY \
  --broadcast
```

### Via Etherscan (if DAO is verified)
1. Navigate to DAO contract on Arbiscan
2. "Contract" tab → "Write Contract"
3. Call `propose()`
   - targets: [PSM address]
   - values: [0]
   - calldatas: [0x...]
   - description: "Update CPI"

---

## Voting Workflow

For a concrete fictional review packet with raw calldata, reserve and role analysis, and evidence
requirements, see the [governance proposal review example](GOVERNANCE-PROPOSAL-REVIEW-EXAMPLE.md).

### Phase 1: Voting Delay (1 block)
- Proposal created at block N
- Voting starts at block N+1
- **Snapshot block**: N (voting power fixed)

### Phase 2: Voting Period (configured for the target chain)
- Holders vote FOR / AGAINST / ABSTAIN
- Voting power = HLC balance at snapshot
- **Quorum needed**: 4% of total supply

### Phase 3: Check State
```solidity
if (forVotes > againstVotes && forVotes >= quorum) {
    state = SUCCEEDED
} else {
    state = DEFEATED
}
```

### Phase 4: Queue
- If SUCCEEDED, call `dao.queue()`
- Proposal moves to QUEUED state
- Timelock starts counting (2 days)

### Phase 5: Execute
- After 2 days, call `dao.execute()`
- Transaction sent to target contract
- Proposal state = EXECUTED

---

## Reproducible Local Governance Walkthrough

This is a disposable local rehearsal. It never uses a public RPC, real collateral, or a production
private key. Keep the terminal running the demo open until the interactive steps are complete.

### 1. Start the local system

From the repository root, use the local-only demo wrapper:

```bash
./scripts/local-demo.sh
```

Open <http://localhost:3000>. The wrapper starts Anvil on port `8545`, deploys the full role-wired
system, seeds a current CPI report, verifies the deployment, and writes temporary frontend
configuration. It restores the previous `app/.env.local` and stops Anvil when you press `Ctrl-C`.

### 2. Create a proposal through the dApp

1. Connect the first published Anvil account with **Browser Wallet**.
2. Open **Swap**, choose **Deposit**, and deposit some faucet-backed `mDAI`. This mints HLC and
   creates the account's redeemable PSM credit.
3. Open **Governance** and click **Self-delegate to activate voting power**. Wait for the
   confirmation, then confirm voting power is at least `100 HLC`.
4. Choose **New proposal**, keep the **Update CPI rate** template, enter a rate between `0.1` and
   `2.0` with at most six decimal places, and provide a description.
5. Submit the proposal. The detail page should show one action targeting the configured PSM with
   decoded `mockCPI(uint256)` calldata; the proposal list should show its pending state.

The browser flow is covered without a public network by:

```bash
make app-e2e
```

### 3. Rehearse every on-chain lifecycle state

The local browser flow intentionally stops after proposal creation because a real voting period
and timelock should not be shortened in the dApp. The Foundry tests use `vm.roll` and `vm.warp` on
an isolated chain to advance the exact same lifecycle safely:

```bash
cd contracts
forge test --match-contract HalalDAOTest --match-test test_ProposalState_Transitions -vvv
forge test --match-contract HalalDAOTest --match-test test_FullProposalFlow -vvv
```

These tests prove the following sequence against the deployed role wiring:

| State | Local rehearsal | Expected result |
| --- | --- | --- |
| Pending | Create proposal | Voting has not started; snapshot is fixed |
| Active | Advance past the 1-block voting delay | A delegated holder can vote |
| Succeeded | Vote for, then advance 50,400 voting blocks | For votes meet the 4% quorum |
| Queued | Call `dao.queue(...)` | The timelock schedules the exact action bundle |
| Executed | Advance 2 days, then call `dao.execute(...)` | The PSM CPI rate changes through governance |

For the exact fixture helpers and assertions, read
[`HalalDAO.t.sol`](../contracts/test/HalalDAO.t.sol) and
[`DeployLocal.s.sol`](../contracts/script/DeployLocal.s.sol). For production deployments, verify
the configured voting period rather than assuming the local `50,400`-block value: the deployment
script defaults Arbitrum chains to `2,419,200` blocks and permits an explicit reviewed override.

---

## Test Coverage

```
Test Suite: HalalDAOTest (28 tests)
├── Setup & role wiring [3 tests]
│   ├── test_InitialState
│   ├── test_VestingInitialized
│   └── role-wiring assertions
│
├── Proposal Creation [4 tests]
│   ├── test_CreateProposal_UpdateCPI
│   ├── test_CreateProposal_GrantMinterRole
│   ├── test_FailProposal_BelowThreshold
│   └── test_MultiTargetProposal
│
├── Voting [6 tests]
│   ├── test_CastVote_For
│   ├── test_CastVote_Against
│   ├── test_CastVote_Abstain
│   ├── test_FullProposalFlow
│   ├── test_ProposalThreshold
│   └── test_Quorum
│
├── Execution [5 tests]
│   ├── test_DAO_ControlsPSM_AfterTakeover
│   ├── test_TimelockPreventsImmediateExecution
│   ├── test_TimelockDelay
│   └── test_ProposalCancellation
│
├── Vesting Integration [2 tests]
│   ├── test_TeamVestingRevocable
│   └── test_TreasuryVestingNonRevocable
│
└── Edge Cases [5+ tests]
    ├── test_ZeroVotes
    ├── test_DuplicateVotes
    └── ...
```

### Run Specific Test
```bash
forge test --match "test_FullProposalFlow" -vvv
```

### View Coverage
```bash
forge coverage
```

---

## Security Checklist

- ✅ Timelock prevents flash loan attacks
- ✅ Voting snapshot prevents front-running
- ✅ 100 HLC threshold prevents proposal spam
- ✅ 4% quorum ensures broad consensus
- ✅ 2-day delay allows exit window
- ✅ Multi-sig beneficiaries on vesting
- ✅ Privileged roles handed to the timelock/DAO
- ✅ No owner-based admin backdoor

---

## Upgrading Parameters (Post-Launch)

### If quorum is too high/low:

The current deployment cannot change Governor settings in place. Plan a new DAO deployment and a
timelocked migration of protocol roles.

### If voting period too short:
```solidity
// Would require proxy upgrade (not in current design)
// Alternative: Deploy DAO v2 and migrate protocol roles through a planned governance transition
```

### If timelock too long:
```solidity
// Would require timelock update or redeployment
// Current: 2 days is safe for mainnet
```

---

## Troubleshooting

### "Proposal threshold not met"
→ Need at least 100 HLC in wallet at proposal block

### "Voting not active"
→ Must wait 1 block after proposal creation

### "Quorum not reached"
→ Need ≥4% of total HLC holders voting FOR

### "Proposal state is DEFEATED"
→ Against votes ≥ For votes, or below quorum

### "Execution reverted"
→ Check target contract has the expected DAO/timelock role and calldata is correct
→ Check caldata is correct (use abi.encodeWithSignature)

---

## Production Checklist

Before moving to Arbitrum mainnet:

- [ ] All tests passing locally and on the target network (197/197 local suite)
- [ ] Manual proposal cycle tested (create → vote → queue → execute)
- [ ] Team vesting wallet is multisig (e.g., Gnosis Safe)
- [ ] Treasury vesting wallet is multisig
- [ ] Chainlink Functions subscription funded
- [ ] PSM has DAI reserves (recommend 2M DAI minimum)
- [ ] Independent security audit completed and published
- [ ] Community governance guidelines posted
- [ ] DAO announcement with voting tutorial

---

## Files Included

- `contracts/src/` — five core contracts plus the optional CPI report adapter and handoff action builder
- `contracts/test/` — 197 tests (184 unit/configuration tests plus 13 stateful PSM invariants) and fixtures
- `contracts/script/Deploy.s.sol` — full-system deployment script
- `contracts/script/Examples.s.sol` — governance proposal examples
- `contracts/script/PrepareCPIAdapterHandoff.s.sol` — non-broadcasting adapter handoff calldata generator
- `app/` — Next.js frontend

---

## Next Steps

1. **Test on Sepolia** (this weekend)
   ```bash
   forge test -vvv
   ```

2. **Create your first proposal** (example: mock CPI update)
   ```bash
   forge script script/Examples.s.sol:ExampleProposal_UpdateCPI --broadcast
   ```

3. **Simulate full vote cycle** (using Foundry time/block manipulation)
   ```bash
   # In test: vm.roll(), vm.warp(), dao.castVote()
   ```

4. **Prepare community** (create governance docs, Discord channel)
   - Explain voting mechanics
   - Share proposal templates
   - Set expectations for response times

5. **Move to mainnet** (when confident)
   ```bash
   # Change RPC_URL, redeploy, same contracts ✓
   ```

---

## Support

Questions on governance?
- Check `contracts/test/HalalDAO.t.sol` for workflow examples
- Review OpenZeppelin Governor documentation
- Consult Arbitrum DAO case studies

This guide supports a testnet or carefully reviewed deployment; it is not a safety or production-readiness claim.

---

**Last Updated:** August 24, 2026
**Network:** Arbitrum Sepolia → Arbitrum One (mainnet)
**Status:** Unaudited reference implementation; do not use with meaningful funds
