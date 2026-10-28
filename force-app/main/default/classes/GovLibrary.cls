public with sharing class GovLibrary {
    public static final List<String> ROLES = new List<String>{'AI Risk','Architecture','Legal','Compliance','Security'};
    public static final List<String> INPUT_FIELDS = new List<String>{
        'Name','Purpose__c','Sector__c','Personal_Data__c','Customer_Facing__c','Cross_Border__c',
        'Cloud_Outsourcing__c','Bank_Type__c','Material_IT_Outsourcing__c','Data_Categories__c','Permitted_Actions__c','Processing_Locations__c','Retention_Days__c'
    };
    private static Catalog cached;
    public class Catalog {
        public String libraryVersion;
        public String limitations;
        public List<Definition> controls;
    }
    public class Definition {
        public String key;
        public String title;
        public String reviewerRole;
        public String scope;
        public String clause;
        public String sourceUrl;
        public String legalStatus;
        public List<String> dependencies;
    }
    public static Catalog catalog() {
        if (cached == null) {
            // Static resources are deployed, non-customer configuration, not user data.
            StaticResource resource = [SELECT Body FROM StaticResource WHERE Name = 'Gov_Control_Library' LIMIT 1];
            cached = (Catalog) JSON.deserialize(resource.Body.toString(), Catalog.class);
        }
        return cached;
    }
    public static Definition definition(String key) {
        for (Definition item : catalog().controls) if (item.key == key) return item;
        throw new GovService.GovernanceException('Unknown control. Refresh the workspace.');
    }
    public static Boolean applicable(Definition item, Gov_Use_Case__c useCase) {
        switch on item.scope {
            when 'Always' { return true; }
            when 'CommercialMaterialIT' { return useCase.Sector__c == 'Bank' && useCase.Bank_Type__c == 'Commercial Bank' && useCase.Cloud_Outsourcing__c && useCase.Material_IT_Outsourcing__c; }
            when 'Personal' { return useCase.Personal_Data__c; }
            when 'PersonalCrossBorder' { return useCase.Personal_Data__c && useCase.Cross_Border__c; }
            when 'Securities' { return useCase.Sector__c == 'Securities'; }
            when 'Insurance' { return useCase.Sector__c == 'Insurance'; }
            when else { throw new GovService.GovernanceException('Unsupported applicability rule: ' + item.scope); }
        }
    }
    public static String digest(String value) {
        return EncodingUtil.convertToHex(Crypto.generateDigest('SHA-256', Blob.valueOf(value)));
    }
    public static String inputHash(Gov_Use_Case__c useCase) {
        return fieldsHash(useCase, INPUT_FIELDS);
    }
    public static String contextHash(Definition item, Gov_Use_Case__c useCase) {
        // Include the rule contents so an accidentally unchanged version label cannot hide a changed clause or dependency.
        return digest(catalog().libraryVersion + '|' + JSON.serialize(item) + '|' + fieldsHash(useCase, item.dependencies));
    }
    public static String fieldsHash(Gov_Use_Case__c useCase, List<String> fields) {
        List<String> sorted = new List<String>(); sorted.addAll(fields); sorted.sort();
        List<String> parts = new List<String>();
        for (String name : sorted) parts.add(name + ':' + JSON.serialize(useCase.get(name)));
        return digest(JSON.serialize(parts));
    }
    public static String roleHash(String role, Gov_Use_Case__c useCase, List<Gov_Control__c> controls) {
        Set<String> fields = new Set<String>{'Sector__c'};
        if (role == 'AI Risk') fields.addAll(INPUT_FIELDS);
        List<String> parts = new List<String>{catalog().libraryVersion, role};
        for (Definition item : catalog().controls) {
            if (item.reviewerRole == role) fields.addAll(item.dependencies);
        }
        for (Gov_Control__c control : controls) {
            if (control.Reviewer_Role__c == role || role == 'AI Risk') {
                parts.add(control.Control_Key__c + '|' + control.Status__c + '|' + String.valueOf(control.Evidence__c) + '|' + control.Context_Hash__c);
            }
        }
        parts.add(fieldsHash(useCase, new List<String>(fields)));
        return digest(JSON.serialize(parts));
    }
}