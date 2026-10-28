import { LightningElement } from 'lwc';
import getWorkspace from '@salesforce/apex/GovController.getWorkspace';
import saveUseCase from '@salesforce/apex/GovController.saveUseCase';
import prepareFiling from '@salesforce/apex/GovController.prepareFiling';
import submitFiling from '@salesforce/apex/GovController.submitFiling';
import attachEvidence from '@salesforce/apex/GovController.attachEvidence';
import decideReview from '@salesforce/apex/GovController.decideReview';
import seedDemo from '@salesforce/apex/GovController.seedDemo';
import seedReviewDemo from '@salesforce/apex/GovController.seedReviewDemo';
import attachSyntheticDemoEvidence from '@salesforce/apex/GovController.attachSyntheticDemoEvidence';
import generateReviewerDraft from '@salesforce/apex/GovController.generateReviewerDraft';

// Display order of the five sign-off gates (the gate line reads left to right).
const ROLES = ['AI Risk', 'Architecture', 'Compliance', 'Legal', 'Security'];
const EMPTY_FORM = {
    Name: '', Purpose__c: '', Sector__c: 'Bank', Personal_Data__c: false,
    Customer_Facing__c: false, Cross_Border__c: false, Cloud_Outsourcing__c: false,
    Bank_Type__c: 'Commercial Bank', Material_IT_Outsourcing__c: false,
    Data_Categories__c: '', Permitted_Actions__c: '', Processing_Locations__c: '', Retention_Days__c: 90
};
const EVIDENCED = 'Evidence attached';
const STATUS_ORDER = { Missing: 0, Expired: 1, Stale: 2, [EVIDENCED]: 3 };
const VIEWS = [
    { id: 'overview', label: 'Overview' },
    { id: 'controls', label: 'Controls' },
    { id: 'signoffs', label: 'Sign-offs' },
    { id: 'history', label: 'History' }
];
const EVENT_LABELS = {
    INTAKE_SAVED: 'Scope saved',
    EVIDENCE_ATTACHED: 'Evidence pinned',
    FILING_PREPARED: 'Filing prepared',
    FILING_BLOCKED: 'Filing blocked',
    FILED_FOR_HUMAN_SIGNOFF: 'Filed for sign-off',
    NATIVE_REVIEW_DECISION: 'Reviewer decision',
    AI_DRAFT_GENERATED: 'AI draft generated'
};
const MONTHS = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

const plural = (n, one, many) => `${n} ${n === 1 ? one : many}`;
const short = (hash) => (hash ? `${String(hash).slice(0, 8)}…` : '—');
const pad = (n) => String(n).padStart(2, '0');
function stamp(value) {
    if (!value) return '—';
    const d = new Date(value);
    return `${d.getDate()} ${MONTHS[d.getMonth()]} ${d.getFullYear()}, ${pad(d.getHours())}:${pad(d.getMinutes())}`;
}
function when(value) {
    if (!value) return '';
    const d = new Date(value);
    const today = new Date();
    const time = `${pad(d.getHours())}:${pad(d.getMinutes())}`;
    return d.toDateString() === today.toDateString() ? `Today ${time}` : `${d.getDate()} ${MONTHS[d.getMonth()]} ${time}`;
}
function pillFor(status) {
    if (status === EVIDENCED) return { label: 'Evidenced', cls: 'pill pill-ok' };
    if (status === 'Missing') return { label: 'Missing', cls: 'pill pill-bad' };
    if (status === 'Stale' || status === 'Expired') return { label: status, cls: 'pill pill-warn' };
    return { label: 'Not applicable', cls: 'pill pill-neutral' };
}

export default class GovWorkspace extends LightningElement {
    workspace;
    caseId;
    busy = false;
    error = '';
    notice = '';
    editing = false;
    view = 'overview';
    loadedAt;
    form = { ...EMPTY_FORM };
    approvers = {};
    rationales = {};
    selectedControl = '';
    expiry = new Date(Date.now() + 90 * 86400000).toISOString().slice(0, 10);
    sectorOptions = ['Bank', 'Securities', 'Insurance'].map((value) => ({ label: value, value }));
    bankTypeOptions = ['Commercial Bank', 'Small Finance Bank', 'Payments Bank', 'Regional Rural Bank', 'Other'].map((value) => ({ label: value, value }));
    pendingUpload;

    connectedCallback() { this.load(); }

    async load(caseId = this.caseId) {
        this.busy = true;
        this.error = '';
        try {
            let data = await getWorkspace({ caseId: caseId || null });
            if (!caseId && data.useCases.length) {
                caseId = data.useCases[0].Id;
                data = await getWorkspace({ caseId });
            }
            this.caseId = caseId;
            this.workspace = data;
            this.loadedAt = new Date();
            // Self-assignment is offered only for visibly marked synthetic demo records.
            if (data.useCase?.Is_Demo__c) {
                this.approvers = Object.fromEntries(ROLES.map((role) => [role, this.approvers[role] || data.currentUserId]));
            }
        } catch (error) { this.error = this.message(error); }
        finally { this.busy = false; }
    }

    // ---------- scope ----------
    get hasCase() { return !!this.workspace?.useCase; }
    get canManage() { return !!this.workspace?.canManage; }
    get isDemo() { return !!this.workspace?.useCase?.Is_Demo__c; }
    get useCase() { return this.workspace?.useCase || {}; }
    get filing() { return this.workspace?.filing || {}; }
    get hasFiling() { return !!this.filing.Id; }
    get showFirstRun() { return !this.editing && !this.busy; }
    get caseName() { return (this.useCase.Name || '').replace(/^DEMO \| /, ''); }
    get caseOptions() { return (this.workspace?.useCases || []).map((item) => ({ label: item.Name.replace(/^DEMO \| /, ''), value: item.Id })); }
    get freshness() { return this.loadedAt ? `Updated ${stamp(this.loadedAt)}` : ''; }
    get outdated() { return this.hasFiling && !this.workspace?.isCurrent; }
    get blockerCount() { return this.workspace?.blockers || 0; }
    get clearedCount() { return this.workspace?.clearedGates || 0; }
    get riskLevel() { return this.filing.Risk_Level__c || '—'; }
    get riskSignals() {
        const u = this.useCase;
        const signals = [u.Personal_Data__c && 'Personal data', u.Customer_Facing__c && 'Customer-facing', u.Cross_Border__c && 'Overseas processing'].filter(Boolean);
        return this.hasFiling ? `${signals.length ? signals.join(' · ') : 'No risk signals'}; human confirms` : 'Prepare a filing to assess';
    }
    get disablePrepare() { return this.busy || !this.hasCase; }
    get evidenceUploadDisabled() { return this.busy || !this.selectedControl; }

    // ---------- controls ----------
    get applicableControls() { return (this.workspace?.controls || []).filter((c) => c.Applicable__c); }
    get openControls() { return this.applicableControls.filter((c) => c.Status__c !== EVIDENCED); }
    get evidencedCount() { return this.applicableControls.length - this.openControls.length; }
    get applicableCount() { return this.applicableControls.length; }
    get hasOpen() { return this.openControls.length > 0; }
    get firstOpen() {
        return [...this.openControls].sort((a, b) => STATUS_ORDER[a.Status__c] - STATUS_ORDER[b.Status__c])[0];
    }
    get openSummary() {
        const open = this.openControls;
        if (!open.length) return this.applicableCount ? 'All applicable controls' : 'No applicable controls';
        return `${open.length} open: ${open.map((c) => c.Control_Key__c).join(', ')}`;
    }
    get openFigClass() { return this.hasOpen ? 'fig-sub bad' : 'fig-sub'; }
    get controlOptions() { return this.applicableControls.map((item) => ({ label: `${item.Control_Key__c} · ${item.Title__c}`, value: item.Control_Key__c })); }
    get controlRows() {
        const evidenceById = new Map((this.workspace?.evidence || []).map((item) => [item.Id, item]));
        return [...this.applicableControls]
            .sort((a, b) => STATUS_ORDER[a.Status__c] - STATUS_ORDER[b.Status__c])
            .map((item) => {
                const proof = evidenceById.get(item.Evidence__c);
                const open = item.Status__c !== EVIDENCED;
                return {
                    ...item, proof, hasProof: !!proof, hasSource: !!item.Source_URL__c, open,
                    pill: pillFor(item.Status__c),
                    rowClass: open ? 'is-open' : '',
                    validThrough: proof && !open ? proof.Expires_On__c : null,
                    subline: `${item.Reviewer_Role__c} gate · ${item.Clause__c}`,
                    hashShort: proof ? short(proof.Content_Hash__c) : '',
                    checksumLabel: proof?.Hash_Algorithm__c || 'SHA-256',
                    sourceLink: proof ? `/sfc/servlet.shepherd/version/download/${proof.Source_Record_Id__c}` : ''
                };
            });
    }
    get notApplicable() { return (this.workspace?.controls || []).filter((c) => !c.Applicable__c); }
    get hasNotApplicable() { return this.notApplicable.length > 0; }
    get notApplicableRows() {
        const u = this.useCase;
        const reason = (c) => {
            const scope = String(c.Explanation__c || '').match(/the (\w+) applicability rule/)?.[1];
            switch (scope) {
                case 'PersonalCrossBorder': return u.Personal_Data__c ? 'no overseas processing declared' : 'no personal data declared';
                case 'Personal': return 'no personal data declared';
                case 'Securities': return `sector is ${u.Sector__c}, not Securities`;
                case 'Insurance': return `sector is ${u.Sector__c}, not Insurance`;
                case 'CommercialMaterialIT': return 'not a commercial bank with material IT outsourcing';
                default: return 'outside the declared scope';
            }
        };
        return this.notApplicable.map((c, i) => ({ key: c.Control_Key__c, reason: reason(c), sep: i < this.notApplicable.length - 1 ? ',' : '' }));
    }
    get notApplicableLabel() { return `${this.notApplicable.length} not applicable:`; }

    // ---------- gates (the gate line) ----------
    get reviewByRole() { return new Map((this.workspace?.reviews || []).map((v) => [v.record.Reviewer_Role__c, v])); }
    get gates() {
        const byRole = this.reviewByRole;
        const filed = this.hasFiling && this.filing.Status__c !== 'Draft';
        return ROLES.map((role) => {
            const mine = this.applicableControls.filter((c) => c.Reviewer_Role__c === role);
            const open = mine.filter((c) => c.Status__c !== EVIDENCED);
            const view = byRole.get(role);
            const status = view?.record.Status__c;
            let pill = null;
            if (view?.affected) pill = { label: 'Re-review', cls: 'pill pill-warn' };
            else if (status === 'Approved') pill = { label: 'Approved', cls: 'pill pill-ok' };
            else if (status === 'Carried Forward') pill = { label: 'Carried forward', cls: 'pill pill-ok' };
            else if (status === 'Rejected') pill = { label: 'Rejected', cls: 'pill pill-bad' };
            else if (filed && status === 'Pending') pill = { label: 'Waiting', cls: 'pill pill-neutral' };
            return {
                role,
                reviewer: view?.record.Approver__r?.Name || (view ? 'Assigned at filing' : 'No gate yet'),
                pill,
                segs: mine.map((c) => ({ key: c.Control_Key__c, cls: c.Status__c === EVIDENCED ? 'seg' : (c.Status__c === 'Missing' ? 'seg missing' : 'seg stale'), title: `${c.Control_Key__c}: ${c.Status__c}` })),
                hasSegs: mine.length > 0,
                evidenced: mine.length - open.length,
                ofLabel: ` of ${mine.length} evidenced`,
                note: open.length ? `${open.map((c) => c.Control_Key__c).join(', ')} ${open.length === 1 ? open[0].Status__c.toLowerCase() : 'open'}` : '',
                keys: mine.map((c) => c.Control_Key__c),
                noteClass: open.length ? 'gate-note bad' : 'gate-note'
            };
        });
    }
    get gatesSub() {
        const s = this.filing.Status__c;
        if (!this.hasFiling) return 'No filing yet';
        if (s === 'Draft') return 'Not yet filed';
        if (s === 'Approved') return 'All gates signed';
        if (s === 'Rework') return 'Rework requested';
        const waiting = (this.workspace?.reviews || []).filter((v) => v.record.Status__c === 'Pending').length;
        return `${plural(waiting, 'reviewer', 'reviewers')} still to decide`;
    }
    get releaseLabel() { return this.workspace?.releaseReady ? 'Cleared' : 'Held'; }

    // ---------- title row: finding, hold and the one primary action ----------
    get finding() {
        if (!this.hasFiling) return { lead: '', text: 'No filing yet. Prepare one to assess the declared scope against the control library.' };
        const v = `Filing v${this.filing.Version__c}`;
        const first = this.firstOpen;
        if (first) {
            const what = first.Status__c === 'Missing' ? 'has no evidence' : `has ${first.Status__c.toLowerCase()} evidence`;
            const more = this.openControls.length > 1 ? ` ${plural(this.openControls.length - 1, 'other control is', 'other controls are')} also open.` : '';
            return { lead: first.Control_Key__c, text: ` (${first.Title__c.toLowerCase()}) ${what}, so the ${first.Reviewer_Role__c} gate cannot clear and ${v.toLowerCase()} is held.${more}` };
        }
        if (this.outdated) return { lead: '', text: `${v} no longer matches the current scope, evidence or library. Prepare a new version; unchanged gates carry forward.` };
        const s = this.filing.Status__c;
        if (s === 'Draft') return { lead: '', text: `${v} is a draft and every applicable control has current evidence. File it for the five human sign-offs.` };
        if (s === 'In Review') {
            const n = this.myWaiting.length;
            if (n) return { lead: `${plural(n, 'gate is', 'gates are')} waiting on you.`, text: ` Read the evidence on Controls, then approve or reject each gate with a rationale. ${this.clearedCount} of 5 cleared so far.` };
            return { lead: '', text: `${v} is with the reviewers: ${this.clearedCount} of 5 gates cleared.` };
        }
        if (s === 'Rework') return { lead: '', text: `${v} was sent back by a reviewer. A rework task is open; update the scope or evidence and prepare a new version.` };
        if (s === 'Approved') return { lead: '', text: `${v} has all five human sign-offs on current evidence. Deployment remains a separate controlled action.` };
        return { lead: '', text: `${v} · ${s}` };
    }
    get hasFindingLead() { return !!this.finding.lead; }
    get myWaiting() { return (this.workspace?.reviews || []).filter((v) => v.canDecide && v.record.Status__c === 'Pending'); }
    get primary() {
        if (!this.hasCase) return null;
        const mine = this.myWaiting.length;
        if (mine && !this.outdated) return { label: mine === 1 ? 'Review 1 gate' : `Review ${mine} gates`, action: 'review' };
        if (!this.canManage) return null;
        const first = this.firstOpen;
        if (first) return { label: `Attach ${first.Control_Key__c} evidence`, action: 'attach' };
        if (!this.hasFiling) return { label: 'Prepare filing', action: 'prepare' };
        if (this.outdated) return { label: `Prepare v${Number(this.filing.Version__c) + 1}`, action: 'prepare' };
        if (this.filing.Status__c === 'Draft') return { label: 'File for sign-off', action: 'file' };
        return null;
    }
    get hasPrimary() { return !!this.primary; }
    get primaryLabel() { return this.primary?.label; }
    get holdText() {
        if (!this.canManage || !this.hasOpen) return '';
        return `File for sign-off is held: ${plural(this.openControls.length, 'control needs', 'controls need')} evidence`;
    }
    get showPrepareSecondary() { return this.canManage && this.hasCase && this.primary?.action !== 'prepare'; }

    // ---------- tabs ----------
    get tabs() {
        return VIEWS.map((v) => ({ ...v, selected: String(this.view === v.id), tabindex: this.view === v.id ? '0' : '-1' }));
    }
    get isOverview() { return this.view === 'overview'; }
    get isControls() { return this.view === 'controls'; }
    get isSignoffs() { return this.view === 'signoffs'; }
    get isHistory() { return this.view === 'history'; }

    // ---------- filing well, checklist, history ----------
    get filingTitle() { return this.hasFiling ? `Filing v${this.filing.Version__c}` : 'Filing'; }
    get filingPrepared() { return this.hasFiling ? `Prepared ${stamp(this.filing.CreatedDate)}` : ''; }
    get filingFacts() {
        const u = this.useCase;
        return [
            { k: 'Status', v: this.filing.Status__c || 'Not prepared', mono: false },
            { k: 'Retention declared', v: u.Retention_Days__c != null ? `${u.Retention_Days__c} days` : '—', mono: false },
            { k: 'Processing', v: (u.Processing_Locations__c || '—').split(/[—;]/)[0].trim(), mono: false },
            { k: 'Library', v: this.filing.Library_Version__c || '—', mono: true },
            { k: 'Input hash', v: short(this.filing.Input_Hash__c), mono: true },
            { k: 'Manifest hash', v: short(this.filing.Manifest_Hash__c), mono: true }
        ].map((f) => ({ ...f, cls: f.mono ? 'mono' : '' }));
    }
    get assignedCount() { return ROLES.filter((r) => this.approvers[r]).length; }
    get steps() {
        const filed = this.hasFiling && this.filing.Status__c !== 'Draft';
        const list = [
            { id: 'evidence', label: 'Evidence on every applicable control', done: !this.hasOpen, figure: `${this.evidencedCount} of ${this.applicableCount}` },
            { id: 'current', label: 'Filing matches current scope and library', done: this.hasFiling && !this.outdated, figure: this.hasFiling ? `v${this.filing.Version__c}` : '—' },
            { id: 'assign', label: 'Assign the five reviewers', done: filed || this.assignedCount === 5, figure: filed ? 'Filed' : `${this.assignedCount} of 5` }
        ];
        return list.map((s) => ({ ...s, cls: s.done ? 'done' : 'todo' }));
    }
    get stepsDone() { return `${this.steps.filter((s) => s.done).length} of 3 done`; }
    get auditRows() {
        return (this.workspace?.auditEvents || []).map((e) => {
            let details = {};
            try { details = JSON.parse(e.Details__c || '{}'); } catch (ignore) { details = {}; }
            let label = EVENT_LABELS[e.Event__c] || e.Event__c;
            if (e.Event__c === 'EVIDENCE_ATTACHED' && details.control) label += `: ${details.control}`;
            if (e.Event__c === 'FILING_PREPARED' && details.version) label = `Filing v${details.version} prepared`;
            if (e.Event__c === 'AI_DRAFT_GENERATED' && details.role) label += `: ${details.role}`;
            let detail = e.CreatedBy?.Name || '';
            if (details.contentHash) detail += ` · ${details.hashAlgorithm || 'SHA-256'} ${short(details.contentHash)}`;
            if (details.validThrough) detail += `, valid through ${details.validThrough}`;
            if (details.nativeApprovalRequests != null) detail += ` · ${plural(details.nativeApprovalRequests, 'approval request', 'approval requests')}`;
            return { ...e, label, detail, when: when(e.CreatedDate), stampLabel: stamp(e.CreatedDate) };
        });
    }
    get recentHistory() { return this.auditRows.slice(0, 5); }
    get historyTotalLabel() { return `View all ${this.auditRows.length}`; }
    get hasHistory() { return this.auditRows.length > 0; }

    // ---------- sign-offs ----------
    get reviewerAssignments() { return ROLES.map((role) => ({ role, value: this.approvers[role] || null })); }
    get disableSubmit() { return this.busy || !this.workspace?.isCurrent || this.filing.Status__c !== 'Draft'; }
    get submitHold() {
        if (this.hasOpen) return this.holdText;
        if (this.outdated) return 'Prepare the current version before filing.';
        if (this.hasFiling && this.filing.Status__c !== 'Draft') return `Filed. ${this.gatesSub}.`;
        return '';
    }
    get reviewRows() {
        const byRole = this.reviewByRole;
        return ROLES.filter((r) => byRole.has(r)).map((role) => {
            const view = byRole.get(role);
            const r = view.record;
            const gate = this.gates.find((g) => g.role === role);
            return {
                ...r, affected: view.affected, gate,
                pill: gate.pill || { label: r.Status__c === 'Pending' ? 'Not filed' : r.Status__c, cls: 'pill pill-neutral' },
                disabled: this.busy || !view.canDecide,
                canDecide: view.canDecide,
                rationale: this.rationales[r.Id] || '',
                approverName: r.Approver__r?.Name || (this.approvers[role] ? 'Reviewer selected for filing' : 'Reviewer not assigned'),
                carried: r.Status__c === 'Carried Forward',
                disableGenerate: this.busy || !this.canManage || !this.workspace?.isCurrent || this.filing.Status__c !== 'Draft' || r.Status__c !== 'Pending',
                hasAiDraft: !!r.AI_Draft__c,
                previousLink: r.Prior_Review__c ? `/${r.Prior_Review__c}` : '',
                recordLink: `/${r.Id}`
            };
        });
    }
    get hasReviews() { return this.reviewRows.length > 0; }
    get executiveSummary() { return this.filing.Executive_Summary__c || 'Prepare a filing to create the executive summary and reviewer briefs.'; }
    get libraryLabel() { return this.filing.Library_Version__c ? `Library ${this.filing.Library_Version__c}` : ''; }
    get limitations() { return this.workspace?.limitations; }

    // ---------- handlers ----------
    handleTab(event) { this.view = event.currentTarget.dataset.view; }
    handleTabKey(event) {
        const ids = VIEWS.map((v) => v.id);
        const i = ids.indexOf(this.view);
        let next = null;
        if (event.key === 'ArrowRight') next = ids[(i + 1) % ids.length];
        if (event.key === 'ArrowLeft') next = ids[(i - 1 + ids.length) % ids.length];
        if (!next) return;
        event.preventDefault();
        this.view = next;
        Promise.resolve().then(() => this.template.querySelector(`[data-view="${next}"]`)?.focus());
    }
    handleViewAll() { this.view = 'history'; }
    handlePrimary() {
        const p = this.primary;
        if (!p) return;
        if (p.action === 'attach') {
            this.selectedControl = this.firstOpen.Control_Key__c;
            this.view = 'controls';
            Promise.resolve().then(() => this.template.querySelector('[data-upload-title]')?.focus());
        } else if (p.action === 'review') {
            this.view = 'signoffs';
            Promise.resolve().then(() => this.template.querySelector('lightning-textarea')?.focus());
        } else if (p.action === 'prepare') {
            this.handlePrepare();
        } else if (p.action === 'file') {
            if (this.assignedCount === 5) this.handleSubmit();
            else { this.view = 'signoffs'; Promise.resolve().then(() => this.template.querySelector('[data-assign-title]')?.focus()); }
        }
    }
    handleAttachRow(event) {
        this.selectedControl = event.currentTarget.dataset.key;
        this.view = 'controls';
        Promise.resolve().then(() => this.template.querySelector('[data-upload-title]')?.focus());
    }
    handleSelect(event) {
        this.approvers = {}; this.rationales = {}; this.selectedControl = ''; this.pendingUpload = null; this.notice = ''; this.editing = false;
        this.load(event.detail.value);
    }
    handleNew() { this.form = { ...EMPTY_FORM }; this.editing = true; this.error = ''; this.focusEditor(); }
    handleEdit() {
        const record = this.useCase;
        this.form = Object.fromEntries(Object.keys(EMPTY_FORM).map((key) => [key, record[key] ?? EMPTY_FORM[key]]));
        this.form.Id = record.Id; this.editing = true; this.error = ''; this.focusEditor();
    }
    async focusEditor() { await Promise.resolve(); this.template.querySelector('[data-editor-title]')?.focus(); }
    handleCancel() { this.editing = false; }
    handleField(event) {
        const field = event.target.dataset.field;
        const value = event.target.type === 'checkbox' ? event.target.checked : (event.detail?.value ?? event.target.value);
        this.form = { ...this.form, [field]: field === 'Retention_Days__c' ? Number(value) : value };
    }
    async handleSave(event) {
        event.preventDefault();
        const fields = [...this.template.querySelectorAll('[data-intake]')];
        if (!fields.every((field) => field.reportValidity())) return;
        await this.run(async () => {
            const caseId = await saveUseCase({ intakeJson: JSON.stringify(this.form) });
            this.caseId = caseId; this.editing = false;
        }, 'Use case saved. Prepare a filing to assess this scope.');
    }
    handlePrepare() { this.run(() => prepareFiling({ caseId: this.caseId }), 'Versioned filing prepared. Unchanged gates carried forward where their scope matched.'); }
    handleApprover(event) { this.approvers = { ...this.approvers, [event.target.dataset.role]: event.detail.recordId }; }
    async handleSubmit() {
        this.busy = true; this.error = ''; this.notice = '';
        try {
            const result = await submitFiling({ caseId: this.caseId, approversJson: JSON.stringify(this.approvers) });
            await this.load();
            if (result.submitted) this.notice = result.message;
            else this.error = result.message;
        } catch (error) { this.error = this.message(error); }
        finally { this.busy = false; }
    }
    handleControl(event) { this.selectedControl = event.detail.value; }
    handleExpiry(event) { this.expiry = event.target.value; }
    async handleUpload(event) {
        const file = event.detail.files[0];
        if (!file) return;
        this.pendingUpload = { caseId: this.caseId, documentId: file.documentId };
        await this.handleRetryUpload();
    }
    get hasPendingUpload() { return !!this.pendingUpload; }
    handleRetryUpload() {
        if (!this.pendingUpload) return undefined;
        const input = { ...this.pendingUpload, controlKey: this.selectedControl, expiresOn: this.expiry };
        return this.run(async () => {
            await attachEvidence(input);
            this.pendingUpload = null;
        }, 'Evidence version pinned. Prepare a new filing version to include it.');
    }
    handleDemoEvidence() { this.run(() => attachSyntheticDemoEvidence({ caseId: this.caseId, controlKey: this.selectedControl }), 'Synthetic evidence attached to this demo use case. Prepare the new filing version.'); }
    handleRationale(event) { this.rationales = { ...this.rationales, [event.target.dataset.id]: event.target.value }; }
    handleDecision(event) {
        const reviewId = event.target.dataset.id;
        const decision = event.target.dataset.decision;
        this.run(() => decideReview({ reviewId, decision, rationale: this.rationales[reviewId] || '' }), `Human decision recorded: ${decision}.`);
    }
    handleGenerateDraft(event) {
        const reviewerRole = event.target.dataset.role;
        this.run(() => generateReviewerDraft({ caseId: this.caseId, reviewerRole }), 'AI draft generated from the filed records. Verify every claim and evidence reference before sign-off.');
    }
    handleSeed() {
        this.run(async () => {
            this.caseId = await seedDemo();
            const first = await seedReviewDemo({ index: 0 });
            await seedReviewDemo({ index: 1 });
            this.caseId = first;
        }, 'Synthetic bank demos loaded. Two use cases are filed and waiting on your review; the service assistant has one deliberate evidence gap.');
    }
    handleRefresh() { this.load(); }
    async run(action, message) {
        this.busy = true; this.error = ''; this.notice = '';
        try { await action(); this.notice = message; await this.load(); }
        catch (error) { this.error = this.message(error); }
        finally { this.busy = false; }
    }
    message(error) { return error?.body?.message || error?.message || 'The operation could not be completed.'; }
}