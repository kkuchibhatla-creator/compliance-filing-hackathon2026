trigger GovAuditGuard on Gov_Audit__c (before update, before delete) {
    for (Gov_Audit__c event : (Trigger.isDelete ? Trigger.old : Trigger.new)) {
        event.addError('Governance audit events are retained. Record a new correction event instead of editing or deleting history.');
    }
}