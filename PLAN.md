# Umsetzungsplan: Material- und Ökobilanz-App

## Ziel

Eine kleine, deutschsprachige Web-App für Architekturstudierende. Nutzerinnen und Nutzer suchen ein Material und erhalten nachvollziehbare ÖKOBAUDAT-Werte sowie Hinweise auf vergleichbare Datensätze mit niedrigeren CO₂-Werten. Die App soll mit viel Weißraum und Blau als Akzentfarbe schlicht und übersichtlich sein.

## Aktueller Stand

Ein lokal ausprobierbarer Prototyp ist umgesetzt. Unter Windows startet ein Doppelklick auf `Start-App.bat` die App im Browser. Beim ersten Suchen lädt ein lokaler PowerShell-Server den offiziellen ÖKOBAUDAT-CSV-Export (ungefähr 50 MB) und speichert ihn im Benutzerprofil zwischen. Der Cache wird nach einem Tag erneuert. Es ist keine zusätzliche Softwareinstallation erforderlich.

Der Prototyp nutzt ÖKOBAUDAT 2024-II und wertet Datensätze nach EN 15804+A2 für die Produktionsphase A1–A3 aus. Er bietet:

- Suche nach Materialnamen und Auswahl eines Treffers mit Datensatzdetails.
- GWP total (Treibhauspotenzial) sowie bis zu neun weitere Umweltindikatoren, falls Werte vorhanden sind.
- Vergleichsdatensätze aus derselben ÖKOBAUDAT-Hauptkategorie, Bezugsmenge, Einheit und Lebenszyklusphase; niedrigere CO₂-Werte werden zuerst angezeigt.
- Eine relative Ampel für den CO₂-Vergleich. Gibt es weniger als drei passende Datensätze, wird keine sichere Einstufung vorgenommen.
- Eine optionale Auswahl für den Bauteil-Einsatz. Sie dient derzeit nur als Kontext und filtert die Suche oder Alternativen nicht.
- Hinweise auf Quelle, Datenstand und Grenzen der Vergleichbarkeit.

Die Ampel ist kein allgemeingültiges Gütesiegel. Negative CO₂-Werte können biogenen Kohlenstoff im Material abbilden. A1–A3 ist nur die Produktionsphase und keine vollständige Lebenszyklusbilanz. Ein niedrigerer Wert belegt keine technische Austauschbarkeit; Alternativen sind ökologische Hinweise und keine bautechnische Freigabe.

## Umsetzungsplan und Fortschritt

1. **Projekt und Datenzugriff klären — teilweise erledigt**
   Der ÖKOBAUDAT-CSV-Export ist eingebunden. Für eLCA ist noch zu klären, ob es einen geeigneten und erlaubten direkten Datenzugriff gibt. „LCA Bau“ ist als Quelle noch nicht eindeutig identifiziert.

2. **Vergleichsregeln festlegen — erste Regeln umgesetzt, fachliche Abstimmung offen**
   Der Prototyp vergleicht Datensätze derselben ÖKOBAUDAT-Hauptkategorie, Bezugsmenge und Einheit in A1–A3 und stellt niedrigere GWP-Werte zuerst dar. Die Ampel zeigt nur eine relative Einordnung innerhalb der Vergleichsgruppe, keine allgemeingültigen Grenzwerte. Diese Regeln sollten mit der Gruppe fachlich geprüft werden.

3. **Materialsuche und Bauteil-Einsatz bauen — teilweise erledigt**
   Die Materialsuche ist umgesetzt. Der Bauteil-Einsatz kann ausgewählt werden, ist aber noch nicht mit den Datensatzkategorien verknüpft und beeinflusst die Treffer nicht.

4. **Bilanz und Ampel verständlich anzeigen — erste Version umgesetzt**
   GWP total, verfügbare Umweltindikatoren, Datensatz-Metadaten und die relative Ampel werden angezeigt. Fehlende Werte und zu kleine Vergleichsgruppen werden kenntlich gemacht.

5. **Alternativen vorschlagen — erste Version umgesetzt**
   Es werden Datensätze mit passender Vergleichsgrundlage gezeigt. Die Vorschläge bestätigen keine bautechnische Eignung oder Austauschbarkeit.

6. **Oberfläche gestalten und prüfen — erste Version umgesetzt**
   Die responsive Oberfläche ist deutschsprachig und nutzt viel Weißraum, Blau und Ampelfarben. Suche und Darstellung wurden mit ÖKOBAUDAT-Treffern geprüft. Eine automatische Testsuite gibt es derzeit nicht.

## Offene nächste Schritte

1. Die Vergleichsgruppe und die relative Ampel mit der Gruppe fachlich abstimmen.
2. Den genauen Anbieter beziehungsweise die Website hinter „LCA Bau“ klären und Nutzungsbedingungen sowie Datenzugriff für weitere Quellen prüfen.
3. Festlegen, welche Bauteil-Einsätze zuverlässig auf Materialkategorien abgebildet werden können, und die Auswahl erst danach als Suchfilter verwenden.
4. Prüfen, ob weitere Tests für Datenlücken, veraltete Cache-Daten und verschiedene Suchbegriffe sinnvoll ergänzt werden sollen.

## Hinweise zu den Datenquellen

- **ÖKOBAUDAT:** Die offizielle Website beschreibt eine kostenlose Datensammlung für die Ökobilanzierung von Bauwerken. Sie weist darauf hin, dass ÖKOBAUDAT nicht für Produkt-Ökobilanzen zulässig ist. Die App darf Bauwerksvergleiche deshalb nicht als Produkt-Ökobilanzen darstellen. [oekobaudat.de](https://www.oekobaudat.de/)
- **eLCA:** Der [eLCA-Bauteileditor](https://www.bauteileditor.de/) nutzt unter anderem ÖKOBAUDAT-Daten zur Bilanzierung von Bauwerken. Ein separater, geeigneter und erlaubter Datenzugriff für diese App ist noch nicht bestätigt.
- **LCA Bau:** Die genaue Website und eine öffentlich nutzbare Datenschnittstelle sind noch nicht verlässlich identifiziert.
