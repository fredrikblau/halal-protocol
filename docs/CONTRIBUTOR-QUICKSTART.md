# Contributor quickstart

This is the shortest safe path from a clean clone to a first useful contribution. It assumes
Git, Foundry (`forge`, `anvil`, and `cast`), Node.js 22+, and pnpm 11 are already installed.

If a protocol term is unfamiliar while choosing a task, use the [protocol glossary](GLOSSARY.md)
before searching through the full contract sources.

## 1. Clone and verify the toolchain

```shell
git clone --recurse-submodules https://github.com/fredrikblau/halal-protocol.git
cd halal-protocol
node --version       # 22 or newer
pnpm --version       # 11
forge --version
anvil --version
cast --version
pnpm --dir app install --frozen-lockfile
```

The `--recurse-submodules` flag is required because the Foundry project pins OpenZeppelin and
forge-std as Git submodules. If you already cloned without it, initialize the same dependencies
with `git submodule update --init --recursive` before running any contract or local-demo command.

## 2. See the complete protocol locally

```shell
make app-smoke
```

This starts a disposable Anvil chain on `127.0.0.1:18545`, deploys the local contracts and signed
CPI adapter, builds the dApp, and exercises its important routes. A successful run ends with:

```text
Configured local dApp smoke test passed on chain 31337.
```

The smoke test uses only local state and a faucet-backed `mDAI` token. It does not need a wallet,
an RPC key, or real funds. To explore the UI manually instead, run `./scripts/local-demo.sh` and
open <http://localhost:3000>; press `Ctrl-C` when finished. See the
[troubleshooting guide](LOCAL-DEMO-TROUBLESHOOTING.md) if either command cannot start.

## 3. Pick a bounded contribution

Start with the [open good-first issues](https://github.com/fredrikblau/halal-protocol/issues?q=is%3Aissue+is%3Aopen+label%3A%22good+first+issue%22).
Documentation, frontend, monitoring, and economic-model changes are safe places to learn the
repository. Open or comment on an issue before starting a non-trivial change; never put secrets,
private keys, or public security findings in an issue or pull request.

For a documentation-only change, check the result with:

```shell
git diff --check
```

For code or contract changes, follow the relevant commands in
[`LOCAL-DEVELOPMENT.md`](LOCAL-DEVELOPMENT.md), run `make verify` before requesting review, and
include the exact commands and commit SHA in the pull request. Contract changes also require the
security and design context in [`CONTRIBUTING.md`](../CONTRIBUTING.md).

## 4. Submit a reviewable pull request

```shell
git checkout -b docs/short-description
git status --short
git diff --check
```

Use a [Conventional Commit](https://www.conventionalcommits.org/) subject, explain what changed
and why, link the issue, and describe whether deployed behavior changes. The full contribution
rules are in [`CONTRIBUTING.md`](../CONTRIBUTING.md); vulnerability reports belong in
[`SECURITY.md`](../SECURITY.md), not in a public issue.
