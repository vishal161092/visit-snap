import { LightningElement, api, track } from "lwc";
import { ShowToastEvent } from "lightning/platformShowToastEvent";
import {
  FlowAttributeChangeEvent,
  FlowNavigationNextEvent
} from "lightning/flowSupport";
import saveAudioToRecord from "@salesforce/apex/de_Voice_Recording_Service.saveAudioToRecord";

const MIME_CANDIDATES = [
  "audio/webm;codecs=opus",
  "audio/webm",
  "audio/ogg;codecs=opus",
  "audio/mp4"
];

const WAVE_COUNT = 32;

function pickRecorderMimeType() {
  for (const t of MIME_CANDIDATES) {
    if (window.MediaRecorder && MediaRecorder.isTypeSupported(t)) {
      return t;
    }
  }
  return "";
}

function blobToBase64(blob) {
  return new Promise((resolve, reject) => {
    const reader = new FileReader();
    reader.onloadend = () => {
      const dataUrl = reader.result;
      if (typeof dataUrl !== "string" || !dataUrl.includes(",")) {
        reject(new Error("Could not read audio as base64."));
        return;
      }
      resolve(dataUrl.split(",")[1]);
    };
    reader.onerror = () => reject(reader.error);
    reader.readAsDataURL(blob);
  });
}

function extensionForMimeType(mimeType) {
  const m = (mimeType || "").toLowerCase();
  if (m.includes("webm")) {
    return "webm";
  }
  if (m.includes("ogg")) {
    return "ogg";
  }
  if (m.includes("mp4") || m.includes("mpeg")) {
    return "m4a";
  }
  return "webm";
}

function buildAudioFileName(mimeType) {
  const ext = extensionForMimeType(mimeType);
  const stamp = new Date().toISOString().replace(/[:.]/g, "-");
  return `voice_recording_${stamp}.${ext}`;
}

function buildAudioTitle() {
  return `Voice recording ${new Date().toLocaleString()}`;
}

function messageFromApexError(error) {
  if (Array.isArray(error?.body) && error.body[0]) {
    return error.body[0].message;
  }
  if (error?.body && typeof error.body.message === "string") {
    return error.body.message;
  }
  if (typeof error?.message === "string") {
    return error.message;
  }
  return "Could not save the recording.";
}

function shortFormatLabel(mime) {
  const m = (mime || "").toLowerCase();
  if (m.includes("webm")) {
    return "WebM";
  }
  if (m.includes("ogg")) {
    return "Ogg";
  }
  if (m.includes("mp4")) {
    return "M4A";
  }
  return "Audio";
}

function buildIdleWave() {
  return Array.from({ length: WAVE_COUNT }, (_, i) => ({
    id: `w${i}`,
    h: 4,
    active: false,
    barClass: "de-vo-wv-bar",
    barStyle: "height: 4px; min-height: 2px"
  }));
}

function formatTime(totalSeconds) {
  const s = Math.max(0, Math.floor(totalSeconds || 0));
  const mm = String(Math.floor(s / 60)).padStart(2, "0");
  const ss = String(s % 60).padStart(2, "0");
  return `${mm}:${ss}`;
}

export default class DeRealtimeVoiceAnlysis extends LightningElement {
  @api recordId;
  @api contentDocumentId;
  @api availableActions = [];

  @track isRecording = false;
  @track isSaving = false;
  @track statusMessage = "Press Start, then speak. Press Stop when you are done.";

  @track timerText = "00:00";
  @track recLabel = "STANDBY";
  @track metaDuration = "—";
  @track metaStatus = "Idle";
  @track metaFormat = "—";
  @track metaFormatAccent = false;
  @track metaStatusAccent = false;
  @track metaQuality = "—";
  @track qualityAccent = false;

  @track waveBarItems = buildIdleWave();

  _stream;
  _mediaRecorder;
  _chunks = [];
  _mimeType = "";
  _seconds = 0;
  _timerInterval;
  _waveInterval;

  connectedCallback() {
    this._initWaveIdle();
  }

  _initWaveIdle() {
    this.waveBarItems = buildIdleWave();
  }

  _startTimer() {
    this._clearTimer();
    this._seconds = 0;
    this.timerText = "00:00";
    this.metaDuration = "00:00";
    this._timerInterval = window.setInterval(() => {
      this._seconds += 1;
      this.timerText = formatTime(this._seconds);
      this.metaDuration = this.timerText;
    }, 1000);
  }

  _clearTimer() {
    if (this._timerInterval) {
      window.clearInterval(this._timerInterval);
      this._timerInterval = undefined;
    }
  }

  _startWaveAnim() {
    this._clearWaveAnim();
    this._waveInterval = window.setInterval(() => {
      this.waveBarItems = this.waveBarItems.map((row) => {
        const h = 4 + Math.floor(Math.random() * 38);
        const hot = h > 22;
        return {
          id: row.id,
          h,
          active: hot,
          barClass: "de-vo-wv-bar" + (hot ? " de-vo-wvHot" : ""),
          barStyle: `height: ${h}px; min-height: 2px;`
        };
      });
    }, 80);
  }

  _clearWaveAnim() {
    if (this._waveInterval) {
      window.clearInterval(this._waveInterval);
      this._waveInterval = undefined;
    }
  }

  _stopTimerAndWave() {
    this._clearTimer();
    this._clearWaveAnim();
    this._initWaveIdle();
  }

  _notifyContentDocumentId(value) {
    const s = value == null ? "" : String(value);
    this.contentDocumentId = s;
    this.dispatchEvent(new FlowAttributeChangeEvent("contentDocumentId", s));
  }

  disconnectedCallback() {
    this._stopTimerAndWave();
    this._releaseMicrophone();
  }

  get startDisabled() {
    return this.isRecording || this.isSaving;
  }

  get stopDisabled() {
    return !this.isRecording || this.isSaving;
  }

  get classStop() {
    return "de-vo-btn de-vo-btn-stop" + (this.isRecording ? " de-vo-stopOn" : "");
  }

  get classRecDot() {
    return "de-vo-rec-dot" + (this.isRecording ? " de-vo-recDotOn" : "");
  }

  get classRecTxt() {
    return "de-vo-rec-txt" + (this.isRecording ? " de-vo-recTxtOn" : "");
  }

  get classStatus() {
    return "de-vo-status" + (this.isRecording ? " de-vo-statusRec" : "");
  }

  get mvalStatus() {
    return "de-vo-mval de-vo-mono" + (this.metaStatusAccent ? " de-vo-mvalPop" : "");
  }

  get mvalQuality() {
    return "de-vo-mval de-vo-mono" + (this.qualityAccent ? " de-vo-mvalPop" : "");
  }

  get mvalFormat() {
    return "de-vo-mval de-vo-mono" + (this.metaFormatAccent ? " de-vo-mvalPop" : "");
  }

  /** Same-org download URL for the stored file (contentDocumentId from save / Flow output). */
  get filePlaybackUrl() {
    const id = this.contentDocumentId;
    if (!id || !String(id).trim()) {
      return "";
    }
    return (
      window.location.origin +
      "/sfc/servlet.shepherd/document/download/" +
      String(id)
    );
  }

  get showPlayback() {
    return Boolean(this.contentDocumentId && String(this.contentDocumentId).trim());
  }

  get flowNextDisabled() {
    const a = this.availableActions;
    return Boolean(
      a &&
        a.length > 0 &&
        !a.some((x) => String(x).toUpperCase() === "NEXT")
    );
  }

  handleFlowNext() {
    if (this.flowNextDisabled) {
      return;
    }
    this.dispatchEvent(new FlowNavigationNextEvent());
  }

  handleStart = async () => {
    this._notifyContentDocumentId("");
    this._stopTimerAndWave();
    this.statusMessage = "Requesting microphone access…";
    this.recLabel = "STANDBY";
    this.metaStatus = "Requesting";
    this.metaStatusAccent = false;
    this.metaFormat = "—";
    this.metaFormatAccent = false;
    this.metaDuration = "—";
    this.metaQuality = "—";
    this.qualityAccent = false;
    this.timerText = "00:00";

    try {
      this._stream = await navigator.mediaDevices.getUserMedia({
        audio: {
          echoCancellation: true,
          noiseSuppression: true
        }
      });
    } catch (e) {
      this.statusMessage =
        "Microphone access was denied or unavailable. Allow access and try again.";
      this.metaStatus = "Blocked";
      // eslint-disable-next-line no-console
      console.error("getUserMedia failed", e);
      return;
    }

    this._mimeType = pickRecorderMimeType();
    const options = this._mimeType ? { mimeType: this._mimeType } : undefined;

    try {
      this._mediaRecorder = new MediaRecorder(this._stream, options);
    } catch (e) {
      this._releaseMicrophone();
      this.statusMessage = "Could not start audio recorder on this device.";
      this.metaStatus = "Error";
      // eslint-disable-next-line no-console
      console.error("MediaRecorder constructor failed", e);
      return;
    }

    this._chunks = [];
    this._mediaRecorder.addEventListener("dataavailable", (ev) => {
      if (ev.data && ev.data.size > 0) {
        this._chunks.push(ev.data);
      }
    });

    this._mediaRecorder.addEventListener("stop", () => {
      const type =
        this._mediaRecorder && this._mediaRecorder.mimeType
          ? this._mediaRecorder.mimeType
          : this._mimeType || "audio/webm";
      const blob = new Blob(this._chunks, { type });
      this._chunks = [];
      this._releaseMicrophone();
      this._processRecording(blob, type);
    });

    this._mediaRecorder.addEventListener("error", (ev) => {
      this.statusMessage = "Recording error.";
      this._stopTimerAndWave();
      this._releaseMicrophone();
      this.metaStatus = "Error";
      this.recLabel = "ERROR";
      // eslint-disable-next-line no-console
      console.error("MediaRecorder error", ev.error);
    });

    this._mediaRecorder.start(250);
    this.isRecording = true;
    this.statusMessage = "Recording in progress…";
    this.recLabel = "REC";
    this.metaStatus = "Recording";
    this.metaStatusAccent = true;
    this.metaFormat = this._mimeType
      ? shortFormatLabel(this._mimeType)
      : "—";
    this.metaFormatAccent = true;
    this.metaQuality = "In-browser";
    this.qualityAccent = true;
    this._startTimer();
    this._startWaveAnim();
  };

  handleStop = () => {
    if (!this._mediaRecorder || this._mediaRecorder.state === "inactive") {
      this.isRecording = false;
      return;
    }
    this.statusMessage = "Processing…";
    this._clearTimer();
    this._clearWaveAnim();
    this._initWaveIdle();
    this.recLabel = "STOPPED";
    this.isRecording = false;
    this.metaStatus = "Processing";
    this.metaStatusAccent = false;
    this._mediaRecorder.stop();
  };

  async _processRecording(blob, mimeType) {
    try {
      const base64 = await blobToBase64(blob);
      this.metaFormat = shortFormatLabel(mimeType);
      this.metaFormatAccent = true;
      this.dispatchEvent(
        new CustomEvent("audiocaptured", {
          detail: {
            mimeType,
            size: blob.size
          },
          bubbles: true,
          composed: true
        })
      );

      if (this.recordId) {
        this.isSaving = true;
        this.statusMessage = "Saving to contact…";
        this.metaStatus = "Saving";
        this.metaStatusAccent = true;
        try {
          const docId = await saveAudioToRecord({
            recordId: this.recordId,
            base64,
            pathOnClient: buildAudioFileName(mimeType),
            title: buildAudioTitle()
          });
          this._notifyContentDocumentId(String(docId));
          this.statusMessage =
            "Your Audio file has been generated Successfully. Use the player below to listen back, or Start to record again.";
          this.recLabel = "SAVED";
          this.metaStatus = "Saved";
          this.metaStatusAccent = true;
          this.dispatchEvent(
            new ShowToastEvent({
              title: "Recording saved",
              message: "The audio was added to the contact's files.",
              variant: "success"
            })
          );
          this.dispatchEvent(
            new CustomEvent("recordingfilecreated", {
              detail: { contentDocumentId: String(docId) },
              bubbles: true,
              composed: true
            })
          );
        } catch (e) {
          this._notifyContentDocumentId("");
          this.statusMessage = `Save failed. ${messageFromApexError(e)}`;
          this.recLabel = "ERROR";
          this.metaStatus = "Error";
          this.metaStatusAccent = false;
          this.dispatchEvent(
            new ShowToastEvent({
              title: "Could not save to record",
              message: messageFromApexError(e),
              variant: "error",
              mode: "sticky"
            })
          );
        } finally {
          this.isSaving = false;
        }
      } else {
        this._notifyContentDocumentId("");
        this.statusMessage =
          "Set Contact record ID (Flow input or place on a Contact record page) to save the file.";
        this.recLabel = "READY";
        this.metaStatus = "Unsaved";
        this.metaStatusAccent = false;
      }
    } catch (e) {
      this._notifyContentDocumentId("");
      this.statusMessage = "Could not process the recording.";
      this.recLabel = "ERROR";
      this.metaStatus = "Error";
      // eslint-disable-next-line no-console
      console.error("process recording failed", e);
    } finally {
      this.isRecording = false;
    }
  }

  _releaseMicrophone() {
    if (this._stream) {
      this._stream.getTracks().forEach((t) => t.stop());
    }
    this._stream = undefined;
    this._mediaRecorder = undefined;
  }
}