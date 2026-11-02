import { LightningElement, api, wire, track } from "lwc";
import { getRecord, getFieldValue } from "lightning/uiRecordApi";
import { FlowNavigationNextEvent } from "lightning/flowSupport";
import NOTES_JSON from "@salesforce/schema/Contact.Notes__c";
import { buildVoiceAnalysisModel } from "./deFinalScreenModel.js";

// Matches `audio_analytics_result.html` mini waveform (decorative; original card only)
const WAVE_HEIGHTS = [6, 10, 14, 10, 16, 8, 12, 16, 10, 6, 14, 10];

const PILL_STYLES = [
  "de-fs-lang-hi",
  "de-fs-lang-pa",
  "de-fs-lang-te",
  "de-fs-lang-en"
];

const ENTITY_STYLES = [
  "de-fs-ent-action",
  "de-fs-ent-time",
  "de-fs-ent-object"
];

const FIELDS = [NOTES_JSON];

export default class DeFinalScreen extends LightningElement {
  @api availableActions;
  @api recordId;

  @track _wireError;
  @track _parseError;
  @track _model;
  @track _isLoading = true;
  @track _jsonRaw;

  connectedCallback() {
    this._isLoading = this.recordId != null && String(this.recordId).length >= 3;
  }

  @wire(getRecord, { recordId: "$recordId", fields: FIELDS })
  wiredContact({ data, error }) {
    this._isLoading = false;
    this._wireError = undefined;
    this._parseError = undefined;
    this._jsonRaw = undefined;
    this._model = null;

    if (!this.recordId) {
      return;
    }
    if (error) {
      this._wireError = this._reduceError(error);
      return;
    }
    if (!data) {
      return;
    }
    this._jsonRaw = getFieldValue(data, NOTES_JSON);
    const { model, error: parseError } = buildVoiceAnalysisModel(this._jsonRaw);
    this._parseError = parseError;
    this._model = model;
  }

  get hasRecord() {
    return this.recordId != null && String(this.recordId).length >= 3;
  }

  get isLoading() {
    if (!this.hasRecord) {
      return false;
    }
    return this._isLoading;
  }

  get wireErrorMessage() {
    return this._wireError;
  }

  get showParseError() {
    return this._parseError;
  }

  // --- Header
  get displayTitle() {
    return (this._model && this._model.titleLine1) || "Audio";
  }

  get displayTitleGrad() {
    return (this._model && this._model.titleLine2) || "Analytics";
  }

  get displayBadge() {
    if (!this._model || !this._model.statusBadge) {
      return null;
    }
    return this._model.statusBadge;
  }

  get hasBadge() {
    return Boolean(this.displayBadge);
  }

  get hasSuccessBanner() {
    if (this.isLoading) {
      return false;
    }
    if (!this._model || !this._model.successMessage) {
      return false;
    }
    return true;
  }

  get successBannerText() {
    return this._model && this._model.successMessage
      ? String(this._model.successMessage).trim()
      : "";
  }

  // --- Sections
  get hasOriginal() {
    return this._model && this._model.originalText;
  }

  get displayOriginal() {
    return (this._model && this._model.originalText) || "";
  }

  get languagePills() {
    if (!this._model || !this._model.languages || !this._model.languages.length) {
      return [];
    }
    return this._model.languages.map((label, i) => ({
      key: `lp-${i}`,
      label,
      pillClass: `de-fs-lang-pill ${
        PILL_STYLES[i % PILL_STYLES.length]
      }`
    }));
  }

  get hasLanguagePills() {
    return this.languagePills.length > 0;
  }

  get languageSummary() {
    if (!this._model) {
      return "";
    }
    return this._model.languagesCount
      ? String(this._model.languagesCount)
      : String((this._model.languages && this._model.languages.length) || 0);
  }

  get hasLanguageSummary() {
    return this.hasLanguagePills && (this._model.languagesCount || (this._model.languages && this._model.languages.length));
  }

  get hasSentimentKpi() {
    if (!this._model) {
      return false;
    }
    return (
      (this._model.sentimentLabel != null &&
        String(this._model.sentimentLabel).trim() !== "") ||
      this._model.sentimentMeter != null
    );
  }

  get hasTonalityKpi() {
    if (!this._model) {
      return false;
    }
    return (
      (this._model.tonalityLabel != null &&
        String(this._model.tonalityLabel).trim() !== "") ||
      this._model.tonalityMeter != null
    );
  }

  get kpiCount() {
    return (this.hasSentimentKpi ? 1 : 0) + (this.hasTonalityKpi ? 1 : 0);
  }

  get kpiRowClass() {
    return this.kpiCount < 2 ? "de-fs-kpi-row de-fs-kpi-row--1" : "de-fs-kpi-row";
  }

  get showSentimentMeter() {
    return this._model && this._model.sentimentMeter != null;
  }

  get showTonalityMeter() {
    return this._model && this._model.tonalityMeter != null;
  }

  get displaySentiment() {
    if (!this._model || this._model.sentimentLabel == null) {
      return "—";
    }
    return String(this._model.sentimentLabel);
  }

  get displayTonality() {
    if (!this._model || this._model.tonalityLabel == null) {
      return "—";
    }
    return String(this._model.tonalityLabel);
  }

  get sentimentBarStyle() {
    if (!this._model || this._model.sentimentMeter == null) {
      return "";
    }
    return `width: ${this._model.sentimentMeter}%;`;
  }

  get tonalityBarStyle() {
    if (!this._model || this._model.tonalityMeter == null) {
      return "";
    }
    return `width: ${this._model.tonalityMeter}%;`;
  }

  get hasTranslation() {
    if (!this._model || !this._model.translation) {
      return false;
    }
    return String(this._model.translation).trim() !== "";
  }

  get translationBody() {
    if (!this._model) {
      return "";
    }
    return String(this._model.translation);
  }

  get entityChips() {
    if (!this._model || !this._model.entities) {
      return [];
    }
    return this._model.entities.map((text, i) => ({
      key: `e-${i}`,
      text,
      entClass: `de-fs-entity ${ENTITY_STYLES[i % ENTITY_STYLES.length]}`
    }));
  }

  get hasEntities() {
    return this.entityChips.length > 0;
  }

  get waveBars() {
    if (!this.hasOriginal) {
      return [];
    }
    return WAVE_HEIGHTS.map((h, i) => {
      const mn = Math.max(2, h * 0.3);
      const d = 0.4 + (i % 5) * 0.12;
      return {
        key: `wb-${i}`,
        style: `--de-fs-mn: ${mn}px; --de-fs-mx: ${h}px; --de-fs-d: ${d}s; animation-delay: ${
          i * 0.06
        }s; min-height: ${h}px;`
      };
    });
  }

  get showStack() {
    if (this.isLoading) {
      return false;
    }
    if (!this._model) {
      return false;
    }
    const m = this._model;
    return (
      m.originalText ||
      (m.languages && m.languages.length) ||
      (m.entities && m.entities.length) ||
      m.translation ||
      m.sentimentLabel != null ||
      m.tonalityLabel != null ||
      m.sentimentMeter != null ||
      m.tonalityMeter != null
    );
  }

  get visNoRecord() {
    if (this.isLoading) {
      return false;
    }
    return !this.hasRecord;
  }

  get visEmptyField() {
    if (!this.hasRecord || this.isLoading) {
      return false;
    }
    if (this._wireError || this._parseError) {
      return false;
    }
    return !this._jsonRaw || String(this._jsonRaw).trim() === "";
  }

  get visNoContent() {
    if (!this.hasRecord || this.isLoading) {
      return false;
    }
    if (this._wireError || this._parseError) {
      return false;
    }
    if (!this._jsonRaw || !String(this._jsonRaw).trim()) {
      return false;
    }
    return this._model && !this._model.hasAny;
  }

  // --- Flow
  get showFlowNext() {
    return Array.isArray(this.availableActions);
  }

  get flowNextDisabled() {
    const a = this.availableActions;
    if (!a || !a.length) {
      return false;
    }
    return !a.some((x) => String(x).toUpperCase() === "NEXT");
  }

  handleFlowNext() {
    if (this.flowNextDisabled) {
      return;
    }
    this.dispatchEvent(new FlowNavigationNextEvent());
  }

  _reduceError(error) {
    if (!error) {
      return "Could not load the contact record.";
    }
    if (Array.isArray(error.body) && error.body[0] && error.body[0].message) {
      return error.body[0].message;
    }
    if (error.body && error.body.message) {
      return error.body.message;
    }
    if (typeof error.message === "string") {
      return error.message;
    }
    return "Could not load the contact record.";
  }
}