# Contributing to Halal (HLC)

Thanks for considering a contribution. Halal is a real financial protocol (a CPI-indexed
stablecoin plus the DAO that governs it), so contributions to `contracts/` are held to a higher
bar than a typical app repo — see the [roadmap](docs/ROADMAP.md) and [Changes to
`contracts/src/`](#changes-to-contractssrc) below before you dive in.

## Ground rules

- Be respectful and constructive. See [`CODE_OF_CONDUCT.md`](CODE_OF_CONDUCT.md).
- For anything beyond a small fix (a new feature, a behavior change, a non-trivial refactor),
  **open an issue first** to discuss the approach before writing code. This avoids wasted work on
  a PR that turns out to be the wrong direction.
- For anything that looks like it might be a security vulnerability rather than an ordinary bug,
  **don't open a public issue** — see [`SECURITY.md`](SECURITY.md) for the private disclosure
  process instead.

## Fork / branch / PR flow

New to the repository? Follow the [ten-minute contributor quickstart](docs/CONTRIBUTOR-QUICKSTART.md)
for the clean-clone tool check, disposable local smoke test, and first contribution path.

1. Fork the repository and clone your fork.
2. Create a topic branch off `main`: `git checkout -b feat/short-description`.
3. Make your changes, following the code style and testing expectations below.
4. Push your branch to your fork and open a pull request against `main` on the upstream repo.
5. Fill out the PR template — describe *what* changed and *why*, and link the issue it addresses
   if there is one.
6. Be responsive to review feedback. A maintainer will merge once checks pass and review is
   satisfied.

The `main` branch is protected: changes must arrive through a pull request, receive one approval from
an independent reviewer, pass path detection plus every applicable Contracts, Scripts, generated-ABI,
and Frontend CI check, use linear history, and resolve review conversations. Path-filtered jobs are
skipped safely for unrelated documentation changes. Code-owner review remains encouraged for contract
and deployment changes, but approval from one specific account is not required. Administrators may
bypass the rule for repository recovery, but normal development should use the review path.

The protected checks also include Slither static analysis, extended fuzzing/invariants, and both
CodeQL language analyses. Dependency review and OpenSSF Scorecard remain visible advisory workflows;
dependency review runs only on pull requests and Scorecard reports supply-chain posture.

CI (`.github/workflows/ci.yml`) runs the contracts, dependency-light script, ABI, and frontend test
suites on every relevant push and PR. Markdown changes also run the local link and anchor checker
(`make markdown-links`). A PR won't be merged with a red CI run.

## Running the test suites

For a first end-to-end run, follow the [local development walkthrough](docs/LOCAL-DEVELOPMENT.md).
It explains the disposable Anvil workflow, the temporary frontend configuration, and the boundary
between local-demo defaults and production deployment safety.

For release review, follow the [release verification walkthrough](docs/RELEASE-VERIFICATION.md)
from a clean clone. It verifies tag identity, source-bundle checksums, generated ABIs, local gates,
and hosted checks without private keys or public RPCs.

For deployment environment guards, see the [deployment-config test guide](docs/DEPLOYMENT-CONFIG-TESTS.md)
before changing `contracts/script/Deploy.s.sol` or `contracts/test/DeployConfig.t.sol`.

From the repository root, `make verify` runs the complete contract and frontend verification
workflow, including a configured production dApp smoke test on disposable Anvil state. The subtree
commands below are useful for faster iteration.

### Contracts (`contracts/`)

The contracts are a [Foundry](https://book.getfoundry.sh/) project.

```bash
cd contracts
forge install      # pulls in the git-submodule dependencies (forge-std, OpenZeppelin)
forge build
forge test         # full 196-test suite, including 13 stateful invariants
forge test -vvv    # verbose, useful when a test fails
forge fmt --check src test script  # verify first-party formatting without rewriting dependencies
forge fmt           # actually reformat
```

### Frontend (`app/`)

The frontend is a Next.js app using `pnpm`.

```bash
cd app
pnpm install
pnpm gen:abis       # regenerate interfaces after Solidity changes
pnpm lint
pnpm build   # production build; also run `pnpm dev` locally for interactive testing

# From the repository root, run the configured production route smoke test:
cd .. && make app-smoke
```

## Code style

- **Solidity**: run `forge fmt src test script` before committing — `contracts/foundry.toml` pins the formatting
  rules (120-char line length, 4-space tabs, double quotes) so there's no ambiguity about style.
  CI runs `forge fmt --check` and will fail on unformatted code.
- **Frontend**: follow the existing ESLint configuration in `app/eslint.config.mjs` (`pnpm lint`
  in `app/`). Match the conventions already used in the surrounding code (component structure,
  naming, hooks usage) rather than introducing a new pattern for a single file.

## Commit messages

This project uses [Conventional Commits](https://www.conventionalcommits.org/). Prefix your
commit subject with a type, e.g.:

- `feat: add reserve health view to PSM dashboard`
- `fix: correct rounding in HalalPSM._hlcToReserve`
- `docs: clarify voting-period block-time caveat`
- `test: add fuzz test for HalalVesting.revoke`
- `chore: bump OpenZeppelin Contracts submodule`
- `ci: cache forge dependencies in workflow`

Squash trivial "fix typo" follow-up commits into a single logical commit where practical before
merge; it's fine to keep a messier history while a PR is in review.

## Changes to `contracts/src/`

`contracts/src/` is the actual on-chain logic — `HalalToken`, `HalalVesting`, `HalalPSM`,
`HalalDAO`, `HalalTimelock`. These contracts are **not upgradeable** by design (see
[`docs/AddingFeature.md`](docs/AddingFeature.md) for the intended extension pattern — new
functionality is added as a separate contract granted a role by DAO vote, not by patching
existing contracts), and the protocol is **unaudited** (see [`SECURITY.md`](SECURITY.md)). That
combination means bugs here are unusually expensive to get wrong. So, for any PR touching
`contracts/src/`:

- **Discuss significant changes in an issue first.** "Significant" means anything beyond a
  comment/NatSpec fix or an obviously-safe typo — if in doubt, open the issue.
- **Tests are not optional.** New behavior needs new tests; changed behavior needs updated
tests demonstrating the change is correct. `contracts/test/` currently passes 196/196 (183
  unit/configuration tests plus 13 stateful invariants) — a PR that
  drops that number, or that changes contract behavior without a corresponding test change, will
  need justification before it can be merged.
- **Explain the "why," not just the "what."** For contract changes especially, reviewers need to
  understand the reasoning to properly evaluate risk — see
  [`docs/DESIGN-DECISIONS.md`](docs/DESIGN-DECISIONS.md) for the kind of rationale we're looking
  for and for context on prior deliberate deviations from the original design docs.
- **Consider gas, access control, and edge cases explicitly** in the PR description — who can
  call the new/changed function, what happens at zero/max values, and whether the change
  interacts with the PSM's collateralization accounting or the DAO's timelock-gated execution
  path.

We'd rather take longer on a `contracts/src/` PR and get it right than move fast on code that
moves real value.
