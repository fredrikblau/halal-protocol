import test from "node:test";
import assert from "node:assert/strict";
import { countInvariantFunctions, parseFoundryJson, parseFoundrySummary, validateCurrentDocumentation } from "../check-test-counts.mjs";

const SUMMARY = `
Ran 27 tests for test/CPIReportAdapter.t.sol:CPIReportAdapterTest
Ran 73 tests for test/HalalPSM.t.sol:HalalPSMTest
Ran 1 test for test/HalalPSMAdversarialInvariant.t.sol:HalalPSMInvariantTest
  [PASS] invariant_Accounting
  [PASS] invariant_Collateral
Ran 1 test for test/HalalPSMAdversarialInvariant.t.sol:HalalPSMFalseReserveInvariantTest
  [PASS] invariant_FalseReserve
Ran 105 tests in 1 suite: 100 tests passed, 0 failed, 0 skipped
`;

test("parses total and invariant counts from a Foundry summary", () => {
  assert.deepEqual(parseFoundrySummary(SUMMARY), {
    total: 103,
    unit: 100,
    invariants: 3,
    failed: 0,
    skipped: 0,
    suites: [
      { name: "CPIReportAdapterTest", passed: 27, failed: 0, skipped: 0 },
      { name: "HalalPSMTest", passed: 73, failed: 0, skipped: 0 },
      { name: "HalalPSMInvariantTest", passed: 1, failed: 0, skipped: 0 },
      { name: "HalalPSMFalseReserveInvariantTest", passed: 1, failed: 0, skipped: 0 },
    ],
  });
});

test("counts individual invariant results from Foundry JSON", () => {
  const summary = parseFoundryJson(JSON.stringify({
    "test/HalalPSM.t.sol:HalalPSMTest": {
      test_results: {
        test_deposit: { status: "Success" },
      },
    },
    "test/HalalPSMInvariant.t.sol:HalalPSMInvariantTest": {
      test_results: {
        invariant_supply: { status: "Success" },
        invariant_credit: { status: "Success" },
      },
    },
  }));
  assert.equal(summary.total, 3);
  assert.equal(summary.unit, 1);
  assert.equal(summary.invariants, 2);
  assert.equal(summary.failed, 0);
  assert.equal(summary.skipped, 0);
});

test("counts invariant declarations independently of Foundry suite reporting", () => {
  assert.equal(
    countInvariantFunctions("contracts/test"),
    11,
  );
});

test("accepts synchronized documentation counts", () => {
  const errors = validateCurrentDocumentation(
    { total: 199, unit: 188, invariants: 11 },
    ["README.md"],
    "/virtual",
    () => "199 total, 188 unit, 11 invariants",
  );
  assert.deepEqual(errors, []);
});

test("reports stale unit and invariant counts", () => {
  const errors = validateCurrentDocumentation(
    { total: 196, unit: 185, invariants: 11 },
    ["README.md"],
    "/virtual",
    () => "196 total, 183 unit, 13 invariants",
  );
  assert.deepEqual(errors, [
    "README.md does not mention current count 185",
    "README.md does not mention current count 11",
  ]);
});
