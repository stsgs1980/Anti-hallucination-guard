// ============================================================================
// bump.ts -- Atomic version bump across all discovered files
//
// Uses discover-versions to find all files containing version numbers,
// then updates them all atomically to the specified version.
// Optionally adds a CHANGELOG entry if a CHANGELOG file exists.
// ============================================================================

import { readFileSync, writeFileSync, existsSync } from "fs";
import { join } from "path";
import { discoverVersions } from "./discover-versions.js";
import { discoverChangelog } from "./discover-changelog.js";

// -- Result types ------------------------------------------------------------

export interface BumpResult {
  /** Number of files updated */
  updated: number;
  /** Files that were updated */
  files: string[];
  /** Files that could not be updated */
  failed: string[];
  /** Whether CHANGELOG was updated */
  changelogUpdated: boolean;
  /** Dry run results (if --dry-run) */
  dryRun: boolean;
}

// -- Helpers -----------------------------------------------------------------

function replaceVersionInFile(
  filePath: string,
  root: string,
  oldVersion: string,
  newVersion: string
): boolean {
  const fullPath = join(root, filePath);
  try {
    let content = readFileSync(fullPath, "utf-8");
    const escaped = oldVersion.replace(/\./g, "\\.");

    // Try common patterns and replace
    const patterns = [
      // "version": "OLD" -> "version": "NEW" (JSON)
      new RegExp(`("version"\\s*:\\s*")${escaped}(")`),
      // version/VERSION = "OLD" -> version/VERSION = "NEW" (JS/TS)
      new RegExp(`(version\\s*[=:]\\s*["'])${escaped}(["'])`, "i"),
      // vOLD | -> vNEW | (markdown table)
      new RegExp(`(v)${escaped}(\\s*\\|)`),
      // version: OLD -> version: NEW
      new RegExp(`(version[:\\s]+)${escaped}`, "i"),
      // Generic: just replace the version string
      new RegExp(escaped, "g"),
    ];

    for (const pattern of patterns) {
      const newContent = content.replace(pattern, (match, ...args) => {
        // If there are capture groups, reconstruct with new version
        if (args.length >= 2) {
          return args[0] + newVersion + args[1];
        }
        return newVersion;
      });

      if (newContent !== content) {
        writeFileSync(fullPath, newContent, "utf-8");
        return true;
      }
    }

    return false;
  } catch {
    return false;
  }
}

function addChangelogEntry(
  root: string,
  version: string,
  changelogFile: string
): boolean {
  const fullPath = join(root, changelogFile);
  try {
    const content = readFileSync(fullPath, "utf-8");
    const date = new Date().toISOString().split("T")[0];

    // Find the first ## heading (version entry level) and insert before it.
    // This preserves the # Title heading (e.g. "# Changelog") at the top.
    const h2Match = content.match(/^##\s/m);
    if (h2Match && h2Match.index !== undefined) {
      const entry = `## [${version}] - ${date}\n\n- \n\n`;
      const newContent =
        content.slice(0, h2Match.index) +
        entry +
        content.slice(h2Match.index);
      writeFileSync(fullPath, newContent, "utf-8");
      return true;
    }

    // No ## heading found -- insert after the first # heading (title)
    const h1Match = content.match(/^#\s.*\n/m);
    if (h1Match && h1Match.index !== undefined) {
      const insertAfter = h1Match.index + h1Match[0].length;
      const entry = `## [${version}] - ${date}\n\n- \n\n`;
      const newContent =
        content.slice(0, insertAfter) +
        entry +
        content.slice(insertAfter);
      writeFileSync(fullPath, newContent, "utf-8");
      return true;
    }

    // No heading at all -- prepend
    const entry = `## [${version}] - ${date}\n\n- \n\n`;
    writeFileSync(fullPath, entry + content, "utf-8");
    return true;
  } catch {
    return false;
  }
}

// -- Main bump function ------------------------------------------------------

export function bumpVersion(
  root: string,
  newVersion: string,
  options?: { dryRun?: boolean }
): BumpResult {
  const dryRun = options?.dryRun ?? false;
  const versionInfo = discoverVersions(root);

  const updatedFiles: string[] = [];
  const failedFiles: string[] = [];

  for (const dv of versionInfo.files) {
    if (dv.version === null) continue;
    if (dv.version === newVersion) {
      // Already at target version
      continue;
    }

    if (dryRun) {
      updatedFiles.push(dv.file);
      continue;
    }

    const success = replaceVersionInFile(dv.file, root, dv.version, newVersion);
    if (success) {
      updatedFiles.push(dv.file);
    } else {
      failedFiles.push(dv.file);
    }
  }

  // Update CHANGELOG if found
  let changelogUpdated = false;
  const changelogInfo = discoverChangelog(root, newVersion);
  if (changelogInfo.files.length > 0 && !dryRun) {
    changelogUpdated = addChangelogEntry(
      root,
      newVersion,
      changelogInfo.files[0]
    );
  } else if (changelogInfo.files.length > 0 && dryRun) {
    changelogUpdated = true; // would update
  }

  return {
    updated: updatedFiles.length,
    files: updatedFiles,
    failed: failedFiles,
    changelogUpdated,
    dryRun,
  };
}
