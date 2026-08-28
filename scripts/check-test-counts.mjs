#!/usr/bin/env node

import { readdirSync, readFileSync } from "node:fs";
import { spawnSync } from "node:child_process";
import path from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const CONTRACTS = path.join(ROOT, "contracts");
const CURRENT_DOCUMENTS = [
  "README.md",
  "CONTRIBUTING.md",
  "contracts/README.md",
  "docs/Architecture.md",
  "docs/DAO-Guide.md",
  "docs/TECHNICAL-DOCS.md",
];

export function parseFoundrySummary(output) {
  const suites = [];
  const runPattern = /^Ran\s+(\d+)\s+tests?\s+for\s+[^:]+:([^\s]+)\s*$/gm;
  for (const match of output.matchAll(runPattern)) {
    suites.push({ name: match[2], passed: Number(match[1]), failed: 0, skipped: 0 });
  }
  const finalResult = output.match(/Ran\s+\d+\s+(?:test suites?|tests?)\s+in[^\n]*:\s*(\d+)\s+tests?\s+passed,\s*(\d+)\s+failed,\s*(\d+)\s+skipped/);
  if (suites.length > 0 && finalResult) {
    // Foundry 1.8 reports an invariant contract as one test, while older releases report each
    // invariant function. Count the individual invariant assertions from their stable names so the
    // documented count remains comparable across supported Foundry versions.
    const invariants = (output.match(/^\s*\[PASS\]\s+invariant_[A-Za-z0-9_]+\s*$/gm) ?? []).length;
    const unit = suites
      .filter((suite) => !/InvariantTest$/.test(suite.name))
      .reduce((sum, suite) => sum + suite.passed, 0);
    return { total: unit + invariants, unit, invariants, failed: Number(finalResult[2]), skipped: Number(finalResult[3]), suites };
  }

  // Foundry 1.7's summary mode emits a table instead of per-suite result lines. Keep this fallback
  // for the local version documented by the project and normalize its invariant rows the same way.
  suites.length = 0;
  const tablePattern = /^\|\s*([^|]+?)\s*\|\s*(\d+)\s*\|\s*(\d+)\s*\|\s*(\d+)\s*\|\s*$/gm;
  for (const match of output.matchAll(tablePattern)) {
    const [, name, passed, failed, skipped] = match;
    if (!/^Test Suite$/i.test(name.trim())) suites.push({ name: name.trim(), passed: Number(passed), failed: Number(failed), skipped: Number(skipped) });
  }
  if (suites.length === 0) throw new Error("could not find Foundry test-suite results");
  const invariants = suites
    .filter((suite) => /InvariantTest$/.test(suite.name))
    .reduce((sum, suite) => sum + suite.passed, 0);
  const unit = suites
    .filter((suite) => !/InvariantTest$/.test(suite.name))
    .reduce((sum, suite) => sum + suite.passed, 0);
  const failed = suites.reduce((sum, suite) => sum + suite.failed, 0);
  const skipped = suites.reduce((sum, suite) => sum + suite.skipped, 0);
  return { total: unit + invariants, unit, invariants, failed, skipped, suites };
}

export function validateCurrentDocumentation(summary, documents = CURRENT_DOCUMENTS, root = ROOT, readText = (file) => readFileSync(file, "utf8")) {
  const expected = [String(summary.total), String(summary.unit), String(summary.invariants)];
  const errors = [];
  for (const relativePath of documents) {
    const file = path.join(root, relativePath);
    const text = readText(file);
    for (const value of expected) {
      if (!new RegExp(`\\b${value}\\b`).test(text)) {
        errors.push(`${relativePath} does not mention current count ${value}`);
      }
    }
  }
  return errors;
}

export function parseFoundryJson(output) {
  const suites = [];
  const results = JSON.parse(output);
  for (const [suiteName, suite] of Object.entries(results)) {
    for (const [testName, test] of Object.entries(suite.test_results ?? {})) {
      const status = test.status;
      suites.push({
        name: suiteName,
        testName,
        passed: status === "Success" ? 1 : 0,
        failed: status === "Failure" ? 1 : 0,
        skipped: status === "Skipped" ? 1 : 0,
      });
    }
  }
  if (suites.length === 0) throw new Error("could not find Foundry JSON test results");
  const invariants = suites.filter((test) => test.testName.startsWith("invariant_")).length;
  const unit = suites.length - invariants;
  const failed = suites.reduce((sum, test) => sum + test.failed, 0);
  const skipped = suites.reduce((sum, test) => sum + test.skipped, 0);
  return { total: unit + invariants, unit, invariants, failed, skipped, suites };
}

export function countInvariantFunctions(testRoot = path.join(CONTRACTS, "test")) {
  let count = 0;
  for (const entry of readdirSync(testRoot, { withFileTypes: true, recursive: true })) {
    if (!entry.isFile() || !entry.name.endsWith(".sol")) continue;
    const file = path.join(entry.parentPath ?? testRoot, entry.name);
    count += (readFileSync(file, "utf8").match(/^\s*function\s+invariant_[A-Za-z0-9_]+\s*\(/gm) ?? []).length;
  }
  if (count === 0) throw new Error("could not find invariant functions in the Foundry test tree");
  return count;
}

export function run() {
  const result = spawnSync("forge", ["test", "--json"], {
    cwd: CONTRACTS,
    encoding: "utf8",
    maxBuffer: 16 * 1024 * 1024,
  });
  const output = result.stdout ?? "";
  if (result.error) throw new Error(`could not run forge: ${result.error.message}`);
  if (result.status !== 0) throw new Error(`forge test failed with exit code ${result.status}`);
  const summary = parseFoundryJson(output);
  summary.invariants = countInvariantFunctions();
  summary.total = summary.unit + summary.invariants;
  if (summary.failed !== 0 || summary.skipped !== 0) {
    throw new Error(`Foundry summary contains ${summary.failed} failed and ${summary.skipped} skipped tests`);
  }
  const errors = validateCurrentDocumentation(summary);
  if (errors.length > 0) throw new Error(errors.join("; "));
  console.log(`Foundry test counts synchronized: ${summary.total} total (${summary.unit} unit/configuration + ${summary.invariants} invariants)`);
}

if (import.meta.url === pathToFileURL(path.resolve(process.argv[1] ?? "")).href) {
  try {
    run();
  } catch (error) {
    console.error(`error: ${error instanceof Error ? error.message : String(error)}`);
    process.exitCode = 1;
  }
}
