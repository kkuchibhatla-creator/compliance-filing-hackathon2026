Id actor=UserInfo.getUserId();
Gov_Use_Case__c demo=[SELECT Id FROM Gov_Use_Case__c WHERE Is_Demo__c = true AND OwnerId = :actor LIMIT 1];
String draft=GovController.generateReviewerDraft(demo.Id,'Security');
System.assert(draft.contains('Recorded source references'),'The real draft must contain the system source ledger.');
System.assert(draft.contains('RBI-ACCESS | Missing | No evidence source attached'),'Missing evidence must remain explicit.');
System.assert(draft.contains('DPDP-SECURITY | Evidence attached | Evidence '),'Attached evidence must retain its source identifier.');
System.debug(LoggingLevel.INFO,'Native AI draft generated for synthetic demo. Character count: '+draft.length());
System.debug(LoggingLevel.INFO,draft);
