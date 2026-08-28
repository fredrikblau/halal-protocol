import test from "node:test";
import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { chmodSync, mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import path from "node:path";
import os from "node:os";

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "../..");
const HEALTH_CHECK = path.join(ROOT, "scripts/check-deployment-health.sh");
const PSM_HEALTH_CHECK = path.join(ROOT, "scripts/check-psm-health.sh");
const ADAPTER_DEMO = path.join(ROOT, "scripts/local-adapter-demo.sh");

function run(script, env, options = {}) {
  const result = spawnSync("bash", [script], {
    cwd: ROOT,
    env,
    encoding: "utf8",
    timeout: options.timeout ?? 30_000,
  });
  return { ...result, output: `${result.stdout ?? ""}${result.stderr ?? ""}` };
}

function runDeploymentHealthJson(env) {
  const result = spawnSync("bash", [HEALTH_CHECK, "--json"], {
    cwd: ROOT,
    env,
    encoding: "utf8",
    timeout: 30_000,
  });
  return { ...result, output: `${result.stdout ?? ""}${result.stderr ?? ""}` };
}

function runPsmHealthWithFakeCast(overrides = {}) {
  const tempDir = mkdtempSync(path.join(os.tmpdir(), "halal-health-check-"));
  const fakeCast = path.join(tempDir, "cast");
  const values = {
    timestamp: "1000",
    reserveSurplus: "0",
    lastReportTimestamp: "900",
    cpiRate: "1000000",
    maxReportAge: "200",
    lastUpdated: "1000",
    minUpdateInterval: "200",
    source: '"BLS-CPI"',
    adapterPsm: "0x0000000000000000000000000000000000000001",
    adapterOwner: "0x0000000000000000000000000000000000000002",
    adapterSourceId: `0x${"a".repeat(64)}`,
    adapterThreshold: "1",
    adapterSignerCount: "1",
    adapterLastSubmitted: "900",
    adapterLastSubmittedCpi: "1000000",
    adapterSigner: "0x0000000000000000000000000000000000000003",
    code: "0x1234",
    ...overrides,
  };
  writeFileSync(
    fakeCast,
    `#!/usr/bin/env bash
set -euo pipefail
case "$*" in
  *"code "*) echo '${values.code}' ;;
  *"block latest"*) echo '${values.timestamp}' ;;
  *"reserveSurplus"*) echo '${values.reserveSurplus}' ;;
  *"lastReportTimestamp"*) echo '${values.lastReportTimestamp}' ;;
  *"cpiRate"*) echo '${values.cpiRate}' ;;
  *"MAX_REPORT_AGE"*) echo '${values.maxReportAge}' ;;
  *"lastUpdated"*) echo '${values.lastUpdated}' ;;
  *"minUpdateInterval"*) echo '${values.minUpdateInterval}' ;;
  *"source()(string)"*) echo '${values.source}' ;;
  *"psm()(address)"*) echo '${values.adapterPsm}' ;;
  *"owner()(address)"*) echo '${values.adapterOwner}' ;;
  *"sourceId()(bytes32)"*) echo '${values.adapterSourceId}' ;;
  *"threshold()(uint256)"*) echo '${values.adapterThreshold}' ;;
  *"signerCount()(uint256)"*) echo '${values.adapterSignerCount}' ;;
  *"lastSubmittedTimestamp()(uint256)"*) echo '${values.adapterLastSubmitted}' ;;
  *"lastSubmittedCPI()(uint256)"*) echo '${values.adapterLastSubmittedCpi}' ;;
  *"signerAt(uint256)(address)"*) echo '${values.adapterSigner}' ;;
  *) echo "unexpected fake cast call: $*" >&2; exit 1 ;;
esac
`,
  );
  chmodSync(fakeCast, 0o755);

  try {
    return run(PSM_HEALTH_CHECK, {
    ...process.env,
    PATH: `${tempDir}:${process.env.PATH}`,
    RPC_URL: "http://fake-rpc.invalid",
    PSM: "0x0000000000000000000000000000000000000001",
    FAIL_ON_UPDATE_OVERDUE: "false",
    ...overrides,
  });
  } finally {
    rmSync(tempDir, { recursive: true, force: true });
  }
}

test("healthy disposable adapter rehearsal returns zero and status=healthy", () => {
  const result = run(ADAPTER_DEMO, { ...process.env }, { timeout: 120_000 });
  assert.equal(result.status, 0, result.output);
  assert.match(result.output, /^status=healthy$/m);
});

test("missing deployment-health configuration is classified and nonzero", () => {
  const env = { ...process.env };
  delete env.RPC_URL;
  delete env.EXPECTED_CHAIN_ID;
  delete env.PSM;

  const result = run(HEALTH_CHECK, env);
  assert.notEqual(result.status, 0, result.output);
  assert.match(result.output, /status=unhealthy/);
  assert.match(result.output, /reason=missing_required_environment_variable/);
  assert.match(result.output, /missing_variable=RPC_URL/);
});

test("deployment-health JSON mode preserves unhealthy exit status and structured diagnostics", () => {
  const env = { ...process.env };
  delete env.RPC_URL;
  delete env.EXPECTED_CHAIN_ID;
  delete env.PSM;

  const result = runDeploymentHealthJson(env);
  assert.notEqual(result.status, 0, result.output);
  const report = JSON.parse(result.stdout);
  assert.equal(report.schemaVersion, 1);
  assert.equal(report.status, "unhealthy");
  assert.deepEqual(report.reasons, ["missing_required_environment_variable"]);
  assert.equal(report.observed.missing_variable, "RPC_URL");
});

test("failed deployment wiring is classified and nonzero", () => {
  const result = run(HEALTH_CHECK, {
    ...process.env,
    RPC_URL: "http://127.0.0.1:1",
    EXPECTED_CHAIN_ID: "421614",
    PSM: "0x0000000000000000000000000000000000000001",
  });
  assert.notEqual(result.status, 0, result.output);
  assert.match(result.output, /reason=deployment_wiring_check_failed/);
});

test("standalone PSM health check reports a healthy fake-RPC state", () => {
  const result = runPsmHealthWithFakeCast();
  assert.equal(result.status, 0, result.output);
  assert.match(result.output, /^psm=0x0000000000000000000000000000000000000001$/m);
  assert.match(result.output, /^cpi_source=BLS-CPI$/m);
  assert.match(result.output, /^status=healthy$/m);
});

test("configured CPI adapter rejects a changed PSM source label", () => {
  const result = runPsmHealthWithFakeCast({
    source: '"DIFFERENT-SOURCE"',
    CPI_ADAPTER: "0x0000000000000000000000000000000000000004",
    EXPECTED_CPI_ADAPTER_OWNER: "0x0000000000000000000000000000000000000002",
    EXPECTED_CPI_SOURCE: "BLS-CPI",
    EXPECTED_CPI_SOURCE_ID: `0x${"a".repeat(64)}`,
  });
  assert.notEqual(result.status, 0, result.output);
  assert.match(result.output, /^reason=cpi_source_mismatch$/m);
});

test("standalone PSM health check reports stale CPI data", () => {
  const result = runPsmHealthWithFakeCast({ lastReportTimestamp: "700" });
  assert.notEqual(result.status, 0, result.output);
  assert.match(result.output, /^status=unhealthy$/m);
  assert.match(result.output, /^reason=timestamped_cpi_report_stale$/m);
});

test("standalone PSM health check reports adapter rate mismatch", () => {
  const result = runPsmHealthWithFakeCast({
    adapterLastSubmittedCpi: "1000001",
    CPI_ADAPTER: "0x0000000000000000000000000000000000000004",
    EXPECTED_CPI_ADAPTER_OWNER: "0x0000000000000000000000000000000000000002",
    EXPECTED_CPI_SOURCE: "BLS-CPI",
    EXPECTED_CPI_SOURCE_ID: `0x${"a".repeat(64)}`,
  });
  assert.notEqual(result.status, 0, result.output);
  assert.match(result.output, /^reason=cpi_adapter_rate_mismatch$/m);
});

test("standalone PSM health check reports a reserve deficit", () => {
  const result = runPsmHealthWithFakeCast({ reserveSurplus: "-1" });
  assert.notEqual(result.status, 0, result.output);
  assert.match(result.output, /^status=unhealthy$/m);
  assert.match(result.output, /^reason=reserve_deficit$/m);
});

test("standalone PSM health check classifies malformed numeric RPC output", () => {
  const result = runPsmHealthWithFakeCast({ lastReportTimestamp: "not-a-timestamp" });
  assert.notEqual(result.status, 0, result.output);
  assert.match(result.output, /^status=unhealthy$/m);
  assert.match(result.output, /^reason=invalid_last_report_timestamp$/m);
});

test("standalone PSM health check rejects an oversized arithmetic value", () => {
  const result = runPsmHealthWithFakeCast({ lastReportTimestamp: "9223372036854775808" });
  assert.notEqual(result.status, 0, result.output);
  assert.match(result.output, /^status=unhealthy$/m);
  assert.match(result.output, /^reason=invalid_last_report_timestamp_range$/m);
});

test("standalone PSM health check avoids timestamp-addition overflow", () => {
  const maximum = "9223372036854775807";
  const result = runPsmHealthWithFakeCast({
    timestamp: maximum,
    lastReportTimestamp: "9223372036854775707",
    maxReportAge: "200",
    lastUpdated: "9223372036854775707",
    minUpdateInterval: "200",
  });
  assert.equal(result.status, 0, result.output);
  assert.doesNotMatch(result.output, /^warning=normal_cpi_update_overdue$/m);
  assert.match(result.output, /^status=healthy$/m);
});

test("standalone PSM health check rejects future timestamps", () => {
  const result = runPsmHealthWithFakeCast({
    timestamp: "1000",
    lastReportTimestamp: "1001",
    lastUpdated: "1001",
  });
  assert.notEqual(result.status, 0, result.output);
  assert.match(result.output, /^status=unhealthy$/m);
  assert.match(result.output, /^reason=timestamped_cpi_report_in_future$/m);
  assert.match(result.output, /^reason=last_updated_in_future$/m);
});

test("standalone PSM health check rejects an invalid overdue mode", () => {
  const result = run(PSM_HEALTH_CHECK, {
    ...process.env,
    RPC_URL: "http://fake-rpc.invalid",
    PSM: "0x0000000000000000000000000000000000000001",
    FAIL_ON_UPDATE_OVERDUE: "sometimes",
  });
  assert.notEqual(result.status, 0, result.output);
  assert.match(result.output, /^status=unhealthy$/m);
  assert.match(result.output, /^reason=invalid_fail_on_update_overdue$/m);
});

test("configured CPI adapter requires an expected source label", () => {
  const result = runPsmHealthWithFakeCast({
    CPI_ADAPTER: "0x0000000000000000000000000000000000000004",
    EXPECTED_CPI_ADAPTER_OWNER: "0x0000000000000000000000000000000000000002",
  });
  assert.notEqual(result.status, 0, result.output);
  assert.match(result.output, /^status=unhealthy$/m);
  assert.match(result.output, /^reason=cpi_source_expectation_missing$/m);
});

test("configured CPI adapter rejects malformed metadata before adapter RPC calls", () => {
  const result = runPsmHealthWithFakeCast({
    CPI_ADAPTER: "not-an-address",
    EXPECTED_CPI_ADAPTER_OWNER: "0x0000000000000000000000000000000000000002",
    EXPECTED_CPI_SOURCE: "BLS-CPI",
    EXPECTED_CPI_SOURCE_ID: `0x${"a".repeat(64)}`,
  });
  assert.notEqual(result.status, 0, result.output);
  assert.match(result.output, /^status=unhealthy$/m);
  assert.match(result.output, /^reason=invalid_cpi_adapter$/m);
  assert.doesNotMatch(result.output, /unexpected fake cast call/);
});

test("standalone PSM health check classifies an address without contract code", () => {
  const result = runPsmHealthWithFakeCast({ code: "0x" });
  assert.notEqual(result.status, 0, result.output);
  assert.match(result.output, /^status=unhealthy$/m);
  assert.match(result.output, /^reason=psm_no_code$/m);
});
