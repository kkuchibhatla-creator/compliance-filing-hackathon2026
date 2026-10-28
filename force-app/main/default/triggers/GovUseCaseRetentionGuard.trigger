trigger GovUseCaseRetentionGuard on Gov_Use_Case__c (before delete) {
    // Master-detail cascades do not invoke each child's delete trigger.
    Set<Id> retained = new Set<Id>();
    for (AggregateResult row : [SELECT Use_Case__c caseId FROM Gov_Audit__c WHERE Use_Case__c IN :Trigger.oldMap.keySet() GROUP BY Use_Case__c]) {
        retained.add((Id)row.get('caseId'));
    }
    for (Gov_Use_Case__c useCase : Trigger.old) {
        if (retained.contains(useCase.Id)) useCase.addError('This use case has retained governance history and cannot be deleted.');
    }
}