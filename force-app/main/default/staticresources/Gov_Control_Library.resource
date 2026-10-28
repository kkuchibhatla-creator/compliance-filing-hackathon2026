{
  "libraryVersion": "demo-2026.10.28.2",
  "limitations": "Illustrative control set for commercial banks, not a complete legal opinion. Selected RBI mappings use the 2025 commercial-bank outsourcing directions; materiality, exclusions, amendments and other instruments require human review. DPDP items are readiness gates under demo internal policy; check phased commencement and later notifications. Other bank types, securities and insurance require specialist maps. Evidence attachment does not establish compliance.",
  "controls": [
    {
      "key": "GOV-RISK",
      "title": "Structured AI risk assessment",
      "reviewerRole": "AI Risk",
      "scope": "Always",
      "clause": "Demo internal AI risk template v1",
      "sourceUrl": "",
      "legalStatus": "Internal demo policy",
      "dependencies": [
        "Purpose__c",
        "Sector__c",
        "Personal_Data__c",
        "Customer_Facing__c",
        "Cross_Border__c",
        "Cloud_Outsourcing__c",
        "Data_Categories__c",
        "Permitted_Actions__c",
        "Processing_Locations__c",
        "Retention_Days__c",
        "Bank_Type__c",
        "Material_IT_Outsourcing__c"
      ]
    },
    {
      "key": "GOV-ARCH",
      "title": "Architecture and action boundaries",
      "reviewerRole": "Architecture",
      "scope": "Always",
      "clause": "Demo architecture review standard v1",
      "sourceUrl": "",
      "legalStatus": "Internal demo policy",
      "dependencies": [
        "Sector__c",
        "Cloud_Outsourcing__c",
        "Permitted_Actions__c",
        "Processing_Locations__c",
        "Data_Categories__c",
        "Bank_Type__c",
        "Material_IT_Outsourcing__c"
      ]
    },
    {
      "key": "REG-CURRENCY",
      "title": "Regulatory scope, materiality and source currency",
      "reviewerRole": "Compliance",
      "scope": "Always",
      "clause": "Human-verified instrument inventory; bank classification, materiality and exclusions",
      "sourceUrl": "",
      "legalStatus": "Mandatory demo policy gate; confirm sector, materiality, exclusions, commencement and amendments",
      "dependencies": [
        "Sector__c",
        "Personal_Data__c",
        "Customer_Facing__c",
        "Cross_Border__c",
        "Cloud_Outsourcing__c",
        "Permitted_Actions__c",
        "Processing_Locations__c",
        "Bank_Type__c",
        "Material_IT_Outsourcing__c"
      ]
    },
    {
      "key": "RBI-RISK",
      "title": "Document outsourcing risk and accountability",
      "reviewerRole": "Compliance",
      "scope": "CommercialMaterialIT",
      "clause": "RBI commercial-bank outsourcing directions 2025, Chapter IV, paragraphs 60-61",
      "sourceUrl": "https://www.rbi.org.in/Scripts/BS_ViewMasDirections.aspx?id=13139",
      "legalStatus": "2025 commercial-bank instrument; confirm materiality, exclusions and later amendments",
      "dependencies": [
        "Sector__c",
        "Cloud_Outsourcing__c",
        "Purpose__c",
        "Permitted_Actions__c",
        "Bank_Type__c",
        "Material_IT_Outsourcing__c"
      ]
    },
    {
      "key": "RBI-ACCESS",
      "title": "Restrict service-provider access",
      "reviewerRole": "Security",
      "scope": "CommercialMaterialIT",
      "clause": "RBI commercial-bank outsourcing directions 2025, Chapter IV, paragraphs 63-65",
      "sourceUrl": "https://www.rbi.org.in/Scripts/BS_ViewMasDirections.aspx?id=13139",
      "legalStatus": "2025 commercial-bank instrument; confirm materiality, exclusions and later amendments",
      "dependencies": [
        "Sector__c",
        "Cloud_Outsourcing__c",
        "Personal_Data__c",
        "Data_Categories__c",
        "Permitted_Actions__c",
        "Processing_Locations__c",
        "Bank_Type__c",
        "Material_IT_Outsourcing__c"
      ]
    },
    {
      "key": "DPDP-NOTICE",
      "title": "Document processing grounds, notice and consent boundaries",
      "reviewerRole": "Legal",
      "scope": "Personal",
      "clause": "DPDP Act 2023, sections 4-7; G.S.R. 843(E), paragraph (c)",
      "sourceUrl": "https://www.meity.gov.in/static/uploads/2025/11/c56ceae6c383460ca69577428d36828b.pdf",
      "legalStatus": "18-month commencement phase in G.S.R. 843(E); readiness gate under demo policy",
      "dependencies": [
        "Personal_Data__c",
        "Customer_Facing__c",
        "Purpose__c",
        "Data_Categories__c"
      ]
    },
    {
      "key": "DPDP-RETENTION",
      "title": "Justify retention and deletion exceptions",
      "reviewerRole": "Compliance",
      "scope": "Personal",
      "clause": "DPDP Act 2023, section 8(7); Rules 2025, rule 8",
      "sourceUrl": "https://www.meity.gov.in/static/uploads/2025/11/53450e6e5dc0bfa85ebd78686cadad39.pdf",
      "legalStatus": "Phased commencement; distinguish future DPDP readiness from current duties",
      "dependencies": [
        "Personal_Data__c",
        "Purpose__c",
        "Retention_Days__c",
        "Data_Categories__c"
      ]
    },
    {
      "key": "DPDP-SECURITY",
      "title": "Evidence the personal-data safeguards",
      "reviewerRole": "Security",
      "scope": "Personal",
      "clause": "DPDP Act 2023, section 8(5); Rules 2025, rule 6",
      "sourceUrl": "https://www.meity.gov.in/static/uploads/2025/11/53450e6e5dc0bfa85ebd78686cadad39.pdf",
      "legalStatus": "Phased commencement; readiness gate under demo policy",
      "dependencies": [
        "Personal_Data__c",
        "Data_Categories__c",
        "Permitted_Actions__c",
        "Processing_Locations__c"
      ]
    },
    {
      "key": "DPDP-TRANSFER",
      "title": "Assess overseas processing and sector restrictions",
      "reviewerRole": "Legal",
      "scope": "PersonalCrossBorder",
      "clause": "DPDP Act 2023, section 16; Rules 2025, rule 15",
      "sourceUrl": "https://www.meity.gov.in/static/uploads/2025/11/53450e6e5dc0bfa85ebd78686cadad39.pdf",
      "legalStatus": "Phased commencement; no blanket transfer prohibition inferred",
      "dependencies": [
        "Personal_Data__c",
        "Cross_Border__c",
        "Processing_Locations__c",
        "Data_Categories__c"
      ]
    },
    {
      "key": "SEBI-SCOPE",
      "title": "Supply the verified SEBI control map",
      "reviewerRole": "Compliance",
      "scope": "Securities",
      "clause": "Specialist mapping required before clearance",
      "sourceUrl": "",
      "legalStatus": "Coverage gap: specialist mapping required",
      "dependencies": [
        "Sector__c",
        "Purpose__c",
        "Personal_Data__c",
        "Permitted_Actions__c"
      ]
    },
    {
      "key": "IRDAI-SCOPE",
      "title": "Supply the verified IRDAI control map",
      "reviewerRole": "Compliance",
      "scope": "Insurance",
      "clause": "Specialist mapping required before clearance",
      "sourceUrl": "",
      "legalStatus": "Coverage gap: specialist mapping required",
      "dependencies": [
        "Sector__c",
        "Purpose__c",
        "Personal_Data__c",
        "Permitted_Actions__c"
      ]
    }
  ]
}
