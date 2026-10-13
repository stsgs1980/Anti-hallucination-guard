// ============================================================================
// verify-section3.ts -- Version synchronization verification
//
// Ensures that a single source-of-truth version (e.g. from manifest.json
// or package.json) matches the version stated in other documentation files.
//
// This prevents the common problem where README, ARCHITECTURE, and other
// docs each carry their own version that diverges over time.
// ============================================================================

import { existsSync } from "fs";
import { join } from "path";
import type { VersionSyncConfig, LineResult } from "./types.js";
import { safeRead } from "./resolvers.js";

/**
 * Section 3: Version synchronization.
 * Extracts version from source of truth, compares with targets.
 * Returns an array of LineResult entries and the number of errors found.
 */
export function verifySection3(
  versionSync: VersionSyncConfig | undefined,
  root: string
): { results: LineResult[]; errors: number } {
  const results: LineResult[] = [];
  let errors = 0;

  if (!versionSync) {
    return { results, errors };
  }

  // --- Step 1: Extract version from source of truth ---
  const sourcePath = versionSync.source.startsWith("file:")
    ? join(root, versionSync.source.slice(5))
    : join(root, versionSync.source);

  const sourceContent = safeRead(sourcePath);
  if (!sourceContent) {
    results.push({
      status: "ERR",
      name: "Version source",
      detail: `Cannot read source: ${versionSync.source}`
    });
    errors++;
    return { results, errors };
  }

  const sourceMatch = sourceContent.match(new RegExp(versionSync.extractPattern));
  if (!sourceMatch || !sourceMatch[1]) {
    results.push({
      status: "ERR",
      name: "Version source",
      detail: `Cannot extract version from ${versionSync.source} using pattern: ${versionSync.extractPattern}`
    });
    errors++;
    return { results, errors };
  }

  const sourceVersion = sourceMatch[1];
  results.push({
    status: "info",
    name: "Version source",
    detail: `${versionSync.source} -> v${sourceVersion}`
  });

  // --- Step 2: Check each target ---
  for (const target of versionSync.targets) {
    const targetPath = join(root, target.file);

    // A target listed in the config is expected to exist and to carry the
    // version. Reporting it as "skip" let a deleted or renamed version file
    // pass verification silently; only "optional": true means skip.
    if (!existsSync(targetPath)) {
      results.push({
        status: target.optional ? "skip" : "ERR",
        name: target.file,
        detail: target.optional
          ? "file not found (optional target)"
          : "file not found -- listed as a version target but missing"
      });
      if (!target.optional) errors++;
      continue;
    }

    const targetContent = safeRead(targetPath);
    if (!targetContent) {
      results.push({
        status: target.optional ? "skip" : "ERR",
        name: target.file,
        detail: target.optional
          ? "cannot read file (optional target)"
          : "cannot read file"
      });
      if (!target.optional) errors++;
      continue;
    }

    const targetMatch = targetContent.match(new RegExp(target.pattern));
    if (!targetMatch || !targetMatch[1]) {
      results.push({
        status: target.optional ? "skip" : "ERR",
        name: target.file,
        detail: target.optional
          ? `pattern not found (optional target): ${target.pattern}`
          : `pattern not found, version cannot be confirmed: ${target.pattern}`
      });
      if (!target.optional) errors++;
      continue;
    }

    const targetVersion = targetMatch[1];
    const ok = targetVersion === sourceVersion;

    if (ok) {
      results.push({
        status: "OK",
        name: target.file,
        detail: `v${targetVersion} MATCH source`
      });
    } else {
      results.push({
        status: "ERR",
        name: target.file,
        detail: `v${targetVersion} MISMATCH -> source=v${sourceVersion}, fix: ${targetVersion} -> ${sourceVersion}`
      });
      errors++;
    }
  }

  return { results, errors };
}
