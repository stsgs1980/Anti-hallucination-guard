#!/usr/bin/env bun
// ============================================================================
// cli.ts -- Command-line interface for verify-docs v2.0
//
// Modes:
//   VERIFY    (default)    -- run with verify-docs.json config
//   DISCOVER  (--discover) -- auto-scan project without config
//   BUMP      (--bump=X)   -- update version in all discovered files
//   INIT      (--init)     -- generate verify-docs.json from discover
//   BASELINE  (--baseline) -- create/update .ahg-baseline.json
//
// Exit codes: 0 = pass, 1 = mismatch/error, 2 = config error
// ============================================================================

import { resolve } from "path";
import { readFileSync, existsSync, writeFileSync } from "fs";
import { verify, registerSource } from "./engine.js";
import { discover } from "./discover.js";
import { bumpVersion } from "./bump.js";
import { createBaseline } from "./discover-baseline.js";

// -- Parse args --------------------------------------------------------------
const args = process.argv.slice(2);
const ci = args.includes("--ci");
const configFlag = args.find((a) => a.startsWith("--config="));
const configPath = configFlag ? configFlag.split("=")[1] : "verify-docs.json";
const root = resolve(process.cwd());
const doDiscover = args.includes("--discover");
const bumpFlag = args.find((a) => a.startsWith("--bump="));
const doBump = bumpFlag ? bumpFlag.split("=")[1] : null;
const doInit = args.includes("--init");
const doBaseline = args.includes("--baseline");
const doBaselineCheck = args.includes("--baseline") && args.includes("--check");
const doDryRun = args.includes("--dry-run");

// -- Show help ---------------------------------------------------------------
if (args.includes("--help") || args.includes("-h")) {
  console.log(`
verify-docs -- Data-driven doc consistency checker v2.0

USAGE
  verify-docs                          Run with verify-docs.json config
  verify-docs --ci                     CI mode: skip cross-repo checks
  verify-docs --config=X               Custom config file path
  verify-docs --discover               Auto-discover project (no config)
  verify-docs --discover --json        Discover output as JSON
  verify-docs --bump=X.Y.Z             Update version in all files
  verify-docs --bump=X.Y.Z --dry-run   Preview bump without writing
  verify-docs --init                   Generate verify-docs.json from discover
  verify-docs --baseline               Create .ahg-baseline.json
  verify-docs --baseline --check       Check current files vs baseline

MODES
  VERIFY    (default)    Check docs against config
  DISCOVER  (--discover) Scan project, find issues without config
  BUMP      (--bump)     Update version atomically across all files
  INIT      (--init)     Generate config from auto-discover results
  BASELINE  (--baseline) Track project files for deletion detection

SECTIONS (verify mode)
  1. README vs Code        Numbers in docs match actual code
  2. Cross-repo            Values consistent across sibling repos
  3. Version sync          Version matches across all docs
  4. Feature status        Stub markers don't contradict existing code
  5. Doc coverage          Code files are mentioned in documentation

EXIT CODES
  0  All checks passed (or discover-mode with warnings only)
  1  Mismatch / error found
  2  Config error
`);
  process.exit(0);
}

// -- Helper: format result line ----------------------------------------------
function formatLine(line: { status: string; name: string; detail: string }): string {
  const tag =
    line.status === "info" ? "info"
    : line.status === "skip" ? "--"
    : line.status === "ci" ? "CI"
    : line.status;
  return `[${tag}] ${line.name}: ${line.detail}`;
}

// -- MODE: BUMP --------------------------------------------------------------
if (doBump) {
  console.log(`Bumping version to ${doBump}...\n`);
  const result = bumpVersion(root, doBump, { dryRun: doDryRun });

  if (result.dryRun) {
    console.log("[DRY-RUN] Would update:");
    for (const f of result.files) console.log(`  [+] ${f}`);
    if (result.changelogUpdated) console.log("  [+] CHANGELOG entry (new)");
  } else {
    for (const f of result.files) console.log(`[OK] ${f} updated`);
    for (const f of result.failed) console.log(`[FAIL] ${f} could not update`);
    if (result.changelogUpdated) console.log("[OK] CHANGELOG entry added");
  }
  console.log(`\n${result.updated} file(s) updated.`);
  if (result.failed.length > 0) process.exit(1);
  process.exit(0);
}

// -- MODE: BASELINE ----------------------------------------------------------
if (doBaseline && !doBaselineCheck) {
  const results = createBaseline(root);
  for (const line of results) console.log(formatLine(line));
  process.exit(0);
}

// -- MODE: DISCOVER ----------------------------------------------------------
if (doDiscover) {
  const result = discover(root, { createBaseline: doBaseline });

  for (const section of result.sections) {
    console.log(`\n=== ${section.name} ===\n`);
    for (const line of section.results) {
      console.log(formatLine(line));
    }
  }

  process.exit(result.errors > 0 ? 1 : 0);
}

// -- MODE: INIT --------------------------------------------------------------
if (doInit) {
  // Build a FULL config from auto-discover results, not a half-empty template
  console.log("Generating verify-docs.json from auto-discover...\n");
  const result = discover(root);

  // -- Version sync ----------------------------------------------------------
  const versionInfo = result.versionInfo;
  const sotFile = versionInfo.sourceOfTruth?.file || "";
  const sotExt = sotFile.split(".").pop() || "";
  const extractPattern = sotExt === "json"
    ? '"version"\\s*:\\s*"([\\d.]+)"'
    : sotExt === "md"
    ? "v([\\d.]+)"
    : "version[=:\\s]+[\"']?([\\d.]+)[\"']?";
  const targetPattern = (ext: string) =>
    ext === "md" ? "v([\\d.]+)"
    : ext === "json" ? '"version"\\s*:\\s*"([\\d.]+)"'
    : '(?:VERSION|version)\\s*[=:]\\s*["\']([\\d.]+)["\']';

  const versionSync = versionInfo.sourceOfTruth
    ? {
        source: `file:${sotFile}`,
        extractPattern,
        targets: versionInfo.files
          .filter((f) => f !== versionInfo.sourceOfTruth)
          .map((f) => ({
            file: f.file,
            pattern: targetPattern(f.file.split(".").pop() || ""),
          })),
      }
    : undefined;

  // -- Checks: auto-generate info-only checks for source directories -----------
  const checks: Record<string, unknown>[] = [];
  for (const section of result.sections) {
    if (section.name === "Doc Coverage") {
      for (const r of section.results) {
        if (r.status === "info" && r.name === "Source directories") {
          // Parse "Found: src, lib" -> generate glob checks
          const dirs = r.detail.replace("Found: ", "").split(", ").filter(Boolean);
          for (const dir of dirs) {
            // Determine extensions based on what's in the directory
            checks.push({
              name: `${dir}/ source files`,
              source: `glob:${dir}/**/*.ts`,
              readmePattern: null,
              infoOnly: true,
            });
            checks.push({
              name: `${dir}/ JS files`,
              source: `glob:${dir}/**/*.js`,
              readmePattern: null,
              infoOnly: true,
            });
          }
        }
      }
    }
  }
  // Also add a check for shell scripts
  checks.push({
    name: "Shell scripts",
    source: "glob:scripts/*.sh",
    readmePattern: null,
    infoOnly: true,
  });

  // -- Doc coverage: auto-generate from discovered source dirs -----------------
  const docCoverage: Record<string, unknown>[] = [];
  for (const section of result.sections) {
    if (section.name === "Doc Coverage") {
      for (const r of section.results) {
        if (r.status === "info" && r.name === "Source directories") {
          const dirs = r.detail.replace("Found: ", "").split(", ").filter(Boolean);
          for (const dir of dirs) {
            docCoverage.push({
              name: `${dir}/ in docs`,
              sourceDir: dir,
              docFile: "README.md",
              requiredMention: false,
              severity: "warn" as const,
            });
          }
        }
      }
    }
  }

  // -- Build final config ----------------------------------------------------
  const config: Record<string, unknown> = {
    readme: "README.md",
    checks,
    versionSync,
    featureStatus: [],
    docCoverage,
  };

  const outPath = resolve(root, configPath);
  if (existsSync(outPath)) {
    console.log(`[skip] ${configPath} already exists`);
    console.log("  To regenerate: rm verify-docs.json && run --init again");
  } else {
    writeFileSync(outPath, JSON.stringify(config, null, 2) + "\n", "utf-8");
    console.log(`[OK] Created ${configPath}`);
    console.log("");
    console.log("Generated config includes:");
    console.log(`  versionSync: ${versionSync ? `${versionInfo.files.length} file(s) tracked` : "no version files found"}`);
    console.log(`  checks:      ${checks.length} info-only check(s)`);
    console.log(`  docCoverage: ${docCoverage.length} coverage zone(s)`);
    console.log("");
    console.log("Customize further: add countPattern to checks, featureStatus entries, etc.");
    console.log("See: https://github.com/stsgs1980/Anti-hallucination-guard#verify-docsjson");
  }

  // Also create baseline
  createBaseline(root);

  process.exit(0);
}

// -- MODE: VERIFY (default) --------------------------------------------------
// With config: run configured checks
// Without config: auto-discover as fallback (not exit(2))

const fullConfigPath = resolve(root, configPath);
if (!existsSync(fullConfigPath)) {
  // v2.0: auto-discover fallback instead of exit(2)
  console.log(`Config not found: ${configPath}`);
  console.log("Running auto-discover instead...\n");

  const result = discover(root);
  for (const section of result.sections) {
    console.log(`\n=== ${section.name} ===\n`);
    for (const line of section.results) console.log(formatLine(line));
  }

  console.log(`\nTip: run "verify-docs --init" to generate ${configPath}`);
  process.exit(result.errors > 0 ? 1 : 0);
}

// Load config and run verification
const config = JSON.parse(readFileSync(fullConfigPath, "utf-8"));

// Load project-specific plugins (optional)
const pluginPath = resolve(root, "verify-docs.plugins.ts");
if (existsSync(pluginPath)) {
  try {
    const plugin = await import(pluginPath);
    if (typeof plugin.default === "function") {
      plugin.default({ registerSource });
    }
  } catch (err: any) {
    console.warn(`[warn] Plugin load failed: ${err.message}`);
  }
}

if (ci) console.log("[CI mode] Cross-repo checks will be skipped.\n");

const result = verify(root, config, { ci });

// Print all sections
const sections = [
  { title: "1. README vs Code", data: result.section1 },
  { title: "2. Cross-repo Consistency", data: result.section2 },
  { title: "3. Version Synchronization", data: result.section3 },
  { title: "4. Feature Status (Stub Detection)", data: result.section4 },
  { title: "5. Documentation Coverage", data: result.section5 },
];

for (const section of sections) {
  if (section.data.length > 0) {
    console.log(`\n=== ${section.title} ===\n`);
    for (const line of section.data) console.log(formatLine(line));
  }
}

// Summary
if (result.errors > 0) {
  console.log(`\n!! ${result.errors} mismatch(es) found!`);
  process.exit(1);
} else {
  console.log("\nAll checks consistent.");
  process.exit(0);
}
