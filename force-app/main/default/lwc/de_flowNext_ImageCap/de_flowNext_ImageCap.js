import { LightningElement, api } from "lwc";
import { FlowNavigationNextEvent } from "lightning/flowSupport";

const DEF_TITLE = "Client POC notes";
const DEF_INTRO =
  "Capture Client POC's additional notes via either voice or image upload.";
const DEF_BTN = "Start";

export default class DeFlowNextImageCap extends LightningElement {
  @api availableActions = [];

  @api titleAccent;
  @api introText;
  @api buttonLabel;

  get displayTitleAccent() {
    const t = this.titleAccent && String(this.titleAccent).trim();
    return t || DEF_TITLE;
  }

  get displayIntro() {
    const i = this.introText && String(this.introText).trim();
    return i || DEF_INTRO;
  }

  get displayButtonLabel() {
    const b = this.buttonLabel && String(this.buttonLabel).trim();
    return b || DEF_BTN;
  }

  handleNext() {
    if (
      this.availableActions &&
      this.availableActions.length &&
      !this.availableActions.includes("NEXT")
    ) {
      return;
    }
    this.dispatchEvent(new FlowNavigationNextEvent());
  }
}