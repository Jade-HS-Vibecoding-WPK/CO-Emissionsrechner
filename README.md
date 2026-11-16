# CO-Emissionsrechner

Lokaler Prototyp für die Suche nach Baustoff-Datensätzen und den Vergleich ausgewiesener ÖKOBAUDAT-GWP-Werte.

## Starten

Unter Windows `Start-App.bat` öffnen. Die App läuft lokal unter `http://127.0.0.1:8765/`. Für die erste Suche ist eine Internetverbindung zum ÖKOBAUDAT-CSV-Export erforderlich; der Export wird lokal zwischengespeichert.

## Umfang und Grenzen

- Die Suche zeigt höchstens zehn zusammengefasste Materialgruppen; wiederkehrende Rezept-/Werkvarianten werden gebündelt. Datensatzversionen, Quellen, Einheiten, Bezugsgrößen und Gültigkeit bleiben in den Detailansichten sichtbar.
- „Gut“, „mittel“ und „schlecht“ sind vorläufige relative Drittel ausschließlich innerhalb gültiger ÖKOBAUDAT-Datensätze mit gleicher Kategorie, Einheit, Bezugsmenge, Norm und Lebenszyklusphase sowie passendem Namens-/Technikprofil. Gleiche Werte werden nicht getrennt, daher können die Gruppen unterschiedlich groß sein. Bei weniger als drei passenden Datensätzen oder identischen GWP-Werten bleibt die Einordnung nicht klassifiziert.
- Ein niedrigerer GWP-Wert wird nur als Datensatzvergleich innerhalb derselben vorläufigen Vergleichsgruppe gezeigt. Gemeinsam verfügbare Indikatoren werden mit beiden Rohwerten und Einheiten separat ausgewiesen; sie werden nicht zu einer Gesamtpunktzahl verrechnet. Das ist kein Materialersatz und bestätigt keine technische oder funktionale Gleichwertigkeit.
- Die Einsatz-Auswahl wird für einen separaten, bedingten Materialalternativen-Check verwendet, filtert aber keine Suchtreffer. Bei Beton für Außenwand oder Mauerwerk kann Kalksandstein-Mauerwerk als ausdrücklich unbestätigter Prüfpfad erscheinen. Es wird kein GWP-Vorteil behauptet: Die derzeitigen Datensätze erlauben keinen fairen Vergleich gleichwertiger vollständiger Bauteile. Für andere Fälle wird keine Materialalternative erfunden.
- Die Materialalternativen-Prüfung ist noch nicht mit einer verifizierten Zuordnung funktional vergleichbarer Bauteile oder ergänzenden offiziellen Quellen verbunden. Ihre Prüfpunkte machen die fehlenden technischen Randbedingungen sichtbar; sie ersetzen keine Planung oder Nachweise.
- Der IFC-Bereich ist nur ein UI-Prototyp: Dateien werden weder hochgeladen noch gelesen. Native Archicad-PLN-Dateien werden nicht unterstützt.
- BMWSB, BMWE und BMUKN sowie produktspezifische EPDs sind noch nicht angebunden. Die Produktkataloge von Knauf, Wienerberger, Bundesverband Ziegel und KS-ORIGINAL dienen ausschließlich der Produktidentifikation, nie als Ökobilanzbelege.
