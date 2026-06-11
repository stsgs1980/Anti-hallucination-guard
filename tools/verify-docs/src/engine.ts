// ============================================================================
// engine.ts -- Core verification engine
//
// Generic, project-agnostic. Reads a config, resolves sources, compares.
// Custom source types can be registered via registerSource() from resolvers.ts.
// ============================================================================

import { readFileSync, existsSync } from "fs";
import { join } from "path";
import type { CheckConfig, VerifyConfig, VerifyResult, LineResult } from "./types.js";
import { registerSource, findFiles, safeRead, resolveFromRegistry } from "./resolvers.js";

// Re-export types and registerSource so existing consumers (cli.ts, init.ts) work unchanged
export type { CheckConfig, CrossRepoConfig, VerifyConfig, VerifyResult, LineResult, SourceResolver } from "./types.js";
export { registerSource } from "./resolvers.js";

// ── Check resolver ─────────────────────────────────────────────────────────

function resolveCheck(
  check: CheckConfig,
  root: string,
  readmeContent: string
): { actual: number | null; readme: number | null } {
  let actual: number | null = resolveFromRegistry(check.source, root);

  // file: with countPattern -- count regex matches in a file
  if (check.source.startsWith("file:")) {
    const filePath = join(root, check.source.slice(5));
    const content = safeRead(filePath);
    if (content && check.countPattern) {
      const regex = new RegExp(check.countPattern, "gm");
      const matches = content.match(regex);
      if (matches) {
        const filtered = check.countExclude
          ? matches.filter((m) => !check.countExclude!.some((exc) => m.includes(exc)))
          : matches;
        actual = filtered.length;
      }
    }
  }

  // Apply exclude for glob
  if (check.source.startsWith("glob:") && check.exclude && actual !== null) {
    const globPath = check.source.slice(5);
    const fileName = globPath.split("/").pop()!;
    const dir = globPath.split("/").slice(0, -1).join("/");
    const regex = new RegExp(
      fileName.replace(/\*/g, ".*").replace(/\./g, "\\.") + "$"
    );
    let files = findFiles(dir || ".", regex, root);
    for (const exc of check.exclude) {
      files = files.filter((f) => !f.includes(exc));
    }
    actual = files.length;
  }

  // Get readme value
  let readme: number | null = null;
  if (check.readmePattern) {
    const match = readmeContent.match(new RegExp(check.readmePattern));
    readme = match ? parseInt(match[1], 10) : null;
  }

  return { actual, readme };
}

// ── Main engine ───────────────────────────────────────────────────────────

/**
 * Run the verification engine.
 *
 * @param root - Absolute path to the project root
 * @param config - Verification config (usually loaded from verify-docs.json)
 * @param options - Optional: { ci: true } to skip cross-repo checks
 * @returns VerifyResult with pass/fail status and detailed output
 */
export function verify(
  root: string,
  config: VerifyConfig,
  options?: { ci?: boolean }
): VerifyResult {
  const ci = options?.ci ?? false;
  const readmeContent = readFileSync(join(root, config.readme), "utf-8");
  const section1: LineResult[] = [];
  const section2: LineResult[] = [];
  let errors = 0;

  // ── Section 1: README vs Code ─────────────────────────────────────────

  for (const check of config.checks) {
    const { actual, readme } = resolveCheck(check, root, readmeContent);

    if (check.infoOnly) {
      section1.push({
        status: "info",
        name: check.name,
        detail: `code=${actual ?? "?"}`,
      });
      continue;
    }
    if (readme === null) {
      section1.push({
        status: "skip",
        name: check.name,
        detail: "not in README",
      });
      continue;
    }
    if (actual === null) {
      section1.push({
        status: "skip",
        name: check.name,
        detail: "can't count from source",
      });
      continue;
    }

    const tol = check.tolerance || 0;
    const ok = actual === readme || (tol && Math.abs(actual - readme) <= tol);
    const detail = ok && tol && actual !== readme
      ? `code=${actual} readme=${readme} MATCH (+/-${tol})`
      : ok
        ? `code=${actual} readme=${readme} MATCH`
        : `code=${actual} readme=${readme} MISMATCH -> fix: ${readme} -> ${actual}`;

    if (!ok) errors++;
    section1.push({ status: ok ? "OK" : "ERR", name: check.name, detail });
  }

  // Build lookup for cross-repo references
  const actualValues: Record<string, number> = {};
  for (const check of config.checks) {
    const { actual } = resolveCheck(check, root, readmeContent);
    if (actual !== null) actualValues[check.name] = actual;
  }

  // ── Section 2: Cross-repo consistency ─────────────────────────────────

  for (const cross of config.crossRepo ?? []) {
    if (ci) {
      section2.push({
        status: "ci",
        name: cross.name,
        detail: "skipped (no sibling repos in CI)",
      });
      continue;
    }

    const repoPath = join(root, cross.repo);
    if (!existsSync(repoPath)) {
      section2.push({
        status: "skip",
        name: cross.name,
        detail: `${cross.repo} not found`,
      });
      continue;
    }

    const filePath = join(
      repoPath,
      cross.source.startsWith("file:") ? cross.source.slice(5) : cross.source
    );
    const content = safeRead(filePath);
    if (!content) {
      section2.push({
        status: "skip",
        name: cross.name,
        detail: "can't read file",
      });
      continue;
    }

    let crossValue: number | null = null;
    if (cross.filePattern) {
      if (cross.filePattern.startsWith("extract:")) {
        const pat = cross.filePattern.slice(8);
        const match = content.match(new RegExp(pat));
        crossValue = match ? parseInt(match[1], 10) : null;
      } else {
        crossValue = (
          content.match(new RegExp(cross.filePattern, "gm")) || []
        ).length;
      }
    }

    if (crossValue === null) {
      section2.push({
        status: "skip",
        name: cross.name,
        detail: "pattern not found",
      });
      continue;
    }

    let expected: number | null = null;
    if (cross.matchAgainst) {
      expected = actualValues[cross.matchAgainst] ?? null;
    } else if (cross.readmePattern) {
      const readmeMatch = readmeContent.match(new RegExp(cross.readmePattern));
      expected = readmeMatch ? parseInt(readmeMatch[1], 10) : null;
    }

    if (expected === null) {
      section2.push({
        status: "skip",
        name: cross.name,
        detail: "no expected value",
      });
      continue;
    }

    const tol = cross.tolerance || 0;
    const okMatch =
      crossValue === expected ||
      (tol && Math.abs(crossValue - expected) <= tol);
    const detail = okMatch && tol && crossValue !== expected
      ? `value=${crossValue} expected=${expected} (+/-${tol})`
      : okMatch
        ? `value=${crossValue} expected=${expected} MATCH`
        : `value=${crossValue} expected=${expected} MISMATCH -> fix: ${crossValue} -> ${expected}`;

    if (!okMatch) errors++;
    section2.push({ status: okMatch ? "OK" : "ERR", name: cross.name, detail });

    // Make this value available for subsequent cross-repo checks
    if (crossValue !== null) actualValues[cross.name] = crossValue;
  }

  return { passed: errors === 0, errors, section1, section2 };
}
