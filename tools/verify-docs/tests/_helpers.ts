// ============================================================================
// _helpers.ts -- shared test fixture helpers
//
// Every fixture is created in a fresh temporary directory and removed
// after the test finishes, so the repository is never modified by tests.
// ============================================================================

import { mkdtempSync, writeFileSync, mkdirSync, rmSync, readFileSync } from "fs";
import { tmpdir } from "os";
import { join, dirname } from "path";

/** Create a temporary project from a { relativePath: content } map. */
export function makeFixture(files: Record<string, string>): string {
  const dir = mkdtempSync(join(tmpdir(), "ahg-test-"));
  for (const rel of Object.keys(files)) {
    const full = join(dir, rel);
    mkdirSync(dirname(full), { recursive: true });
    writeFileSync(full, files[rel], "utf-8");
  }
  return dir;
}

/** Remove a temporary project. */
export function cleanup(dir: string): void {
  rmSync(dir, { recursive: true, force: true });
}

/** Read a file inside a fixture. */
export function read(dir: string, rel: string): string {
  return readFileSync(join(dir, rel), "utf-8");
}

/** Tracks fixtures created by a test file so they can all be removed. */
export class FixturePool {
  private dirs: string[] = [];

  make(files: Record<string, string>): string {
    const dir = makeFixture(files);
    this.dirs.push(dir);
    return dir;
  }

  drain(): void {
    while (this.dirs.length > 0) {
      cleanup(this.dirs.pop() as string);
    }
  }
}
