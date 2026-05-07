#!/bin/bash
set -e

echo "=============================================="
echo " Post-Deployment Verification"
echo "=============================================="
echo ""

TARGET_ORG="${1:-}"
ORG_FLAG=""
if [ -n "$TARGET_ORG" ]; then
    ORG_FLAG="--target-org $TARGET_ORG"
fi

echo "[1] Checking Custom Objects..."
echo "  Compliance Rules:"
sf data query --query "SELECT COUNT() FROM Compliance_Rule__c" $ORG_FLAG
echo "  Compliance Alerts:"
sf data query --query "SELECT COUNT() FROM Compliance_Alert__c" $ORG_FLAG
echo "  Audit Logs:"
sf data query --query "SELECT COUNT() FROM Compliance_Audit_Log__c" $ORG_FLAG
echo ""

echo "[2] Checking Flow Status..."
sf data query --query "SELECT ApiName, ActiveVersionNumber, LatestVersionNumber FROM FlowDefinitionView WHERE ApiName IN ('Visit_Logging_Compliance_Check','ProviderVisit_Compliance_Background_Validation','Visit_Note_Processor_Simple')" $ORG_FLAG
echo ""

echo "[3] Checking Apex Classes..."
sf data query --query "SELECT Name, Status FROM ApexClass WHERE Name LIKE 'Compliance%' OR Name = 'FlowValidationResult' ORDER BY Name" $ORG_FLAG
echo ""

echo "[4] Checking Triggers..."
sf data query --query "SELECT Name, Status FROM ApexTrigger WHERE Name LIKE '%ComplianceTrigger'" $ORG_FLAG
echo ""

echo "[5] Checking Permission Set..."
sf data query --query "SELECT Id, Label FROM PermissionSet WHERE Name = 'Compliance_Framework_Admin'" $ORG_FLAG
echo ""

echo "[6] Checking Rule Configuration..."
sf data query --query "SELECT Name__c, Rule_Type__c, Is_Active__c, Target_Object__c, Target_Field__c, Action__c FROM Compliance_Rule__c ORDER BY Name__c" $ORG_FLAG
echo ""

echo "=============================================="
echo " Verification Complete"
echo "=============================================="
