# Halal (HLC)

[![CI](https://github.com/fredrikblau/halal-protocol/actions/workflows/ci.yml/badge.svg)](https://github.com/fredrikblau/halal-protocol/actions/workflows/ci.yml)
[![Security](https://github.com/fredrikblau/halal-protocol/actions/workflows/security.yml/badge.svg)](https://github.com/fredrikblau/halal-protocol/actions/workflows/security.yml)
[![Slither](https://github.com/fredrikblau/halal-protocol/actions/workflows/slither.yml/badge.svg)](https://github.com/fredrikblau/halal-protocol/actions/workflows/slither.yml)
[![Deep contract tests](https://github.com/fredrikblau/halal-protocol/actions/workflows/deep-tests.yml/badge.svg)](https://github.com/fredrikblau/halal-protocol/actions/workflows/deep-tests.yml)
[![OpenSSF Scorecard](https://api.securityscorecards.dev/projects/github.com/fredrikblau/halal-protocol/badge)](https://securityscorecards.dev/viewer/?uri=github.com/fredrikblau/halal-protocol)
[![Latest release](https://img.shields.io/github/v/release/fredrikblau/halal-protocol?include_prereleases&label=latest%20release)](https://github.com/fredrikblau/halal-protocol/releases)
[![GitHub stars](https://img.shields.io/github/stars/fredrikblau/halal-protocol?style=social)](https://github.com/fredrikblau/halal-protocol/stargazers)
[![GitHub forks](https://img.shields.io/github/forks/fredrikblau/halal-protocol?style=social)](https://github.com/fredrikblau/halal-protocol/network/members)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

Halal is a DAO-governed, CPI-indexed stablecoin protocol. **HLC** minted through its Peg Stability
Module (PSM) is redeemable against a reserve asset such as DAI or USDC at a CPI-adjusted rate;
the goal is for HLC's *purchasing power*, not just its nominal reserve-asset price, to stay roughly
stable. The separate fixed genesis allocation (6,000,000 HLC to the team and 4,000,000 HLC to the
treasury, both time-vested) is not reserve-backed. PSM issuance, protocol parameters, and treasury
spending are controlled by an on-chain DAO (OpenZeppelin `Governor` + `TimelockController`) once
the system is fully deployed and handed off — there is no unilateral admin key in that final state.

This is a genuine, from-scratch implementation, not a fork or a wrapper: five immutable core
contracts (`HalalToken`, `HalalVesting`, `HalalPSM`, `HalalDAO`, `HalalTimelock`), an optional signed
CPI adapter, a Foundry test suite, and a Next.js frontend, all in this monorepo.

The fastest way to see the complete system is `./scripts/local-demo.sh`: it starts a disposable
Anvil chain, deploys the wired contracts, seeds a fresh local CPI report, and opens the frontend
with a faucet-backed local reserve.
No external RPC key or real funds are needed for the demo.

## Contribute

Start with the [good first issues](https://github.com/fredrikblau/halal-protocol/issues?q=is%3Aissue+is%3Aopen+label%3A%22good+first+issue%22):

- Run `./scripts/local-demo.sh` to see the contracts and dApp together.
- Follow the [local development walkthrough](docs/LOCAL-DEVELOPMENT.md) from a clean checkout.
- Use the [local-demo troubleshooting guide](docs/LOCAL-DEMO-TROUBLESHOOTING.md) if a prerequisite,
  port, or stale local configuration blocks the demo.
- Run `make verify` before opening a pull request.
- Pick a bounded task from the [open good-first-issue list](https://github.com/fredrikblau/halal-protocol/issues?q=is%3Aissue+is%3Aopen+label%3A%22good+first+issue%22),
  such as [deployment-manifest source-label testing](https://github.com/fredrikblau/halal-protocol/issues/100),
  [CPI source policy documentation](https://github.com/fredrikblau/halal-protocol/issues/80), or
  [accessibility smoke coverage](https://github.com/fredrikblau/halal-protocol/issues/102).
- Help coordinate the first carefully gated [Arbitrum Sepolia deployment](https://github.com/fredrikblau/halal-protocol/issues/40).
- Review the bounded [security challenge](https://github.com/fredrikblau/halal-protocol/issues/16) or
  [production CPI adapter design](https://github.com/fredrikblau/halal-protocol/issues/17).
- Use [Discussions](https://github.com/fredrikblau/halal-protocol/discussions) for design questions.
- Report security vulnerabilities through [`SECURITY.md`](SECURITY.md), not a public issue.

## Why this project is interesting

Most stablecoins target a nominal unit of a reserve asset. Halal explores a different target:
keeping HLC's reserve-asset redemption rate moving with consumer-price inflation, so one HLC is
intended to represent roughly stable purchasing power over time. That idea is paired with a
conservative accounting model:

- Only reserve deposited through the PSM creates a redeemable HLC claim; the fixed team and treasury
  allocations are explicitly separate and not reserve-backed.
- CPI updates are bounded by absolute limits, per-update movement, cadence, report freshness, and
  the reserve held for outstanding claims.
- Governance is delayed and observable: protocol roles route through an OpenZeppelin Governor and
  TimelockController, while deployment tooling verifies chain identity and final role wiring.

## Proof at a glance

| Reviewer question | Evidence in this repository |
| --- | --- |
| Does the accounting have stateful coverage? | 196 Foundry tests, including 13 PSM invariants, differential arithmetic checks, and fuzzing |
| Do invariants cover CPI changes? | [`docs/INVARIANTS.md`](docs/INVARIANTS.md) models governance rate changes and reserve top-ups |
| Can a deployment be checked without a private key? | [`scripts/verify-deployment.sh`](scripts/verify-deployment.sh) |
| Can registry readiness be checked offline? | [`scripts/preflight-deployment.mjs`](scripts/preflight-deployment.mjs) or `make deployment-preflight` (no RPC, signing, or writes) |
| Can I inspect the full system locally? | [`./scripts/local-demo.sh`](scripts/local-demo.sh) on a disposable Anvil chain |
| Can I exercise the signed CPI adapter locally? | [`make adapter-demo`](Makefile), a disposable 31337-only two-of-two report rehearsal; included in `make verify` and hosted CI |
| Does the PSM fail closed on missing or stale CPI data? | `HalalPSM` rejects deposits until `isCPIReportFresh()` is true; the dApp mirrors the gate |
| Can an operator audit a deployment without a wallet? | [`scripts/check-deployment-health.sh`](scripts/check-deployment-health.sh) combines wiring and PSM health checks |
| Can I model CPI-driven reserve needs reproducibly? | [`docs/ECONOMIC-MODEL.md`](docs/ECONOMIC-MODEL.md) and `make economic-model` |
| Can I reproduce an official CPI report payload? | [`scripts/parse-bls-cpi.mjs`](scripts/parse-bls-cpi.mjs) and [`docs/CPI-ADAPTER-SPEC.md`](docs/CPI-ADAPTER-SPEC.md) |
| Can I verify a report before submitting it? | [`scripts/verify-cpi-report.mjs`](scripts/verify-cpi-report.mjs) checks live adapter/PSM watermarks and freshness, then recovers each EIP-712 signer without private keys |
| Does governance decode CPI adapter actions? | The dApp includes the generated `CPIReportAdapter` ABI for signer, threshold, ownership, and report actions |
| Can the active CPI signer set be audited? | `CPIReportAdapter.getSigners()` and `check-psm-health.sh` expose the current addresses after each rotation |
| Does the dApp show adapter custody state? | The dashboard and PSM page show the live adapter owner, source ID, quorum, signers, and last submitted report |
| Does the dApp verify adapter/PSM report alignment? | It compares the adapter watermark with the PSM's accepted-report watermark and flags divergence |
| Can an operator inspect deployment health without a wallet? | The read-only [`/health` page](https://github.com/fredrikblau/halal-protocol/tree/main/app/src/app/health) checks contract wiring, CPI freshness, reserve coverage, and adapter alignment |
| Does the dApp expose deployment evidence? | The dashboard shows the registry's deployment transaction, verified-source, and deployment-journal links when they are published |
| Can I inspect the CPI timeline? | The dashboard reads recent `CPIUpdated` events with block, transaction, source, and rate-change context |
| Are public deployment addresses reviewable? | [`docs/DEPLOYMENT-REGISTRY.md`](docs/DEPLOYMENT-REGISTRY.md) and the checked-in registry |
| Are generated frontend interfaces kept in sync? | ABI regeneration is a required CI check |
| Does CI exercise a configured dApp? | `scripts/local-app-smoke.sh` deploys disposable Anvil state, builds with live addresses, and checks the main routes |
| Is the CI supply chain independently scored? | The pinned-action [`Scorecard workflow`](.github/workflows/scorecard.yml) publishes OpenSSF SARIF results |
| What static-analysis scope has been checked? | [`docs/STATIC-ANALYSIS.md`](docs/STATIC-ANALYSIS.md) records the pinned Slither command, source scope, and interpretation |
| Can a permit-capable wallet approve and act in one transaction? | `HalalPSM` exposes bounded EIP-2612 paths for deposits, withdrawals, redeemable-credit transfers, and claim retirement |
| Does the dApp expose permit transfers? | The redeemable-credit form offers “Sign & transfer in one transaction” with approval fallback |
| Does the dApp expose permit claim retirement? | The same form offers selector-gated “Sign & retire claim” while preserving the approval fallback |
| Does the dApp expose permit withdrawals? | The swap form detects the deployed PSM selector and offers signed HLC withdrawal with approval fallback |
| Are release sources checksummed and attestable? | [`Release artifacts`](.github/workflows/release-artifacts.yml) publishes a reproducible source bundle, SHA-256 checksum, and build-provenance attestation |
| Is the security posture stated plainly? | [`SECURITY.md`](SECURITY.md) and [`docs/THREAT-MODEL.md`](docs/THREAT-MODEL.md) |
| Is the production CPI integration boundary defined? | [`docs/CPI-ADAPTER-SPEC.md`](docs/CPI-ADAPTER-SPEC.md) and [issue #17](https://github.com/fredrikblau/halal-protocol/issues/17) |
| Is CPI source policy recorded separately from on-chain checks? | [`docs/CPI-SOURCE-POLICY-TEMPLATE.md`](docs/CPI-SOURCE-POLICY-TEMPLATE.md) |
| Can a reviewer trace a CPI report from source publication to PSM acceptance? | [`docs/CPI-ADAPTER-SPEC.md`](docs/CPI-ADAPTER-SPEC.md) includes the submission sequence and evidence map |

The project is still unaudited and not production-ready. The table is evidence of engineering
discipline, not a safety guarantee.

## Status & risk

**This protocol has not undergone a professional security audit, and there is no bug bounty
program yet.** The contracts pass their own test suite (196/196 at the time of writing — 183 unit
and configuration tests plus 13 stateful invariants; see
`contracts/test/`), but a passing test suite is not a substitute for an audit, and this repo
should not be treated as safe to use with real, meaningful funds. If you deploy or interact with
any instance of these contracts, you do so at your own risk. See [`SECURITY.md`](SECURITY.md) for
the responsible-disclosure process if you find a vulnerability, and please don't treat anything
in this README, or in `docs/`, as a claim that the software is production-ready — it's an
active, unaudited, open-source project, and honesty about that is a design goal in its own right.

## Architecture, briefly

- **`HalalToken` (HLC)** — `ERC20Votes` + `ERC20Permit` + `AccessControl`. Genesis 6M/4M
  team/treasury allocation minted once via `initialMint`; all further minting requires
  `MINTER_ROLE`, while accounting-aware burns require `BURNER_ROLE`; the DAO grants those roles
  narrowly (initially to the PSM, and to future modules only by case-by-case vote).
- **`HalalVesting`** — one instance per beneficiary (team, treasury), linear vesting with an
  optional cliff; the team schedule is DAO-revocable, the treasury schedule is not.
- **`HalalPSM`** — mints/burns HLC against a reserve asset at a CPI-adjusted rate; CPI is
  submitted by a rate-limited `UPDATER_ROLE` (intended to be a Chainlink Functions consumer or
  similar in production) with a DAO-gated manual override for emergencies.
- **`CPIReportAdapter`** — optional EIP-712 quorum module that authenticates signed reports before
  forwarding them to the PSM; it is unaudited and does not authenticate the underlying statistics
  agency by itself.
- **`HalalDAO`** — an OpenZeppelin `Governor` (settings + simple counting + votes + quorum
  fraction + timelock control) wired to HLC's vote-weight and to `HalalTimelock`.
- **`HalalTimelock`** — a standard `TimelockController` enforcing an execution delay between a
  passed proposal and its effects taking place.

For the full picture — diagrams, the access-control matrix, a worked governance-proposal
walkthrough, and the exact API surface — see:

- [`docs/WHITEPAPER.md`](docs/WHITEPAPER.md) — the protocol whitepaper: the problem, the
  CPI-peg mechanism, tokenomics, governance, roadmap, and an honest risks section.
- [`docs/Architecture.md`](docs/Architecture.md) — system diagrams and contract call flow.
- [`docs/TECHNICAL-DOCS.md`](docs/TECHNICAL-DOCS.md) — the fullest spec: deployment steps,
  governance parameters, API reference, security notes.
- [`docs/DAO-Guide.md`](docs/DAO-Guide.md) — governance walkthrough (proposal lifecycle, `.env`
  setup, troubleshooting).
- [`docs/Treasury.md`](docs/Treasury.md) — how vesting/treasury flows work in practice.
- [`docs/AddingFeature.md`](docs/AddingFeature.md) — the pattern for adding new functionality to
  the already-deployed, non-upgradeable system (new contract + DAO-granted role, not a patch to
  existing contracts).
- [`docs/DESIGN-DECISIONS.md`](docs/DESIGN-DECISIONS.md) — where the actual implementation
  deliberately deviates from those planning docs, and why. Worth reading before assuming a
  number or behavior described in the docs above is exactly what the code does.
- [`docs/THREAT-MODEL.md`](docs/THREAT-MODEL.md) — assets, trust boundaries, attack scenarios,
  mitigations, and unresolved risks for reviewers and deployment operators.
- [`docs/OPERATOR-RUNBOOK.md`](docs/OPERATOR-RUNBOOK.md) — launch acceptance, monitoring, CPI
  updater operations, governance review, and incident response.
- [`scripts/verify-governance-payload.mjs`](scripts/verify-governance-payload.mjs) — offline,
  fail-closed preflight for exact governance targets, values, selectors, and calldata.
- [`docs/INVARIANTS.md`](docs/INVARIANTS.md) — the stateful PSM properties exercised by Foundry
  and the exact scope of those guarantees.
- [`docs/ECONOMIC-MODEL.md`](docs/ECONOMIC-MODEL.md) — a dependency-free CPI and reserve-adequacy
  scenario model with machine-readable output.
- [`docs/DEPLOYMENT-REGISTRY.md`](docs/DEPLOYMENT-REGISTRY.md) — how operators publish verified
  deployment addresses without copying unverified values into a frontend environment.
- [`docs/DEPLOYMENT-JOURNAL-TEMPLATE.md`](docs/DEPLOYMENT-JOURNAL-TEMPLATE.md) — a copyable evidence
  record joining deployment, reserve, CPI, health, monitoring, and final decision review.
- [`docs/INCIDENT-TABLETOP-WORKSHEET.md`](docs/INCIDENT-TABLETOP-WORKSHEET.md) — a safe rehearsal
  worksheet for operational failures and recovery evidence.
- [`docs/CONTRIBUTOR-MAP.md`](docs/CONTRIBUTOR-MAP.md) — concrete contribution paths for security,
  oracle integrations, monitoring, economics, governance, dApp UX, and documentation.
- [`docs/LOCAL-CPI-REPORT-WALKTHROUGH.md`](docs/LOCAL-CPI-REPORT-WALKTHROUGH.md) — copy-paste local
  CPI report preparation and verification lifecycle.
- [Security review challenge #16](https://github.com/fredrikblau/halal-protocol/issues/16) — a bounded
  starting point for independent PSM and CPI review.
- [`docs/ROADMAP.md`](docs/ROADMAP.md) — the risk-ordered path from unaudited reference
  implementation to independently reviewed testnet and production readiness.

Those docs describe design intent and were written to guide the implementation; a few figures in
them are approximate/aspirational rather than exact. `contracts/src/` is the ground truth for
anything you need to be precise about (role names, parameter bounds, function signatures) —
read the NatSpec comments there, they're kept accurate and up to date.

## Repository layout

```
contracts/   Foundry Solidity project — five core contracts plus CPIReportAdapter,
             tests, deploy/example scripts.
app/         Next.js frontend dApp.
docs/        Design and governance documentation (see above).
```

## Quickstart

From the repository root, `make verify` runs the full contract and frontend verification suite,
including a configured production dApp smoke test on disposable Anvil state.
The individual commands below are useful when working on one subtree.

### Contracts

```bash
cd contracts
forge install     # fetch git-submodule dependencies (forge-std, OpenZeppelin Contracts)
forge test        # run the full test suite
```

To run the complete dApp locally against Anvil with one command:

```bash
./scripts/local-demo.sh
```

The wrapper starts a disposable Anvil chain, deploys the system, writes `app/.env.local`, and starts
the frontend. The local deployment uses a faucet reserve token intentionally named `mDAI`; it must
never be used as a real reserve asset on a public network. For manual deployment or a custom local
beneficiary, see `contracts/script/DeployLocal.s.sol`.

See [`contracts/script/Deploy.s.sol`](contracts/script/Deploy.s.sol) for the deployment script,
[`contracts/script/Examples.s.sol`](contracts/script/Examples.s.sol) for example governance
proposals, and [`contracts/script/PrepareCPIAdapterHandoff.s.sol`](contracts/script/PrepareCPIAdapterHandoff.s.sol)
for reviewed CPI adapter handoff calldata. For a read-only proposal preflight, run
`node scripts/verify-governance-payload.mjs --bundle <bundle.json> --policy <policy.json>`. Read `docs/DAO-Guide.md` and `docs/TECHNICAL-DOCS.md`
for the full deployment walkthrough and required environment variables.

### Frontend

```bash
cd app
pnpm install
pnpm dev          # local dev server
```

Run `pnpm build` to produce a production build.

When a deployment is configured, the dApp supports wallet-free read-only browsing. Set
`NEXT_PUBLIC_READ_CHAIN_ID` if several deployments are configured; connect a wallet only when you
want to approve transactions, swap, vote, or use another signing action.

## Contributing

Contributions are welcome — bug fixes, tests, documentation, and (after a discussion in an issue
first) new features. See [`CONTRIBUTING.md`](CONTRIBUTING.md) for the fork/branch/PR workflow,
how to run each subtree's tests, code style, and commit conventions. Changes to `contracts/src/`
get extra scrutiny given this is a live financial protocol — see the note in `CONTRIBUTING.md`
about that specifically. Please also read [`CODE_OF_CONDUCT.md`](CODE_OF_CONDUCT.md).

## Security

Found a vulnerability, especially one that could put funds at risk? Please **do not** open a
public issue — see [`SECURITY.md`](SECURITY.md) for the private responsible-disclosure process,
scope, and what response times to expect.

## License

MIT — see [`LICENSE`](LICENSE).

If this project contributes to research or another open-source project, see [`CITATION.cff`](CITATION.cff)
for citation metadata.
