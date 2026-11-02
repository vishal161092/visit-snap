import { LightningElement, api, track } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import getConflictForAccount from '@salesforce/apex/de_CaseConflictService.getConflictForAccount';

/**
 * Account (client) record page — account-scoped conflict check.
 */
export default class de_CaseAccountConflict extends NavigationMixin(
  LightningElement
) {
  @api recordId;
  @track _result;
  @track _rows = [];
  loading;
  _lastKey;
  _refreshedLabel = '—';

  get panelTitle() {
    return 'Client Conflict';
  }

  get effectiveId() {
    return this.recordId ? String(this.recordId).trim() : null;
  }

  get showMissingId() {
    return !this.effectiveId;
  }

  get missingHelp() {
    return 'Add this component to a Client (Account) record page so the Account Id is available.';
  }

  get panelMetaLine() {
    if (this.showMissingId) {
      return 'Record Id required';
    }
    if (this.loading) {
      return 'Loading…';
    }
    if (this._result == null) {
      return 'de conflict check';
    }
    if (this.isError) {
      return 'Error';
    }
    if (this.hasConflict) {
      const n = (this._rows && this._rows.length) || 0;
      const t = this.conflictTypeCount;
      return `${n} conflict${n === 1 ? '' : 's'} · ${t} conflict type${
        t === 1 ? '' : 's'
      } · ${this._refreshedLabel}`;
    }
    return 'No business conflicts in scope';
  }

  get conflictTypeCount() {
    let c = 0;
    if (this.type1Rows.length) {
      c += 1;
    }
    if (this.type2Rows.length) {
      c += 1;
    }
    return c;
  }

  get type1Rows() {
    return (this._rows || []).filter((r) => r && this._isType1(r));
  }

  get type2Rows() {
    return (this._rows || []).filter((r) => r && this._isType2(r));
  }

  get hasType1Block() {
    return this.type1Rows.length > 0;
  }

  get hasType2Block() {
    return this.type2Rows.length > 0;
  }

  get type2SectionClass() {
    return this.hasType1Block
      ? 'decp-block subsequent'
      : 'decp-block';
  }

  get type1Count() {
    return this.type1Rows.length;
  }

  get type2Count() {
    return this.type2Rows.length;
  }

  get type1ForView() {
    return this._decorateRows(this.type1Rows);
  }

  get type2ForView() {
    return this._decorateRows(this.type2Rows);
  }

  _isType1(r) {
    const t = (r.typeLabel || '').toLowerCase();
    return t.includes('type 1') || t.includes('same client');
  }

  _isType2(r) {
    const t = (r.typeLabel || '').toLowerCase();
    return t.includes('type 2') || t.includes('cross-party');
  }

  _decorateRows(list) {
    return (list || []).map((r) => {
      const partner = r.otherPartnerName || r.ownerName || '—';
      const forId = r.forCaseId;
      return {
        key: `${forId || 'x'}-${r.caseId}`,
        otherCaseId: r.caseId,
        caseNumber: r.caseNumber || '—',
        subject: r.subject || '—',
        otherPartnerName: partner,
        detailHtml: this._formatDetail(
          r.detail
        ),
        initials: this._initials(
          partner
        ),
        forCaseId: forId,
        forCaseNumber: r.forCaseNumber || '—',
        forCaseSubject:
          r.forCaseSubject != null &&
          String(r.forCaseSubject).trim() !== ''
            ? r.forCaseSubject
            : '',
        showForCase: Boolean(forId),
        clientName: r.clientName != null && String(r.clientName).trim() !== '' ? r.clientName : '—'
      };
    });
  }

  _formatDetail(
    s
  ) {
    return (s || '')
      .replace(
        /\*\*([^*]+?)\*\*/g,
        '<b>$1</b>'
      );
  }

  _initials(name) {
    if (!name || typeof name !== 'string') {
      return '?';
    }
    const p = name
      .trim()
      .split(/\s+/)
      .filter(Boolean);
    if (p.length === 0) {
      return '?';
    }
    if (p.length === 1) {
      return p[0].substring(0, 2).toUpperCase();
    }
    return (p[0][0] + p[p.length - 1][0]).toUpperCase();
  }

  get richMessage() {
    const m = (this._result && this._result.message) || '';
    return m
      .replace(/\*\*([^*]+?)\*\*/g, '<b>$1</b>')
      .split('\n')
      .map((line) => `${line}<br/>`)
      .join('');
  }

  get contextStripHtml() {
    if (!this.hasConflict) {
      return '';
    }
    return this.richMessage;
  }

  get contextStripHtmlNoConflict() {
    if (!this._result || this.isError || this.hasConflict) {
      return '';
    }
    return this.richMessage;
  }

  get isError() {
    return this._result && this._result.conflictType === 'ERROR';
  }

  get hasConflict() {
    return this._result && this._result.hasConflict === true;
  }

  get showSuccessState() {
    return (
      this._result && !this.isError && this._result.hasConflict === false
    );
  }

  get showEmptyState() {
    return !this.loading && this._result == null && !this.showMissingId;
  }

  get refreshDisabled() {
    if (this.loading) {
      return true;
    }
    return !this.effectiveId;
  }

  handleRefresh() {
    this._load();
  }

  handleDismiss() {
    this.dispatchEvent(
      new CustomEvent('dedismiss', { bubbles: true, composed: true })
    );
  }

  handleProceed() {
    this.dispatchEvent(
      new CustomEvent('deproceed', { bubbles: true, composed: true })
    );
  }

  handleOpenCase(event) {
    const id = event.currentTarget && event.currentTarget.dataset.caseid;
    if (!id) {
      return;
    }
    this[NavigationMixin.Navigate]({
      type: 'standard__recordPage',
      attributes: {
        recordId: id,
        objectApiName: 'Case',
        actionName: 'view'
      }
    });
  }

  renderedCallback() {
    const k = `ACCOUNT|${this.effectiveId || ''}`;
    if (k === this._lastKey) {
      return;
    }
    this._lastKey = k;
    this._load();
  }

  _load() {
    if (!this.effectiveId) {
      this._result = null;
      this._rows = [];
      return;
    }
    this.loading = true;
    getConflictForAccount({ accountId: this.effectiveId })
      .then((r) => {
        this._result = r;
        this._rows = (r && r.rows) || [];
        this._refreshedLabel = 'Refreshed just now';
      })
      .catch((e) => {
        this._result = {
          hasConflict: false,
          conflictType: 'ERROR',
          message: e && e.body && e.body.message ? e.body.message : 'Unknown',
          rows: []
        };
        this._rows = [];
        this._refreshedLabel = '—';
      })
      .finally(() => {
        this.loading = false;
      });
  }
}