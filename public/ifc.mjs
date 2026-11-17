const MAX_FILE_CHARACTERS = 100 * 1024 * 1024;
const REF_PATTERN = /^#(\d+)$/;
const SI_PREFIXES = {
  EXA: 1e18,
  PETA: 1e15,
  TERA: 1e12,
  GIGA: 1e9,
  MEGA: 1e6,
  KILO: 1e3,
  HECTO: 1e2,
  DECA: 1e1,
  DECI: 1e-1,
  CENTI: 1e-2,
  MILLI: 1e-3,
  MICRO: 1e-6,
  NANO: 1e-9,
  PICO: 1e-12,
  FEMTO: 1e-15,
  ATTO: 1e-18,
};

const QUANTITY_TYPES = {
  IFCQUANTITYLENGTH: "length",
  IFCQUANTITYAREA: "area",
  IFCQUANTITYVOLUME: "volume",
  IFCQUANTITYWEIGHT: "mass",
  IFCQUANTITYMASS: "mass",
  IFCQUANTITYCOUNT: "count",
};

const DATASET_UNITS = [
  { dimension: "length", factor: 1, names: ["m", "meter", "metre"] },
  { dimension: "length", factor: 1e-2, names: ["cm", "centimeter", "centimetre"] },
  { dimension: "length", factor: 1e-3, names: ["mm", "millimeter", "millimetre"] },
  { dimension: "area", factor: 1, names: ["m2", "m^2", "qm", "squaremeter", "squaremetre"] },
  { dimension: "area", factor: 1e-4, names: ["cm2", "cm^2", "squarecentimeter", "squarecentimetre"] },
  { dimension: "area", factor: 1e-6, names: ["mm2", "mm^2", "squaremillimeter", "squaremillimetre"] },
  { dimension: "volume", factor: 1, names: ["m3", "m^3", "cubicmeter", "cubicmetre"] },
  { dimension: "volume", factor: 1e-3, names: ["l", "liter", "litre"] },
  { dimension: "mass", factor: 1, names: ["kg", "kilogram", "kilograms"] },
  { dimension: "mass", factor: 1e-3, names: ["g", "gram", "grams"] },
  { dimension: "mass", factor: 1e3, names: ["t", "tonne", "tonnes"] },
  { dimension: "count", factor: 1, names: ["st", "stk", "stueck", "stück", "pc", "pcs", "piece", "pieces", "each"] },
];

function splitTopLevel(value) {
  const parts = [];
  let start = 0;
  let depth = 0;
  let inString = false;

  for (let index = 0; index < value.length; index += 1) {
    const character = value[index];
    if (character === "'") {
      if (inString && value[index + 1] === "'") {
        index += 1;
      } else {
        inString = !inString;
      }
    } else if (!inString) {
      if (character === "(") depth += 1;
      if (character === ")") depth -= 1;
      if (character === "," && depth === 0) {
        parts.push(value.slice(start, index).trim());
        start = index + 1;
      }
    }
  }

  if (value.slice(start).trim() || parts.length) {
    parts.push(value.slice(start).trim());
  }
  return parts;
}

function decodeStepString(raw) {
  let value = raw.slice(1, -1).replaceAll("''", "'");
  value = value.replace(/\\X2\\([0-9A-Fa-f]+)\\X0\\/g, (_, hex) => {
    let decoded = "";
    for (let index = 0; index < hex.length; index += 4) {
      decoded += String.fromCharCode(Number.parseInt(hex.slice(index, index + 4), 16));
    }
    return decoded;
  });
  value = value.replace(/\\X4\\([0-9A-Fa-f]+)\\X0\\/g, (_, hex) => {
    let decoded = "";
    for (let index = 0; index < hex.length; index += 8) {
      decoded += String.fromCodePoint(Number.parseInt(hex.slice(index, index + 8), 16));
    }
    return decoded;
  });
  return value;
}

function parseValue(raw) {
  const value = raw.trim();
  if (!value || value === "$" || value === "*") return null;

  const reference = value.match(REF_PATTERN);
  if (reference) return { kind: "ref", id: reference[1] };
  if (value.startsWith("'") && value.endsWith("'")) return decodeStepString(value);
  if (/^\.[A-Z0-9_]+\.$/i.test(value)) return value.slice(1, -1).toUpperCase();
  if (value.startsWith("(") && value.endsWith(")")) {
    return splitTopLevel(value.slice(1, -1)).map(parseValue);
  }

  const typed = value.match(/^([A-Z][A-Z0-9_]*)\(([\s\S]*)\)$/i);
  if (typed) {
    return { kind: "typed", type: typed[1].toUpperCase(), value: parseValue(typed[2]) };
  }
  if (/^[+-]?(?:\d+(?:\.\d*)?|\.\d+)(?:[Ee][+-]?\d+)?$/.test(value)) {
    return Number(value);
  }
  return value;
}

function readDataRecords(text) {
  const dataStart = text.search(/\bDATA\s*;/i);
  if (dataStart < 0) throw new Error("Im IFC-File fehlt der DATA-Abschnitt.");

  const records = new Map();
  let index = dataStart + text.slice(dataStart).match(/\bDATA\s*;/i)[0].length;
  while (index < text.length) {
    while (/\s/.test(text[index] || "")) index += 1;
    if (text.startsWith("/*", index)) {
      const commentEnd = text.indexOf("*/", index + 2);
      if (commentEnd < 0) throw new Error("Ein IFC-Kommentar ist nicht abgeschlossen.");
      index = commentEnd + 2;
      continue;
    }
    if (/^ENDSEC\s*;/i.test(text.slice(index))) break;
    if (text[index] !== "#") {
      index += 1;
      continue;
    }

    const start = index;
    index += 1;
    const idStart = index;
    while (/\d/.test(text[index] || "")) index += 1;
    const id = text.slice(idStart, index);
    while (/\s/.test(text[index] || "")) index += 1;
    if (!id || text[index] !== "=") throw new Error(`Ungültiger IFC-Datensatz bei Zeichen ${start}.`);
    index += 1;
    while (/\s/.test(text[index] || "")) index += 1;

    const typeStart = index;
    while (/[A-Z0-9_]/i.test(text[index] || "")) index += 1;
    const type = text.slice(typeStart, index).toUpperCase();
    while (/\s/.test(text[index] || "")) index += 1;
    if (!type || text[index] !== "(") throw new Error(`Ungültige IFC-Attribute bei #${id}.`);

    const argumentStart = ++index;
    let depth = 1;
    let inString = false;
    while (index < text.length && depth > 0) {
      const character = text[index];
      if (character === "'") {
        if (inString && text[index + 1] === "'") {
          index += 2;
          continue;
        }
        inString = !inString;
      } else if (!inString) {
        if (character === "(") depth += 1;
        if (character === ")") depth -= 1;
      }
      index += 1;
    }
    if (depth !== 0 || inString) throw new Error(`Nicht abgeschlossene IFC-Attribute bei #${id}.`);

    const rawArguments = text.slice(argumentStart, index - 1);
    while (/\s/.test(text[index] || "")) index += 1;
    if (text[index] !== ";") throw new Error(`IFC-Datensatz #${id} endet nicht mit einem Semikolon.`);
    index += 1;
    if (records.has(id)) throw new Error(`Die IFC-ID #${id} ist mehrfach vorhanden.`);
    records.set(id, { id, type, args: splitTopLevel(rawArguments).map(parseValue) });
  }

  return records;
}

function referenceId(value) {
  return value?.kind === "ref" ? value.id : null;
}

function referenceList(value) {
  return Array.isArray(value) ? value.map(referenceId).filter(Boolean) : [];
}

function enumValue(value) {
  return typeof value === "string" ? value.toUpperCase() : "";
}

function numericValue(value) {
  if (typeof value === "number") return value;
  if (value?.kind === "typed") return numericValue(value.value);
  return null;
}

function typeDimension(unitType) {
  return ({
    LENGTHUNIT: "length",
    AREAUNIT: "area",
    VOLUMEUNIT: "volume",
    MASSUNIT: "mass",
  })[unitType] || null;
}

function unitScale(records, unitId, visiting = new Set()) {
  if (visiting.has(unitId)) return null;
  visiting.add(unitId);
  const unit = records.get(unitId);
  if (!unit) return null;

  if (unit.type === "IFCSIUNIT") {
    const dimension = typeDimension(enumValue(unit.args[1]));
    const prefix = enumValue(unit.args[2]);
    const name = enumValue(unit.args[3]);
    if (!dimension || (prefix && SI_PREFIXES[prefix] === undefined)) return null;
    const prefixFactor = prefix ? SI_PREFIXES[prefix] : 1;
    const exponent = dimension === "area" ? 2 : dimension === "volume" ? 3 : 1;
    const baseFactor = dimension === "mass" && name === "GRAM" ? 1e-3 : 1;
    return {
      dimension,
      factor: baseFactor * prefixFactor ** exponent,
      label: [prefix, name].filter(Boolean).join(" "),
    };
  }

  if (unit.type === "IFCCONVERSIONBASEDUNIT") {
    const dimension = typeDimension(enumValue(unit.args[1]));
    const conversionId = referenceId(unit.args[3]);
    const conversion = records.get(conversionId);
    if (!dimension || conversion?.type !== "IFCMEASUREWITHUNIT") return null;
    const multiplier = numericValue(conversion.args[0]);
    const base = unitScale(records, referenceId(conversion.args[1]), visiting);
    if (!Number.isFinite(multiplier) || !base || base.dimension !== dimension) return null;
    return { dimension, factor: multiplier * base.factor, label: String(unit.args[2] || "Konvertierungseinheit") };
  }

  return null;
}

function unitDisplayLabel(unit) {
  const known = {
    length: [[1, "m"], [1e-2, "cm"], [1e-3, "mm"]],
    area: [[1, "m²"], [1e-4, "cm²"], [1e-6, "mm²"]],
    volume: [[1, "m³"], [1e-3, "l"]],
    mass: [[1, "kg"], [1e-3, "g"], [1e3, "t"]],
  }[unit.dimension] || [];
  return known.find(([factor]) => Math.abs(unit.factor - factor) < Number.EPSILON * 10)?.[1] || unit.label;
}

function projectUnits(records) {
  const project = [...records.values()].find((record) => record.type === "IFCPROJECT");
  const assignment = records.get(referenceId(project?.args[8]));
  if (assignment?.type !== "IFCUNITASSIGNMENT") return new Map();

  const units = new Map();
  for (const id of referenceList(assignment.args[0])) {
    const unit = unitScale(records, id);
    if (!unit) continue;
    if (!units.has(unit.dimension)) units.set(unit.dimension, []);
    units.get(unit.dimension).push({ id, ...unit });
  }
  return units;
}

function materialNames(records, materialId, visiting = new Set()) {
  if (visiting.has(materialId)) return [];
  visiting.add(materialId);
  const material = records.get(materialId);
  if (!material) return [];
  if (material.type === "IFCMATERIAL") {
    return typeof material.args[0] === "string" ? [material.args[0].trim()].filter(Boolean) : [];
  }

  const childIds = [];
  if (material.type === "IFCMATERIALLIST") childIds.push(...referenceList(material.args[0]));
  if (material.type === "IFCMATERIALLAYERSET") {
    for (const layerId of referenceList(material.args[0])) {
      childIds.push(referenceId(records.get(layerId)?.args[0]));
    }
  }
  if (material.type === "IFCMATERIALLAYERSETUSAGE") {
    childIds.push(referenceId(material.args[0]));
  }
  if (material.type === "IFCMATERIALCONSTITUENTSET") {
    for (const constituentId of referenceList(material.args[2])) {
      childIds.push(referenceId(records.get(constituentId)?.args[2]));
    }
  }
  if (material.type === "IFCMATERIALPROFILESET") {
    for (const profileId of referenceList(material.args[2])) {
      childIds.push(referenceId(records.get(profileId)?.args[2]));
    }
  }
  if (material.type === "IFCMATERIALPROFILESETUSAGE") {
    childIds.push(referenceId(material.args[0]));
  }

  return childIds.filter(Boolean).flatMap((id) => materialNames(records, id, visiting));
}

function parseQuantity(records, quantity, units) {
  const dimension = QUANTITY_TYPES[quantity.type];
  if (!dimension) return null;
  const name = typeof quantity.args[0] === "string" ? quantity.args[0] : quantity.type;
  const value = numericValue(quantity.args[3]);
  if (!Number.isFinite(value)) {
    return { name, type: quantity.type, dimension, value: null, error: "Der IFC-Mengenwert ist nicht numerisch." };
  }

  if (dimension === "count") {
    if (referenceId(quantity.args[2])) {
      return { name, type: quantity.type, dimension, value, error: "Die explizite IFC-Einheit für Stückzahlen wird nicht unterstützt." };
    }
    return { name, type: quantity.type, dimension, value, canonicalValue: value, unit: "Stück" };
  }

  const explicitUnitId = referenceId(quantity.args[2]);
  let unit = explicitUnitId ? unitScale(records, explicitUnitId) : null;
  if (!unit && !explicitUnitId) {
    const projectUnitsForDimension = units.get(dimension) || [];
    if (projectUnitsForDimension.length === 1) unit = projectUnitsForDimension[0];
    if (projectUnitsForDimension.length > 1) {
      return { name, type: quantity.type, dimension, value, error: "Mehrere Projekteinhheiten passen zu dieser Menge." };
    }
  }
  if (!unit) {
    return { name, type: quantity.type, dimension, value, error: "Die IFC-Einheit dieser Menge ist nicht eindeutig oder wird nicht unterstützt." };
  }
  if (unit.dimension !== dimension) {
    return { name, type: quantity.type, dimension, value, error: "Die angegebene IFC-Einheit passt nicht zur Mengendimension." };
  }

  const canonicalValue = value * unit.factor;
  if (!Number.isFinite(canonicalValue)) {
    return { name, type: quantity.type, dimension, value, error: "Der umgerechnete IFC-Mengenwert ist nicht endlich." };
  }
  return {
    name,
    type: quantity.type,
    dimension,
    value,
    canonicalValue,
    unit: ({ length: "m", area: "m²", volume: "m³", mass: "kg" })[dimension],
    sourceUnit: unitDisplayLabel(unit),
  };
}

function entityDisplayName(record) {
  const name = record?.args[2];
  return typeof name === "string" && name.trim() ? name.trim() : `${record?.type || "IfcElement"} #${record?.id || ""}`;
}

export function parseIfcText(text) {
  if (typeof text !== "string" || !text.trim()) throw new Error("Die ausgewählte IFC-Datei ist leer.");
  if (text.length > MAX_FILE_CHARACTERS) throw new Error("Die IFC-Datei ist größer als 100 MB und kann nicht lokal verarbeitet werden.");
  if (!/^\s*ISO-10303-21\s*;/i.test(text)) throw new Error("Die Datei hat keinen gültigen IFC/STEP-21-Kopf.");
  if (!/\bEND-ISO-10303-21\s*;/i.test(text)) throw new Error("Die IFC-Datei ist unvollständig; END-ISO-10303-21 fehlt.");

  const schemaMatch = text.match(/FILE_SCHEMA\s*\(\s*\(\s*'((?:[^']|'')*)'/i);
  const schema = schemaMatch ? decodeStepString(`'${schemaMatch[1]}'`).toUpperCase() : "";
  if (!schema.startsWith("IFC2X3") && !schema.startsWith("IFC4")) {
    throw new Error(schema ? `Das IFC-Schema „${schema}“ wird nicht unterstützt.` : "Im IFC-Kopf fehlt FILE_SCHEMA.");
  }

  const records = readDataRecords(text);
  if (!records.size) throw new Error("Der IFC-DATA-Abschnitt enthält keine Bauteile.");
  const units = projectUnits(records);
  const materialByObject = new Map();
  const unresolvedMaterialObjects = new Set();
  const typeByObject = new Map();
  const quantitiesByObject = new Map();
  const containedObjectIds = new Set();

  for (const relation of records.values()) {
    if (relation.type === "IFCRELASSOCIATESMATERIAL") {
      const materialRef = relation.args[5];
      for (const objectId of referenceList(relation.args[4])) {
        if (!records.has(objectId)) throw new Error(`IFC-Beziehung #${relation.id} verweist auf unbekanntes Bauteil #${objectId}.`);
        if (!materialByObject.has(objectId)) materialByObject.set(objectId, []);
        const materialId = referenceId(materialRef);
        const names = materialId ? materialNames(records, materialId) : [];
        if (!names.length) unresolvedMaterialObjects.add(objectId);
        for (const name of names) {
          if (!materialByObject.get(objectId).includes(name)) materialByObject.get(objectId).push(name);
        }
      }
    }
    if (relation.type === "IFCRELDEFINESBYTYPE") {
      const typeId = referenceId(relation.args[5]);
      for (const objectId of referenceList(relation.args[4])) {
        if (!records.has(objectId) || !typeId || !records.has(typeId)) {
          throw new Error(`IFC-Typbeziehung #${relation.id} enthält einen unbekannten Bauteil- oder Typverweis.`);
        }
        if (!typeByObject.has(objectId)) typeByObject.set(objectId, []);
        typeByObject.get(objectId).push(typeId);
      }
    }
    if (relation.type === "IFCRELDEFINESBYPROPERTIES") {
      const propertySetId = referenceId(relation.args[5]);
      const propertySet = records.get(propertySetId);
      if (propertySet?.type !== "IFCELEMENTQUANTITY") continue;
      const quantityIds = referenceList(propertySet.args.at(-1));
      for (const objectId of referenceList(relation.args[4])) {
        if (!records.has(objectId) || quantityIds.some((quantityId) => !records.has(quantityId))) {
          throw new Error(`IFC-Mengenbeziehung #${relation.id} enthält einen unbekannten Bauteil- oder Mengenverweis.`);
        }
        if (!quantitiesByObject.has(objectId)) quantitiesByObject.set(objectId, []);
        quantitiesByObject.get(objectId).push(...quantityIds);
      }
    }
    if (relation.type === "IFCRELCONTAINEDINSPATIALSTRUCTURE") {
      for (const objectId of referenceList(relation.args[4])) {
        if (!records.has(objectId)) {
          throw new Error(`IFC-Raumstruktur #${relation.id} verweist auf unbekanntes Bauteil #${objectId}.`);
        }
        containedObjectIds.add(objectId);
      }
    }
  }

  const objectIds = new Set([
    ...materialByObject.keys(),
    ...quantitiesByObject.keys(),
    ...typeByObject.keys(),
    ...containedObjectIds,
  ]);
  const elements = [];
  for (const id of objectIds) {
    const record = records.get(id);
    if (!record || record.type.endsWith("TYPE")) continue;
    const typeIds = typeByObject.get(id) || [];
    const hasDirectAssignment = materialByObject.has(id);
    const assignmentIds = hasDirectAssignment ? [id] : typeIds.filter((typeId) => materialByObject.has(typeId));
    const materials = [...new Set(assignmentIds.flatMap((assignmentId) => materialByObject.get(assignmentId) || []))];
    const unresolvedMaterial = assignmentIds.some((assignmentId) => unresolvedMaterialObjects.has(assignmentId));
    const quantityIds = [...new Set(quantitiesByObject.get(id) || [])];
    const quantities = quantityIds
      .map((quantityId) => records.get(quantityId))
      .filter(Boolean)
      .map((quantity) => parseQuantity(records, quantity, units))
      .filter(Boolean);

    elements.push({
      id,
      type: record.type,
      name: entityDisplayName(record),
      materials,
      materialStatus: materials.length === 1 && !unresolvedMaterial ? "ready" : materials.length || unresolvedMaterial ? "ambiguous" : "missing",
      materialIssue: unresolvedMaterial ? "Mindestens eine IFC-Materialzuordnung konnte nicht eindeutig gelesen werden." : "",
      materialSource: hasDirectAssignment ? "Bauteil" : assignmentIds.length ? "Bauteiltyp" : "",
      quantities,
      contained: containedObjectIds.has(id),
    });
  }

  if (!elements.length) {
    throw new Error("Es wurden keine Bauteile mit expliziten IFC-Materialzuordnungen oder Mengen gefunden.");
  }

  return {
    schema,
    elements,
    containmentAvailable: containedObjectIds.size > 0,
    containedElementCount: containedObjectIds.size,
  };
}

function normalizeUnit(value) {
  return String(value ?? "")
    .trim()
    .toLowerCase()
    .replaceAll("²", "2")
    .replaceAll("³", "3")
    .replace(/[\s._-]+/g, "")
    .replaceAll("ä", "ae")
    .replaceAll("ö", "oe")
    .replaceAll("ü", "ue");
}

export function datasetUnitInfo(unit) {
  const normalized = normalizeUnit(unit);
  return DATASET_UNITS.find((candidate) => candidate.names.some((name) => normalizeUnit(name) === normalized)) || null;
}

export function isDatasetValid(dataset) {
  return dataset?.Validity === "valid";
}

function normalizeMaterialName(value) {
  return String(value ?? "").trim().replace(/\s+/g, " ").toLocaleLowerCase("de-DE");
}

export function assessProjectDataQuality(entries, containmentAvailable) {
  if (!entries.length) {
    return {
      level: "none",
      label: "Keine belastbare Schätzung",
      explanation: "Es liegt noch kein berechenbarer A1–A3-Beitrag vor.",
    };
  }

  const unresolvedCount = entries.filter((entry) => !entry.calculation).length;
  const invalidDatasetCount = entries.filter((entry) =>
    entry.dataset && !isDatasetValid(entry.dataset)).length;
  const missingMaterialMatchCount = entries.filter((entry) =>
    entry.calculation &&
    (!String(entry.material ?? "").trim() || !String(entry.dataset?.Name ?? "").trim())).length;
  const uncontainedCount = entries.filter((entry) => !entry.contained).length;
  if (unresolvedCount || invalidDatasetCount || missingMaterialMatchCount ||
    !containmentAvailable || uncontainedCount) {
    const reasons = [];
    if (unresolvedCount) {
      reasons.push(`${unresolvedCount} von ${entries.length} erfassten Bauteilen sind nicht berechenbar und bleiben aus der Summe ausgeschlossen.`);
    }
    if (invalidDatasetCount) {
      reasons.push(`${invalidDatasetCount} gewählte Datensätze sind abgelaufen oder ihre Gültigkeit ist unbekannt und bleiben ausgeschlossen.`);
    }
    if (missingMaterialMatchCount) {
      reasons.push(`${missingMaterialMatchCount} Materialzuordnungen sind nicht eindeutig belegt.`);
    }
    if (!containmentAvailable || uncontainedCount) {
      reasons.push(!containmentAvailable
        ? "Eine IFC-Raumstrukturzuordnung fehlt; der Modellumfang ist nicht prüfbar."
        : `${uncontainedCount} erfasste Bauteile sind keiner IFC-Raumstruktur zugeordnet; der Modellumfang ist nicht prüfbar.`);
    }
    return {
      level: "limited",
      label: "Datenqualität: eingeschränkt",
      explanation: reasons.join(" "),
    };
  }

  const exactMaterialNames = entries.every((entry) => entry.calculation && isDatasetValid(entry.dataset) &&
    normalizeMaterialName(entry.material) === normalizeMaterialName(entry.dataset?.Name));
  if (exactMaterialNames) {
    return {
      level: "high",
      label: "Datenqualität: gut",
      explanation: "Alle erfassten Bauteile haben explizite, kompatible IFC-Mengen und gültige ÖKOBAUDAT-Datensätze mit übereinstimmenden Materialnamen. Das bestätigt nicht die Vollständigkeit des IFC-Exports oder die Produktgleichheit.",
    };
  }

  return {
    level: "medium",
    label: "Datenqualität: mittel",
    explanation: "Alle erfassten Bauteile sind berechenbar und die Datensätze sind gültig; mindestens eine Materialzuordnung weicht vom Datensatznamen ab und wurde manuell ausgewählt. Produktgleichheit und Exportvollständigkeit sind nicht bestätigt.",
  };
}

function parseReferenceAmount(value) {
  if (typeof value === "number") return value;
  const text = String(value ?? "").trim();
  if (!/^[+-]?(?:\d+(?:[.,]\d*)?|[.,]\d+)$/.test(text)) return null;
  const decimalPart = text.split(/[.,]/)[1];
  if (decimalPart?.length === 3) return null;
  return Number(text.replace(",", "."));
}

export function calculateContribution(quantity, dataset) {
  if (!quantity || !dataset) throw new Error("IFC-Menge und ÖKOBAUDAT-Datensatz müssen ausgewählt sein.");
  if (!isDatasetValid(dataset)) {
    throw new Error(dataset.Validity === "expired"
      ? "Der ÖKOBAUDAT-Datensatz ist abgelaufen."
      : "Die Gültigkeit des ÖKOBAUDAT-Datensatzes ist unbekannt.");
  }
  if (quantity.error || !Number.isFinite(quantity.canonicalValue)) {
    throw new Error(quantity.error || "Die IFC-Menge ist nicht numerisch.");
  }
  if (quantity.canonicalValue < 0) throw new Error("Negative IFC-Mengen können nicht bilanziert werden.");

  const unit = datasetUnitInfo(dataset.Unit);
  if (!unit) throw new Error(`Die Datensatz-Einheit „${dataset.Unit || "unbekannt"}“ wird nicht unterstützt.`);
  if (unit.dimension !== quantity.dimension) {
    throw new Error(`Die IFC-Menge (${quantity.unit || quantity.dimension}) und Datensatz-Einheit (${dataset.Unit}) sind nicht kompatibel.`);
  }

  if (dataset.Gwp === null || dataset.Gwp === undefined || dataset.Gwp === "") {
    throw new Error("Der ÖKOBAUDAT-Datensatz enthält keinen gültigen GWP-Wert.");
  }
  const gwp = Number(dataset.Gwp);
  const referenceAmount = parseReferenceAmount(dataset.ReferenceAmount);
  if (!Number.isFinite(gwp)) throw new Error("Der ÖKOBAUDAT-Datensatz enthält keinen gültigen GWP-Wert.");
  if (!Number.isFinite(referenceAmount) || referenceAmount <= 0) {
    throw new Error("Die ÖKOBAUDAT-Bezugsmenge fehlt oder ist nicht positiv.");
  }

  const datasetQuantity = quantity.canonicalValue / unit.factor;
  const contribution = (datasetQuantity / referenceAmount) * gwp;
  if (!Number.isFinite(contribution)) throw new Error("Der berechnete GWP-Beitrag ist nicht endlich.");
  return {
    datasetQuantity,
    datasetUnit: dataset.Unit,
    referenceAmount,
    gwp,
    contribution,
  };
}

export function flattenSearchResults(data) {
  const items = [];
  for (const group of data?.groups || []) {
    for (const peer of group.PeerGroups || []) {
      items.push(...(peer.Items || []));
    }
  }
  return items;
}
