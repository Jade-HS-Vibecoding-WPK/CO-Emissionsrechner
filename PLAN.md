# Umsetzungsplan: Material- und Ökobilanz-Assistent

## Ziel und Produktumfang

Die bestehende Web-App soll zu einem leicht verständlichen Assistenten für die ökologische Einordnung von Baustoffen und Bauprodukten weiterentwickelt werden. Die gute vorhandene Aufmachung bleibt Ausgangspunkt; das Vorhaben ist kein Anlass für einen vollständigen visuellen Neustart.

Der zentrale Einstieg ist eine einfache Freitextabfrage: Eine Person kann beispielsweise „Beton“ eingeben, ohne zuerst Hersteller, Produktlinie oder technische Eigenschaften auswählen zu müssen. Die App erklärt, welche belastbaren Datensätze zu der Anfrage passen, zeigt deren ökologische Einordnung samt CO₂-Fußabdruck und macht Unterschiede und Datenlücken sichtbar. Wenn eine Einordnung orange oder rot ausfällt, zeigt sie – sofern geeignete und vergleichbare Datensätze vorliegen – ökologisch bessere Alternativen. Eine Produkt- oder Materialabfrage ist vollständig nutzbar, auch wenn kein 3D-Modell hochgeladen wird.

Optional soll ein 3D-Modell zur Prüfung eingereicht werden können. Der erste realistische Schwerpunkt liegt auf einem von Archicad exportierten IFC-Modell, in dem Bauteile und Materialangaben enthalten sind. Aus dem Modell erkannte Materialien und Mengen werden nur ausgewertet, soweit sie verlässlich zugeordnet werden können. Die App weist auf problematische beziehungsweise nicht bewertbare Positionen hin und schlägt für belastbar bewertete schlechte Positionen Alternativen vor. Eine direkte Verarbeitung nativer Archicad-Projektdateien (.PLN) oder eine verlustfreie Übernahme beliebiger 3D-Modelle wird nicht vorausgesetzt.

## Verbindliche Daten- und Bewertungsgrundsätze

- Für ökologische Kennwerte, Ampeln und Vergleiche werden ausschließlich nachvollziehbare und methodisch vergleichbare ÖKOBAUDAT-/Ministeriums-Daten verwendet. Verfügbare produktspezifische EPDs oder Ökobilanzbelege können als ergänzende Nachweise angezeigt und berücksichtigt werden, wenn Methode, Einheit und Bilanzgrenze transparent und für den konkreten Vergleich geeignet sind. EPDs begründen keine frei gewählten Ampelschwellen und erlauben keinen Vergleich außerhalb einer nachvollziehbaren gemeinsamen Methode und Bilanzgrenze.
- Zusätzlich dürfen die folgenden Seiten ausschließlich für Produktkatalog- und Produktidentifikationsangaben wie Produktname, Produktgruppe und veröffentlichte technische Merkmale herangezogen werden:
  - Knauf, Produktübersicht: https://knauf.com/de-DE/p/produkte
  - Wienerberger, Ziegelprodukte: https://www.wienerberger.de/produkte/wand/ziegel.html?xvtxmc_loadmore=2
  - Bundesverband Ziegel, Produkte: https://www.ziegel.de/produkte
  - KS-ORIGINAL, Produkte: https://www.ks-original.de/kalksandstein/produkte
- Katalogangaben und Marketingtexte sind keine Belege für ökologische Kennwerte. Aus ihnen dürfen weder CO₂-Werte noch Ökobilanzresultate, Ampelfarben oder ökologische Rangfolgen abgeleitet werden. Fehlen geeignete ökologische Daten oder belastbare Nachweise, zeigt die App die Bewertung als fehlend beziehungsweise unsicher und benennt die Datenlücke, statt Werte aus Produktbeschreibungen abzuleiten.
- Für jeden angezeigten Wert werden Quelle, Datensatz/Bezeichnung, Bezugs- beziehungsweise deklarierte Einheit, betrachtete Lebenszyklusmodule oder Bilanzgrenzen, Gültigkeits-/Versionsangabe soweit verfügbar und Abruf- oder Veröffentlichungsstand nachvollziehbar dargestellt. Es wird keine amtliche Empfehlung oder Zertifizierung suggeriert, wenn die Quelle das nicht ausdrücklich aussagt.
- Die Ampel wird nur angewendet, wenn eine dokumentierte, fachlich begründete Bewertungsregel für die jeweilige Kennzahl, Einheit und Vergleichsgruppe verfügbar ist. Schwellenwerte werden nicht frei erfunden und nicht über inkompatible Einheiten, Produktkategorien oder Lebenszyklusgrenzen hinweg verglichen. Ist keine belastbare Regel vorhanden, zeigt die App den Zahlenwert und seine Einordnung als „nicht klassifiziert“ statt eine scheinbar objektive Farbe.
- CO₂-Werte sind mit Einheit und Bilanzgrenze auszuweisen; „CO₂-Fußabdruck“ darf nicht unterschiedliche Treibhausgasindikatoren, Module oder deklarierte Einheiten zusammenfassen. Umrechnungen, etwa auf eine Modellmenge, sind nur zulässig, wenn Eingangsdaten und Umrechnungsweg dokumentiert sind.
- Fehlende, veraltete, widersprüchliche oder nur teilweise passende Daten werden deutlich als Unsicherheit gekennzeichnet. Die App schätzt fehlende Werte nicht stillschweigend und setzt „keine Daten“ nicht mit „ökologisch schlecht“ gleich.
- Alternativen gelten nur dann als besser, wenn sie in einer nachvollziehbaren, möglichst direkten Vergleichsgruppe anhand derselben relevanten Kennzahl, Einheit und Bilanzgrenze einen niedrigeren Wert aufweisen. Die Vergleichbarkeit und verbleibende Einschränkungen werden angezeigt; andernfalls wird keine Rangfolge behauptet.

## Umsetzungsphasen

### Phase 1 – Bestand, Datenzugang und fachliche Bewertungsregeln klären

1. Vorhandene Gestaltung, Navigation und technische Struktur aufnehmen und bewährte Elemente erhalten.
2. Verfügbarkeit, Nutzungsbedingungen und Aktualisierungsweg der ÖKOBAUDAT-/Ministeriumsquellen sowie Verfügbarkeit und Bedingungen der vier zusätzlichen Produktkataloge prüfen. In einer Quellenübersicht werden Quellen und Zweck getrennt dokumentiert: ökologische Bewertungsdaten, ergänzende EPD-/Ökobilanzbelege und reine Produkt-/Katalogangaben.
3. Für Materialsuche, CO₂-Kennzahlen, Ampel-Schwellen und Alternativen festlegen, welche belastbaren Quellenaussagen tatsächlich verfügbar sind. Nicht durch Quellen gedeckte Regeln bleiben ausdrücklich offen und werden nicht als fertiges Feature eingeplant.
4. Unterstützte Datenfelder, Einheiten, Lebenszyklusmodule und Umgang mit veralteten oder fehlenden Datensätzen festlegen.

**Abnahme:** Es gibt eine überprüfbare Quellen- und Bewertungsübersicht mit den bestehenden ÖKOBAUDAT-/Ministeriumsquellen und den vier zusätzlich genannten Katalogseiten, jeweils mit klar getrenntem Verwendungszweck. Jede Ampel- und Vergleichsregel ist einer belastbaren ökologischen Quelle und einer klaren Vergleichsgrundlage zugeordnet; nicht belegbare Regeln sind als offene Punkte markiert. Produktkataloge und Marketingtexte werden nicht als ökologische Belege geführt.

### Phase 2 – Einfache Material- und Produktabfrage

1. Eine Freitextsuche ermöglichen, die allgemeine Begriffe wie „Beton“ ohne zwingende Hersteller-, Produkt- oder Typauswahl annimmt.
2. Ergebnisse bei Bedarf nach Materialgruppe beziehungsweise Datensatz auffächern und Unterschiede erklären, statt einen einzelnen Treffer als allgemeingültige Bewertung für das Material auszugeben. Die zusätzlichen Katalogquellen können bei der Produktidentifikation und Anzeige von Produktangaben helfen; diese Angaben werden sichtbar von ökologischen Kennwerten und deren Quellen getrennt.
3. Ökologische Ampel und CO₂-Wert inklusive Einheit, Bezugsgröße, Bilanzgrenze, Datenquelle und Datenstand anzeigen, sofern die Daten eine fachlich gültige Einordnung erlauben.
4. Bei orange/rot passende bessere Alternativen anhand geeigneter ÖKOBAUDAT-/Ministeriums-Daten vorschlagen. Produktkataloge können zur Identifikation entsprechender Produkte dienen, nicht als Nachweis ihrer ökologischen Überlegenheit. Vergleichbarkeit und Gründe für die Empfehlung offenlegen.
5. Für fehlende oder nicht vergleichbare Daten einen verständlichen Zustand wie „keine belastbare Bewertung möglich“ anbieten.

**Abnahme:** Eine Eingabe wie „Beton“ ist ohne weitere Pflichtangaben ausführbar. Produktangaben aus den vier Katalogen sind klar als solche erkennbar und getrennt von ÖKOBAUDAT-/Ministeriums-Daten und verfügbaren EPD-/Ökobilanzbelegen dargestellt. Das Ergebnis erfindet keine materialspezifische Sicherheit aus einem beliebigen Einzelprodukt oder Marketingtext; es zeigt für ökologische Werte Quelle, CO₂-Einheit und Bilanzgrenze. Orange/rot führt nur bei belegtem, vergleichbarem Datensatz zu einer als solche erklärten Alternative. Ohne ausreichende Daten wird keine Ampelfarbe oder scheinbar präzise Rangfolge ausgegeben.

### Phase 3 – Optionaler 3D-Modell-Import und Modellprüfung

1. Den Modell-Upload als optionalen, separaten Einstieg anbieten; die Material-/Produktabfrage bleibt unabhängig davon verfügbar.
2. Als erste Austauschgrenze IFC-Dateien vorsehen, vorzugsweise einen überprüften Archicad-IFC-Export. Vor Umsetzung prüfen, welche IFC-Versionen und Property-/Materialzuordnungen die verwendete Importtechnik zuverlässig lesen kann.
3. Native Archicad-PLN-Dateien nicht als direkt unterstütztes Format versprechen. Bei nicht unterstützten oder fehlerhaften Formaten verständlich auf einen geeigneten IFC-Export verweisen.
4. Bauteile, vorhandene Material-/Produktbezeichnungen, Mengen und Einheiten nur übernehmen, wenn sie aus dem Modell verlässlich auslesbar sind. Unklare oder fehlende Angaben als nicht zugeordnet kennzeichnen und gegebenenfalls gezielte manuelle Zuordnung ermöglichen; keine nicht belegte automatische Produkterkennung behaupten.
5. Modellpositionen mit geeigneten ÖKOBAUDAT-/Ministeriumsdatensätzen verknüpfen, CO₂- und Ökobilanzwerte nur innerhalb der jeweiligen Datenabdeckung berechnen und die Zuordnung sowie Berechnungsannahmen je Position nachvollziehbar machen.
6. Schlechte bewertete Positionen mit vergleichbaren Alternativen versehen. Nicht bewertbare Positionen, fehlende Mengen oder inkompatible Bezugsgrößen separat ausweisen und nicht in eine vollständige Gebäudebilanz hochrechnen.
7. Dateigröße, Verarbeitungsfehler und Datenschutz/Löschverhalten für hochgeladene Modelle vor Freigabe festlegen und transparent kommunizieren.

**Abnahme:** Ein unterstützter IFC-Testexport wird entweder mit erkannten Bauteilen und nachvollziehbaren Material-/Mengen-Zuordnungen ausgewertet oder mit konkretem Grund als nicht auswertbar gemeldet. Die Ergebnisse zeigen Datenquelle, Einheit, Bilanzgrenze und Zuordnung je Position. Fehlende Angaben werden nicht still ergänzt. Die Oberfläche funktioniert weiterhin vollständig ohne Modell-Upload; native PLN-Unterstützung wird nicht behauptet, solange sie nicht nachweislich implementiert und getestet ist.

### Phase 4 – Qualitätssicherung und Freigabe

1. Suchfälle für allgemeine Begriffe, mehrere Treffer, fehlende Daten und nicht kompatible Vergleiche prüfen.
2. Berechnungen und Darstellungen anhand dokumentierter Quell-Datensätze, Einheiten und Lebenszyklusgrenzen verifizieren.
3. IFC-Import mit repräsentativen, zulässigen Testmodellen einschließlich fehlender Materialzuordnung, fehlender Mengen und nicht unterstützter Dateien prüfen.
4. Verständlichkeit, Tastaturbedienbarkeit, Fehlerzustände und Erhalt der vorhandenen Gestaltung prüfen.
5. Quellenstände und bekannte Einschränkungen für Nutzer sichtbar und für Wartung nachvollziehbar dokumentieren.

**Abnahme:** Für alle unterstützten Fälle sind Werte und Umrechnungen reproduzierbar; unvollständige Fälle liefern einen klaren Hinweis statt einer irreführenden Bilanz. Die festgelegten Importgrenzen und Fehlerzustände sind getestet. Es werden weder nicht freigegebene Quellen verwendet noch unbelegte ökologische Empfehlungen ausgegeben.

## Explizite Grenzen und offene Prüfungen

- Diese Planung setzt weder voraus, dass jede allgemeine Materialanfrage einen einzelnen eindeutigen ÖKOBAUDAT-Datensatz besitzt, noch dass alle Datensätze zu einer allgemeinen Ampel-Skala zusammengeführt werden können.
- Ob offizielle Ministeriumsseiten zusätzliche nutzbare Datensätze, Schwellenwerte oder Bewertungsmethoden bereitstellen und ob auf den Katalogseiten produktspezifische EPD-/Ökobilanzbelege verfügbar sind, ist in Phase 1 anhand der tatsächlichen Inhalte und Bedingungen zu verifizieren. Die bloße Nennung eines Ministeriums, Produktbeschreibung oder Werbeaussage ist keine fachliche Begründung für einen ökologischen Bewertungswert.
- Eine Archicad-Datei im nativen PLN-Format kann proprietäre beziehungsweise nicht offen unterstützte Strukturen enthalten. Der Plan verspricht daher zunächst nur den nach Prüfung konkret unterstützten IFC-Export, nicht den Import jeder Archicad-Version oder beliebiger 3D-Formate.
- Eine vollständige Gebäude-Ökobilanz ist nur dann möglich, wenn Modellgeometrie, Mengen, Einheiten, Bauteilzuordnungen und passende Datensätze hinreichend vollständig und methodisch kompatibel sind. Andernfalls bleibt das Ergebnis eine partielle, entsprechend gekennzeichnete Auswertung.
- Umsetzung der Web-App und Integration der Daten beginnen erst nach Prüfung und Freigabe dieses Plans.
