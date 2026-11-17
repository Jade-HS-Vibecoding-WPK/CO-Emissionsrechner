# CO-Emissionsrechner

Lokaler Prototyp für die Suche nach Baustoff-Datensätzen und den Vergleich ausgewiesener ÖKOBAUDAT-GWP-Werte.

## Starten

Unter Windows `Start-App.bat` öffnen. Die App läuft lokal unter `http://127.0.0.1:8765/`. Für die erste Suche ist eine Internetverbindung zur offiziellen ÖKOBAUDAT-Downloadseite und zum dort verlinkten CSV-Export erforderlich.

## Tests

Die fokussierten IFC-Parser- und Berechnungstests benötigen nur Node.js:

```powershell
node --test tests\ifc.test.mjs tests\hero.test.mjs tests\public-sources.test.mjs
powershell -NoProfile -File tests\search.test.ps1
```

Die ÖKOBAUDAT-Suchtests prüfen außerdem die offizielle CSV-Linkauswahl, Datenstand-Metadaten, den Cache-Sidecar, den lokalen Katalogmanifest-/Indexaufbau, die CSV-Validierung und bekannte deutsche/englische Materialaliasse.

## Umfang und Grenzen

- Die Oberfläche verwendet ein responsives Swiss-Style-Raster mit 12/8/4 Spalten, linksbündiger Grotesktypografie und Schwarz, Weiß sowie Pastellgrün. Die dezente Hintergrundbewegung berücksichtigt `prefers-reduced-motion`.
- Die Suche zeigt höchstens zehn zusammengefasste Materialgruppen; wiederkehrende Rezept-/Werkvarianten werden gebündelt. Datensatzversionen, Quellen, Einheiten, Bezugsgrößen und Gültigkeit bleiben in den Detailansichten sichtbar.
- „Gut“, „mittel“ und „schlecht“ sind vorläufige relative Drittel ausschließlich innerhalb gültiger ÖKOBAUDAT-Datensätze mit gleicher Kategorie, Einheit, Bezugsmenge, Norm und Lebenszyklusphase sowie passendem Namens-/Technikprofil. Innerhalb solcher Gruppen stehen die besten belegten GWP-Werte zuerst; Gleichstände werden nach Datensatzname stabil aufgelöst. Die Ergebnisbalken zeigen die relative Position von Pastellrot bis Pastellgrün und ergänzen sie stets um Rang und Textlabel. Nicht klassifizierte oder inkompatible Treffer erscheinen getrennt und nachrangig. Gleiche Werte werden nicht getrennt, daher können die Gruppen unterschiedlich groß sein. Bei weniger als drei passenden Datensätzen oder identischen GWP-Werten bleibt die Einordnung nicht klassifiziert.
- Ein niedrigerer GWP-Wert wird nur als Datensatzvergleich innerhalb derselben vorläufigen Vergleichsgruppe gezeigt. Gemeinsam verfügbare Indikatoren werden mit beiden Rohwerten und Einheiten separat ausgewiesen; sie werden nicht zu einer Gesamtpunktzahl verrechnet. Das ist kein Materialersatz und bestätigt keine technische oder funktionale Gleichwertigkeit.
- Die Einsatz-Auswahl wird für einen separaten, bedingten Materialalternativen-Check verwendet, filtert aber keine Suchtreffer. Bei Beton für Außenwand oder Mauerwerk kann Kalksandstein-Mauerwerk als ausdrücklich unbestätigter Prüfpfad erscheinen. Es wird kein GWP-Vorteil behauptet: Die derzeitigen Datensätze erlauben keinen fairen Vergleich gleichwertiger vollständiger Bauteile. Für andere Fälle wird keine Materialalternative erfunden.
- Die Materialalternativen-Prüfung ist noch nicht mit einer verifizierten Zuordnung funktional vergleichbarer Bauteile oder ergänzenden offiziellen Quellen verbunden. Ihre Prüfpunkte machen die fehlenden technischen Randbedingungen sichtbar; sie ersetzen keine Planung oder Nachweise.
- IFC2x3-/IFC4-Dateien bis 100 MB werden lokal im Browser gelesen und nicht hochgeladen. Die Auswertung nutzt direkte oder eindeutig vom Bauteiltyp geerbte Materialzuordnungen sowie explizite Längen-, Flächen-, Volumen-, Massen- und Stückmengen aus IFC-Element-Quantitäten. Pro Bauteil müssen ein passender IFC-Mengenwert und ein gültiger ÖKOBAUDAT-Datensatz ausgewählt werden; abgelaufene oder in ihrer Gültigkeit unbekannte Datensätze bleiben ohne Beitrag. Die hervorgehobene CO₂e-Zahl summiert berechenbare A1–A3-Beiträge, zeigt Datensatz, Bezugsmenge und Quelle und bleibt als Teilbilanz gekennzeichnet, wenn Bauteile oder Modellumfang offen sind. Das qualitative Datenlabel beruht auf Zuordnung, Menge, Datensatzgültigkeit und IFC-Raumstruktur; eine statistische Unsicherheitsspanne oder geprüfte Vollständigkeit wird nicht behauptet. Materialschichten werden nicht aufgeteilt, native Archicad-PLN-Dateien werden nicht unterstützt.
- BMWSB, BMWE und BMUKN sowie produktspezifische EPDs sind noch nicht angebunden. Die Produktkataloge von Knauf, Wienerberger, Bundesverband Ziegel und KS-ORIGINAL dienen ausschließlich der Produktidentifikation, nie als Ökobilanzbelege.
- WECOBIS wird nur als qualitativer Materialkontext verlinkt; veröffentlichte IBU-EPDs sind als manuelle öffentliche Prüfquelle verlinkt, werden aber nicht automatisch numerisch ausgelesen. IBU.data-XML-Downloads mit Registrierung und allgemeine Websuche ohne zulässigen öffentlichen Endpunkt sind nicht angebunden. Nicht belegte GWP-Werte bleiben außerhalb der Teilbilanz.
- Die ÖKOBAUDAT-Version und der CSV-Download werden aus der offiziellen Downloadseite gelesen; die konkrete Datenstock-ID wird nicht mehr fest im Programmcode angenommen. Die CSV wird vor dem Ersetzen des Caches auf erwartete Spalten und EN-15804+A2/A1–A3-Datensätze geprüft. Ein lokaler Metadaten-Sidecar speichert Release, Datenstock-ID, offizielle Download-URL und Abrufzeit; Such- und Detailantworten ergänzen `provenance`, ohne die vorhandenen `/api/search`- und `/api/detail`-Felder zu entfernen. Bei fehlgeschlagener Release-Prüfung oder Aktualisierung bleibt ein vorhandener Cache nutzbar, wird aber mit Datenstand-/Cache-Warnung gekennzeichnet.
- Der quellenbewusste lokale Katalog wird aus diesem CSV-Cache beim Laden im Arbeitsspeicher aufgebaut. `catalog\manifest.json` unter `%LOCALAPPDATA%\CO-Emissionsrechner\` erfasst Quelle, Release, Datenstock, Abruf-/Cache-Status, Quelldateigröße/-hash und Anzahl indexierter Datensätze; der Eintrag wird atomar aktualisiert. Der Katalog speichert keine zweite Datensatzkopie und wird weder ins Repository noch ins Frontend-Bundle übernommen. Die ÖKOBAUDAT ist öffentlich zugänglich, aber eine pauschale Lizenz zur Weitergabe wurde nicht verifiziert; die Oberfläche legt diese Grenze offen. Es sind keine weiteren Quellen angebunden.
- Die Suche erweitert bekannte Materialbegriffe deterministisch um ausgewählte deutsche und englische Synonyme (z. B. Beton/concrete, Kalksandstein/calcium silicate brick, Holzfaser/wood fibre insulation). Das ist eine begrenzte Aliasliste, keine Übersetzung beliebiger Materialnamen und keine allgemeine Websuche.
- ÖKOBAUDAT dokumentiert eine standardisierte Datenaustauschschnittstelle, über die Datensätze gelesen werden können. Die Downloadseite bestätigt einen öffentlichen CSV-Export und dessen Release. Ein konkreter, dokumentierter Lesezugang für die Schnittstelle wurde nicht ermittelt; die App verwendet deshalb den dort offiziell verlinkten CSV-Export und behauptet keine direkte API-Integration.
