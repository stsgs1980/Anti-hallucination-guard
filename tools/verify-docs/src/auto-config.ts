// ============================================================================
// auto-config.ts -- Generate VerifyConfig from auto-discover results
//
// This module is the core of the "no config needed" philosophy:
//   - discover() scans the project and finds version files, source dirs, etc.
//   - generateAutoConfig() turns those discover results into a VerifyConfig
//   - The config can be used in-memory (verify fallback) or written to disk (--init)
//
// This means `ahg.sh verify` works WITHOUT verify-docs.json by auto-generating
// a config on the fly and running the full verification engine.
// ============================================================================

import { existsSync, readdirSync, statSync } from "fs";
import { join, extname } from "path";
import { discover } from "./discover.js";
import type { VerifyConfig, CheckConfig, VersionSyncConfig, DocCoverageConfig } from "./types.js";

// -- Project type detection ---------------------------------------------------

type ProjectType = "typescript" | "javascript" | "python" | "go" | "rust" | "unknown";

const PROJECT_TYPE_MARKERS: Record<string, string[]> = {
  typescript: ["tsconfig.json"],
  javascript: ["package.json"],
  python: ["pyproject.toml", "setup.py", "requirements.txt", "Pipfile"],
  go: ["go.mod", "go.sum"],
  rust: ["Cargo.toml", "Cargo.lock"],
};

function detectProjectType(root: string): ProjectType {
  // Check in priority order: TS > JS > Python > Go > Rust
  // TS is checked first because TS projects also have package.json
  for (const [type, markers] of Object.entries(PROJECT_TYPE_MARKERS)) {
    for (const marker of markers) {
      if (existsSync(join(root, marker))) {
        return type as ProjectType;
      }
    }
  }
  return "unknown";
}

// -- Source extension detection ------------------------------------------------

const EXTENSIONS_BY_TYPE: Record<string, string[]> = {
  typescript: [".ts", ".tsx"],
  javascript: [".js", ".jsx", ".mjs"],
  python: [".py"],
  go: [".go"],
  rust: [".rs"],
  unknown: [".ts", ".js", ".py", ".go", ".rs"],  // check all
};

// -- Detect actual source directories (beyond hardcoded SOURCE_DIRS) -----------

const STANDARD_SOURCE_DIRS = ["src", "lib", "pkg", "cmd", "internal", "app", "tools"];

function findSourceDirectories(root: string): string[] {
  const found: string[] = [];
  try {
    const entries = readdirSync(root, { withFileTypes: true });
    for (const entry of entries) {
      if (!entry.isDirectory()) continue;
      if (entry.name.startsWith(".") || entry.name === "node_modules" ||
          entry.name === "dist" || entry.name === "build" || entry.name === "out" ||
          entry.name === "coverage" || entry.name === "anti-hallucination-guard") continue;

      // Check if directory contains code files (direct children)
      const hasCode = hasCodeFiles(join(root, entry.name));
      if (hasCode || STANDARD_SOURCE_DIRS.includes(entry.name)) {
        found.push(entry.name);
      }
    }
  } catch { /* can't read root */ }

  // Also check root itself for code files (some projects have code in root)
  return found;
}

function hasCodeFiles(dir: string, depth: number = 0): boolean {
  try {
    const entries = readdirSync(dir, { withFileTypes: true });
    for (const entry of entries) {
      if (entry.isFile()) {
        const ext = extname(entry.name);
        if ([".ts", ".tsx", ".js", ".jsx", ".py", ".go", ".rs", ".sh"].includes(ext)) {
          return true;
        }
      }
      // Only recurse one level to avoid scanning too deep
      if (entry.isDirectory() && depth < 1 && !entry.name.startsWith(".") &&
          entry.name !== "node_modules") {
        if (hasCodeFiles(join(dir, entry.name), depth + 1)) return true;
      }
    }
  } catch { /* skip */ }
  return false;
}

/** Detect which code extensions actually exist in a directory (recursive) */
function detectExtensionsInDir(dir: string, root: string): string[] {
  const found = new Set<string>();
  const codeExts = [".ts", ".tsx", ".js", ".jsx", ".mjs", ".py", ".go", ".rs", ".sh"];
  const skipDirs = new Set(["node_modules", ".git", "dist", ".next", ".turbo", "build", "out", "anti-hallucination-guard"]);

  function walk(d: string, depth: number) {
    if (depth > 3) return;  // don't scan too deep
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

// -- Main function: generateAutoConfig ----------------------------------------

export interface AutoConfigResult {
  /** The generated VerifyConfig */
  config: VerifyConfig;
  /** Project type detected */
  projectType: ProjectType;
  /** Source directories found */
  sourceDirs: string[];
  /** Version files count */
  versionFilesCount: number;
  /** Whether this was a minimal config (no version files found) */
  isMinimal: boolean;
}

/**
 * Generate a VerifyConfig from auto-discover results.
 *
 * This function runs discover() on the project, extracts all the information
 * it can find, and builds a complete VerifyConfig that can be used by the
 * verify engine.
 *
 * Used by:
 *   - `ahg.sh verify` fallback when no verify-docs.json exists
 *   - `ahg.sh init` to generate the initial config file
 *
 * @param root - Absolute path to the project root
 * @returns AutoConfigResult with the generated config and metadata
 */
export function generateAutoConfig(root: string): AutoConfigResult {
  // Step 1: Run discover to understand project structure
  const result = discover(root);
  const projectType = detectProjectType(root);
  const sourceDirs = findSourceDirectories(root);
  const extensions = EXTENSIONS_BY_TYPE[projectType];

  // Step 2: Build checks (Section 1: README vs Code) --------------------------

  const checks: CheckConfig[] = [];

  // Generate info-only checks for each source directory
  // For known project types: use that type's extensions
  // For unknown: detect which extensions actually exist in the directory
  for (const dir of sourceDirs) {
    const dirExtensions = projectType === "unknown"
      ? detectExtensionsInDir(dir, root)
      : extensions;

    // If no extensions detected, add a generic glob check
    if (dirExtensions.length === 0) {
      checks.push({
        name: `${dir}/ files`,
        source: `glob:${dir}/*`,
        readmePattern: null,
        infoOnly: true,
        exclude: ["test", "spec", "__mocks__", ".test.", ".spec."],
      });
      continue;
    }

    // NOTE: glob:dir/*${ext} already works recursively in the AHG resolver.
    // Don't use glob:dir/**/*${ext} -- the resolver doesn't handle ** in paths.
    for (const ext of dirExtensions) {
      checks.push({
        name: `${dir}/*${ext} files`,
        source: `glob:${dir}/*${ext}`,
        readmePattern: null,  // info-only by default
        infoOnly: true,
      });
    }
  }

  // Also add checks for shell scripts in scripts/ directory
  if (existsSync(join(root, "scripts"))) {
    checks.push({
      name: "Shell scripts",
      source: "glob:scripts/*.sh",
      readmePattern: null,
      infoOnly: true,
    });
  }

  // Add git commits check (works for any git repo)
  checks.push({
    name: "Git commits",
    source: "git:HEAD",
    readmePattern: null,
    infoOnly: true,
  });

  // Step 3: Build versionSync (Section 3) -------------------------------------

  const versionInfo = result.versionInfo;
  const sotFile = versionInfo.sourceOfTruth?.file || "";
  const sotExt = sotFile.split(".").pop() || "";

  const extractPattern = sotExt === "json"
    ? '"version"\\s*:\\s*"([\\d.]+)"'
    : sotExt === "md"
    ? "v([\\d.]+)"
    : sotExt === "toml"
    ? 'version\\s*=\\s*"([\\d.]+)"'
    : "version[=:\\s]+[\"']?([\\d.]+)[\"']?";

  const targetPattern = (ext: string): string =>
    ext === "md" ? "v([\\d.]+)"
    : ext === "json" ? '"version"\\s*:\\s*"([\\d.]+)"'
    : ext === "toml" ? 'version\\s*=\\s*"([\\d.]+)"'
    : ext === "yaml" || ext === "yml" ? 'version:\\s*["\']?([\\d.]+)["\']?'
    : '(?:VERSION|version)\\s*[=:]\\s*["\']([\\d.]+)["\']';

  let versionSync: VersionSyncConfig | undefined;
  if (versionInfo.sourceOfTruth) {
    const targets = versionInfo.files
      .filter((f) => f !== versionInfo.sourceOfTruth)
      .map((f) => ({
        file: f.file,
        pattern: targetPattern(f.file.split(".").pop() || ""),
      }));

    versionSync = {
      source: `file:${sotFile}`,
      extractPattern,
      targets,
    };
  }

  // Step 4: Build docCoverage (Section 5) -------------------------------------

  const docCoverage: DocCoverageConfig[] = [];

  // Find documentation files to check against
  const docFiles: string[] = [];
  for (const docCandidate of ["README.md", "ARCHITECTURE.md", "docs/"]) {
    if (existsSync(join(root, docCandidate))) {
      docFiles.push(docCandidate);
    }
  }

  for (const dir of sourceDirs) {
    // Use README.md as default doc file, or first available doc
    const docFile = docFiles[0] || "README.md";
    docCoverage.push({
      name: `${dir}/ in docs`,
      sourceDir: dir,
      docFile,
      requiredMention: false,  // info-only by default in auto mode
      severity: "warn",
    });
  }

  // Step 5: Build final config ------------------------------------------------

  const config: VerifyConfig = {
    readme: "README.md",
    checks,
    versionSync,
    featureStatus: [],  // Can't auto-discover feature status markers
    docCoverage,
  };

  const versionFilesCount = versionInfo.files.length;
  const isMinimal = versionFilesCount === 0 && sourceDirs.length === 0;

  return {
    config,
    projectType,
    sourceDirs,
    versionFilesCount,
    isMinimal,
  };
}
