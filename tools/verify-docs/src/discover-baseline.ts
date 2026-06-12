// ============================================================================
// discover-baseline.ts -- Create and check file baselines
//
// A baseline records which files exist in the project at the time of AHG
// installation. On subsequent runs, deleted files are detected by comparing
// the current file list against the baseline.
//
// This prevents the silent deletion problem: "CHANGELOG.md was lost" but
// nobody noticed because there was nothing to check against.
// ============================================================================

import { existsSync, readFileSync, writeFileSync, readdirSync } from "fs";
import { join } from "path";
import type { LineResult } from "./types.js";

// -- Result types ------------------------------------------------------------

export interface BaselineData {
  version: number;
  created: string;
  files: string[];
}

export interface BaselineCheckResult {
  /** Files that exist in baseline but are now missing */
  deleted: string[];
  /** Files that exist now but were not in baseline */
  added: string[];
  /** Number of issues found */
  issues: number;
  /** LineResult entries for reporting */
  results: LineResult[];
}

// -- Configuration -----------------------------------------------------------

const BASELINE_FILE = ".ahg-baseline.json";
const SKIP_DIRS = new Set([
  "node_modules", ".next", ".git", "dist", ".turbo", "build",
  "out", "coverage", ".cache", "vendor", "__pycache__",
  "anti-hallucination-guard",  // AHG module itself (not part of host project)
]);

// -- Helpers -----------------------------------------------------------------

function walkFiles(dir: string, root: string, results: string[]): void {
  const fullDir = join(root, dir);
  try {
    const entries = readdirSync(fullDir, { withFileTypes: true });
    for (const entry of entries) {
      if (SKIP_DIRS.has(entry.name)) continue;
      if (entry.name.startsWith(".")) continue; // skip hidden files/dirs
      const relPath = dir ? `${dir}/${entry.name}` : entry.name;
      if (entry.isDirectory()) {
        walkFiles(relPath, root, results);
      } else if (entry.isFile()) {
        results.push(relPath);
      }
    }
  } catch { /* directory doesn't exist */ }
}

// -- Create baseline ---------------------------------------------------------

export function createBaseline(root: string): LineResult[] {
  const results: LineResult[] = [];
  const files: string[] = [];
  walkFiles("", root, files);
  files.sort();

  const baseline: BaselineData = {
    version: 1,
    created: new Date().toISOString(),
    files,
  };

  const baselinePath = join(root, BASELINE_FILE);
  writeFileSync(baselinePath, JSON.stringify(baseline, null, 2) + "\n", "utf-8");

  results.push({
    status: "OK",
    name: "Baseline created",
    detail: `${BASELINE_FILE} with ${files.length} files`,
  });

  return results;
}

// -- Check against baseline --------------------------------------------------

export function checkBaseline(root: string): BaselineCheckResult {
  const results: LineResult[] = [];
  const baselinePath = join(root, BASELINE_FILE);

  if (!existsSync(baselinePath)) {
    results.push({
      status: "warn",
      name: "Baseline",
      detail: `${BASELINE_FILE} not found -- run: verify-docs --baseline to create`,
    });
    return { deleted: [], added: [], issues: 0, results };
  }

  // Read baseline
  let baseline: BaselineData;
  try {
    const raw = readFileSync(baselinePath, "utf-8");
    baseline = JSON.parse(raw);
  } catch {
    results.push({
      status: "ERR",
      name: "Baseline",
      detail: `${BASELINE_FILE} is not valid JSON`,
    });
    return { deleted: [], added: [], issues: 1, results };
  }

  const baselineFiles = new Set(baseline.files);

  // Get current files
  const currentFiles: string[] = [];
  walkFiles("", root, currentFiles);
  const currentSet = new Set(currentFiles);

  // Find deleted (in baseline but not in current)
  const deleted: string[] = [];
  for (const file of baseline.files) {
    if (!currentSet.has(file) && !file.startsWith(".")) {
      deleted.push(file);
    }
  }

  // Find added (in current but not in baseline) -- info only
  const added: string[] = [];
  for (const file of currentFiles) {
    if (!baselineFiles.has(file)) {
      added.push(file);
    }
  }

  // Report
  if (deleted.length === 0) {
    results.push({
      status: "OK",
      name: "Baseline check",
      detail: `All ${baseline.files.length} baseline files present`,
    });
  } else {
    for (const file of deleted) {
      results.push({
        status: "ERR",
        name: "File deleted",
        detail: `${file} existed at baseline (${baseline.created}) but is now missing`,
      });
    }
  }

  if (added.length > 0) {
    results.push({
      status: "info",
      name: "New files",
      detail: `${added.length} files added since baseline (run --baseline to update)`,
    });
  }

  return { deleted, added, issues: deleted.length, results };
}
