# Next steps

This file answers one question: **what should someone work on next, and why that rather than
something else?** It is maintained for both human contributors and coding agents, and it is
deliberately ordered by what unblocks the most other work.

The protocol remains unaudited, has no public deployment, and no bug bounty. Nothing in this file
changes that. A task being listed here is not evidence that the underlying risk is solved.

For the longer risk-ordered arc, see [`ROADMAP.md`](ROADMAP.md). This file is the shorter,
current-state view.

## 1. The two real gates

Everything else in this repository is secondary to these, and neither is blocked on more code.
Both need a decision from the maintainer, not another pull request.

### Independent security review — [issue #126](https://github.com/fredrikblau/halal-protocol/issues/126)

The contracts are immutable by design, so a review has to happen before a deployment that matters,
not after. The repository already provides what a reviewer needs to start: the threat model,
invariants, design decisions, a complete Foundry suite, a deployment verifier, and a disposable
local demo.

What is missing is a reviewer. That requires either a budget or a specific person, which is a
maintainer decision.

### First Arbitrum Sepolia reference deployment — [issue #40](https://github.com/fredrikblau/halal-protocol/issues/40)

Blocked on three choices that only the maintainer can make:

- which reserve token the deployment uses, and why that one
- multisig addresses for the team and treasury beneficiaries — the deployment verifier rejects
  deployer-controlled beneficiaries outside the local demo, so real custody must exist first
- who operates the CPI updater, under the custody rules in
  [`CPI-ADAPTER-SPEC.md`](CPI-ADAPTER-SPEC.md)

Once those exist, the mechanical path is already built and tested: deploy, then publish addresses,
verified source links, the deployment log, and `scripts/verify-deployment.sh` output, following
[`DEPLOYMENT-REGISTRY.md`](DEPLOYMENT-REGISTRY.md).

## 2. Repository health, in priority order

These are bounded, do not need a maintainer decision, and are worth doing before adding features.

1. **Fix the intermittent a11y test failure —
   [issue #188](https://github.com/fredrikblau/halal-protocol/issues/188).** Highest value of
   anything on this list. `a11y-critical-states.spec.ts` intermittently fails when a governance
   `mockCPI` call reverts. It reproduces on the default branch, so it fails a *required* check on
   unrelated pull requests and costs a rerun each time. It taxes every contributor, not just the
   person who hit it.
2. **Resolve the frontend dependency majors —
   [issue #136](https://github.com/fredrikblau/halal-protocol/issues/136).** Two Dependabot pull
   requests are deliberately held open because their titles understate them:
   [#184](https://github.com/fredrikblau/halal-protocol/pull/184) contains `wagmi` 2 → 3, and
   [#185](https://github.com/fredrikblau/halal-protocol/pull/185) contains TypeScript 5 → 7,
   ESLint 9 → 10, and `@types/node` 20 → 26. The dApp's fail-closed contract-read behaviour is
   asserted mostly through mocked RPC failures, so a green suite alone does not prove those
   semantics survived a `wagmi` major. Upgrade deliberately and re-verify the fail-closed paths.
3. **Broaden adversarial reserve coverage.** The adversarial invariant suite now models
   fee-on-transfer, false-returning, no-return, transfer-capped, and rebasing reserve tokens. Longer
   stateful runs on release candidates remain open work.
4. **Pick up an unclaimed starter issue.** See the
   [good first issues](https://github.com/fredrikblau/halal-protocol/issues?q=is%3Aissue+is%3Aopen+label%3A%22good+first+issue%22)
   filter for the current live set rather than a list hard-coded here, which goes stale.

## 3. Working effectively in this repository

Points that are not obvious from the source and have cost real time.

### Documented test counts are enforced

`make test-counts` compares the live Foundry suite against the counts written in `README.md`,
`CONTRIBUTING.md`, `contracts/README.md`, `docs/Architecture.md`, `docs/DAO-Guide.md`, and
`docs/TECHNICAL-DOCS.md`. If you add or remove tests, update all six or the check fails.

Do not hard-code a count in a test to satisfy it — that reintroduces exactly the drift the check
exists to prevent.

### The merge queue is serial, so keep it short

`main` requires strict status checks, meaning every branch must be current with `main` before it
merges. Each merge puts every other open branch behind again. **Throughput is therefore about one
pull request per CI cycle regardless of how many are ready.**

The practical consequence: opening work faster than it lands does not speed anything up. It creates
conflicts, because long-lived branches drift against the same documentation and test files. Prefer
finishing and landing a change over starting another.

### A red check is often not your change

Before assuming a failure is yours, check these known causes:

| Symptom | Cause | Action |
| --- | --- | --- |
| `Frontend (Next.js)` fails in `pnpm audit` with `TimeoutError` | npm advisory endpoint outage, not a dependency problem | The step retries transport failures automatically; if it still fails, confirm the endpoint is reachable before investigating dependencies |
| `a11y-critical-states.spec.ts` fails with a reverted `mockCPI` | [Issue #188](https://github.com/fredrikblau/halal-protocol/issues/188), reproduces on `main` | Rerun the failed job; do not treat it as caused by your branch |
| A fork pull request reports **no checks at all** | First-time-contributor workflow runs sit at `action_required` | A maintainer approves the workflow runs |
| `gh pr update-branch` reports a conflict on a fork PR | The API cannot update a fork branch | Merge `main` locally and push to the fork; verify the merge is genuinely clean first |
| Pushing a branch that merged `main` is rejected over HTTPS | The token lacks `workflow` scope and the merge touched `.github/workflows/` | Push over SSH |

Two of these look identical to a real defect in a pull request. Confirm which one you have before
rewriting code.

### Verification commands

```shell
make verify           # complete local gate
make test-counts      # documented Foundry counts vs the live suite
make markdown-links   # tracked Markdown links and anchors
make workflow-lint    # pinned actionlint; requires Docker
```

`make workflow-lint` needs a running Docker daemon. Without it, the hosted workflow-syntax job is
the authority.

## 4. What not to do

- Do not add hidden admin or upgrade paths to `contracts/src/`. Core contracts are non-upgradeable
  by design; new capability belongs in a separate, narrowly scoped module granted roles by
  governance.
- Do not describe the protocol as audited, production-ready, or safe for meaningful funds anywhere
  in code, documentation, issues, or release notes.
- Do not put exploit detail for a fund-risking bug in a public issue or pull request. Use the
  private route in [`SECURITY.md`](../SECURITY.md).
- Do not add an address to `app/src/config/deployment-registry.json` before the evidence required by
  [`DEPLOYMENT-REGISTRY.md`](DEPLOYMENT-REGISTRY.md) exists.
- Do not commit private keys, seed phrases, RPC credentials, or real deployment secrets. The local
  demo's Anvil mnemonic is public and disposable, and must never be used against a public RPC.
