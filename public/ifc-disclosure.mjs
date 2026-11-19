export function createCollapsedIfcRows(rowCount) {
  return new Set(Array.from({ length: rowCount }, (_, index) => index));
}

export function toggleIfcRow(collapsedRows, index) {
  if (collapsedRows.has(index)) {
    collapsedRows.delete(index);
    return false;
  }
  collapsedRows.add(index);
  return true;
}

export function toggleIfcComponentList(collapsed) {
  return !collapsed;
}

export function getIfcDisclosureAttributes(index, name, collapsed) {
  return {
    id: `ifc-component-details-${index}`,
    expanded: !collapsed,
    label: `Details für Bauteil ${name} ${collapsed ? "anzeigen" : "verbergen"}`,
  };
}

export function getIfcComponentListControl(collapsed) {
  return {
    hidden: collapsed,
    expanded: !collapsed,
    controls: "ifc-component-list",
    label: collapsed ? "Alle Bauteile ausklappen" : "Alle Bauteile einklappen",
  };
}
