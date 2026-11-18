import test from "node:test";
import assert from "node:assert/strict";
import {
  assessProjectDataQuality,
  calculateContribution,
  datasetUnitInfo,
  flattenSearchResults,
  isDatasetValid,
  parseIfcText,
  suggestIfcMaterialCategory,
  uniqueIfcSearchCandidates,
} from "../public/ifc.mjs";

function makeIfc({ schema = "IFC4", records = "", directMaterial = true } = {}) {
  return `ISO-10303-21;
HEADER;
FILE_DESCRIPTION(('ViewDefinition [CoordinationView]'),'2;1');
FILE_NAME('sample.ifc','2026-01-01T00:00:00',('test'),('test'),'','test','');
FILE_SCHEMA(('${schema}'));
ENDSEC;
DATA;
#1=IFCPROJECT('project',$,'Project',$,$,$,$,$,#2);
#2=IFCUNITASSIGNMENT((#3,#4,#5));
#3=IFCSIUNIT(*,.LENGTHUNIT.,.MILLI.,.METRE.);
#4=IFCSIUNIT(*,.AREAUNIT.,$,.SQUARE_METRE.);
#5=IFCSIUNIT(*,.VOLUMEUNIT.,$,.CUBIC_METRE.);
#6=IFCMATERIAL('Beton''s Rezept',$,$);
#7=IFCWALL('wall',$,'Südwand',$,$,$,$,$);
${directMaterial ? "#8=IFCRELASSOCIATESMATERIAL('material-rel',$,$,$,(#7),#6);" : ""}
#9=IFCQUANTITYLENGTH('Length',$,#3,2500.,$);
#10=IFCQUANTITYVOLUME('NetVolume',$,$,2.5,$);
#11=IFCELEMENTQUANTITY('qto',$,'BaseQuantities',$,$,(#9,#10));
#12=IFCRELDEFINESBYPROPERTIES('qto-rel',$,$,$,(#7),#11);
${records}
ENDSEC;
END-ISO-10303-21;`;
}

test("parses direct material, escaped names, and explicit IFC quantities", () => {
  const model = parseIfcText(makeIfc());
  assert.equal(model.schema, "IFC4");
  assert.equal(model.elements.length, 1);
  assert.deepEqual(model.elements[0].materials, ["Beton's Rezept"]);
  assert.equal(model.elements[0].materialStatus, "ready");
  assert.equal(model.elements[0].name, "Südwand");
  assert.deepEqual(
    model.elements[0].quantities.map(({ name, value, canonicalValue, unit, sourceUnit }) => ({ name, value, canonicalValue, unit, sourceUnit })),
    [
      { name: "Length", value: 2500, canonicalValue: 2.5, unit: "m", sourceUnit: "mm" },
      { name: "NetVolume", value: 2.5, canonicalValue: 2.5, unit: "m³", sourceUnit: "m³" },
    ],
  );
});

test("converts prefixed SI area and mass quantities to their canonical units", () => {
  const model = parseIfcText(makeIfc({
    records: `
#13=IFCSIUNIT(*,.AREAUNIT.,.CENTI.,.SQUARE_METRE.);
#14=IFCSIUNIT(*,.MASSUNIT.,.KILO.,.GRAM.);
#15=IFCQUANTITYAREA('GrossSideArea',$,#13,100000.,$);
#16=IFCQUANTITYWEIGHT('NetWeight',$,#14,500.,$);
#17=IFCELEMENTQUANTITY('qto-extra',$,'ExtraQuantities',$,$,(#15,#16));
#18=IFCRELDEFINESBYPROPERTIES('qto-extra-rel',$,$,$,(#7),#17);`,
  }));
  const quantities = model.elements[0].quantities;
  assert.equal(quantities.find(({ name }) => name === "GrossSideArea").canonicalValue, 10);
  assert.equal(quantities.find(({ name }) => name === "GrossSideArea").sourceUnit, "cm²");
  assert.equal(quantities.find(({ name }) => name === "NetWeight").canonicalValue, 500);
  assert.equal(quantities.find(({ name }) => name === "NetWeight").unit, "kg");
});

test("uses a material assigned to the IFC element type", () => {
  const model = parseIfcText(makeIfc({
    directMaterial: false,
    records: `
#13=IFCWALLTYPE('wall-type',$,'Wandtyp',$,$,$,$,$,$,$);
#14=IFCRELASSOCIATESMATERIAL('type-material',$,$,$,(#13),#6);
#15=IFCRELDEFINESBYTYPE('type-rel',$,$,$,(#7),#13);`,
  }));
  assert.equal(model.elements[0].materialSource, "Bauteiltyp");
  assert.deepEqual(model.elements[0].materials, ["Beton's Rezept"]);
});

test("does not fall back to a type material when the element has an unreadable direct assignment", () => {
  const model = parseIfcText(makeIfc({
    directMaterial: false,
    records: `
#13=IFCWALLTYPE('wall-type',$,'Wandtyp',$,$,$,$,$,$,$);
#14=IFCRELASSOCIATESMATERIAL('type-material',$,$,$,(#13),#6);
#15=IFCRELDEFINESBYTYPE('type-rel',$,$,$,(#7),#13);
#16=IFCMATERIALUNSUPPORTED('layer-set',$);
#17=IFCRELASSOCIATESMATERIAL('unreadable-material',$,$,$,(#7),#16);`,
  }));
  assert.equal(model.elements[0].materialStatus, "ambiguous");
  assert.deepEqual(model.elements[0].materials, []);
  assert.equal(model.elements[0].materialSource, "Bauteil");
});

test("supports IFC2x3 and refuses to guess between multiple project units", () => {
  const ifc2x3 = parseIfcText(makeIfc({ schema: "IFC2X3" }));
  assert.equal(ifc2x3.schema, "IFC2X3");

  const ambiguousUnits = makeIfc().replace(
    "#2=IFCUNITASSIGNMENT((#3,#4,#5));",
    "#2=IFCUNITASSIGNMENT((#3,#4,#5,#13));",
  ).replace(
    "ENDSEC;\nEND-ISO-10303-21;",
    "#13=IFCSIUNIT(*,.VOLUMEUNIT.,.MILLI.,.CUBIC_METRE.);\nENDSEC;\nEND-ISO-10303-21;",
  );
  const model = parseIfcText(ambiguousUnits);
  assert.match(model.elements[0].quantities[1].error, /Mehrere Projekteinhheiten/);
});

test("marks multiple associated materials as ambiguous", () => {
  const model = parseIfcText(makeIfc({
    records: `
#13=IFCMATERIAL('Stahl',$,$);
#14=IFCMATERIALLIST((#6,#13));
#15=IFCRELASSOCIATESMATERIAL('multiple-materials',$,$,$,(#7),#14);`,
  }));
  assert.equal(model.elements[0].materialStatus, "ambiguous");
  assert.deepEqual(new Set(model.elements[0].materials), new Set(["Beton's Rezept", "Stahl"]));
});

test("keeps multilayer assemblies ambiguous instead of assigning the whole quantity to one layer", () => {
  const model = parseIfcText(makeIfc({
    directMaterial: false,
    records: `
#13=IFCMATERIAL('Stahl',$,$);
#14=IFCMATERIALLAYER(#6,0.2,$,$,$,$,$);
#15=IFCMATERIALLAYER(#13,0.1,$,$,$,$,$);
#16=IFCMATERIALLAYERSET((#14,#15),$);
#17=IFCRELASSOCIATESMATERIAL('layered-material',$,$,$,(#7),#16);`,
  }));
  assert.equal(model.elements[0].materialStatus, "ambiguous");
  assert.deepEqual(new Set(model.elements[0].materials), new Set(["Beton's Rezept", "Stahl"]));
});

test("keeps explicitly contained elements with missing material or quantity data visible", () => {
  const model = parseIfcText(makeIfc({
    records: `
#13=IFCWALL('wall-without-data',$,'Innenwand',$,$,$,$,$);
#14=IFCRELCONTAINEDINSPATIALSTRUCTURE('containment',$,$,$,(#7,#13),#15);
#15=IFCBUILDINGSTOREY('storey',$,'EG',$,$,$,$,$,.ELEMENT.,0.);`,
  }));
  const unmeasured = model.elements.find((element) => element.id === "13");
  assert.equal(model.containmentAvailable, true);
  assert.equal(model.containedElementCount, 2);
  assert.equal(model.elements.every((element) => element.contained), true);
  assert.equal(unmeasured.materialStatus, "missing");
  assert.equal(unmeasured.quantities.length, 0);
});

test("includes supported IFC components without material, quantities, or relations", () => {
  const model = parseIfcText(makeIfc({
    records: "#13=IFCWALL('orphan-wall',$,'Unzugeordnete Wand',$,$,$,$,$);",
  }));
  const unassigned = model.elements.find((element) => element.id === "13");
  assert.ok(unassigned);
  assert.equal(unassigned.materialStatus, "missing");
  assert.deepEqual(unassigned.quantities, []);
  assert.equal(unassigned.contained, false);
});

test("material category matching returns suggestions, not exact matches", () => {
  assert.deepEqual(suggestIfcMaterialCategory("Concrete C30/37"), {
    name: "Beton",
    query: "Beton",
  });
  assert.deepEqual(suggestIfcMaterialCategory("Wood fibre board"), {
    name: "Holzfaser",
    query: "Holzfaser",
  });
  assert.equal(suggestIfcMaterialCategory("mystery composite"), null);
});

test("rejects empty, malformed, incomplete, and unsupported IFC files", () => {
  assert.throws(() => parseIfcText(""), /leer/);
  assert.throws(() => parseIfcText("not an IFC file"), /Kopf/);
  assert.throws(() => parseIfcText(makeIfc().replace("END-ISO-10303-21;", "")), /unvollständig/);
  assert.throws(() => parseIfcText(makeIfc({ schema: "IFC5" })), /nicht unterstützt/);
});

test("calculates contributions in compatible units and scales by reference amount", () => {
  const quantity = { dimension: "volume", canonicalValue: 2.5, unit: "m³" };
  const result = calculateContribution(quantity, { Unit: "m³", ReferenceAmount: "1,0", Gwp: 20, Validity: "valid" });
  assert.equal(result.datasetQuantity, 2.5);
  assert.equal(result.contribution, 50);

  const tonnes = calculateContribution(
    { dimension: "mass", canonicalValue: 1000, unit: "kg" },
    { Unit: "t", ReferenceAmount: 2, Gwp: 4, Validity: "valid" },
  );
  assert.equal(tonnes.datasetQuantity, 1);
  assert.equal(tonnes.contribution, 2);
});

test("assesses estimate quality from valid records, explicit mappings, and model scope", () => {
  const exactEntry = {
    material: " Beton ",
    dataset: { Name: "Beton", Validity: "valid" },
    calculation: { contribution: 50 },
    contained: true,
  };
  assert.equal(isDatasetValid(exactEntry.dataset), true);
  assert.equal(assessProjectDataQuality([exactEntry], true).level, "high");

  const manuallyMapped = {
    ...exactEntry,
    dataset: { Name: "Normalbeton C25/30", Validity: "valid" },
  };
  assert.equal(assessProjectDataQuality([manuallyMapped], true).level, "medium");

  const partial = { ...exactEntry, calculation: null };
  const partialAssessment = assessProjectDataQuality([exactEntry, partial], true);
  assert.equal(partialAssessment.level, "limited");
  assert.match(partialAssessment.explanation, /bleiben aus der Summe ausgeschlossen/);

  const expired = {
    ...exactEntry,
    dataset: { Name: "Beton", Validity: "expired" },
    calculation: null,
  };
  assert.equal(isDatasetValid(expired.dataset), false);
  assert.match(assessProjectDataQuality([expired], true).explanation, /abgelaufen/);

  assert.equal(assessProjectDataQuality([exactEntry], false).level, "limited");
  assert.equal(assessProjectDataQuality([{ ...exactEntry, contained: false }], true).level, "limited");
  assert.equal(assessProjectDataQuality([], false).level, "none");

  const categorySuggestion = assessProjectDataQuality([
    { ...exactEntry, matchType: "category-suggestion" },
  ], true);
  assert.equal(categorySuggestion.level, "limited");
  assert.match(categorySuggestion.explanation, /Materialkategorie-Vorschlag/);
});

test("rejects incompatible, missing, invalid, and negative calculation inputs", () => {
  assert.throws(
    () => calculateContribution({ dimension: "volume", canonicalValue: 1 }, { Unit: "kg", ReferenceAmount: 1, Gwp: 2, Validity: "valid" }),
    /nicht kompatibel/,
  );
  assert.throws(
    () => calculateContribution({ dimension: "volume", canonicalValue: 1 }, { Unit: "m³", ReferenceAmount: 0, Gwp: 2, Validity: "valid" }),
    /Bezugsmenge/,
  );
  assert.throws(
    () => calculateContribution({ dimension: "volume", canonicalValue: 1 }, { Unit: "m³", ReferenceAmount: "1,000", Gwp: 2, Validity: "valid" }),
    /Bezugsmenge/,
  );
  assert.throws(
    () => calculateContribution({ dimension: "volume", canonicalValue: -1 }, { Unit: "m³", ReferenceAmount: 1, Gwp: 2, Validity: "valid" }),
    /Negative IFC-Mengen/,
  );
  assert.throws(
    () => calculateContribution({ dimension: "length", canonicalValue: 1 }, { Unit: "unbekannt", ReferenceAmount: 1, Gwp: 2, Validity: "valid" }),
    /nicht unterstützt/,
  );
  assert.throws(
    () => calculateContribution({ dimension: "volume", canonicalValue: 1 }, { Unit: "m³", ReferenceAmount: 1, Gwp: null, Validity: "valid" }),
    /GWP-Wert/,
  );
  assert.throws(
    () => calculateContribution(
      { dimension: "volume", canonicalValue: 1 },
      { Unit: "m³", ReferenceAmount: 1, Gwp: 2, Validity: "expired" },
    ),
    /abgelaufen/,
  );
  assert.throws(
    () => calculateContribution(
      { dimension: "volume", canonicalValue: 1 },
      { Unit: "m³", ReferenceAmount: 1, Gwp: 2, Validity: "unknown" },
    ),
    /Gültigkeit.*unbekannt/,
  );
  assert.equal(datasetUnitInfo("m³").dimension, "volume");
  assert.equal(datasetUnitInfo("Stück").dimension, "count");
});

test("flattens the existing grouped ÖKOBAUDAT search response", () => {
  const item = { Id: "dataset-1" };
  assert.deepEqual(
    flattenSearchResults({ groups: [{ PeerGroups: [{ Items: [item] }] }] }),
    [item],
  );
});

test("keeps static demo candidates without version fields and removes duplicate records", () => {
  const item = { Id: "demo-1", Name: "synthetic example" };
  const results = uniqueIfcSearchCandidates({
    groups: [{ PeerGroups: [{ Items: [item, { ...item }, { Name: "no id" }] }] }],
  });
  assert.deepEqual(results, [item]);
});

test("keeps a solar-only local import visible without allowing a fabricated GWP contribution", () => {
  const solarOnlyImport = {
    Id: "USER-import-1",
    Version: "1.0",
    RecordKind: "user-import",
    Name: "Pine cladding",
    Unit: "",
    ReferenceAmount: "",
    Gwp: null,
    Validity: "unknown",
    SolarReflectance: {
      Value: 45.2,
      Unit: "%",
      Method: "EN 410",
      Wavelength: "300-2500 nm",
      SourceName: "Example source",
    },
  };
  const candidates = uniqueIfcSearchCandidates({
    groups: [{ PeerGroups: [{ Items: [solarOnlyImport] }] }],
  });

  assert.equal(candidates.length, 1);
  assert.equal(candidates[0].SolarReflectance.Value, 45.2);
  assert.equal(isDatasetValid(candidates[0]), false);
  assert.throws(
    () => calculateContribution(
      { dimension: "area", canonicalValue: 1, unit: "m²" },
      candidates[0],
    ),
    /Gültigkeit.*unbekannt/,
  );
});
