import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

test("tree cursor uses a small hero-matching asset with native fallbacks", async () => {
  const [cursor, styles] = await Promise.all([
    readFile(new URL("../public/tree-cursor.svg", import.meta.url), "utf8"),
    readFile(new URL("../public/styles.css", import.meta.url), "utf8"),
  ]);

  assert.match(cursor, /width="24" height="24"/);
  assert.match(cursor, /stroke="#527b59"/);
  assert.match(styles, /cursor:\s*url\("\.\/tree-cursor\.svg"\)\s+12\s+20,\s*auto/);
  assert.match(styles, /cursor:\s*url\("\.\/tree-cursor\.svg"\)\s+12\s+20,\s*pointer/);
  assert.match(styles, /input,\s*textarea,\s*\[contenteditable="true"\]\s*\{\s*cursor:\s*text;/);
  assert.match(styles, /@media \(hover:\s*none\)/);
});
