public with sharing class GovService {
    public class GovernanceException extends Exception {}

    public static void requireManager() {
        if (!FeatureManagement.checkPermission('Gov_Manage')) throw new GovernanceException('Compliance Filing Builder permission is required.');
    }
    public static Gov_Use_Case__c useCaseById(Id caseId, Boolean lockRecord) {
        String query = 'SELECT Id, OwnerId, Is_Demo__c, Name, Purpose__c, Sector__c, Personal_Data__c, Customer_Facing__c, ' +
            'Cross_Border__c, Cloud_Outsourcing__c, Bank_Type__c, Material_IT_Outsourcing__c, Data_Categories__c, Permitted_Actions__c, Processing_Locations__c, Retention_Days__c ' +
            'FROM Gov_Use_Case__c WHERE Id = :caseId' + (lockRecord ? ' FOR UPDATE' : '');
        List<Gov_Use_Case__c> rows = Database.queryWithBinds(query, new Map<String,Object>{'caseId'=>caseId}, AccessLevel.USER_MODE);
        if (rows.isEmpty()) throw new GovernanceException('Use case unavailable or access denied.');
        return rows[0];
    }
    public static Gov_Use_Case__c editableCase(Id caseId) {
        requireManager();
        Gov_Use_Case__c record = useCaseById(caseId, true);
        Id userId = UserInfo.getUserId();
        List<UserRecordAccess> access = [SELECT RecordId, HasEditAccess FROM UserRecordAccess WHERE UserId = :userId AND RecordId = :caseId];
        if (access.isEmpty() || !access[0].HasEditAccess) throw new GovernanceException('Edit access to this use case is required.');
        return record;
    }
    public static Gov_Filing__c latestFiling(Id caseId) {
        List<Gov_Filing__c> records = [
            SELECT Id, Name, Use_Case__c, Version__c, Status__c, Input_Hash__c, Manifest_Hash__c,
                Snapshot__c, Executive_Summary__c, Risk_Assessment__c, Risk_Level__c, Library_Version__c, CreatedDate
            FROM Gov_Filing__c WHERE Use_Case__c = :caseId WITH USER_MODE ORDER BY Version__c DESC LIMIT 1
        ];
        return records.isEmpty() ? null : records[0];
    }
    public static List<Gov_Evidence__c> evidence(Id caseId) {
        return [SELECT Id, Name, Control_Key__c, Source_Record_Id__c, Snapshot__c, Content_Hash__c, Hash_Algorithm__c, Context_Hash__c, Expires_On__c, CreatedDate
            FROM Gov_Evidence__c WHERE Use_Case__c = :caseId WITH USER_MODE ORDER BY CreatedDate DESC, Id DESC];
    }
    public static List<Gov_Control__c> controls(Gov_Use_Case__c useCase) {
        Map<String,Gov_Evidence__c> newest = new Map<String,Gov_Evidence__c>();
        Set<Id> sourceIds = new Set<Id>();
        for (Gov_Evidence__c item : evidence(useCase.Id)) {
            if (!newest.containsKey(item.Control_Key__c)) {
                newest.put(item.Control_Key__c, item);
                if (item.Source_Record_Id__c != null) sourceIds.add((Id)item.Source_Record_Id__c);
            }
        }
        // Evidence links pin immutable ContentVersion IDs; removed or inaccessible sources fail closed.
        Set<Id> visibleSources = new Map<Id,ContentVersion>([
            SELECT Id FROM ContentVersion WHERE Id IN :sourceIds WITH USER_MODE
        ]).keySet();
        List<Gov_Control__c> result = new List<Gov_Control__c>();
        for (GovLibrary.Definition item : GovLibrary.catalog().controls) {
            Boolean applies = GovLibrary.applicable(item, useCase);
            String context = GovLibrary.contextHash(item, useCase);
            Gov_Evidence__c proof = newest.get(item.key);
            String status = 'Missing';
            String explanation = 'Applies because of the declared ' + item.scope + ' scope. Attach a versioned evidence file; a human must assess its adequacy.';
            if (!applies) {
                status = 'Not applicable';
                explanation = 'The declared use case does not match the ' + item.scope + ' applicability rule. This is a scoped rule result, subject to reviewer confirmation.';
            } else if (proof != null) {
                if (proof.Context_Hash__c != context || !visibleSources.contains((Id)proof.Source_Record_Id__c)) {
                    status = 'Stale'; explanation = 'Relevant inputs changed or the pinned source is unavailable. Supply evidence for the current scope.';
                } else if (proof.Expires_On__c == null || proof.Expires_On__c < Date.today()) {
                    status = 'Expired'; explanation = 'The evidence validity date has passed. Supply a replacement snapshot.';
                } else {
                    status = 'Evidence attached'; explanation = 'An exact source version and its recorded checksum are linked. Attachment is not a finding of legal compliance.';
                }
            }
            result.add(new Gov_Control__c(
                Control_Key__c=item.key, Title__c=item.title, Reviewer_Role__c=item.reviewerRole,
                Source_URL__c=item.sourceUrl, Clause__c=item.clause, Legal_Status__c=item.legalStatus,
                Applicable__c=applies, Status__c=status, Context_Hash__c=context, Explanation__c=explanation,
                Evidence__c=applies && proof != null ? proof.Id : null
            ));
        }
        return result;
    }
    public static String manifest(List<Gov_Control__c> controls) {
        List<String> parts = new List<String>();
        for (Gov_Control__c control : controls) parts.add(control.Control_Key__c + '|' + control.Status__c + '|' + control.Context_Hash__c + '|' + String.valueOf(control.Evidence__c));
        return GovLibrary.digest(JSON.serialize(parts));
    }
    public static Boolean current(Gov_Filing__c filing, Gov_Use_Case__c useCase, List<Gov_Control__c> controls) {
        return filing != null && filing.Status__c != 'Superseded' && filing.Input_Hash__c == GovLibrary.inputHash(useCase) &&
            filing.Library_Version__c == GovLibrary.catalog().libraryVersion && filing.Manifest_Hash__c == manifest(controls);
    }
    public static Integer missingCount(List<Gov_Control__c> controls, String role) {
        Integer count = 0;
        for (Gov_Control__c item : controls) if (item.Applicable__c && item.Status__c != 'Evidence attached' && (role == null || role == 'AI Risk' || role == item.Reviewer_Role__c)) count++;
        return count;
    }
    public static void audit(Id caseId, Id filingId, String event, Map<String,Object> details) {
        // Business decision inputs, source references and outcomes; no private model reasoning.
        insert new Gov_Audit__c(Use_Case__c=caseId, Filing__c=filingId, Event__c=event, Details__c=JSON.serialize(details));
    }
    public static Id saveCase(Gov_Use_Case__c input) {
        requireManager();
        if (String.isBlank(input.Name) || String.isBlank(input.Purpose__c) || String.isBlank(input.Permitted_Actions__c) || String.isBlank(input.Processing_Locations__c)) {
            throw new GovernanceException('Provide a name, purpose, permitted actions and processing locations.');
        }
        if (input.Retention_Days__c == null || input.Retention_Days__c < 1 || input.Retention_Days__c > 36500) throw new GovernanceException('Retention must be between 1 and 36,500 days.');
        if (input.Personal_Data__c && String.isBlank(input.Data_Categories__c)) throw new GovernanceException('Describe the personal-data categories.');
        if (input.Sector__c == 'Bank' && String.isBlank(input.Bank_Type__c)) throw new GovernanceException('Classify the bank type before assessing regulatory applicability.');
        if (input.Material_IT_Outsourcing__c && !input.Cloud_Outsourcing__c) throw new GovernanceException('Material IT outsourcing requires the IT/cloud outsourcing scope signal.');
        for (String name : new List<String>{'Purpose__c','Permitted_Actions__c','Processing_Locations__c','Data_Categories__c'}) {
            String value = (String)input.get(name);
            if (value != null && value.length() > 2000) throw new GovernanceException('Keep each intake description within 2,000 characters.');
        }
        // Copy only intake fields; client-supplied fields never control governance state.
        Gov_Use_Case__c clean = new Gov_Use_Case__c();
        for (String name : GovLibrary.INPUT_FIELDS) clean.put(name, input.get(name));
        if (input.Id != null) { editableCase(input.Id); clean.Id = input.Id; update as user clean; }
        else { insert as user clean; }
        audit(clean.Id, null, 'INTAKE_SAVED', new Map<String,Object>{'inputHash'=>GovLibrary.inputHash(clean), 'actor'=>UserInfo.getUserId()});
        return clean.Id;
    }
    public static Id attachEvidence(Id caseId, String key, Id documentId, Date expiresOn) {
        Gov_Use_Case__c useCase = editableCase(caseId);
        GovLibrary.Definition definition = GovLibrary.definition(key);
        if (!GovLibrary.applicable(definition, useCase)) throw new GovernanceException('This control is not applicable to the declared scope.');
        if (expiresOn == null || expiresOn < Date.today()) throw new GovernanceException('Choose an evidence validity date today or later.');
        List<ContentDocumentLink> linked = [SELECT Id FROM ContentDocumentLink WHERE ContentDocumentId = :documentId AND LinkedEntityId = :caseId WITH USER_MODE LIMIT 1];
        if (linked.isEmpty()) throw new GovernanceException('Upload and link the evidence file to this use case first.');
        List<ContentVersion> versions = [SELECT Id, Title, ContentSize, FileExtension, ContentLocation, Checksum FROM ContentVersion WHERE ContentDocumentId = :documentId AND IsLatest = true WITH USER_MODE LIMIT 1];
        if (versions.isEmpty() || versions[0].ContentLocation != 'S') {
            throw new GovernanceException('Upload the original evidence file to Salesforce Files; external links cannot be snapshotted.');
        }
        ContentVersion version = versions[0];
        // Native Files stores the bytes. Never load arbitrary binaries into the synchronous Apex heap.
        String snapshot;
        String contentHash;
        String hashAlgorithm = 'MD5';
        if (version.FileExtension != null && version.FileExtension.toLowerCase() == 'txt' && version.ContentSize <= 20000) {
            ContentVersion textVersion = [SELECT VersionData FROM ContentVersion WHERE Id = :version.Id WITH USER_MODE];
            try { snapshot = textVersion.VersionData.toString(); }
            catch (Exception error) { snapshot = null; } // Non-UTF-8 text is still retained as a file attachment.
            if (!String.isBlank(snapshot)) {
                contentHash = EncodingUtil.convertToHex(Crypto.generateDigest('SHA-256', textVersion.VersionData));
                hashAlgorithm = 'SHA-256';
            }
        }
        if (hashAlgorithm == 'MD5') {
            if (String.isBlank(version.Checksum)) {
                throw new GovernanceException('The file was uploaded, but its Salesforce checksum is not available yet. Retry the evidence snapshot after the file finishes processing.');
            }
            contentHash = version.Checksum.toLowerCase();
            snapshot = JSON.serializePretty(new Map<String,Object>{
                'snapshotKind'=>'File attachment only', 'sourceVersion'=>version.Id,
                'title'=>version.Title, 'fileExtension'=>version.FileExtension, 'sizeBytes'=>version.ContentSize,
                'checksumAlgorithm'=>'MD5', 'checksum'=>contentHash, 'textExtracted'=>false,
                'reviewInstructions'=>'Document contents have not been extracted. Open the pinned original file to review its contents. Do not infer evidence adequacy from the filename or checksum.'
            });
        }
        Gov_Evidence__c item = new Gov_Evidence__c(Use_Case__c=caseId, Control_Key__c=key, Source_Record_Id__c=version.Id,
            Snapshot__c=snapshot, Content_Hash__c=contentHash, Hash_Algorithm__c=hashAlgorithm,
            Context_Hash__c=GovLibrary.contextHash(definition,useCase), Expires_On__c=expiresOn);
        insert item;
        audit(caseId, null, 'EVIDENCE_ATTACHED', new Map<String,Object>{'evidenceId'=>item.Id,'sourceVersion'=>version.Id,'control'=>key,
            'contentHash'=>item.Content_Hash__c,'hashAlgorithm'=>hashAlgorithm,'textExtracted'=>hashAlgorithm == 'SHA-256',
            'fileExtension'=>version.FileExtension,'sizeBytes'=>version.ContentSize,'contextHash'=>item.Context_Hash__c,'validThrough'=>expiresOn});
        return item.Id;
    }
    public static Id prepare(Id caseId) {
        Gov_Use_Case__c useCase = editableCase(caseId);
        reconcileNativeDecisions(caseId);
        List<Gov_Control__c> assessed = controls(useCase);
        Gov_Filing__c previous = latestFiling(caseId);
        if (current(previous, useCase, assessed)) return previous.Id;
        Map<String,Gov_Review__c> priorByRole = new Map<String,Gov_Review__c>();
        if (previous != null) {
            for (Gov_Review__c prior : [SELECT Id, Reviewer_Role__c, Scope_Hash__c, Status__c, Prior_Review__c, Approver__c FROM Gov_Review__c WHERE Filing__c = :previous.Id WITH USER_MODE]) priorByRole.put(prior.Reviewer_Role__c,prior);
            recallPending(previous.Id);
            previous.Status__c = 'Superseded'; update previous;
        }
        Integer signals = (useCase.Personal_Data__c ? 1 : 0) + (useCase.Customer_Facing__c ? 1 : 0) + (useCase.Cross_Border__c ? 2 : 0);
        String risk = signals >= 3 ? 'High' : (signals >= 1 ? 'Moderate' : 'Low');
        Map<String,Object> snapshot = new Map<String,Object>();
        for (String name : GovLibrary.INPUT_FIELDS) snapshot.put(name,useCase.get(name));
        Gov_Filing__c filing = new Gov_Filing__c(Use_Case__c=caseId, Version__c=previous == null ? 1 : previous.Version__c + 1,
            Status__c='Draft', Input_Hash__c=GovLibrary.inputHash(useCase), Manifest_Hash__c=manifest(assessed),
            Snapshot__c=JSON.serialize(snapshot), Library_Version__c=GovLibrary.catalog().libraryVersion, Risk_Level__c=risk,
            Risk_Assessment__c=JSON.serialize(new Map<String,Object>{'method'=>'demo policy v1; human confirmation required','riskLevel'=>risk,'personalData'=>useCase.Personal_Data__c,'customerFacing'=>useCase.Customer_Facing__c,'crossBorder'=>useCase.Cross_Border__c,'actionBoundary'=>useCase.Permitted_Actions__c,'dataCategories'=>useCase.Data_Categories__c,'retentionDays'=>useCase.Retention_Days__c,'missingEvidence'=>missingCount(assessed,null)}),
            Executive_Summary__c=useCase.Name + '\nPurpose: ' + useCase.Purpose__c + '\nProposed risk tier: ' + risk + ' (demo policy; reviewer confirmation required).\nOutstanding evidence controls: ' + missingCount(assessed,null) + '.\nFive human review gates. Clearance is limited to this exact filing scope.\n' + GovLibrary.catalog().limitations);
        insert filing;
        for (Gov_Control__c control : assessed) control.Filing__c=filing.Id;
        insert assessed;
        List<Gov_Review__c> reviews = new List<Gov_Review__c>();
        for (String role : GovLibrary.ROLES) {
            String scopeHash = GovLibrary.roleHash(role,useCase,assessed);
            Gov_Review__c prior = priorByRole.get(role);
            Boolean carry = prior != null && (prior.Status__c == 'Approved' || prior.Status__c == 'Carried Forward') && prior.Scope_Hash__c == scopeHash;
            Gov_Review__c review = new Gov_Review__c(Filing__c=filing.Id, Reviewer_Role__c=role,
                Status__c=carry ? 'Carried Forward' : 'Pending', Scope_Hash__c=scopeHash, Brief__c=brief(role,useCase,assessed),
                Prior_Review__c=carry ? (prior.Prior_Review__c == null ? prior.Id : prior.Prior_Review__c) : null,
                Approver__c=carry ? prior.Approver__c : null,
                Rationale__c=carry ? 'References a prior human approval. The role-specific input and evidence scope is unchanged; no new human decision is asserted.' : null);
            reviews.add(review);
        }
        insert reviews;
        audit(caseId,filing.Id,'FILING_PREPARED',new Map<String,Object>{'version'=>filing.Version__c,'inputHash'=>filing.Input_Hash__c,'manifestHash'=>filing.Manifest_Hash__c,'libraryVersion'=>filing.Library_Version__c,'priorFiling'=>previous == null ? null : previous.Id});
        return filing.Id;
    }
    private static String brief(String role, Gov_Use_Case__c useCase, List<Gov_Control__c> controls) {
        List<String> lines = new List<String>{role + ' review | ' + useCase.Name, 'Purpose: '+useCase.Purpose__c,
            'Declared actions: '+useCase.Permitted_Actions__c, 'Processing locations: '+useCase.Processing_Locations__c,
            'Evidence requiring attention: '+missingCount(controls,role), 'Assess the linked evidence and record an explicit decision.'};
        for (Gov_Control__c control : controls) {
            if (role == 'AI Risk' || control.Reviewer_Role__c == role) lines.add(control.Control_Key__c + ' — ' + control.Title__c + ' | ' + control.Status__c + '\n' + control.Clause__c + '\n' + control.Legal_Status__c + '\nEvidence: ' + control.Evidence__c);
        }
        lines.add('Prepared from structured records using a deterministic template. Generative brief enrichment is not enabled in this starter.');
        return String.join(lines,'\n\n');
    }
    private static void recallPending(Id filingId) {
        Set<Id> reviewIds = new Map<Id,Gov_Review__c>([SELECT Id FROM Gov_Review__c WHERE Filing__c = :filingId]).keySet();
        for (ProcessInstanceWorkitem item : [SELECT Id FROM ProcessInstanceWorkitem WHERE ProcessInstance.TargetObjectId IN :reviewIds]) {
            Approval.ProcessWorkitemRequest request = new Approval.ProcessWorkitemRequest();
            request.setWorkitemId(item.Id); request.setAction('Removed'); request.setComments('Filing superseded; a new version will be assessed.');
            Approval.ProcessResult result = Approval.process(request);
            if (!result.isSuccess()) throw new GovernanceException('Recall the prior pending approvals as their submitter before preparing a new filing.');
        }
    }
    public static void submit(Id caseId, Map<String,Id> approvers) {
        Gov_Use_Case__c useCase = editableCase(caseId);
        if (useCase.Sector__c != 'Bank' || useCase.Bank_Type__c != 'Commercial Bank') throw new GovernanceException('This starter supports commercial banks. Add a verified specialist control library for the selected sector or bank type before submission.');
        Gov_Filing__c filing = latestFiling(caseId);
        List<Gov_Control__c> assessed = controls(useCase);
        if (!current(filing,useCase,assessed)) throw new GovernanceException('Inputs or evidence changed. Prepare the current filing first.');
        if (filing.Status__c != 'Draft') throw new GovernanceException('Only a prepared draft can be filed. Rework requires a new evidence or input version.');
        List<Gov_Review__c> pending = [SELECT Id, Approver__c, Reviewer_Role__c FROM Gov_Review__c WHERE Filing__c = :filing.Id AND Status__c = 'Pending' WITH USER_MODE];
        Set<Id> assigned = new Set<Id>();
        for (Gov_Review__c review : pending) {
            Id approver = approvers == null ? null : approvers.get(review.Reviewer_Role__c);
            if (approver == null) throw new GovernanceException('Assign a reviewer to every pending gate.');
            review.Approver__c=approver; assigned.add(approver);
        }
        if ([SELECT COUNT() FROM User WHERE Id IN :assigned AND IsActive = true] != assigned.size()) throw new GovernanceException('Each approver must be an active Salesforce user.');
        Set<Id> permitted=new Set<Id>();
        for (PermissionSetAssignment assignment : [SELECT AssigneeId FROM PermissionSetAssignment
            WHERE AssigneeId IN :assigned AND PermissionSet.Name IN ('Gov_Builder','Gov_Reviewer')]) permitted.add(assignment.AssigneeId);
        if (permitted.size() != assigned.size()) throw new GovernanceException('Assign the Compliance Filing Reviewer or Builder permission set to every reviewer before filing.');
        update pending;
        List<Gov_Use_Case__Share> shares = new List<Gov_Use_Case__Share>();
        Set<Id> sharedWith = new Set<Id>{useCase.OwnerId};
        for (Gov_Use_Case__Share share : [SELECT UserOrGroupId FROM Gov_Use_Case__Share WHERE ParentId = :caseId AND UserOrGroupId IN :assigned]) sharedWith.add(share.UserOrGroupId);
        for (Id assignee : assigned) if (!sharedWith.contains(assignee)) shares.add(new Gov_Use_Case__Share(ParentId=caseId,UserOrGroupId=assignee,AccessLevel='Read',RowCause=Schema.Gov_Use_Case__Share.RowCause.Manual));
        if (!shares.isEmpty()) insert shares;
        filing.Status__c='In Review'; update filing;
        for (Gov_Review__c review : pending) {
            Approval.ProcessSubmitRequest request = new Approval.ProcessSubmitRequest();
            request.setObjectId(review.Id); request.setProcessDefinitionNameOrId('Gov_Human_Signoff');
            request.setComments('COMPLIANCE FILING filing '+filing.Id+'; scope and evidence are version-bound.');
            Approval.ProcessResult result = Approval.process(request);
            if (!result.isSuccess()) throw new GovernanceException('Salesforce could not file the approval request. Check the active Gov approval process and reviewer permissions.');
        }
        audit(caseId,filing.Id,'FILED_FOR_HUMAN_SIGNOFF',new Map<String,Object>{'nativeApprovalRequests'=>pending.size(),'reviewerIds'=>assigned});
    }
    public static void decide(Id reviewId, String decision, String rationale) {
        if (!FeatureManagement.checkPermission('Gov_Review')) throw new GovernanceException('Compliance Filing Reviewer permission is required.');
        if (decision != 'Approve' && decision != 'Reject') throw new GovernanceException('Choose Approve or Reject.');
        if (String.isBlank(rationale) || rationale.length() > 3000) throw new GovernanceException('Record a rationale of 1 to 3,000 characters.');
        Gov_Review__c review = [SELECT Id, Filing__c, Filing__r.Use_Case__c, Reviewer_Role__c FROM Gov_Review__c WHERE Id = :reviewId WITH USER_MODE];
        Gov_Use_Case__c useCase = useCaseById(review.Filing__r.Use_Case__c,true);
        Gov_Filing__c filing = latestFiling(useCase.Id);
        List<Gov_Control__c> assessed = controls(useCase);
        if (filing == null || filing.Id != review.Filing__c || !current(filing,useCase,assessed)) throw new GovernanceException('This approval scope is outdated. Prepare and submit a new filing.');
        if (decision == 'Approve' && missingCount(assessed,review.Reviewer_Role__c) > 0) throw new GovernanceException('Resolve missing, stale or expired evidence for this gate before approval.');
        Id actor = UserInfo.getUserId();
        List<ProcessInstanceWorkitem> items = [SELECT Id FROM ProcessInstanceWorkitem WHERE ProcessInstance.TargetObjectId = :reviewId AND ActorId = :actor LIMIT 1];
        if (items.isEmpty()) throw new GovernanceException('Only the assigned native approval reviewer can decide this work item.');
        Approval.ProcessWorkitemRequest request = new Approval.ProcessWorkitemRequest();
        request.setWorkitemId(items[0].Id); request.setAction(decision); request.setComments(rationale);
        Approval.ProcessResult result = Approval.process(request);
        if (!result.isSuccess()) throw new GovernanceException('The native approval decision failed. Refresh and check its current status.');
        reconcileNativeDecisions(useCase.Id);
    }
    public static void reconcileNativeDecisions(Id caseId) {
        // Do not depend on approval field updates invoking Apex triggers. Native ProcessInstance
        // and ProcessInstanceStep are the authority, including decisions made in Salesforce's own UI.
        Gov_Use_Case__c useCase=useCaseById(caseId,true);
        Gov_Filing__c filing=latestFiling(caseId);
        if (filing == null || filing.Status__c == 'Superseded' || filing.Status__c == 'Draft') return;
        Map<Id,Gov_Review__c> reviews=new Map<Id,Gov_Review__c>([
            SELECT Id, Status__c, Reviewer_Role__c, Decision_At__c, Decision_By__c, Rationale__c
            FROM Gov_Review__c WHERE Filing__c = :filing.Id WITH USER_MODE
        ]);
        Set<Id> reviewIds=reviews.keySet();
        Set<Id> seen=new Set<Id>();
        List<Gov_Review__c> updates=new List<Gov_Review__c>();
        List<Gov_Audit__c> events = new List<Gov_Audit__c>();
        List<Task> tasks=new List<Task>();
        for (ProcessInstance instance : [SELECT Id, TargetObjectId, Status, CompletedDate, LastActorId,
            (SELECT Comments, ActorId FROM Steps ORDER BY CreatedDate DESC LIMIT 1)
            FROM ProcessInstance WHERE TargetObjectId IN :reviewIds ORDER BY CreatedDate DESC]) {
            if (seen.contains(instance.TargetObjectId)) continue;
            seen.add(instance.TargetObjectId);
            if (instance.Status != 'Approved' && instance.Status != 'Rejected') continue;
            Gov_Review__c review=reviews.get(instance.TargetObjectId);
            String comments=instance.Steps.isEmpty() ? null : instance.Steps[0].Comments;
            if (review.Decision_At__c == instance.CompletedDate && review.Status__c == instance.Status && review.Decision_By__c == instance.LastActorId) continue;
            review.Status__c=instance.Status; review.Decision_At__c=instance.CompletedDate;
            review.Decision_By__c=instance.LastActorId; review.Rationale__c=comments;
            updates.add(review);
            events.add(new Gov_Audit__c(Use_Case__c=caseId,Filing__c=filing.Id,Event__c='NATIVE_REVIEW_DECISION',
                Details__c=JSON.serialize(new Map<String,Object>{'reviewId'=>review.Id,'nativeProcessId'=>instance.Id,
                    'role'=>review.Reviewer_Role__c,'status'=>instance.Status,'actor'=>instance.LastActorId,'rationale'=>comments,'completedAt'=>instance.CompletedDate})));
            if (instance.Status == 'Rejected') tasks.add(new Task(Subject='Compliance filing rework: '+review.Reviewer_Role__c,
                WhatId=review.Id,OwnerId=useCase.OwnerId,Status='Not Started',Priority='High',Description=comments,ActivityDate=Date.today().addDays(1)));
        }
        if (!updates.isEmpty()) {
            update updates; insert events;
            if (!tasks.isEmpty()) insert tasks;
        }
        Boolean allApproved=reviews.size() == 5; Boolean rejected=false;
        for (Gov_Review__c review : reviews.values()) {
            allApproved=allApproved && (review.Status__c == 'Approved' || review.Status__c == 'Carried Forward');
            rejected=rejected || review.Status__c == 'Rejected';
        }
        String status=rejected ? 'Rework' : (allApproved ? 'Approved' : 'In Review');
        if (status != filing.Status__c) { filing.Status__c=status; update filing; }
    }
}
