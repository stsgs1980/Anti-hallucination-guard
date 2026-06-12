// ============================================================================
// cli-helpers.ts -- Shared output formatting for verify-docs CLI
//
// Extracted from cli.ts to keep it under 250 lines (Rule 11: Anti-monolith).
// ============================================================================

import type { VerifyResult, LineResult } from "./types.js";

// -- Format a single result line ----------------------------------------------

export function formatLine(line: { status: string; name: string; detail: string }): string {
  const tag =
    line.status === "info" ? "info"
    : line.status === "skip" ? "--"
    : line.status === "ci" ? "CI"
    : line.status;
  return `[${tag}] ${line.name}: ${line.detail}`;
}

// -- Print verify sections ----------------------------------------------------

const SECTION_TITLES = [
  "1. README vs Code",
  "2. Cross-repo Consistency",
  "3. Version Synchronization",
  "4. Feature Status (Stub Detection)",
  "5. Documentation Coverage",
];

export function printVerifySections(result: VerifyResult): void {
  const sections = [
    result.section1,
    result.section2,
    result.section3,
    result.section4,
    result.section5,
  ];

  for (let i = 0; i < sections.length; i++) {
    if (sections[i].length > 0) {
      console.log(`\n=== ${SECTION_TITLES[i]} ===\n`);
      for (const line of sections[i]) console.log(formatLine(line));
    }
  }
}

// -- Print discover sections --------------------------------------------------

export function printDiscoverSections(sections: { name: string; results: LineResult[] }[]): void {
  for (const section of sections) {
    console.log(`\n=== ${section.name} ===\n`);
    for (const line of section.results) console.log(formatLine(line));
  }
}
