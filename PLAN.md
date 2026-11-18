# Plan: Materialquellen, Reflexionsdaten und Upload

**Status:** Der frühere IFC-/Cursor-Ausbau ist umgesetzt. Diese Aktualisierung plant die nächste Erweiterung um Herstellerquellen, einen möglichen Reflexionskennwert und einen lokalen Nutzerimport. In dieser Planetappe wird ausschließlich `PLAN.md` geändert; App und laufender Server bleiben unverändert. Neue Herstellerdaten sind noch nicht integriert.

## Umsetzungsstand (18.11.2026)

- Der vorhandene lokale ÖKOBAUDAT-CSV-Cache und In-Memory-Suchindex bleiben die einzige numerische Datenquelle; es wurde keine neue Datenbank-Engine oder kein fremder Datensatz ohne geklärten Zugang und Rechte ergänzt.
- Der IFC-Parser nimmt unterstützte Bauteilinstanzen auch ohne Material, Menge, Typ- oder Raumstrukturbeziehung in die Ergebnisliste auf. Kontrollierte Kategorieabfragen sind als manuelle Vorschläge gekennzeichnet, werden nicht vorgewählt und schränken die Datenqualitätsbewertung ein. Ohne belegten Datensatz bleibt der Beitrag leer und außerhalb der Teilbilanz.
- Für ÖKOBAUDAT-Treffer erscheinen Quellen- und Lizenzstatus samt Nutzungshinweis; die Oberfläche listet angefragte, aber nicht angebundene Quellen samt Prüfvorbehalt. Pages bleibt bei synthetischen Beispielen und akzeptiert Quellenwerte nur bei belegtem Weitergaberecht.
- Der 24×24-SVG-Baumcursor wird lokal vom PowerShell-Server und in Pages ausgeliefert; Textfelder, interaktive Elemente, Touch-Geräte und Standardcursor-Fallbacks bleiben berücksichtigt.
- Fokussierte IFC-, Pages-, Quellen-, Cursor- und lokale Suchtests wurden ausgeführt.

## Neue Etappe: Herstellerquellen, Reflexionskennwert und Nutzerimport

Die folgenden Punkte sind Planungsumfang, keine bereits erfolgte Quellenprüfung oder Implementierung. Ziel ist eine bessere IFC-Datenabdeckung, ohne Produktwerte, Nutzungsrechte oder Trefferqualität zu erfinden.

### Zu prüfende Quellen

Die angefragten Namen werden zunächst in der übermittelten Schreibweise geführt: **Röben, Wieneberger, Heinze, Bundesverband Ziegel, Haro, Bauwerk, bembé, Boen, Drüsedau, Grunreben, Hain, Trumpf, ter Hürne, Holz Reinlein, Wimmer, Schotten und Hansen, Meisterwerke, Parador, Parkett-Herter, Kährs, Rockwoll, Würth, Casea, formula, one Mineral und knauf.** Für keinen dieser zusätzlichen Einträge ist hiermit ein frei zugänglicher numerischer Datenbestand oder ein Recht zur lokalen Speicherung bestätigt.

- Je Name zuerst die genaue Organisation, Produktlinie und offizielle Quelle verifizieren. Insbesondere **Wieneberger** nicht ungeprüft mit dem schon im Repository genannten **Wienerberger** gleichsetzen; Schreibweisen wie **Rockwoll** nicht automatisch zu **ROCKWOOL** korrigieren. Namen wie Grunreben, Trumpf, Casea, formula, one Mineral, Wimmer und Bauwerk benötigen ebenfalls Identitätsabgleich. Heinze und Bundesverband Ziegel können Quellenverzeichnisse oder Produktinformationen statt eigener Datensatzanbieter sein.
- Pro Hersteller ausschließlich offizielle Produktseiten oder verlinkte Original-EPDs prüfen: Funktioniert der konkrete Abruf ohne API-Schlüssel und Registrierung? Gibt es einen erlaubten maschinenlesbaren Download oder nur ein PDF/eine Webseite? Sind Indexierung, lokale Speicherung, interne Berechnung und Anzeige erlaubt, und welche Attribution ist nötig? Keine Massendownloads, Scrapes oder Zugangsumgehungen.
- Numerische Werte nur aus identifizierbaren Datensätzen übernehmen. Produkt/Variante, Hersteller, Datensatz-ID und Version, EPD-Programm, deklarierte Einheit, GWP-Methode, Module/Systemgrenze, Gültigkeit und Originalbeleg müssen erhalten bleiben. Ein Produktkatalog oder ein Werbe-/Technikblatt allein ist kein GWP-Beleg. Nicht bestätigte Quellen bleiben als `not-integrated` oder `manual-link-only` sichtbar; ein nicht nutzbarer Herstellerwert darf nicht durch einen ähnlichen Datensatz ersetzt werden.

### Bedeutung und Darstellung von „Reflektionsdaten“

„Reflektionsdaten“ ist fachlich noch nicht eindeutig. Vor einer Umsetzung prüfen, ob eine Quelle tatsächlich einen passenden Kennwert ausweist, etwa solare Reflexion/Reflektanz, und welche Messmethode, Oberfläche, Wellenlänge bzw. Spektraldefinition und Einheit gelten. Der bestehende ÖKOBAUDAT-Suchpfad weist ökologische Wirkungsindikatoren aus; ein Reflexionsfeld ist dort bislang nicht als unterstützter Suchindikator festgelegt. Nicht unterstellen, dass Hersteller-EPDs diesen Kennwert enthalten.

Vorschlag: Falls Bedeutung und Quelle bestätigt sind, den exakt benannten Wert klein neben Wasserknappheit anzeigen, mit Einheit und Methodik/Produktbezug, ohne ihn in GWP oder eine Umwelt-Gesamtwertung einzurechnen. Bei fehlendem oder methodisch nicht vergleichbarem Wert ausdrücklich „nicht verfügbar“ zeigen, statt aus Materialtyp oder Farbe zu schätzen. **Offen für die Nutzerin:** Ist Solarreflexion/Reflektanz gemeint oder ein anderer Kennwert, und soll auch ein bestimmtes Messverfahren gelten?

### Sicherer Import eigener Datensätze

Vorschlag für die lokale Windows-App: ein ausdrücklich ausgewählter UTF-8-CSV-Import nach einer dokumentierten Vorlage, zunächst beispielsweise begrenzt auf 5 MiB und 10.000 Zeilen. Keine ausführbaren Dateien, Makros, Archive oder beliebigen PDFs importieren. Der Parser behandelt alle Zellen als Text bis zur strikt typisierten Validierung; Formeln werden nie ausgeführt, Zahlenfelder akzeptieren nur gültige Zahlen mit passender Einheit.

Pflichtfelder der Vorlage sollen mindestens Quelle/Original-URL und Rechte-/Attributionsangabe, Hersteller und Produkt/Variante, stabile Datensatz-ID und Version, Kategorie, Indikator, Rohwert und Einheit, deklarierte Bezugsmenge/-einheit, Standard/Methode und Module sowie Gültigkeit enthalten. Fehlende oder widersprüchliche Angaben werden pro Zeile mit Grund angezeigt. Nutzerbestätigung und ein Herkunfts-/Nutzungsrechte-Hinweis sind vor der Aktivierung erforderlich; unvollständige, ungültige oder nicht belegte Werte dürfen in Suche, IFC-Zuordnung und Summen nicht als belastbare Faktoren erscheinen.

- Erst eine vollständig geprüfte Importvorschau nach ausdrücklicher Bestätigung aktivieren. Exakte Dubletten anhand Quelle, Datensatz-ID und Version erkennen; abweichende Werte unter derselben ID als Konflikt zurückhalten, nicht still überschreiben. Fehlgeschlagene Zeilen mit nachvollziehbarem Fehlerbericht erhalten.
- Importierte Einträge in einem getrennten lokalen Katalogspeicher samt Importdatum, Prüfergebnis und Provenienz halten. In der Suche und als IFC-Kandidaten sichtbar als „Benutzerimport“ kennzeichnen. Ein IFC-Beitrag ist erst nach expliziter Zuordnung und Prüfung von Produktbezug, Einheit, Bezugsmenge, Indikator/Modulen und Gültigkeit zulässig; ein Import allein erzeugt keine automatische Bauteilzuordnung.
- **Offen für die Nutzerin:** Sollen bestätigte Importe dauerhaft nur auf diesem Rechner gespeichert werden (Vorschlag), und wie sollen sie überprüft, entfernt oder ersetzt werden? Sollen sie standardmäßig in der normalen Suche erscheinen und bei IFC lediglich als manuelle Kandidaten angeboten werden (Vorschlag)? Synchronisierung, gemeinsamer Mehrbenutzerbestand und GitHub-Pages-Uploads sind nicht Teil dieses lokalen Importpfads.

### Abgrenzung GitHub Pages

Nur das lokale Loopback-Backend kann einen nutzerbestätigten Import dauerhaft in seinen lokalen Suchindex aufnehmen. Die statische GitHub-Pages-Demo kann ohne Backend keine gemeinsame oder persistente Datenbank führen; sie erhält deshalb weder Upload-Endpunkt noch importierte reale Nutzerdaten. Eine spätere Pages-Lösung bräuchte eine gesondert geplante, abgesicherte Serverkomponente und ausdrückliche Entscheidung zu Speicherung, Zugriff und Datenschutz.

## Ziel und Grenzen

Eine nachvollziehbare Materialdatenbank soll die bestehende IFC-Auswertung mit möglichst vielen rechtmäßig nutzbaren, ohne API-Schlüssel erreichbaren Datensätzen versorgen. Beim IFC-Import sollen Bauteile auch dann sichtbar ausgewertet werden, wenn kein passender Datenbanktreffer vorliegt. Fehlende Werte bleiben ausdrücklich fehlend: weder Ähnlichkeitssuche noch Demo-Daten dürfen einen echten GWP-Wert vortäuschen. Layout und bestehende Funktionen bleiben erhalten; ergänzt werden nur Datenabdeckung, verständliche Zuordnungszustände und der kleine Baum-Cursor.

„Ohne API-Schlüssel erreichbar“ ist eine Zugangsvoraussetzung, aber keine Lizenz. Vor Abruf, Speicherung, Indexierung, Anzeige oder Weitergabe sind für jede Quelle die offiziellen Zugangsbedingungen und konkreten Nutzungsrechte zu prüfen. Keine Registrierung, Zugangsbeschränkung, Rate-Limits oder Lizenzbedingungen umgehen. Wenn eine Quelle nicht ohne Schlüssel und zulässigen Zugriff verfügbar ist, wird sie nicht automatisiert angebunden; sie kann höchstens als klar gekennzeichneter manueller Quellenlink erscheinen.

Eine vollständige, weltweit alle Produkte umfassende Datenbank ist nicht realistisch versprechbar. Ziel ist eine erweiterbare, quellengetrennte Abdeckung mit sichtbaren Lücken, Datenständen und Fehlern.

## Vorhandener Stand

- Die lokale Windows-App wird über `Start-App.bat` und `server.ps1` gestartet. Das PowerShell-Backend bietet `/api/health`, `/api/search` und `/api/detail`, lädt den offiziellen ÖKOBAUDAT-CSV-Export, hält die CSV unter `%LOCALAPPDATA%\CO-Emissionsrechner\` und baut daraus einen Laufzeitindex sowie ein lokales Metadatenmanifest auf. Eine weitergabefreigegebene Mehrquellen-Datenbank gibt es noch nicht.
- Die Oberfläche liegt unter `public\`. `public\ifc.mjs` parst IFC2x3/IFC4 im Browser, liest direkte und eindeutig geerbte Materialzuordnungen sowie explizite Mengen und berechnet Beiträge nur bei passender Einheit und gültigem Datensatz. `public\app.js` sucht pro erkanntem Material in ÖKOBAUDAT (in Pages in Beispieldaten); Datensatz und passende IFC-Menge werden je Bauteil ausgewählt.
- Der IFC-Parser unterscheidet fehlende und mehrdeutige Materialzuordnungen und kann enthaltene Bauteile ohne Material/Menge sichtbar machen. Der Plan ergänzt Tests und Anzeigeverhalten für den Fall, dass eine Suche null Treffer liefert oder ein Materialname nicht zuverlässig zugeordnet werden kann.
- Der GitHub-Pages-Workflow baut aus `public\` eine statische Demo. Sie hat kein PowerShell-Backend und keine Live-ÖKOBAUDAT-Suche; sie verwendet ausdrücklich synthetische, als Demo markierte Beispiele. Änderungen an dieser Demo dürfen keine Beispielwerte als echte Ökobilanz ausgeben.
- Die Landschaftsillustration `public\hero-landscape.svg` enthält den gewünschten dünnlinigen Baumstil. Die Darstellung und das bestehende responsive Swiss-Style-Layout sollen ansonsten unverändert bleiben.
- Vorhandene fokussierte Prüfungen: `tests\ifc.test.mjs`, `tests\pages-demo.test.mjs`, `tests\public-sources.test.mjs`, `tests\hero.test.mjs` sowie `tests\search.test.ps1`. Der Pages-Workflow führt die JavaScript-Tests aus.

## Quellenprüfung vor Integration

Für jede Quelle zuerst die genaue Organisation/Publikation und den offiziellen Zugang bestimmen. Pro Quelle dokumentieren: öffentlicher Endpunkt oder erlaubter manueller Download, ob dieser ohne API-Schlüssel und ohne Registrierung funktioniert, Abruflimits, Lizenz und erlaubte Speicherung/Indexierung/Anzeige/Weitergabe, Attributionsvorgaben, Aktualisierungsweg, stabile Datensatz-ID, Dateiformat und Eignung der Kennzahlen für den vorgesehenen Vergleich. Dieser Plan behauptet nicht, diese Punkte bereits recherchiert oder bestätigt zu haben.

| Genannte Quelle | Geplanter Prüf- und Einsatzpfad (noch nicht bestätigt) |
|---|---|
| ÖKOBAUDAT | Bestehenden offiziellen CSV-Import lokal erhalten. Zugang ohne API-Schlüssel ist der derzeitige App-Pfad; konkrete Rechte für abgeleitete Speicherung und Verteilung des Datensatzinhalts gesondert klären. Nicht als Hersteller-EPD ausgeben. |
| WECOBIS | Prüfen, ob ein offiziell erlaubter maschinenlesbarer Zahlenbestand existiert. Bis dahin qualitative Orientierung und Original-Link, keine aus Text abgeleiteten GWP-Werte. |
| IBU | Öffentliche EPD-Seiten und separate Datenangebote/Zugangsbedingungen einzeln prüfen. Keine registrierungs- oder lizenzpflichtigen Downloads automatisieren oder weitergeben. |
| KBOB und eco-bau | Offizielle Publikationen, Datenformate, Versionen, Geltungsbereich und Rechte prüfen; Faktorlisten nicht ungeprüft als produktbezogene EPD behandeln. |
| IPB | Zuerst klären, welche Organisation/Quelle mit „IPB“ gemeint ist; bis zur eindeutigen Identifikation keine Integration. |
| ProBas | Offiziellen Zugang, Datentyp, Systemgrenzen, Lizenz und Aktualität prüfen; Prozess-/Hintergrunddaten nicht ohne methodische Prüfung als Produktwert verwenden. |
| Global EPD und ECO EPD | Herausgeber, offizielle öffentliche EPD-Suche bzw. Downloads, maschinenlesbare Formate, Rechte und Vergleichbarkeit je Programm prüfen. Keine Massendownloads oder Scrapes voraussetzen. |
| Ecoinvent und GaBi | Lizenz- und Zugangsvoraussetzungen besonders sorgfältig prüfen; keine kostenpflichtigen, geschützten oder zugangsbeschränkten Inhalte ohne ausdrückliche Berechtigung importieren. Nur ein belegter, schlüsselfreier und lizenzkonformer Zugriff käme infrage. |
| Climatiq | Aktuelle Dokumentation auf einen für diesen Zweck geeigneten Endpunkt ohne API-Schlüssel prüfen. Wenn ein Schlüssel oder unpassende Emissionsfaktoren nötig sind, aus der automatischen Datenbank ausschließen. |
| DEFRA | Offizielle freie Faktoren und Nutzungsbedingungen prüfen. Nur dann nutzen, wenn Quelle, Aktivität, Einheit und Systemgrenze zur konkreten Rechnung passen; generische Emissionsfaktoren sind kein Ersatz für eine passende Baustoff-EPD. |
| DGNB Navigator | Öffentliche Produktdaten, Zugangsvoraussetzungen, Lizenz und maschinenlesbare Nutzung prüfen; Produktangaben ohne belegten Ökobilanzdatensatz nur zur Identifikation verwenden. |
| Herstellerkataloge | „Alle Hersteller“ ist nicht abgrenzbar. Eine priorisierte, gepflegte Liste konkreter Hersteller festlegen; je Hersteller Datenfeed, Original-EPD, Nutzungsrechte und stabile Produktkennung prüfen. Produktseiten oder technische Datenblätter allein sind kein GWP-Beleg. |

Ein Quellenregister soll auch geprüfte, aber nicht integrierte Quellen mit Status und Begründung enthalten, etwa `manual-link-only`, `no-key-access-not-confirmed`, `license-not-cleared`, `not-comparable` oder `active`. Bei ungeklärtem Zugang oder Recht bleibt es bei `not-integrated`; keine Umgehung durch Scraping, Spiegeln oder Nachbildung geschützter APIs.

## Zielarchitektur und Datenmodell

### Lokaler Katalog

- Die lokale App bleibt zunächst PowerShell/.NET-Backend mit bestehendem HTTP-Vertrag. Den vorhandenen ÖKOBAUDAT-Import rückwärtskompatibel halten; neue Quellen als einzeln fehlertolerante Adapter hinter `/api/search` und `/api/detail` anbinden. Vor einer zusätzlichen SQL-Abhängigkeit Datenmenge und Suchleistung messen; zunächst vorhandene App-Datenablage und einen quellenreferenzierten Suchindex nutzen.
- Den Katalog in einem lokalen App-Datenverzeichnis außerhalb des Repositories halten. Pro Quelle erlaubte Snapshots/Indexdaten getrennt speichern. Nur Felder persistieren, deren Speicherung erlaubt ist; andernfalls nur Referenz und erlaubte Metadaten indexieren. Keine fremden EPD-Volltexte oder PDFs kopieren, wenn das nicht ausdrücklich gestattet ist.
- Manifest/Status pro Quelle mit Schema-Version, Quell-ID, Original-URL, Release/Datenstand, Lizenzverweis und Prüfstatus, Abrufzeit, Hash, Datensatzanzahl, Warnungen und Cachezustand führen. Nie Lizenzfreigabe suggerieren, wenn sie nicht geprüft wurde.

### Normalisierte Datensätze und Herkunft

Jeder Eintrag erhält mindestens:

- stabile Quell-Datensatz-ID und Version, Originalname/Sprache, Material- oder Produktkategorie und Original-Link;
- Herausgeber, Abruf-/Veröffentlichungsstand, Lizenz-/Attributionsstatus und Importmethode;
- Indikator mit exakter Bezeichnung/Methodik, Rohwert, Roh-Einheit, deklarierte Bezugsmenge/-einheit sowie Lebenszyklusmodule und Gültigkeit;
- Land/Region und weitere Vergleichsmerkmale, sofern die Quelle sie liefert;
- getrennte Originalfelder und Normalisierungsfelder, Importwarnungen und Zuordnungsstatus.

Die Quellenfelder bleiben erhalten. Einheiten dürfen nur dimensionsrichtig normalisiert werden. Werte verschiedener Indikatoren, Module, Methoden oder Bezugsgrößen nicht zusammenlegen oder addieren. Dichte, funktionale Gleichwertigkeit und Produktidentität niemals aus bloßer Namensähnlichkeit ableiten. Dubletten anhand Quell-ID/Version kennzeichnen statt Datensätze verschiedener Quellen zu verschmelzen.

Ein Reflexionskennwert ist ein eigenständiges physikalisches Produktmerkmal, kein Ökobilanzindikator: falls er freigegeben und verfügbar ist, zusätzlich Methode, Messbedingungen, Oberfläche, Einheit und Variantenbezug speichern. Benutzerimporte bleiben mit Originalzeile und Importherkunft getrennt von Anbieteradaptern und erhalten bis zur Validierung keinen Such- oder Rechenstatus `active`.

## Aktualisierung und Offline-Verhalten

- Abrufhäufigkeit je offizieller Updatepolitik; Release-ID und Hash erkennen. ETag/Last-Modified nur verwenden, wenn der konkrete Endpunkt sie bereitstellt. Keine unnötigen Wiederholungsdownloads.
- Import zuerst vollständig validieren und dann atomar aktivieren. Bei Netzwerkfehler, leeren/fehlerhaften Antworten oder inkompatiblem Schema den letzten gültigen Cache behalten und den Quellfehler sichtbar machen; ein Fehler einer Quelle soll andere Quellen nicht blockieren.
- Letzten zulässigen Katalog lokal weiterverwenden, wenn offline. Den Datenstand als möglicherweise veraltet kennzeichnen. Beim ersten Start ohne Netz und ohne Cache klar „keine Daten verfügbar“ anzeigen statt Ergebnisse vorzutäuschen.
- API-Antworten bestehende Felder beibehalten und additiv Quellenstatus, Herkunft, Datenstand, Nutzungsstatus sowie Aktualisierungs-/Cachewarnungen liefern.

## IFC-Zuordnung und Ergebnisverhalten

1. IFC-Import bleibt lokal im Browser. Alle unterstützten, auslesbaren Bauteile in der Tabelle anzeigen – unabhängig davon, ob Material, Menge oder Datenbanktreffer verfügbar sind. Dateien weiterhin nicht hochladen; Format-/Größenlimits und Parserfehler verständlich ausweisen.
2. Zuordnungsreihenfolge: eindeutiger direkter IFC-Materialname, eindeutig geerbter Bauteiltyp, normalisierter exakter Katalogname, danach eine kontrollierte und dokumentierte Aliasliste. Ein exakter Name ist noch kein Beweis, dass Produkt, Gültigkeit und funktionale Anwendung identisch sind.
3. Ähnliche Namen oder breitere Materialfamilien höchstens als „mögliche Treffer“ mit Quelle, Einheit und Vergleichsmerkmalen anzeigen. Sie dürfen keine automatische Berechnung auslösen. Eine manuelle Auswahl muss als manuelle Zuordnung sichtbar sein; berechnet wird nur nach expliziter Bestätigung, wenn Datensatzgültigkeit, Indikator/Module, Bezugsmenge und IFC-Mengeneinheit kompatibel sind.
4. Pro Bauteil klare Zustände ausgeben: `berechenbar`, `kein Material`, `mehrdeutiges IFC-Material`, `kein Treffer`, `nur Vorschläge`, `keine passende Menge`, `Einheit/Modul inkompatibel`, `Quelle nicht verfügbar`, `Datensatz ungültig`. Auch bei null Treffern bleibt die Bauteilliste mit diesen Gründen und ggf. erlaubten Original-Quellenlinks sichtbar.
5. Nur belegte Beiträge summieren und die Summe stets als Teilbilanz mit Anzahl/Umfang ungelöster Bauteile kennzeichnen. Bei null berechenbaren Beiträgen keinen Wert als CO₂-Ergebnis ausgeben; stattdessen „keine belegten Beiträge“ und die fehlenden Zuordnungen zeigen. Keine Schätzung, Nullersetzung oder KI-generierte GWP-Zahl.

## Lokale App und GitHub-Pages-Demo

- **Lokale App:** darf Backend-Adapter und lokalen Cache nutzen, wenn Zugriff und Rechte geklärt sind. Quellenfehler und fehlende Treffer bleiben am jeweiligen Datensatz sichtbar.
- **GitHub Pages:** bleibt statisch und hat kein PowerShell-Backend oder Live-Import. Ein Build-Zeit-Katalog darf nur Datensätze enthalten, deren Weitergabe und Veröffentlichung ausdrücklich erlaubt ist. Wenn das nicht belegt ist, werden keine realen Katalogdaten gebündelt; Demo-Beispiele bleiben unmissverständlich synthetisch und IFC-Beiträge bleiben als Demo markiert. Ungeklärte/fehlende reale Daten dürfen in Pages nicht als echte Werte erscheinen.
- Nutzer-Uploads sind ausschließlich ein lokaler Backendpfad; sie werden weder in Pages gebaut noch aus Pages entgegengenommen oder mit dem Repository synchronisiert.
- Kein API-Schlüssel in Repository, Frontend oder Pages-Build hinterlegen. Ein nur mit Schlüssel nutzbarer Anbieter ist für die automatische Integration dieser Anforderung nach ausgeschlossen.

## Kleiner Baum-Cursor und Layout

- Ein kleines SVG-Cursorbild im feinen, zurückhaltenden Linien-/Grünton des Baums aus `public\hero-landscape.svg` ergänzen. Größe und Klick-Hotspot so wählen, dass der Baum als Cursor erkennbar, aber nicht störend oder schwer bedienbar ist.
- CSS-Cursorbild mit geeignetem normalen Cursor als Fallback einsetzen; bei nicht unterstützten/fehlenden Assets oder Browsern muss die gewohnte Systemdarstellung funktionieren. Textfelder behalten den Textcursor, interaktive Elemente und Größenänderungen ihre passenden Cursorzustände.
- Nur den Cursor ergänzen. Vorhandenes Layout, Farben, Hintergrundillustration, responsive Verhalten, bestehende Suche, Detailansichten, Alternativenprüfung und IFC-Fluss beibehalten. Keine unabhängige Neugestaltung.

## Umsetzung und gezielte Prüfung

1. Quellenregister für alle neuen Herstellerkandidaten vervollständigen: Identität, schlüsselfreier offizieller Zugriff, Datenformat, Nutzungs-/Speicher-/Anzeigerechte, Aktualisierung und Produkt-/EPD-Metadaten dokumentieren. Nur einzeln freigegebene Quellen aktivieren; übrige Gründe sichtbar halten.
2. Existierende ÖKOBAUDAT-API rückwärtskompatibel lassen. Ein separates, validiertes CSV-Import-/Vorschauvorgehen im lokalen Backend entwerfen; atomar aktivieren, Provenienz und Konflikte speichern sowie Rücknahme/Entfernung ermöglichen.
3. Fachbedeutung und Datenverfügbarkeit des Reflexionskennwerts klären. Nur bei eindeutigem Produktmerkmal eine additive Suchanzeige neben Wasserknappheit ergänzen; bestehende Umweltindikatoren und IFC-GWP-Berechnung unverändert lassen.
4. IFC-Zuordnung/Ergebnisdarstellung so erhalten, dass jedes erkannte Bauteil auch ohne Treffer einen aussagekräftigen Status erhält. Neue Hersteller- und Benutzerdatensätze nur nach geprüfter Passung bzw. bestätigter manueller Zuordnung einrechnen.
5. Den bereits umgesetzten Baum-Cursor, bestehende Suche, Detailansichten und Layout unverändert lassen.
6. Fokussierte Offline-Tests ergänzen: freigegebene/no-key Quelle versus Lizenzblockierung; gültige und ungültige CSVs, Größen-/Zeilenlimit, Pflichtfelder/Einheiten, Formeltext, Dubletten/Konflikte, Preview/Bestätigung, Entfernung und Offline-Persistenz; korrekte Provenienz im Such-/IFC-Kandidaten sowie Ausschluss ungeprüfter Zeilen; Reflexionswert-Verfügbarkeit, Einheit und Anzeige ohne GWP-Verrechnung; Pages ohne Upload/importierte Echtwerte.
7. Bestehende Tests beibehalten und betroffene Suiten ausführen: `node --test tests\ifc.test.mjs tests\hero.test.mjs tests\public-sources.test.mjs`, `node --test tests\pages-demo.test.mjs tests\cursor.test.mjs` sowie `powershell -NoProfile -File tests\search.test.ps1`.

## Abnahmekriterien und Grenzen

- Kein API-Schlüssel oder geschützter Zugriff erforderlich; Quellen ohne bestätigten öffentlichen Zugang oder zulässige Nutzung bleiben außen vor.
- Jeder importierte Zahlenwert ist auf Originalquelle, Datensatzversion, Einheit/Bezugsmenge, Indikator und Lebenszyklusmodule zurückführbar.
- Neu aufgenommene Herstellerdaten sind nur dann numerisch verfügbar, wenn offizieller schlüsselfreier Zugriff und Speicherung/Anzeige-/Nutzungsrecht für den jeweiligen Einsatz geklärt sind; Produkte, Module und Versionen bleiben unterscheidbar.
- Reflexionswerte haben eine bestätigte fachliche Definition, Einheiten- und Messmetadaten und werden getrennt von Ökobilanzindikatoren angezeigt; fehlende Werte werden nicht geschätzt.
- Eigene Uploads werden nur im lokalen Backend nach Vorschau, strikter Validierung und ausdrücklicher Bestätigung aktiviert. Ungültige, widersprüchliche oder unvollständig belegte Zeilen erzeugen keinen IFC- oder Suchbeitrag; Herkunft bleibt sichtbar und Importe sind entfernbar.
- Ein IFC-Import liefert sichtbare Bauteilzeilen und klare Gründe auch bei null Treffern; fehlende oder unbestätigte Zuordnungen erzeugen keinen GWP-Beitrag.
- Offline-Betrieb nutzt nur einen vorhandenen Cache und kennzeichnet dessen Status; Fehler einer einzelnen Quelle machen andere verfügbare Daten nicht unsichtbar.
- Pages enthält ausschließlich erlaubte Veröffentlichungsdaten oder klar markierte synthetische Demo-Daten und wird nicht als Live-Katalog ausgegeben.
- Der kleine Baum-Cursor fällt zuverlässig auf den passenden Standardcursor zurück; Layout und bestehende Funktionen bleiben erhalten.
- Reichweite bleibt durch Datenabdeckung, Quellenrechte, EPD-Methodik, IFC-Qualität und die nicht vollständig identifizierbare Menge aller Hersteller begrenzt. Das Ergebnis ist eine nachvollziehbare Orientierung bzw. Teilbilanz, keine geprüfte Gebäudebilanz.
