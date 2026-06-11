// ============================================================================
// engine.ts -- Core verification engine (thin orchestrator)
//
// Delegates to:
//   resolve-check.ts   -- single check resolution
//   verify-section1.ts -- README vs Code comparison
//   verify-section2.ts -- cross-repo consistency
//
// Custom source types: register via registerSource() from resolvers.ts.
// ============================================================================

import { readFileSync } from "fs";
import { join } from "path";
import type { VerifyConfig, VerifyResult } from "./types.js";
import { registerSource } from "./resolvers.js";
import { resolveCheck } from "./resolve-check.js";
import { verifySection1 } from "./verify-section1.js";
import { verifySection2 } from "./verify-section2.js";

// Re-export so existing consumers (cli.ts, init.ts) work unchanged
export type { CheckConfig, CrossRepoConfig, VerifyConfig, VerifyResult, LineResult, SourceResolver } from "./types.js";
export { registerSource } from "./resolvers.js";

/**
 * Run the full verification engine.
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

  // Section 1: README vs Code
  const { results: section1, errors: s1Errors } = verifySection1(config.checks, root, readmeContent);

  // Build actual-values lookup for cross-repo references
  const actualValues: Record<string, number> = {};
  for (const check of config.checks) {
    const { actual } = resolveCheck(check, root, readmeContent);
    if (actual !== null) actualValues[check.name] = actual;
  }

  // Section 2: Cross-repo consistency
  const { results: section2, errors: s2Errors } = verifySection2(
    config.crossRepo ?? [],
    root,
    readmeContent,
    actualValues,
    ci
  );

  return { passed: s1Errors + s2Errors === 0, errors: s1Errors + s2Errors, section1, section2 };
}
