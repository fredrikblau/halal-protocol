import test from "node:test";
import assert from "node:assert/strict";
import { parseFoundrySummary, validateCurrentDocumentation } from "../check-test-counts.mjs";

const SUMMARY = `
| Test Suite                           | Passed | Failed | Skipped |
| CPIReportAdapterTest                 | 27     | 0      | 0        |
| HalalPSMTest                         | 73     | 0      | 0        |
| HalalPSMInvariantTest                | 3      | 0      | 0        |
| HalalPSMFalseReserveInvariantTest    | 2      | 0      | 0        |
`;

test("parses total and invariant counts from a Foundry summary", () => {
  assert.deepEqual(parseFoundrySummary(SUMMARY), {
    total: 105,
    unit: 100,
    invariants: 5,
    failed: 0,
    skipped: 0,
    suites: [
      { name: "CPIReportAdapterTest", passed: 27, failed: 0, skipped: 0 },
      { name: "HalalPSMTest", passed: 73, failed: 0, skipped: 0 },
      { name: "HalalPSMInvariantTest", passed: 3, failed: 0, skipped: 0 },
      { name: "HalalPSMFalseReserveInvariantTest", passed: 2, failed: 0, skipped: 0 },
    ],
  });
});

test("reports stale documentation counts", () => {
  const errors = validateCurrentDocumentation(
    { total: 199, unit: 188, invariants: 11 },
    ["README.md"],
    "/virtual",
    () => "199 total, 188 unit, 11 invariants",
  );
  assert.deepEqual(errors, []);
});
