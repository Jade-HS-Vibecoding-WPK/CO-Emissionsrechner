import assert from "node:assert/strict";
import test from "node:test";
import {
  createCollapsedIfcRows,
  getIfcComponentListControl,
  getIfcDisclosureAttributes,
  toggleIfcComponentList,
  toggleIfcRow,
} from "../public/ifc-disclosure.mjs";

test("individual disclosure toggles expose matching accessible state", () => {
  const collapsedRows = createCollapsedIfcRows(2);
  assert.deepEqual(getIfcDisclosureAttributes(0, "Südwand", true), {
    id: "ifc-component-details-0",
    expanded: false,
    label: "Details für Bauteil Südwand anzeigen",
  });

  assert.equal(toggleIfcRow(collapsedRows, 0), false);
  assert.equal(collapsedRows.has(0), false);
  assert.equal(collapsedRows.has(1), true);
  assert.deepEqual(getIfcDisclosureAttributes(0, "Südwand", false), {
    id: "ifc-component-details-0",
    expanded: true,
    label: "Details für Bauteil Südwand verbergen",
  });
});

test("one list toggle hides all components without altering data or the end result", () => {
  let listCollapsed = false;
  const rows = [
    { selectedDatasetIndex: 1, selectedQuantityIndex: 0, contribution: 42 },
    { selectedDatasetIndex: null, selectedQuantityIndex: null, contribution: null },
  ];
  const total = 42;
  const before = rows.map((row) => ({ ...row }));

  assert.deepEqual(getIfcComponentListControl(listCollapsed), {
    hidden: false,
    expanded: true,
    controls: "ifc-component-list",
    label: "Alle Bauteile einklappen",
  });
  listCollapsed = toggleIfcComponentList(listCollapsed);
  assert.deepEqual(getIfcComponentListControl(listCollapsed), {
    hidden: true,
    expanded: false,
    controls: "ifc-component-list",
    label: "Alle Bauteile ausklappen",
  });
  assert.deepEqual(rows, before);
  assert.equal(total, 42);

  listCollapsed = toggleIfcComponentList(listCollapsed);
  assert.equal(getIfcComponentListControl(listCollapsed).hidden, false);
  assert.deepEqual(rows, before);
  assert.equal(total, 42);

  assert.deepEqual(rows, before);
});
