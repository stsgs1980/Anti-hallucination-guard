// ============================================================================
// version-sync.test.ts -- regression tests for Section 3 (version sync)
//
// Regression: a target file that was explicitly listed in verify-docs.json but
// did not exist on disk was reported as "skip" and did not count as an error,
// so a deleted or renamed version file silently passed verification.
// ============================================================================

import { describe, test, expect, afterEach } from "bun:test";
import { verifySection3 } from "../src/verify-section3.js";
import { FixturePool } from "./_helpers.js";

const pool = new FixturePool();
afterEach(() => pool.drain());

const SOURCE = "file:package.json";
const EXTRACT = '"version"\\s*:\\s*"([\\d.]+)"';
const PKG = '{\n  "name": "fixture",\n  "version": "1.0.0"\n}\n';

describe("configured version target missing from disk", () => {
  test("counts as an error, not a skip", () => {
    const dir = pool.make({ "package.json": PKG });

    const { results, errors } = verifySection3(
      {
        source: SOURCE,
        extractPattern: EXTRACT,
        targets: [{ file: "docs/GONE.md", pattern: "v([\\d.]+)" }],
      },
      dir
    );

    const entry = results.find((r) => r.name === "docs/GONE.md");
    expect(entry).toBeDefined();
    expect(entry?.status).toBe("ERR");
    expect(errors).toBe(1);
  });

  test("is skipped without an error when marked optional", () => {
    const dir = pool.make({ "package.json": PKG });

    const { results, errors } = verifySection3(
      {
        source: SOURCE,
        extractPattern: EXTRACT,
        targets: [{ file: "docs/GONE.md", pattern: "v([\\d.]+)", optional: true }],
      },
      dir
    );

    const entry = results.find((r) => r.name === "docs/GONE.md");
    expect(entry?.status).toBe("skip");
    expect(errors).toBe(0);
  });
});

describe("configured version target present", () => {
  test("matching version passes", () => {
    const dir = pool.make({
      "package.json": PKG,
      "docs/VERSION.md": "version: 1.0.0\n",
    });

    const { errors } = verifySection3(
      {
        source: SOURCE,
        extractPattern: EXTRACT,
        targets: [{ file: "docs/VERSION.md", pattern: "version:\\s*([\\d.]+)" }],
      },
      dir
    );

    expect(errors).toBe(0);
  });

  test("mismatched version is an error", () => {
    const dir = pool.make({
      "package.json": PKG,
      "docs/VERSION.md": "version: 7.7.7\n",
    });

    const { errors } = verifySection3(
      {
        source: SOURCE,
        extractPattern: EXTRACT,
        targets: [{ file: "docs/VERSION.md", pattern: "version:\\s*([\\d.]+)" }],
      },
      dir
    );

    expect(errors).toBe(1);
  });

  test("pattern that does not match is an error, not a silent skip", () => {
    const dir = pool.make({
      "package.json": PKG,
      "docs/VERSION.md": "no version here\n",
    });

    const { results, errors } = verifySection3(
      {
        source: SOURCE,
        extractPattern: EXTRACT,
        targets: [{ file: "docs/VERSION.md", pattern: "version:\\s*([\\d.]+)" }],
      },
      dir
    );

    const entry = results.find((r) => r.name === "docs/VERSION.md");
    expect(entry?.status).toBe("ERR");
    expect(errors).toBe(1);
  });
});
