@IsTest
private class GovAiDraftTest {
    @TestSetup
    static void setupUser() {
        User actor=new User(Alias='govai',LastName='Governance AI Test',Email='govai@example.invalid',
            Username='govai.'+UserInfo.getOrganizationId()+'.'+System.now().getTime()+'@example.invalid',
            ProfileId=UserInfo.getProfileId(),TimeZoneSidKey='Asia/Kolkata',LocaleSidKey='en_IN',EmailEncodingKey='UTF-8',LanguageLocaleKey='en_US');
        insert actor;
        PermissionSet permission=[SELECT Id FROM PermissionSet WHERE Name = 'Gov_Builder' LIMIT 1];
        insert new PermissionSetAssignment(AssigneeId=actor.Id,PermissionSetId=permission.Id);
    }
    private static User actor() { return [SELECT Id FROM User WHERE Alias = 'govai' AND LastName = 'Governance AI Test' LIMIT 1]; }
    private class FakeGateway implements GovAiDraft.Gateway {
        public String seenPrompt;
        public Id changeCase;
        public Boolean fail=false;
        public Boolean empty=false;
        public GovAiDraft.Generation generate(String prompt) {
            seenPrompt=prompt;
            if (fail) throw new GovService.GovernanceException('Simulated model outage');
            if (changeCase != null) update new Gov_Use_Case__c(Id=changeCase,Retention_Days__c=91);
            GovAiDraft.Generation result=new GovAiDraft.Generation();
            result.text=empty ? '' : 'AI-generated draft requiring human verification. RBI-ACCESS has missing evidence. Request the access-control test.';
            result.generationId='synthetic-generation-id';
            return result;
        }
    }
    @IsTest
    static void fileMetadataDoesNotPretendToBeExtractedDocumentContent() {
        System.runAs(actor()) {
            Id caseId=GovController.seedDemo();
            ContentVersion upload=new ContentVersion(Title='Security assessment',PathOnClient='assessment.pdf',VersionData=EncodingUtil.convertFromHex('255044462D312E370AFF'),FirstPublishLocationId=caseId);
            insert upload;
            upload=[SELECT ContentDocumentId FROM ContentVersion WHERE Id = :upload.Id];
            GovController.attachEvidence(caseId,'RBI-ACCESS',upload.ContentDocumentId,Date.today().addDays(30));
            GovController.prepareFiling(caseId);
            FakeGateway fake=new FakeGateway(); GovAiDraft.gateway=fake;
            Test.startTest();
            GovController.generateReviewerDraft(caseId,'Security');
            Test.stopTest();
            Assert.isTrue(fake.seenPrompt.contains('"evidenceTextExtracted":false'));
            Assert.isTrue(fake.seenPrompt.contains('Document contents have not been extracted'));
            Assert.isTrue(fake.seenPrompt.contains('never infer contents or adequacy from a filename or checksum'));
            Assert.areEqual('Draft',GovService.latestFiling(caseId).Status__c);
        }
    }
    @IsTest
    static void generationIsGroundedAndDoesNotApprove() {
        System.runAs(actor()) {
            Id caseId=GovController.seedDemo();
            FakeGateway fake=new FakeGateway(); GovAiDraft.gateway=fake;
            Test.startTest();
            String draft=GovController.generateReviewerDraft(caseId,'Security');
            Test.stopTest();
            Assert.isTrue(fake.seenPrompt.contains('RBI-ACCESS'));
            Assert.isTrue(fake.seenPrompt.contains('Missing'));
            Assert.isTrue(fake.seenPrompt.contains('untrusted DATA'));
            Gov_Filing__c filing=GovService.latestFiling(caseId);
            Gov_Review__c review=[SELECT Status__c, AI_Draft__c, AI_Generation_Id__c FROM Gov_Review__c WHERE Filing__c = :filing.Id AND Reviewer_Role__c = 'Security'];
            Assert.areEqual('Draft',filing.Status__c);
            Assert.areEqual('Pending',review.Status__c);
            Assert.areEqual(draft,review.AI_Draft__c);
            Assert.isTrue(draft.contains('Recorded source references'));
            Assert.isTrue(draft.contains('RBI-ACCESS | Missing | No evidence source attached'));
            Assert.isTrue(draft.contains('DPDP-SECURITY | Evidence attached | Evidence '));
            Assert.areEqual('synthetic-generation-id',review.AI_Generation_Id__c);
            Assert.areEqual(1,[SELECT COUNT() FROM Gov_Audit__c WHERE Use_Case__c = :caseId AND Event__c = 'AI_DRAFT_GENERATED']);
        }
    }
    @IsTest
    static void changedScopeDiscardsTheModelOutput() {
        System.runAs(actor()) {
            Id caseId=GovController.seedDemo();
            FakeGateway fake=new FakeGateway(); fake.changeCase=caseId; GovAiDraft.gateway=fake;
            Test.startTest();
            try { GovAiDraft.generate(caseId,'Compliance'); Assert.fail('Concurrent scope change must invalidate the generation.'); }
            catch (GovService.GovernanceException error) { Assert.isTrue(error.getMessage().contains('scope changed')); }
            Test.stopTest();
            Gov_Filing__c filing=GovService.latestFiling(caseId);
            Assert.areEqual(0,[SELECT COUNT() FROM Gov_Review__c WHERE Filing__c = :filing.Id AND AI_Generation_Id__c != null]);
            Assert.areEqual(0,[SELECT COUNT() FROM Gov_Audit__c WHERE Use_Case__c = :caseId AND Event__c = 'AI_DRAFT_GENERATED']);
        }
    }
    @IsTest
    static void failuresAndInvalidRolesNeverProduceDecisions() {
        System.runAs(actor()) {
            Id caseId=GovController.seedDemo();
            FakeGateway fake=new FakeGateway(); fake.fail=true; GovAiDraft.gateway=fake;
            Test.startTest();
            try { GovAiDraft.generate(caseId,'Legal'); Assert.fail('Model outage must be reported.'); }
            catch (GovService.GovernanceException error) { Assert.isTrue(error.getMessage().contains('unavailable')); }
            fake.fail=false; fake.empty=true;
            try { GovAiDraft.generate(caseId,'Legal'); Assert.fail('Empty output must be rejected.'); }
            catch (GovService.GovernanceException error) { Assert.isTrue(error.getMessage().contains('usable')); }
            try { GovAiDraft.generate(caseId,'Unknown'); Assert.fail('Unknown role must be rejected.'); }
            catch (GovService.GovernanceException error) { Assert.isTrue(error.getMessage().contains('supported reviewer')); }
            Test.stopTest();
            Assert.areEqual('Draft',GovService.latestFiling(caseId).Status__c);
        }
    }
    @IsTest
    static void filedAndOutdatedVersionsCannotBeRedrafted() {
        System.runAs(actor()) {
            Id caseId=GovController.seedDemo();
            Gov_Use_Case__c useCase=GovService.useCaseById(caseId,false); useCase.Retention_Days__c=91; GovService.saveCase(useCase);
            FakeGateway fake=new FakeGateway(); GovAiDraft.gateway=fake;
            Test.startTest();
            try { GovAiDraft.generate(caseId,'Legal'); Assert.fail('An outdated assessment cannot be used for generation.'); }
            catch (GovService.GovernanceException error) { Assert.isTrue(error.getMessage().contains('scope changed')); }
            // Filing now requires complete, current evidence; repair both the deliberate demo gap and the changed retention dependencies.
            GovController.attachSyntheticDemoEvidence(caseId,'RBI-ACCESS');
            GovController.attachSyntheticDemoEvidence(caseId,'GOV-RISK');
            GovController.attachSyntheticDemoEvidence(caseId,'DPDP-RETENTION');
            GovController.prepareFiling(caseId);
            Map<String,Id> reviewers=new Map<String,Id>();
            for (String role : GovLibrary.ROLES) reviewers.put(role,UserInfo.getUserId());
            GovService.submit(caseId,reviewers);
            try { GovAiDraft.generate(caseId,'Legal'); Assert.fail('A filed brief must remain stable during review.'); }
            catch (GovService.GovernanceException error) { Assert.isTrue(error.getMessage().contains('before submitting')); }
            Test.stopTest();
            Assert.isNull(fake.seenPrompt,'Generation must not start for invalid filing states.');
        }
    }
}