// ============================================================================
// discover-project.ts -- Project structure detection for auto-config
//
// Detects project type, source directories, and code extensions.
// Used by auto-config.ts to generate VerifyConfig from project structure.
// ============================================================================

import { existsSync, readdirSync } from "fs";
import { join, extname } from "path";

// -- Project type detection ---------------------------------------------------

export type ProjectType = "typescript" | "javascript" | "python" | "go" | "rust" | "unknown";

const PROJECT_TYPE_MARKERS: Record<string, string[]> = {
  typescript: ["tsconfig.json"],
  javascript: ["package.json"],
  python: ["pyproject.toml", "setup.py", "requirements.txt", "Pipfile"],
  go: ["go.mod", "go.sum"],
  rust: ["Cargo.toml", "Cargo.lock"],
};

export const EXTENSIONS_BY_TYPE: Record<string, string[]> = {
  typescript: [".ts", ".tsx"],
  javascript: [".js", ".jsx", ".mjs"],
  python: [".py"],
  go: [".go"],
  rust: [".rs"],
  unknown: [".ts", ".js", ".py", ".go", ".rs"],
};

/**
 * Detect project type by checking for marker files.
 * Priority: TS > JS > Python > Go > Rust > unknown.
 * TS is first because TS projects also have package.json.
 */
export function detectProjectType(root: string): ProjectType {
  for (const [type, markers] of Object.entries(PROJECT_TYPE_MARKERS)) {
    for (const marker of markers) {
      if (existsSync(join(root, marker))) {
        return type as ProjectType;
      }
    }
  }
  return "unknown";
}

// -- Source directory detection ------------------------------------------------

const STANDARD_SOURCE_DIRS = ["src", "lib", "pkg", "cmd", "internal", "app", "tools"];

const SKIP_DIR_NAMES = new Set([
  "node_modules", "dist", "build", "out", "coverage",
  "anti-hallucination-guard",
]);

/**
 * Find source directories in the project root.
 * Checks both standard names and directories that contain code files.
 */
export function findSourceDirectories(root: string): string[] {
  const found: string[] = [];
  try {
    const entries = readdirSync(root, { withFileTypes: true });
    for (const entry of entries) {
      if (!entry.isDirectory()) continue;
      if (entry.name.startsWith(".") || SKIP_DIR_NAMES.has(entry.name)) continue;

      const hasCode = hasCodeFiles(join(root, entry.name));
      if (hasCode || STANDARD_SOURCE_DIRS.includes(entry.name)) {
        found.push(entry.name);
      }
    }
  } catch { /* can't read root */ }
  return found;
}

// -- File system helpers -------------------------------------------------------

const CODE_EXTENSIONS = new Set([".ts", ".tsx", ".js", ".jsx", ".py", ".go", ".rs", ".sh"]);

/** Check if a directory contains code files (recursive, max depth 1) */
function hasCodeFiles(dir: string, depth: number = 0): boolean {
  try {
    const entries = readdirSync(dir, { withFileTypes: true });
    for (const entry of entries) {
      if (entry.isFile() && CODE_EXTENSIONS.has(extname(entry.name))) {
        return true;
      }
      if (entry.isDirectory() && depth < 1 &&
          !entry.name.startsWith(".") && entry.name !== "node_modules") {
        if (hasCodeFiles(join(dir, entry.name), depth + 1)) return true;
      }
    }
  } catch { /* skip */ }
  return false;
}

/** Detect which code extensions actually exist in a directory (recursive, max depth 3) */
export function detectExtensionsInDir(dir: string, root: string): string[] {
  const found = new Set<string>();
  const codeExts = [".ts", ".tsx", ".js", ".jsx", ".mjs", ".py", ".go", ".rs", ".sh"];
  const skipDirs = new Set([
    "node_modules", ".git", "dist", ".next", ".turbo",
    "build", "out", "anti-hallucination-guard",
  ]);

  function walk(d: string, depth: number) {
    if (depth > 3) return;
    const fullDir = join(root, d);
    try {
      const entries = readdirSync(fullDir, { withFileTypes: true });
      for (const entry of entries) {
        if (entry.name.startsWith(".")) continue;
        const relPath = d ? `${d}/${entry.name}` : entry.name;
        if (entry.isDirectory()) {
          if (!skipDirs.has(entry.name)) walk(relPath, depth + 1);
        } else if (entry.isFile()) {
          const ext = extname(entry.name);
          if (codeExts.includes(ext)) found.add(ext);
        }
      }
    } catch { /* skip */ }
  }

  walk(dir, 0);
  return Array.from(found).sort();
}
