# Halal Contracts

Foundry project for the Halal (HLC) protocol: `HalalToken`, `HalalVesting`, `HalalPSM`,
`HalalDAO`, `HalalTimelock`, and the optional `CPIReportAdapter`. For the protocol overview,
architecture, and governance model, see
the [root README](../README.md) and [`../docs/`](../docs).

## Layout

- `src/` — the five core contracts plus the optional CPI report adapter.
- `test/` — Foundry test suite (196 tests at the time of writing: 185 unit/configuration tests plus 11 stateful
  PSM invariants; run `forge test` to confirm).
- `script/Deploy.s.sol` — full deployment script (token, vesting, DAO, timelock, role wiring).
- `script/DeployCPIReportAdapter.s.sol` — chain-guarded optional adapter deployment; it does not
  grant the PSM updater role.
- `../scripts/verify-deployment.sh` — read-only post-deployment wiring and role verifier.
- `../scripts/check-psm-health.sh` — read-only monitoring check for reserve deficits and CPI freshness.
- `../scripts/prepare-cpi-report.mjs` and `../scripts/parse-bls-cpi.mjs` — deterministic report
  normalization tools for the optional signed adapter.
- The production deployer selects an approximately one-week voting period on Arbitrum by default;
  review or override it for every target chain.
- `script/Examples.s.sol` — example governance proposal templates (CPI update, source switch,
  role grants, vesting revocation).

## Usage

### Build

```shell
forge build
```

### Test

```shell
forge test -vvv
```

### Format

```shell
forge fmt src test script
```

CI checks formatting for first-party code only, so local verification can avoid rewriting the
vendored libraries:

```shell
forge fmt --check src test script
```

### Gas report / coverage

```shell
forge build --gas-report
forge coverage
```

### Deploy

Requires a `.env` with `PRIVATE_KEY`, `RPC_URL`, `EXPECTED_CHAIN_ID`, `RESERVE_TOKEN`, `TEAM_BENEFICIARY`, and
`TREASURY_BENEFICIARY` (plus optional governance parameters) — see
[`../docs/DAO-Guide.md`](../docs/DAO-Guide.md) for the full walkthrough.

```shell
forge script script/Deploy.s.sol:DeployHalalSystem --rpc-url $RPC_URL --private-key $PRIVATE_KEY --broadcast
```

`EXPECTED_CHAIN_ID` is mandatory for the production deploy script. It must equal the chain ID
returned by `RPC_URL`; the script refuses to broadcast when it is missing or mismatched. The
production path also requires both vesting beneficiaries to already be deployed contracts, so
EOA beneficiaries cannot be accidentally used where the deployment policy requires multisig or
custody control. The local demo intentionally uses disposable Anvil EOAs instead.

The production CPI adapter script applies the same boundary to `ADAPTER_OWNER`: it must be a
deployed contract (normally the protocol timelock), and cannot be the deployer. The local adapter
rehearsal uses a disposable EOA owner by design and is not a production deployment path.

After deployment, independently verify the on-chain wiring before accepting funds:

```shell
../scripts/verify-deployment.sh
```

Set `RPC_URL`, `EXPECTED_CHAIN_ID`, `TIMELOCK`, `TOKEN`, `TEAM_VESTING`, `TREASURY_VESTING`, `DAO`,
`PSM`, `RESERVE_TOKEN`, `TEAM_BENEFICIARY`, `TREASURY_BENEFICIARY`, and `DEPLOYER_ADDRESS`.
Optionally set `CPI_UPDATER` to check that role too. The verifier checks the RPC
chain identity, that every supplied address has contract bytecode, the DAO's token/timelock links,
the PSM and vesting links, immutable vesting allocations and the intended vesting policy, role wiring
(including the timelock's self-admin and permissionless executor), and a
nonzero timelock delay. It also rejects a team or treasury beneficiary equal to the deployer unless
`ALLOW_DEPLOYER_BENEFICIARY=true` is set explicitly for the disposable local demo. It remains valid
after vesting releases, is read-only, and does not require a private key or
`--broadcast`.

For recurring monitoring, run the health check with only the RPC and PSM address:

```shell
RPC_URL="$RPC_URL" PSM=0x<psm> ../scripts/check-psm-health.sh
```

It prints `key=value` metrics and exits nonzero when the PSM has a reserve deficit, has never
accepted a timestamped CPI report, or the latest report exceeds `MAX_REPORT_AGE`. It also warns when
the normal updater cadence is overdue; set `FAIL_ON_UPDATE_OVERDUE=false` if an operator wants that
condition logged without making the check fail. The script is read-only and requires no private key.
