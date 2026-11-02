import { LightningElement, api } from "lwc";
import { FlowNavigationNextEvent } from "lightning/flowSupport";

const DEF_MSG = "Your notes have been processed.";
const DEF_TITLE = "All set";
const DEF_GRAD = "Complete";

export default class DeFlowFinished extends LightningElement {
  /** Injected in Screen Flow */
  @api availableActions;

  @api message;
  @api titleText;
  @api titleGrad;
  @api badge;
  @api subtext;

  get displayMessage() {
    const m = this.message && String(this.message).trim();
    return m || DEF_MSG;
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
    return !a.some((x) => String(x).toUpperCase() === "NEXT");
  }

  handleFlowNext() {
    if (this.flowNextDisabled) {
      return;
    }
    this.dispatchEvent(new FlowNavigationNextEvent());
  }
}