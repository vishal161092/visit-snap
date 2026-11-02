/**
 * Normalizes `Contact.Notes__c` JSON (loose; supports common key aliases.)
 * Suggested server shape (example):
 * {
 *   "titleLine1": "Audio", "titleLine2": "Analytics", "statusBadge": "Analysis complete",
 *   "successMessage": "…",
 *   "originalText": "…", "languages": ["Hindi","Punjabi"], "languageCount": 4,
 *   "sentiment": { "label": "Neutral", "meter": 50 },
 *   "tonality": { "label": "Urgent", "meter": 82 },
 *   "translation": "…",
 *   "keyEntities": ["Tomorrow", "…"]
 * }
 * @param {string | null | undefined} raw
 * @returns {{ json: object|null, error: string|null, model: object } }
 */
export function buildVoiceAnalysisModel(raw) {
  if (raw === undefined || raw === null || String(raw).trim() === "") {
    return { json: null, error: null, model: emptyModel() };
  }
  let parsed;
  try {
    parsed = JSON.parse(String(raw));
  } catch (e) {
    return { json: null, error: "Invalid JSON in Contact Notes", model: emptyModel() };
  }
  if (parsed === null || typeof parsed !== "object" || Array.isArray(parsed)) {
    return { json: parsed, error: null, model: emptyModel() };
  }
  return { json: parsed, error: null, model: mapModel(parsed) };
}

function emptyModel() {
  return {
    hasAny: false,
    successMessage: null,
    statusBadge: null,
    titleLine1: null,
    titleLine2: null,
    originalText: null,
    languages: [],
    languagesCount: null,
    sentimentLabel: null,
    sentimentMeter: null,
    tonalityLabel: null,
    tonalityMeter: null,
    translation: null,
    entities: []
  };
}

function firstNonEmpty(...candidates) {
  for (const c of candidates) {
    if (c === undefined || c === null) {
      continue;
    }
    if (typeof c === "number" && !Number.isNaN(c)) {
      return c;
    }
    if (Array.isArray(c) && c.length) {
      return c;
    }
    if (typeof c === "string") {
      const t = c.trim();
      if (t !== "") {
        return t;
      }
    }
  }
  return null;
}

/** Read first own property that is present and non-empty (string/array/object/number). */
function pickFirst(obj, ...keys) {
  if (obj == null || typeof obj !== "object") {
    return undefined;
  }
  for (const k of keys) {
    if (Object.prototype.hasOwnProperty.call(obj, k)) {
      const v = obj[k];
      if (v === undefined || v === null) {
        continue;
      }
      if (typeof v === "string" && v.trim() === "") {
        continue;
      }
      if (Array.isArray(v) && v.length === 0) {
        continue;
      }
      return v;
    }
  }
  return undefined;
}

function toMeter(val) {
  if (val === undefined || val === null || val === "") return null;
  const n = parseFloat(String(val));
  if (Number.isNaN(n)) return null;
  return Math.min(100, Math.max(0, n));
}

function normalizeLanguages(root) {
  const raw = firstNonEmpty(
    pickFirst(root, "languages", "Languages", "Language_List"),
    root.languageList,
    root.detectedLanguages,
    root.languagesList
  );
  if (Array.isArray(raw)) {
    return raw
      .map((x) => {
        if (typeof x === "string") return x.trim();
        if (x && typeof x === "object") {
          return firstNonEmpty(x.name, x.label, x.lang, x.code) || null;
        }
        return null;
      })
      .filter(Boolean);
  }
  if (typeof raw === "string") {
    return raw
      .split(/[,;|]/)
      .map((s) => s.trim())
      .filter(Boolean);
  }
  return [];
}

function normalizeEntities(root) {
  const out = [];
  const raw = firstNonEmpty(
    pickFirst(
      root,
      "keyEntities",
      "Key_Entities",
      "KeyEntities",
      "entities",
      "Entities",
      "entityList",
      "KeyEntitiesDetected"
    ),
    pickFirst(root, "entities", "Entities")
  );
  if (Array.isArray(raw)) {
    for (const x of raw) {
      if (typeof x === "string" && x.trim()) out.push(x.trim());
      else if (x && typeof x === "object") {
        const t = firstNonEmpty(x.text, x.name, x.label, x.value);
        if (t) out.push(String(t));
      }
    }
  } else if (typeof raw === "string" && raw.trim()) {
    raw
      .split(/[;|\n]/)
      .map((s) => s.trim())
      .forEach((s) => s && out.push(s));
  }
  return out;
}

function subMeter(obj) {
  if (!obj || typeof obj !== "object" || Array.isArray(obj)) {
    return { label: null, meter: null };
  }
  return {
    label: firstNonEmpty(
      pickFirst(
        obj,
        "label",
        "Label",
        "name",
        "Name",
        "value",
        "Value",
        "tone",
        "mood"
      )
    ),
    meter: toMeter(
      firstNonEmpty(
        pickFirst(obj, "meter", "Meter", "score", "Score", "pct", "Pct"),
        obj.valueNum
      )
    )
  };
}

function mapModel(root) {
  const rawSent = pickFirst(root, "sentiment", "Sentiment", "SENTIMENT");
  const sBlock =
    rawSent && typeof rawSent === "object" && !Array.isArray(rawSent)
      ? subMeter(rawSent)
      : {
          label: firstNonEmpty(
            typeof rawSent === "string" ? String(rawSent).trim() : null,
            pickFirst(root, "sentimentLabel", "Sentiment_Label", "SentimentLabel")
          ),
          meter: toMeter(
            firstNonEmpty(
              pickFirst(root, "sentimentMeter", "Sentiment_Meter", "SentimentMeter"),
              pickFirst(root, "sentimentScore", "Sentiment_Score", "SentimentScore")
            )
          )
        };
  const rawTon = pickFirst(root, "tonality", "Tonality", "TONALITY");
  const tBlock =
    rawTon && typeof rawTon === "object" && !Array.isArray(rawTon)
      ? subMeter(rawTon)
      : {
          label: firstNonEmpty(
            typeof rawTon === "string" ? String(rawTon).trim() : null,
            pickFirst(root, "tonalityLabel", "Tonality_Label", "TonalityLabel")
          ),
          meter: toMeter(
            firstNonEmpty(
              pickFirst(root, "tonalityMeter", "Tonality_Meter", "TonalityMeter"),
              pickFirst(root, "tonalityScore", "Tonality_Score", "TonalityScore")
            )
          )
        };

  const langs = normalizeLanguages(root);
  const lc = firstNonEmpty(
    pickFirst(root, "languageCount", "Language_Count", "LanguageCount"),
    pickFirst(root, "languagesCount", "Languages_Count", "LanguagesCount"),
    pickFirst(root, "numLanguages", "Num_Languages", "NumLanguages")
  );
  const languagesCount =
    lc != null
      ? String(lc)
      : langs.length
        ? String(langs.length)
        : null;

  const m = {
    hasAny: false,
    successMessage: firstNonEmpty(
      root.successMessage,
      pickFirst(root, "Success_Message", "SuccessMessage"),
      root.message,
      pickFirst(root, "Message"),
      root.processingSummary,
      root.summary
    ),
    statusBadge: firstNonEmpty(
      pickFirst(root, "Status_Badge", "StatusBadge"),
      root.statusBadge,
      root.badge,
      root.analysisStatus
    ),
    titleLine1:
      firstNonEmpty(
        pickFirst(root, "Title_Line_1", "TitleLine1"),
        root.titleLine1,
        root.headerLine1
      ) || "Audio",
    titleLine2:
      firstNonEmpty(
        pickFirst(root, "Title_Line_2", "TitleLine2"),
        root.titleLine2,
        root.headerLine2,
        root.headerAccent
      ) || "Analytics",
    originalText: firstNonEmpty(
      pickFirst(
        root,
        "originalText",
        "original_input",
        "originalInput",
        "Original_Input",
        "OriginalInput"
      ),
      root.originalTranscript,
      pickFirst(root, "transcript", "Transcript", "rawText", "Raw_Text"),
      root.transcript,
      root.original,
      root.rawText
    ),
    languages: langs,
    languagesCount,
    sentimentLabel: sBlock.label,
    sentimentMeter: sBlock.meter,
    tonalityLabel: tBlock.label,
    tonalityMeter: tBlock.meter,
    translation: firstNonEmpty(
      pickFirst(
        root,
        "translation",
        "englishTranslation",
        "translatedText",
        "English_Translation",
        "EnglishTranslation"
      ),
      root.translation,
      root.englishTranslation,
      root.translatedText,
      pickFirst(root, "Transcript_EN", "English_Text"),
      root.englishText
    ),
    entities: normalizeEntities(root)
  };
  m.hasAny = Boolean(
    m.successMessage ||
      m.statusBadge ||
      m.originalText ||
      m.languages.length ||
      m.translation ||
      m.entities.length ||
      m.sentimentLabel != null ||
      m.tonalityLabel != null ||
      m.sentimentMeter != null ||
      m.tonalityMeter != null
  );
  return m;
}