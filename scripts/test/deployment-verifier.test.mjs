import assert from "node:assert/strict";
import { chmodSync, mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { spawnSync } from "node:child_process";
import { tmpdir } from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";
import test from "node:test";

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "../..");
const VERIFIER = path.join(ROOT, "scripts/verify-deployment.sh");
const ADDRESSES = {
  timelock: "0x0000000000000000000000000000000000000001",
  token: "0x0000000000000000000000000000000000000002",
  teamVesting: "0x0000000000000000000000000000000000000003",
  treasuryVesting: "0x0000000000000000000000000000000000000004",
  dao: "0x0000000000000000000000000000000000000005",
  psm: "0x0000000000000000000000000000000000000006",
  reserve: "0x0000000000000000000000000000000000000007",
  adapter: "0x0000000000000000000000000000000000000008",
  teamBeneficiary: "0x0000000000000000000000000000000000000009",
  treasuryBeneficiary: "0x000000000000000000000000000000000000000a",
  deployer: "0x000000000000000000000000000000000000000b",
  signerOne: "0x000000000000000000000000000000000000000c",
  signerTwo: "0x000000000000000000000000000000000000000d",
};
const SOURCE_ID = `0x${"a".repeat(64)}`;

function fakeCastScript() {
  return `#!/usr/bin/env bash
set -euo pipefail
case "$1" in
  chain-id) echo "\${FAKE_CHAIN_ID:-421614}" ;;
  code) [[ -n "\${FAKE_EOA:-}" && "$2" == "$FAKE_EOA" ]] && echo 0x || echo 0x1234 ;;
  call)
    target="$2"
    signature="$3"
    case "$signature" in
      'reserve()('* ) echo ${ADDRESSES.reserve} ;;
      'hlc()('* ) echo ${ADDRESSES.token} ;;
      'token()('* ) echo ${ADDRESSES.token} ;;
      'dao()('* ) echo ${ADDRESSES.timelock} ;;
      'timelock()('* ) echo ${ADDRESSES.timelock} ;;
      'getMinDelay()('* ) echo 172800 ;;
      'genesisMinted()('* ) echo true ;;
      'TEAM_ALLOCATION()('* ) echo 6000000000000000000000000 ;;
      'TREASURY_ALLOCATION()('* ) echo 4000000000000000000000000 ;;
      'totalAllocation()('* ) [[ "$target" == "${ADDRESSES.teamVesting}" ]] && echo 6000000000000000000000000 || echo 4000000000000000000000000 ;;
      'cliff()('* ) [[ "$target" == "${ADDRESSES.teamVesting}" ]] && echo 31536000 || echo 0 ;;
      'duration()('* ) [[ "$target" == "${ADDRESSES.teamVesting}" ]] && echo 126144000 || echo 94608000 ;;
      'revocable()('* ) [[ "$target" == "${ADDRESSES.teamVesting}" ]] && echo true || echo false ;;
      'beneficiary()('* ) [[ "$target" == "${ADDRESSES.teamVesting}" ]] && echo ${ADDRESSES.teamBeneficiary} || echo ${ADDRESSES.treasuryBeneficiary} ;;
      'MINTER_ROLE()('*|'BURNER_ROLE()('*|'DEFAULT_ADMIN_ROLE()('*|'PROPOSER_ROLE()('*|'EXECUTOR_ROLE()('*|'PARAM_ROLE()('*|'UPDATER_ROLE()('* ) echo 0x$(printf '0%.0s' {1..64}) ;;
      hasRole*)
        [[ " $* " == *" ${ADDRESSES.deployer} "* ]] && echo false || echo true ;;
      'psm()('* ) echo ${ADDRESSES.psm} ;;
      'owner()('* ) echo ${ADDRESSES.timelock} ;;
      'sourceId()('* ) echo ${SOURCE_ID} ;;
      'source()('* ) echo '"BLS:CUUR0000SA0"' ;;
      'lastSubmittedTimestamp()('* ) echo "\${FAKE_ADAPTER_WATERMARK:-0}" ;;
      'lastReportTimestamp()('* ) echo "\${FAKE_PSM_WATERMARK:-0}" ;;
      'threshold()('* ) echo "\${FAKE_ADAPTER_THRESHOLD:-2}" ;;
      'signerCount()('* ) echo "\${FAKE_ADAPTER_SIGNER_COUNT:-2}" ;;
      signerAt*) [[ "$4" == 0 ]] && echo ${ADDRESSES.signerOne} || echo ${ADDRESSES.signerTwo} ;;
      *) echo "unexpected fake cast call: $*" >&2; exit 1 ;;
    esac
    ;;
  *) echo "unexpected fake cast command: $*" >&2; exit 1 ;;
esac
`;
}

function runVerifier(withAdapter, overrides = {}) {
  const directory = mkdtempSync(path.join(tmpdir(), "halal-deployment-verifier-"));
  const fakeCast = path.join(directory, "cast");
  writeFileSync(fakeCast, fakeCastScript());
  chmodSync(fakeCast, 0o755);
  const env = {
    ...process.env,
    PATH: `${directory}:${process.env.PATH}`,
    RPC_URL: "http://fake-rpc.invalid",
    EXPECTED_CHAIN_ID: "421614",
    TIMELOCK: ADDRESSES.timelock,
    TOKEN: ADDRESSES.token,
    TEAM_VESTING: ADDRESSES.teamVesting,
    TREASURY_VESTING: ADDRESSES.treasuryVesting,
    DAO: ADDRESSES.dao,
    PSM: ADDRESSES.psm,
    RESERVE_TOKEN: ADDRESSES.reserve,
    TEAM_BENEFICIARY: ADDRESSES.teamBeneficiary,
    TREASURY_BENEFICIARY: ADDRESSES.treasuryBeneficiary,
    DEPLOYER_ADDRESS: ADDRESSES.deployer,
    ...(withAdapter ? { CPI_ADAPTER: ADDRESSES.adapter, EXPECTED_CPI_SOURCE: "BLS:CUUR0000SA0", EXPECTED_CPI_SOURCE_ID: SOURCE_ID } : {}),
    ...overrides,
  };
  try {
    return spawnSync("bash", [VERIFIER], { cwd: ROOT, env, encoding: "utf8" });
  } finally {
    rmSync(directory, { recursive: true, force: true });
  }
}

test("deployment verifier checks governed CPI adapter metadata", () => {
  const result = runVerifier(true);
  assert.equal(result.status, 0, `${result.stdout}\n${result.stderr}`);
  assert.match(result.stdout, /Halal deployment wiring verified/);
});

test("deployment verifier keeps the core path valid without an adapter", () => {
  const result = runVerifier(false);
  assert.equal(result.status, 0, `${result.stdout}\n${result.stderr}`);
});

test("deployment verifier rejects mismatched CPI adapter and PSM watermarks", () => {
  const result = runVerifier(true, { FAKE_ADAPTER_WATERMARK: "10", FAKE_PSM_WATERMARK: "9" });
  assert.notEqual(result.status, 0);
  assert.match(result.stderr, /CPI adapter report watermark/);
});

test("deployment verifier rejects an oversized CPI adapter signer count", () => {
  const result = runVerifier(true, { FAKE_ADAPTER_SIGNER_COUNT: "65" });
  assert.notEqual(result.status, 0);
  assert.match(result.stderr, /CPI adapter signer count/);
});

test("deployment verifier rejects a changed PSM CPI source label", () => {
  const result = runVerifier(true, { EXPECTED_CPI_SOURCE: "different-source" });
  assert.notEqual(result.status, 0);
  assert.match(result.stderr, /PSM CPI source/);
});

test("deployment verifier rejects shared production beneficiaries", () => {
  const result = runVerifier(false, {
    TEAM_BENEFICIARY: ADDRESSES.teamBeneficiary,
    TREASURY_BENEFICIARY: ADDRESSES.teamBeneficiary,
  });
  assert.notEqual(result.status, 0);
  assert.match(result.stderr, /team and treasury beneficiaries must be distinct/);
});

test("deployment verifier rejects EOA production beneficiaries", () => {
  const result = runVerifier(false, { FAKE_EOA: ADDRESSES.teamBeneficiary });
  assert.notEqual(result.status, 0);
  assert.match(result.stderr, /team beneficiary has no deployed contract bytecode/);
});

test("deployment verifier rejects an EOA CPI adapter owner", () => {
  const result = runVerifier(true, {
    FAKE_EOA: ADDRESSES.signerOne,
    EXPECTED_CPI_ADAPTER_OWNER: ADDRESSES.signerOne,
  });
  assert.notEqual(result.status, 0);
  assert.match(result.stderr, /CPI adapter owner has no deployed contract bytecode/);
});

test("deployment verifier rejects the local beneficiary escape hatch on a remote chain", () => {
  const result = runVerifier(false, { ALLOW_DEPLOYER_BENEFICIARY: "true" });
  assert.notEqual(result.status, 0);
  assert.match(result.stderr, /restricted to Anvil chain 31337/);
});

test("deployment verifier permits the beneficiary escape hatch only on loopback Anvil", () => {
  const result = runVerifier(false, {
    ALLOW_DEPLOYER_BENEFICIARY: "true",
    EXPECTED_CHAIN_ID: "31337",
    FAKE_CHAIN_ID: "31337",
    RPC_URL: "http://127.0.0.1:8545",
  });
  assert.equal(result.status, 0, `${result.stdout}\n${result.stderr}`);
});
