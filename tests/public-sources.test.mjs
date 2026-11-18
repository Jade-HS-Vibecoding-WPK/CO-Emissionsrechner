import test from "node:test";
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";

test("public source links are guidance only and do not imply automatic GWP data", async () => {
  const [html, app, server] = await Promise.all([
    readFile(new URL("../public/index.html", import.meta.url), "utf8"),
    readFile(new URL("../public/app.js", import.meta.url), "utf8"),
    readFile(new URL("../server.ps1", import.meta.url), "utf8"),
  ]);

  assert.match(html, /https:\/\/www\.wecobis\.de\/index\.php\?id=16043/);
  assert.match(html, /https:\/\/ibu-epd\.com\/veroeffentlichte-epds\//);
  assert.match(html, /qualitativer Kontext.*nicht als GWP-Faktor/);
  assert.match(html, /IBU\.data-XML-Downloads mit Registrierung werden nicht verwendet/);
  assert.match(html, /kein zulässiger öffentlicher Suchendpunkt ohne Login\/API-Schlüssel/);
  assert.match(html, /KBOB, eco-bau, IPB, ProBas, Global EPD, ECO EPD, Ecoinvent, GaBi, Climatiq, DEFRA, DGNB Navigator/);
  assert.match(html, /maschinenlesbares Format sowie Rechte für Abruf/);
  assert.match(html, /Röben, Wieneberger.*Rockwoll.*one Mineral.*Knauf/);
  assert.match(html, /nicht als separate Herstellerfeeds integriert/);
  assert.match(html, /Öffentliche Produktseiten allein belegen weder einen Ökobilanzwert/);
  assert.match(html, /Lokale Datenimporte/);
  assert.match(html, /GitHub Pages stellt weder Upload noch lokale Datenbank bereit/);
  assert.match(html, /SourceRecordId, Version, ProductName, Category/);
  assert.match(app, /Weitere Quellen zur manuellen Prüfung/);
  assert.match(app, /kein automatischer Zahlenwert übernommen/);
  assert.match(app, /matchType === "category-suggestion"/);
  assert.match(app, /Nutzungs- und Weitergaberechte nicht unabhängig verifiziert/);
  assert.match(app, /!calculation \? getPublicSourceHints\(\) : ""/);
  assert.match(app, /Solarreflexion \/ Reflexionsgrad/);
  assert.match(app, /\/api\/import\/preview/);
  assert.match(app, /\/api\/import\/confirm/);
  assert.match(app, /Nutzungsrechte vom Importierenden bestätigt, nicht unabhängig verifiziert/);
  assert.match(server, /function ConvertFrom-UserCatalogCsv/);
  assert.match(server, /function Confirm-UserImport/);
  assert.match(server, /function Remove-UserImportBatch/);
  assert.match(server, /SolarReflectanceWavelength/);
  assert.match(server, /UserImportMaxBytes = 5 \* 1024 \* 1024/);
  assert.match(server, /'\/demo-data\.mjs'\s*=\s*'demo-data\.mjs'/);
  assert.match(server, /'\/tree-cursor\.svg'\s*=\s*'tree-cursor\.svg'/);
  assert.match(server, /-or \$path -eq '\/demo-data\.mjs'/);
  assert.match(server, /-or \$path -eq '\/tree-cursor\.svg'/);
});
