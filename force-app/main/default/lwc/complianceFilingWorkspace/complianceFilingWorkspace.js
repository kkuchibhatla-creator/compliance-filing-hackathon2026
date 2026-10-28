import { LightningElement } from 'lwc';
import getWorkspace from '@salesforce/apex/GovController.getWorkspace';
import saveUseCase from '@salesforce/apex/GovController.saveUseCase';
import prepareFiling from '@salesforce/apex/GovController.prepareFiling';
import submitFiling from '@salesforce/apex/GovController.submitFiling';
import attachEvidence from '@salesforce/apex/GovController.attachEvidence';
import decideReview from '@salesforce/apex/GovController.decideReview';
import seedDemo from '@salesforce/apex/GovController.seedDemo';
import attachSyntheticDemoEvidence from '@salesforce/apex/GovController.attachSyntheticDemoEvidence';
import generateReviewerDraft from '@salesforce/apex/GovController.generateReviewerDraft';

const ROLES = ['AI Risk', 'Architecture', 'Legal', 'Compliance', 'Security'];
const EMPTY_FORM = {
    Name: '', Purpose__c: '', Sector__c: 'Bank', Personal_Data__c: false,
    Customer_Facing__c: false, Cross_Border__c: false, Cloud_Outsourcing__c: false,
    Bank_Type__c: 'Commercial Bank', Material_IT_Outsourcing__c: false,
    Data_Categories__c: '', Permitted_Actions__c: '', Processing_Locations__c: '', Retention_Days__c: 90
};

export default class GovWorkspace extends LightningElement {
    workspace;
    caseId;
    busy = false;
    error = '';
    notice = '';
    editing = false;
    form = { ...EMPTY_FORM };
    approvers = {};
    rationales = {};
    selectedControl = '';
    pendingUpload;
    expiry = new Date(Date.now() + 90 * 86400000).toISOString().slice(0, 10);
    sectorOptions = ['Bank', 'Securities', 'Insurance'].map((value) => ({ label: value, value }));
    bankTypeOptions = ['Commercial Bank', 'Small Finance Bank', 'Payments Bank', 'Regional Rural Bank', 'Other'].map((value) => ({ label: value, value }));

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
            // Self-assignment is offered only for visibly marked synthetic demo records.
            if (data.useCase?.Is_Demo__c) {
                this.approvers = Object.fromEntries(ROLES.map((role) => [role, this.approvers[role] || data.currentUserId]));
            }
        } catch (error) { this.error = this.message(error); }
        finally { this.busy = false; }
    }

    get hasCase() { return !!this.workspace?.useCase; }
    get canManage() { return !!this.workspace?.canManage; }
    get isDemo() { return !!this.workspace?.useCase?.Is_Demo__c; }
    get useCase() { return this.workspace?.useCase || {}; }
    get filing() { return this.workspace?.filing || {}; }
    get caseOptions() { return (this.workspace?.useCases || []).map((item) => ({ label: item.Name, value: item.Id })); }
    get filingLabel() { return this.filing.Id ? `Version ${this.filing.Version__c} · ${this.filing.Status__c}` : 'Awaiting assessment'; }
    get clearanceLabel() { return this.workspace?.releaseReady ? 'Human sign-offs complete' : 'Release clearance blocked'; }
    get clearanceClass() { return this.workspace?.releaseReady ? 'clearance ready' : 'clearance blocked'; }
    get outdated() { return !!this.filing.Id && !this.workspace?.isCurrent; }
    get blockerCount() { return this.workspace?.blockers || 0; }
    get clearedCount() { return this.workspace?.clearedGates || 0; }
    get riskLevel() { return this.filing.Risk_Level__c || 'Unassessed'; }
    get disablePrepare() { return this.busy || !this.hasCase; }
    get disableSubmit() { return this.busy || !this.workspace?.isCurrent || this.filing.Status__c !== 'Draft'; }
    get evidenceUploadDisabled() { return this.busy || !this.selectedControl; }
    get hasPendingUpload() { return !!this.pendingUpload; }
    get controlOptions() { return (this.workspace?.controls || []).filter((item) => item.Applicable__c).map((item) => ({ label: `${item.Control_Key__c} · ${item.Title__c}`, value: item.Control_Key__c })); }
    get controlRows() {
        const evidenceById = new Map((this.workspace?.evidence || []).map((item) => [item.Id, item]));
        return (this.workspace?.controls || []).map((item) => {
            const proof = evidenceById.get(item.Evidence__c);
            return {
                ...item, proof, hasProof: !!proof, hasSource: !!item.Source_URL__c,
                checksumLabel: proof?.Hash_Algorithm__c || 'SHA-256',
                sourceLink: proof ? `/sfc/servlet.shepherd/version/download/${proof.Source_Record_Id__c}` : '',
                statusClass: item.Status__c === 'Evidence attached' ? 'badge success' : (item.Status__c === 'Not applicable' ? 'badge neutral' : 'badge warning')
            };
        });
    }
    get reviewerAssignments() { return ROLES.map((role) => ({ role, value: this.approvers[role] || null })); }
    get reviewRows() {
        return (this.workspace?.reviews || []).map((view) => ({
            ...view.record, affected: view.affected,
            disabled: this.busy || !view.canDecide,
            rationale: this.rationales[view.record.Id] || '',
            approverName: view.record.Approver__r?.Name || 'Unassigned',
            carried: view.record.Status__c === 'Carried Forward',
            disableGenerate: this.busy || !this.canManage || !this.workspace?.isCurrent || this.filing.Status__c !== 'Draft' || view.record.Status__c !== 'Pending',
            hasAiDraft: !!view.record.AI_Draft__c,
            previousLink: view.record.Prior_Review__c ? `/${view.record.Prior_Review__c}` : '',
            recordLink: `/${view.record.Id}`,
            statusClass: ['Approved', 'Carried Forward'].includes(view.record.Status__c) ? 'badge success' : 'badge neutral'
        }));
    }
    get auditRows() { return this.workspace?.auditEvents || []; }
    get executiveSummary() { return this.filing.Executive_Summary__c || 'Prepare a filing to create the executive summary and reviewer briefs.'; }

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
    handlePrepare() { this.run(() => prepareFiling({ caseId: this.caseId }), 'Versioned filing prepared. Review the evidence and assign the pending gates.'); }
    handleApprover(event) { this.approvers = { ...this.approvers, [event.target.dataset.role]: event.detail.recordId }; }
    handleSubmit() { this.run(() => submitFiling({ caseId: this.caseId, approversJson: JSON.stringify(this.approvers) }), 'Filed. Native Salesforce approval work items are waiting for human decisions.'); }
    handleControl(event) { this.selectedControl = event.detail.value; }
    handleExpiry(event) { this.expiry = event.target.value; }
    async handleUpload(event) {
        const file = event.detail.files[0];
        if (!file) return;
        this.pendingUpload = { caseId: this.caseId, documentId: file.documentId };
        await this.handleRetryUpload();
    }
    handleRetryUpload() {
        if (!this.pendingUpload) return;
        const input = { ...this.pendingUpload, controlKey: this.selectedControl, expiresOn: this.expiry };
        return this.run(async () => {
            await attachEvidence(input);
            this.pendingUpload = null;
        }, 'Evidence version pinned. Prepare a new filing to include it.');
    }
    handleDemoEvidence() { this.run(() => attachSyntheticDemoEvidence({ caseId: this.caseId, controlKey: this.selectedControl }), 'Synthetic evidence attached to this demo use case. Prepare the new filing version.'); }
    handleRationale(event) { this.rationales = { ...this.rationales, [event.target.dataset.id]: event.target.value }; }
    handleDecision(event) {
        const reviewId = event.target.dataset.id;
        const decision = event.target.dataset.decision;
        this.run(() => decideReview({ reviewId, decision, rationale: this.rationales[reviewId] || '' }), `Human decision recorded: ${decision}.`);
    }
    handleGenerateDraft(event) {
        const reviewerRole=event.target.dataset.role;
        this.run(() => generateReviewerDraft({ caseId: this.caseId, reviewerRole }), 'AI draft generated from the filed records. Verify every claim and evidence reference before sign-off.');
    }
    handleSeed() { this.run(async () => { this.caseId = await seedDemo(); }, 'Synthetic bank demo loaded. One access-control evidence item is deliberately missing.'); }
    handleRefresh() { this.load(); }
    async run(action, message) {
        this.busy = true; this.error = ''; this.notice = '';
        try { await action(); this.notice = message; await this.load(); }
        catch (error) { this.error = this.message(error); }
        finally { this.busy = false; }
    }
    message(error) { return error?.body?.message || error?.message || 'The operation could not be completed.'; }
}
