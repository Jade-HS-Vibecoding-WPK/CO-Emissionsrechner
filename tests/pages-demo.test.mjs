import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { mkdtemp, readFile, rm } from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import test from "node:test";
import { fileURLToPath } from "node:url";
import { getDemoDetail, searchDemoData } from "../public/demo-data.mjs";

const repositoryRoot = fileURLToPath(new URL("../", import.meta.url));

test("demo search returns only explicitly marked synthetic records", () => {
  const result = searchDemoData("concrete");
  assert.equal(result.count, 3);
  assert.match(result.source, /DEMO.*keine Quelle/);
  for (const group of result.groups) {
    for (const item of group.PeerGroups[0].Items) {
      assert.match(item.Name, /^DEMO-Beispiel:/);
      assert.equal(item.Url, "");
      assert.equal(item.Rating.Rank, null);
    }
  }
  assert.equal(searchDemoData("does-not-exist").count, 0);
});

test("demo detail cannot imply a sourced or verified environmental result", () => {
  const item = searchDemoData("Beton").groups[0].PeerGroups[0].Items[0];
  const detail = getDemoDetail(item.Id, "Außenwand / Fassade");
  assert.equal(detail.item.Url, "");
  assert.equal(detail.comparison.comparable, false);
  assert.match(detail.comparison.reason, /ohne Quelle/);
  assert.match(detail.item.ValidUntil, /nicht geprüft/);
  assert.match(detail.source, /synthetische Beispieldaten/);
  assert.throws(() => getDemoDetail("unknown"), /Unbekanntes Demo-Beispiel/);
});

test("Pages build injects demo mode and retains relative static assets", async () => {
  const outputDirectory = await mkdtemp(path.join(os.tmpdir(), "co-pages-demo-"));
  try {
    execFileSync(process.execPath, [
      path.join(repositoryRoot, "scripts", "build-pages.mjs"),
      outputDirectory,
    ], { cwd: repositoryRoot, stdio: "pipe" });

    const html = await readFile(path.join(outputDirectory, "index.html"), "utf8");
    const app = await readFile(path.join(outputDirectory, "app.js"), "utf8");
    const imports = await readFile(path.join(outputDirectory, "ifc.mjs"), "utf8");
    const styles = await readFile(path.join(outputDirectory, "styles.css"), "utf8");
    const cursor = await readFile(path.join(outputDirectory, "tree-cursor.svg"), "utf8");
    assert.match(html, /window\.__PAGES_DEMO__\s*=\s*true/);
    assert.match(html, /href="\.\/styles\.css"/);
    assert.match(html, /src="\.\/app\.js"/);
    assert.match(html, /src="\.\/hero-landscape\.svg"/);
    assert.doesNotMatch(html, /id="local-import"|user-import-file|\/api\/import/);
    assert.match(app, /from "\.\/ifc\.mjs"/);
    assert.doesNotMatch(html, /(?:href|src)="\/(?:styles|swiss|app|ifc|hero)/);
    assert.match(app, /pagesDemo\s*\?\s*searchDemoData/);
    assert.match(imports, /export function parseIfcText/);
    assert.match(styles, /\.\/tree-cursor\.svg/);
    assert.match(cursor, /<svg/);
  } finally {
    await rm(outputDirectory, { recursive: true, force: true });
  }
});
