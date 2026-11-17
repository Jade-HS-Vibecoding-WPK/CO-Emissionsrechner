# Plan: eigene, nachvollziehbare Materialdatenbank

**Status:** Die erste lokale ÖKOBAUDAT-Katalogetappe ist umgesetzt. Weitere Quellen bleiben ausgesetzt, bis Zugriff und Nutzungsrechte bestätigt sind.

## Ziel und Grenzen

Die Website soll einen lokalen, durchsuchbaren Materialkatalog aus rechtmäßig nutzbaren, öffentlich verfügbaren Ökobilanzdaten aufbauen. Der Katalog soll passende Baustoffdatensätze leichter finden und Herkunft, Datenstand sowie Vergleichbarkeit erhalten. Die Oberfläche und bestehenden Funktionen bleiben grundsätzlich bestehen.

„Alle Materialien“ kann keine Datenbank garantieren: Quellen decken unterschiedliche Produkte, Länder, Einheiten und Lebenszyklusmodule ab und ändern ihre Inhalte. Es werden daher Abdeckung, Aktualität und fehlende Werte sichtbar gemacht. Kein Treffer bleibt ein fehlender/unberechneter Beitrag; es gibt weder erfundene Werte noch automatisch erzeugte LLM-Schätzungen.

Öffentliche Erreichbarkeit bedeutet nicht automatisch, dass Datensätze dauerhaft kopiert, in eine eigene Datenbank überführt oder weiterveröffentlicht werden dürfen. Ein Import erfolgt erst, wenn Quelle, technische Zugriffsmethode und erlaubte Speicherung/Nutzung überprüft sind. Keine geschützten Zugriffe, Registrierungsskripte, undokumentierten Scrapes oder unzulässigen Massendownloads.

## Geprüfter Ist-Zustand (17.11.2026)

- Der Worktree ist auf `lr20261116-transparente-hero-landschaft`. Bestehende Änderungen in App, Tests, README und PLAN.md sind vorhanden und bleiben erhalten; diese Planrevision soll nur `PLAN.md` ändern.
- `server.ps1` ist ein lokaler PowerShell-HTTP-Server. Er stellt `/api/health`, `/api/search` und `/api/detail` bereit. Die Oberfläche verwendet diese Routen; es gibt weder eine SQL-Datenbank noch eine allgemeine Websuchintegration oder einen konfigurierten Suchanbieter.
- Die ÖKOBAUDAT-CSV wird von der offiziellen Downloadseite aufgelöst, geprüft und unter `%LOCALAPPDATA%\CO-Emissionsrechner\oekobaudat.csv` zwischengespeichert. Die vorhandene Datei war bei der Prüfung 52.047.093 Bytes groß. Das Verzeichnis liegt außerhalb des Repositories. Eine Metadaten-Sidecar-Datei erfasst Quelle, Datenstand, Datenstock-ID, URL und Abrufzeit; Such- und Detailantworten ergänzen Quellenprovenienz. Der Server lädt die Datensätze in den Arbeitsspeicher.
- Der aktuelle offizielle CSV-Link verweist auf ÖKOBAUDAT `2024-III` / Datenstock `bca3670a-8dcf-44d0-be1f-0633d9ba1a75`. Die Downloadseite sagt, dass der letzte generische Datenbestand am 02.10.2024 aktualisiert wurde. Die tägliche Aktualisierbarkeit eines Releases ist deshalb nicht mit täglichen neuen Materialdaten gleichzusetzen.
- Die ÖKOBAUDAT-Website beschreibt ihre Daten als kostenfrei zugänglich und nennt eine standardisierte Datenaustauschschnittstelle. Für diese App ist weiterhin kein konkreter, dokumentierter Lese-Endpunkt ermittelt; vorhanden ist der offizielle CSV-Export. Die öffentliche Seite ist kein pauschaler Nachweis einer Open-Data-Lizenz oder unbegrenzten Weiterverbreitung. Nutzungsrechte für lokalen Import, abgeleitete Indexierung, Anzeige und etwaige Weitergabe sind vor einer Katalogverteilung gesondert zu prüfen. ÖKOBAUDAT weist außerdem darauf hin, dass ihre Datenbasis nicht zur Erstellung von Produktökobilanzen zugelassen ist.
- WECOBIS ist in der App ein Kontextlink; ein zulässiger maschinenlesbarer GWP-Feed ist nicht integriert oder bestätigt. IBU.data stellt XML-EPDs nach Registrierung bereit. Laut veröffentlichter IBU-Nutzungsbedingungen sind Downloads für die Gebäudeökobilanzierung nach Registrierung kostenfrei; weitergehende kommerzielle Nutzung und Weitergabe an Dritte erfordern eine gesonderte Lizenz. Eine allgemeine öffentliche Schnittstelle ist nicht bestätigt. Daher derzeit kein automatischer IBU-Import.
- Die Suche erweitert bekannte Materialbegriffe mit einer kleinen deterministischen DE/EN-Aliasliste. Die vorhandenen fokussierten Tests liegen in `tests/search.test.ps1`; JavaScript-Tests prüfen IFC und öffentliche Quellen. Es gibt keine zusätzliche Datenbank- oder Suchanbieter-Abhängigkeit.
- Im Repository-Root wurde keine `.gitignore` gefunden. Der Datenkatalog soll deshalb nicht im Repository oder im auslieferbaren App-Ordner abgelegt werden.

## Quellen- und Rechteprüfung vor jedem Import

Für jede neue Quelle wird vor technischer Integration ein Eintrag im Quellenregister angelegt:

| Prüfpunkt | Erforderlicher Nachweis |
|---|---|
| Herausgeber und Originalquelle | Offizielle Download-/API-Seite und identifizierbare Originaldatensätze |
| Zugang | Dokumentierter öffentlicher Endpunkt oder erlaubter manueller Import; keine Umgehung von Login, Rate-Limits oder Zugriffsschutz |
| Lizenz/Nutzung | Erlaubnis für automatisierten Abruf, lokale Speicherung, Indexierung, Anzeige/Attribution und gegebenenfalls Weitergabe; Bedingungen getrennt prüfen |
| Aktualisierung | Version/Datenstand, Updatefrequenz und stabiler Datensatzschlüssel |
| Eignung | GWP-Indikator, Einheit/Bezugsmenge, Module, Methodik und Produkt-/Materialbezug auslesbar |
| Umfang | Anzahl/Größe der Datensätze, Abruflimits, Speicherbedarf und Ausfallverhalten |

Vorgesehene Reihenfolge:

1. **ÖKOBAUDAT:** Bestehenden offiziellen CSV-Import als erste Quelle erhalten. Vor persistenter Neuverteilung bzw. Einbettung des vollständigen Exports die konkreten Nutzungsrechte prüfen. Die Daten dürfen nicht als produktbezogene EPD oder Produktökobilanz ausgegeben werden.
2. **WECOBIS:** Nur Kontext, Materialbezeichnungen und Original-Links, sofern das ohne automatisiertes Kopieren zulässig ist. Keine GWP-Faktoren aus qualitativen Texten ableiten.
3. **IBU und öffentliche EPDs:** IBU.data nicht ohne Registrierung, Nutzungsfreigabe und ausdrückliche Berechtigung für automatisierten Zugriff/Weitergabe integrieren. Einzelne frei zugängliche EPDs nur verwenden, wenn Zugriff und Verarbeitung erlaubt sind und die Zahlen vollständig maschinenlesbar und vergleichbar sind.
4. **Hersteller, EPD International, UBA/ProBas, Forschung und weitere öffentliche Quellen:** Kein Feed ist allein wegen eines öffentlichen Webauftritts freigegeben. Je Quelle erst offizielle technische Verfügbarkeit, Lizenz, Abrufgrenzen und Feldqualität belegen; ohne Bestätigung nur als manueller Quellenlink führen.
5. **Allgemeine Websuche:** Aktuell nicht konfiguriert. Eine spätere Integration benötigt einen tatsächlich erreichbaren, zulässigen Anbieter/Endpunkt samt Schlüssel, Quoten- und Datenschutzprüfung, falls erforderlich. Keine Suchmaschinenseiten scrapen; Suchtreffer sind keine Datenquelle und Materialnamen sind die einzigen zulässigen Suchanfragen. Keine IFC-Dateien oder Modellmengen an Suchdienste senden.

## Umsetzung und weitere Schritte

### Umgesetzt

- Die bestehende offizielle ÖKOBAUDAT-CSV bleibt die einzige automatische numerische Quelle. Nach Validierung wird der lokale Datensatz wie bisher in quellenbewusste Materialobjekte geladen; ein normalisierter Suchindex mit Referenzen auf diese Objekte wird für die Laufzeit aufgebaut.
- Unter `%LOCALAPPDATA%\CO-Emissionsrechner\catalog\manifest.json` wird atomar ein Katalogmanifest gespeichert. Es enthält Schema-/Katalogmodus, Quelle, Lizenzstatus und Nutzungshinweis, Release/Datenstock/URLs, Abruf- und Cache-Status, Quelldateigröße und SHA-256 sowie die Anzahl indexierter A1–A3-Datensätze. Es enthält keine Materialdatensätze oder GWP-Werte und erzeugt keine zweite Datenkopie.
- `/api/health`, `/api/search` und `/api/detail` behalten ihre bestehenden Felder; die `provenance`-Metadaten ergänzen Katalogstatus, Indexgröße, Lizenzstatus und Nutzungshinweis. Die Suchmeldung zeigt den Indexumfang und den Hinweis an, ohne das Seitenlayout umzubauen.
- Der Katalog wird aus dem bestehenden lokalen CSV-Cache neu aufgebaut; der Suchindex der Materialnamen und Kategorien bleibt im Arbeitsspeicher. Da keine pauschale Weitergabeberechtigung verifiziert ist, wird keine abgeleitete Materialdatenbank dauerhaft gespeichert, ins Repository gelegt oder an das Frontend ausgeliefert.
- Bestehende Aliasregeln und die Cache-Nutzung bleiben erhalten. Die Testabdeckung prüft Indexsuche, Manifest, Hash/Datensatzanzahl, Quellenprovenienz sowie den Offline-Fallback und stellt sicher, dass im Katalogordner keine CSV-Kopie angelegt wird.

### Noch offen

- Erweiterung um andere Quellen erst nach separat bestätigter maschinenlesbarer Zugriffsmethode und Erlaubnis für Abruf, Speicherung, Anzeige und gegebenenfalls Weitergabe. WECOBIS bleibt Kontextlink, IBU.data bleibt ohne erforderliche Freigabe/Registrierung unangetastet.
- Eine dauerhafte normalisierte Materialdatenbank oder ein SQL-Speicher wird erst erwogen, wenn eine konkrete Nutzungslizenz, ein zusätzlicher zulässiger Feed und ein durch Messungen begründeter Speicher-/Abfragebedarf vorliegen.
- Abdeckung bleibt auf geprüfte Quellen und ihre Datensätze begrenzt; generische Websuche, Scraping und LLM-Schätzwerte sind nicht umgesetzt.

### 1. Lokaler Katalog und Speicherung

- Einen App-eigenen, quellenbewussten Materialkatalog unter `%LOCALAPPDATA%\CO-Emissionsrechner\catalog\` aufbauen, nicht im Git-Repository und nicht in der distributierbaren Web-App. Die vorhandene ÖKOBAUDAT-CSV und API-Felder bleiben rückwärtskompatibel.
- Ein Quellenmanifest pro Import führen: Quellen-ID/-Name, erlaubte Nutzungsart, Original-URL, Release/Datenstand, Lizenzverweis und Prüfstatus, Abrufzeit, Hash, Datensatzanzahl, Warnungen und Cachezustand.
- Quellensnapshots nur speichern, soweit die Nutzungsbedingungen es gestatten. Daneben einen normalisierten, nach Quelle referenzierten Suchindex erstellen; keine nicht erlaubten Volltexte oder PDFs dauerhaft kopieren. Dubletten anhand stabiler Quellen-ID/Version kennzeichnen statt verschiedene Produkte anhand ähnlicher Namen zusammenzulegen.
- Da aktuell nur PowerShell/.NET und keine SQL-Abhängigkeit vorhanden sind, zuerst eine kompakte, quellengetrennte Datei-/Indexspeicherung im lokalen App-Datenverzeichnis prüfen und messen. Eine SQLite-Abhängigkeit nur einführen, wenn die reale Kataloggröße/Abfrageleistung sie erfordert und ein verteilbarer, unterstützter Provider feststeht; keine zusätzliche Paketabhängigkeit ohne Begründung.
- Cache und Index versionieren und atomar austauschen. Ein fehlerhafter oder unvollständiger Import darf den letzten validierten Katalog nicht ersetzen. Bei Quellenausfall andere Quellen und den vorhandenen Katalog weiter nutzbar lassen und Fehler pro Quelle sichtbar machen.

### 2. Einheitliches Datensatzmodell und Suche

Jeder numerische Eintrag bewahrt Originalangaben und normalisierte Suchfelder:

- Material-/Produktname im Original, Sprache, Materialgruppe, zulässige Synonyme und gefundener Suchbegriff;
- Quelle, Herausgeber, Original-URL, Quellen-Datensatz-ID/-Version, Lizenz-/Nutzungsstatus, Datenstand, Veröffentlichungs- und Abrufdatum;
- GWP-Indikator und Wert, Originaleinheit, deklarierte Bezugsmenge/-einheit, Norm/Methodik und Lebenszyklusmodule;
- optional normalisierter Wert je kg/t/m³ nur bei dimensionsrichtiger Umrechnung und belastbarer, passender Dichte;
- Qualität/Verifizierung der Quelle und Zuordnung, Importmethode, Gültigkeit sowie erkannte Konflikte.

Die Suche priorisiert exakte ÖKOBAUDAT-Treffer, dann vorhandene explizite Synonyme; weitere Quellen werden in bestätigter Rangfolge abgefragt. Nur kontrollierte Normalisierung und Aliasregeln erzeugen Treffer. Ähnlichkeit darf höchstens Vorschläge liefern, keine automatische Produktgleichheit oder belastbare Menge. Werte mit abweichenden Modulen, Indikatoren oder Bezugsgrößen bleiben getrennt und dürfen nicht in einer gemeinsamen Kennzahl verrechnet werden.

### 3. Aktualisierung, API und Website

- Datenstände je Quelle separat prüfen; Release-ID/Hash bevorzugen und Abrufhäufigkeit an die dokumentierte Updatepolitik anpassen. `ETag`/`Last-Modified` nur nutzen, wenn Quelle sie anbietet. Keine unnötigen Wiederholungsdownloads.
- Erfolgreiche Quellen einzeln atomar aktualisieren. Bei neuem, inkompatiblem Schema, fehlerhaftem Datensatz oder Netzwerkausfall den alten Katalog behalten und Quelle samt Status/Warnung in `/api/health` und Suchantworten ausweisen.
- `/api/search`, `/api/detail` und bestehende Feldnamen beibehalten; additive Metadaten liefern: Quell-Datensatz, Datenstand, Original-URL, Nutzungshinweis, Module, Einheit/Basis, Abrufstatus und passende Aliasbegriffe. Keine erfolgreichen Treffer simulieren, wenn eine Quelle nicht erreichbar ist.
- Web-App im bisherigen Aufbau belassen. In Treffern Quelle und anklickbaren Link, Datenstand, Module, Einheit/Bezugsmenge und Verifizierungs-/Nutzungsstatus anzeigen. Sichtbar machen, welche Quellen durchsucht wurden, welche nicht verfügbar sind, wie aktuell der Katalog ist und welche Materialanfragen ohne Zahl bleiben.
- IFC-Schätzung nur aus expliziten Modellmengen und passenden, numerisch verwertbaren Katalogdatensätzen berechnen. A1–A3 bevorzugen; unvergleichbare Datensätze nicht umrechnen oder vermischen. Fehlende Zuordnung/Menge ergibt eine ausgewiesene Teilbilanz, niemals einen Pflicht- oder Ersatzwert.

### 4. Tests und Abnahmekriterien

- Fixture-basierte Offline-Tests für jeden freigegebenen Adapter: gültiger/ungültiger Header, Versionswechsel, leere oder doppelte Datensätze, fehlende GWP-/Einheiten-/Modulfelder, Timeout/HTTP-Fehler, Lizenz-/Importblockierung und isolierter Quellenausfall.
- Cache-/Katalogtests: gültiger Cache, veralteter Release, Hash-/Manifest-Abgleich, atomarer Austausch, Abbruch ohne Cachekorruption, Start ohne Internet und parallele/mehrfache Aktualisierungsanfragen.
- Suchtests: exakter Treffer, explizite DE/EN-Aliasse, getrennte Produkt-/generische Datensätze, keine Treffer, nicht verfügbare Quelle und Konflikt mehrerer kompatibler/inkompatibler Quellen.
- Berechnungstests: identische Module/Indikatoren/Bezugsgrößen, kg↔t, m³↔kg nur mit belegter passender Dichte, fehlende Mengen, Mehrdeutigkeit und Teilbilanz. Quellenlink, Datenstand und Nutzungsstatus in API und UI prüfen.
- Bestehende PowerShell-Suchtests, IFC-Tests, Endpunkte und App-Start regressionsprüfen. Netzwerktests standardmäßig deaktiviert; Live-Prüfung einer Quelle nur gegen ausdrücklich zulässigen Endpunkt.

## Blocker und erwartbare Reichweite

- Eine eigene lokale Indexierung der ÖKOBAUDAT ist die minimale realistische Etappe; die rund 52-MB-CSV ist bereits im lokalen App-Cache vorhanden. Für eine weiterverteilte oder gehostete Datenbank muss die Berechtigung zum Speichern, Indexieren und Anzeigen des Datensatzinhalts geklärt sein.
- Ein universeller Katalog aus „frei zugänglichem Internet“ ist ohne Rechteklärung und maschinenlesbare Quellen nicht umsetzbar. Insbesondere WECOBIS ist kein bestätigter numerischer Feed; IBU.data erfordert Registrierung und beschränkt weitergehende Nutzung; sonstige Quellen und Websuche benötigen jeweils geprüfte Zugänge.
- Wenn Nutzungsrechte, Feed, API-Zugang oder Schlüssel fehlen, wird diese Quelle nicht automatisiert importiert. Die Website zeigt dann nur einen Kontext-/Original-Link oder den Grund „nicht verfügbar/keine zulässige Datenquelle“, statt Websuche, Vollständigkeit oder einen CO₂-Wert vorzutäuschen.
- Der Katalog kann nachvollziehbare Abdeckung statt Vollständigkeit versprechen: Zahl und Stand importierter Datensätze, aktive Quellen, Quellenfehler und nicht zugeordnete Materialien.

## Öffentliche Referenzen (geprüft am 17.11.2026)

- [ÖKOBAUDAT: Zweck, Datenzugang und Grenzen](https://www.oekobaudat.de/)
- [ÖKOBAUDAT: offizielle Downloads, Releases und Aktualisierungshinweis](https://www.oekobaudat.de/service/downloads.html)
- [WECOBIS: Baustoff- und Materialinformationen](https://www.wecobis.de/)
- [IBU.data: Registrierung, Download und Nutzungsbedingungen](https://ibu-epd.com/ibu-data-start/)
- [IBU: veröffentlichte EPDs](https://ibu-epd.com/veroeffentlichte-epds/)
- [EPD International: öffentliche EPD-Library](https://www.environdec.com/library)
