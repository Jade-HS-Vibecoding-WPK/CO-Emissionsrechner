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

const ratingLabels = {
  good: "Niedriger im Vergleich",
  medium: "Mittlerer Vergleichswert",
  poor: "Höher im Vergleich",
  unknown: "Nicht sicher bewertbar",
};

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
  const color = rating?.Color || "unknown";
  const label = readableText(rating?.Label || ratingLabels[color]);
  return `<span class="rating-badge ${escapeHtml(color)}"><i class="traffic-dot ${escapeHtml(color)}" aria-hidden="true"></i>${escapeHtml(label)}</span>`;
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
  resultsCount.textContent = data.count > data.items.length
    ? `${data.count} Datensätze · erste ${data.items.length} angezeigt`
    : `${data.count} ${data.count === 1 ? "Datensatz" : "Datensätze"}`;
  detailPanel.innerHTML = `<div class="empty-detail"><span class="empty-icon" aria-hidden="true">↖</span><strong>Wähle einen Datensatz</strong><p>Hier siehst du die Ökobilanzwerte und passende Vergleichsmöglichkeiten.</p></div>`;

  if (!data.items.length) {
    resultsList.innerHTML = `<div class="empty-detail"><strong>Keine passenden Datensätze gefunden</strong><p>Versuche einen allgemeineren Begriff, zum Beispiel „Dämmung“, „Holz“ oder „Beton“.</p></div>`;
    detailPanel.innerHTML = `<div class="empty-detail"><span class="empty-icon" aria-hidden="true">⌕</span><strong>Suche anpassen</strong><p>Die App zeigt nur Treffer aus dem gewählten ÖKOBAUDAT-Datenbestand.</p></div>`;
    return;
  }

  resultsList.innerHTML = data.items.map((item, index) => `
    <button class="result-card" type="button" data-index="${index}" aria-pressed="false">
      <span class="result-name">${escapeHtml(item.Name)}</span>
      <span class="result-category">${escapeHtml(item.Category || "Kategorie nicht angegeben")}</span>
      <span class="result-bottom">
        <span class="result-year">${escapeHtml(item.ReferenceYear || "Jahr unbekannt")} · ${item.ReferenceAmount && item.Unit ? `pro ${escapeHtml(item.ReferenceAmount)} ${escapeHtml(readableText(item.Unit))}` : "Bezugsgröße fehlt"}</span>
        <span class="result-value">${item.Gwp === null ? "Kein CO₂-Wert" : `${formatNumber(item.Gwp)} kg CO₂-eq`}</span>
      </span>
    </button>
  `).join("");

  resultsList.querySelectorAll(".result-card").forEach((button) => {
    button.addEventListener("click", () => selectResult(data.items[Number(button.dataset.index)], button));
  });

  if (data.warning) {
    setMessage("Zwischengespeicherte Daten", data.warning);
  } else {
    setMessage(
      `${data.count} ${data.count === 1 ? "Datensatz" : "Datensätze"} gefunden`,
      `Quelle: ${readableText(data.source)}. Daten lokal abgerufen am ${data.retrievedAt}. Wähle einen Treffer für Details und Vergleiche.`,
    );
  }
}

async function selectResult(item, button) {
  resultsList.querySelectorAll(".result-card").forEach((card) => card.setAttribute("aria-pressed", "false"));
  button.setAttribute("aria-pressed", "true");
  detailPanel.innerHTML = `<div class="empty-detail"><span class="empty-icon" aria-hidden="true">…</span><strong>Datensatz wird geladen</strong></div>`;

  try {
    const params = new URLSearchParams({ id: item.Id, version: item.Version });
    const data = await requestJson(`/api/detail?${params}`);
    renderDetail(data, useCase.value);
  } catch (error) {
    detailPanel.innerHTML = `<div class="empty-detail"><strong>Details konnten nicht geladen werden</strong><p>${escapeHtml(error.message)}</p></div>`;
  }
}

function renderDetail(data, selectedUse) {
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
    ? data.alternatives.map((alternative) => `
        <div class="alternative">
          <div>
            <span class="alternative-name">${escapeHtml(alternative.Item.Name)}</span>
            <span class="alternative-cat">${escapeHtml(alternative.Item.Category)}</span>
          </div>
          <div class="alternative-value">
            <i class="traffic-dot ${escapeHtml(alternative.Rating.Color)}" aria-hidden="true"></i>
            ${formatNumber(alternative.Item.Gwp)} kg
            <small>${escapeHtml(alternative.Rating.Label)}</small>
          </div>
        </div>
      `).join("")
    : `<p class="no-alternatives">In derselben ÖKOBAUDAT-Hauptkategorie, Einheit und Lebenszyklusphase wurden keine passenden Vergleichsdatensätze gefunden.</p>`;
  const useNote = selectedUse
    ? `Dein gewählter Einsatz: ${escapeHtml(selectedUse)}. Die Alternativen unten stammen aus derselben ÖKOBAUDAT-Kategorie; die Daten bestätigen keine technische Austauschbarkeit.`
    : "Die Alternativen stammen aus derselben ÖKOBAUDAT-Hauptkategorie, Einheit und Lebenszyklusphase. Die Daten bestätigen keine technische Austauschbarkeit.";
  const interpretationNote = `${useNote} Angezeigt wird nur die Produktionsphase A1–A3, nicht der gesamte Lebenszyklus. Negative CO₂-Werte können biogenen Kohlenstoff im Material abbilden und bedeuten nicht automatisch eine negative Gesamtbilanz.`;

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
        <div><dt>Datenquelle</dt><dd>ÖKOBAUDAT 2024-II</dd></div>
        <div><dt>Referenzjahr</dt><dd>${escapeHtml(item.ReferenceYear || "Nicht angegeben")}</dd></div>
        <div><dt>Dateneigner</dt><dd>${escapeHtml(item.Owner || "Nicht angegeben")}</dd></div>
        <div><dt>Gültig bis</dt><dd>${escapeHtml(item.ValidUntil || "Nicht angegeben")}</dd></div>
      </dl>
      <a class="dataset-link" href="${escapeHtml(item.Url)}" target="_blank" rel="noreferrer">Originaldatensatz bei ÖKOBAUDAT ansehen ↗</a>
      <p class="compare-note">${interpretationNote} Verglichen wird nur der ausgewiesene GWP-Wert; die Ampel ist relativ zur passenden Datensatzgruppe, kein allgemeines Qualitätsurteil.</p>
      <div class="alternatives">
        <h3>Materialien zum Vergleichen</h3>
        <p class="alternatives-intro">${data.comparison.count} Datensätze in „${escapeHtml(data.comparison.category)}“ je ${escapeHtml(data.comparison.referenceAmount || "unbekannte Bezugsmenge")} ${escapeHtml(readableText(data.comparison.unit || ""))}. Niedrigere GWP-Werte stehen oben.</p>
        ${alternatives}
      </div>
    </div>
  `;
}

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
  setMessage("ÖKOBAUDAT wird durchsucht", "Beim ersten Start werden etwa 50 MB aus dem offiziellen Export geladen und auf vergleichbare Datensätze geprüft. Spätere Suchen verwenden den lokalen Zwischenspeicher.", "loading");

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
