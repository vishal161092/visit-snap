import { LightningElement, api } from "lwc";
import {
  FlowNavigationNextEvent,
  FlowAttributeChangeEvent
} from "lightning/flowSupport";
import saveVisitingCardImage from "@salesforce/apex/de_Image_Capture_Service.saveVisitingCardImage";
import searchAccountsByName from "@salesforce/apex/de_Image_Capture_Service.searchAccountsByName";

const DEF_TITLE = "Capture Visiting Cards";
const DEF_GRAD = "";
const DEF_HINT =
  "Upload a clear photo to capture all the POCs for your Client.";
const MAX_BYTES = 12 * 1024 * 1024;

export default class DeImageCapture extends LightningElement {
  @api availableActions;

  @api recordId;
  @api defaultAccountId;
  @api titleText;
  @api titleGrad;
  @api hintText;
  @api fileTitle;
  @api requireUploadBeforeNext;

  _contentDocId;
  _accountId;
  _accountSearchTerm = "";
  _accountOptions = [];
  _accountSearchLoading = false;
  _accountSearchError = "";
  _pastedAccountId = "";
  _uploading = false;
  _error;
  _fileName;
  _previewUrl;

  /**
   * ContentDocument Id of the uploaded file (output to Flow).
   * Getter + setter are required so the Flow runtime can bind this output;
   * after upload, dispatch FlowAttributeChangeEvent so mapped variables update.
   */
  @api
  get contentDocId() {
    return this._contentDocId == null || this._contentDocId === ""
      ? ""
      : String(this._contentDocId);
  }

  set contentDocId(value) {
    if (value == null || value === "") {
      this._contentDocId = undefined;
    } else {
      this._contentDocId = String(value);
    }
  }

  /**
   * Account Id chosen in the record picker (output to Flow).
   */
  @api
  get accountId() {
    return this._accountId == null || this._accountId === ""
      ? ""
      : String(this._accountId);
  }

  set accountId(value) {
    if (value == null || value === "") {
      this._accountId = undefined;
      this._pastedAccountId = "";
    } else {
      this._accountId = String(value);
      this._pastedAccountId = this._accountId;
    }
  }

  get pickerAccountValue() {
    return this._accountId || undefined;
  }

  get accountSearchTerm() {
    return this._accountSearchTerm;
  }

  get accountOptions() {
    return this._accountOptions;
  }

  get hasAccountOptions() {
    return this._accountOptions.length > 0;
  }

  get accountSearchLoading() {
    return this._accountSearchLoading;
  }

  get showAccountSearchError() {
    return Boolean(this._accountSearchError);
  }

  get accountSearchError() {
    return this._accountSearchError || "";
  }

  get pastedAccountId() {
    return this._pastedAccountId || "";
  }

  get displayTitle() {
    const t = this.titleText && String(this.titleText).trim();
    return t || DEF_TITLE;
  }

  get displayTitleGrad() {
    const t = this.titleGrad && String(this.titleGrad).trim();
    return t || DEF_GRAD;
  }

  get displayHint() {
    const h = this.hintText && String(this.hintText).trim();
    return h || DEF_HINT;
  }

  get showError() {
    return Boolean(this._error);
  }

  get errorMessage() {
    return this._error || "";
  }

  get showFlowNext() {
    return Array.isArray(this.availableActions);
  }

  get flowNextDisabled() {
    const a = this.availableActions;
    if (a && a.length && !a.includes("NEXT")) {
      return true;
    }
    const skip =
      this.requireUploadBeforeNext === false ||
      this.requireUploadBeforeNext === "false";
    if (skip) {
      return false;
    }
    return !this._contentDocId;
  }

  get uploading() {
    return this._uploading;
  }

  get hasFile() {
    return Boolean(this._contentDocId);
  }

  get successLine() {
    return this._contentDocId
      ? `Saved as file. Content Document Id is available to the Flow.`
      : "";
  }

  get displayFileName() {
    return this._fileName || "";
  }

  get showPreview() {
    return Boolean(this._previewUrl);
  }

  get previewStyle() {
    return this._previewUrl ? `background-image: url(${this._previewUrl})` : "";
  }

  _emitContentDocId() {
    const v = this.contentDocId;
    this.dispatchEvent(new FlowAttributeChangeEvent("contentDocId", v));
  }

  _emitAccountId() {
    const v = this.accountId;
    this.dispatchEvent(new FlowAttributeChangeEvent("accountId", v));
  }

  connectedCallback() {
    const d = this.defaultAccountId && String(this.defaultAccountId).trim();
    if (d && d.length >= 15) {
      this.accountId = d;
      this._pastedAccountId = d;
    }
    this._emitContentDocId();
    this._emitAccountId();
  }

  handleAccountSearchInput(event) {
    this._accountSearchTerm = event.target.value;
  }

  handleAccountSearchClick() {
    this._accountSearchError = "";
    const t = (this._accountSearchTerm || "").trim();
    if (t.length < 2) {
      this._accountOptions = [];
      this._accountSearchError = "Enter at least 2 characters to search.";
      return;
    }
    this._accountSearchLoading = true;
    searchAccountsByName({ searchTerm: t, limitSize: 10 })
      .then((rows) => {
        this._accountOptions = Array.isArray(rows)
          ? rows.map((r) => ({ label: r.label, value: r.value }))
          : [];
        if (!this._accountOptions.length) {
          this._accountSearchError =
            "No Accounts matched. Try different text or paste an Id below.";
        }
      })
      .catch((e) => {
        this._accountOptions = [];
        this._accountSearchError = this._reduceError(e) || "Account search failed.";
      })
      .finally(() => {
        this._accountSearchLoading = false;
      });
  }

  handleAccountComboChange(event) {
    this._accountSearchError = "";
    const v = event.detail.value;
    this.accountId = v || "";
    this._pastedAccountId = this.accountId || "";
    this._emitAccountId();
  }

  handlePastedAccountIdChange(event) {
    this._pastedAccountId = event.target.value;
  }

  handlePastedAccountIdBlur() {
    this._accountSearchError = "";
    const t = (this._pastedAccountId || "").trim();
    if (t.length === 0) {
      this.accountId = "";
      this._emitAccountId();
      return;
    }
    if (t.length < 15) {
      return;
    }
    this.accountId = t;
    this._emitAccountId();
  }

  handleFlowNext() {
    if (this.flowNextDisabled) {
      return;
    }
    this.dispatchEvent(new FlowNavigationNextEvent());
  }

  handlePickClick() {
    const input = this.template.querySelector('[data-dic="file"]');
    if (input) {
      input.click();
    }
  }

  handleFileChange(event) {
    const input = event.target;
    const file = input.files && input.files[0];
    input.value = "";
    if (!file) {
      return;
    }

    this._error = undefined;
    if (!file.type || !file.type.startsWith("image/")) {
      this._error = "Please choose an image file (PNG, JPEG, or similar).";
      return;
    }
    if (file.size > MAX_BYTES) {
      this._error = `File is too large. Maximum size is ${Math.floor(MAX_BYTES / (1024 * 1024))} MB.`;
      return;
    }

    this._fileName = file.name;
    this._uploading = true;

    const reader = new FileReader();
    reader.onerror = () => {
      this._uploading = false;
      this._error = "Could not read the file. Try again.";
    };
    reader.onload = () => {
      const dataUrl = reader.result;
      const base64 =
        typeof dataUrl === "string" ? dataUrl : "";
      const titleFromFlow =
        this.fileTitle && String(this.fileTitle).trim();
      const title = titleFromFlow || file.name || "Visiting cards capture";
      const rid = this._normalizedRecordId();

      saveVisitingCardImage({
        base64,
        pathOnClient: file.name,
        title,
        recordId: rid
      })
        .then((docId) => {
          this.contentDocId = docId ? String(docId) : "";
          this._previewUrl =
            typeof dataUrl === "string" ? dataUrl : undefined;
          this._emitContentDocId();
        })
        .catch((e) => {
          this.contentDocId = "";
          this._previewUrl = undefined;
          this._emitContentDocId();
          this._error = this._reduceError(e);
        })
        .finally(() => {
          this._uploading = false;
        });
    };
    reader.readAsDataURL(file);
  }

  _normalizedRecordId() {
    const r = this.recordId && String(this.recordId).trim();
    if (!r || r.length < 15) {
      return null;
    }
    return r;
  }

  _reduceError(error) {
    if (!error) {
      return "Upload failed.";
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
    return "Upload failed.";
  }
}