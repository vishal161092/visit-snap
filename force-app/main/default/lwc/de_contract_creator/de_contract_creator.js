import { LightningElement, api, wire, track } from 'lwc';
import { loadScript } from 'lightning/platformResourceLoader';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { getRecord, getFieldValue } from 'lightning/uiRecordApi';
import NAME_FIELD from '@salesforce/schema/Account.Name';
import savePdfToAccount from '@salesforce/apex/de_Contract_Pdf_Service.savePdfToAccount';
import jspdfUrl from '@salesforce/resourceUrl/de_jspdf';
import templateUrl from '@salesforce/resourceUrl/de_contract_template_demo';

const ACCOUNT_FIELDS = [NAME_FIELD];

export default class DeContractCreator extends LightningElement {
  @api recordId;

  @track form = {};
  @track step = 1;
  @track isLoading = true;
  @track isGenerating = false;
  @track loadError = '';
  /** Loaded JSON from Static Resource — must NOT be named `template` (shadows LWC this.template / querySelector). */
  @track contractTemplate = null;

  fields = [];
  signatures = [];
  jspdfReady = false;
  _drawState = null;

  @wire(getRecord, { recordId: '$recordId', fields: ACCOUNT_FIELDS })
  wiredAccount({ data }) {
    if (!data || !this.contractTemplate) {
      return;
    }
    const name = getFieldValue(data, NAME_FIELD);
    if (name && !this.form.CLIENT_LEGAL_NAME) {
      this.form = { ...this.form, CLIENT_LEGAL_NAME: name };
    }
  }

  connectedCallback() {
    this.loadError = '';
    loadScript(this, jspdfUrl)
      .then(() => {
        this.jspdfReady = true;
        return fetch(templateUrl);
      })
      .then((res) => {
        if (!res.ok) {
          throw new Error('Template HTTP ' + res.status);
        }
        return res.json();
      })
      .then((json) => {
        this.contractTemplate = json;
        this.fields = Array.isArray(json.fields) ? json.fields : [];
        this.signatures = Array.isArray(json.signatures) ? json.signatures : [];
        this.seedDefaults();
        this.isLoading = false;
      })
      .catch((e) => {
        this.isLoading = false;
        this.loadError =
          'Could not load de_contract_template_demo or de_jspdf. ' +
          this._errMessage(e);
      });
  }

  seedDefaults() {
    const d = new Date();
    const local = d.toLocaleDateString(undefined, {
      year: 'numeric',
      month: 'short',
      day: 'numeric'
    });
    this.form = {
      ...this.form,
      EFFECTIVE_DATE: this.form.EFFECTIVE_DATE || local,
      GOVERNING_LAW: this.form.GOVERNING_LAW || 'State / province shown on Client address (demo)',
      FEE_SUMMARY: this.form.FEE_SUMMARY || 'Time and materials at agreed rates (demo).'
    };
  }

  get templateName() {
    return (
      (this.contractTemplate && this.contractTemplate.templateName) || 'Contract'
    );
  }

  get progressStep() {
    return String(this.step);
  }

  get isStep1() {
    return this.step === 1;
  }

  get isStep2() {
    return this.step === 2;
  }

  get isStep3() {
    return this.step === 3;
  }

  get isBackDisabled() {
    return this.step === 1 || this.isGenerating;
  }

  /** Signature canvases must stay in the DOM (off-screen when not step 2) so PDF export can read them. */
  get signaturePanelClass() {
    return (
      'de-sig-panel' + (this.step === 2 ? '' : ' de-sig-panel--hidden')
    );
  }

  get fieldRows() {
    return (this.fields || []).map((f) => ({
      ...f,
      _value: this.form[f.key] ?? ''
    }));
  }

  get previewHtml() {
    return this.mergeBodyHtml();
  }

  handleFieldChange(event) {
    const key = event.target.dataset.key;
    if (!key) {
      return;
    }
    this.form = { ...this.form, [key]: event.target.value };
  }

  handleNext() {
    if (this.step === 1) {
      if (!this.validateStep1()) {
        return;
      }
      this.step = 2;
      return;
    }
    if (this.step === 2) {
      this.step = 3;
    }
  }

  handleBack() {
    if (this.step > 1 && !this.isGenerating) {
      this.step -= 1;
    }
  }

  validateStep1() {
    const missing = [];
    for (const f of this.fields) {
      if (f.required && !String(this.form[f.key] || '').trim()) {
        missing.push(f.label || f.key);
      }
    }
    if (missing.length) {
      this.dispatchEvent(
        new ShowToastEvent({
          title: 'Required fields',
          message: 'Please fill: ' + missing.join(', '),
          variant: 'warning'
        })
      );
      return false;
    }
    return true;
  }

  handlePointerDown(event) {
    if (!event.isPrimary) {
      return;
    }
    const canvas = event.target;
    try {
      canvas.setPointerCapture(event.pointerId);
    } catch (e) {
      /* ignore */
    }
    const rect = canvas.getBoundingClientRect();
    const ctx = canvas.getContext('2d');
    ctx.lineWidth = 2;
    ctx.strokeStyle = '#080808';
    ctx.lineCap = 'round';
    ctx.lineJoin = 'round';
    this._drawState = {
      canvas,
      ctx,
      lastX: event.clientX - rect.left,
      lastY: event.clientY - rect.top
    };
  }

  handlePointerMove(event) {
    if (!this._drawState) {
      return;
    }
    const { canvas, ctx } = this._drawState;
    const rect = canvas.getBoundingClientRect();
    const x = event.clientX - rect.left;
    const y = event.clientY - rect.top;
    const { lastX, lastY } = this._drawState;
    ctx.beginPath();
    ctx.moveTo(lastX, lastY);
    ctx.lineTo(x, y);
    ctx.stroke();
    this._drawState.lastX = x;
    this._drawState.lastY = y;
  }

  handlePointerUp() {
    this._drawState = null;
  }

  handleClearSignature(event) {
    const key = event.currentTarget.dataset.key;
    if (!key) {
      return;
    }
    const root = this.template;
    const canvas = root.querySelector(`canvas[data-key='${key}']`);
    if (!canvas) {
      return;
    }
    const ctx = canvas.getContext('2d');
    ctx.clearRect(0, 0, canvas.width, canvas.height);
  }

  mergeBodyHtml() {
    if (!this.contractTemplate || !this.contractTemplate.bodyHtml) {
      return '';
    }
    let html = this.contractTemplate.bodyHtml;
    for (const f of this.fields) {
      const raw = (this.form[f.key] || '').trim();
      const safe = raw ? this.escapeHtml(raw) : '—';
      const token = '{{' + f.key + '}}';
      html = html.split(token).join(safe);
    }
    return html;
  }

  escapeHtml(value) {
    return String(value)
      .replace(/&/g, '&amp;')
      .replace(/</g, '&lt;')
      .replace(/>/g, '&gt;')
      .replace(/"/g, '&quot;')
      .replace(/'/g, '&#39;');
  }

  /**
   * Turn merged HTML into ordered blocks so the PDF keeps headings and paragraph breaks
   * (innerText alone collapses structure into one wall of text).
   */
  buildPdfBlocks(html) {
    const host = document.createElement('div');
    host.innerHTML = html;
    const root = host.querySelector('article') || host;
    const blocks = [];
    const push = (kind, text, fontSize) => {
      const t = (text || '').replace(/\s+/g, ' ').trim();
      if (t) {
        blocks.push({
          kind,
          text: t,
          fontSize: fontSize || 11
        });
      }
    };

    Array.from(root.children).forEach((child) => {
      const tag = child.tagName;
      if (tag === 'H1') {
        push('h1', child.innerText, 18);
      } else if (tag === 'H2') {
        push('h2', child.innerText, 14);
      } else if (tag === 'H3') {
        push('h2', child.innerText, 12);
      } else if (tag === 'P') {
        push('p', child.innerText, 11);
      } else if (tag === 'OL' || tag === 'UL') {
        Array.from(child.children).forEach((li) => {
          if (li.tagName === 'LI') {
            push('p', li.innerText, 11);
          }
        });
      }
    });
    return blocks;
  }

  _isCanvasBlank(canvas) {
    if (!canvas || !canvas.getContext) {
      return true;
    }
    const ctx = canvas.getContext('2d');
    const w = canvas.width;
    const h = canvas.height;
    let data;
    try {
      data = ctx.getImageData(0, 0, w, h).data;
    } catch (e) {
      return true;
    }
    const stride = 16;
    for (let i = 0; i < data.length; i += 4 * stride) {
      const a = data[i + 3];
      if (a < 24) {
        continue;
      }
      const r = data[i];
      const g = data[i + 1];
      const b = data[i + 2];
      if (r < 248 || g < 248 || b < 248) {
        return false;
      }
    }
    return true;
  }

  async handleGeneratePdf() {
    if (!this.recordId) {
      this.dispatchEvent(
        new ShowToastEvent({
          title: 'Missing Account',
          message: 'Open this component on an Account record.',
          variant: 'error'
        })
      );
      return;
    }
    if (!this.jspdfReady || !window.jspdf || !window.jspdf.jsPDF) {
      this.dispatchEvent(
        new ShowToastEvent({
          title: 'PDF library',
          message: 'jsPDF is still loading. Wait a moment and try again.',
          variant: 'warning'
        })
      );
      return;
    }

    this.isGenerating = true;
    const root = this.template;
    try {
      const PdfCtor = window.jspdf.jsPDF;
      const doc = new PdfCtor({ unit: 'pt', format: 'letter' });
      const margin = 48;
      const pageW = 612;
      const maxW = pageW - 2 * margin;
      let y = margin;

      const blocks = this.buildPdfBlocks(this.mergeBodyHtml());
      const lineHeight = 14;

      for (const block of blocks) {
        const isHead = block.kind === 'h1' || block.kind === 'h2';
        doc.setFont('helvetica', isHead ? 'bold' : 'normal');
        doc.setFontSize(block.fontSize || 11);
        if (y > margin + 8 && isHead) {
          y += lineHeight * 0.65;
        }
        const lines = doc.splitTextToSize(block.text, maxW);
        for (const line of lines) {
          if (y > 756 - margin) {
            doc.addPage();
            y = margin;
          }
          doc.text(line, margin, y);
          y += isHead ? lineHeight * 1.25 : lineHeight;
        }
        y += lineHeight * 0.45;
        doc.setFontSize(11);
      }

      y += lineHeight;
      if (y > 680) {
        doc.addPage();
        y = margin;
      }
      doc.setFontSize(12);
      doc.setFont('helvetica', 'bold');
      doc.text('Signatures', margin, y);
      y += lineHeight * 1.25;
      doc.setFont('helvetica', 'normal');
      doc.setFontSize(10);

      for (const sig of this.signatures) {
        const canvas = root.querySelector(`canvas[data-key='${sig.key}']`);
        if (!canvas) {
          continue;
        }
        if (y > 700) {
          doc.addPage();
          y = margin;
        }
        doc.setFont('helvetica', 'bold');
        doc.setFontSize(10);
        doc.text(sig.label + ':', margin, y);
        y += lineHeight;
        doc.setFont('helvetica', 'normal');
        doc.setFontSize(9);
        if (this._isCanvasBlank(canvas)) {
          doc.text(
            'Signature: _________________________________________',
            margin,
            y + 6
          );
          doc.text(
            'Name (print): _____________________________________',
            margin,
            y + 22
          );
          doc.text(
            'Date: _____________________________________________',
            margin,
            y + 38
          );
          y += 56;
        } else {
          const url = canvas.toDataURL('image/png');
          doc.addImage(url, 'PNG', margin, y, 220, 70);
          y += 78;
        }
      }

      const dataUri = doc.output('datauristring');
      const base64 = dataUri.includes(',')
        ? dataUri.substring(dataUri.indexOf(',') + 1)
        : dataUri;

      const docId = await savePdfToAccount({
        accountId: this.recordId,
        base64Pdf: base64,
        title: this.templateName
      });

      this.dispatchEvent(
        new ShowToastEvent({
          title: 'PDF saved',
          message: 'File attached to this Account (ContentDocument Id: ' + docId + ').',
          variant: 'success'
        })
      );
    } catch (e) {
      this.dispatchEvent(
        new ShowToastEvent({
          title: 'Could not save PDF',
          message: this._errMessage(e),
          variant: 'error'
        })
      );
    } finally {
      this.isGenerating = false;
    }
  }

  _errMessage(error) {
    if (!error) {
      return 'Unknown error';
    }
    if (error.body && error.body.message) {
      return error.body.message;
    }
    return error.message || String(error);
  }
}