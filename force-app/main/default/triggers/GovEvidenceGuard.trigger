trigger GovEvidenceGuard on Gov_Evidence__c (before update, before delete) {
    for (Gov_Evidence__c item : (Trigger.isDelete ? Trigger.old : Trigger.new)) item.addError('Evidence snapshots are retained. Create a replacement snapshot instead of editing or deleting this record.');
}
