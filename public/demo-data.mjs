const demoItems = [
  {
    Id: "demo-concrete-a",
    Name: "DEMO-Beispiel: Beton – Variante A",
    SearchTerms: ["beton", "concrete"],
    Category: "DEMO / synthetisches Beispielszenario",
    CategoryGroup: "DEMO / Beispielmaterial",
    ComparisonClass: "synthetische Demo-Variante",
    Unit: "m³",
    ReferenceAmount: "1",
    Gwp: 125,
    Owner: "Demo – keine Quelle",
    ReferenceYear: "Demo – kein Datenjahr",
    ValidUntil: "Demo – nicht geprüft",
    Validity: "valid",
  },
  {
    Id: "demo-concrete-b",
    Name: "DEMO-Beispiel: Beton – Variante B",
    SearchTerms: ["beton", "concrete"],
    Category: "DEMO / synthetisches Beispielszenario",
    CategoryGroup: "DEMO / Beispielmaterial",
    ComparisonClass: "synthetische Demo-Variante",
    Unit: "m³",
    ReferenceAmount: "1",
    Gwp: 240,
    Owner: "Demo – keine Quelle",
    ReferenceYear: "Demo – kein Datenjahr",
    ValidUntil: "Demo – nicht geprüft",
    Validity: "valid",
  },
  {
    Id: "demo-concrete-c",
    Name: "DEMO-Beispiel: Beton – Variante C",
    SearchTerms: ["beton", "concrete"],
    Category: "DEMO / synthetisches Beispielszenario",
    CategoryGroup: "DEMO / Beispielmaterial",
    ComparisonClass: "synthetische Demo-Variante",
    Unit: "m³",
    ReferenceAmount: "1",
    Gwp: 380,
    Owner: "Demo – keine Quelle",
    ReferenceYear: "Demo – kein Datenjahr",
    ValidUntil: "Demo – nicht geprüft",
    Validity: "valid",
  },
  {
    Id: "demo-insulation",
    Name: "DEMO-Beispiel: Dämmstoff",
    SearchTerms: ["dämmstoff", "dämmung", "insulation"],
    Category: "DEMO / synthetisches Beispielszenario",
    CategoryGroup: "DEMO / Beispielmaterial",
    ComparisonClass: "synthetischer Demo-Einzelwert",
    Unit: "m³",
    ReferenceAmount: "1",
    Gwp: 18,
    Owner: "Demo – keine Quelle",
    ReferenceYear: "Demo – kein Datenjahr",
    ValidUntil: "Demo – nicht geprüft",
    Validity: "valid",
  },
];

const demoSource = "DEMO / synthetische Beispieldaten – keine Quelle";

function toSearchItem(item) {
  return {
    ...item,
    FamilyName: item.Name,
    Gwp: item.Gwp,
    Rating: { Group: "nicht vergleichbar", Rank: null, Count: null },
    Url: "",
    SourceName: demoSource,
    Metrics: [],
  };
}

export function searchDemoData(query) {
  const normalizedQuery = String(query || "").trim().toLocaleLowerCase("de");
  const matches = demoItems.filter((item) =>
    [item.Name, item.Category, ...item.SearchTerms]
      .some((value) => value.toLocaleLowerCase("de").includes(normalizedQuery)),
  );
  const groups = matches.map((item) => ({
    Name: item.Name,
    Category: item.Category,
    CategoryGroup: item.CategoryGroup,
    Count: 1,
    PeerGroups: [{
      Status: "incomplete",
      ComparisonClass: item.ComparisonClass,
      Unit: item.Unit,
      ReferenceAmount: item.ReferenceAmount,
      RatingGroup: "nicht vergleichbar",
      Count: 1,
      Items: [toSearchItem(item)],
    }],
  }));
  return {
    query: String(query || ""),
    matchedTerms: [],
    count: matches.length,
    groupCount: groups.length,
    groups,
    retrievedAt: "Keine Erhebung – statische Demo-Beispiele",
    source: demoSource,
  };
}

export function getDemoDetail(id, application = "") {
  const item = demoItems.find((candidate) => candidate.Id === id);
  if (!item) throw new Error("Unbekanntes Demo-Beispiel.");
  const detailItem = toSearchItem(item);
  return {
    item: detailItem,
    rating: detailItem.Rating,
    comparison: {
      category: item.Category,
      technicalClass: item.ComparisonClass,
      unit: item.Unit,
      referenceAmount: item.ReferenceAmount,
      count: 1,
      comparable: false,
      reason: "Synthetische Beispielwerte ohne Quelle; keine Ökobilanz oder Vergleichsaussage.",
    },
    materialAlternative: {
      Status: "not_available",
      Candidate: "",
      Application: application,
      Reason: "Die Demo enthält keine geprüfte Materialalternative.",
      Checks: [],
    },
    alternatives: [],
    retrievedAt: "Keine Erhebung – statische Demo-Beispiele",
    source: demoSource,
  };
}
