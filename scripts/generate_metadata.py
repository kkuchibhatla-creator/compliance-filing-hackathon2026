"""Generate the repetitive Salesforce source metadata for Gov."""
from pathlib import Path
from xml.sax.saxutils import escape
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1] / 'force-app/main/default'
NS = 'http://soap.sforce.com/2006/04/metadata'


def write(path, body):
    target = ROOT / path
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text('<?xml version="1.0" encoding="UTF-8"?>\n' + body + '\n')


def field(obj, name, kind='Text', **opts):
    label = opts.pop('label', name.replace('_', ' '))
    body = f'<fullName>{name}__c</fullName><label>{escape(label)}</label><type>{kind}</type>'
    if kind == 'Text':
        body += f'<length>{opts.pop("length", 255)}</length>'
    elif kind == 'LongTextArea':
        body += '<length>32768</length><visibleLines>5</visibleLines>'
    elif kind == 'Checkbox':
        body += '<defaultValue>false</defaultValue>'
    elif kind == 'Number':
        body += '<precision>9</precision><scale>0</scale>'
    elif kind in ('MasterDetail', 'Lookup'):
        target = opts.pop('target')
        body += f'<referenceTo>{target}</referenceTo><relationshipLabel>{escape(opts.get("relationship", obj))}</relationshipLabel><relationshipName>{opts.get("relationship", obj)}</relationshipName>'
        if kind == 'MasterDetail':
            body += '<reparentableMasterDetail>false</reparentableMasterDetail><writeRequiresMasterRead>false</writeRequiresMasterRead>'
        else:
            constraint = 'SetNull' if target in ('User', f'Gov_{obj}__c') else 'Restrict'
            body += f'<deleteConstraint>{constraint}</deleteConstraint>'
    elif kind == 'Picklist':
        values = opts.pop('values')
        body += '<valueSet><restricted>true</restricted><valueSetDefinition><sorted>false</sorted>'
        for i, value in enumerate(values):
            body += f'<value><fullName>{escape(value)}</fullName><default>{str(i == 0).lower()}</default><label>{escape(value)}</label></value>'
        body += '</valueSetDefinition></valueSet>'
    write(f'objects/Gov_{obj}__c/fields/{name}__c.field-meta.xml', f'<CustomField xmlns="{NS}">{body}</CustomField>')


objects = {
    'Use_Case': 'Use case', 'Filing': 'Governance filing', 'Evidence': 'Evidence snapshot',
    'Control': 'Control assessment', 'Review': 'Reviewer sign-off', 'Audit': 'Audit event'
}
for obj, label in objects.items():
    name_field = '<type>Text</type><label>Use case name</label>' if obj == 'Use_Case' else f'<type>AutoNumber</type><label>{label} number</label><displayFormat>AST-{{00000}}</displayFormat>'
    sharing = 'Private' if obj == 'Use_Case' else 'ControlledByParent'
    write(f'objects/Gov_{obj}__c/Gov_{obj}__c.object-meta.xml', f'''<CustomObject xmlns="{NS}">
<deploymentStatus>Deployed</deploymentStatus><enableActivities>{str(obj == 'Review').lower()}</enableActivities><enableReports>true</enableReports>
<label>{label}</label><nameField>{name_field}</nameField><pluralLabel>{label}s</pluralLabel><sharingModel>{sharing}</sharingModel>
</CustomObject>''')

for name in ('Purpose', 'Data_Categories', 'Permitted_Actions', 'Processing_Locations'):
    field('Use_Case', name, 'LongTextArea')
field('Use_Case', 'Sector', 'Picklist', values=['Bank', 'Securities', 'Insurance'])
field('Use_Case', 'Bank_Type', 'Picklist', values=['Commercial Bank', 'Small Finance Bank', 'Payments Bank', 'Regional Rural Bank', 'Other'])
for name in ('Personal_Data', 'Customer_Facing', 'Cross_Border', 'Cloud_Outsourcing'):
    field('Use_Case', name, 'Checkbox')
field('Use_Case', 'Is_Demo', 'Checkbox')
field('Use_Case', 'Material_IT_Outsourcing', 'Checkbox')
field('Use_Case', 'Retention_Days', 'Number')

for obj in ('Filing', 'Evidence', 'Audit'):
    field(obj, 'Use_Case', 'MasterDetail', target='Gov_Use_Case__c', relationship=obj+'s')
for obj in ('Control', 'Review'):
    field(obj, 'Filing', 'MasterDetail', target='Gov_Filing__c', relationship=obj+'s')
for name in ('Version',):
    field('Filing', name, 'Number')
field('Filing', 'Status', 'Picklist', values=['Draft', 'In Review', 'Rework', 'Approved', 'Superseded'])
for name in ('Input_Hash', 'Manifest_Hash'):
    field('Filing', name, length=64)
for name in ('Snapshot', 'Executive_Summary', 'Risk_Assessment'):
    field('Filing', name, 'LongTextArea')
field('Filing', 'Risk_Level', 'Picklist', values=['Low', 'Moderate', 'High'])
field('Filing', 'Library_Version', length=80)

for name in ('Control_Key', 'Context_Hash', 'Content_Hash', 'Source_Record_Id'):
    field('Evidence', name, length=64 if name != 'Source_Record_Id' else 18)
field('Evidence', 'Snapshot', 'LongTextArea')
field('Evidence', 'Hash_Algorithm', length=16)
field('Evidence', 'Expires_On', 'Date')

for name, length in [('Control_Key', 64), ('Title', 255), ('Reviewer_Role', 80), ('Source_URL', 255), ('Clause', 255), ('Legal_Status', 255), ('Context_Hash', 64)]:
    field('Control', name, length=length)
field('Control', 'Explanation', 'LongTextArea')
field('Control', 'Evidence', 'Lookup', target='Gov_Evidence__c', relationship='Control_Assessments')
field('Control', 'Status', 'Picklist', values=['Missing', 'Evidence attached', 'Not applicable', 'Stale', 'Expired'])
field('Control', 'Applicable', 'Checkbox')

roles = ['AI Risk', 'Architecture', 'Legal', 'Compliance', 'Security']
field('Review', 'Reviewer_Role', 'Picklist', values=roles)
field('Review', 'Approver', 'Lookup', target='User', relationship='Gov_Reviews')
field('Review', 'Status', 'Picklist', values=['Pending', 'Approved', 'Rejected', 'Carried Forward'])
for name in ('Brief', 'Rationale'):
    field('Review', name, 'LongTextArea')
field('Review', 'AI_Draft', 'LongTextArea')
field('Review', 'AI_Generation_Id', length=255)
field('Review', 'Scope_Hash', length=64)
field('Review', 'Prior_Review', 'Lookup', target='Gov_Review__c', relationship='Successor_Reviews')
field('Review', 'Decision_At', 'DateTime')
field('Review', 'Decision_By', 'Lookup', target='User', relationship='Gov_Decisions')

field('Audit', 'Filing', 'Lookup', target='Gov_Filing__c', relationship='Audit_Events')
field('Audit', 'Event', length=80)
field('Audit', 'Details', 'LongTextArea')

for permission, label in [('Gov_Manage', 'Manage compliance filings'), ('Gov_Review', 'Review compliance filings')]:
    write(f'customPermissions/{permission}.customPermission-meta.xml', f'<CustomPermission xmlns="{NS}"><label>{label}</label></CustomPermission>')

for role in ('Builder', 'Reviewer'):
    permissions = f'<customPermissions><enabled>true</enabled><name>Gov_Review</name></customPermissions>'
    if role == 'Builder':
        permissions += '<customPermissions><enabled>true</enabled><name>Gov_Manage</name></customPermissions>'
    for cls in ('GovController', 'GovAgentActions'):
        permissions += f'<classAccesses><apexClass>{cls}</apexClass><enabled>true</enabled></classAccesses>'
    for obj in objects:
        edit = obj == 'Use_Case' and role == 'Builder'
        permissions += f'<objectPermissions><allowCreate>{str(edit).lower()}</allowCreate><allowDelete>false</allowDelete><allowEdit>{str(edit).lower()}</allowEdit><allowRead>true</allowRead><modifyAllRecords>false</modifyAllRecords><object>Gov_{obj}__c</object><viewAllRecords>false</viewAllRecords></objectPermissions>'
        for path in sorted((ROOT / f'objects/Gov_{obj}__c/fields').glob('*.xml')):
            name = path.name.split('.')[0]
            if '<type>MasterDetail</type>' in path.read_text():
                continue  # Master-detail permissions follow object access.
            permissions += f'<fieldPermissions><editable>{str(edit and name != "Is_Demo__c").lower()}</editable><field>Gov_{obj}__c.{name}</field><readable>true</readable></fieldPermissions>'
    permissions += '<tabSettings><tab>Gov</tab><visibility>Visible</visibility></tabSettings>'
    permission_root = ET.fromstring(f'<PermissionSet xmlns="{NS}">{permissions}<label>Compliance Filing {role}</label></PermissionSet>')
    permission_root[:] = sorted(permission_root, key=lambda item: item.tag)
    ET.register_namespace('', NS)
    write(f'permissionsets/Gov_{role}.permissionset-meta.xml', ET.tostring(permission_root, encoding='unicode'))

write('tabs/Gov.tab-meta.xml', f'<CustomTab xmlns="{NS}"><label>Compliance Filing</label><lwcComponent>complianceFilingWorkspace</lwcComponent><motif>Custom63: Chip</motif></CustomTab>')
write('applications/Gov.app-meta.xml', f'<CustomApplication xmlns="{NS}"><description>Agentforce governance filing workspace</description><formFactors>Large</formFactors><label>Compliance Filing</label><navType>Standard</navType><tabs>Gov</tabs><uiType>Lightning</uiType></CustomApplication>')

actions = ''
for action, value in [('Approve_Review', 'Approved'), ('Reject_Review', 'Rejected')]:
    actions += f'<fieldUpdates><fullName>{action}</fullName><field>Status__c</field><literalValue>{value}</literalValue><name>{action.replace("_", " ")}</name><notifyAssignee>false</notifyAssignee><operation>Literal</operation><protected>false</protected><reevaluateOnChange>false</reevaluateOnChange></fieldUpdates>'
write('workflows/Gov_Review__c.workflow-meta.xml', f'<Workflow xmlns="{NS}">{actions}</Workflow>')
write('approvalProcesses/Gov_Review__c.Gov_Human_Signoff.approvalProcess-meta.xml', f'''<ApprovalProcess xmlns="{NS}">
<active>true</active><allowRecall>true</allowRecall><allowedSubmitters><type>creator</type></allowedSubmitters>
<approvalPageFields><field>Name</field><field>Reviewer_Role__c</field><field>Brief__c</field><field>Filing__c</field></approvalPageFields>
<approvalStep><allowDelegate>false</allowDelegate><assignedApprover><approver><name>Approver__c</name><type>relatedUserField</type></approver><whenMultipleApprovers>FirstResponse</whenMultipleApprovers></assignedApprover><label>Human sign-off</label><name>Human_Signoff</name><rejectBehavior><type>RejectRequest</type></rejectBehavior></approvalStep>
<entryCriteria><criteriaItems><field>Gov_Review__c.Status__c</field><operation>equals</operation><value>Pending</value></criteriaItems></entryCriteria>
<finalApprovalActions><action><name>Approve_Review</name><type>FieldUpdate</type></action></finalApprovalActions><finalApprovalRecordLock>false</finalApprovalRecordLock>
<finalRejectionActions><action><name>Reject_Review</name><type>FieldUpdate</type></action></finalRejectionActions><finalRejectionRecordLock>false</finalRejectionRecordLock>
<label>Compliance filing human sign-off</label><processOrder>1</processOrder><recordEditability>AdminOnly</recordEditability><showApprovalHistory>true</showApprovalHistory>
</ApprovalProcess>''')

for cls in ('GovLibrary', 'GovService', 'GovController', 'GovAgentActions', 'GovServiceTest', 'GovAiDraft', 'GovAiDraftTest'):
    write(f'classes/{cls}.cls-meta.xml', f'<ApexClass xmlns="{NS}"><apiVersion>65.0</apiVersion><status>Active</status></ApexClass>')
for trigger in ('GovEvidenceGuard',):
    write(f'triggers/{trigger}.trigger-meta.xml', f'<ApexTrigger xmlns="{NS}"><apiVersion>65.0</apiVersion><status>Active</status></ApexTrigger>')
print('Generated Salesforce objects, permissions, approval workflow, and app metadata.')
