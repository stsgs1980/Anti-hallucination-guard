// ============================================================================
// bump.test.ts -- regression tests for version bumping
//
// Regression: the replace callback in bump.ts treated every callback argument
// as a capture group. For patterns with a single capture group (or none) the
// trailing arguments are the match offset and the whole source string, so the
// offset was appended to the new version:
//   "version: 9.9.9"  --bump=2.0.0-->  "version: 2.0.06"
// ============================================================================

import { describe, test, expect, afterEach } from "bun:test";
import { bumpVersion, replaceVersionInFile } from "../src/bump.js";
import { FixturePool, read } from "./_helpers.js";

const pool = new FixturePool();
afterEach(() => pool.drain());

describe("bump: markdown 'version: X.Y.Z'", () => {
  test("does not append the match offset to the new version", () => {
    const dir = pool.make({
      "package.json": '{\n  "name": "fixture",\n  "version": "9.9.9"\n}\n',
      "README.md": "# App\n\nversion: 9.9.9\n",
    });

    const result = bumpVersion(dir, "2.0.0");

    expect(read(dir, "README.md")).toBe("# App\n\nversion: 2.0.0\n");
    expect(read(dir, "package.json")).toContain('"version": "2.0.0"');
    expect(result.failed).toEqual([]);
  });
});

describe("bump: bare version occurrence (generic fallback pattern)", () => {
  test("replaces only the version string", () => {
    const dir = pool.make({ "bare.txt": "release 1.0.0 is live\n" });

    const ok = replaceVersionInFile("bare.txt", dir, "1.0.0", "2.0.0");

    expect(ok).toBe(true);
    expect(read(dir, "bare.txt")).toBe("release 2.0.0 is live\n");
  });
});

describe("bump: markdown table row", () => {
  test("keeps the surrounding table syntax", () => {
    const dir = pool.make({ "README.md": "# App\n\n| v9.9.9 | current |\n" });

    const ok = replaceVersionInFile("README.md", dir, "9.9.9", "2.0.0");

    expect(ok).toBe(true);
    expect(read(dir, "README.md")).toBe("# App\n\n| v2.0.0 | current |\n");
  });
});

describe("bump: JSON manifest", () => {
  test("keeps the quotes around the version", () => {
    const dir = pool.make({
      "package.json": '{\n  "name": "fixture",\n  "version": "9.9.9"\n}\n',
    });

    const ok = replaceVersionInFile("package.json", dir, "9.9.9", "2.0.0");

    expect(ok).toBe(true);
    expect(read(dir, "package.json")).toBe(
      '{\n  "name": "fixture",\n  "version": "2.0.0"\n}\n'
    );
  });
});

describe("bump: dry run", () => {
  test("writes nothing", () => {
    const dir = pool.make({
      "package.json": '{\n  "name": "fixture",\n  "version": "9.9.9"\n}\n',
      "README.md": "# App\n\nversion: 9.9.9\n",
    });

    const result = bumpVersion(dir, "2.0.0", { dryRun: true });

    expect(result.dryRun).toBe(true);
    expect(result.updated).toBe(2);
    expect(read(dir, "README.md")).toBe("# App\n\nversion: 9.9.9\n");
    expect(read(dir, "package.json")).toContain('"version": "9.9.9"');
  });
});

describe("bump: several occurrences in one file", () => {
  test("updates every occurrence, not just the first match", () => {
    const dir = pool.make({
      "package.json": '{\n  "name": "fixture",\n  "version": "9.9.9"\n}\n',
      "README.md":
        "# App\n\n![v](https://img.shields.io/badge/v9.9.9-x-green.svg)\n\n| v9.9.9 | current |\n",
    });

    const result = bumpVersion(dir, "2.0.0");
    const readme = read(dir, "README.md");

    expect(readme).not.toContain("9.9.9");
    expect(readme).toContain("badge/v2.0.0-x-green.svg");
    expect(readme).toContain("| v2.0.0 | current |");
    expect(result.failed).toEqual([]);
  });
});

describe("bump: CHANGELOG entry", () => {
  test("does not duplicate an entry that already exists", () => {
    const dir = pool.make({
      "package.json": '{\n  "name": "fixture",\n  "version": "2.5.0"\n}\n',
      "CHANGELOG.md":
        "# Changelog\n\n## [2.5.1] - 2026-10-13\n\n- already documented\n",
    });

    const result = bumpVersion(dir, "2.5.1");
    const changelog = read(dir, "CHANGELOG.md");

    expect(changelog.match(/## \[2\.5\.1\]/g)?.length).toBe(1);
    expect(changelog).toContain("- already documented");
    expect(result.changelogUpdated).toBe(false);
  });

  test("adds an entry when the version is new", () => {
    const dir = pool.make({
      "package.json": '{\n  "name": "fixture",\n  "version": "2.5.0"\n}\n',
      "CHANGELOG.md":
        "# Changelog\n\n## [2.5.0] - 2026-06-14\n\n- old entry\n",
    });

    const result = bumpVersion(dir, "2.5.1");
    const changelog = read(dir, "CHANGELOG.md");

    expect(result.changelogUpdated).toBe(true);
    expect(changelog).toContain("## [2.5.1] -");
    expect(changelog).toContain("## [2.5.0] - 2026-06-14");
  });
});
