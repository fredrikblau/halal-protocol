# Halal (HLC): A CPI-Indexed, DAO-Governed Stablecoin

**Version 1.0**

> This document describes the design and intent of the Halal protocol. It is not investment
> advice, and it is not a claim that the software described here is complete, audited, or safe
> to use with real funds today. See [Status & risk](../README.md#status--risk) in the root
> README, and [`SECURITY.md`](../SECURITY.md), for the current, honest state of the project.

## Abstract

Most "stablecoins" stabilize the wrong thing. They peg to a unit of account — the US dollar —
that itself loses purchasing power to inflation year over year. A token that reliably trades for
$1 is not the same thing as a token that reliably buys the same basket of goods. Halal (HLC) is
an attempt to close that gap: a token collateralized by a reserve asset at the applicable
CPI-adjusted rate, redeemable through a Peg Stability Module (PSM) whose rate is periodically
adjusted to track a Consumer Price Index (CPI) feed, so that HLC's *purchasing power* — not just its nominal price against the reserve —
stays roughly constant over time. The protocol is governed entirely on-chain by HLC holders
through an OpenZeppelin `Governor` + `TimelockController` pair; there is no admin key, upgrade
proxy, or centralized off-switch once the system is fully deployed and handed off.

## 1. The problem

A dollar-pegged stablecoin is a claim on a dollar, not a claim on a fixed amount of purchasing
power. Over a long enough horizon, that distinction matters: someone holding a dollar-pegged
stablecoin through a decade of inflation has preserved their *nominal* balance while losing real
value, exactly as a cash holder would. For a token that wants to function as a long-horizon
store of value or unit of account — rather than purely as short-term trading collateral — that's
a design flaw, not a neutral fact of life.

CPI-indexation is the standard tool economies use to solve this for other instruments (inflation-
linked bonds, wage escalation clauses, some pension schemes). Halal applies the same idea to a
crypto-native, reserve-backed token: instead of fixing the exchange rate between HLC and its
reserve asset, the rate itself moves with a CPI feed, so a holder who redeems HLC for reserve
assets later gets back proportionally more reserve per HLC than someone who redeemed earlier,
compensating for the reserve currency's own inflation over that period.

## 2. System overview

Halal's core system is five contracts, deployed once and never upgraded. An optional signed CPI
adapter can sit in front of the PSM without changing those core contracts:

| Contract | Role |
|---|---|
| `HalalToken` | The HLC token itself — `ERC20Votes` + `ERC20Permit` + `AccessControl`, burnable. |
| `HalalVesting` | Linear vesting with cliff, one instance each for the team and treasury allocations. |
| `HalalPSM` | The Peg Stability Module — mints/burns HLC against a reserve asset at the current CPI-adjusted rate. |
| `HalalDAO` | An OpenZeppelin `Governor` — the only entity that can mint beyond genesis supply, change PSM parameters, or move treasury funds. |
| `HalalTimelock` | Enforces a delay between a passed vote and its execution. |

No contract is upgradeable, and no contract has an owner key that bypasses the DAO. Every
privileged action — minting, PSM parameter changes, treasury spending, granting roles to future
modules — happens through a proposal, a vote, and a timelock delay. This is a deliberate
trade-off: it means there is no emergency admin override if something goes wrong (see
[§8, Risks](#8-risks-and-honest-limitations)), in exchange for the token actually being
credibly neutral rather than "decentralized" in name with a backdoor in practice.

For the full technical specification — function signatures, access-control matrix, gas
estimates, and the exact contract call flow for a sample proposal — see
[`TECHNICAL-DOCS.md`](TECHNICAL-DOCS.md) and [`Architecture.md`](Architecture.md). This document
is deliberately non-technical by comparison; it explains *why* the system is shaped the way it
is, not *how* to call its functions.

## 3. The Peg Stability Module and CPI mechanism

The PSM is where HLC enters and leaves circulation in response to user action (as opposed to
genesis/vesting supply, which is fixed at deployment). A user deposits a reserve asset — any
ERC-20 whose decimals the PSM supports, chosen per deployment — and receives HLC at the current
rate; redeeming works in reverse. There is no public deployment yet, so no reserve asset has been
selected in production; the disposable local demo uses a faucet-only mock token, and the criteria
a real candidate must satisfy are set out in
[`RESERVE-ASSET-DUE-DILIGENCE.md`](RESERVE-ASSET-DUE-DILIGENCE.md).

The rate is not fixed at 1:1 indefinitely. It moves according to a CPI figure submitted on-chain
by a rate-limited `UPDATER_ROLE`, bounded to a 0.1–2.0 range so that a bad or malicious data point
cannot move the rate to an absurd extreme.

The PSM deliberately does not fetch CPI data itself. It accepts a bounded, timestamped report from
whatever holds `UPDATER_ROLE`, which keeps the settlement contract independent of any single
oracle vendor. The reference implementation of that role is
[`CPIReportAdapter`](../contracts/src/CPIReportAdapter.sol): an optional contract that verifies a
quorum of EIP-712 signatures over `(reportedCPI, reportedAt, sourceId)` before forwarding a report,
so no individual signer can move the rate alone. A Chainlink Functions consumer, a Chainlink
Automation relayer, or a differently-governed multi-signer scheme are all equally valid holders of
that role; the choice is a deployment decision, not a protocol dependency. Source provenance,
signer custody, and rotation requirements are specified in
[`CPI-ADAPTER-SPEC.md`](CPI-ADAPTER-SPEC.md).

A separate, DAO-gated manual override exists purely as an emergency mechanism if the feed breaks.
It bypasses the cadence and per-step limits but remains bounded to the same 0.1–2.0 range, is
deliberately harder to invoke than the routine update path, and any use of it is a matter of
public record via governance.

**Per-depositor redemption accounting.** Because HLC is one fungible token shared between
PSM-issued (reserve-backed) supply and the fixed genesis/vesting allocation (which was never
backed by PSM reserves), the contract tracks how much HLC each address has actually minted
through the PSM and not yet redeemed. Only that amount is redeemable by that address. This closes
an entire class of exploit where genesis tokens, or PSM-minted HLC that changed hands, could be
used to drain the reserve out from under legitimate depositors — at the cost of PSM-minted HLC
losing its redemption right if transferred through a plain ERC20 transfer; users can instead call
the PSM's atomic `transferRedeemable` path after approving it. That trade-off is documented in
detail, with the reasoning behind it, in [`DESIGN-DECISIONS.md`](DESIGN-DECISIONS.md).

## 4. Mechanism specification

This section states the settlement arithmetic and the parameters that bound it. Values are taken
from [`HalalPSM`](../contracts/src/HalalPSM.sol); the invariants they are meant to preserve are
enumerated in [`INVARIANTS.md`](INVARIANTS.md).

### 4.1 Notation and conversion

Let `r` be the current CPI rate scaled by `CPI_PRECISION = 1e6`, so `r = 1_000_000` means 1.0.
Let `d` be the reserve token's decimals and HLC's decimals be 18. Define the scale factor
`s = 10^(18 - d)`, which normalises a reserve amount into 18-decimal units.

For a reserve token with `d <= 18`:

```
hlcOut     = reserveIn · s · CPI_PRECISION / r
reserveOut = hlcIn · r / (CPI_PRECISION · s)
```

Equivalently: one HLC settles against `r / CPI_PRECISION` normalised reserve units. A rise in `r`
means each HLC redeems for *more* reserve — that is the entire point of the index. A reserve token
with more than 18 decimals is handled by a separate branch that carries the extra precision
through the multiplication rather than truncating in two stages, so small withdrawals are not
systematically underpaid when `r` is not exactly 1.0.

All conversions use `Math.mulDiv`, so the intermediate product does not overflow when the result
itself is representable. Rounding is toward zero throughout, which favours the reserve rather than
the redeemer — a deliberate direction, since the alternative lets rounding drain collateral.

The PSM's outstanding obligation is `reserveRequired() = hlcToReserve(totalHlcIssued)`, computed
at the current rate. Comparing that against the reserve balance defines whether the system is
fully collateralised at this instant.

### 4.2 Bounds and guards

| Parameter | Value | Purpose |
|---|---|---|
| `CPI_PRECISION` | `1e6` | Fixed-point scale for the rate |
| `MIN_CPI` / `MAX_CPI` | `100_000` / `2_000_000` (0.1–2.0) | Absolute rate bounds; enforced on every path including the DAO override |
| `MAX_CPI_STEP_BPS` | `2_000` (20%) | Largest single move on the report path |
| `minUpdateInterval` | 25 days (DAO-settable) | Minimum spacing between accepted reports, once a watermark exists |
| `MAX_REPORT_AGE` | 90 days | Rejects stale reports, and marks the accepted watermark stale for deposits |
| `MAX_RESERVE_DECIMALS` | 77 | Upper bound on supported reserve tokens |
| `MAX_SIGNERS` (adapter) | 64 | Caps signature verification cost below practical block-gas limits |

One bootstrap rule applies before any of this takes effect: while no report has ever been
accepted, the cadence guard is skipped, because otherwise a fresh deployment could never take its
first report. Once a watermark exists, every subsequent report is subject to it.

Beyond that, two asymmetries are deliberate and worth stating plainly, because they are easy to
misread:

1. **The routine report path is strictly more constrained than the emergency override.**
   A report submitted through `UPDATER_ROLE` must satisfy the freshness bound, the cadence
   interval, the per-step limit, a strictly increasing timestamp, *and* leave the PSM able to
   cover `reserveRequired()` — it reverts otherwise. The DAO's `mockCPI` override bypasses the
   cadence and step limits by design, since its purpose is to correct a feed that has already
   failed, but it remains bounded by `MIN_CPI`/`MAX_CPI`.
2. **A stale feed halts new deposits rather than freezing redemption.** If no fresh report has
   been accepted within `MAX_REPORT_AGE`, the system stops issuing new HLC against reserves while
   existing redemption claims remain subject to the ordinary accounting and reserve checks. The
   failure mode is chosen to stop the protocol taking on new obligations it cannot price, not to
   trap existing holders.

### 4.3 The signed report adapter

`CPIReportAdapter` is optional and sits in front of the PSM. It verifies `threshold` EIP-712
signatures over the typed struct `CPIReport(uint256 reportedCPI, uint256 reportedAt, bytes32
sourceId)`, requires them in strictly ascending signer order (which rejects duplicates), binds
every signature to an immutable `sourceId` so a report for one series cannot be replayed against
another, and tracks the last forwarded timestamp so reports cannot be replayed or reordered.

After forwarding, it re-reads the PSM and requires that both the accepted-report watermark and the
stored rate actually moved to the submitted values before recording its own state. A sink that
silently ignored the call, or accepted a different value, therefore cannot leave the adapter
looking healthy. Signer-set changes and threshold changes are `Ownable2Step`-gated, intended to be
held by the timelock.

## 5. Token and allocation

HLC has a fixed genesis supply of 10,000,000 tokens, split:

- **6,000,000 HLC — team allocation.** Vests linearly over 4 years with a 1-year cliff.
  Revocable by DAO vote, so unvested tokens return to the timelock (i.e. the DAO) if a vote
  determines revocation is warranted — this is not a unilateral founder privilege.
- **4,000,000 HLC — treasury allocation.** Vests linearly over 3 years, not revocable. Vested
  tokens flow to a treasury multisig and are spent only per DAO-approved proposals — see
  [`Treasury.md`](Treasury.md) for worked examples (bootstrapping liquidity, paying for an
  audit).

Beyond genesis, the only way new HLC enters circulation is (a) through the PSM, collateralized by
deposited reserve assets at the applicable CPI-adjusted redemption rate, or (b) through a future
contract that the DAO has explicitly voted to grant `MINTER_ROLE`. There is no discretionary
inflation.

## 6. Governance

HLC holders govern the protocol directly; voting power comes from `ERC20Votes` checkpoints (an
address's balance, delegated), so voting weight is auditable and snapshot-based rather than
signature-of-the-day.

- **Proposal threshold:** 100 HLC held (delegated) to submit a proposal — low enough that
  meaningful stakeholders, not just whales, can propose.
- **Quorum:** 4% of total supply must vote for a proposal to be actionable — intentionally low,
  to avoid governance paralysis from low turnout, at the cost of concentrated holders having
  outsized influence on any given vote (see [§8](#8-risks-and-honest-limitations)).
- **Voting period:** targets roughly one week of real time, converted into a block count from
  the actual target chain's block time rather than a number copied from an Ethereum L1 reference
  (a ~12s/block chain and a sub-second-block L2 need very different block counts for the same
  wall-clock voting window — see [`TECHNICAL-DOCS.md`](TECHNICAL-DOCS.md) for the derivation).
- **Timelock delay:** 2 days (172,800 seconds) between a proposal succeeding and its execution
  being possible — enough time for anyone watching the chain to notice and react to a proposal
  they believe is harmful, even though there is deliberately no privileged canceller once a
  proposal is queued (removing that role removed a would-be admin backdoor; see
  [`DESIGN-DECISIONS.md`](DESIGN-DECISIONS.md) §6).

A proposal's lifecycle: **Pending** (one block, so voting power is snapshotted before anyone can
react to the proposal's contents) → **Active** (the voting window) → **Succeeded** or **Defeated**
(based on for/against votes and quorum) → **Queued** (timelock delay) → **Executed**.

### Extending the protocol without touching existing contracts

Because the core contracts are immutable, new functionality is added by deploying a new,
independent contract and having the DAO grant it a narrowly-scoped role — never by patching or
upgrading an existing contract. This is not a hypothetical pattern; it is the intended path for
the near-term roadmap below, and it is documented in full (with a worked example) in
[`AddingFeature.md`](AddingFeature.md).

## 7. Roadmap

The core system — token, vesting, PSM, DAO, timelock — is deliberately minimal: it's the smallest
set of contracts that makes a CPI-indexed, DAO-governed stablecoin work end to end. Everything
below is future work, to be built as standalone contracts and connected to the existing system
purely through DAO-granted roles, per the extension pattern in [§6](#extending-the-protocol-without-touching-existing-contracts).

- **Lending module.** The first planned extension. A money-market contract (Aave/Compound-style
  pool or an isolated-pair design — to be decided via governance discussion, not pre-committed
  here) that lets HLC holders lend against or borrow HLC using other assets as collateral. It
  would be granted `MINTER_ROLE` by DAO vote so that it can mint HLC against posted collateral
  the same way the PSM mints against reserve deposits, subject to whatever collateral-factor and
  liquidation parameters the DAO approves. Because it's a separate contract, a flaw in the
  lending module cannot compromise the PSM, the token, or governance itself — the DAO can revoke
  its role and deploy a fixed version without touching anything else.
- **Staking / veHLC-style vote-locking.** A mechanism for holders to lock HLC for a period in
  exchange for boosted voting weight and/or a share of protocol revenue (e.g. PSM spread, if one
  is ever introduced by governance). Intended to align long-term holders more closely with
  governance outcomes than a simple balance-weighted vote does, and to give quorum a more stable
  base than freely-liquid balances provide.
- **Cross-chain expansion.** The first reference deployment targets Arbitrum Sepolia and has not
  happened yet; a canonical-vs-bridged
  supply model (e.g. a canonical mint on one chain with a burn-and-mint or lock-and-mint bridge
  contract elsewhere) is the leading candidate for expanding HLC to additional chains without
  fragmenting DAO authority — governance would remain on a single home chain, with bridge
  contracts on other chains granted only the specific mint/burn rights they need.
- **Additional reserve/collateral types.** The reference PSM supports a single reserve asset;
  supporting multiple reserve assets (or multiple isolated PSM instances, each with its own
  reserve and risk parameters) is a natural extension once the single-asset design has real
  usage to learn from.

None of the above exists in the contracts today, and nothing here is a commitment to a specific
implementation, timeline, or parameter set — those are exactly the kind of decisions this
protocol's own governance process exists to make. This section describes direction, not a spec.

## 8. Risks and honest limitations

This project does not benefit from overselling itself, so this section is written as plainly as
the rest of the technical documentation:

- **No professional security audit has been performed.** The contracts pass an internal test
  suite and have been through an internal adversarial review (which found and fixed one
  critical and one medium-severity issue — see [`DESIGN-DECISIONS.md`](DESIGN-DECISIONS.md)),
  but neither of those is a substitute for an independent, professional audit. One is strongly
  recommended, and planned, before real user funds are put at meaningful risk.
- **CPI-indexed redemption has an inherent reserve-adequacy tension.** If CPI rises after a
  deposit, the PSM's redemption obligation for that deposit can exceed what it holds in reserve
  for a period, and `withdraw()` will correctly revert rather than pay out more than the reserve
  can cover. The PSM can still process redemptions that preserve the existing deficit, but the
  treasury must top up the shortfall before full redemption is available. This is not a bug to be
  patched away; it is the direct consequence of promising purchasing-power stability without
  infinite reserves, and it is a real operational responsibility for the treasury and DAO, not a
  solved problem.
- **No admin emergency brake.** Removing any privileged canceller/pause role was a deliberate
  choice in favor of credible neutrality over convenience. It also means there is genuinely no
  way to stop a maliciously-passed proposal once it clears the timelock, beyond the 2-day window
  during which the community can react. Anyone relying on this protocol should understand that
  trade-off, not assume an admin safety net exists.
- **Low quorum (4%) is a deliberate but real trade-off.** It keeps governance functional with
  modest turnout, at the cost of a concentrated set of holders being able to pass proposals that
  the broader, less-engaged token base did not weigh in on.
- **CPI oracle dependency.** The system's core promise — purchasing-power stability — is only as
  good as the CPI data feeding it. A compromised, delayed, or manipulated data source degrades
  the peg's meaning even though the on-chain mechanics enforcing the *reported* rate remain
  sound.

## 9. Security model

The protocol's security rests on four claims, each of which is stated so that a reviewer can try
to break it rather than take it on trust. The full analysis lives in
[`THREAT-MODEL.md`](THREAT-MODEL.md) and [`INVARIANTS.md`](INVARIANTS.md); this is the summary.

1. **No privileged actor outside governance.** After deployment the deployer holds no roles. Every
   privileged action routes through a proposal, a vote, and the timelock. The deployment script
   asserts this and refuses to finish otherwise, and `scripts/verify-deployment.sh` re-checks it
   against a live chain without needing a key.
2. **Issuance is collateralised or it does not happen.** HLC issued through the PSM is matched by
   deposited reserves at the rate in force, and a report that would leave the PSM unable to cover
   its outstanding obligation is rejected rather than accepted-and-flagged.
3. **Redemption rights are per-address and cannot be laundered through transfers.** Redemption
   credit tracks the address that deposited, so genesis and vesting supply — which never had
   reserves behind it — cannot be redeemed against the reserve, and PSM-issued HLC that changes
   hands via a plain ERC-20 transfer does not carry its claim with it.
4. **Minting and burning authority is reachable only by deployed modules.** `MINTER_ROLE` and
   `BURNER_ROLE` are rejected for externally owned accounts, so governance cannot — accidentally
   or otherwise — turn a private key into an unbounded issuer.

**What this model does not cover.** The reserve asset's own solvency and censorship behaviour, the
integrity of the CPI series and the parties signing it, the security of whatever key material
operates the updater role, the correctness of the compiler and vendored libraries, and the
possibility that a majority of voting power is simply hostile. Several of those are addressed by
process rather than by code, and process is weaker than code.

Assurance evidence to date is a Foundry suite covering unit, configuration, differential
arithmetic, adversarial reserve-token, and stateful invariant properties; static analysis; and an
internal adversarial review. **None of that is an independent audit, and no independent audit has
been performed.** Recruiting one is tracked in
[issue #126](https://github.com/fredrikblau/halal-protocol/issues/126).

## 10. Prior art and what is different here

Indexing a claim to a price index is old and well understood outside crypto: inflation-linked
government bonds such as US TIPS pay a principal that tracks CPI, and wage and rent escalation
clauses do the same thing contractually. Halal applies that established idea to a reserve-backed
on-chain token; the novelty is not the indexation itself.

Within crypto, three neighbouring designs are worth distinguishing:

- **Fiat-pegged stablecoins** hold a reserve and target a constant *nominal* price. They solve
  volatility against the dollar and, by construction, inherit the dollar's loss of purchasing
  power. That is the gap this protocol targets.
- **Rebasing tokens** adjust every holder's balance to move a price toward a target. Halal
  deliberately does not rebase: balances are stable and the *redemption rate* moves instead, which
  keeps ERC-20 accounting, integrations, and vote weights intact.
- **Moving-target designs** (a redemption price that drifts under controller logic) share the idea
  of a peg that is not a constant, but derive the target from market feedback rather than from a
  published external index. Halal's target is an external, attestable series, which trades
  autonomy for auditability: anyone can check the reported figure against the published source.

The PSM pattern itself — a contract that mints and burns against deposited collateral at a
governed rate — is prior art from existing DeFi systems and is used here largely as it is
understood elsewhere, with the CPI-adjusted rate and per-address redemption accounting layered on
top.

## 11. References

- OpenZeppelin Contracts — `ERC20Votes`, `ERC20Permit`, `AccessControl`, `Governor`,
  `TimelockController`, `Ownable2Step`: <https://docs.openzeppelin.com/contracts>
- EIP-712, typed structured data hashing and signing: <https://eips.ethereum.org/EIPS/eip-712>
- EIP-2612, permit extension for ERC-20: <https://eips.ethereum.org/EIPS/eip-2612>
- US Bureau of Labor Statistics, Consumer Price Index: <https://www.bls.gov/cpi/>
- US Treasury, Treasury Inflation-Protected Securities:
  <https://www.treasurydirect.gov/marketable-securities/tips/>
- Repository documentation index: [`../README.md`](../README.md)

## 12. Summary

Halal is a from-scratch attempt at a stablecoin that stabilizes purchasing power rather than
nominal price, governed entirely by the people who hold it, with no upgrade path and no admin
key once launched. The core system is intentionally small; a lending module, a vote-locking
staking mechanism, cross-chain expansion, and multi-collateral PSM support are the near-term
roadmap, each to be added as an independent contract granted a narrow role by governance vote —
never as a patch to the contracts described here. It is early, unaudited, and honest about both
facts.
