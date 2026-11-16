const form = document.querySelector("#search-form");
const input = document.querySelector("#material-query");
const useCase = document.querySelector("#use-case");
const message = document.querySelector("#message");
const resultsSection = document.querySelector("#results-section");
const resultsList = document.querySelector("#results-list");
const resultsCount = document.querySelector("#results-count");
const resultsTitle = document.querySelector("#results-title");
const detailPanel = document.querySelector("#detail-panel");
const searchButton = form.querySelector("button");
const modelFile = document.querySelector("#model-file");
const modelStatus = document.querySelector("#model-status");
let selectedItem = null;
let selectedButton = null;

function escapeHtml(value) {
  return String(value ?? "").replace(/[&<>"']/g, (character) => ({
    "&": "&amp;",
    "<": "&lt;",
    ">": "&gt;",
    '"': "&quot;",
    "'": "&#39;",
  })[character]);
}

function formatNumber(value) {
  if (value === null || value === undefined || value === "") return "Kein Wert";
  return new Intl.NumberFormat("de-DE", { maximumSignificantDigits: 4 }).format(value);
}

function readableText(value) {
  return String(value ?? "")
    .replace("OEKOBAUDAT", "ÖKOBAUDAT")
    .replace("Hoeher", "Höher")
    .replace("Suesswasser", "Süßwasser")
    .replaceAll("Aequivalent", "Äquivalent")
    .replaceAll("m3", "m³")
    .replaceAll("qm", "m²");
}

function setMessage(title, text, state = "") {
  message.hidden = false;
  message.className = `message ${state}`.trim();
  message.innerHTML = `<span class="message-icon" aria-hidden="true">${state === "loading" ? "" : state === "error" ? "!" : "i"}</span><div><strong>${escapeHtml(title)}</strong><p>${escapeHtml(text)}</p></div>`;
}

function ratingBadge(rating) {
  const group = rating?.Group || "nicht vergleichbar";
  const rank = rating?.Rank && rating?.Count
    ? ` · Rang ${formatNumber(rating.Rank)} von ${formatNumber(rating.Count)}`
    : "";
  return `<span class="rating-badge">${escapeHtml(group)}${escapeHtml(rank)}</span>`;
}

async function requestJson(url) {
  const response = await fetch(url);
  const result = await response.json();
  if (!response.ok) throw new Error(result.error || "Die Anfrage ist fehlgeschlagen.");
  return result;
}

function renderResults(data) {
  resultsSection.hidden = false;
  resultsTitle.textContent = `Treffer für „${data.query}“`;
  resultsCount.textContent = `${data.groups.length} von ${data.groupCount} Materialgruppen · ${data.count} Datensätze`;
  detailPanel.innerHTML = `<div class="empty-detail"><span class="empty-icon" aria-hidden="true">↖</span><strong>Wähle einen Datensatz</strong><p>Hier siehst du die Ökobilanzwerte, Datensatzvergleiche und den Status möglicher Materialalternativen.</p></div>`;

  if (!data.groups.length) {
    resultsList.innerHTML = `<div class="empty-detail"><strong>Keine passenden Datensätze gefunden</strong><p>Versuche einen allgemeineren Begriff, zum Beispiel „Dämmung“, „Holz“ oder „Beton“.</p></div>`;
    detailPanel.innerHTML = `<div class="empty-detail"><span class="empty-icon" aria-hidden="true">⌕</span><strong>Suche anpassen</strong><p>Die App zeigt nur Treffer aus dem gewählten ÖKOBAUDAT-Datenbestand.</p></div>`;
    return;
  }

  resultsList.innerHTML = data.groups.map((group, groupIndex) => `
    <section class="result-family">
      <header class="family-heading">
        <div>
          <span class="family-kicker">${escapeHtml(group.CategoryGroup || "Materialgruppe")}</span>
          <h3>${escapeHtml(group.Name)}</h3>
          <span class="result-category">${escapeHtml(group.Category || "Kategorie nicht angegeben")}</span>
        </div>
        <span class="family-count">${group.Count} ${group.Count === 1 ? "Datensatz" : "Datensätze"}</span>
      </header>
      <div class="family-items">
        ${group.Items.map((item, itemIndex) => `
          <button class="result-card" type="button" data-group-index="${groupIndex}" data-item-index="${itemIndex}" aria-pressed="false">
            <span class="result-name">${escapeHtml(item.Name)}</span>
            <span class="result-bottom">
              <span class="result-year">${escapeHtml(item.ReferenceYear || "Jahr unbekannt")} · ${item.ReferenceAmount && item.Unit ? `pro ${escapeHtml(item.ReferenceAmount)} ${escapeHtml(readableText(item.Unit))}` : "Bezugsgröße fehlt"}</span>
              <span class="result-value">${item.Gwp === null ? "Kein GWP-Wert" : `${formatNumber(item.Gwp)} kg CO₂-eq`}</span>
            </span>
            <span class="result-rating">${ratingBadge(item.Rating)}</span>
          </button>
        `).join("")}
        ${group.Count > group.Items.length ? `<p class="variant-note">${group.Items.length} Varianten angezeigt; ${group.Count - group.Items.length} weitere Datensätze sind in dieser Gruppe enthalten. Verfeinere die Suche für eine bestimmte Produktvariante.</p>` : ""}
      </div>
    </section>
  `).join("");

  resultsList.querySelectorAll(".result-card").forEach((button) => {
    button.addEventListener("click", () => {
      const group = data.groups[Number(button.dataset.groupIndex)];
      selectResult(group.Items[Number(button.dataset.itemIndex)], button);
    });
  });

  if (data.warning) {
    setMessage("Zwischengespeicherte Daten", data.warning);
  } else {
    setMessage(
      `${data.groups.length} Materialgruppen gefunden`,
      `Quelle: ${readableText(data.source)}. ${data.count} Datensätze in ${data.groupCount} Gruppen; angezeigt werden höchstens zehn Gruppen. Daten lokal abgerufen am ${data.retrievedAt}.`,
    );
  }
}

async function selectResult(item, button) {
  selectedItem = item;
  selectedButton = button;
  resultsList.querySelectorAll(".result-card").forEach((card) => card.setAttribute("aria-pressed", "false"));
  button.setAttribute("aria-pressed", "true");
  detailPanel.innerHTML = `<div class="empty-detail"><span class="empty-icon" aria-hidden="true">…</span><strong>Datensatz wird geladen</strong></div>`;

  try {
    const params = new URLSearchParams({ id: item.Id, version: item.Version, useCase: useCase.value });
    const data = await requestJson(`/api/detail?${params}`);
    renderDetail(data);
  } catch (error) {
    detailPanel.innerHTML = `<div class="empty-detail"><strong>Details konnten nicht geladen werden</strong><p>${escapeHtml(error.message)}</p></div>`;
  }
}

function renderMaterialAlternative(assessment) {
  const checklist = assessment.Checks?.length
    ? `<ul>${assessment.Checks.map((check) => `<li>${escapeHtml(check)}</li>`).join("")}</ul>`
    : "";
  const title = assessment.Candidate
    ? `${escapeHtml(assessment.Candidate)} · bedingter Prüfpfad`
    : assessment.Status === "needs_application"
      ? "Einsatz noch nicht angegeben"
      : "Keine belastbare Materialalternative";
  const status = assessment.Status === "conditional_candidate"
    ? `<p class="assessment-status">Keine ökologische Empfehlung · Funktion noch nicht verglichen</p>`
    : assessment.Status === "needs_application"
      ? `<p class="assessment-status">Bauteilbezogene Prüfung nicht möglich</p>`
      : `<p class="assessment-status">Keine verifizierte Materialsubstitution verfügbar</p>`;

  return `
    <section class="material-assessment" aria-labelledby="material-assessment-title">
      <h3 id="material-assessment-title">Materialalternative nach Anwendung</h3>
      <p class="assessment-application">${assessment.Application ? `Einsatz: ${escapeHtml(assessment.Application)}` : "Wähle oben den vorgesehenen Einsatz."}</p>
      <strong class="assessment-title">${title}</strong>
      ${status}
      <p>${escapeHtml(assessment.Reason)}</p>
      ${checklist}
    </section>
  `;
}

function renderDetail(data) {
  const item = data.item;
  const reference = item.ReferenceAmount && item.Unit
    ? `pro ${escapeHtml(item.ReferenceAmount)} ${escapeHtml(readableText(item.Unit))}`
    : escapeHtml(item.Unit || "Bezugsgröße nicht angegeben");
  const metricBasis = item.ReferenceAmount && item.Unit
    ? `je ${escapeHtml(item.ReferenceAmount)} ${escapeHtml(readableText(item.Unit))}`
    : "je angegebener Bezugsmenge";
  const metrics = item.Metrics?.length
    ? `<h3 class="metric-heading">Weitere Umweltindikatoren</h3><div class="metric-grid">${item.Metrics.map((metric) => `
        <div class="metric">
          <span class="metric-name">${escapeHtml(readableText(metric.Name))}</span>
          <span class="metric-value">${formatNumber(metric.Value)} <span class="metric-unit">${escapeHtml(readableText(metric.Unit))} · ${metricBasis}</span></span>
        </div>
      `).join("")}</div>`
    : `<h3 class="metric-heading">Weitere Umweltindikatoren</h3><p class="no-alternatives">Für diesen Datensatz sind in der ausgewerteten Lebenszyklusphase keine weiteren Werte vorhanden.</p>`;
  const alternatives = data.alternatives?.length
    ? data.alternatives.map((alternative) => {
      const lowerMetrics = (alternative.Metrics || []).filter((metric) => metric.Relation === "lower");
      const higherMetrics = (alternative.Metrics || []).filter((metric) => metric.Relation === "higher");
      const comparisonRows = (alternative.Metrics || []).map((metric) => `
        <div class="comparison-row">
          <span>${escapeHtml(readableText(metric.Name))}</span>
          <span>${formatNumber(metric.SelectedValue)} → ${formatNumber(metric.AlternativeValue)} ${escapeHtml(readableText(metric.Unit))}</span>
          <small>${metric.Relation === "lower" ? "niedrigerer Wert" : metric.Relation === "higher" ? "höherer Wert" : "gleicher Wert"}</small>
        </div>
      `).join("");
      return `
        <div class="alternative">
          <div>
            <span class="alternative-name">${escapeHtml(alternative.Item.Name)}</span>
            <span class="alternative-cat">${escapeHtml(alternative.Item.Category)}</span>
          </div>
          <div class="alternative-value">
            ${formatNumber(alternative.Item.Gwp)} kg CO₂-eq
            <small>pro ${escapeHtml(alternative.Item.ReferenceAmount)} ${escapeHtml(readableText(alternative.Item.Unit))}</small>
          </div>
          <div class="alternative-evidence">
            <p><strong>Datensatzbeziehung:</strong> ${alternative.SameFamily ? "gleiche zusammengefasste Produktfamilie, anderer Datensatz / Produktionsstandort" : "gleiches vorläufiges, aus dem Datensatznamen abgeleitetes Vergleichsprofil"}.</p>
            <p><strong>GWP im Datensatzvergleich:</strong> ${formatNumber(item.Gwp)} → ${formatNumber(alternative.Item.Gwp)} kg CO₂-eq pro ${escapeHtml(item.ReferenceAmount)} ${escapeHtml(readableText(item.Unit))}.</p>
            ${lowerMetrics.length ? `<p><strong>Niedrigere ausgewiesene Indikatorwerte:</strong> ${lowerMetrics.map((metric) => escapeHtml(readableText(metric.Name))).join(", ")}.</p>` : ""}
            ${higherMetrics.length ? `<p><strong>Abweichungen mit höherem Einzelwert:</strong> ${higherMetrics.map((metric) => escapeHtml(readableText(metric.Name))).join(", ")}.</p>` : ""}
            ${comparisonRows ? `<details><summary>Alle gemeinsam verfügbaren Indikatoren (${(alternative.Metrics || []).length})</summary><div class="comparison-rows">${comparisonRows}</div></details>` : `<p>Keine weiteren Indikatorwerte mit gleicher Bezeichnung und Einheit für beide Datensätze vorhanden.</p>`}
            <p><strong>Dateneigner / Version:</strong> ${escapeHtml(alternative.Item.Owner || "nicht angegeben")} · ${escapeHtml(alternative.Item.Version || "nicht angegeben")} · gültig bis ${escapeHtml(alternative.Item.ValidUntil || "nicht angegeben")}. <a class="dataset-link" href="${escapeHtml(alternative.Item.Url)}" target="_blank" rel="noreferrer">Quelldatensatz ↗</a></p>
          </div>
          <p class="alternative-limits">Gleiche Kategorie, Einheit, Bezugsmenge und vorläufiges Namensprofil innerhalb A1–A3. Dieser Datensatzvergleich ist kein Materialersatz und belegt weder technische Gleichwertigkeit noch eine bessere Gesamtökobilanz.</p>
        </div>
      `;
    }).join("")
    : `<p class="no-alternatives">${data.comparison.comparable
      ? "In derselben Kategorie, Einheit und Bezugsmenge wurden keine Datensätze mit niedrigerem GWP-Wert gefunden."
      : escapeHtml(data.comparison.reason || "Ein vergleichbarer Datensatz ist nicht verfügbar.")} Das ist keine Aussage zur technischen Austauschbarkeit.</p>`;
  const validityLabel = item.Validity === "valid"
    ? "laut Datensatz aktuell"
    : item.Validity === "expired"
      ? "Gültigkeit abgelaufen"
      : "Gültigkeit unbekannt";
  const useNote = data.materialAlternative.Application
    ? `Dein gewählter Einsatz: ${escapeHtml(data.materialAlternative.Application)}. Er dient als Kontext für den Materialalternativen-Check, filtert aber nicht die ÖKOBAUDAT-Treffer.`
    : "Ohne gewählten Einsatz lässt sich kein bauteilbezogener Materialersatz prüfen.";
  const ratingNote = data.rating.Group === "nicht vergleichbar"
    ? "Keine belastbare relative Einordnung: Es fehlen mindestens drei gültige, methodisch passende Datensätze."
    : data.rating.Group === "nicht unterscheidbar"
      ? "Die GWP-Werte dieser Vergleichsgruppe sind identisch; eine relative Abstufung ist nicht möglich."
      : `Relative Einordnung: ${data.rating.Group} (Rang ${formatNumber(data.rating.Rank)} von ${formatNumber(data.rating.Count)} innerhalb dieser Vergleichsgruppe). Das ist keine absolute Öko-Bewertung.`;
  const interpretationNote = `${useNote} ${ratingNote} Angezeigt wird nur die Produktionsphase A1–A3, nicht der gesamte Lebenszyklus. Negative CO₂-Werte können biogenen Kohlenstoff im Material abbilden und bedeuten nicht automatisch eine negative Gesamtbilanz.`;

  detailPanel.innerHTML = `
    <div class="detail-content">
      <div class="detail-topline">
        <span class="detail-kicker">Material-Datensatz</span>
        ${ratingBadge(data.rating)}
      </div>
      <h2 class="detail-title">${escapeHtml(item.Name)}</h2>
      <p class="detail-category">${escapeHtml(item.Category || "Kategorie nicht angegeben")}</p>
      <div class="gwp-card">
        <span class="gwp-label">Treibhauspotenzial · GWP total</span>
        <strong class="gwp-value">${formatNumber(item.Gwp)}</strong>
        <span class="gwp-unit">kg CO₂-Äquivalent ${reference}</span>
        <div class="gwp-caption">Produktionsphase A1–A3 · DIN EN 15804+A2</div>
      </div>
      ${metrics}
      <dl class="metadata">
        <div><dt>Datenquelle</dt><dd>${escapeHtml(readableText(data.source))}</dd></div>
        <div><dt>Datensatz-Version</dt><dd>${escapeHtml(item.Version || "Nicht angegeben")}</dd></div>
        <div><dt>Vorläufiges Vergleichsprofil</dt><dd>${escapeHtml(item.ComparisonClass || "Nicht angegeben")}</dd></div>
        <div><dt>Referenzjahr</dt><dd>${escapeHtml(item.ReferenceYear || "Nicht angegeben")}</dd></div>
        <div><dt>Dateneigner</dt><dd>${escapeHtml(item.Owner || "Nicht angegeben")}</dd></div>
        <div><dt>Gültigkeit</dt><dd>${escapeHtml(item.ValidUntil || "Nicht angegeben")} · ${escapeHtml(validityLabel)}</dd></div>
        <div><dt>Lokal abgerufen</dt><dd>${escapeHtml(data.retrievedAt || "Nicht angegeben")}</dd></div>
      </dl>
      <a class="dataset-link" href="${escapeHtml(item.Url)}" target="_blank" rel="noreferrer">Originaldatensatz bei ÖKOBAUDAT ansehen ↗</a>
      <p class="compare-note">${interpretationNote}</p>
      <div class="alternatives">
        <h3>GWP-Datensatzvergleich</h3>
        <p class="alternatives-intro">${data.comparison.count} gültige Datensätze derselben Kategorie in „${escapeHtml(data.comparison.category)}“, Modul A1–A3, je ${escapeHtml(data.comparison.referenceAmount || "unbekannte Bezugsmenge")} ${escapeHtml(readableText(data.comparison.unit || ""))}. Höchstens eine Variante mit niedrigerem GWP wird gezeigt. Das ist kein Materialersatz.</p>
        ${alternatives}
      </div>
      ${renderMaterialAlternative(data.materialAlternative)}
    </div>
  `;
}

useCase.addEventListener("change", () => {
  if (selectedItem && selectedButton) {
    selectResult(selectedItem, selectedButton);
  }
});

form.addEventListener("submit", async (event) => {
  event.preventDefault();
  const query = input.value.trim();
  if (query.length < 2) {
    setMessage("Suchbegriff zu kurz", "Bitte gib mindestens zwei Zeichen ein.", "error");
    input.focus();
    return;
  }

  searchButton.disabled = true;
  searchButton.querySelector("span").textContent = "Suche …";
  resultsSection.hidden = true;
  selectedItem = null;
  selectedButton = null;
  setMessage("ÖKOBAUDAT wird durchsucht", "Beim ersten Suchlauf wird der offizielle CSV-Export geladen und lokal zwischengespeichert. Das kann einen Moment dauern.", "loading");

  try {
    const data = await requestJson(`/api/search?q=${encodeURIComponent(query)}`);
    renderResults(data);
  } catch (error) {
    setMessage("Die Suche konnte nicht abgeschlossen werden", error.message, "error");
  } finally {
    searchButton.disabled = false;
    searchButton.querySelector("span").textContent = "Suchen";
  }
});

modelFile.addEventListener("change", () => {
  const file = modelFile.files?.[0];
  if (!file) {
    modelStatus.textContent = "Noch kein Modell ausgewählt. Native Archicad-PLN-Dateien werden nicht unterstützt.";
    return;
  }

  if (!file.name.toLowerCase().endsWith(".ifc")) {
    modelStatus.textContent = "Nicht unterstützt: Bitte einen IFC-Export aus Archicad wählen. PLN-Dateien werden nicht verarbeitet.";
    modelFile.value = "";
    return;
  }

  modelStatus.textContent = `Ausgewählt: ${file.name}. Demo: Die Datei wurde nicht hochgeladen oder ausgewertet; die Materialsuche oben funktioniert unabhängig davon.`;
});
