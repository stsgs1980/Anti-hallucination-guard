// ============================================================================
// discover-versions.test.ts -- regression tests for version file discovery
//
// Regression: a CHANGELOG was treated as a file holding the project version.
// Every version in a changelog belongs to a past release, and prose such as
// "version v2.1 -> v2.5" matches the same patterns as a real version field,
// so the check reported phantom mismatches -- and `ahg bump` rewrote
// historical entries.
// ============================================================================

import { describe, test, expect, afterEach } from "bun:test";
import { discoverVersions } from "../src/discover-versions.js";
import { execFileSync } from "child_process";
import { bumpVersion } from "../src/bump.js";
import { FixturePool, read } from "./_helpers.js";

const pool = new FixturePool();
afterEach(() => pool.drain());

const PKG = '{\n  "name": "fixture",\n  "version": "2.5.0"\n}\n';

describe("CHANGELOG is not a version file", () => {
  test("historical versions inside it are not discovered", () => {
    const dir = pool.make({
      "package.json": PKG,
      "CHANGELOG.md":
        "# Changelog\n\n## [2.1.0] - 2025-01-01\n\n" +
        "- scripts/ahg.sh: version v2.1 -> v2.5\n" +
        '- fixed a line that read "version: 9.9.9"\n',
    });

    const found = discoverVersions(dir).files.map((f) => f.file);

    expect(found).not.toContain("CHANGELOG.md");
    expect(found).toContain("package.json");
  });

  test("bump leaves historical entries untouched", () => {
    const dir = pool.make({
      "package.json": PKG,
      "CHANGELOG.md":
        "# Changelog\n\n## [2.5.0] - 2026-06-14\n\n- entry mentioning 2.5.0\n",
    });

    bumpVersion(dir, "3.0.0");

    const changelog = read(dir, "CHANGELOG.md");
    expect(changelog).toContain("## [2.5.0] - 2026-06-14");
    expect(changelog).toContain("entry mentioning 2.5.0");
    expect(read(dir, "package.json")).toContain('"version": "3.0.0"');
  });
});

describe("gitignored files are not version files", () => {
  test("runtime state with its own version field is skipped", () => {
    const dir = pool.make({
      "package.json": '{\n  "name": "fixture",\n  "version": "2.5.1"\n}\n',
      ".gitignore": "state.json\n",
      "state.json": '{\n  "version": "1.0"\n}\n',
    });
    execFileSync("git", ["-C", dir, "init", "-q"], { stdio: "ignore" });

    const found = discoverVersions(dir).files.map((f) => f.file);

    expect(found).not.toContain("state.json");
    expect(found).toContain("package.json");
  });
});

describe("verify-docs copy under tools/", () => {
  test("is a version file when the root is the AHG module itself", () => {
    const dir = pool.make({
      "setup.sh": "#!/bin/sh\n",
      "AGENT_RULES.md": "# rules\n",
      "README.md": "# App\n\n| v2.5.1 | current |\n",
      "tools/verify-docs/package.json":
        '{\n  "name": "verify-docs",\n  "version": "2.5.1"\n}\n',
    });

    const found = discoverVersions(dir).files.map((f) => f.file);

    expect(found).toContain("tools/verify-docs/package.json");
  });

  test("is skipped inside a consumer project", () => {
    const dir = pool.make({
      "package.json": '{\n  "name": "consumer",\n  "version": "1.2.3"\n}\n',
      "tools/verify-docs/package.json":
        '{\n  "name": "verify-docs",\n  "version": "2.5.1"\n}\n',
    });

    const found = discoverVersions(dir).files.map((f) => f.file);

    expect(found).not.toContain("tools/verify-docs/package.json");
  });
});
