#!/usr/bin/env bun
// ============================================================================
// cli.ts -- Command-line interface for verify-docs v2.1
//
// Modes:
//   VERIFY    (default)    -- run with verify-docs.json config
//                             OR auto-discover fallback (no config needed!)
//   DISCOVER  (--discover) -- auto-scan project without config
//   BUMP      (--bump=X)   -- update version in all discovered files
//   INIT      (--init)     -- generate verify-docs.json from auto-discover
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
import { generateAutoConfig } from "./auto-config.js";
import { formatLine, printVerifySections, printDiscoverSections } from "./cli-helpers.js";

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
verify-docs -- Data-driven doc consistency checker v2.1

USAGE
  verify-docs                          Run verify (auto-discover if no config)
  verify-docs --ci                     CI mode: skip cross-repo checks
  verify-docs --config=X               Custom config file path
  verify-docs --discover               Auto-discover project (no config)
  verify-docs --bump=X.Y.Z             Update version in all files
  verify-docs --bump=X.Y.Z --dry-run   Preview bump without writing
  verify-docs --init                   Generate verify-docs.json from auto-discover
  verify-docs --baseline               Create .ahg-baseline.json
  verify-docs --baseline --check       Check current files vs baseline

AUTO-DISCOVER FALLBACK
  When verify-docs.json is missing, verify auto-generates a config and
  runs the full 5-section verification. No manual config required!

EXIT CODES
  0  All checks passed (or discover-mode with warnings only)
  1  Mismatch / error found
  2  Config error
`);
  process.exit(0);
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
  printDiscoverSections(result.sections);
  process.exit(result.errors > 0 ? 1 : 0);
}

// -- MODE: INIT --------------------------------------------------------------
if (doInit) {
  console.log("Generating verify-docs.json from auto-discover...\n");
  const { config, projectType, sourceDirs, versionFilesCount } = generateAutoConfig(root);

  const outPath = resolve(root, configPath);
  if (existsSync(outPath)) {
    console.log(`[skip] ${configPath} already exists`);
    console.log("  To regenerate: rm verify-docs.json && run --init again");
  } else {
    writeFileSync(outPath, JSON.stringify(config, null, 2) + "\n", "utf-8");
    console.log(`[OK] Created ${configPath}`);
    console.log(`Project type detected: ${projectType}`);
    console.log(`Source directories:     ${sourceDirs.join(", ") || "none found"}`);
    console.log(`  versionSync: ${config.versionSync ? `${versionFilesCount} file(s) tracked` : "no version files found"}`);
    console.log(`  checks:      ${config.checks.length} info-only check(s)`);
    console.log(`  docCoverage: ${config.docCoverage ? config.docCoverage.length : 0} coverage zone(s)`);
    console.log("\nCustomize: add countPattern to checks, featureStatus entries, etc.");
  }

  createBaseline(root);
  process.exit(0);
}

// -- MODE: VERIFY (default) --------------------------------------------------
// With config: run configured checks
// Without config: auto-discover -> generateAutoConfig -> verify()

const fullConfigPath = resolve(root, configPath);
if (!existsSync(fullConfigPath)) {
  // v2.1: Full auto-discover fallback -- generate config in memory, run verify()
  console.log(`Config not found: ${configPath}`);
  console.log("Auto-discovering project structure...\n");

  const { config, projectType, sourceDirs, versionFilesCount, isMinimal } = generateAutoConfig(root);

  console.log(`Project type: ${projectType}`);
  console.log(`Source dirs:   ${sourceDirs.join(", ") || "none found"}`);
  console.log(`Version files: ${versionFilesCount}\n`);

  if (isMinimal) {
    console.log("[warn] Minimal project structure -- showing discover report instead.\n");
    const discoverResult = discover(root);
    printDiscoverSections(discoverResult.sections);
  } else {
    console.log("Running verification with auto-generated config...\n");
    if (ci) console.log("[CI mode] Cross-repo checks will be skipped.\n");

    const verifyResult = verify(root, config, { ci });
    printVerifySections(verifyResult);

    if (verifyResult.errors > 0) {
      console.log(`\n!! ${verifyResult.errors} mismatch(es) found!`);
    } else {
      console.log("\nAll auto-discover checks consistent.");
    }
  }

  console.log(`\nTip: run "ahg init" to save config as ${configPath}`);
  console.log("     then customize it for your project.\n");
  process.exit(0);
}

// -- Load config and run verification ----------------------------------------
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
printVerifySections(result);

if (result.errors > 0) {
  console.log(`\n!! ${result.errors} mismatch(es) found!`);
  process.exit(1);
} else {
  console.log("\nAll checks consistent.");
  process.exit(0);
}
