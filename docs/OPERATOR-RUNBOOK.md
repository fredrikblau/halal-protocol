# Operator Runbook

This runbook covers a reference deployment of the Halal contracts. It assumes the operator has
the repository checkout, Foundry, a read-only RPC endpoint, and access to the deployment and
governance accounts. Keep private keys in the signer or custody system; do not put them in this
repository, shell history, CI logs, or monitoring configuration.

The contracts are immutable and the reference system has no general pause. `HalalPSM` rejects new
deposits until it has a fresh CPI report, and rejects them again when that report exceeds
`MAX_REPORT_AGE`. Existing users can still withdraw their own redeemable credit when the reserve
and accounting checks permit it. Treat the PSM health check as an alert and follow the reserve and
governance procedures below.

## 1. Launch acceptance

Complete these checks before accepting a public deposit.

### 1.0 Run the offline preflight

Before using an RPC or credentials, run the report-only registry preflight from the repository
root:

```shell
node scripts/preflight-deployment.mjs --chain-id 421614
```

It checks that the requested chain has a complete, supported registry entry and prints the missing
field plus a next action. An empty registry is intentionally `not_ready`. JSON output is available
for automation with `--json`; preserve its `schemaVersion` and fail the automation when the command
exits nonzero. This command does not contact a network, sign, broadcast, or modify the registry,
and it cannot verify live bytecode, balances, roles, signer custody, or independent review.

### 1.1 Confirm the deployment inputs

Record the following in a deployment journal:

Start from the copyable [`deployment journal template`](DEPLOYMENT-JOURNAL-TEMPLATE.md) and retain
the completed record with the artifacts collected below.

- chain name and chain ID;
- reserve token address, symbol, decimals, and transfer behavior;
- distinct team and treasury beneficiary contract addresses, neither equal to the deployer, with multisig ownership confirmed;
- DAO, timelock, token, vesting, and PSM addresses;
- CPI source, report publisher, updater account, key custody, and rotation contact;
- deployer address and the commit or release used for deployment.

The reserve token is an external dependency. Check fee-on-transfer behavior, blacklist or pause
controls, upgradeability, decimals, and the issuer's admin powers before deployment. The PSM
accounts for balance deltas and rejects unsupported decimals, but it cannot make a hostile or frozen
reserve token safe.

Use the standalone [reserve-asset due-diligence checklist](RESERVE-ASSET-DUE-DILIGENCE.md) to
record the exact token address, implementation, transfer observations, issuer controls, evidence,
and launch decision in the deployment journal.

Complete the provider-neutral [`CPI source-policy record`](CPI-SOURCE-POLICY-TEMPLATE.md) for the
exact source and parser before granting `UPDATER_ROLE`. The repository includes a clearly marked
[`BLS CPI source-policy draft`](CPI-SOURCE-POLICY-BLS-DRAFT.md) as a worked example, not approval.
Link its raw response hashes, parser version, revision policy, signer custody, and monitoring
evidence from the deployment journal.

The production deployment script rejects EOA vesting beneficiaries by checking that both addresses
already contain contract bytecode. Use deployed multisig or custody contracts and record their
ownership/threshold evidence; the disposable local demo is the only path that intentionally permits
Anvil EOAs.

Use this compatibility matrix as a review starting point. “Covered” means the repository has a
focused test; it is not a certification of an arbitrary issuer token. Review the referenced tests
against the exact token implementation and repeat the checks on the intended chain before launch.

| Reserve-token behavior | Repository evidence | Launch interpretation |
| --- | --- | --- |
| 0–17 decimals | [Arithmetic differential tests](../contracts/test/HalalPSMArithmetic.t.sol) fuzz this range; [6-decimal round-trip tests](../contracts/test/HalalPSM.t.sol) cover a common case | Covered for the tested arithmetic and rounding boundaries; confirm the issuer's actual `decimals()` behavior |
| 18 decimals | The default PSM fixture and [standard deposit/withdraw tests](../contracts/test/HalalPSM.t.sol) use 18 decimals | Covered for the reference ERC-20 behavior |
| 19–77 decimals | The arithmetic tests fuzz through 77; [24-decimal tests](../contracts/test/HalalPSM.t.sol) exercise high-decimal scaling and precision | Covered for arithmetic within the constructor limit; check liquidity and rounding economics |
| More than 77 decimals | The constructor rejects 78 decimals with `UnsupportedDecimals` in [the PSM tests](../contracts/test/HalalPSM.t.sol) | Unsupported; do not deploy this PSM with the token |
| Fee on incoming transfers | [Balance-delta deposit tests](../contracts/test/HalalPSM.t.sol) cover fee-adjusted minting, zero-receipt rejection, and a fee change before withdrawal | Mechanically covered for the tested fee model; document the real fee, slippage limits, and whether the economics are acceptable |
| Fee or extra debit on outgoing transfers | [Withdrawal and reserve-floor tests](../contracts/test/HalalPSM.t.sol) cover recipient deltas and floor protection | Mechanically covered for the tested fee model; validate recipient receipts and reserve solvency under the issuer's rules |
| False-returning or reverting transfers | [Safe-transfer regression tests](../contracts/test/HalalPSM.t.sol) use a token that returns `false` | Covered for this failure mode; arbitrary non-standard call behavior still needs review |
| Reentrancy or callback behavior | [Admin-transfer reentrancy test](../contracts/test/HalalPSM.t.sol) verifies the guard | Covered for the supplied callback mock; review hooks, callbacks, and upgrade paths on the real token |
| Pausable, blacklistable, upgradeable, or issuer-controlled token | [Paused-token withdrawal regression test](../contracts/test/HalalPSM.t.sol) plus threat-model discussion of the [reserve dependency](THREAT-MODEL.md) | The PSM preserves accounting when a tested transfer reverts; operator due diligence remains required because it cannot make a frozen, censored, malicious, or later-upgraded token safe |

The matrix does not approve any particular reserve asset. Record the token address, implementation
and proxy details, admin powers, fee policy, pause/blacklist policy, and test evidence in the
deployment journal. If the token's behavior changes, treat it as a new launch review.

### 1.2 Deploy and verify

Use a dedicated deployer key and set an explicit chain ID. The production script reads its
configuration from environment variables:

```shell
cd contracts
PRIVATE_KEY=0x... \
RPC_URL=https://... \
EXPECTED_CHAIN_ID=421614 \
RESERVE_TOKEN=0x... \
TEAM_BENEFICIARY=0x... \
TREASURY_BENEFICIARY=0x... \
CPI_UPDATER=0x... \
forge script script/Deploy.s.sol:DeployHalalSystem \
  --rpc-url "$RPC_URL" --private-key "$PRIVATE_KEY" --broadcast
```

Copy the printed addresses into the journal. Run the read-only verifier from the repository root,
including `CPI_UPDATER` when the deployment bootstraps an updater:

```shell
RPC_URL="$RPC_URL" EXPECTED_CHAIN_ID=421614 \
TIMELOCK=0x... TOKEN=0x... TEAM_VESTING=0x... TREASURY_VESTING=0x... \
DAO=0x... PSM=0x... RESERVE_TOKEN=0x... \
TEAM_BENEFICIARY=0x... TREASURY_BENEFICIARY=0x... \
DEPLOYER_ADDRESS=0x... CPI_UPDATER=0x... \
CPI_ADAPTER=0x... EXPECTED_CPI_SOURCE='BLS:CUUR0000SA0' EXPECTED_CPI_SOURCE_ID=0x... \
./scripts/verify-deployment.sh
```

When a governed signed adapter is used, provide `CPI_ADAPTER`, `EXPECTED_CPI_SOURCE`, and
`EXPECTED_CPI_SOURCE_ID` together; the verifier additionally checks adapter bytecode, PSM and
timelock ownership, source identity, quorum, signer uniqueness/owner separation, the adapter's
`UPDATER_ROLE`, and equality between the adapter and PSM accepted-report CPI values and watermarks. The verifier checks
bytecode, chain identity, immutable wiring, vesting policy, beneficiary custody boundaries, token
roles, timelock roles, PSM roles, and the absence of deployer privileges. Stop the launch if it
fails.
Before approving the handoff itself, complete the reviewer checklist in
[`CPI-ADAPTER-SPEC.md`](CPI-ADAPTER-SPEC.md) and attach its evidence to the deployment journal.
Verify every contract's source and constructor arguments on the target explorer after the verifier
passes. Explorer verification does not replace the verifier.

### 1.3 Bootstrap the CPI feed

The PSM starts with `lastReportTimestamp == 0`, and its deposit entrypoints reject calls until a
report has been accepted. Submit a current report through the preferred timestamped path before
opening the frontend:

```shell
REPORT_AT=... # source publication timestamp, in Unix seconds
REPORT_CPI=... # CPI_PRECISION units; 1.0 is 1000000
cast send "$PSM" \
  'updateCPIWithTimestamp(uint256,uint256)' "$REPORT_CPI" "$REPORT_AT" \
  --private-key "$UPDATER_KEY" --rpc-url "$RPC_URL"
```

The first report can be accepted immediately when it is in the past, no more than 90 days old, and
new enough to establish the report watermark. Later reports must advance that watermark and wait
for the configured update interval. The updater account cannot bypass the CPI bounds, step limit,
cadence, freshness, or reserve-adequacy checks.

Confirm the result without a signer:

```shell
RPC_URL="$RPC_URL" PSM="$PSM" ./scripts/check-psm-health.sh
```

Require `status=healthy`. Save the output and transaction hash in the journal. When using the BLS
parser, also retain the generated report's `source.responseSha256` beside the exact downloaded
response bytes.

## 2. Recurring monitoring

Run the combined deployment audit from a host that can reach the RPC. It needs no private key and
checks contract wiring before it checks live PSM health:

```shell
RPC_URL=https://... EXPECTED_CHAIN_ID=421614 \
TIMELOCK=0x... TOKEN=0x... TEAM_VESTING=0x... TREASURY_VESTING=0x... \
DAO=0x... PSM=0x... RESERVE_TOKEN=0x... \
TEAM_BENEFICIARY=0x... TREASURY_BENEFICIARY=0x... DEPLOYER_ADDRESS=0x... \
./scripts/check-deployment-health.sh
```

For a health-only check, run:

```shell
RPC_URL=https://... PSM=0x... ./scripts/check-psm-health.sh
```

For a deployment with a governed adapter and recorded source metadata, pass the adapter and both
source expectations; `EXPECTED_CPI_SOURCE` and `EXPECTED_CPI_SOURCE_ID` are mandatory whenever
`CPI_ADAPTER` is set. Include
the timelock as the expected adapter owner. The check then fails if
governance removed the updater role, changed the source label, pointed the adapter at another PSM,
changed its owner, or changed its quorum:

```shell
RPC_URL=https://... PSM=0x... \
CPI_UPDATER=0x... CPI_ADAPTER=0x... \
EXPECTED_CPI_ADAPTER_OWNER=0x<timelock> \
EXPECTED_CPI_SOURCE='BLS:CUUR0000SA0' EXPECTED_CPI_SOURCE_ID=0x... \
./scripts/check-psm-health.sh
```

The script emits `key=value` records suitable for a cron wrapper, log shipper, or small exporter.
For a configured adapter it also emits one `cpi_adapter_signer_<index>` record per current signer;
compare those addresses with the deployment journal after each rotation. Alert on a nonzero exit
code and retain the emitted values:

For integrations that need structured output, pass `--json` to the combined check. It preserves the
same exit status and emits a stable versioned object with `status`, de-duplicated `reasons` and
`warnings`, plus string-valued `observed` fields. The default human-readable output is unchanged:

```shell
./scripts/check-deployment-health.sh --json > health.json
node -e 'const h = require("./health.json"); if (h.status !== "healthy") process.exit(1)'
```

The JSON mode uses only the Node runtime already required by the repository and never includes
private keys. Treat `schemaVersion` as the compatibility boundary and alert on a nonzero exit code.

| Signal | Meaning | First response |
| --- | --- | --- |
| `reason=timestamped_cpi_report_missing` | No timestamped source report has been accepted | The PSM rejects deposits; bootstrap a reviewed report through the updater |
| `reason=timestamped_cpi_report_stale` | The latest report is older than `MAX_REPORT_AGE` | The PSM rejects deposits; investigate the source and relayer |
| `reason=reserve_deficit` | Current reserve is below `reserveRequired()` | Stop public promotion, investigate reserve movements, and prepare a governance-approved top-up |
| `reason=configured_cpi_updater_missing_role` | The expected updater no longer holds `UPDATER_ROLE` | Inspect role events and execute a reviewed rotation or restoration proposal |
| `reason=cpi_source_mismatch` | The on-chain source label differs from the deployment record | Review the source-change proposal before accepting new reports |
| `reason=cpi_adapter_psm_mismatch` | The adapter does not target the monitored PSM | Stop updates and inspect the adapter deployment and role grant |
| `reason=cpi_adapter_owner_expectation_missing` | Adapter monitoring lacks the expected timelock owner | Add the deployment timelock as `EXPECTED_CPI_ADAPTER_OWNER` |
| `reason=cpi_adapter_owner_mismatch` | The adapter owner differs from the expected timelock | Stop updates and review ownership transfer events |
| `reason=cpi_adapter_source_id_mismatch` | The adapter's signed-report source ID differs from the deployment record | Rotate to the reviewed adapter for the documented source series |
| `reason=cpi_adapter_quorum_invalid` | The adapter threshold cannot be met by its configured signers | Stop updates and repair the adapter through governance |
| `reason=cpi_adapter_signer_owner_overlap` | The adapter owner is also configured as a report signer | Stop updates and separate ownership from signer custody through governance |
| `reason=cpi_adapter_signer_duplicate` | The live signer enumeration contains the same address more than once | Stop updates and repair or replace the adapter through governance |
| `reason=cpi_adapter_watermark_mismatch` | The adapter and PSM accepted-report timestamps differ | Stop updates and inspect for an unintended updater, incomplete handoff, or inconsistent deployment state |
| `reason=cpi_adapter_rate_mismatch` | The adapter's submitted CPI differs from the PSM's accepted CPI | Stop updates and inspect for an unintended updater or inconsistent deployment state |
| `warning=normal_cpi_update_overdue` | `lastUpdated + minUpdateInterval` has passed | Check the updater queue and source publication schedule |

The combined `check-deployment-health.sh` command also emits a machine-readable reason when it
cannot reach PSM health: `reason=missing_required_environment_variable` includes
`missing_variable=<name>`, while a failed wiring audit emits
`reason=deployment_wiring_check_failed`. Preserve the preceding diagnostic lines, but route alerts
using the `reason` field rather than parsing human-readable `FAILED:` text.

The default `FAIL_ON_UPDATE_OVERDUE=true` makes overdue cadence an alert. Use
`FAIL_ON_UPDATE_OVERDUE=false` only when a separate alerting rule handles cadence:

```shell
RPC_URL=https://... PSM=0x... FAIL_ON_UPDATE_OVERDUE=false \
  ./scripts/check-psm-health.sh
```

Also monitor these on-chain events and state changes:

- `CPIUpdated` and `CPIReportAccepted` for rate, source timestamp, and updater cadence;
- `ReserveDeposited`, `ReserveWithdrawn`, `Deposited`, `Withdrawn`, and `RedeemableCancelled`;
- `RoleGranted` and `RoleRevoked` on the token, PSM, timelock, and vesting contracts;
- governance proposals, queues, executions, cancellations, and proposal descriptions;
- reserve token upgrades, issuer pauses, blacklist changes, and fee-policy changes.

The health script is the minimum check. Pair it with event indexing and an explorer or archive RPC
when monitoring a public deployment.

See the dependency-free [machine-readable monitoring example](MONITORING-JSON-EXAMPLE.md) for a
consumer that preserves the health command's exit status.

### 2.1 Cron or systemd health wrapper

The health command already emits `key=value` records and returns nonzero when a deployment is
unhealthy. A small wrapper can turn that result into one log line for a scheduler or service
manager:

```bash
#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="/opt/halal-protocol"
if output="$({
  RPC_URL="$HALAL_RPC_URL" EXPECTED_CHAIN_ID="$HALAL_CHAIN_ID" \
  TIMELOCK="$HALAL_TIMELOCK" TOKEN="$HALAL_TOKEN" \
  TEAM_VESTING="$HALAL_TEAM_VESTING" TREASURY_VESTING="$HALAL_TREASURY_VESTING" \
  DAO="$HALAL_DAO" PSM="$HALAL_PSM" RESERVE_TOKEN="$HALAL_RESERVE_TOKEN" \
  TEAM_BENEFICIARY="$HALAL_TEAM_BENEFICIARY" TREASURY_BENEFICIARY="$HALAL_TREASURY_BENEFICIARY" \
  DEPLOYER_ADDRESS="$HALAL_DEPLOYER_ADDRESS" \
  "$ROOT_DIR/scripts/check-deployment-health.sh";
} 2>&1)"; then
  printf 'halal_health status=healthy\n'
else
  reason="$(printf '%s\n' "$output" | awk -F= '$1 == "reason" { print $2; exit }')"
  printf 'halal_health status=unhealthy reason=%s\n' "${reason:-check_failed}" >&2
  exit 1
fi
```

Inject the `HALAL_*` values through a protected service environment or secret manager. Do not put
private keys in this wrapper: `check-deployment-health.sh` is read-only. Alert on exit status 1 and
include the emitted `reason` in the incident record. At minimum, exercise the wrapper against a
stale CPI report and a reserve deficit before enabling automatic alerts.

### Reproduce the exit contract locally

The disposable adapter rehearsal provides a healthy success case without a public RPC or real
funds:

```shell
make adapter-demo
# expect: status=healthy and exit status 0
```

To exercise the fail-closed configuration path without starting a chain, omit a required input and
assert the command is nonzero. This is useful for testing a cron, systemd, or CI wrapper before it
is given production credentials:

```shell
set +e
RPC_URL=http://127.0.0.1:18545 PSM= \
  ./scripts/check-psm-health.sh >/tmp/halal-health-failure.log 2>&1
health_exit=$?
set -e
test "$health_exit" -ne 0
grep -F 'Missing required environment variable: PSM' /tmp/halal-health-failure.log
```

The first command proves the healthy output path on disposable Anvil state; the second proves that
missing monitoring configuration cannot be mistaken for a healthy deployment. For an on-chain
failure rehearsal, use a disposable deployment with a stale report or reserve deficit and retain
the emitted `reason=...` record in the journal.

For a Prometheus textfile collector or another pull-based monitor, the same records can be mapped
without `jq` or a network service. This example intentionally preserves the health command's exit
code; the collector can publish the metrics while the scheduler still treats an unhealthy check as
a failed job:

```bash
#!/usr/bin/env bash
set -u

set +e
health_output="$(
  RPC_URL="$HALAL_RPC_URL" PSM="$HALAL_PSM" \
  CPI_ADAPTER="${HALAL_CPI_ADAPTER:-}" \
  EXPECTED_CPI_ADAPTER_OWNER="${HALAL_TIMELOCK:-}" \
  ./scripts/check-psm-health.sh 2>&1
)"
health_exit=$?
set -e

printf '%s\n' "$health_output" | awk -F= '
  $1 == "status" { status = $2 }
  $1 == "reason" { reason = $2 }
  $1 == "reserve_surplus" { reserve = $2 }
  $1 == "cpi_rate" { cpi = $2 }
  $1 == "last_report_timestamp" { report = $2 }
  $1 == "cpi_adapter_last_submitted_timestamp" { adapter = $2 }
  $1 == "cpi_adapter_last_submitted_cpi" { adapter_cpi = $2 }
  END {
    healthy = (status == "healthy" ? 1 : 0)
    watermark_match = (adapter != "" && adapter == report ? 1 : 0)
    rate_match = (adapter_cpi != "" && adapter_cpi == cpi ? 1 : 0)
    printf "halal_psm_health %d\n", healthy
    if (reserve != "") printf "halal_psm_reserve_surplus %s\n", reserve
    if (report != "") printf "halal_psm_last_report_timestamp %s\n", report
    if (adapter != "") printf "halal_cpi_adapter_watermark_match %d\n", watermark_match
    if (adapter_cpi != "") printf "halal_cpi_adapter_rate_match %d\n", rate_match
    if (reason != "") printf "halal_psm_health_reason{reason=\"%s\"} 1\n", reason
  }
'

exit "$health_exit"
```

Alert when `halal_psm_health == 0`, `halal_psm_reserve_surplus < 0`, or
`halal_cpi_adapter_watermark_match == 0` or `halal_cpi_adapter_rate_match == 0` when an adapter is configured. The last conditions are the
machine-readable forms of `reason=cpi_adapter_watermark_mismatch` and `reason=cpi_adapter_rate_mismatch`; they detect an unintended updater,
an incomplete handoff, or an inconsistent deployment state.

## 3. CPI updater operations

Use a dedicated updater account or reviewed consumer. Give it only `UPDATER_ROLE` on the PSM, keep
the signing key in a restricted custody system, and record the source publication timestamp with
each submission. Prefer `updateCPIWithTimestamp` so replayed and delayed source data fails on-chain.

For a quorum adapter, prepare the typed data with `scripts/prepare-cpi-report.mjs`, collect
signatures through the approved custody process, and verify them before submitting. Use the signer
addresses printed by `check-psm-health.sh` and keep them in ascending order:

```shell
node scripts/verify-cpi-report.mjs \
  --typed-data /path/to/typed-data.json \
  --rpc-url "$RPC_URL" --adapter 0x<adapter> \
  --signers 0x<lowest-signer>,0x<next-signer> \
  --signatures 0x<signature-for-lowest>,0x<signature-for-next>
```

Keep the verifier output with the report archive. It contains the adapter, PSM, source ID, live
watermarks, freshness window, signer list, and signature count, but no private key material. The
command fails before signature recovery when the report is stale, replayed, future-dated, or older
than the PSM's accepted-report watermark.

Before each submission, verify:

1. the report came from the documented source;
2. `REPORT_AT` identifies the source publication time, not the relayer's current time;
3. the source value uses the PSM's `CPI_PRECISION` units;
4. the current report is newer than the last accepted report;
5. the cadence has elapsed and the reserve can support the resulting rate.

To rotate an updater, use a normal DAO proposal that calls `grantRole(UPDATER_ROLE, newUpdater)`
and `revokeRole(UPDATER_ROLE, oldUpdater)` on the PSM. The timelock is the PSM role admin. Queue the
proposal, allow the configured voting and timelock windows to complete, verify the executed events,
then run `scripts/verify-deployment.sh` with the new updater address. Keep the old key available
until the new account has successfully submitted a report, then revoke or destroy it according to
the custody policy.

Do not use `mockCPI` as a routine updater path. It is a DAO-gated emergency override that bypasses
the normal step and interval limits. Document the reason, proposed value, reserve impact, and
follow-up source correction in the governance proposal.

## 4. Governance proposal review

Before voting or queueing a proposal, reviewers should:

Use the [governance proposal review example](GOVERNANCE-PROPOSAL-REVIEW-EXAMPLE.md) as a fictional
walkthrough of raw calldata, independent simulation, role impact, reserve impact, and timelock
evidence. It includes an intentionally unsafe proposal that must be rejected. Copy the [governance
review evidence template](GOVERNANCE-REVIEW-EVIDENCE-TEMPLATE.md) for each real review. Run the
offline `scripts/verify-governance-payload.mjs` preflight with a separately reviewed target policy;
its successful exit confirms policy alignment only, not payload safety.

- decode every target, value, and calldata field;
- compare the target and selector with the published contract source;
- calculate reserve impact at the current and plausible future CPI rates;
- check whether the action grants `MINTER_ROLE`, `BURNER_ROLE`, `PARAM_ROLE`, or `UPDATER_ROLE`;
- confirm beneficiary, reserve token, oracle source, and multisig addresses;
- confirm that the action respects the timelock delay and the published change rationale;
- record the proposal ID, description hash, decoded actions, votes, queue transaction, and execution
  transaction in the deployment journal.

The DAO can govern parameters and extensions, but it cannot make an unsafe reserve token reliable
or recover a compromised signer automatically. Keep proposal review independent from the account
that submits or executes the proposal.

## 5. Incident response

For a structured rehearsal, copy the [protocol incident tabletop worksheet](INCIDENT-TABLETOP-WORKSHEET.md)
and run it against a disposable or testnet deployment before accepting meaningful funds.
The [stale-CPI tabletop example](INCIDENT-RESPONSE-TABLETOP-EXAMPLE.md) shows the expected evidence
and containment record.

### Missing or stale CPI report

1. Confirm the alert against a second RPC or explorer.
2. Check source publication, updater custody, nonce state, and the last accepted timestamp.
3. Keep the dApp in its safety state and publish the incident status.
4. Submit a verified report when the source and timestamp are available.
5. If the source is wrong or unavailable, prepare a DAO-reviewed emergency action; do not invent a
   report to make the dashboard green.

### Reserve deficit

1. Confirm `reserveSurplus()` and the reserve token balance from an independent RPC.
2. Identify CPI changes, withdrawals, cancellations, reserve transfers, and reserve-token events
   since the last healthy check.
3. Stop new public promotion. The frontend blocks deposits while the deficit remains visible;
   the contract's CPI freshness gate remains independent of that reserve alert.
4. Prepare a governance proposal to top up the reserve or apply another documented mitigation.
5. Do not withdraw reserve surplus while the deficit exists. Re-run the health check after every
   governance or reserve action.

### Suspected updater or privileged-key compromise

1. Revoke or rotate the affected signer through the timelocked governance path if governance still
   controls the role admin.
2. Review all recent `CPIUpdated`, `RoleGranted`, `RoleRevoked`, and governance events.
3. Preserve RPC responses, transaction hashes, source reports, and custody logs.
4. Publish a clear incident notice with affected deployments and user actions.
5. Treat immutable contract behavior as fixed. A code correction requires a separately deployed and
   reviewed system followed by a documented migration.

## 6. Evidence to retain

For each deployment and release, retain:

- git commit and release tag;
- exact environment-variable names and non-secret values;
- deployment transaction hashes and printed addresses;
- verifier output and explorer source-verification links;
- health-check output before and after the first report;
- reserve-token due-diligence notes;
- updater source reports, timestamps, and submission hashes;
- governance proposal IDs, decoded actions, votes, queue, and execution hashes;
- incidents, decisions, and remediation links.

The repository's tests and scripts provide evidence about the reference implementation. They do not
prove that a deployed reserve token, oracle source, signer, RPC endpoint, or governance community is
safe. Record those external assumptions beside the on-chain evidence.
