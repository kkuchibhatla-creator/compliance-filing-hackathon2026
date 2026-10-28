public with sharing class GovController {
    public class ReviewView {
        @AuraEnabled public Gov_Review__c record;
        @AuraEnabled public Boolean affected;
        @AuraEnabled public Boolean canDecide;
    }
    public class Workspace {
        @AuraEnabled public List<Gov_Use_Case__c> useCases;
        @AuraEnabled public Gov_Use_Case__c useCase;
        @AuraEnabled public Gov_Filing__c filing;
        @AuraEnabled public List<Gov_Control__c> controls;
        @AuraEnabled public List<Gov_Evidence__c> evidence;
        @AuraEnabled public List<ReviewView> reviews;
        @AuraEnabled public List<Gov_Audit__c> auditEvents;
        @AuraEnabled public Boolean isCurrent;
        @AuraEnabled public Boolean releaseReady;
        @AuraEnabled public Boolean canManage;
        @AuraEnabled public Boolean canReview;
        @AuraEnabled public Id currentUserId;
        @AuraEnabled public String limitations;
        @AuraEnabled public Integer blockers;
        @AuraEnabled public Integer clearedGates;
    }
    @AuraEnabled
    public static Workspace getWorkspace(Id caseId) {
        Workspace result = new Workspace();
        result.canManage=FeatureManagement.checkPermission('Gov_Manage');
        result.canReview=FeatureManagement.checkPermission('Gov_Review');
        result.currentUserId=UserInfo.getUserId(); result.limitations=GovLibrary.catalog().limitations;
        result.useCases=[SELECT Id, Name FROM Gov_Use_Case__c WITH USER_MODE ORDER BY LastModifiedDate DESC LIMIT 50];
        result.controls=new List<Gov_Control__c>(); result.reviews=new List<ReviewView>();
        result.evidence=new List<Gov_Evidence__c>(); result.auditEvents=new List<Gov_Audit__c>();
        result.isCurrent=false; result.releaseReady=false; result.blockers=0; result.clearedGates=0;
        if (caseId == null) return result;
        result.useCase=GovService.useCaseById(caseId,false);
        GovService.reconcileNativeDecisions(caseId);
        result.filing=GovService.latestFiling(caseId);
        result.controls=GovService.controls(result.useCase);
        result.evidence=GovService.evidence(caseId);
        result.blockers=GovService.missingCount(result.controls,null);
        result.isCurrent=GovService.current(result.filing,result.useCase,result.controls);
        if (result.filing != null) {
            for (Gov_Review__c review : [SELECT Id, Name, Filing__c, Reviewer_Role__c, Approver__c, Approver__r.Name,
                Status__c, Brief__c, Rationale__c, AI_Draft__c, AI_Generation_Id__c, Scope_Hash__c, Prior_Review__c, Decision_At__c, Decision_By__c
                FROM Gov_Review__c WHERE Filing__c = :result.filing.Id WITH USER_MODE ORDER BY Reviewer_Role__c]) {
                ReviewView view = new ReviewView(); view.record=review;
                view.affected=review.Scope_Hash__c != GovLibrary.roleHash(review.Reviewer_Role__c,result.useCase,result.controls);
                view.canDecide=result.canReview && result.isCurrent && review.Status__c == 'Pending' &&
                    review.Approver__c == result.currentUserId && result.filing.Status__c != 'Draft';
                if (!view.affected && (review.Status__c == 'Approved' || review.Status__c == 'Carried Forward')) result.clearedGates++;
                result.reviews.add(view);
            }
            result.releaseReady=result.isCurrent && result.blockers == 0 && result.clearedGates == 5 &&
                result.filing.Status__c == 'Approved' && result.useCase.Sector__c == 'Bank' && result.useCase.Bank_Type__c == 'Commercial Bank';
        }
        result.auditEvents=[SELECT Id, Name, Event__c, Details__c, CreatedDate, CreatedBy.Name, Filing__c
            FROM Gov_Audit__c WHERE Use_Case__c = :caseId WITH USER_MODE ORDER BY CreatedDate DESC, Id DESC LIMIT 100];
        return result;
    }
    @AuraEnabled
    public static Id saveUseCase(String intakeJson) {
        try { return GovService.saveCase((Gov_Use_Case__c)JSON.deserialize(intakeJson,Gov_Use_Case__c.class)); }
        catch (Exception error) { throw handled(error); }
    }
    @AuraEnabled
    public static Id attachEvidence(Id caseId, String controlKey, Id documentId, Date expiresOn) {
        try { return GovService.attachEvidence(caseId,controlKey,documentId,expiresOn); }
        catch (Exception error) { throw handled(error); }
    }
    @AuraEnabled
    public static Id prepareFiling(Id caseId) {
        try { return GovService.prepare(caseId); }
        catch (Exception error) { throw handled(error); }
    }
    @AuraEnabled
    public static GovService.FilingResult submitFiling(Id caseId, String approversJson) {
        try { return GovService.attemptSubmit(caseId,(Map<String,Id>)JSON.deserialize(approversJson,Map<String,Id>.class)); }
        catch (Exception error) { throw handled(error); }
    }
    @AuraEnabled
    public static void decideReview(Id reviewId, String decision, String rationale) {
        try { GovService.decide(reviewId,decision,rationale); }
        catch (Exception error) { throw handled(error); }
    }
    @AuraEnabled
    public static String generateReviewerDraft(Id caseId, String reviewerRole) {
        try { return GovAiDraft.generate(caseId,reviewerRole); }
        catch (Exception error) { throw handled(error); }
    }
    @AuraEnabled
    public static Id seedDemo() {
        GovService.requireManager();
        Id actor=UserInfo.getUserId();
        List<Gov_Use_Case__c> existing=[SELECT Id FROM Gov_Use_Case__c WHERE Is_Demo__c = true AND OwnerId = :actor WITH USER_MODE LIMIT 1];
        if (!existing.isEmpty()) return existing[0].Id;
        Id caseId=GovService.saveCase(new Gov_Use_Case__c(Name='DEMO | Nila Bank service assistant', Sector__c='Bank',
            Purpose__c='Help authenticated customers understand service requests. No credit decisions or payments.',
            Personal_Data__c=true, Customer_Facing__c=true, Cross_Border__c=false, Cloud_Outsourcing__c=true, Bank_Type__c='Commercial Bank', Material_IT_Outsourcing__c=true,
            Data_Categories__c='Synthetic customer name, service request and contact preference. No real customer data.',
            Permitted_Actions__c='Read permitted service requests and draft responses. A human sends each response.',
            Processing_Locations__c='India — declared demo processing boundary; verify actual provider configuration.', Retention_Days__c=90));
        update new Gov_Use_Case__c(Id=caseId,Is_Demo__c=true);
        Gov_Use_Case__c useCase=GovService.useCaseById(caseId,false);
        List<ContentVersion> files=new List<ContentVersion>(); List<String> keys=new List<String>();
        for (GovLibrary.Definition control : GovLibrary.catalog().controls) {
            if (GovLibrary.applicable(control,useCase) && control.key != 'RBI-ACCESS') {
                keys.add(control.key); files.add(demoFile(caseId,control));
            }
        }
        insert files;
        Set<Id> versionIds=new Map<Id,ContentVersion>(files).keySet();
        Map<Id,ContentVersion> versions=new Map<Id,ContentVersion>([SELECT Id, ContentDocumentId FROM ContentVersion WHERE Id IN :versionIds]);
        for (Integer i=0; i<files.size(); i++) GovService.attachEvidence(caseId,keys[i],versions.get(files[i].Id).ContentDocumentId,Date.today().addDays(90));
        GovService.prepare(caseId);
        return caseId;
    }
    @AuraEnabled
    public static void attachSyntheticDemoEvidence(Id caseId, String controlKey) {
        GovService.requireManager();
        Gov_Use_Case__c useCase=GovService.useCaseById(caseId,false);
        if (!useCase.Is_Demo__c) throw new AuraHandledException('Synthetic evidence is available only on marked demo records.');
        ContentVersion file=demoFile(caseId,GovLibrary.definition(controlKey)); insert file;
        file=[SELECT Id, ContentDocumentId FROM ContentVersion WHERE Id = :file.Id];
        GovService.attachEvidence(caseId,controlKey,file.ContentDocumentId,Date.today().addDays(90));
    }
    /** Seeds two synthetic demo use cases, fully evidenced and filed to the current user on every gate,
        so a bank reviewer can open Sign-offs and approve or reject. Idempotent per owner and name.
        One demo per call (index 0 or 1) keeps each transaction inside the SOQL limit. */
    @AuraEnabled
    public static Id seedReviewDemo(Integer index) {
        try {
            GovService.requireManager();
            if (index == 0) return seedFiledDemo(new Gov_Use_Case__c(Name='DEMO | Nila Bank home-loan pre-screening assistant', Sector__c='Bank',
                Purpose__c='Summarise a synthetic home-loan enquiry against published eligibility rules and draft a pre-screening note for a credit officer. The assistant never approves, declines or prices a loan.',
                Personal_Data__c=true, Customer_Facing__c=false, Cross_Border__c=false, Cloud_Outsourcing__c=true, Bank_Type__c='Commercial Bank', Material_IT_Outsourcing__c=true,
                Data_Categories__c='Synthetic applicant name, declared income band, employment type, property city and loan amount requested. No bureau data, no real customers.',
                Permitted_Actions__c='Read the enquiry record and the published eligibility table; draft a pre-screening note. A credit officer reviews every note and makes the decision.',
                Processing_Locations__c='India (Mumbai region) — declared demo boundary; verify actual provider configuration.', Retention_Days__c=180));
            if (index == 1) return seedFiledDemo(new Gov_Use_Case__c(Name='DEMO | Nila Bank collections reminder agent', Sector__c='Bank',
                Purpose__c='Draft polite payment-due reminders for synthetic retail-loan accounts 1–30 days past due, in the customer\'s preferred language. No threats, no third-party contact, no settlement offers.',
                Personal_Data__c=true, Customer_Facing__c=true, Cross_Border__c=true, Cloud_Outsourcing__c=true, Bank_Type__c='Commercial Bank', Material_IT_Outsourcing__c=true,
                Data_Categories__c='Synthetic borrower name, masked account number, amount and due date, preferred language and contact window. No real customers.',
                Permitted_Actions__c='Read the due-list and draft one SMS or email reminder per account inside the permitted contact window. A collections officer approves each batch before it is sent.',
                Processing_Locations__c='India for records; language model inference in Singapore — declared demo boundary; verify actual provider configuration.', Retention_Days__c=365));
            throw new GovService.GovernanceException('Choose review demo 0 or 1.');
        } catch (Exception error) { throw handled(error); }
    }
    private static Id seedFiledDemo(Gov_Use_Case__c input) {
        Id actor=UserInfo.getUserId();
        List<Gov_Use_Case__c> existing=[SELECT Id FROM Gov_Use_Case__c WHERE Is_Demo__c = true AND OwnerId = :actor AND Name = :input.Name WITH USER_MODE LIMIT 1];
        if (!existing.isEmpty()) return existing[0].Id;
        Id caseId=GovService.saveCase(input);
        update new Gov_Use_Case__c(Id=caseId,Is_Demo__c=true);
        Gov_Use_Case__c useCase=GovService.useCaseById(caseId,false);
        List<ContentVersion> files=new List<ContentVersion>(); List<String> keys=new List<String>();
        for (GovLibrary.Definition control : GovLibrary.catalog().controls) {
            if (GovLibrary.applicable(control,useCase)) { keys.add(control.key); files.add(reviewFile(caseId,useCase,control)); }
        }
        insert files;
        Map<Id,ContentVersion> versions=new Map<Id,ContentVersion>([SELECT Id, ContentDocumentId FROM ContentVersion WHERE Id IN :new Map<Id,ContentVersion>(files).keySet()]);
        for (Integer i=0; i<files.size(); i++) GovService.attachEvidence(caseId,keys[i],versions.get(files[i].Id).ContentDocumentId,Date.today().addDays(120));
        GovService.prepare(caseId);
        Map<String,Id> approvers=new Map<String,Id>();
        for (String role : GovLibrary.ROLES) approvers.put(role,actor);
        GovService.submit(caseId,approvers);
        return caseId;
    }
    private static ContentVersion reviewFile(Id caseId, Gov_Use_Case__c useCase, GovLibrary.Definition control) {
        Map<String,String> body=new Map<String,String>{
            'GOV-RISK'=>'Risk tier: Medium. Top risks: (1) inaccurate draft reaches a customer; (2) personal data in prompts; (3) over-reliance by staff. Mitigations: human approval of every output, prompt redaction of account numbers, weekly 50-sample quality review. Residual risk accepted by the business owner (synthetic).',
            'GOV-ARCH'=>'Data flow: Salesforce record -> redaction step -> model endpoint -> draft stored on the record. The agent has read-only access to the listed objects and no send, update or payment permissions. Kill switch: deactivate the permission set. Logs retained with the record.',
            'REG-CURRENCY'=>'Scope reviewed against the bundled RBI IT outsourcing directions and DPDP Act 2023 summaries. Materiality: material IT outsourcing (cloud model provider). Source currency checked by the demo compliance owner; no newer circular identified for this synthetic review.',
            'RBI-RISK'=>'Outsourcing risk assessment: provider due diligence questionnaire completed, concentration risk Low, exit plan tested on paper (switch to a second endpoint in 10 working days). Board-approved outsourcing policy referenced. Accountability stays with the bank.',
            'RBI-ACCESS'=>'Provider access: no standing human access to bank data; support access only through a time-boxed ticket approved by the bank. Encryption in transit (TLS 1.2+) and at rest. Right to audit and inspect included in the contract schedule (synthetic).',
            'DPDP-NOTICE'=>'Processing ground: legitimate use for servicing an existing relationship. Notice text updated to mention AI-assisted drafting reviewed by staff. No new purpose, no marketing use, no training of provider models on bank data.',
            'DPDP-RETENTION'=>'Drafts and prompts retained for '+useCase.Retention_Days__c+' days for audit, then purged by a scheduled job. Exception: records under legal hold. Deletion test run on synthetic data with the expected result observed.',
            'DPDP-SECURITY'=>'Safeguards: field-level masking of account numbers before inference, role-based access, audit trail on every draft, quarterly access recertification, breach-response runbook linked. Pen test of the integration scheduled (synthetic).',
            'DPDP-TRANSFER'=>'Overseas processing: model inference in Singapore. Country not on any notified restricted list as of the review date (verify). Sector rules checked: RBI payment-data localisation does not apply because no payment-system data is sent. Contract includes onward-transfer restriction.'
        };
        String specific=body.containsKey(control.key) ? body.get(control.key) : 'Documented boundary, test procedure, expected result and observed result.';
        String content='SYNTHETIC DEMONSTRATION EVIDENCE — NOT A REAL COMPLIANCE ASSERTION\n\nUse case: '+useCase.Name+'\nControl: '+control.key+' — '+control.title+
            '\nOwner: demo control owner, fictional Nila Bank.\n\n'+specific+'\n\nSource reference: '+control.clause+'\nA qualified human must validate source currency and applicability before real use.';
        return new ContentVersion(Title='DEMO '+control.key,PathOnClient='DEMO-'+control.key+'.txt',VersionData=Blob.valueOf(content),FirstPublishLocationId=caseId);
    }
    private static ContentVersion demoFile(Id caseId, GovLibrary.Definition control) {
        String content='SYNTHETIC DEMONSTRATION EVIDENCE — NOT A REAL COMPLIANCE ASSERTION\n\nControl: '+control.key+'\n'+control.title+
            '\nPrepared for the fictional Nila Bank demonstration.\nOwner: demo control owner.\nEvidence example: documented boundary, test procedure, expected result, observed result, reviewer and date.'+
            '\nSource reference: '+control.clause+'\nSource currency and applicability must be validated by a qualified human before real use.';
        return new ContentVersion(Title='DEMO '+control.key,PathOnClient='DEMO-'+control.key+'.txt',VersionData=Blob.valueOf(content),FirstPublishLocationId=caseId);
    }
    private static AuraHandledException handled(Exception error) {
        String message=error instanceof GovService.GovernanceException ? error.getMessage() : 'The operation failed. Check record access, required fields and the active approval process.';
        AuraHandledException wrapped=new AuraHandledException(message); wrapped.setMessage(message); return wrapped;
    }
}