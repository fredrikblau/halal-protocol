# Local development walkthrough

This walkthrough takes a clean checkout to a running Halal dApp on a disposable Anvil chain.
It uses only local contracts, a faucet-backed `mDAI` reserve, and the published Anvil development
mnemonic. Never point these commands at a public RPC or use the demo token as real collateral.

If a prerequisite, port, or stale local configuration prevents the demo from starting, see the
[local-demo troubleshooting guide](LOCAL-DEMO-TROUBLESHOOTING.md).

## Prerequisites

Install:

- Git
- Foundry (`forge`, `anvil`, and `cast`)
- Node.js 22 or newer
- pnpm 11

Clone the repository and install frontend dependencies:

```shell
git clone https://github.com/fredrikblau/halal-protocol.git
cd halal-protocol
pnpm --dir app install --frozen-lockfile
```

## One-command smoke test

To deploy disposable contracts, build the app, request every important route, and exit:

```shell
make app-smoke
```

This starts Anvil on port `18545`, deploys the local system and signed CPI adapter, writes a
temporary `app/.env.local`, and checks the dashboard, governance, PSM, vesting, and health routes.
It removes the temporary chain and restores the previous environment file when it exits.

## Interactive local demo

To keep Anvil and the dApp running for manual exploration:

```shell
./scripts/local-demo.sh
```

Open <http://localhost:3000>. The script prints the deployed addresses, seeds a fresh CPI report,
and writes the matching `NEXT_PUBLIC_*` values to `app/.env.local`. Press `Ctrl-C` to stop both
processes and restore the previous environment file.

If the default local ports are already in use, override them without changing the deployment
configuration:

```shell
ANVIL_PORT=18545 APP_PORT=3001 ./scripts/local-demo.sh
```

`ANVIL_PORT` defaults to `8545` and `APP_PORT` defaults to `3000`; both must be distinct integers
from `1` through `65535`, and both listeners stay bound to `127.0.0.1` for this disposable demo.

The local demo intentionally assigns both vesting beneficiaries to the funded Anvil broadcaster.
That is convenient for a disposable demo, but it is not an acceptable production custody model.
The production deployment and verification paths reject deployer-controlled beneficiaries.

## Useful checks while developing

From the repository root:

```shell
make contracts-test   # Solidity tests and invariants
make app-lint         # frontend lint
make app-build        # production frontend build
make app-e2e          # browser flow on disposable Anvil state
make verify           # complete local verification suite
```

After changing a Solidity interface, regenerate the frontend ABIs and inspect the diff:

```shell
make abis
git diff -- app/src/abis
```

For protocol behavior and deployment safety, read [`DESIGN-DECISIONS.md`](DESIGN-DECISIONS.md),
the [`THREAT-MODEL.md`](THREAT-MODEL.md), and the [operator runbook](OPERATOR-RUNBOOK.md).
Do not use the local demo as evidence that an arbitrary reserve token or production deployment is
safe; the reference contracts remain unaudited.

To rehearse how deployment output becomes review evidence, see the
[local deployment evidence example](LOCAL-DEPLOYMENT-EVIDENCE.md).
