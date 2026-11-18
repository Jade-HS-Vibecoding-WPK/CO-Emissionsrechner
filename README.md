# CO-Emissionsrechner

Ein Entwurfswerkzeug zur Suche und zum Vergleich von Baustoff-Datensätzen sowie zur lokalen Auswertung von IFC-Mengen. Die Anwendung ist in zwei Varianten verfügbar: als lokale Windows-App mit PowerShell-Backend und Live-ÖKOBAUDAT-CSV-Katalog oder als statische GitHub-Pages-Demo mit synthetischen Beispieldaten.

## Start und Voraussetzungen

### Lokale Windows-App

Voraussetzung ist Windows mit Windows PowerShell. `Start-App.bat` starten; die App öffnet sich unter <http://127.0.0.1:8765/>. Das Backend bindet ausschließlich an die Loopback-Adresse. Für einen neuen oder zu aktualisierenden Katalog benötigt es Internetzugriff auf die offizielle ÖKOBAUDAT-Downloadseite und den dort verlinkten CSV-Export. Ist der Download nicht verfügbar, kann ein vorhandener Cache mit sichtbarem Warn-/Datenstandstatus weiterverwendet werden.

Das Backend stellt unter anderem `/api/health`, `/api/search` und `/api/detail` sowie lokale `/api/import/*`-Routen bereit. Der offizielle CSV-Cache, Metadaten und Suchmanifest liegen unter `%LOCALAPPDATA%\CO-Emissionsrechner\`; bestätigte Nutzerimporte liegen getrennt in `user-imports.json`.

### Statische GitHub-Pages-Demo

Die veröffentlichte Demo ist unter <https://jade-hs-vibecoding-wpk.github.io/CO-Emissionsrechner/> erreichbar. `.github/workflows/pages.yml` testet die statische Demo, baut sie mit `scripts/build-pages.mjs` aus `public\` und veröffentlicht das Artefakt über GitHub Pages. Der Workflow läuft bei passenden Änderungen auf `main` oder manuell über `workflow_dispatch`; für das Repository muss Pages mit „GitHub Actions“ eingerichtet sein.

Pages enthält ausschließlich ausdrücklich synthetische Beispieldaten. Es gibt dort kein PowerShell-Backend, keine Live-ÖKOBAUDAT-Suche und keinen CSV-Upload. Auch die IFC-Rechenvorschau verwendet nur synthetische Demo-Werte und ist keine reale Bilanz. Der Pages-Build entfernt den lokalen Importbereich. Die Demo speichert weder Uploads noch Importdaten oder eine gemeinsame Datenbank.

## Datenquellen und Grenzen

- **Automatisch ausgewertete Quelle:** Der lokale Server liest die offizielle ÖKOBAUDAT-Downloadseite aus und wählt den dort veröffentlichten CSV-Export samt Release und Datenstock-ID aus. Er validiert den Export und wertet Datensätze nach EN 15804+A2, Modul A1–A3 aus. Cache, Abrufzeit, Release und Warnungen werden in der Provenienz ausgewiesen. Die dokumentierte ÖKOBAUDAT-Datenaustauschschnittstelle wird nicht direkt angesprochen; die App nutzt den offiziellen CSV-Download.
- **Herstellersuche:** Herstellernamen können Treffer in den geladenen ÖKOBAUDAT-Datensätzen auffindbar machen. Das sind weiterhin ÖKOBAUDAT-Datensätze, keine automatisch angebundenen Herstellerfeeds. Namen und Schreibvarianten werden nicht ohne Beleg gleichgesetzt; etwa „Wieneberger“ ist kein bestätigtes Alias für „Wienerberger“ und „Rockwoll“ keines für „ROCKWOOL“.
- **Manuelle Quellenhinweise:** WECOBIS ist als qualitativer Materialkontext verlinkt; veröffentlichte IBU-EPDs können manuell geprüft werden. Keine der beiden Quellen wird automatisch numerisch ausgelesen. IBU.data-XML-Downloads mit Registrierung sowie allgemeine Websuche sind nicht integriert.
- **Nicht integrierte Anbieter:** KBOB, eco-bau, IPB, ProBas, Global EPD, ECO EPD, Ecoinvent, GaBi, Climatiq, DEFRA, DGNB Navigator, BMWSB, BMWE, BMUKN und weitere Herstellerquellen liefern der App derzeit keine automatischen Zahlen. Zugriff ohne Schlüssel/Registrierung, maschinenlesbares Format und Rechte für Abruf, Speicherung, Anzeige oder Weitergabe sind nicht für jede Quelle geklärt; „IPB“ ist zudem nicht eindeutig identifiziert. Zugangsbeschränkungen und Lizenzbedingungen werden nicht umgangen. Produktkataloge oder öffentliche Produktseiten allein belegen keinen Ökobilanzwert.

ÖKOBAUDAT ist öffentlich zugänglich; eine pauschale Lizenz zur Weitergabe ihrer Inhalte wird nicht behauptet. Die App weist den ungeprüften Weitergabestatus aus und kopiert den Katalog weder ins Repository noch ins Pages-Bundle. Datenstand, Gültigkeit, Bezugsmenge, Einheit und Quelle eines Datensatzes bleiben relevant; ein Suchtreffer ist kein Nachweis der Produkt- oder Funktionsgleichheit.

## IFC-Import und Auswertung

Der Browser verarbeitet IFC-STEP-Textdateien im Format IFC2x3 oder IFC4 bis 100 MB. Native Archicad-PLN-Dateien werden nicht unterstützt. Die ausgewählte IFC-Datei wird nicht an das Backend oder an GitHub Pages hochgeladen.

Der Parser verwendet direkte Materialzuordnungen; eine Materialzuordnung am Bauteiltyp wird nur verwendet, wenn dem Bauteil keine direkte Zuordnung vorliegt. Mehrere, nicht lesbare oder geschichtete Materialzuordnungen bleiben mehrdeutig; Schichten werden nicht aufgeteilt. Bauteile bleiben auch ohne Material, explizite Menge oder Katalogtreffer sichtbar. Mengen stammen aus IFC-Element-Quantitäten und werden nur bei eindeutiger, unterstützter Einheit verwendet. Direkte Namenssuche und begrenzte Materialaliasse können Treffer liefern; Kategorie-Vorschläge sind ausdrücklich nur Vorschläge und müssen manuell gewählt werden.

Ein Beitrag wird nur aus einer passenden expliziten IFC-Menge und einem gültigen Datensatz berechnet, wenn Dimension, Einheit, Bezugsmenge, Standard und Module zusammenpassen. Abgelaufene oder in der Gültigkeit unbekannte Datensätze sowie nicht auflösbare Positionen bleiben ohne Beitrag; es werden keine Mengen oder GWP-Werte erfunden. Die Summe ist eine A1–A3-Teilbilanz, keine geprüfte Gebäudebilanz. Die Datenqualitätsanzeige bewertet unter anderem Zuordnung, Menge, Gültigkeit und IFC-Raumstruktur; sie ist weder eine statistische Unsicherheitsspanne noch ein Vollständigkeitsnachweis.

Die relativen Labels „gut“, „mittel“ und „schlecht“ gelten nur innerhalb ausreichend großer, gültiger und kompatibler ÖKOBAUDAT-Vergleichsgruppen. Sie sind keine absolute Umweltbewertung und bestätigen keine technische Gleichwertigkeit. Der bedingte Alternativen-Check ist kein Nachweis einer funktionalen Materialsubstitution. Solarreflexion wird, falls im Datensatz vorhanden, mit Einheit und Messangaben separat angezeigt und nicht in GWP eingerechnet.

## Lokale CSV-Importe und Datenschutz

Nur die lokale App akzeptiert UTF-8-CSV-Dateien (maximal 5 MiB und 10.000 Zeilen je Datei; lokal höchstens 25.000 Datensätze). Vorschau, Zeilenvalidierung, Duplikat-/Konflikterkennung und eine ausdrückliche Rechtebestätigung sind erforderlich. Die Vorlage enthält Quelle, ID, Version, Produkt, Einheit, Bezugsmenge, GWP, Norm/Module, Gültigkeit und Quellen- sowie Lizenzhinweis. GWP wird nur für EN 15804+A2 / A1–A3 und unterstützte Einheiten verwendet; Solarreflexion benötigt außerdem Messmethode und Wellenlängenbereich. Imports bleiben als Nutzerimporte gekennzeichnet und können entfernt werden.

Die angegebene Herkunft und Rechtebestätigung werden nicht unabhängig geprüft. Importiere nur Daten, die du lokal speichern und verwenden darfst. Die CSV wird vom Browser an das lokale Loopback-Backend übertragen und dort in `%LOCALAPPDATA%\CO-Emissionsrechner\user-imports.json` gespeichert; das ist kein geschützter Mehrbenutzerspeicher. IFC-Dateien bleiben im Browser. Auf Pages gibt es weder Import noch serverseitige Speicherung.

## Tests

Für die JavaScript-Tests wird Node.js benötigt; `tests\search.test.ps1` und `tests\imports.test.ps1` benötigen Windows PowerShell:

```powershell
node --test tests\ifc.test.mjs tests\hero.test.mjs tests\public-sources.test.mjs tests\pages-demo.test.mjs tests\cursor.test.mjs
powershell -NoProfile -File tests\search.test.ps1
powershell -NoProfile -File tests\imports.test.ps1
```

Die Tests decken unter anderem IFC-Parsing und -Berechnung, lokale Suche und CSV-Import, Quellenhinweise, Cursor sowie synthetischen Pages-Build ab. Der Pages-Workflow führt die JavaScript-Tests für Pages, IFC, Quellen und Cursor aus.
