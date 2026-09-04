# Design Decisions

This document tracks places where the **implementation** (`contracts/src/`) deliberately
diverges from the original planning docs (`docs/Architecture.md`, `docs/TECHNICAL-DOCS.md`,
`docs/DAO-Guide.md`, `docs/Treasury.md`, `docs/AddingFeature.md`). Those docs describe the
system's design intent and are useful narrative context, but they were written before — and in
some places slightly ahead of — the actual Solidity, and a few numbers in them are approximate
or aspirational rather than exact. When the docs and the code disagree, **the code is ground
truth**. This page exists so contributors understand *why* the two differ instead of assuming
one of them is simply wrong.

If you're extending the protocol and you notice another discrepancy between the docs and
`contracts/src/`, please open an issue or PR adding it here rather than silently working around
it — that's exactly the kind of tribal knowledge this file is for.

## 1. Genesis supply is minted via `initialMint`, not the constructor

The planning docs describe the 6,000,000 HLC team allocation and 4,000,000 HLC treasury
allocation as if they simply exist from deployment (see `docs/TECHNICAL-DOCS.md`'s DAO
constructor walkthrough, which doesn't mention a separate mint step). The actual
[`HalalToken`](../contracts/src/HalalToken.sol) constructor mints nothing — it grants only
`DEFAULT_ADMIN_ROLE` to the deployer-controlled `admin` address. The deployer is deliberately not
a minter; the deployment script grants `MINTER_ROLE` directly to the PSM before relinquishing
admin control:

```solidity
constructor(address admin) ERC20("Halal", "HLC") ERC20Permit("Halal") {
    if (admin == address(0)) revert ZeroAddress();
    _grantRole(DEFAULT_ADMIN_ROLE, admin);
}
```

The genesis supply is minted separately, exactly once, by calling:

```solidity
function initialMint(address teamVesting, address treasuryVesting) external onlyRole(DEFAULT_ADMIN_ROLE)
```

which mints `TEAM_ALLOCATION` (6,000,000e18) to `teamVesting` and `TREASURY_ALLOCATION`
(4,000,000e18) to `treasuryVesting`, and sets a one-time `genesisMinted` latch (`initialMint`
reverts with `GenesisAlreadyMinted` if called twice).

**Why:** the two `HalalVesting` instances (team and treasury) need to exist — and their
addresses need to be known — before any tokens can be minted to them. If the genesis mint were
in `HalalToken`'s constructor, the deployer would have to predict the vesting contracts'
addresses ahead of time (e.g. via `CREATE` nonce arithmetic or `CREATE2` salts) and pass those
predicted addresses into the token constructor before the vesting contracts actually exist. That
works, but it's fragile: it breaks if the deployer's nonce changes for any reason between
prediction and deployment (a failed transaction, an unrelated transaction from the same key, a
different RPC ordering), and it makes the deploy script harder to reason about and re-run
safely. Splitting genesis mint into its own guarded, one-time call means the deploy sequence is
simply "deploy token → deploy vesting contracts with the token's real address → call
`initialMint` with the vesting contracts' real addresses" — no address prediction anywhere. See
`contracts/script/Deploy.s.sol` for the actual ordering.

## 2. HalalPSM: `updateCPI` is a gated report submission, not a live Chainlink Functions call

The planning docs (`docs/Architecture.md`, `docs/TECHNICAL-DOCS.md`, `docs/DAO-Guide.md`)
describe `updateCPI()` as directly triggering an on-chain Chainlink Functions request that fetches
CPI data live. The actual [`HalalPSM`](../contracts/src/HalalPSM.sol) has no Chainlink dependency
at all — it is fully self-contained so it can be built, tested, and deployed without a live
Chainlink Functions subscription. Concretely:

- `updateCPI(uint256 reportedCPI)` is gated by a dedicated `UPDATER_ROLE` (not the DAO's own
  role) and is bounds-, rate-, and step-limited, cadence-limited after bootstrap, and
  reserve-limited: it reverts with `RateOutOfBounds` outside
  `[MIN_CPI, MAX_CPI]` (0.1x–2.0x), with `StepTooLarge` if the move exceeds `MAX_CPI_STEP_BPS`
  (20%) in one call, and with `UpdateTooSoon` if called before `minUpdateInterval` (25 days by
  default) has elapsed since the last accepted report or governance override. The first fresh
  report can bootstrap immediately. It also reverts with `RateWouldUnderCollateralize` if
  the new rate would require more reserve than the PSM currently holds. It's a *report submission*
  function, not an oracle call.
- `updateCPIWithTimestamp(uint256 reportedCPI, uint256 reportedAt)` is the preferred production
  relayer entrypoint. It rejects future, replayed, and more-than-90-day-old source reports using
  the on-chain `lastReportTimestamp` watermark (which starts at zero so the first fresh report may
  have been published just before deployment). The original `updateCPI(uint256)` remains as a
  compatibility path for integrations that only provide a current submission.
- `mockCPI(uint256 newCPI)` is a **separate**, DAO-gated (`PARAM_ROLE`) manual override that
  bypasses the step and interval limits entirely (it still respects `[MIN_CPI, MAX_CPI]`).
  It's meant for governance-approved emergency corrections — e.g. the updater misbehaves, the
  off-chain data source is disputed, or the protocol needs to respond faster than
  `minUpdateInterval` allows.
- `setMinUpdateInterval(uint256)` rejects zero. Governance can choose a shorter positive interval
  when operating a faster oracle, while the manual override remains the explicit path for bypassing
  the normal updater cadence.
- The deployment script accepts an optional `CPI_UPDATER` address. When supplied, the PSM grants
  that address `UPDATER_ROLE` in its constructor while the timelock remains the role admin; the
  deployer is explicitly rejected as the updater so the handoff still leaves it with no privileged
  access. Leaving the variable unset preserves a governance-only role bootstrap.

The intended production topology is: the DAO grants `UPDATER_ROLE` to a Chainlink Functions
consumer contract (or a Chainlink Automation-triggered relayer) that fetches CPI off-chain and
submits it via `updateCPIWithTimestamp`. That keeps routine monthly-ish updates from requiring a full
governance vote each time, while governance still controls *who* can submit (`UPDATER_ROLE`
  grant/revoke), the bounds those submissions are checked against (`MIN_CPI`/`MAX_CPI`/
  `MAX_CPI_STEP_BPS`), current reserve adequacy, and the emergency override (`mockCPI`,
  `PARAM_ROLE`). No such consumer
contract ships in this repo — wiring one up is left as a real integration task for whoever
operates a production deployment.

**Two related additions not in the original design:**

- **Decimal normalization.** `HalalPSM` reads the reserve token's `decimals()` at construction
  time (`_reserveDecimals`) and scales all conversions through its decimal-normalization helpers
  before
  applying the CPI rate. This means the PSM works correctly with a 6-decimal reserve asset (e.g.
  USDC) as well as an 18-decimal one (e.g. DAI) — the original docs only ever discuss DAI and
  don't address decimal mismatch. Conversions round down; both deposits and withdrawals reject
  amounts that would produce zero output, so a caller cannot accidentally burn a nonzero HLC claim
  for a zero-unit reserve return. The arithmetic uses OpenZeppelin's full-precision `Math.mulDiv`
  where multiplication-before-division could otherwise overflow for a large input whose final
  result is still representable.
- **ERC20 transfer return data.** Reserve transfers use OpenZeppelin `SafeERC20`, so a token whose
  `transfer` or `transferFrom` returns no data is accepted as long as the call itself succeeds.
  Tokens that return `false` or revert are rejected. Balance-delta checks remain in place for
  fee-on-transfer behavior, but deployment operators must still review the reserve token's full
  transfer, pause, blacklist, upgradeability, and issuer controls.
- **`reserveRequired()` / `reserveSurplus()` views.** These didn't exist in the original design.
  Because deposits lock in reserve at the CPI rate prevailing *at deposit time* while withdrawals
  pay out at the rate prevailing *at withdrawal time*, a CPI that has risen since a given deposit
  means that deposit's eventual redemption can cost more reserve than it originally brought in.
  `reserveRequired()` returns the reserve balance the PSM would need on hand right now to redeem
  *all* outstanding PSM-issued HLC at the current rate; `reserveSurplus()` returns actual balance
  minus that requirement (negative means under-collateralized). Withdrawals may proceed on a
  first-come-first-served basis while preserving the existing deficit, but they revert if a token's
  outgoing debit would make that deficit worse. These views let the DAO/treasury and any external
  integrator see a looming shortfall before it becomes operationally material.

## 3. Governance voting period is chain-dependent — don't copy `50,400` blindly

Earlier versions of the documentation gave `50,400 blocks` as "~1 week" — which is only true on
Ethereum L1, where blocks are ~12 seconds apart (50,400 × 12s ≈ 7 days). On a
fast L2 — Arbitrum's block time is closer to ~0.25s — `50,400` blocks is only on the order of a
few hours, not a week, and would leave essentially no time for voters to react to a proposal.

`HalalDAO`'s constructor takes `votingPeriod_` as a plain `uint32` (see
[`contracts/src/HalalDAO.sol`](../contracts/src/HalalDAO.sol)) — the contract has no opinion
about what a "block" means on whatever chain it's deployed to. `contracts/script/Deploy.s.sol`
reflects this: `VOTING_PERIOD_BLOCKS` is a configurable environment variable. The deployment
script defaults to approximately one week on Arbitrum (`2_419_200` blocks) and `50_400` elsewhere,
with an
explicit comment warning that the value must be recomputed for the actual target chain's block
time before deploying anywhere else.

**Takeaway for contributors/operators:** before deploying to any chain, compute
`votingPeriod = desired_seconds / actual_average_block_time_on_that_chain` from that chain's real
observed block time, and pass it explicitly as `VOTING_PERIOD_BLOCKS` — never assume `50,400` is
correct just because it appears in the docs or as the script's fallback default.

## 4. `via_ir = true` was tried and deliberately reverted

`contracts/foundry.toml` pins `via_ir = false`. This wasn't the starting default so much as a
considered decision: `via_ir` was tried, and turned up a real, silent test-correctness bug, not
just a performance question.

With the via-IR pipeline and its optimizer enabled, a **second textually-identical
`block.timestamp + X` expression within the same function** was observed returning a stale,
cached value across an intervening `vm.warp()` cheatcode call inside a test — i.e. the optimizer
treated the second occurrence of the expression as redundant with the first and reused its
value, even though `vm.warp()` had changed `block.timestamp` in between. Because
`block.timestamp` is normally assumed to be effectively opaque/volatile, this is exactly the kind
of thing a "pure" optimization pass isn't supposed to do to it — and it fails silently: no
compiler error, no revert, just a wrong number. In this codebase it showed up as time-based
vesting assertions in `contracts/test/HalalVesting.t.sol` (and similar patterns in
`HalalDAO.t.sol`) computing incorrect `vestedAmount`/`releasable` expectations after a `vm.warp`,
because a repeated `block.timestamp`-derived expression in the assertion path didn't reflect the
warp.

**Why this matters for future contributors:** if you're tempted to flip `via_ir` back on
(e.g. to get under the stack-depth limit instead of restructuring a function, or for the gas
savings), know that this project hit a genuine optimizer/cheatcode interaction bug doing exactly
that, and it did not fail loudly — tests kept "passing" with a value that was wrong. If you
re-enable it, re-run the full suite with careful manual review of every time-dependent assertion
(anything touching `block.timestamp`, `vestedAmount`, `releasable`, or CPI update timing) rather
than trusting a green `forge test` alone, and consider isolating repeated `block.timestamp`
reads into a local variable read once per function as a mitigation either way — that's good
practice independent of this bug and would have caught it earlier.
`contracts/script/Deploy.s.sol` also splits its deployment logic into small internal helpers
partly so it doesn't need `via_ir` to fit under the stack-variable limit, which is the other
place this tradeoff surfaces.

## 5. PSM redemption rights are per-depositor, not per-token (`redeemableBalance`)

HLC is a single fungible ERC20 shared between two very different roles: the fixed 10,000,000
genesis allocation (6M team / 4M treasury, minted via `initialMint`, never backed by any
reserve — it's a compensation/incentive allocation, not a redemption claim) and the elastic,
reserve-backed supply minted by `HalalPSM.deposit()`. An early version of `withdraw()` let *any*
HLC holder redeem against the PSM's shared reserve pool, gated only on the pool having enough
reserve on hand. Because HLC is fully fungible, that meant genesis/vesting HLC — free to acquire,
contributed no reserve — could be redeemed exactly like a real deposit, directly at the expense of
actual depositors: whoever called `withdraw()` first (genesis holder or not) got paid from a pool
that legitimate depositors funded, and later depositors could find the reserve they were counting
on already gone.

The fix: `HalalPSM` tracks `redeemableBalance[address]`, incremented by `deposit()` and
decremented by `withdraw()`, and `withdraw()` reverts with `InsufficientRedeemableBalance` if the
caller's own credit doesn't cover the amount requested — regardless of how much HLC they actually
hold. Since `deposit()` credits the depositor for exactly what they minted, and `withdraw()` can
never debit more than that credit, `sum(redeemableBalance)` always equals `totalHlcIssued`, and no
one can redeem reserve they (or whoever transferred them PSM-minted HLC) didn't themselves deposit.

**Tradeoff, stated plainly:** a plain ERC20 transfer does not move the redemption right to another
address — the recipient can hold, spend, or trade the HLC like any other HLC, but cannot
`withdraw()` it through this PSM. To support a safe handoff without making arbitrary genesis HLC
redeemable, the PSM also exposes `transferRedeemable(to, amount)`: after approving the PSM, a user
can atomically transfer PSM-issued HLC and its matching credit. This is deliberately narrower than
a fully composable ERC-4626-style claim token: a separate receipt token would add share-price
accounting and another attack surface, so it remains a possible future extension rather than an
implicit promise of the current HLC token.

The reference deployment grants `BURNER_ROLE` to the PSM and does not expose a public self-burn.
This is deliberate: a holder burning HLC without informing the PSM would strand that address's
redemption credit and leave the corresponding reserve as surplus. `cancelRedeemable(amount)` retires
the matching credit before the PSM burns the HLC and returns no reserve, keeping `totalHlcIssued()`
and `reserveRequired()` accurate. Future modules that need to burn HLC must preserve this ordering
and receive `BURNER_ROLE` through governance.

The normal updater path now refuses to create that shortfall. Governance can still use the explicit
`mockCPI` emergency path to accept a reserve shortfall when correcting a disputed or failed oracle,
but must then use `reserveSurplus()` and `depositReserve()` to restore full backing.

## 6. No emergency-cancel path for a queued proposal — by design, not oversight

`HalalTimelock` is never granted `CANCELLER_ROLE` for `address(dao)` in `Deploy.s.sol`. An earlier
version did grant it, on the assumption that it let the DAO abort a queued proposal during the
2-day timelock window as a safety net. It doesn't: `Governor.cancel()` (which `HalalDAO` inherits
unmodified) is gated by `_validateCancel`, which requires `state == Pending` — but
`GovernorTimelockControl._cancel` only ever calls `_timelock.cancel(...)` for a proposal that has
already been queued (`_timelockIds[proposalId] != 0`), i.e. is in the `Queued` state, not
`Pending`. Those two conditions can never both hold for the same proposal, so the grant enabled
nothing — `CANCELLER_ROLE` was dead weight, not a functioning emergency brake. (The proposer *can*
still withdraw their own proposal via `cancel()` while it's genuinely `Pending`, before voting
starts — that path never touches the timelock and doesn't need `CANCELLER_ROLE` at all.)

The realistic alternative — a guardian/multisig address with its own `CANCELLER_ROLE`, able to
veto a queued proposal unilaterally — was considered and rejected. This system's documented
security posture (`docs/Architecture.md`'s "No centralized admin: All functions through DAO votes
only") treats the absence of any admin backdoor as a feature, not an accident; a guardian that can
unilaterally kill governance-approved proposals is exactly that kind of backdoor, just narrower in
scope. Once a proposal clears voting and quorum and is queued, the only recourse during the 2-day
window is the one already documented elsewhere in this repo: token holders and integrators can act
on the public queued transaction before it executes (exit positions, pause external integrations,
etc.) — the delay's purpose was always "give the community time to react," not "give governance a
kill switch," and this system doesn't have the latter. If a future version of this protocol wants
one, that's a deliberate governance-model change (e.g. a DAO-elected, term-limited, narrowly-scoped
guardian committee) worth its own proposal and discussion, not a role grant slipped in as if it
were already part of the design.
