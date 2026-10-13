// ============================================================================
// feature-status.test.ts -- regression tests for Section 4 (feature status)
//
// Regression: "documented as working" + "implementation file exists" was
// reported as OK / "Implemented", even when the implementation file contained
// nothing but a TODO stub. File presence is not proof of implementation, so
// the result must either detect the stub or say plainly that only presence
// was checked.
// ============================================================================

import { describe, test, expect, afterEach } from "bun:test";
import { verifySection4 } from "../src/verify-section4.js";
import type { FeatureStatusConfig } from "../src/types.js";
import { FixturePool } from "./_helpers.js";

const pool = new FixturePool();
afterEach(() => pool.drain());

const STUB_CODE = "// TODO: not implemented yet\nexport function feature() {}\n";
const REAL_CODE =
  'export function feature(): string {\n  return "computed";\n}\n';

function config(implFile: string): FeatureStatusConfig[] {
  return [
    {
      name: "Feature X",
      docFile: "README.md",
      stubPatterns: ["TODO", "not implemented", "stub"],
      // NOTE: "implemented" alone would also match inside "not implemented",
      // so the patterns here are word-anchored phrases.
      implementedPatterns: ["is working", "is complete"],
      implementationFiles: [implFile],
    },
  ];
}

describe("doc claims working", () => {
  test("TODO-only implementation file is an error", () => {
    const dir = pool.make({
      "README.md": "# App\n\nFeature X is working.\n",
      "src/feature.ts": STUB_CODE,
    });

    const { results, errors } = verifySection4(config("src/feature.ts"), dir);

    expect(errors).toBe(1);
    expect(results[0].status).toBe("ERR");
  });

  test("real implementation passes but is labelled presence-only", () => {
    const dir = pool.make({
      "README.md": "# App\n\nFeature X is working.\n",
      "src/feature.ts": REAL_CODE,
    });

    const { results, errors } = verifySection4(config("src/feature.ts"), dir);

    expect(errors).toBe(0);
    expect(results[0].status).toBe("OK");
    expect(results[0].detail).toContain("presence check only");
    expect(results[0].detail).not.toMatch(/^Implemented:/);
  });
});

describe("doc claims stub", () => {
  test("implementation file present is an error", () => {
    const dir = pool.make({
      "README.md": "# App\n\nFeature X is a stub, not implemented.\n",
      "src/feature.ts": REAL_CODE,
    });

    const { errors } = verifySection4(config("src/feature.ts"), dir);

    expect(errors).toBe(1);
  });

  test("honest stub with no implementation file passes", () => {
    const dir = pool.make({
      "README.md": "# App\n\nFeature X is a stub, not implemented.\n",
    });

    const { results, errors } = verifySection4(config("src/feature.ts"), dir);

    expect(errors).toBe(0);
    expect(results[0].status).toBe("OK");
  });
});

describe("doc claims working but nothing exists", () => {
  test("is an error", () => {
    const dir = pool.make({ "README.md": "# App\n\nFeature X is working.\n" });

    const { errors } = verifySection4(config("src/feature.ts"), dir);

    expect(errors).toBe(1);
  });
});
