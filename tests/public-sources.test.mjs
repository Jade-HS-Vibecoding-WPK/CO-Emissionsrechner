import test from "node:test";
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";

test("public source links are guidance only and do not imply automatic GWP data", async () => {
  const [html, app] = await Promise.all([
    readFile(new URL("../public/index.html", import.meta.url), "utf8"),
    readFile(new URL("../public/app.js", import.meta.url), "utf8"),
  ]);

  assert.match(html, /https:\/\/www\.wecobis\.de\/index\.php\?id=16043/);
  assert.match(html, /https:\/\/ibu-epd\.com\/veroeffentlichte-epds\//);
  assert.match(html, /qualitativer Kontext.*nicht als GWP-Faktor/);
  assert.match(html, /IBU\.data-XML-Downloads mit Registrierung werden nicht verwendet/);
  assert.match(html, /kein zulässiger öffentlicher Suchendpunkt ohne Login\/API-Schlüssel/);
  assert.match(app, /Weitere Quellen zur manuellen Prüfung/);
  assert.match(app, /kein automatischer Zahlenwert übernommen/);
  assert.match(app, /!calculation \? getPublicSourceHints\(\) : ""/);
});
