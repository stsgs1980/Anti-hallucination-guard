// ============================================================================
// discover-changelog.ts -- Auto-discover and verify CHANGELOG freshness
//
// Finds CHANGELOG files in the project and checks whether the latest
// entry matches the current project version. Reports stale or missing
// CHANGELOG entries.
// ============================================================================

import { existsSync, readFileSync } from "fs";
import { join } from "path";
import type { LineResult } from "./types.js";

// -- Result types ------------------------------------------------------------

export interface ChangelogDiscoverResult {
  /** CHANGELOG files found */
  files: string[];
  /** Number of issues found */
  issues: number;
  /** LineResult entries for reporting */
  results: LineResult[];
}

// -- CHANGELOG file names to search ------------------------------------------

const CHANGELOG_NAMES = [
  "CHANGELOG.md",
  "CHANGES.md",
  "HISTORY.md",
  "CHANGELOG",
  "CHANGES",
];

// -- Helpers -----------------------------------------------------------------

function findChangelogs(root: string): string[] {
  const found: string[] = [];
  for (const name of CHANGELOG_NAMES) {
    if (existsSync(join(root, name))) {
      found.push(name);
    }
    // Also check common subdirectories
    if (existsSync(join(root, "docs", name))) {
      found.push(`docs/${name}`);
    }
  }
  return found;
}

/**
 * Extract the latest version mentioned in a CHANGELOG.
 * Looks for common patterns: "## [X.Y.Z]", "## X.Y.Z", "# X.Y.Z",
 * "## vX.Y.Z", "- v1.2.3", etc.
 */
function extractLatestVersion(content: string): string | null {
  const lines = content.split("\n");
  for (const line of lines) {
    // Match: ## [1.2.3] or ## 1.2.3 or ## v1.2.3 or # 1.2.3
    const headingMatch = line.match(
      /^#{1,3}\s+\[?v?(\d+\.\d+(?:\.\d+)*)\]?/i
    );
    if (headingMatch) return headingMatch[1];

    // Match: - v1.2.3 or * v1.2.3 (less common but valid)
    const listMatch = line.match(/^[\-\*]\s+v?(\d+\.\d+(?:\.\d+)*)/);
    if (listMatch) return listMatch[1];
  }
  return null;
}

/**
 * Check if the CHANGELOG has an entry for the given version.
 */
function hasEntryForVersion(content: string, version: string): boolean {
  // Escape dots for regex
  const escaped = version.replace(/\./g, "\\.");
  const pattern = new RegExp(
    `^#{1,3}\\s+\\[?v?${escaped}\\]?|^[\-\*]\\s+v?${escaped}`,
    "m"
  );
  return pattern.test(content);
}

// -- Main discover function --------------------------------------------------

export function discoverChangelog(
  root: string,
  currentVersion?: string | null
): ChangelogDiscoverResult {
  const results: LineResult[] = [];
  let issues = 0;

  const changelogs = findChangelogs(root);

  if (changelogs.length === 0) {
    results.push({
      status: "warn",
      name: "CHANGELOG",
      detail: "No CHANGELOG file found in project root",
    });
    return { files: [], issues: 0, results };
  }

  for (const changelog of changelogs) {
    const content = readFileSync(join(root, changelog), "utf-8");
    const latestInChangelog = extractLatestVersion(content);

    if (!latestInChangelog) {
      results.push({
        status: "warn",
        name: changelog,
        detail: "Cannot extract latest version from CHANGELOG (no version headings found)",
      });
      continue;
    }

    results.push({
      status: "info",
      name: changelog,
      detail: `Latest entry: v${latestInChangelog}`,
    });

    // If we know the current version, check freshness
    if (currentVersion) {
      const hasEntry = hasEntryForVersion(content, currentVersion);
      if (hasEntry) {
        results.push({
          status: "OK",
          name: `${changelog} freshness`,
          detail: `Entry for v${currentVersion} exists`,
        });
      } else {
        issues++;
        results.push({
          status: "ERR",
          name: `${changelog} stale`,
          detail: `No entry for current version v${currentVersion} (latest: v${latestInChangelog})`,
        });
      }
    }
  }

  return { files: changelogs, issues, results };
}
