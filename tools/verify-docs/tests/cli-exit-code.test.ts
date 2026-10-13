// ============================================================================
// cli-exit-code.test.ts -- regression tests for CLI exit codes
//
// Regression: in auto-discover mode (no verify-docs.json) the CLI printed
// "!! N mismatch(es) found!" and then exited 0 unconditionally, so CI and the
// pre-commit hook saw a pass on a project with real version mismatches.
// cli.ts documents its own contract: 0 = pass, 1 = mismatch/error.
// ============================================================================

import { describe, test, expect, afterEach } from "bun:test";
import { join, dirname } from "path";
import { fileURLToPath } from "url";
import { FixturePool } from "./_helpers.js";

const CLI = join(dirname(fileURLToPath(import.meta.url)), "..", "src", "cli.ts");

const pool = new FixturePool();
afterEach(() => pool.drain());

async function runCli(cwd: string, args: string[] = []) {
  const proc = Bun.spawn([process.execPath, "run", CLI, ...args], {
    cwd,
    stdout: "pipe",
    stderr: "pipe",
    env: { ...process.env, NO_COLOR: "1" },
  });
  const stdout = await new Response(proc.stdout).text();
  const stderr = await new Response(proc.stderr).text();
  const code = await proc.exited;
  return { code, output: stdout + stderr };
}

describe("auto-discover mode (no verify-docs.json)", () => {
  test("exits 1 when a version mismatch is found", async () => {
    const dir = pool.make({
      "package.json": '{\n  "name": "fixture",\n  "version": "1.0.0"\n}\n',
      "README.md": "# Fixture\n\n| v9.9.9 | current |\n",
    });

    const { code, output } = await runCli(dir);

    expect(output).toContain("mismatch");
    expect(code).toBe(1);
  });

  test("exits 0 when everything is consistent", async () => {
    const dir = pool.make({
      "package.json": '{\n  "name": "fixture",\n  "version": "1.0.0"\n}\n',
      "README.md": "# Fixture\n\n| v1.0.0 | current |\n",
    });

    const { code } = await runCli(dir);

    expect(code).toBe(0);
  });
});

describe("configured mode (verify-docs.json present)", () => {
  test("exits 1 when a configured version target mismatches", async () => {
    const dir = pool.make({
      "package.json": '{\n  "name": "fixture",\n  "version": "1.0.0"\n}\n',
      "README.md": "# Fixture\n\n| v1.0.0 | current |\n",
      "docs/VERSION.md": "version: 7.7.7\n",
      "verify-docs.json": JSON.stringify({
        readme: "README.md",
        checks: [],
        versionSync: {
          source: "file:package.json",
          extractPattern: '"version"\\s*:\\s*"([\\d.]+)"',
          targets: [{ file: "docs/VERSION.md", pattern: "version:\\s*([\\d.]+)" }],
        },
      }),
    });

    const { code, output } = await runCli(dir);

    expect(output).toContain("MISMATCH");
    expect(code).toBe(1);
  });
});
