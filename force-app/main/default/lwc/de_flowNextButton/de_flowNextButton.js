import { LightningElement, api } from "lwc";
import { FlowNavigationNextEvent } from "lightning/flowSupport";

export default class DeFlowNextButton extends LightningElement {
  @api availableActions = [];

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