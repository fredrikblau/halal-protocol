import assert from "node:assert/strict";
import { chmod, mkdtemp, readFile, writeFile, rm } from "node:fs/promises";
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

async function runRecorder(withAdapter) {
  const directory = await mkdtemp(join(tmpdir(), "halal-recorder-"));
  const fakeCast = join(directory, "cast");
  const fakeBash = join(directory, "bash");
  const output = join(directory, "registry.json");
  await writeFile(output, "{}\n");
  await writeFile(
    fakeCast,
    `#!/usr/bin/bash
set -euo pipefail
case "\$1" in
  receipt) echo '{"transactionHash":"0x${"1".repeat(64)}","blockNumber":"0x64","status":"0x1"}' ;;
  block) echo 0x70 ;;
  *) echo "unexpected fake cast command: \$*" >&2; exit 1 ;;
esac
`,
  );
  await writeFile(
    fakeBash,
    `#!/usr/bin/bash
set -euo pipefail
if [[ "\$1" == *verify-deployment.sh ]]; then
  echo "fake deployment verifier passed"
  exit 0
fi
exec /usr/bin/bash "\$@"
`,
  );
  await chmod(fakeCast, 0o755);
  await chmod(fakeBash, 0o755);

  const env = {
    ...process.env,
    PATH: `${directory}:${process.env.PATH}`,
    RPC_URL: "http://fake-rpc.invalid",
    EXPECTED_CHAIN_ID: "421614",
    TOKEN: `0x${"1".repeat(40)}`,
    TEAM_VESTING: `0x${"2".repeat(40)}`,
    TREASURY_VESTING: `0x${"3".repeat(40)}`,
    DAO: `0x${"4".repeat(40)}`,
    PSM: `0x${"5".repeat(40)}`,
    TIMELOCK: `0x${"6".repeat(40)}`,
    RESERVE_TOKEN: `0x${"7".repeat(40)}`,
    RESERVE_SYMBOL: "USDC",
    DEPLOYMENT_BLOCK: "100",
    TEAM_BENEFICIARY: `0x${"8".repeat(40)}`,
    TREASURY_BENEFICIARY: `0x${"9".repeat(40)}`,
    DEPLOYER_ADDRESS: `0x${"a".repeat(40)}`,
    ...(withAdapter
      ? {
          CPI_ADAPTER: `0x${"b".repeat(40)}`,
          EXPECTED_CPI_SOURCE: "BLS:CUUR0000SA0",
          EXPECTED_CPI_SOURCE_ID: `0x${"c".repeat(64)}`,
          CPI_POLICY_URL: "https://example.com/cpi-policy",
        }
      : {}),
  };
  const result = spawnSync(
    process.execPath,
    [recorder, "--chain-id", "421614", "--network", "arbitrum-sepolia", "--release", "v0.1.0-test", "--commit", "d".repeat(40), "--deployment-tx", `0x${"1".repeat(64)}`, "--explorer-url", "https://example.com/tx/1", "--source-url", "https://example.com/address/1#code", "--journal-url", "https://example.com/journal/1", "--output", output],
    { cwd: root, env, encoding: "utf8" },
  );
  const recorded = result.status === 0 ? JSON.parse(await readFile(output, "utf8")) : null;
  await rm(directory, { recursive: true, force: true });
  return { result, recorded };
}

test("accepts a complete registry entry with governed CPI adapter metadata", async () => {
  const result = await runValidator(deployment());
  assert.equal(result.status, 0, result.stderr);
});

test("records governed CPI source metadata and preserves the full manifest round trip", async () => {
  const { result, recorded } = await runRecorder(true);
  assert.equal(result.status, 0, `${result.stdout}\n${result.stderr}`);
  const entry = recorded["421614"];
  assert.equal(entry.cpiSource, "BLS:CUUR0000SA0");
  assert.equal(entry.cpiSourceId, `0x${"c".repeat(64)}`);
  assert.equal(entry.cpiPolicyUrl, "https://example.com/cpi-policy");
  assert.equal(entry.psm, `0x${"5".repeat(40)}`);

  const validation = await runValidator(entry, "421614");
  assert.equal(validation.status, 0, validation.stderr);
});

test("records the core manifest without adapter metadata", async () => {
  const { result, recorded } = await runRecorder(false);
  assert.equal(result.status, 0, `${result.stdout}\n${result.stderr}`);
  const entry = recorded["421614"];
  assert.equal(entry.reserveTokenSymbol, "USDC");
  assert.equal(entry.cpiAdapter, undefined);

  const validation = await runValidator(entry, "421614");
  assert.equal(validation.status, 0, validation.stderr);
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
