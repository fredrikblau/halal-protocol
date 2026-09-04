import test from "node:test";
import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { mkdtempSync, rmSync, writeFileSync } from "node:fs";
import os from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "../..");
const CHECKER = path.join(ROOT, "scripts/check-markdown-links.mjs");

function runFixture(markdown) {
  const fixture = mkdtempSync(path.join(os.tmpdir(), "halal-markdown-links-"));
  writeFileSync(path.join(fixture, "README.md"), markdown);
  try {
    return execFileSync(process.execPath, [CHECKER, `--root=${fixture}`, "--files=README.md"], {
      encoding: "utf8",
      stdio: "pipe",
    });
  } finally {
    rmSync(fixture, { recursive: true, force: true });
  }
}

test("accepts existing files, anchors, and external links", () => {
  const fixture = mkdtempSync(path.join(os.tmpdir(), "halal-markdown-links-"));
  writeFileSync(path.join(fixture, "README.md"), "# Guide\n\n[Details](details.md#data-model)\n[External](https://example.com)\n");
  writeFileSync(path.join(fixture, "details.md"), "# Data model\n");
  try {
    const output = execFileSync(process.execPath, [CHECKER, `--root=${fixture}`, "--files=README.md"], { encoding: "utf8" });
    assert.match(output, /Markdown links checked: 1 files/);
  } finally {
    rmSync(fixture, { recursive: true, force: true });
  }
});

test("rejects a broken internal link", () => {
  assert.throws(
    () => runFixture("# Guide\n\n[Broken](missing.md)\n"),
    /missing link target/,
  );
});

test("rejects a missing heading anchor", () => {
  const fixture = mkdtempSync(path.join(os.tmpdir(), "halal-markdown-links-"));
  writeFileSync(path.join(fixture, "README.md"), "[Details](details.md#missing)\n");
  writeFileSync(path.join(fixture, "details.md"), "# Present\n");
  try {
    assert.throws(
      () => execFileSync(process.execPath, [CHECKER, `--root=${fixture}`, "--files=README.md"], { encoding: "utf8", stdio: "pipe" }),
      /missing anchor/,
    );
  } finally {
    rmSync(fixture, { recursive: true, force: true });
  }
});

test("ignores link-shaped text inside fenced code", () => {
  const output = runFixture("# Guide\n\n```md\n[Example](missing.md)\n```\n");
  assert.match(output, /Markdown links checked/);
});

test("strips nested HTML-like tags before generating heading anchors", () => {
  const output = runFixture("# <scr<script>ipt>alert</script>\n\n[Alert](#iptalert)\n");
  assert.match(output, /Markdown links checked/);
});
