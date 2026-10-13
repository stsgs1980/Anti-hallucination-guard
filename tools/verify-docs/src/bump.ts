// ============================================================================
// bump.ts -- Version bump across all discovered files
//
// Uses discover-versions to find all files containing version numbers,
// then updates them all to the specified version.
// Optionally adds a CHANGELOG entry if a CHANGELOG file exists.
//
// NOT atomic across files: a filesystem cannot roll back several writes.
// What this module does guarantee is ordering -- every replacement is
// computed first, and only after all of them succeed are any files written.
// A write that fails halfway is reported in BumpResult.failed, never hidden.
// ============================================================================

import { readFileSync, writeFileSync } from "fs";
import { join } from "path";
import { discoverVersions } from "./discover-versions.js";
import { discoverChangelog, changelogHasEntry } from "./discover-changelog.js";
import { addChangelogEntry } from "./bump-changelog.js";

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

/** Version patterns tried in priority order, most specific first. */
function versionPatterns(oldVersion: string): RegExp[] {
  const escaped = oldVersion.replace(/\./g, "\\.");

  // Every pattern is global: a single file can carry the version several
  // times (badge, table row, example command), and leaving one of them behind
  // is exactly the version drift this tool exists to prevent.
  return [
    // "version": "OLD" -> "version": "NEW" (JSON)
    new RegExp(`("version"\\s*:\\s*")${escaped}(")`, "g"),
    // version/VERSION = "OLD" -> version/VERSION = "NEW" (JS/TS)
    new RegExp(`(version\\s*[=:]\\s*["'])${escaped}(["'])`, "gi"),
    // vOLD | -> vNEW | (markdown table)
    new RegExp(`(v)${escaped}(\\s*\\|)`, "g"),
    // version: OLD -> version: NEW
    new RegExp(`(version[:\\s]+)${escaped}`, "gi"),
    // Generic: just replace the version string
    new RegExp(escaped, "g"),
  ];
}

/**
 * Build a String.replace() callback that swaps the old version for the new one.
 *
 * A replace callback is invoked as (match, ...captures, offset, string):
 * the LAST two arguments are the match offset and the whole source string,
 * never capture groups. Treating them as captures is what appended the match
 * offset to the new version -- "version: 9.9.9" bumped to 2.0.0 became
 * "version: 2.0.06" (offset 6), and the group-less generic pattern pasted the
 * entire file content back into itself.
 */
function versionReplacer(newVersion: string) {
  return (...cbArgs: unknown[]): string => {
    const captures = cbArgs
      .slice(1, cbArgs.length - 2)
      .map((c) => (typeof c === "string" ? c : ""));

    if (captures.length === 0) return newVersion;
    return captures[0] + newVersion + captures.slice(1).join("");
  };
}

/**
 * Compute the new content of a file with the version replaced.
 * Returns null when the old version cannot be found or the file is unreadable.
 * Does not touch the filesystem beyond reading.
 */
export function computeVersionReplacement(
  filePath: string,
  root: string,
  oldVersion: string,
  newVersion: string
): string | null {
  const fullPath = join(root, filePath);
  try {
    let content = readFileSync(fullPath, "utf-8");
    let changed = false;

    // All patterns are applied, not just the first one that matches: they
    // cover different notations of the same version inside one file.
    for (const pattern of versionPatterns(oldVersion)) {
      const next = content.replace(pattern, versionReplacer(newVersion));
      if (next !== content) {
        content = next;
        changed = true;
      }
    }

    return changed ? content : null;
  } catch {
    return null;
  }
}

/**
 * Replace the version inside one file and write the result.
 * Returns true when the file was rewritten.
 */
export function replaceVersionInFile(
  filePath: string,
  root: string,
  oldVersion: string,
  newVersion: string
): boolean {
  const newContent = computeVersionReplacement(
    filePath,
    root,
    oldVersion,
    newVersion
  );
  if (newContent === null) return false;

  try {
    writeFileSync(join(root, filePath), newContent, "utf-8");
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

  // -- Phase 1: compute every replacement before writing anything -----------
  // If a version cannot be located in a discovered file, it is reported as a
  // failure instead of being silently skipped.
  const planned: { file: string; content: string }[] = [];

  for (const dv of versionInfo.files) {
    if (dv.version === null) continue;
    if (dv.version === newVersion) {
      // Already at target version
      continue;
    }

    const content = computeVersionReplacement(
      dv.file,
      root,
      dv.version,
      newVersion
    );
    if (content === null) {
      failedFiles.push(dv.file);
    } else {
      planned.push({ file: dv.file, content });
    }
  }

  // -- Phase 2: write -------------------------------------------------------
  // Dry run stops here: nothing has been written during phase 1.
  if (dryRun) {
    for (const p of planned) updatedFiles.push(p.file);
  } else {
    for (const p of planned) {
      try {
        writeFileSync(join(root, p.file), p.content, "utf-8");
        updatedFiles.push(p.file);
      } catch {
        failedFiles.push(p.file);
      }
    }
  }

  // Update CHANGELOG if found. Never add an entry that is already there:
  // re-running the same bump used to stack another empty section on top.
  let changelogUpdated = false;
  const changelogInfo = discoverChangelog(root, newVersion);
  if (changelogInfo.files.length > 0) {
    const changelogFile = changelogInfo.files[0];
    const alreadyDocumented = changelogHasEntry(root, changelogFile, newVersion);
    if (dryRun) {
      changelogUpdated = !alreadyDocumented; // would update
    } else if (!alreadyDocumented) {
      changelogUpdated = addChangelogEntry(root, newVersion, changelogFile);
    }
  }

  return {
    updated: updatedFiles.length,
    files: updatedFiles,
    failed: failedFiles,
    changelogUpdated,
    dryRun,
  };
}
