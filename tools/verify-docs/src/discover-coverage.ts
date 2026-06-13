// ============================================================================
// discover-coverage.ts -- Auto-discover documentation coverage gaps
//
// Scans source directories for code files, then checks whether each file
// is mentioned in the project's documentation. Reports coverage percentage
// and lists uncovered files.
//
// This replaces the need for manual docCoverage configuration -- AHG finds
// source directories and documentation files automatically.
// ============================================================================

import { existsSync, readdirSync, readFileSync, statSync as fsStatSync } from "fs";
import { join, extname } from "path";
import type { LineResult } from "./types.js";

// -- Result types ------------------------------------------------------------

export interface CoverageDiscoverResult {
  /** Source directories found */
  sourceDirs: string[];
  /** Documentation files found */
  docFiles: string[];
  /** Number of uncovered files */
  uncovered: number;
  /** LineResult entries for reporting */
  results: LineResult[];
}

// -- Configuration -----------------------------------------------------------

const SOURCE_DIRS = ["src", "lib", "pkg", "cmd", "internal", "app"];
const DOC_FILES = ["README.md", "ARCHITECTURE.md", "docs/"];
const SKIP_DIRS = new Set([
  "node_modules", ".next", ".git", "dist", ".turbo", "build",
  "out", "coverage", ".cache", "__pycache__", "__tests__",
  "test", "tests", "spec", ".test", ".spec",
  "anti-hallucination-guard",  // AHG module itself (not part of host project)
]);

const CODE_EXTENSIONS = new Set([
  ".ts", ".tsx", ".js", ".jsx", ".py", ".go", ".rs", ".rb",
  ".java", ".kt", ".swift", ".c", ".cpp", ".h", ".sh",
]);

// -- Helpers -----------------------------------------------------------------

function findSourceDirs(root: string): string[] {
  const found: string[] = [];
  for (const dir of SOURCE_DIRS) {
    const full = join(root, dir);
    if (existsSync(full)) {
      try {
        if (fsStatSync(full).isDirectory()) found.push(dir);
      } catch { /* not a directory */ }
    }
  }
  return found;
}

function findDocFiles(root: string): string[] {
  const found: string[] = [];
  for (const doc of DOC_FILES) {
    if (existsSync(join(root, doc))) {
      found.push(doc);
    }
  }
  return found;
}

function collectCodeFiles(
  dir: string,
  root: string,
  results: string[]
): void {
  const fullDir = join(root, dir);
  try {
    const entries = readdirSync(fullDir, { withFileTypes: true });
    for (const entry of entries) {
      if (SKIP_DIRS.has(entry.name)) continue;
      const relPath = dir ? `${dir}/${entry.name}` : entry.name;
      if (entry.isDirectory()) {
        collectCodeFiles(relPath, root, results);
      } else if (entry.isFile() && CODE_EXTENSIONS.has(extname(entry.name))) {
        results.push(relPath);
      }
    }
  } catch { /* skip */ }
}

function isMentionedInDoc(basename: string, basenameNoExt: string, docContent: string): boolean {
  return docContent.includes(basename) || docContent.includes(basenameNoExt);
}

// -- Main discover function --------------------------------------------------

export function discoverCoverage(root: string): CoverageDiscoverResult {
  const results: LineResult[] = [];
  let uncovered = 0;

  const sourceDirs = findSourceDirs(root);
  const docFiles = findDocFiles(root);

  if (sourceDirs.length === 0) {
    results.push({
      status: "info",
      name: "Doc coverage",
      detail: "No standard source directories found (src/, lib/, pkg/, etc.)",
    });
    return { sourceDirs: [], docFiles, uncovered: 0, results };
  }

  results.push({
    status: "info",
    name: "Source directories",
    detail: `Found: ${sourceDirs.join(", ")}`,
  });

  if (docFiles.length === 0) {
    results.push({
      status: "warn",
      name: "Documentation",
      detail: "No documentation files found (README.md, ARCHITECTURE.md)",
    });
    return { sourceDirs, docFiles: [], uncovered: 0, results };
  }

  // Collect all code files from source directories
  const allCodeFiles: string[] = [];
  for (const dir of sourceDirs) {
    collectCodeFiles(dir, root, allCodeFiles);
  }

  if (allCodeFiles.length === 0) {
    results.push({
      status: "info",
      name: "Doc coverage",
      detail: "No code files found in source directories",
    });
    return { sourceDirs, docFiles, uncovered: 0, results };
  }

  // Read documentation content
  const docContents: Record<string, string> = {};
  for (const doc of docFiles) {
    try {
      docContents[doc] = readFileSync(join(root, doc), "utf-8");
    } catch { /* skip */ }
  }

  // Check each code file against documentation
  const mentioned: string[] = [];
  const notMentioned: string[] = [];

  for (const file of allCodeFiles) {
    const basename = file.split("/").pop() || "";
    const basenameNoExt = basename.replace(/\.[^.]+$/, "");

    let isMentioned = false;
    for (const content of Object.values(docContents)) {
      if (isMentionedInDoc(basename, basenameNoExt, content)) {
        isMentioned = true;
        break;
      }
    }

    if (isMentioned) {
      mentioned.push(basename);
    } else {
      notMentioned.push(basename);
    }
  }

  const coveragePct = Math.round((mentioned.length / allCodeFiles.length) * 100);
  const summary = `${mentioned.length}/${allCodeFiles.length} files mentioned (${coveragePct}%) in docs`;

  if (notMentioned.length === 0) {
    results.push({ status: "OK", name: "Doc coverage", detail: summary });
  } else if (coveragePct >= 80) {
    results.push({
      status: "warn",
      name: "Doc coverage",
      detail: `${summary} -- MISSING: ${notMentioned.slice(0, 10).join(", ")}${notMentioned.length > 10 ? ` (+${notMentioned.length - 10} more)` : ""}`,
    });
    uncovered = notMentioned.length;
  } else {
    results.push({
      status: "ERR",
      name: "Doc coverage",
      detail: `${summary} -- MISSING: ${notMentioned.slice(0, 10).join(", ")}${notMentioned.length > 10 ? ` (+${notMentioned.length - 10} more)` : ""}`,
    });
    uncovered = notMentioned.length;
  }

  return { sourceDirs, docFiles, uncovered, results };
}
