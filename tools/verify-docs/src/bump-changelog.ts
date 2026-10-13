// ============================================================================
// bump-changelog.ts -- CHANGELOG entry creation for a version bump
//
// Split out of bump.ts (Rule 12: one file = one responsibility).
// Inserts a new "## [version] - date" section at the top of the existing
// entries, preserving any "# Title" heading above them.
// ============================================================================

import { readFileSync, writeFileSync } from "fs";
import { join } from "path";

/**
 * Insert a new version section into a CHANGELOG file.
 * Returns true when the file was rewritten.
 */
export function addChangelogEntry(
  root: string,
  version: string,
  changelogFile: string
): boolean {
  const fullPath = join(root, changelogFile);
  try {
    const content = readFileSync(fullPath, "utf-8");
    const date = new Date().toISOString().split("T")[0];

    // Find the first ## heading (version entry level) and insert before it.
    // This preserves the # Title heading (e.g. "# Changelog") at the top.
    const h2Match = content.match(/^##\s/m);
    if (h2Match && h2Match.index !== undefined) {
      const entry = `## [${version}] - ${date}\n\n- \n\n`;
      const newContent =
        content.slice(0, h2Match.index) +
        entry +
        content.slice(h2Match.index);
      writeFileSync(fullPath, newContent, "utf-8");
      return true;
    }

    // No ## heading found -- insert after the first # heading (title)
    const h1Match = content.match(/^#\s.*\n/m);
    if (h1Match && h1Match.index !== undefined) {
      const insertAfter = h1Match.index + h1Match[0].length;
      const entry = `## [${version}] - ${date}\n\n- \n\n`;
      const newContent =
        content.slice(0, insertAfter) +
        entry +
        content.slice(insertAfter);
      writeFileSync(fullPath, newContent, "utf-8");
      return true;
    }

    // No heading at all -- prepend
    const entry = `## [${version}] - ${date}\n\n- \n\n`;
    writeFileSync(fullPath, entry + content, "utf-8");
    return true;
  } catch {
    return false;
  }
}
