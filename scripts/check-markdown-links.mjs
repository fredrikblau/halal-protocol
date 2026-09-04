#!/usr/bin/env node

import { execFileSync } from "node:child_process";
import { existsSync, readFileSync, statSync } from "node:fs";
import { relative, resolve, sep } from "node:path";
import { fileURLToPath } from "node:url";

const scriptPath = fileURLToPath(import.meta.url);
const defaultRoot = resolve(scriptPath, "../..");
const args = new Map(process.argv.slice(2).map((arg) => {
  const [key, ...value] = arg.split("=");
  return [key, value.join("=")];
}));
const root = resolve(args.get("--root") ?? defaultRoot);

function markdownFiles() {
  if (args.has("--files")) return args.get("--files").split(",").filter(Boolean);
  return execFileSync("git", ["ls-files", "--", "*.md"], { cwd: root, encoding: "utf8" })
    .split(/\r?\n/)
    .filter(Boolean);
}

function withoutFencedCode(markdown) {
  const output = [];
  let fence = null;
  for (const line of markdown.split(/\r?\n/)) {
    const marker = line.match(/^ {0,3}(`{3,}|~{3,})/);
    if (fence) {
      if (marker && marker[1][0] === fence[0] && marker[1].length >= fence.length) fence = null;
      output.push("");
    } else if (marker) {
      fence = marker[1];
      output.push("");
    } else {
      output.push(line);
    }
  }
  return output.join("\n");
}

function stripHtmlTags(value) {
  let previous;
  do {
    previous = value;
    value = value.replace(/<[^>]*>/g, "");
  } while (value !== previous);
  return value;
}

function githubSlug(heading) {
  return stripHtmlTags(heading)
    .replace(/!?(\[[^\]]*\])\([^)]*\)/g, "$1")
    .replace(/[`*_~]/g, "")
    .trim()
    .toLowerCase()
    .replace(/\s+/g, "-")
    .replace(/[^\p{L}\p{N}-]/gu, "");
}

function headings(markdown) {
  const result = new Set();
  const counts = new Map();
  for (const line of markdown.split(/\r?\n/)) {
    const match = line.match(/^ {0,3}#{1,6}\s+(.+?)\s*#*\s*$/);
    if (!match) continue;
    const base = githubSlug(match[1]);
    const count = counts.get(base) ?? 0;
    counts.set(base, count + 1);
    result.add(count === 0 ? base : `${base}-${count}`);
  }
  return result;
}

function isExternal(target) {
  return /^(?:[a-z][a-z\d+.-]*:|\/\/)/i.test(target);
}

function validateFile(relativeFile) {
  const file = resolve(root, relativeFile);
  const markdown = readFileSync(file, "utf8");
  const errors = [];
  const source = withoutFencedCode(markdown);
  const linkPattern = /!?\[[^\]]*\]\(\s*(<[^>]+>|[^)\s]+)(?:\s+["'][^)]*["'])?\s*\)/g;

  for (const match of source.matchAll(linkPattern)) {
    let target = match[1];
    if (target.startsWith("<") && target.endsWith(">")) target = target.slice(1, -1);
    if (isExternal(target)) continue;

    const hashIndex = target.indexOf("#");
    const pathPart = hashIndex === -1 ? target : target.slice(0, hashIndex);
    const fragment = hashIndex === -1 ? "" : decodeURIComponent(target.slice(hashIndex + 1));
    const targetPath = pathPart ? resolve(file, "..", decodeURIComponent(pathPart)) : file;
    const line = source.slice(0, match.index).split(/\r?\n/).length;
    const display = `${relative(root, file)}:${line}`;

    if (!targetPath.startsWith(`${root}${sep}`) && targetPath !== root) {
      errors.push(`${display}: link escapes repository root: ${target}`);
      continue;
    }
    if (!existsSync(targetPath)) {
      errors.push(`${display}: missing link target: ${target}`);
      continue;
    }
    if (fragment && statSync(targetPath).isFile() && targetPath.toLowerCase().endsWith(".md")) {
      const targetHeadings = headings(readFileSync(targetPath, "utf8"));
      if (!targetHeadings.has(fragment.toLowerCase())) {
        errors.push(`${display}: missing anchor "#${fragment}" in ${relative(root, targetPath)}`);
      }
    }
  }
  return errors;
}

const files = markdownFiles();
const errors = files.flatMap(validateFile);
if (errors.length > 0) {
  console.error(errors.join("\n"));
  process.exitCode = 1;
} else {
  console.log(`Markdown links checked: ${files.length} files`);
}
