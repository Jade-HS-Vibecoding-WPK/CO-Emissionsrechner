import {
  assessProjectDataQuality,
  calculateContribution,
  datasetUnitInfo,
  flattenSearchResults,
  isDatasetValid,
  parseIfcText,
} from "/ifc.mjs";

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
const modelResults = document.querySelector("#ifc-results");
const modelResultsSummary = document.querySelector("#ifc-results-summary");
const modelResultsBody = document.querySelector("#ifc-results-body");
const modelTotal = document.querySelector("#ifc-total");
let selectedItem = null;
let selectedButton = null;
let ifcState = null;
let modelLoadRevision = 0;

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

function hasUsableRank(item) {
  const rank = Number(item.Rating?.Rank);
  const count = Number(item.Rating?.Count);
  return Number.isFinite(rank) && Number.isFinite(count) && count >= 3 && rank >= 1 && rank <= count;
}

function compareNames(left, right) {
  return String(left ?? "").localeCompare(String(right ?? ""), "de", { sensitivity: "base" });
}

function comparePeerItems(left, right) {
  const leftRanked = hasUsableRank(left);
  const rightRanked = hasUsableRank(right);
  if (leftRanked !== rightRanked) return leftRanked ? -1 : 1;
  if (leftRanked && rightRanked) {
    const rankDifference = Number(left.Rating.Rank) - Number(right.Rating.Rank);
    if (rankDifference) return rankDifference;
    const gwpDifference = Number(left.Gwp) - Number(right.Gwp);
    if (Number.isFinite(gwpDifference) && gwpDifference) return gwpDifference;
  }
  return compareNames(left.Name, right.Name) ||
    compareNames(left.Version, right.Version) ||
    compareNames(left.Id, right.Id);
}

function peerStatusOrder(status) {
  return ({
    ranked: 0,
    unclassified: 1,
    expired: 2,
    "validity-unknown": 3,
    incomplete: 4,
  })[status] ?? 4;
}

function comparePeerGroups(left, right) {
  return peerStatusOrder(left.Status) - peerStatusOrder(right.Status) ||
    compareNames(left.ComparisonClass, right.ComparisonClass) ||
    compareNames(left.Unit, right.Unit) ||
    compareNames(left.ReferenceAmount, right.ReferenceAmount);
}

function rankPosition(item) {
  const rank = Number(item.Rating.Rank);
  const count = Number(item.Rating.Count);
  return Math.round(((count - rank) / (count - 1)) * 100);
}

function rankingText(item) {
  if (hasUsableRank(item)) {
    return `Rang ${formatNumber(item.Rating.Rank)} von ${formatNumber(item.Rating.Count)} · ${item.Rating.Group}`;
  }
  if (item.Rating?.Group === "nicht unterscheidbar") {
    return "Nicht unterscheidbar · gleiche GWP-Werte";
  }
  return "Nicht klassifiziert · kein belastbarer Rang";
}

function peerHeading(peer) {
  if (peer.Status === "ranked") return "Vergleichbare Treffer";
  if (peer.Status === "unclassified" && peer.RatingGroup === "nicht unterscheidbar") {
    return "Nicht unterscheidbar · gleiche GWP-Werte";
  }
  if (peer.Status === "unclassified") return "Vergleichbar, aber nicht klassifiziert";
  if (peer.Status === "expired") return "Nicht klassifiziert · Gültigkeit abgelaufen";
  if (peer.Status === "validity-unknown") return "Nicht klassifiziert · Gültigkeit unbekannt";
  return "Nicht klassifiziert · Vergleichsdaten fehlen";
}

function peerDescription(peer) {
  if (!peer.ComparisonClass || !peer.Unit || !peer.ReferenceAmount) return "";
  return `${peer.ComparisonClass} · pro ${peer.ReferenceAmount} ${readableText(peer.Unit)}`;
}

function getPeerGroups(group) {
  const peerGroups = group.PeerGroups || [{
    Status: "incomplete",
    Count: group.Items?.length || 0,
    Items: group.Items || [],
  }];
  return peerGroups
    .map((peer) => ({ ...peer, Items: [...(peer.Items || [])].sort(comparePeerItems) }))
    .sort(comparePeerGroups);
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
        ${getPeerGroups(group).map((peer, peerIndex) => `
          <section class="peer-group">
            <header class="peer-heading">
              <div>
                <h4>${escapeHtml(peerHeading(peer))}</h4>
                ${peerDescription(peer) ? `<span>${escapeHtml(peerDescription(peer))}</span>` : ""}
              </div>
              <span>${formatNumber(peer.Count)} ${peer.Count === 1 ? "Datensatz" : "Datensätze"}</span>
            </header>
            ${peer.Items.map((item, itemIndex) => `
              <button class="result-card" type="button" data-group-index="${groupIndex}" data-peer-index="${peerIndex}" data-item-index="${itemIndex}" aria-pressed="false">
                <span class="result-name">${escapeHtml(item.Name)}</span>
                <span class="result-bottom">
                  <span class="result-year">${escapeHtml(item.ReferenceYear || "Jahr unbekannt")} · ${item.ReferenceAmount && item.Unit ? `pro ${escapeHtml(item.ReferenceAmount)} ${escapeHtml(readableText(item.Unit))}` : "Bezugsgröße fehlt"}</span>
                  <span class="result-value">${item.Gwp === null ? "Kein GWP-Wert" : `${formatNumber(item.Gwp)} kg CO₂-eq`}</span>
                </span>
                <span class="result-ranking">
                  ${hasUsableRank(item)
                    ? `<span class="rank-meter" style="--rank-position: ${rankPosition(item)}%" aria-hidden="true"><span></span></span>`
                    : ""}
                  <span class="result-ranking-label">${escapeHtml(rankingText(item))}</span>
                </span>
              </button>
            `).join("")}
            ${peer.Count > peer.Items.length ? `<p class="variant-note">${peer.Items.length} Varianten angezeigt; ${peer.Count - peer.Items.length} weitere Datensätze sind in dieser Vergleichsgruppe enthalten. Verfeinere die Suche für eine bestimmte Produktvariante.</p>` : ""}
          </section>
        `).join("")}
      </div>
    </section>
  `).join("");

  resultsList.querySelectorAll(".result-card").forEach((button) => {
    button.addEventListener("click", () => {
      const group = data.groups[Number(button.dataset.groupIndex)];
      const peer = getPeerGroups(group)[Number(button.dataset.peerIndex)];
      selectResult(peer.Items[Number(button.dataset.itemIndex)], button);
    });
  });

  const provenance = data.provenance || {};
  const cacheStatus = ({
    updated: "gerade aktualisiert",
    "current-cache": "Tagescache",
    "refresh-failed": "Cache nach fehlgeschlagener Aktualisierung",
    "release-unverified-cache": "Cache, Datenstand nicht verifiziert",
  })[provenance.cacheStatus] || "lokaler Datenstand";
  const release = provenance.release ? ` Datenstand ${provenance.release}.` : "";
  const hasCatalogCount = provenance.catalogRecordCount !== null &&
    provenance.catalogRecordCount !== undefined &&
    Number.isFinite(Number(provenance.catalogRecordCount));
  const catalogCount = hasCatalogCount
    ? ` Lokaler Suchindex mit ${formatNumber(provenance.catalogRecordCount)} Datensätzen.`
    : "";
  const matchedAliases = (data.matchedTerms || [])
    .filter((term) => term.toLocaleLowerCase("de") !== String(data.query || "").toLocaleLowerCase("de"));
  const aliasNote = matchedAliases.length
    ? ` Synonym-/Alternativtreffer über: ${matchedAliases.join(", ")}.`
    : "";
  const usageNote = provenance.usageNotice ? ` ${provenance.usageNotice}` : "";
  const provenanceText = `Quelle: ${readableText(data.source)}.${release} Cache: ${cacheStatus}; lokal abgerufen am ${data.retrievedAt || "unbekannt"}.${catalogCount}${aliasNote}${usageNote}`;
  if (data.warning) {
    const title = provenance.cacheStatus === "refresh-failed" || provenance.cacheStatus === "release-unverified-cache"
      ? "Zwischengespeicherte Daten"
      : "Hinweis zum Datenstand";
    setMessage(title, `${data.warning} ${provenanceText}`);
  } else {
    setMessage(
      `${data.groups.length} Materialgruppen gefunden`,
      `${data.count} Datensätze in ${data.groupCount} Gruppen; angezeigt werden höchstens zehn Gruppen. ${provenanceText}`,
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
  const hasRank = Number.isFinite(data.rating.Rank) && Number.isFinite(data.rating.Count);

  detailPanel.innerHTML = `
    <div class="detail-content">
      <div class="detail-topline">
        <span class="detail-kicker">Material-Datensatz</span>
        ${ratingBadge(data.rating)}
      </div>
      <h2 class="detail-title">${escapeHtml(item.Name)}</h2>
      <p class="detail-category">${escapeHtml(item.Category || "Kategorie nicht angegeben")}</p>
      <div class="gwp-card">
        <div class="gwp-main">
          <span class="gwp-label">Treibhauspotenzial · GWP total</span>
          <strong class="gwp-value">${formatNumber(item.Gwp)}</strong>
          <span class="gwp-unit">kg CO₂-Äquivalent ${reference}</span>
          <div class="gwp-caption">Produktionsphase A1–A3 · DIN EN 15804+A2</div>
        </div>
        <aside class="gwp-ranking" aria-label="Relative Rangordnung">
          <span class="gwp-ranking-label">${hasRank ? "Rang in Vergleichsgruppe" : "Einordnung"}</span>
          ${hasRank
            ? `<strong class="gwp-ranking-value">${formatNumber(data.rating.Rank)}<span> von ${formatNumber(data.rating.Count)}</span></strong>
              <span class="gwp-ranking-group">${escapeHtml(data.rating.Group)}</span>`
            : `<strong class="gwp-ranking-unavailable">${escapeHtml(data.rating.Group || "nicht vergleichbar")}</strong>
              <span class="gwp-ranking-group">Keine vergleichbare Rangzahl</span>`}
        </aside>
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
  setMessage("ÖKOBAUDAT wird durchsucht", "Die offizielle Downloadseite wird auf den aktuellen Datenstand geprüft; die verlinkte CSV-Datei wird bei Bedarf lokal zwischengespeichert.", "loading");

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

function getSelectedDataset(row, searchResult) {
  if (!Number.isInteger(row.selectedDatasetIndex)) return null;
  return searchResult?.items[row.selectedDatasetIndex] || null;
}

function getDatasetSourceLink(dataset) {
  try {
    const url = new URL(dataset?.Url);
    if (url.protocol === "https:" &&
      (url.hostname === "oekobaudat.de" || url.hostname.endsWith(".oekobaudat.de"))) {
      return `<a href="${escapeHtml(url.href)}" target="_blank" rel="noreferrer">ÖKOBAUDAT-Quelldatensatz ↗</a>`;
    }
  } catch {
    return "ÖKOBAUDAT-Quelldatensatz-Link nicht verfügbar";
  }
  return "ÖKOBAUDAT-Quelldatensatz-Link nicht verfügbar";
}

function getDatasetValidityText(dataset) {
  if (isDatasetValid(dataset)) return `gültig bis ${dataset.ValidUntil || "nicht angegeben"}`;
  if (dataset?.Validity === "expired") return `abgelaufen seit ${dataset.ValidUntil || "unbekannt"}`;
  return "Gültigkeit unbekannt";
}

function getPublicSourceHints() {
  return `<small class="ifc-public-source-hints">Weitere Quellen zur manuellen Prüfung: <a href="https://www.wecobis.de/index.php?id=16043" target="_blank" rel="noreferrer">WECOBIS</a> (Materialkontext, kein GWP-Faktor) · <a href="https://ibu-epd.com/veroeffentlichte-epds/" target="_blank" rel="noreferrer">IBU-EPDs</a> (öffentliche PDF/HTML-Angaben prüfen). Daraus wird hier kein automatischer Zahlenwert übernommen.</small>`;
}

function getQuantityLabel(quantity) {
  if (quantity.error) return `${quantity.name}: ${quantity.error}`;
  const original = `${formatNumber(quantity.value)} ${quantity.sourceUnit || quantity.unit || quantity.dimension}`;
  const converted = quantity.sourceUnit && quantity.unit
    ? ` → ${formatNumber(quantity.canonicalValue)} ${quantity.unit}`
    : "";
  return `${quantity.name}: ${original}${converted}`;
}

function renderIfcResults() {
  if (!ifcState) {
    modelResults.hidden = true;
    return;
  }

  modelResults.hidden = false;
  const completed = [];
  const unresolved = [];
  const assessmentEntries = [];
  modelResultsBody.innerHTML = ifcState.rows.map((row, index) => {
    const element = row.element;
    const material = element.materials.length === 1 ? element.materials[0] : "";
    const searchResult = material ? ifcState.materialSearch.get(material) : null;
    const candidates = searchResult?.items || [];
    const dataset = getSelectedDataset(row, searchResult);
    const quantity = Number.isInteger(row.selectedQuantityIndex)
      ? element.quantities[row.selectedQuantityIndex]
      : null;
    let calculation = null;
    let status = "";
    let statusClass = "is-pending";

    if (element.materialStatus === "ambiguous") {
      status = element.materials.length > 1
        ? `Mehrere Materialien (${element.materials.join(", ")}); die Elementmenge lässt sich keinem Material sicher zuordnen.`
        : element.materialIssue || "Die IFC-Materialzuordnung lässt sich nicht eindeutig lesen.";
    } else if (element.materialStatus === "missing") {
      status = "Keine explizite IFC-Materialzuordnung vorhanden.";
    } else if (!searchResult || searchResult.loading) {
      status = "ÖKOBAUDAT-Datensätze werden gesucht …";
    } else if (searchResult.error) {
      status = `Datensatzsuche fehlgeschlagen: ${searchResult.error}`;
    } else if (!candidates.length) {
      status = "Keine ÖKOBAUDAT-Treffer für dieses IFC-Material.";
    } else if (!dataset) {
      status = "ÖKOBAUDAT-Datensatz auswählen.";
    } else if (!isDatasetValid(dataset)) {
      status = dataset.Validity === "expired"
        ? `Datensatz abgelaufen (${dataset.ValidUntil || "Ablaufjahr unbekannt"}); er wird nicht eingerechnet.`
        : "Gültigkeit des Datensatzes unbekannt; er wird nicht eingerechnet.";
    } else {
      const datasetUnit = datasetUnitInfo(dataset.Unit);
      const compatibleQuantities = element.quantities
        .map((item, quantityIndex) => ({ item, quantityIndex }))
        .filter(({ item }) => !item.error &&
          Number.isFinite(item.canonicalValue) &&
          item.canonicalValue >= 0 &&
          datasetUnit?.dimension === item.dimension);
      if (!datasetUnit) {
        status = `Datensatz-Einheit „${dataset.Unit || "unbekannt"}“ wird nicht unterstützt.`;
      } else if (!compatibleQuantities.length) {
        status = "Keine explizite IFC-Menge mit kompatibler, unterstützter Einheit vorhanden.";
      } else if (!quantity) {
        status = "Passende IFC-Menge auswählen.";
      } else {
        try {
          calculation = calculateContribution(quantity, dataset);
          status = "Berechnet aus IFC-Menge und gewähltem ÖKOBAUDAT-Datensatz.";
          statusClass = "is-calculated";
        } catch (error) {
          status = error.message;
        }
      }
    }

    if (calculation) completed.push({ calculation, dataset, material });
    else unresolved.push(element);

    const datasetOptions = candidates.map((candidate, candidateIndex) => {
      const amount = candidate.ReferenceAmount && candidate.Unit
        ? `pro ${candidate.ReferenceAmount} ${readableText(candidate.Unit)}`
        : "Bezugsgröße fehlt";
      const gwp = candidate.Gwp === null || candidate.Gwp === undefined || candidate.Gwp === ""
        ? "kein GWP-Wert"
        : `${formatNumber(candidate.Gwp)} kg CO₂-eq`;
      const validity = candidate.Validity === "valid"
        ? "gültig"
        : candidate.Validity === "expired"
          ? "abgelaufen"
          : "Gültigkeit unbekannt";
      return `<option value="${candidateIndex}" ${candidateIndex === row.selectedDatasetIndex ? "selected" : ""}>${escapeHtml(candidate.Name)} · ${escapeHtml(gwp)} · ${escapeHtml(amount)} · ${escapeHtml(candidate.ReferenceYear || "Jahr unbekannt")} · ${validity}</option>`;
    }).join("");
    const quantityOptions = element.quantities.map((item, quantityIndex) => {
      const incompatible = dataset && datasetUnitInfo(dataset.Unit)?.dimension !== item.dimension;
      const disabled = Boolean(item.error) || incompatible || item.canonicalValue < 0;
      return `<option value="${quantityIndex}" ${quantityIndex === row.selectedQuantityIndex ? "selected" : ""} ${disabled ? "disabled" : ""}>${escapeHtml(getQuantityLabel(item))}</option>`;
    }).join("");
    const materialCell = element.materialStatus === "ready"
      ? `<strong>${escapeHtml(material)}</strong><small>${escapeHtml(element.materialSource ? `Zuordnung aus ${element.materialSource}` : "Materialquelle nicht angegeben")}</small>
          <label class="ifc-control-label" for="ifc-dataset-${index}">Datensatz</label>
          <select id="ifc-dataset-${index}" data-ifc-dataset="${index}" aria-label="ÖKOBAUDAT-Datensatz für ${escapeHtml(element.name)}">
            <option value="">Datensatz auswählen</option>${datasetOptions}
          </select>${dataset ? `<small>${getDatasetSourceLink(dataset) || "ÖKOBAUDAT-Quelle: sicherer Datensatzlink nicht verfügbar"} · Version ${escapeHtml(dataset.Version || "nicht angegeben")} · Bezugsmenge ${escapeHtml(dataset.ReferenceAmount || "nicht angegeben")} ${escapeHtml(readableText(dataset.Unit || ""))} · ${escapeHtml(getDatasetValidityText(dataset))}</small>` : ""}${!calculation ? getPublicSourceHints() : ""}`
      : `<strong>${element.materials.length ? element.materials.map(escapeHtml).join(", ") : "Material fehlt"}</strong><small>${element.materialStatus === "ambiguous" ? escapeHtml(element.materialIssue || "Mehrfachzuordnung; keine Mengenaufteilung geraten") : "Keine direkte oder eindeutige Typzuordnung"}</small>`;
    const contributionCell = calculation
      ? `<strong>${formatNumber(calculation.contribution)} kg CO₂-eq</strong><small>${formatNumber(calculation.gwp)} kg CO₂-eq × ${formatNumber(calculation.datasetQuantity)} ${escapeHtml(readableText(calculation.datasetUnit))} ÷ ${formatNumber(calculation.referenceAmount)} ${escapeHtml(readableText(calculation.datasetUnit))}</small>`
      : "<span>—</span>";

    assessmentEntries.push({ calculation, dataset, material, contained: element.contained });
    return `<tr>
      <th scope="row"><strong>${escapeHtml(element.name)}</strong><small>${escapeHtml(element.type)} · #${escapeHtml(element.id)}</small></th>
      <td>${materialCell}</td>
      <td><label class="ifc-control-label" for="ifc-quantity-${index}">Menge</label>
        <select id="ifc-quantity-${index}" data-ifc-quantity="${index}" aria-label="IFC-Menge für ${escapeHtml(element.name)}">
          <option value="">Menge auswählen</option>${quantityOptions}
        </select></td>
      <td>${contributionCell}</td>
      <td><span class="ifc-row-status ${statusClass}">${escapeHtml(status)}</span></td>
    </tr>`;
  }).join("");

  const containedRows = ifcState.rows.filter((row) => row.element.contained).length;
  const uncontainedRows = ifcState.rows.length - containedRows;
  const scopeSummary = ifcState.containmentAvailable
    ? `${containedRows} erfasste ${containedRows === 1 ? "Bauteil ist" : "Bauteile sind"} in der IFC-Raumstruktur enthalten; ${uncontainedRows} nicht.`
    : "Keine IFC-Raumstrukturzuordnung gefunden; die Vollständigkeit des Modellumfangs ist nicht prüfbar.";
  modelResultsSummary.textContent =
    `Schema ${ifcState.schema} · ${ifcState.rows.length} erfasste Bauteile · ${completed.length} berechenbar. ${scopeSummary}`;

  const quality = assessProjectDataQuality(assessmentEntries, ifcState.containmentAvailable);
  if (!completed.length) {
    modelTotal.innerHTML = `<div class="ifc-total-main">
        <div><p class="ifc-total-eyebrow">ÖKOBAUDAT-Schätzung · A1–A3-Teilbilanz</p><p class="ifc-total-empty">Noch keine Beiträge berechenbar</p></div>
        <div class="ifc-quality" data-level="${quality.level}"><strong>${escapeHtml(quality.label)}</strong><p>${escapeHtml(quality.explanation)}</p></div>
      </div>
      <p class="ifc-total-limit">Ohne berechenbare Beiträge wird keine Zahl ausgegeben. Es gibt keine statistische Unsicherheitsspanne; fehlende Daten werden nicht ergänzt oder geschätzt.</p>`;
  } else {
    const subtotal = completed.reduce((sum, item) => sum + item.calculation.contribution, 0);
    const scopeExplanation = unresolved.length
      ? `${completed.length} von ${ifcState.rows.length} erfassten Bauteilen sind in der Zahl enthalten; ${unresolved.length} bleiben unberechnet.`
      : `Alle ${ifcState.rows.length} vom Parser erfassten Bauteile sind berechenbar.`;
    const fileScopeWarning = !ifcState.containmentAvailable
      ? "Eine IFC-Raumstrukturzuordnung fehlt; die Vollständigkeit des Modellumfangs ist nicht prüfbar."
      : uncontainedRows
        ? `${uncontainedRows} erfasste Bauteile sind keiner IFC-Raumstruktur zugeordnet; der Modellumfang ist nicht prüfbar.`
        : "Die Vollständigkeit des IFC-Exports ist nicht unabhängig bestätigt.";
    const groupedDatasets = new Map();
    for (const { calculation, dataset } of completed) {
      const key = `${dataset.Id || dataset.Name}|${dataset.Version || ""}`;
      const group = groupedDatasets.get(key);
      if (group) {
        group.count += 1;
      } else {
        groupedDatasets.set(key, { dataset, calculation, count: 1 });
      }
    }
    const datasetSources = [...groupedDatasets.values()].map(({ dataset, calculation, count }) =>
      `<li><strong>${escapeHtml(dataset.Name || "ÖKOBAUDAT-Datensatz")}</strong> · Version ${escapeHtml(dataset.Version || "nicht angegeben")}
        <span>${getDatasetSourceLink(dataset) || "ÖKOBAUDAT-Quelle: sicherer Datensatzlink nicht verfügbar"}</span>
        <span>${formatNumber(calculation.gwp)} kg CO₂-eq je ${formatNumber(calculation.referenceAmount)} ${escapeHtml(readableText(calculation.datasetUnit))} · Referenzjahr ${escapeHtml(dataset.ReferenceYear || "nicht angegeben")} · ${escapeHtml(dataset.Owner || "Dateneigner nicht angegeben")}</span>
        <span>${count} ${count === 1 ? "Bauteil" : "Bauteile"} · ${escapeHtml(getDatasetValidityText(dataset))}</span></li>`).join("");
    modelTotal.innerHTML = `<div class="ifc-total-main">
        <div>
          <p class="ifc-total-eyebrow">ÖKOBAUDAT-Schätzung · A1–A3-Teilbilanz</p>
          <p class="ifc-total-number">${formatNumber(subtotal)} <span>kg CO₂-eq</span></p>
          <p class="ifc-total-caption">${escapeHtml(scopeExplanation)} ${escapeHtml(fileScopeWarning)}</p>
        </div>
        <div class="ifc-quality" data-level="${quality.level}"><strong>${escapeHtml(quality.label)}</strong><p>${escapeHtml(quality.explanation)}</p></div>
      </div>
      <p class="ifc-total-method"><strong>Systemgrenze:</strong> Produktionsphase A1–A3 nach EN 15804+A2, nicht der gesamte Lebenszyklus. <strong>Rechenweg:</strong> Summe aus (IFC-Menge ÷ Bezugsmenge) × ÖKOBAUDAT-GWP.</p>
      <div class="ifc-total-sources"><h3>Verwendete ÖKOBAUDAT-Datensätze</h3><ul>${datasetSources}</ul></div>
      <p class="ifc-total-limit">Komponentenbasierte Schätzung, keine geprüfte Vollbilanz. Das Qualitätslabel beschreibt Datenlage und Zuordnung, keine statistische Genauigkeit; eine belastbare Unsicherheitsspanne liegt nicht vor.</p>`;
  }
}

modelResults.addEventListener("change", (event) => {
  const control = event.target;
  const datasetIndex = Number(control.dataset.ifcDataset);
  const quantityIndex = Number(control.dataset.ifcQuantity);
  if (!ifcState) return;

  if (control.matches("[data-ifc-dataset]")) {
    const row = ifcState.rows[datasetIndex];
    const material = row?.element.materials[0];
    const searchResult = material ? ifcState.materialSearch.get(material) : null;
    row.selectedDatasetIndex = control.value === "" ? null : Number(control.value);
    row.selectedQuantityIndex = null;
    const dataset = getSelectedDataset(row, searchResult);
    if (dataset) {
      const compatible = row.element.quantities
        .map((quantity, index) => ({ quantity, index }))
        .filter(({ quantity }) => !quantity.error &&
          quantity.canonicalValue >= 0 &&
          datasetUnitInfo(dataset.Unit)?.dimension === quantity.dimension);
      if (compatible.length === 1) row.selectedQuantityIndex = compatible[0].index;
    }
  } else if (control.matches("[data-ifc-quantity]")) {
    const row = ifcState.rows[quantityIndex];
    if (row) row.selectedQuantityIndex = control.value === "" ? null : Number(control.value);
  } else {
    return;
  }
  renderIfcResults();
});

modelFile.addEventListener("change", async () => {
  const revision = ++modelLoadRevision;
  const file = modelFile.files?.[0];
  if (!file) {
    ifcState = null;
    modelStatus.textContent = "Noch kein Modell ausgewählt. Native Archicad-PLN-Dateien werden nicht unterstützt.";
    renderIfcResults();
    return;
  }
  if (!file.name.toLowerCase().endsWith(".ifc")) {
    modelStatus.textContent = "Nicht unterstützt: Bitte einen IFC-Export aus Archicad wählen. PLN-Dateien werden nicht verarbeitet.";
    modelFile.value = "";
    ifcState = null;
    renderIfcResults();
    return;
  }
  if (file.size > 100 * 1024 * 1024) {
    modelStatus.textContent = "Die IFC-Datei ist größer als 100 MB und kann nicht lokal verarbeitet werden.";
    ifcState = null;
    renderIfcResults();
    return;
  }

  ifcState = null;
  renderIfcResults();
  modelStatus.textContent = `Lese ${file.name} lokal im Browser; die Datei wird nicht hochgeladen …`;
  try {
    const parsed = parseIfcText(await file.text());
    if (revision !== modelLoadRevision) return;
    ifcState = {
      ...parsed,
      rows: parsed.elements.map((element) => ({
        element,
        selectedDatasetIndex: null,
        selectedQuantityIndex: null,
      })),
      materialSearch: new Map(),
    };
    const materialNames = [...new Set(parsed.elements
      .filter((element) => element.materialStatus === "ready")
      .map((element) => element.materials[0]))];
    for (const material of materialNames) {
      if (revision !== modelLoadRevision) return;
      const search = { items: [], loading: true, error: null };
      ifcState.materialSearch.set(material, search);
      modelStatus.textContent = `IFC lokal gelesen. Suche ÖKOBAUDAT-Datensätze für „${material}“ …`;
      renderIfcResults();
      if (material.trim().length < 2) {
        search.loading = false;
        search.error = "Materialname ist zu kurz für die ÖKOBAUDAT-Suche.";
        continue;
      }
      try {
        const data = await requestJson(`/api/search?q=${encodeURIComponent(material)}`);
        if (revision !== modelLoadRevision) return;
        search.items = flattenSearchResults(data)
          .filter((item) => item?.Id && item?.Version)
          .filter((item, index, list) => list.findIndex((other) =>
            other.Id === item.Id && other.Version === item.Version) === index);
      } catch (error) {
        if (revision !== modelLoadRevision) return;
        search.error = error.message;
      } finally {
        search.loading = false;
      }
    }
    if (revision !== modelLoadRevision) return;
    modelStatus.textContent = `${file.name} wurde lokal ausgewertet. Wähle pro Bauteil einen Datensatz und eine passende IFC-Menge; es werden keine Mengen geschätzt.`;
    renderIfcResults();
  } catch (error) {
    if (revision !== modelLoadRevision) return;
    ifcState = null;
    modelStatus.textContent = `IFC-Import fehlgeschlagen: ${error.message}`;
    renderIfcResults();
  }
});
