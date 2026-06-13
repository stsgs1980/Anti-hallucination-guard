// ============================================================================
// discover-versions.ts -- Auto-discover files containing version numbers
//
// Scans the project for files that contain version patterns (e.g. "version":
// "X.Y.Z" or v1.2.3), extracts the version from each, and reports which
// files are in sync and which have diverged.
//
// This replaces the need for manual versionSync configuration -- AHG finds
// version files automatically.
// ============================================================================

import { readFileSync, readdirSync, statSync } from "fs";
import { join, extname } from "path";
import type { LineResult } from "./types.js";

// -- Common version patterns per file type -----------------------------------

interface VersionPattern {
  /** Regex with one capturing group for the version string */
  pattern: RegExp;
  /** Human-readable description */
  description: string;
}

const PATTERNS: Record<string, VersionPattern[]> = {
  ".json": [
    { pattern: /"version"\s*:\s*"([\d.]+)"/, description: '"version": "X.Y.Z"' },
  ],
  ".md": [
    { pattern: /v(\d+\.\d+(?:\.\d+)*)\s*\|/, description: "vX.Y.Z |" },
    { pattern: /version[:\s]+(\d+\.\d+(?:\.\d+)*)/i, description: "version: X.Y.Z" },
  ],
  ".html": [
    { pattern: /version[:\s>]+(\d+\.\d+(?:\.\d+)*)/i, description: "version in HTML" },
    { pattern: /v(\d+\.\d+(?:\.\d+)*)/i, description: "vX.Y.Z in HTML" },
  ],
  ".js": [
    { pattern: /version\s*[=:]\s*["']([\d.]+)["']/i, description: 'version = "X.Y.Z"' },
  ],
  ".ts": [
    { pattern: /version\s*[=:]\s*["']([\d.]+)["']/i, description: 'version = "X.Y.Z"' },
  ],
  ".mjs": [
    { pattern: /version\s*[=:]\s*["']([\d.]+)["']/i, description: 'version = "X.Y.Z"' },
  ],
  ".yaml": [
    { pattern: /version:\s*["']?([\d.]+)["']?/, description: "version: X.Y.Z" },
  ],
  ".yml": [
    { pattern: /version:\s*["']?([\d.]+)["']?/, description: "version: X.Y.Z" },
  ],
  ".toml": [
    { pattern: /version\s*=\s*["']([\d.]+)["']/, description: 'version = "X.Y.Z"' },
  ],
};

// -- File names that are commonly the version source of truth ----------------

const SOURCE_OF_TRUTH_NAMES = [
  "package.json",
  "manifest.json",
  "Cargo.toml",
  "pyproject.toml",
  "setup.py",
  "version.go",
  "VERSION",
];

// -- Result types ------------------------------------------------------------

export interface DiscoveredVersion {
  /** Relative file path from project root */
  file: string;
  /** Extracted version string (null if not found) */
  version: string | null;
  /** Which pattern matched */
  pattern: string;
  /** Is this likely the source of truth? */
  isSourceOfTruth: boolean;
}

export interface VersionDiscoverResult {
  /** All files that contain version patterns */
  files: DiscoveredVersion[];
  /** The most likely source of truth (first match) */
  sourceOfTruth: DiscoveredVersion | null;
  /** Number of mismatches found */
  mismatches: number;
  /** LineResult entries for reporting */
  results: LineResult[];
}

// -- Helpers -----------------------------------------------------------------

const SKIP_DIRS = new Set([
  "node_modules", ".next", ".git", "dist", ".turbo", "build",
  "out", "coverage", ".cache", "vendor", "__pycache__",
  "anti-hallucination-guard",  // AHG module (submodule copy)
]);

function walkDir(dir: string, root: string, results: string[]): void {
  const fullDir = join(root, dir);
  try {
    const entries = readdirSync(fullDir, { withFileTypes: true });
    for (const entry of entries) {
      if (SKIP_DIRS.has(entry.name)) continue;
      const relPath = dir ? `${dir}/${entry.name}` : entry.name;
      // Skip installed verify-docs copy (not part of host project versions)
      if (relPath.startsWith("tools/verify-docs/")) continue;
      if (entry.isDirectory()) {
        walkDir(relPath, root, results);
      } else if (entry.isFile()) {
        results.push(relPath);
      }
    }
  } catch { /* directory doesn't exist */ }
}

function extractVersion(
  filePath: string,
  root: string
): { version: string | null; pattern: string } {
  const ext = extname(filePath);
  const patterns = PATTERNS[ext];
  if (!patterns) return { version: null, pattern: "no patterns for ext" };

  try {
    const content = readFileSync(join(root, filePath), "utf-8");
    // Only scan first 100 lines (version is usually near the top)
    const lines = content.split("\n").slice(0, 100).join("\n");
    for (const p of patterns) {
      const match = lines.match(p.pattern);
      if (match && match[1]) {
        return { version: match[1], pattern: p.description };
      }
    }
  } catch { /* can't read */ }

  return { version: null, pattern: "no match" };
}

// -- Main discover function --------------------------------------------------

export function discoverVersions(root: string): VersionDiscoverResult {
  const allFiles: string[] = [];
  walkDir("", root, allFiles);

  const discovered: DiscoveredVersion[] = [];

  for (const file of allFiles) {
    const ext = extname(file);
    if (!PATTERNS[ext]) continue;

    const { version, pattern } = extractVersion(file, root);
    if (version === null) continue;

    const basename = file.split("/").pop() || "";
    const isSourceOfTruth = SOURCE_OF_TRUTH_NAMES.includes(basename);

    discovered.push({ file, version, pattern, isSourceOfTruth });
  }

  // Determine source of truth: first match from SOURCE_OF_TRUTH_NAMES
  const sourceOfTruth = discovered.find((f) => f.isSourceOfTruth) || discovered[0] || null;

  // Compare all versions against source of truth
  const results: LineResult[] = [];
  let mismatches = 0;

  if (sourceOfTruth && sourceOfTruth.version) {
    results.push({
      status: "info",
      name: "Source of truth",
      detail: `${sourceOfTruth.file} -> v${sourceOfTruth.version} (${sourceOfTruth.pattern})`,
    });

    for (const dv of discovered) {
      if (dv === sourceOfTruth) continue;
      const ok = dv.version === sourceOfTruth.version;
      if (!ok) mismatches++;
      results.push({
        status: ok ? "OK" : "ERR",
        name: dv.file,
        detail: ok
          ? `v${dv.version} MATCH source`
          : `v${dv.version} MISMATCH -> source=v${sourceOfTruth.version}, fix: ${dv.version} -> ${sourceOfTruth.version}`,
      });
    }
  } else if (discovered.length > 0) {
    // No clear source of truth -- report what we found
    results.push({
      status: "warn",
      name: "Source of truth",
      detail: "No standard source-of-truth file found (package.json, manifest.json, etc.)",
    });
    for (const dv of discovered) {
      results.push({
        status: "info",
        name: dv.file,
        detail: `v${dv.version} (${dv.pattern})`,
      });
    }
  } else {
    results.push({
      status: "info",
      name: "Version discovery",
      detail: "No files with version patterns found in project",
    });
  }

  return { files: discovered, sourceOfTruth, mismatches, results };
}
