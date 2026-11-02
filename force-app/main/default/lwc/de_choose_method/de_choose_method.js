import { LightningElement, api } from "lwc";
import {
  FlowNavigationNextEvent,
  FlowAttributeChangeEvent
} from "lightning/flowSupport";

const NOTES_METHOD_VOICE = "Voice";
const NOTES_METHOD_IMAGE = "Image";

const DEF_TITLE = "Capture Notes";
const DEF_GRAD = "";
const DEF_HINT =
  "Select Voice to record audio, or Image to upload a visiting-card photo.";

export default class DeChooseMethod extends LightningElement {
  @api availableActions;

  @api titleText;
  @api titleGrad;
  @api hintText;
  @api requireSelectionBeforeNext;

  _notesCaptureMethod;

  @api
  get notesCaptureMethod() {
    return this._notesCaptureMethod == null || this._notesCaptureMethod === ""
      ? ""
      : String(this._notesCaptureMethod);
  }

  set notesCaptureMethod(value) {
    // Output-only: Flow can re-invoke the setter with "". Do not clear a user selection.
    if (value == null || value === "") {
      return;
    }
    this._notesCaptureMethod = String(value).trim();
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

  get isVoiceSelected() {
    return this._notesCaptureMethod === NOTES_METHOD_VOICE;
  }

  get isImageSelected() {
    return this._notesCaptureMethod === NOTES_METHOD_IMAGE;
  }

  get voiceCardClass() {
    return `de-chm-card${this.isVoiceSelected ? " de-chm-card--on" : ""}`;
  }

  get imageCardClass() {
    return `de-chm-card${this.isImageSelected ? " de-chm-card--on" : ""}`;
  }

  get showFlowNext() {
    return Array.isArray(this.availableActions);
  }

  get flowNextDisabled() {
    const a = this.availableActions;
    if (Array.isArray(a) && a.length > 0) {
      const hasNext = a.some(
        (x) => String(x).toUpperCase() === "NEXT"
      );
      if (!hasNext) {
        return true;
      }
    }
    const skip =
      this.requireSelectionBeforeNext === false ||
      this.requireSelectionBeforeNext === "false";
    if (skip) {
      return false;
    }
    return !this._notesCaptureMethod;
  }

  connectedCallback() {
    this._emitNotesCaptureMethod();
  }

  _emitNotesCaptureMethod() {
    this.dispatchEvent(
      new FlowAttributeChangeEvent("notesCaptureMethod", this.notesCaptureMethod)
    );
  }

  handlePickVoice() {
    this._notesCaptureMethod = NOTES_METHOD_VOICE;
    this._emitNotesCaptureMethod();
  }

  handlePickImage() {
    this._notesCaptureMethod = NOTES_METHOD_IMAGE;
    this._emitNotesCaptureMethod();
  }

  handleFlowNext() {
    if (this.flowNextDisabled) {
      return;
    }
    this.dispatchEvent(new FlowNavigationNextEvent());
  }
}