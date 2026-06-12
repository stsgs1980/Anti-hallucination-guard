// ============================================================================
// auto-config.ts -- Generate VerifyConfig from auto-discover results
//
// Core of the "no config needed" philosophy:
//   - discover() scans the project (versions, changelog, coverage, baseline)
//   - discover-project.ts detects project type and source directories
//   - generateAutoConfig() assembles a VerifyConfig from all of the above
//   - Config is used in-memory (verify fallback) or written to disk (--init)
//
// This means `ahg.sh verify` works WITHOUT verify-docs.json.
// ============================================================================

import { existsSync } from "fs";
import { join } from "path";
import { discover } from "./discover.js";
import { detectProjectType, findSourceDirectories, detectExtensionsInDir, EXTENSIONS_BY_TYPE } from "./discover-project.js";
import type { ProjectType } from "./discover-project.js";
import type { VerifyConfig, CheckConfig, VersionSyncConfig, DocCoverageConfig } from "./types.js";

// -- Result type --------------------------------------------------------------

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

// -- Helpers: version pattern generators --------------------------------------

function extractPatternFor(ext: string): string {
  if (ext === "json") return '"version"\\s*:\\s*"([\\d.]+)"';
  if (ext === "md") return "v([\\d.]+)";
  if (ext === "toml") return 'version\\s*=\\s*"([\\d.]+)"';
  return 'version[=:\\s]+["\']?([\\d.]+)["\']?';
}

function targetPatternFor(ext: string): string {
  if (ext === "md") return "v([\\d.]+)";
  if (ext === "json") return '"version"\\s*:\\s*"([\\d.]+)"';
  if (ext === "toml") return 'version\\s*=\\s*"([\\d.]+)"';
  if (ext === "yaml" || ext === "yml") return 'version:\\s*["\']?([\\d.]+)["\']?';
  return '(?:VERSION|version)\\s*[=:]\\s*["\']([\\d.]+)["\']';
}

// -- Build checks (Section 1) ------------------------------------------------

function buildChecks(sourceDirs: string[], projectType: ProjectType, root: string): CheckConfig[] {
  const checks: CheckConfig[] = [];
  const extensions = EXTENSIONS_BY_TYPE[projectType];

  for (const dir of sourceDirs) {
    const dirExtensions = projectType === "unknown"
      ? detectExtensionsInDir(dir, root)
      : extensions;

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

    // NOTE: glob:dir/*${ext} works recursively in the AHG resolver.
    // Don't use glob:dir/**/*${ext} -- the resolver doesn't handle **.
    for (const ext of dirExtensions) {
      checks.push({
        name: `${dir}/*${ext} files`,
        source: `glob:${dir}/*${ext}`,
        readmePattern: null,
        infoOnly: true,
      });
    }
  }

  if (existsSync(join(root, "scripts"))) {
    checks.push({
      name: "Shell scripts",
      source: "glob:scripts/*.sh",
      readmePattern: null,
      infoOnly: true,
    });
  }

  checks.push({
    name: "Git commits",
    source: "git:HEAD",
    readmePattern: null,
    infoOnly: true,
  });

  return checks;
}

// -- Build versionSync (Section 3) -------------------------------------------

function buildVersionSync(versionInfo: ReturnType<typeof discover>["versionInfo"]): VersionSyncConfig | undefined {
  if (!versionInfo.sourceOfTruth) return undefined;

  const sotFile = versionInfo.sourceOfTruth.file;
  const sotExt = sotFile.split(".").pop() || "";

  return {
    source: `file:${sotFile}`,
    extractPattern: extractPatternFor(sotExt),
    targets: versionInfo.files
      .filter((f) => f !== versionInfo.sourceOfTruth)
      .map((f) => ({
        file: f.file,
        pattern: targetPatternFor(f.file.split(".").pop() || ""),
      })),
  };
}

// -- Build docCoverage (Section 5) -------------------------------------------

function buildDocCoverage(sourceDirs: string[], root: string): DocCoverageConfig[] {
  const docFiles: string[] = [];
  for (const doc of ["README.md", "ARCHITECTURE.md", "docs/"]) {
    if (existsSync(join(root, doc))) docFiles.push(doc);
  }

  return sourceDirs.map((dir) => ({
    name: `${dir}/ in docs`,
    sourceDir: dir,
    docFile: docFiles[0] || "README.md",
    requiredMention: false,
    severity: "warn" as const,
  }));
}

// -- Main function -----------------------------------------------------------

/**
 * Generate a VerifyConfig from auto-discover results.
 * Used by `ahg verify` (no config fallback) and `ahg init`.
 */
export function generateAutoConfig(root: string): AutoConfigResult {
  const result = discover(root);
  const projectType = detectProjectType(root);
  const sourceDirs = findSourceDirectories(root);

  const config: VerifyConfig = {
    readme: "README.md",
    checks: buildChecks(sourceDirs, projectType, root),
    versionSync: buildVersionSync(result.versionInfo),
    featureStatus: [],
    docCoverage: buildDocCoverage(sourceDirs, root),
  };

  const versionFilesCount = result.versionInfo.files.length;
  const isMinimal = versionFilesCount === 0 && sourceDirs.length === 0;

  return { config, projectType, sourceDirs, versionFilesCount, isMinimal };
}
