import { LightningElement, api } from "lwc";
import { FlowNavigationNextEvent } from "lightning/flowSupport";

const DEF_TITLE = "Client POCs Created";
const DEF_GRAD = "";
const DEF_CONFIRMATION =
  "All the POCs for the respective clients have been created.";
const DEF_CARD_LBL = "Confirmation";

export default class DePocClientConfirmation extends LightningElement {
  @api availableActions;

  @api titleText;
  @api titleGrad;
  @api badge;
  @api confirmationMessage;
  @api subtext;
  @api cardSectionLabel;

  get displayCardSectionLabel() {
    const l = this.cardSectionLabel && String(this.cardSectionLabel).trim();
    return l || DEF_CARD_LBL;
  }

  get displayTitle() {
    const t = this.titleText && String(this.titleText).trim();
    return t || DEF_TITLE;
  }

  get displayTitleGrad() {
    const t = this.titleGrad && String(this.titleGrad).trim();
    return t || DEF_GRAD;
  }

  get displayBadge() {
    const b = this.badge && String(this.badge).trim();
    return b || "";
  }

  get hasBadge() {
    return Boolean(this.displayBadge);
  }

  get displayConfirmation() {
    const m = this.confirmationMessage && String(this.confirmationMessage).trim();
    return m || DEF_CONFIRMATION;
  }

  get subtextLine() {
    return this.subtext && String(this.subtext).trim();
  }

  get hasSubtext() {
    return Boolean(this.subtextLine);
  }

  get showFlowNext() {
    return Array.isArray(this.availableActions);
  }

  get flowNextDisabled() {
    const a = this.availableActions;
    if (!a || !a.length) {
      return false;
    }
    return !a.includes("NEXT");
  }

  handleFlowNext() {
    if (this.flowNextDisabled) {
      return;
    }
    this.dispatchEvent(new FlowNavigationNextEvent());
  }
}