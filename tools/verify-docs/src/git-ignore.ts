// ============================================================================
// git-ignore.ts -- ask git which paths are ignored
//
// Split out of discover-versions.ts (Rule 12: one file = one responsibility).
// A version field in an ignored file is runtime state, not the project
// version, so version discovery has to be able to ask about it.
// ============================================================================

import { execFileSync } from "child_process";

/**
 * Paths git reports as ignored. A version field in an ignored file is runtime
 * state, not the project version: .branch-protect-state.json for example
 * carries a schema version that a bump would happily overwrite.
 */
export function gitIgnoredFiles(root: string): string[] {
  try {
    return execFileSync(
      "git",
      ["-C", root, "ls-files", "--others", "--ignored", "--exclude-standard"],
      { encoding: "utf-8", stdio: ["ignore", "pipe", "ignore"] }
    )
      .split("\n")
      .filter((line) => line.length > 0);
  } catch {
    return []; // not a git repo, or git unavailable
  }
}

export function isIgnored(relPath: string, ignored: string[]): boolean {
  for (const entry of ignored) {
    if (entry.endsWith("/") ? relPath.startsWith(entry) : relPath === entry) {
      return true;
    }
  }
  return false;
}

