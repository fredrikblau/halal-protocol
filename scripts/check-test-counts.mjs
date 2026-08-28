#!/usr/bin/env node

import { readFileSync } from "node:fs";
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
  const rowPattern = /^\|\s*([^|]+?)\s*\|\s*(\d+)\s*\|\s*(\d+)\s*\|\s*(\d+)\s*\|\s*$/gm;
  for (const match of output.matchAll(rowPattern)) {
    const [, name, passed, failed, skipped] = match;
    if (/^Test Suite$/i.test(name.trim())) continue;
    suites.push({ name: name.trim(), passed: Number(passed), failed: Number(failed), skipped: Number(skipped) });
  }
  if (suites.length === 0) throw new Error("could not find a Foundry summary table");
  const failed = suites.reduce((sum, suite) => sum + suite.failed, 0);
  const skipped = suites.reduce((sum, suite) => sum + suite.skipped, 0);
  const total = suites.reduce((sum, suite) => sum + suite.passed, 0);
  const invariants = suites
    .filter((suite) => /InvariantTest$/.test(suite.name))
    .reduce((sum, suite) => sum + suite.passed, 0);
  return { total, unit: total - invariants, invariants, failed, skipped, suites };
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

export function run() {
  const result = spawnSync("forge", ["test", "--summary"], { cwd: CONTRACTS, encoding: "utf8" });
  const output = `${result.stdout ?? ""}\n${result.stderr ?? ""}`;
  if (result.error) throw new Error(`could not run forge: ${result.error.message}`);
  if (result.status !== 0) throw new Error(`forge test failed with exit code ${result.status}`);
  const summary = parseFoundrySummary(output);
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
