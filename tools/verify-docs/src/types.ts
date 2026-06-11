// ============================================================================
// types.ts -- Type definitions for verify-docs engine
// ============================================================================

/** A single check: count something in code, compare with README */
export interface CheckConfig {
  /** Human-readable name for output */
  name: string;
  /** Where to get the actual value from. Built-in: "file:...", "glob:...", "git:HEAD". Custom: "custom:..." */
  source: string;
  /** Regex pattern to count in the source file (only for file: source). All matches are counted. */
  countPattern?: string;
  /** Exclude matches that contain any of these strings */
  countExclude?: string[];
  /** Exclude file paths that contain any of these strings (only for glob: source) */
  exclude?: string[];
  /** Regex to extract the number from README. Must have a capturing group (\\d+). null = info-only. */
  readmePattern: string | null;
  /** Allowed difference between actual and readme. 0 = exact match. Use for commit counts etc. */
  tolerance?: number;
  /** If true, only print the value -- don't compare with README */
  infoOnly?: boolean;
}

/** Cross-repo consistency check: compare a value from a sibling repo with an expected value */
export interface CrossRepoConfig {
  /** Human-readable name for output */
  name: string;
  /** Relative path to sibling repo from project root (e.g. "../other-repo") */
  repo: string;
  /** File path within the sibling repo. Prefix with "file:" for clarity. */
  source: string;
  /** How to extract a number from the file:
   *  - "extract:PATTERN" -- extract first match of (\\d+) group from PATTERN
   *  - "PATTERN" -- count all regex matches */
  filePattern: string;
  /** Name of a Section 1 check to compare against (must match a CheckConfig.name) */
  matchAgainst?: string | null;
  /** Regex to extract expected value from README (alternative to matchAgainst) */
  readmePattern?: string | null;
  /** Allowed difference between values */
  tolerance?: number;
}

/** Root config: what to verify and where to find it */
export interface VerifyConfig {
  /** Path to the document to verify (relative to project root). Usually "README.md" */
  readme: string;
  /** Section 1 checks: code vs README */
  checks: CheckConfig[];
  /** Section 2 checks: cross-repo consistency (optional) */
  crossRepo?: CrossRepoConfig[];
}

/** Overall verification result */
export interface VerifyResult {
  /** true if all checks passed */
  passed: boolean;
  /** Number of mismatches found */
  errors: number;
  /** Results from Section 1 (code vs README) */
  section1: LineResult[];
  /** Results from Section 2 (cross-repo consistency) */
  section2: LineResult[];
}

/** A single output line */
export interface LineResult {
  /** Status: OK = match, ERR = mismatch, info = info-only, skip = skipped, ci = skipped in CI */
  status: "OK" | "ERR" | "info" | "skip" | "ci";
  /** Check name */
  name: string;
  /** Human-readable detail string */
  detail: string;
}

/** Source resolver function type */
export type SourceResolver = (source: string, root: string) => number | null;
