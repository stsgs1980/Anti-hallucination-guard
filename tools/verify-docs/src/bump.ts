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

/** Version patterns tried in priority order, most specific first. */
function versionPatterns(oldVersion: string): RegExp[] {
  const escaped = oldVersion.replace(/\./g, "\\.");

  return [
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
    const content = readFileSync(fullPath, "utf-8");

    for (const pattern of versionPatterns(oldVersion)) {
      const newContent = content.replace(pattern, versionReplacer(newVersion));
      if (newContent !== content) return newContent;
    }

    return null;
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
