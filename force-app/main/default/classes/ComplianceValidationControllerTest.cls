@IsTest
private class ComplianceValidationControllerTest {

    @TestSetup
    static void setupData() {
        Compliance_Rule__c rule = new Compliance_Rule__c(
            Name__c = 'Test Block Rule',
            Description__c = 'Test rule for blocking',
            Rule_Type__c = 'Keyword_Match',
            Keywords__c = 'off-label,unapproved',
            Severity__c = 'Critical',
            Action__c = 'Block',
            Target_Object__c = 'ProviderVisit',
            Target_Field__c = 'NextProviderVisitObjective',
            Is_Active__c = true,
            Remediation_Message__c = 'Remove off-label references.'
        );
        insert rule;

        Compliance_Rule__c warnRule = new Compliance_Rule__c(
            Name__c = 'Test Warn Rule',
            Description__c = 'Test rule for warnings',
            Rule_Type__c = 'Keyword_Match',
            Keywords__c = 'competitor product',
            Severity__c = 'Medium',
            Action__c = 'Warn',
            Target_Object__c = 'ProviderVisit',
            Target_Field__c = 'NextProviderVisitObjective',
            Is_Active__c = true,
            Remediation_Message__c = 'Avoid competitor mentions.'
        );
        insert warnRule;
    }

    @IsTest
    static void testValidateObjective_Compliant() {
        Map<String, Object> result = ComplianceValidationController.validateObjective(
            null, 'Discuss approved treatment options with Dr. Smith'
        );
        System.assertEquals(true, result.get('isCompliant'), 'Clean text should be compliant');
    }

    @IsTest
    static void testValidateObjective_BlockingViolation() {
        Map<String, Object> result = ComplianceValidationController.validateObjective(
            null, 'Discuss off-label usage of the drug with the doctor'
        );
        System.assertEquals(false, result.get('isCompliant'), 'Off-label text should be non-compliant');
        System.assertEquals('rules', result.get('source'));
    }

    @IsTest
    static void testValidateObjective_Warning() {
        Map<String, Object> result = ComplianceValidationController.validateObjective(
            null, 'Compare our drug with competitor product offering'
        );
        System.assertNotEquals(null, result, 'Result should not be null');
        // With LLM Flow active, result may be non-compliant (LLM caught it)
        // or compliant-with-warning (rules caught it, LLM passed). Both are valid.
        Boolean isCompliant = (Boolean) result.get('isCompliant');
        if (isCompliant) {
            Boolean hasWarning = result.get('hasWarning') != null ? (Boolean) result.get('hasWarning') : false;
            System.assert(hasWarning, 'Compliant result should have warning flag');
        }
    }

    @IsTest
    static void testValidateObjective_BlankText() {
        Map<String, Object> result = ComplianceValidationController.validateObjective(null, '');
        System.assertEquals(true, result.get('isCompliant'));
        System.assertEquals('No content to validate', result.get('status'));
    }

    @IsTest
    static void testValidateObjective_ShortText() {
        Map<String, Object> result = ComplianceValidationController.validateObjective(null, 'Hi');
        System.assertEquals(true, result.get('isCompliant'));
    }

    @IsTest
    static void testGetVisitObjective() {
        Map<String, Object> result = ComplianceValidationController.getVisitObjective(null);
        System.assertNotEquals(null, result);
    }
}
