# Aktueller Fahrplan

**Stand: 18.11.2026**

Dieses Dokument beschreibt den im Repository vorhandenen Stand und realistische nächste Schritte. „Erledigt“ bezieht sich auf implementierte Funktionen, nicht auf eine fachliche, rechtliche oder externe Zertifizierung. Es werden hier keine neuen Datenquellen, Werte oder bereits laufenden Arbeiten vorausgesetzt.

## Erledigt – im Repository umgesetzt

- **Lokale App und ÖKOBAUDAT-Katalog:** Start über `Start-App.bat`; PowerShell-Backend mit Health-, Such- und Detailrouten. Der Server liest die offizielle Downloadseite aus, lädt den verlinkten CSV-Export, validiert erwartete Felder und filtert auf EN 15804+A2 / A1–A3. Cache und Provenienz/Manifest liegen lokal; ein vorhandener Cache kann bei fehlgeschlagener Aktualisierung mit Warnhinweis genutzt werden.
- **Suche, Details und Vergleich:** lokaler Suchindex, begrenzte deutsche/englische Materialaliasliste, Datensatzdetails, Gültigkeits- und Quellenstatus sowie relative GWP-Gruppierung kompatibler Datensätze. Eine Materialalternative ist damit nicht als technisch gleichwertig bestätigt.
- **Lokale Nutzerimporte:** UTF-8-CSV-Vorschau, Größen- und Zeilenlimits, Feld- und Einheitenvalidierung, Duplikat-/Konfliktbehandlung, explizite Rechtebestätigung, getrennte lokale Speicherung und Entfernung. Importierte Rechte werden als Nutzerangabe, nicht als unabhängige Prüfung ausgewiesen. Pages enthält diese Funktion nicht.
- **IFC-Auswertung:** Browserparser für IFC2x3 und IFC4, Textdateien bis 100 MB, direkte bzw. eindeutig geerbte Materialzuordnung und explizite IFC-Element-Quantitäten. Nicht auflösbare, mehrdeutige oder nicht quantifizierbare Bauteile bleiben sichtbar und ohne erfundenen Beitrag. Die vollständige Bauteilliste lässt sich zentral mit „Alle Bauteile einklappen/ausklappen“ aus- und einblenden; Zähler, Status und A1–A3-Teilbilanz bleiben dabei sichtbar und Auswahl, IFC-Daten sowie Berechnung erhalten. Die separaten Detail-Schaltflächen betreffen nur Zuordnungs- und Mengendetails. Native PLN-Dateien und automatische Schichtaufteilung sind nicht unterstützt.
- **GitHub Pages:** statischer Build mit synthetischen Beispieldaten, relativen Assetpfaden und ohne Live-Backend, Live-Suche oder Upload. Der Workflow baut und veröffentlicht über GitHub Actions.
- **Vorhandene gezielte Tests:** `tests\ifc.test.mjs`, `tests\ifc-disclosure.test.mjs`, `tests\hero.test.mjs`, `tests\public-sources.test.mjs`, `tests\pages-demo.test.mjs`, `tests\cursor.test.mjs`, `tests\search.test.ps1` und `tests\imports.test.ps1`. Die Tests prüfen unter anderem Parsergrenzen, Mengen/Einheiten, das Ein-/Ausblenden der gesamten IFC-Bauteilliste bei erhaltenen Auswahlen und Ergebnissen, Imports, Provenienz und Demo-Isolation; sie ersetzen keine Validierung an realen Projektmodellen oder Lizenzprüfung.

## In Prüfung – Grenzen, vor weiterer Ausweitung

- **Quellenrechte und Aktualität:** Die offizielle ÖKOBAUDAT-CSV ist der einzige automatisch angebundene externe Katalog. Öffentlicher Zugriff belegt nicht pauschal Speicher- oder Weitergaberechte. Die App nutzt den offiziellen CSV-Export, keine direkte Datenaustauschschnittstelle. Jede künftige Verwendung oder Veröffentlichung von Datensatzinhalten braucht eine konkrete Rechteprüfung.
- **Hersteller-Treffer:** Ein Treffer in ÖKOBAUDAT bleibt ein ÖKOBAUDAT-Datensatz; daraus folgt weder ein direkter Herstellerfeed noch bestätigte Produktidentität. Andere Anbieter, registrierungspflichtige Angebote und Quellen mit ungeklärtem Maschinenzugriff oder Lizenzstatus sind nicht integriert.
- **IFC-Eignung und Datenqualität:** Labels und Teilbilanz beruhen auf ausgelesenen Zuordnungen, Mengen, Datensatzgültigkeit und verfügbarer Raumstruktur. Sie bestätigen weder Modellvollständigkeit noch Produktgleichheit, funktionale Gleichwertigkeit oder eine geprüfte Gebäudeökobilanz. Kategorie-Vorschläge bleiben manuelle, nicht produktspezifische Zuordnungen.
- **Statische Demo:** synthetische Werte demonstrieren nur Bedienabläufe. Sie dürfen nicht als reale Materialkennwerte interpretiert werden. Pages stellt weder dauerhafte Datenspeicherung noch Upload- oder Suchbackend bereit.

## Offen – nächste Schritte

1. **ÖKOBAUDAT-Releasewechsel belastbar absichern:** bei künftigen CSV-Schema- oder Releaseänderungen die automatische Auswahl, Validierung, Provenienz und Cache-Fallback anhand versionsbezogener Testdaten prüfen. Bis dahin keine feste Release-ID oder Aktualität versprechen.
2. **IFC-Verhalten mit repräsentativen, zulässig nutzbaren Modellen validieren:** bekannte Mengen, Einheiten, Raumstruktur und Zuordnungen mit unabhängigen Erwartungen vergleichen; fehlende oder mehrdeutige Fälle als nicht quantifizierbar belassen. Keine Modelluploads oder Testdateien mit vertraulichen Projektinhalten veröffentlichen.
3. **Materialalternativen fachlich begründen:** vor einer weitergehenden Bewertung funktionale Einheit, technische Anforderungen, vollständige Bauteilaufbauten und passende Vergleichsdatensätze festlegen. Bis dahin keine GWP-Vorteile oder Gleichwertigkeit aus einzelnen Materialdatensätzen ableiten.
4. **Weitere Quellen nur einzeln und nach Prüfung erwägen:** Anbieteridentität, schlüsselfreien offiziellen Zugang, maschinenlesbares Format, Datenstand, Methodik und konkrete Abruf-/Speicher-/Anzeige-/Weitergaberechte dokumentieren. Ohne belegte Freigabe weder Feed noch Zahlen integrieren; keine Zugangsbeschränkungen umgehen.
5. **Dokumentation und Demo aktuell halten:** Startvoraussetzungen, lokale Speicherung, Grenzen synthetischer Pages-Daten und den Workflow gemeinsam mit relevanten Änderungen aktualisieren. Nur Änderungen an Code/Build/Workflow gegen die passenden Tests prüfen; Dokumentationsänderungen allein haben derzeit keinen eigenen Test.

## Nicht Teil des aktuellen Umfangs

- Eine vollständige Herstellerdatenbank, automatische Websuche oder direkte ÖKOBAUDAT-Schnittstellenintegration.
- Verteilung realer Katalogdaten in GitHub Pages, Uploads aus Pages oder Synchronisierung lokaler Nutzerimporte.
- Automatische Gleichsetzung ähnlicher Produktnamen, Erzeugung fehlender GWP-Werte oder eine zertifizierte Gebäudeökobilanz.
- Umgehung von API-Schlüsseln, Registrierung, Lizenz- oder sonstigen Zugangsvoraussetzungen.
