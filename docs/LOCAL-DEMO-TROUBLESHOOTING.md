# Local demo troubleshooting

This guide is for the disposable demo in [`scripts/local-demo.sh`](../scripts/local-demo.sh). It
starts Anvil on `127.0.0.1:8545`, deploys fresh contracts, seeds a local CPI report, and runs the
dApp at <http://localhost:3000>. The demo mnemonic and faucet-backed `mDAI` are local test fixtures
only. Never point these commands at a public RPC or use the demo accounts with real funds.

## Start with a clean prerequisite check

From the repository root, run:

```shell
node --version
pnpm --version
forge --version
anvil --version
cast --version
pnpm --dir app install --frozen-lockfile
```

Use Node.js 22 or newer and pnpm 11. If `forge`, `anvil`, or `cast` is missing, install Foundry
and ensure its `bin` directory is on `PATH`. If pnpm is missing, install pnpm 11. Keep the
committed `app/pnpm-lock.yaml` when reproducing a contributor issue.

## Port already in use

The interactive demo uses port `8545` for Anvil and port `3000` for Next.js. The smoke test uses
Anvil port `18545` and app port `3001`. Check exact listeners before stopping anything:

```shell
lsof -nP -iTCP:8545 -sTCP:LISTEN
lsof -nP -iTCP:3000 -sTCP:LISTEN
lsof -nP -iTCP:18545 -sTCP:LISTEN
lsof -nP -iTCP:3001 -sTCP:LISTEN
```

If a listener is a leftover Halal demo process, copy its PID from the output, inspect it, and stop
that PID only:

```shell
ps -fp <PID>
kill <PID>
```

If it does not stop, use `kill -TERM <PID>` and inspect again. Do not kill an unidentified process
or a shared Anvil/Next.js server. Then retry `./scripts/local-demo.sh` or `make app-smoke`.
The interactive demo defaults to those ports but accepts alternate values with `ANVIL_PORT` and
`APP_PORT`:

```shell
ANVIL_PORT=18546 APP_PORT=3002 ./scripts/local-demo.sh
```

The two values must be distinct integers from `1` through `65535`. The smoke test continues to
use its own defaults (`18545` and `3001`) and also accepts these overrides.

## Anvil did not start or the RPC is unresponsive

The scripts write startup logs to `/tmp/halal-anvil.log` for the interactive demo and
`/tmp/halal-app-smoke-anvil.log` for the smoke test. Inspect them with:

```shell
tail -n 80 /tmp/halal-anvil.log
tail -n 80 /tmp/halal-app-smoke-anvil.log
cast chain-id --rpc-url http://127.0.0.1:8545
```

A working local chain reports chain ID `31337`. Resolve the port or Anvil startup error first;
deployment and frontend configuration cannot succeed without the RPC.

## Deployment or address errors

The demo deploys fresh addresses on every Anvil start. Do not reuse addresses from an older run.
Stop the active demo with `Ctrl-C`, confirm no Anvil listener remains, and start it again:

```shell
./scripts/local-demo.sh
```

The script temporarily writes matching values to `app/.env.local` and restores an existing file on
exit. If the shell was terminated before cleanup and the file contains old local addresses, remove
that local-only file and rerun the demo:

```shell
rm -- app/.env.local
./scripts/local-demo.sh
```

Only remove this exact local environment file. Never delete the deployment registry, a lockfile,
or an environment file containing real credentials. `NEXT_PUBLIC_*` values are browser-visible and
must never contain private keys, seed phrases, RPC credentials, or API secrets.

## Frontend does not start

If deployment succeeds but the app does not open, inspect the Next.js log and test the local URL:

```shell
tail -n 100 /tmp/halal-app-smoke-next.log
curl --fail --silent --show-error "http://127.0.0.1:${APP_PORT:-3000}/"
```

After stopping the interactive demo, run the app checks separately:

```shell
make app-lint
make app-build
```

If the build reports missing packages, rerun `pnpm --dir app install --frozen-lockfile`. If it
reports stale or malformed public configuration, rerun the demo so addresses and deployment block
are regenerated together.

## What success looks like

For the interactive demo, expect output saying that a fresh local CPI report was seeded, temporary
frontend configuration was written, and the dApp is available at the configured app port (default
<http://localhost:3000>). The dashboard, `/governance`, `/psm`, `/vesting`, and `/health` routes
should load.

For the smoke test:

```shell
make app-smoke
```

The final line should be `Configured local dApp smoke test passed on chain 31337.` For the signed
adapter rehearsal:

```shell
make adapter-demo
```

The final line should be `Local CPI adapter rehearsal passed on chain 31337.` A successful local
demo proves only that disposable scripts agree with one another. It is not a security audit,
deployment approval, reserve-token review, or evidence that the unaudited contracts are safe for
real funds.

## Reporting a reproducible problem

After removing secrets and personal data, include the command, operating system, tool versions,
relevant log excerpt, and commit SHA. Do not include private keys, seed phrases, RPC URLs with
credentials, or wallet data. Suspected fund-risking vulnerabilities must follow [`SECURITY.md`](../SECURITY.md)
instead of being filed publicly.
