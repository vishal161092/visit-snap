import { LightningElement, api } from "lwc";
import {
  FlowNavigationNextEvent,
  FlowAttributeChangeEvent
} from "lightning/flowSupport";
import saveVisitingCardImage from "@salesforce/apex/de_Image_Capture_Service.saveVisitingCardImage";

const DEF_TITLE = "Upload Notes";
const DEF_GRAD = "";
const DEF_HINT =
  "Upload a file for this contact’s POC notes (PDF, Word, images, etc.). The file is stored in Salesforce Files.";
const MAX_BYTES = 12 * 1024 * 1024;

const ALLOWED_PREFIXES = [
  "image/",
  "application/pdf",
  "application/msword",
  "application/vnd.openxmlformats-officedocument.wordprocessingml",
  "application/vnd.openxmlformats-officedocument.spreadsheetml",
  "text/plain"
];

export default class DeNotesUpload extends LightningElement {
  @api availableActions;

  @api recordId;
  @api titleText;
  @api titleGrad;
  @api hintText;
  @api fileTitle;
  @api requireUploadBeforeNext;

  _contentDocId;
  _uploading = false;
  _error;
  _fileName;
  _previewUrl;

  fileAccept =
    "image/*,.pdf,.doc,.docx,.xlsx,.xls,.txt,application/pdf,application/msword,application/vnd.openxmlformats-officedocument.*,text/plain";

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
    if (Array.isArray(a) && a.length > 0) {
      const hasNext = a.some((x) => String(x).toUpperCase() === "NEXT");
      if (!hasNext) {
        return true;
      }
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
      ? "File saved. Content Document Id is available to the Flow."
      : "";
  }

  get displayFileName() {
    return this._fileName || "";
  }

  get showPreview() {
    return Boolean(this._previewUrl && this._isImagePreview);
  }

  get previewStyle() {
    return this._previewUrl ? `background-image: url(${this._previewUrl})` : "";
  }

  _isImagePreview = false;

  _emitContentDocId() {
    this.dispatchEvent(
      new FlowAttributeChangeEvent("contentDocId", this.contentDocId)
    );
  }

  connectedCallback() {
    this._emitContentDocId();
  }

  handleFlowNext() {
    if (this.flowNextDisabled) {
      return;
    }
    this.dispatchEvent(new FlowNavigationNextEvent());
  }

  handlePickClick() {
    const input = this.template.querySelector('[data-dnu="file"]');
    if (input) {
      input.click();
    }
  }

  _isAllowedFile(file) {
    if (!file || !file.type) {
      return false;
    }
    const t = file.type.toLowerCase();
    return ALLOWED_PREFIXES.some((p) => t.startsWith(p) || t === p);
  }

  handleFileChange(event) {
    const input = event.target;
    const file = input.files && input.files[0];
    input.value = "";
    if (!file) {
      return;
    }

    this._error = undefined;
    if (!this._isAllowedFile(file)) {
      this._error =
        "Please choose a supported file (image, PDF, Word, Excel, or plain text).";
      return;
    }
    if (file.size > MAX_BYTES) {
      this._error = `File is too large. Maximum size is ${Math.floor(MAX_BYTES / (1024 * 1024))} MB.`;
      return;
    }

    this._fileName = file.name;
    this._uploading = true;
    this._isImagePreview = Boolean(file.type && file.type.startsWith("image/"));

    const reader = new FileReader();
    reader.onerror = () => {
      this._uploading = false;
      this._error = "Could not read the file. Try again.";
    };
    reader.onload = () => {
      const dataUrl = reader.result;
      const base64 = typeof dataUrl === "string" ? dataUrl : "";
      const titleFromFlow = this.fileTitle && String(this.fileTitle).trim();
      const title = titleFromFlow || file.name || "Notes upload";
      const rid = this._normalizedRecordId();

      saveVisitingCardImage({
        base64,
        pathOnClient: file.name,
        title,
        recordId: rid
      })
        .then((docId) => {
          this.contentDocId = docId ? String(docId) : "";
          if (this._isImagePreview && typeof dataUrl === "string") {
            this._previewUrl = dataUrl;
          } else {
            this._previewUrl = undefined;
          }
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