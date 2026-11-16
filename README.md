# CO₂- und Ökobilanz-Rechner

Eine kleine Web-App für Architekturstudierende. Suche ein Baumaterial und sieh dir dessen CO₂-Wert und weitere verfügbare Umweltindikatoren an. Die App hilft beim Vergleichen mit ähnlichen Datensätzen aus derselben Materialkategorie.

## App ausprobieren (Windows)

1. Öffne diesen Projektordner im Datei-Explorer.
2. Doppelklicke auf **Start-App.bat**. Es öffnet sich ein Fenster mit dem lokalen Webserver und anschließend die App im Browser.
3. Gib einen Suchbegriff wie „Dämmstoff“, „Holz“ oder „Beton“ ein und wähle einen Treffer aus.
4. Beim ersten Suchen lädt die App etwa 50 MB Daten von ÖKOBAUDAT. Das braucht eine Internetverbindung und kann etwas dauern. Die Datei wird lokal zwischengespeichert, damit spätere Suchen schneller sind.
5. Wenn du fertig bist, schließe das Fenster des lokalen Webservers.

Es muss nichts zusätzlich installiert werden. Die App läuft nur auf deinem eigenen Rechner.

## Unsere bisherigen Entscheidungen

- **Daten:** Gewünscht sind Informationen von ÖKOBAUDAT, eLCA und LCA Bau. Die erste App-Version lädt ÖKOBAUDAT-Daten live; eLCA und LCA Bau sind noch nicht separat angebunden.
- **Bilanz:** CO₂ soll zusammen mit weiteren Umweltwerten angezeigt werden, wenn verlässliche Daten dafür vorliegen.
- **Bauteil-Einsatz:** Der geplante Einsatz, zum Beispiel Außenwand oder Dämmung, kann ausgewählt werden. Die Auswahl hilft bei der Einordnung; die Alternativen selbst werden nach derselben ÖKOBAUDAT-Kategorie, Bezugsmenge, Einheit und Lebenszyklusphase verglichen.
- **Fehlende Daten:** Die App soll keine Werte erfinden oder schätzen. Sie soll fehlende Daten klar anzeigen.
- **Bewertung:** Materialien sollen mit einem Ampelsystem bewertet werden: Rot = schlecht, Orange = mittel, Grün = gut. Die Bewertung muss auf nachvollziehbaren, vergleichbaren Daten beruhen und darf keine allgemeingültige Aussage vortäuschen.
- **Gestaltung:** Schlicht, einfach und übersichtlich, mit viel Weißraum und Blau als Akzentfarbe.
- **Erklärungen:** Die Umsetzung soll in einfachen Schritten erklärt werden, ohne Programmierkenntnisse vorauszusetzen.

## Aktueller Stand

1. Materialname eingeben.
2. Optional den geplanten Einsatz im Entwurf auswählen. Diese Auswahl dient nur als Kontext und filtert die Treffer noch nicht.
3. Einen Treffer auswählen und CO₂-Wert, bis zu neun weitere verfügbare Umweltindikatoren sowie Angaben zum Datensatz ansehen.
4. Vergleichbare Datensätze derselben ÖKOBAUDAT-Hauptkategorie, Bezugsmenge, Einheit und Lebenszyklusphase prüfen. Die niedrigeren CO₂-Werte werden zuerst angezeigt.

Verwendet wird der ÖKOBAUDAT-Datenbestand 2024-II mit Datensätzen nach EN 15804+A2 für die Produktionsphase A1–A3. Die Ampel ordnet den CO₂-Wert relativ innerhalb der passenden Vergleichsgruppe ein; bei weniger als drei vergleichbaren Datensätzen wird keine sichere Einstufung vorgenommen. Sie ist kein allgemeines Gütesiegel. Ein niedrigerer CO₂-Wert allein beweist nicht, dass ein Material technisch austauschbar ist. Die Vorschläge sind ökologische Hinweise und keine bautechnische Freigabe. A1–A3 bildet nicht den gesamten Lebenszyklus ab.

## Hinweise zu den gewünschten Datenquellen

- **ÖKOBAUDAT:** Die offizielle Website beschreibt eine kostenlose Datensammlung zur Ökobilanzierung von Bauwerken und nennt eine standardisierte Schnittstelle für den Datenaustausch. Sie weist darauf hin, dass ÖKOBAUDAT nicht für Produkt-Ökobilanzen zulässig ist. Die App darf Bauwerksvergleiche daher nicht als Produkt-Ökobilanzen darstellen.
  [oekobaudat.de](https://www.oekobaudat.de/)
- **eLCA:** Die geprüfte offizielle Einstiegsseite ist der [eLCA-Bauteileditor](https://www.bauteileditor.de/). ÖKOBAUDAT nennt eLCA als Werkzeug, das ÖKOBAUDAT-Daten zur Bilanzierung von Bauwerken nutzt. Daher muss vorab geklärt werden, ob eLCA für die App eine eigene, erlaubte Datenquelle sein kann oder vor allem als Werkzeug für Bauteil-Kontext dient.
- **LCA Bau:** Die genaue Website und eine öffentlich nutzbare Datenschnittstelle sind noch nicht verlässlich identifiziert. Vor der Anbindung muss geklärt werden, welche Seite gemeint ist und ob ihre Daten für diese Nutzung verfügbar sind.

Die Abfrage verwendet den offiziellen ÖKOBAUDAT-CSV-Export. Um die Daten im Browser abrufen zu können, startet **Start-App.bat** einen kleinen lokalen PowerShell-Webserver. Die heruntergeladene Datei liegt im Windows-Benutzerprofil unter `%LOCALAPPDATA%\CO-Emissionsrechner` und wird nach einem Tag erneut geladen. Quelle, Datenstand und Vergleichsgrundlage werden in der App angezeigt. Der Server ist nur während des geöffneten Serverfensters erreichbar.

## Nächste Schritte

1. Mit der Gruppe abstimmen, wie die relative Ampel und die Vergleichsregeln fachlich eingeordnet werden sollen.
2. Zugriffsmöglichkeiten und Nutzungsbedingungen für eLCA prüfen und die genaue Quelle „LCA Bau“ identifizieren.
3. Bauteil-Einsätze künftig mit passenden Materialkategorien verknüpfen, damit sie mehr als Kontext bieten.

Der [Umsetzungsplan](PLAN.md) hält fest, was bereits umgesetzt wurde und welche Punkte noch offen sind.
