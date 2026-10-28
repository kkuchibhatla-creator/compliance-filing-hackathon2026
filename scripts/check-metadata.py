"""Check metadata XML and the references used by the versioned control library."""
import json
from pathlib import Path
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / 'force-app/main/default'
NS = {'m': 'http://soap.sforce.com/2006/04/metadata'}
files = list(SOURCE.rglob('*.xml'))
for path in files:
    ET.parse(path)

catalog = json.loads((SOURCE / 'staticresources/Gov_Control_Library.resource').read_text())
fields = {p.name.split('.')[0] for p in (SOURCE / 'objects/Gov_Use_Case__c/fields').glob('*.xml')} | {'Name'}
keys = set()
roles = {'AI Risk', 'Architecture', 'Legal', 'Compliance', 'Security'}
scopes = {'Always', 'CommercialMaterialIT', 'Personal', 'PersonalCrossBorder', 'Securities', 'Insurance'}
for control in catalog['controls']:
    assert control['key'] not in keys, f'Duplicate control: {control["key"]}'
    keys.add(control['key'])
    assert control['reviewerRole'] in roles
    assert control['scope'] in scopes
    assert set(control['dependencies']) <= fields, f'Unknown dependency: {control["key"]}'
    assert not control['sourceUrl'] or control['sourceUrl'].startswith('https://')
    assert control['legalStatus'], 'Each control must disclose its source/commencement status.'

for permission_file in (SOURCE / 'permissionsets').glob('*.xml'):
    permissions = ET.parse(permission_file).getroot()
    for field in permissions.findall('m:fieldPermissions', NS):
        reference = field.find('m:field', NS).text
        obj, name = reference.split('.')
        assert (SOURCE / f'objects/{obj}/fields/{name}.field-meta.xml').exists(), reference
        if obj != 'Gov_Use_Case__c' or name == 'Is_Demo__c':
            assert field.find('m:editable', NS).text == 'false', f'Governance state must not be client-editable: {reference}'

print(f'Validated {len(files)} XML files and {len(keys)} control definitions. No server-side metadata validation is implied.')
