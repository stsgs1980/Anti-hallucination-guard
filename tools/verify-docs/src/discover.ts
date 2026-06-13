// ============================================================================
// discover.ts -- Auto-discover orchestrator
//
// Runs all discover modules (versions, changelog, coverage, baseline)
// and aggregates results into a unified report. This is the entry point
// for "verify-docs --discover" and for the fallback when no config exists.
// ============================================================================

import type { LineResult } from "./types.js";
import { discoverVersions } from "./discover-versions.js";
import { discoverChangelog } from "./discover-changelog.js";
import { discoverCoverage } from "./discover-coverage.js";
import { checkBaseline, createBaseline } from "./discover-baseline.js";

// -- Result types ------------------------------------------------------------

export interface DiscoverResult {
  /** Total errors found */
  errors: number;
  /** Total warnings found */
  warnings: number;
  /** All result lines, grouped by section */
  sections: {
    name: string;
    results: LineResult[];
  }[];
  /** Version info (for use by bump command) */
  versionInfo: ReturnType<typeof discoverVersions>;
}

// -- Main discover function --------------------------------------------------

export function discover(
  root: string,
  options?: { createBaseline?: boolean }
): DiscoverResult {
  const sections: DiscoverResult["sections"] = [];
  let totalErrors = 0;
  let totalWarnings = 0;

  // 1. Version discovery
  const versionInfo = discoverVersions(root);
  sections.push({
    name: "Version Files",
    results: versionInfo.results,
  });
  totalErrors += versionInfo.mismatches;

  // Get current version for changelog check
  const currentVersion = versionInfo.sourceOfTruth?.version || null;

  // 2. CHANGELOG discovery
  const changelogInfo = discoverChangelog(root, currentVersion);
  sections.push({
    name: "CHANGELOG",
    results: changelogInfo.results,
  });
  totalErrors += changelogInfo.issues;

  // 3. Documentation coverage
  const coverageInfo = discoverCoverage(root);
  sections.push({
    name: "Doc Coverage",
    results: coverageInfo.results,
  });
  // Coverage errors count as warnings in discover mode (not blocking)
  totalWarnings += coverageInfo.uncovered;

  // 4. Baseline check
  if (options?.createBaseline) {
    const baselineResults = createBaseline(root);
    sections.push({
      name: "Baseline",
      results: baselineResults,
    });
  } else {
    const baselineInfo = checkBaseline(root);
    sections.push({
      name: "Baseline",
      results: baselineInfo.results,
    });
    totalErrors += baselineInfo.issues;
  }

  // 5. Summary
  const summaryResults: LineResult[] = [];
  if (totalErrors === 0 && totalWarnings === 0) {
    summaryResults.push({
      status: "OK",
      name: "Discover summary",
      detail: "No issues found. All discovered checks passed.",
    });
  } else {
    const parts: string[] = [];
    if (totalErrors > 0) parts.push(`${totalErrors} error(s)`);
    if (totalWarnings > 0) parts.push(`${totalWarnings} warning(s)`);
    summaryResults.push({
      status: totalErrors > 0 ? "ERR" : "warn",
      name: "Discover summary",
      detail: parts.join(", "),
    });
  }

  // Add coverage info for discover report
  const coveredSections = sections.filter(
    (s) => s.results.length > 0 && s.results.some((r) => r.status !== "info")
  );
  if (coveredSections.length < sections.length) {
    const uncoveredNames = sections
      .filter((s) => !coveredSections.includes(s))
      .map((s) => s.name);
    summaryResults.push({
      status: "info",
      name: "Uncovered zones",
      detail: `Only info found (no issues): ${uncoveredNames.join(", ")}`,
    });
  }

  sections.push({ name: "Summary", results: summaryResults });

  return {
    errors: totalErrors,
    warnings: totalWarnings,
    sections,
    versionInfo,
  };
}
