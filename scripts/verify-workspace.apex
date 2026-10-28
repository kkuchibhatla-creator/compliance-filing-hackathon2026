Id actor=UserInfo.getUserId();
Gov_Use_Case__c demo=[SELECT Id FROM Gov_Use_Case__c WHERE Is_Demo__c = true AND OwnerId = :actor LIMIT 1];
GovController.Workspace workspace=GovController.getWorkspace(demo.Id);
System.assertEquals(1,workspace.blockers,'The starting demo must expose one missing evidence control.');
System.assertEquals(5,workspace.reviews.size(),'Each filing must create all five reviewer gates.');
System.assertEquals(false,workspace.releaseReady,'The starting demo cannot have release clearance.');
System.assertEquals(true,workspace.isCurrent,'The starting filing must match the declared facts and evidence.');
System.debug(LoggingLevel.INFO,JSON.serialize(new Map<String,Object>{'useCaseId'=>demo.Id,'filingId'=>workspace.filing.Id,'version'=>workspace.filing.Version__c,'blockers'=>workspace.blockers,'reviewGates'=>workspace.reviews.size(),'current'=>workspace.isCurrent,'releaseReady'=>workspace.releaseReady}));
