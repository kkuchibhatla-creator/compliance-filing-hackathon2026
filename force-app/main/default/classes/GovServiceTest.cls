@IsTest
private class GovServiceTest {
    @TestSetup
    static void setupUsers() {
        User builder = makeUser('govbld','Governance Test Builder');
        User observer = makeUser('govobs','Governance Test Observer');
        insert new List<User>{builder,observer};
        PermissionSet permission = [SELECT Id FROM PermissionSet WHERE Name = 'Gov_Builder' LIMIT 1];
        insert new PermissionSetAssignment(AssigneeId=builder.Id,PermissionSetId=permission.Id);
    }
    private static User makeUser(String alias, String lastName) {
        return new User(Alias=alias,LastName=lastName,Email=alias+'@example.invalid',
            Username=alias+'.'+UserInfo.getOrganizationId()+'.'+System.now().getTime()+'@example.invalid',
            ProfileId=UserInfo.getProfileId(),TimeZoneSidKey='Asia/Kolkata',LocaleSidKey='en_IN',
            EmailEncodingKey='UTF-8',LanguageLocaleKey='en_US');
    }
    private static User builder() { return [SELECT Id FROM User WHERE Alias = 'govbld' AND LastName = 'Governance Test Builder' LIMIT 1]; }
    private static Id newCase() {
        return GovController.saveUseCase(JSON.serialize(new Gov_Use_Case__c(Name='Test bank service assistant',Sector__c='Bank',
            Purpose__c='Assist with service requests.',Personal_Data__c=true,Customer_Facing__c=true,
            Cross_Border__c=false,Cloud_Outsourcing__c=true,Bank_Type__c='Commercial Bank',Material_IT_Outsourcing__c=true,Data_Categories__c='Synthetic names and service requests',
            Permitted_Actions__c='Read service requests; human sends responses.',Processing_Locations__c='India',Retention_Days__c=90)));
    }
    private static void supplyEvidence(Id caseId, String omit, Boolean expired) {
        Gov_Use_Case__c useCase=GovService.useCaseById(caseId,false);
        List<ContentVersion> files=new List<ContentVersion>();
        List<GovLibrary.Definition> definitions=new List<GovLibrary.Definition>();
        for (GovLibrary.Definition definition : GovLibrary.catalog().controls) {
            if (GovLibrary.applicable(definition,useCase) && definition.key != omit) {
                definitions.add(definition);
                files.add(new ContentVersion(Title='Synthetic '+definition.key,PathOnClient=definition.key+'.txt',FirstPublishLocationId=caseId,VersionData=Blob.valueOf('Synthetic evidence '+definition.key)));
            }
        }
        insert files;
        List<Gov_Evidence__c> proofs=new List<Gov_Evidence__c>();
        for (Integer i=0; i<files.size(); i++) {
            String snapshot='Synthetic evidence '+definitions[i].key;
            proofs.add(new Gov_Evidence__c(Use_Case__c=caseId,Control_Key__c=definitions[i].key,
                Source_Record_Id__c=files[i].Id,Snapshot__c=snapshot,Content_Hash__c=GovLibrary.digest(snapshot),
                Context_Hash__c=GovLibrary.contextHash(definitions[i],useCase),Expires_On__c=expired ? Date.today().addDays(-1) : Date.today().addDays(90)));
        }
        insert proofs;
    }
    private static Map<String,Id> selfReviewers() {
        Map<String,Id> reviewers=new Map<String,Id>();
        for (String role : GovLibrary.ROLES) reviewers.put(role,UserInfo.getUserId());
        return reviewers;
    }
    private static Gov_Review__c review(Id filingId, String role) {
        return [SELECT Id, Status__c, Prior_Review__c, Scope_Hash__c FROM Gov_Review__c WHERE Filing__c = :filingId AND Reviewer_Role__c = :role LIMIT 1];
    }
    @IsTest
    static void applicabilityUsesDeclaredFacts() {
        Gov_Use_Case__c useCase=new Gov_Use_Case__c(Sector__c='Bank',Bank_Type__c='Commercial Bank',Material_IT_Outsourcing__c=true,Personal_Data__c=false,Cross_Border__c=false,Cloud_Outsourcing__c=true);
        Assert.isTrue(GovLibrary.applicable(GovLibrary.definition('RBI-ACCESS'),useCase));
        Assert.isFalse(GovLibrary.applicable(GovLibrary.definition('DPDP-NOTICE'),useCase));
        useCase.Personal_Data__c=true;
        Assert.isTrue(GovLibrary.applicable(GovLibrary.definition('DPDP-NOTICE'),useCase));
        Assert.isFalse(GovLibrary.applicable(GovLibrary.definition('DPDP-TRANSFER'),useCase));
        useCase.Cross_Border__c=true;
        Assert.isTrue(GovLibrary.applicable(GovLibrary.definition('DPDP-TRANSFER'),useCase));
        useCase.Material_IT_Outsourcing__c=false;
        Assert.isFalse(GovLibrary.applicable(GovLibrary.definition('RBI-ACCESS'),useCase),'Materiality affects this IT-outsourcing rule.');
        useCase.Material_IT_Outsourcing__c=true; useCase.Bank_Type__c='Payments Bank';
        Assert.isFalse(GovLibrary.applicable(GovLibrary.definition('RBI-ACCESS'),useCase),'A different bank class needs its own verified instrument.');
    }
    @IsTest
    static void imagesDocumentsAndOtherFilesPinTheirOriginalBytes() {
        System.runAs(builder()) {
            Id caseId=newCase();
            Blob payload=EncodingUtil.base64Decode('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jK1sAAAAASUVORK5CYII=');
            List<String> paths=new List<String>{'scan.png','photo.jpg','photo.jpeg','policy.pdf','policy.doc','policy.docx','bundle.zip','source.other','without-extension'};
            Id originalVersion;
            Id originalDocument;
            Id originalEvidence;
            Test.startTest();
            for (String path : paths) {
                ContentVersion upload=new ContentVersion(Title='Evidence '+path,PathOnClient=path,VersionData=payload,FirstPublishLocationId=caseId);
                insert upload;
                upload=[SELECT Id, ContentDocumentId, Checksum, ContentSize FROM ContentVersion WHERE Id = :upload.Id];
                Id proofId=GovController.attachEvidence(caseId,'GOV-RISK',upload.ContentDocumentId,Date.today().addDays(30));
                Gov_Evidence__c proof=[SELECT Source_Record_Id__c, Snapshot__c, Content_Hash__c, Hash_Algorithm__c, Context_Hash__c FROM Gov_Evidence__c WHERE Id = :proofId];
                Assert.areEqual(String.valueOf(upload.Id),proof.Source_Record_Id__c,path);
                Assert.areEqual('MD5',proof.Hash_Algorithm__c,path);
                Assert.areEqual(EncodingUtil.convertToHex(Crypto.generateDigest('MD5',payload)),proof.Content_Hash__c,path);
                Map<String,Object> metadata=(Map<String,Object>)JSON.deserializeUntyped(proof.Snapshot__c);
                Assert.areEqual(false,metadata.get('textExtracted'),path);
                Assert.areEqual(String.valueOf(upload.Id),(String)metadata.get('sourceVersion'),path);
                Assert.areEqual('File attachment only',metadata.get('snapshotKind'),path);
                if (originalVersion == null) {
                    originalVersion=upload.Id; originalDocument=upload.ContentDocumentId; originalEvidence=proofId;
                }
            }
            insert new ContentVersion(Title='Replacement scan',PathOnClient='scan.png',ContentDocumentId=originalDocument,VersionData=Blob.valueOf('Different bytes'));
            Test.stopTest();
            Gov_Evidence__c pinned=[SELECT Source_Record_Id__c, Content_Hash__c FROM Gov_Evidence__c WHERE Id = :originalEvidence];
            Assert.areEqual(String.valueOf(originalVersion),pinned.Source_Record_Id__c,'A later file version cannot replace the assessed evidence.');
            Assert.areEqual(EncodingUtil.convertToHex(Crypto.generateDigest('MD5',payload)),pinned.Content_Hash__c);
            Assert.areEqual(paths.size(),[SELECT COUNT() FROM Gov_Audit__c WHERE Use_Case__c = :caseId AND Event__c = 'EVIDENCE_ATTACHED']);
        }
    }
    @IsTest
    static void largeAndNonUtf8TextRemainAvailableAsFiles() {
        System.runAs(builder()) {
            Id caseId=newCase();
            List<Blob> contents=new List<Blob>{Blob.valueOf('Text content '.repeat(4000)),EncodingUtil.convertFromHex('FFFE8000'),Blob.valueOf('   ')};
            Test.startTest();
            for (Blob content : contents) {
                ContentVersion upload=new ContentVersion(Title='Text evidence',PathOnClient='evidence.txt',VersionData=content,FirstPublishLocationId=caseId);
                insert upload;
                upload=[SELECT Id, ContentDocumentId FROM ContentVersion WHERE Id = :upload.Id];
                Id proofId=GovController.attachEvidence(caseId,'GOV-RISK',upload.ContentDocumentId,Date.today().addDays(30));
                Gov_Evidence__c proof=[SELECT Snapshot__c, Hash_Algorithm__c, Content_Hash__c FROM Gov_Evidence__c WHERE Id = :proofId];
                Assert.areEqual('MD5',proof.Hash_Algorithm__c);
                Assert.isTrue(proof.Snapshot__c.contains('Document contents have not been extracted'));
                Assert.areEqual(EncodingUtil.convertToHex(Crypto.generateDigest('MD5',content)),proof.Content_Hash__c);
            }
            Test.stopTest();
        }
    }
    @IsTest
    static void fileUploadsStillRequireTheCorrectCaseAndValidity() {
        System.runAs(builder()) {
            Id caseId=newCase();
            Id otherCase=newCase();
            ContentVersion upload=new ContentVersion(Title='Private scan',PathOnClient='scan.png',VersionData=EncodingUtil.convertFromHex('89504E47FF'),FirstPublishLocationId=otherCase);
            insert upload;
            upload=[SELECT ContentDocumentId FROM ContentVersion WHERE Id = :upload.Id];
            Test.startTest();
            try { GovService.attachEvidence(caseId,'GOV-RISK',upload.ContentDocumentId,Date.today().addDays(30)); Assert.fail('A source linked only to another case must be rejected.'); }
            catch (GovService.GovernanceException error) { Assert.isTrue(error.getMessage().contains('link the evidence')); }
            try { GovService.attachEvidence(otherCase,'GOV-RISK',upload.ContentDocumentId,Date.today().addDays(-1)); Assert.fail('Expired evidence must be rejected.'); }
            catch (GovService.GovernanceException error) { Assert.isTrue(error.getMessage().contains('validity date')); }
            try { GovService.attachEvidence(otherCase,'DPDP-TRANSFER',upload.ContentDocumentId,Date.today().addDays(30)); Assert.fail('An inapplicable control must be rejected.'); }
            catch (GovService.GovernanceException error) { Assert.isTrue(error.getMessage().contains('not applicable')); }
            Test.stopTest();
            Assert.areEqual(0,[SELECT COUNT() FROM Gov_Evidence__c WHERE Use_Case__c IN :new Set<Id>{caseId,otherCase}]);
        }
    }
    @IsTest
    static void evidencePinsAnImmutableSourceVersion() {
        System.runAs(builder()) {
            Id caseId=newCase();
            ContentVersion file=new ContentVersion(Title='Policy',PathOnClient='policy.txt',VersionData=Blob.valueOf('Original policy'),FirstPublishLocationId=caseId); insert file;
            file=[SELECT Id, ContentDocumentId FROM ContentVersion WHERE Id = :file.Id];
            Id evidenceId=GovController.attachEvidence(caseId,'GOV-RISK',file.ContentDocumentId,Date.today().addDays(30));
            insert new ContentVersion(Title='Policy',PathOnClient='policy.txt',ContentDocumentId=file.ContentDocumentId,VersionData=Blob.valueOf('Replacement policy'));
            Gov_Evidence__c proof=[SELECT Id, Source_Record_Id__c, Snapshot__c, Content_Hash__c, Hash_Algorithm__c FROM Gov_Evidence__c WHERE Id = :evidenceId];
            Assert.areEqual('SHA-256',proof.Hash_Algorithm__c);
            Assert.areEqual(String.valueOf(file.Id),proof.Source_Record_Id__c);
            Assert.areEqual('Original policy',proof.Snapshot__c);
            Assert.areEqual(GovLibrary.digest('Original policy'),proof.Content_Hash__c);
            proof.Snapshot__c='Changed';
            Database.SaveResult result=Database.update(proof,false);
            Assert.isFalse(result.isSuccess(),'A filed evidence snapshot cannot be overwritten.');
        }
    }
    @IsTest
    static void missingEvidenceCannotBypassTheClearanceGate() {
        System.runAs(builder()) {
            Id caseId=newCase(); supplyEvidence(caseId,'RBI-ACCESS',false);
            Id filingId=GovService.prepare(caseId);
            GovService.submit(caseId,selfReviewers());
            Gov_Review__c security=review(filingId,'Security');
            try { GovService.decide(security.Id,'Approve','Looks sufficient.'); Assert.fail('Approval must fail with missing evidence.'); }
            catch (GovService.GovernanceException error) { Assert.isTrue(error.getMessage().contains('evidence')); }
            Gov_Review__c architecture=review(filingId,'Architecture');
            ProcessInstanceWorkitem item=[SELECT Id FROM ProcessInstanceWorkitem WHERE ProcessInstance.TargetObjectId = :architecture.Id LIMIT 1];
            Approval.ProcessWorkitemRequest direct=new Approval.ProcessWorkitemRequest(); direct.setWorkitemId(item.Id); direct.setAction('Approve');
            Assert.isTrue(Approval.process(direct).isSuccess());
            GovController.Workspace view=GovController.getWorkspace(caseId);
            Assert.isFalse(view.releaseReady,'Native decisions cannot bypass the aggregate completeness and version gate.');
            Assert.areEqual('Approved',review(filingId,'Architecture').Status__c,'Native decisions are reconciled from the platform records.');
            GovService.decide(security.Id,'Reject','Supply the restricted-access test and owner.');
            Assert.areEqual('Rework',GovService.latestFiling(caseId).Status__c);
            Assert.areEqual(1,[SELECT COUNT() FROM Task WHERE WhatId = :security.Id]);
            Assert.isFalse(GovController.getWorkspace(caseId).releaseReady);
        }
    }
    @IsTest
    static void actualApprovalsClearOnlyTheAssessedScope() {
        System.runAs(builder()) {
            Id caseId=newCase(); supplyEvidence(caseId,null,false);
            Id filingId=GovService.prepare(caseId);
            List<Gov_Review__c> reviews=[SELECT Id FROM Gov_Review__c WHERE Filing__c = :filingId];
            Set<Id> reviewIds=new Map<Id,Gov_Review__c>(reviews).keySet();
            Test.startTest();
            GovService.submit(caseId,selfReviewers());
            Assert.areEqual(5,[SELECT COUNT() FROM ProcessInstance WHERE TargetObjectId IN :reviewIds AND Status = 'Pending']);
            for (Gov_Review__c entry : reviews) GovService.decide(entry.Id,'Approve','Reviewed the pinned evidence and scope.');
            Assert.areEqual(5,[SELECT COUNT() FROM ProcessInstance WHERE TargetObjectId IN :reviewIds AND Status = 'Approved']);
            Assert.isTrue(GovController.getWorkspace(caseId).releaseReady);
            Test.stopTest();
            Gov_Use_Case__c useCase=GovService.useCaseById(caseId,false); useCase.Retention_Days__c=91; GovService.saveCase(useCase);
            Assert.isFalse(GovController.getWorkspace(caseId).releaseReady,'A changed use case cannot reuse the old clearance.');
        }
    }
    @IsTest
    static void selectiveReworkReferencesOriginalHumanDecisions() {
        System.runAs(builder()) {
            Id caseId=newCase(); supplyEvidence(caseId,null,false);
            Id first=GovService.prepare(caseId);
            GovService.submit(caseId,selfReviewers());
            List<Gov_Review__c> entries=[SELECT Id FROM Gov_Review__c WHERE Filing__c = :first];
            Test.startTest();
            for (Gov_Review__c entry : entries) GovService.decide(entry.Id,'Approve','Evidence reviewed.');
            Test.stopTest();
            Gov_Review__c originalSecurity=review(first,'Security');
            Gov_Use_Case__c useCase=GovService.useCaseById(caseId,false); useCase.Retention_Days__c=91; GovService.saveCase(useCase);
            Id second=GovService.prepare(caseId);
            Assert.areNotEqual(first,second);
            Assert.areEqual('Superseded',[SELECT Status__c FROM Gov_Filing__c WHERE Id = :first].Status__c);
            Gov_Review__c carried=review(second,'Security');
            Assert.areEqual('Carried Forward',carried.Status__c);
            Assert.areEqual(originalSecurity.Id,carried.Prior_Review__c,'Carry forward must cite the original human decision.');
            Assert.areEqual('Pending',review(second,'Compliance').Status__c);
            Assert.areEqual('Pending',review(second,'AI Risk').Status__c);
        }
    }
    @IsTest
    static void changedScopePreventsPendingNativeDecision() {
        System.runAs(builder()) {
            Id caseId=newCase(); supplyEvidence(caseId,null,false);
            Id filingId=GovService.prepare(caseId); GovService.submit(caseId,selfReviewers());
            Gov_Review__c legal=review(filingId,'Legal');
            Gov_Use_Case__c useCase=GovService.useCaseById(caseId,false); useCase.Cross_Border__c=true; useCase.Processing_Locations__c='India and an overseas processor'; GovService.saveCase(useCase);
            try { GovService.decide(legal.Id,'Approve','Approved.'); Assert.fail('An outdated work item must fail.'); }
            catch (GovService.GovernanceException error) { Assert.isTrue(error.getMessage().contains('outdated')); }
            Id next=GovService.prepare(caseId);
            Assert.areNotEqual(filingId,next);
            Set<Id> oldReviews=new Map<Id,Gov_Review__c>([SELECT Id FROM Gov_Review__c WHERE Filing__c = :filingId]).keySet();
            Assert.areEqual(0,[SELECT COUNT() FROM ProcessInstanceWorkitem WHERE ProcessInstance.TargetObjectId IN :oldReviews],'Supersession recalls pending work.');
        }
    }
    @IsTest
    static void expiredEvidenceAndUnmappedSectorsFailClosed() {
        System.runAs(builder()) {
            Id caseId=newCase(); supplyEvidence(caseId,null,true); GovService.prepare(caseId);
            Assert.isTrue(GovController.getWorkspace(caseId).blockers > 0);
            Gov_Use_Case__c useCase=GovService.useCaseById(caseId,false); useCase.Sector__c='Insurance'; GovService.saveCase(useCase); GovService.prepare(caseId);
            try { GovService.submit(caseId,selfReviewers()); Assert.fail('Unsupported sector must not receive clearance.'); }
            catch (GovService.GovernanceException error) { Assert.isTrue(error.getMessage().contains('specialist')); }
        }
    }
    @IsTest
    static void missingPermissionAndAgentApprovalAttemptsAreRejected() {
        User observer=[SELECT Id FROM User WHERE Alias = 'govobs' AND LastName = 'Governance Test Observer' LIMIT 1];
        System.runAs(observer) {
            try { GovService.requireManager(); Assert.fail('Unassigned user must not manage governance.'); }
            catch (GovService.GovernanceException error) { Assert.isTrue(error.getMessage().contains('permission')); }
        }
        GovAgentActions.Request request=new GovAgentActions.Request(); request.operation='approve';
        try { GovAgentActions.execute(new List<GovAgentActions.Request>{request}); Assert.fail('The agent action cannot approve.'); }
        catch (GovService.GovernanceException error) { Assert.isTrue(error.getMessage().contains('Supported operations')); }
    }
    @IsTest
    static void syntheticDemoAndAgentActionsUseTheSameFiling() {
        System.runAs(builder()) {
            GovController.Workspace empty=GovController.getWorkspace(null);
            Assert.areEqual(0,empty.useCases.size());
            Id caseId=GovController.seedDemo();
            Assert.areEqual(caseId,GovController.seedDemo(),'Loading the demo again must not duplicate it.');
            Assert.isTrue(GovService.useCaseById(caseId,false).Is_Demo__c);
            Assert.areEqual(1,GovController.getWorkspace(caseId).blockers,'The demo has one intentional evidence gap.');
            Test.startTest();
            GovAgentActions.Request request=new GovAgentActions.Request(); request.useCaseId=caseId; request.operation='inspect';
            GovAgentActions.Result inspected=GovAgentActions.execute(new List<GovAgentActions.Request>{request})[0];
            Assert.isTrue(inspected.structuredAssessment.contains('RBI-ACCESS'));
            request.operation='prepare';
            Assert.isTrue(GovAgentActions.execute(new List<GovAgentActions.Request>{request})[0].outcome.contains('Draft'));
            GovController.attachSyntheticDemoEvidence(caseId,'RBI-ACCESS');
            Id filingId=GovController.prepareFiling(caseId);
            Assert.areEqual(0,GovController.getWorkspace(caseId).blockers);
            GovController.submitFiling(caseId,JSON.serialize(selfReviewers()));
            Gov_Review__c security=review(filingId,'Security');
            GovController.decideReview(security.Id,'Reject','Provide the documented test procedure and observed result.');
            Test.stopTest();
            Assert.areEqual('Rework',GovService.latestFiling(caseId).Status__c);
            try { GovController.saveUseCase('{}'); Assert.fail('Incomplete intake must be rejected at the UI boundary.'); }
            catch (AuraHandledException error) { Assert.isTrue(error.getMessage().contains('Provide a name')); }
        }
    }
}
