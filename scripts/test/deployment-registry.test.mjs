import assert from "node:assert/strict";
import { chmod, mkdir, mkdtemp, readFile, writeFile, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";
import test from "node:test";
import { verifyDeploymentReceipt } from "../verify-deployment-receipt.mjs";
import { preflightDeploymentRegistry } from "../preflight-deployment.mjs";

const root = fileURLToPath(new URL("../../", import.meta.url));
const validator = join(root, "scripts/validate-deployment-registry.mjs");
const preflight = join(root, "scripts/preflight-deployment.mjs");
const recorder = join(root, "scripts/record-deployment-manifest.mjs");

function deployment(overrides = {}) {
  return {
    network: "test",
    release: "test",
    commit: "0".repeat(40),
    deploymentTx: `0x${"1".repeat(64)}`,
    explorerUrl: "https://example.com/tx/0x1",
    sourceVerificationUrl: "https://example.com/address/0x1#code",
    journalUrl: "https://example.com/journal/1",
    token: `0x${"1".repeat(40)}`,
    teamVesting: `0x${"2".repeat(40)}`,
    treasuryVesting: `0x${"3".repeat(40)}`,
    psm: `0x${"4".repeat(40)}`,
    dao: `0x${"5".repeat(40)}`,
    timelock: `0x${"6".repeat(40)}`,
    reserveToken: `0x${"7".repeat(40)}`,
    reserveTokenSymbol: "mDAI",
    deploymentBlock: "1",
    cpiAdapter: `0x${"8".repeat(40)}`,
    cpiSource: "BLS:CUUR0000SA0",
    cpiSourceId: `0x${"9".repeat(64)}`,
    cpiPolicyUrl: "https://example.com/cpi-policy",
    ...overrides,
  };
}

async function runValidator(entry, chainId = "31337") {
  const directory = await mkdtemp(join(tmpdir(), "halal-registry-"));
  const path = join(directory, "registry.json");
  await writeFile(path, `${JSON.stringify({ [chainId]: entry })}\n`);
  const result = spawnSync(process.execPath, [validator], {
    cwd: root,
    env: { ...process.env, DEPLOYMENT_REGISTRY_PATH: path },
    encoding: "utf8",
  });
  await rm(directory, { recursive: true, force: true });
  return result;
}

async function runPreflight(contents, args = []) {
  const directory = await mkdtemp(join(tmpdir(), "halal-preflight-"));
  const path = join(directory, "registry.json");
  await writeFile(path, contents);
  const result = spawnSync(process.execPath, [preflight, "--registry", path, ...args], {
    cwd: root,
    env: process.env,
    encoding: "utf8",
  });
  await rm(directory, { recursive: true, force: true });
  return result;
}

function fakeCastScript() {
  return `#!/usr/bin/env bash
set -euo pipefail
case "\${1:-}" in
  receipt) printf '{"transactionHash":"%s","blockNumber":"0x1","status":"0x1"}\\n' "$DEPLOYMENT_TX" ;;
  block) echo 10 ;;
  chain-id) echo "$EXPECTED_CHAIN_ID" ;;
  code) echo 0x1234 ;;
  call)
    target="$2"
    signature="$3"
    case "$signature" in
      'reserve()(address)') echo "$RESERVE_TOKEN" ;;
      'hlc()(address)'|'token()(address)') echo "$TOKEN" ;;
      'dao()(address)'|'timelock()(address)') echo "$TIMELOCK" ;;
      'getMinDelay()(uint256)') echo 172800 ;;
      'genesisMinted()(bool)') echo true ;;
      'TEAM_ALLOCATION()(uint256)') echo 6000000000000000000000000 ;;
      'TREASURY_ALLOCATION()(uint256)') echo 4000000000000000000000000 ;;
      'totalAllocation()(uint256)') [[ "$target" == "$TEAM_VESTING" ]] && echo 6000000000000000000000000 || echo 4000000000000000000000000 ;;
      'cliff()(uint64)') [[ "$target" == "$TEAM_VESTING" ]] && echo 31536000 || echo 0 ;;
      'duration()(uint64)') [[ "$target" == "$TEAM_VESTING" ]] && echo 126144000 || echo 94608000 ;;
      'revocable()(bool)') [[ "$target" == "$TEAM_VESTING" ]] && echo true || echo false ;;
      'beneficiary()(address)') [[ "$target" == "$TEAM_VESTING" ]] && echo "$TEAM_BENEFICIARY" || echo "$TREASURY_BENEFICIARY" ;;
      *'ROLE()(bytes32)') echo "0x$(printf '%064d' 0)" ;;
      'hasRole(bytes32,address)(bool)') [[ "$*" == *"$DEPLOYER_ADDRESS"* ]] && echo false || echo true ;;
      'psm()(address)') echo "$PSM" ;;
      'owner()(address)') echo "$TIMELOCK" ;;
      'sourceId()(bytes32)') echo "$EXPECTED_CPI_SOURCE_ID" ;;
      'source()(string)') printf '"%s"\\n' "$EXPECTED_CPI_SOURCE" ;;
      'lastSubmittedTimestamp()(uint256)'|'lastReportTimestamp()(uint256)') echo 1 ;;
      'threshold()(uint256)') echo 2 ;;
      'signerCount()(uint256)') echo 2 ;;
      'signerAt(uint256)(address)') [[ "$4" == 0 ]] && echo 0x0000000000000000000000000000000000000001 || echo 0x0000000000000000000000000000000000000002 ;;
      *) echo "unexpected fake cast call: $signature" >&2; exit 1 ;;
    esac
    ;;
  *) echo "unexpected fake cast command: $*" >&2; exit 1 ;;
esac
`;
}

async function runRecorder(withAdapter) {
  const directory = await mkdtemp(join(tmpdir(), "halal-recorder-"));
  const fakeBin = join(directory, "bin");
  const fakeCast = join(fakeBin, "cast");
  const output = join(directory, "registry.json");
  await mkdir(fakeBin);
  const entry = deployment(withAdapter ? {} : {
    cpiAdapter: undefined,
    cpiSource: undefined,
    cpiSourceId: undefined,
    cpiPolicyUrl: undefined,
  });
  await writeFile(fakeCast, fakeCastScript());
  await chmod(fakeCast, 0o755);
  await writeFile(output, "{}\n");
  const environment = {
    ...process.env,
    PATH: `${fakeBin}:${process.env.PATH}`,
    RPC_URL: "http://fake.invalid",
    EXPECTED_CHAIN_ID: "31337",
    DEPLOYMENT_TX: entry.deploymentTx,
    TOKEN: entry.token,
    TEAM_VESTING: entry.teamVesting,
    TREASURY_VESTING: entry.treasuryVesting,
    DAO: entry.dao,
    PSM: entry.psm,
    TIMELOCK: entry.timelock,
    RESERVE_TOKEN: entry.reserveToken,
    RESERVE_SYMBOL: entry.reserveTokenSymbol,
    DEPLOYMENT_BLOCK: entry.deploymentBlock,
    TEAM_BENEFICIARY: `0x${"a".repeat(40)}`,
    TREASURY_BENEFICIARY: `0x${"b".repeat(40)}`,
    DEPLOYER_ADDRESS: `0x${"c".repeat(40)}`,
    ...(withAdapter ? {
      CPI_ADAPTER: entry.cpiAdapter,
      EXPECTED_CPI_SOURCE: entry.cpiSource,
      EXPECTED_CPI_SOURCE_ID: entry.cpiSourceId,
      CPI_POLICY_URL: entry.cpiPolicyUrl,
    } : {}),
  };
  const result = spawnSync(process.execPath, [recorder, "--chain-id", "31337", "--deployment-tx", entry.deploymentTx,
    "--explorer-url", entry.explorerUrl, "--source-url", entry.sourceVerificationUrl,
    "--journal-url", entry.journalUrl, "--output", output], {
    cwd: root, env: environment, encoding: "utf8",
  });
  const registry = result.status === 0 ? JSON.parse(await readFile(output, "utf8")) : undefined;
  await rm(directory, { recursive: true, force: true });
  return { result, registry, entry };
}

test("records and validates a core deployment manifest round trip", async () => {
  const { result, registry, entry } = await runRecorder(false);
  assert.equal(result.status, 0, result.stderr);
  assert.deepEqual(registry["31337"], {
    deploymentTx: entry.deploymentTx,
    explorerUrl: entry.explorerUrl,
    sourceVerificationUrl: entry.sourceVerificationUrl,
    journalUrl: entry.journalUrl,
    token: entry.token,
    teamVesting: entry.teamVesting,
    treasuryVesting: entry.treasuryVesting,
    dao: entry.dao,
    psm: entry.psm,
    timelock: entry.timelock,
    reserveToken: entry.reserveToken,
    reserveTokenSymbol: entry.reserveTokenSymbol,
    deploymentBlock: entry.deploymentBlock,
  });
  assert.equal((await runValidator(registry["31337"])).status, 0);
});

test("records and validates governed CPI source labels in a manifest round trip", async () => {
  const { result, registry, entry } = await runRecorder(true);
  assert.equal(result.status, 0, result.stderr);
  assert.equal(registry["31337"].cpiAdapter, entry.cpiAdapter.toLowerCase());
  assert.equal(registry["31337"].cpiSource, entry.cpiSource);
  assert.equal(registry["31337"].cpiSourceId, entry.cpiSourceId.toLowerCase());
  assert.equal(registry["31337"].cpiPolicyUrl, entry.cpiPolicyUrl);
  assert.equal((await runValidator(registry["31337"])).status, 0);
});

test("accepts a complete registry entry with governed CPI adapter metadata", async () => {
  const result = await runValidator(deployment());
  assert.equal(result.status, 0, result.stderr);
});

test("rejects a zero CPI source ID", async () => {
  const result = await runValidator(deployment({ cpiSourceId: `0x${"0".repeat(64)}` }));
  assert.notEqual(result.status, 0);
  assert.match(result.stderr, /invalid cpiSourceId/);
});

test("requires CPI policy evidence when adapter metadata is present", async () => {
  const result = await runValidator(deployment({ cpiPolicyUrl: undefined }));
  assert.notEqual(result.status, 0);
  assert.match(result.stderr, /invalid cpiPolicyUrl/);
});

test("requires a non-empty CPI source label when adapter metadata is present", async () => {
  const result = await runValidator(deployment({ cpiSource: "   " }));
  assert.notEqual(result.status, 0);
  assert.match(result.stderr, /invalid cpiSource/);
});

test("rejects a chain the frontend does not support", async () => {
  const result = await runValidator(deployment(), "1");
  assert.notEqual(result.status, 0);
  assert.match(result.stderr, /Unsupported deployment registry chain ID/);
});

test("requires a deployment journal", async () => {
  const result = await runValidator(deployment({ journalUrl: undefined }));
  assert.notEqual(result.status, 0);
  assert.match(result.stderr, /needs a journalUrl/);
});

test("accepts a successful mined deployment transaction", () => {
  verifyDeploymentReceipt({
    deploymentTx: `0x${"1".repeat(64)}`,
    deploymentBlock: "100",
    latestBlock: "0x70",
    receipt: { transactionHash: `0x${"1".repeat(64)}`, blockNumber: "0x64", status: "0x1" },
  });
});

test("rejects a failed deployment transaction", () => {
  assert.throws(
    () => verifyDeploymentReceipt({
      deploymentTx: `0x${"1".repeat(64)}`,
      deploymentBlock: "100",
      latestBlock: "112",
      receipt: { transactionHash: `0x${"1".repeat(64)}`, blockNumber: "100", status: "0x0" },
    }),
    /did not succeed/
  );
});

test("rejects deployment evidence above the chain tip", () => {
  assert.throws(
    () => verifyDeploymentReceipt({
      deploymentTx: `0x${"1".repeat(64)}`,
      deploymentBlock: "200",
      latestBlock: "150",
      receipt: { transactionHash: `0x${"1".repeat(64)}`, blockNumber: "200", status: "0x1" },
    }),
    /not yet mined/
  );
});

test("preflight reports a complete registry as ready", () => {
  const report = preflightDeploymentRegistry({ "31337": deployment() }, { chainId: "31337" });
  assert.equal(report.status, "ready");
  assert.ok(report.checks.every(({ status }) => status === "pass"));
});

test("preflight fails safely when the registry is empty", () => {
  const report = preflightDeploymentRegistry({});
  assert.equal(report.status, "not_ready");
  assert.match(report.checks.find(({ label }) => label === "registered deployment").detail, /empty/);
});

test("preflight identifies a missing requested chain", () => {
  const report = preflightDeploymentRegistry({ "31337": deployment() }, { chainId: "421614" });
  assert.equal(report.status, "not_ready");
  assert.equal(report.checks.find(({ label }) => label === "requested chain 421614").status, "fail");
});

test("preflight identifies malformed registry entries", () => {
  const report = preflightDeploymentRegistry({ "31337": deployment({ journalUrl: "http://unsafe.example" }) });
  assert.equal(report.status, "not_ready");
  assert.match(report.checks.find(({ label }) => label === "chain 31337: journalUrl").detail, /non-HTTPS/);
});

test("preflight requires HTTPS CPI policy evidence for adapter entries", () => {
  const report = preflightDeploymentRegistry({ "31337": deployment({ cpiPolicyUrl: "http://unsafe.example" }) });
  assert.equal(report.status, "not_ready");
  assert.match(report.checks.find(({ label }) => label === "chain 31337: CPI adapter policy evidence").detail, /HTTPS policy/);
});

test("preflight requires a non-empty CPI source label for adapter entries", () => {
  const report = preflightDeploymentRegistry({ "31337": deployment({ cpiSource: "" }) });
  assert.equal(report.status, "not_ready");
  assert.match(report.checks.find(({ label }) => label === "chain 31337: CPI adapter policy evidence").detail, /source label/);
});

test("preflight CLI emits JSON and a zero exit for a ready fixture", async () => {
  const result = await runPreflight(`${JSON.stringify({ "31337": deployment() })}\n`, ["--chain-id", "31337", "--json"]);
  assert.equal(result.status, 0, result.stderr);
  assert.equal(JSON.parse(result.stdout).status, "ready");
});

test("preflight CLI emits JSON for malformed input and exits nonzero", async () => {
  const result = await runPreflight("{ not-json\n", ["--json"]);
  assert.notEqual(result.status, 0);
  const report = JSON.parse(result.stdout);
  assert.equal(report.status, "not_ready");
  assert.equal(report.checks[0].label, "registry readable JSON");
});
