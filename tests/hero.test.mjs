import test from "node:test";
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";

test("hero has no laptop motif and includes exactly one additional tree", async () => {
  const svg = await readFile(new URL("../public/hero-landscape.svg", import.meta.url), "utf8");
  assert.doesNotMatch(svg, /M644 348h48/);
  assert.equal((svg.match(/<path d="M\d+ \d+V\d+m-/g) || []).length, 11);
});
