import { LightningElement, api, wire } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getResearchAreaOptions from '@salesforce/apex/de_dummy_Account_Research_Apex.getResearchAreaOptions';
import generateResearch from '@salesforce/apex/de_dummy_Account_Research_Apex.generateResearch';

const PREVIEW_MAX = 220;

/** Rotate neutral “research / data” utility icons (no hot pink badges). */
const SOURCE_ICON_CYCLE = [
  'utility:knowledge_base',
  'utility:chart',
  'utility:table',
  'utility:description',
  'utility:case',
  'utility:link'
];

export default class DeDummyAccountResearch extends LightningElement {
  @api recordId;

  researchAreaOptions = [];
  researchAreaValue = '';

  researchedMeta = '';
  overviewHtml =
    '<p>Select a research area and click <strong>Research</strong> to generate live account intelligence.</p>';

  coachingSectionTitle = 'Related insights';
  coachingPreview = '';
  coachingFull = '';

  sources = [];
  coachingExpanded = false;
  sourcesExpanded = true;
  feedback = '';
  isResearching = false;

  @wire(getResearchAreaOptions)
  wiredAreas({ data, error }) {
    if (data && data.length) {
      this.researchAreaOptions = data;
      const stillValid = data.some((o) => o.value === this.researchAreaValue);
      if (!this.researchAreaValue || !stillValid) {
        this.researchAreaValue = data[0].value;
      }
    } else if (error) {
      this.dispatchEvent(
        new ShowToastEvent({
          title: 'Could not load research areas',
          message: this.reduceError(error),
          variant: 'error'
        })
      );
    }
  }

  get sourcesCountLabel() {
    const n = (this.sources && this.sources.length) || 0;
    return `Sources (${n})`;
  }

  get coachingBody() {
    return this.coachingExpanded ? this.coachingFull : this.coachingPreview;
  }

  get expandLabel() {
    return this.coachingExpanded ? 'Collapse' : 'Expand';
  }

  get sourcesSectionClass() {
    return (
      'de-ar-sources__panel slds-m-top_x-small' +
      (this.sourcesExpanded ? '' : ' slds-hide')
    );
  }

  get sourcesChevronIcon() {
    return this.sourcesExpanded ? 'utility:chevrondown' : 'utility:chevronright';
  }

  get researchDisabled() {
    return this.isResearching || !this.recordId || !this.researchAreaValue;
  }

  handleResearchAreaChange(event) {
    this.researchAreaValue = event.detail.value;
  }

  handleResearch() {
    if (!this.recordId) {
      this.dispatchEvent(
        new ShowToastEvent({
          title: 'Account required',
          message: 'Open this component on an Account record page.',
          variant: 'warning'
        })
      );
      return;
    }
    this.isResearching = true;
    generateResearch({
      accountId: this.recordId,
      researchAreaKey: this.researchAreaValue
    })
      .then((result) => {
        if (!result || !result.success) {
          this.dispatchEvent(
            new ShowToastEvent({
              title: 'Research failed',
              message:
                (result && result.errorMessage) ||
                'No response from the server.',
              variant: 'error'
            })
          );
          return;
        }
        this.researchedMeta = result.researchedMeta || '';
        this.overviewHtml =
          result.overviewHtml ||
          '<p>No overview was returned.</p>';
        this.coachingSectionTitle =
          result.coachingSectionTitle || 'Related insights';
        this.coachingFull = result.coachingBody || '';
        this.coachingPreview = this.buildPreview(this.coachingFull);
        this.coachingExpanded = false;
        this.sources = this.decorateSources(result.sources);
        this.sourcesExpanded = true;
      })
      .catch((error) => {
        this.dispatchEvent(
          new ShowToastEvent({
            title: 'Research failed',
            message: this.reduceError(error),
            variant: 'error'
          })
        );
      })
      .finally(() => {
        this.isResearching = false;
      });
  }

  decorateSources(list) {
    if (!Array.isArray(list) || !list.length) {
      return [];
    }
    return list.map((s, i) => ({
      id: s.id,
      title: s.title,
      url: s.url,
      iconName: SOURCE_ICON_CYCLE[i % SOURCE_ICON_CYCLE.length]
    }));
  }

  buildPreview(full) {
    const t = (full || '').trim();
    if (!t) {
      return '';
    }
    if (t.length <= PREVIEW_MAX) {
      return t;
    }
    return t.slice(0, PREVIEW_MAX).trimEnd() + '...';
  }

  reduceError(error) {
    if (!error) {
      return 'Unknown error';
    }
    if (Array.isArray(error.body)) {
      return error.body.map((e) => e.message).join(', ');
    }
    if (error.body && error.body.message) {
      return error.body.message;
    }
    return error.message || String(error);
  }

  handleInfo() {
    this.dispatchEvent(
      new ShowToastEvent({
        title: 'Account Research',
        message:
          'Pick a research area (sources are guided per topic), then Research to call the Models API and refresh this panel.',
        variant: 'info'
      })
    );
  }

  handleEditOverview() {
    this.dispatchEvent(
      new ShowToastEvent({
        title: 'Edit',
        message: 'Wire your own flow or modal to edit and save overview HTML.',
        variant: 'info'
      })
    );
  }

  handleToggleExpand() {
    this.coachingExpanded = !this.coachingExpanded;
  }

  handleToggleSources() {
    this.sourcesExpanded = !this.sourcesExpanded;
  }

  handleFeedback(event) {
    const value = event.currentTarget.dataset.value;
    this.feedback = this.feedback === value ? '' : value;
  }

  handleAddResults() {
    this.dispatchEvent(
      new ShowToastEvent({
        title: 'Add Results to Account',
        message: 'Persist generated fields with your own Apex or Flow.',
        variant: 'success'
      })
    );
  }

  get thumbsUpVariant() {
    return this.feedback === 'up' ? 'brand' : 'neutral';
  }

  get thumbsDownVariant() {
    return this.feedback === 'down' ? 'brand' : 'neutral';
  }
}