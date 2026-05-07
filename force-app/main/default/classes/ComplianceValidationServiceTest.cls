/**
 * @description Test class for ComplianceValidationService
 * @group Compliance Framework Tests
 */
@IsTest
private class ComplianceValidationServiceTest {

    @TestSetup
    static void setupTestData() {
        // Create test compliance rules
        List<Compliance_Rule__c> rules = new List<Compliance_Rule__c>();

        rules.add(new Compliance_Rule__c(
            Name__c = 'Block Rule',
            Rule_Type__c = 'Keyword_Match',
            Keywords__c = 'block-keyword',
            Severity__c = 'Critical',
            Action__c = 'Block',
            Target_Object__c = 'Account',
            Target_Field__c = 'Description',
            Remediation_Message__c = 'This content is blocked',
            Is_Active__c = true
        ));

        rules.add(new Compliance_Rule__c(
            Name__c = 'Warn Rule',
            Rule_Type__c = 'Keyword_Match',
            Keywords__c = 'warn-keyword',
            Severity__c = 'High',
            Action__c = 'Warn',
            Target_Object__c = 'Account',
            Target_Field__c = 'Description',
            Remediation_Message__c = 'This content generates a warning',
            Is_Active__c = true
        ));

        rules.add(new Compliance_Rule__c(
            Name__c = 'Log Rule',
            Rule_Type__c = 'Keyword_Match',
            Keywords__c = 'log-keyword',
            Severity__c = 'Low',
            Action__c = 'Log',
            Target_Object__c = 'Account',
            Target_Field__c = 'Description',
            Remediation_Message__c = 'This content is logged',
            Is_Active__c = true
        ));

        insert rules;
    }

    @IsTest
    static void testValidateRecord_BlockViolation() {
        // Arrange
        Account acc = new Account(
            Name = 'Test Account',
            Description = 'This contains block-keyword'
        );
        insert acc;

        // Act
        Test.startTest();
        ComplianceValidationResult result = ComplianceValidationService.validateRecord(acc, 'Description');
        Test.stopTest();

        // Assert
        System.assertEquals(false, result.isValid, 'Should be invalid');
        System.assertEquals('Block', result.action, 'Should block');
        System.assertEquals('Critical', result.severity, 'Should be critical');
        System.assertNotEquals(null, result.message, 'Should have remediation message');

        // Verify alert was created
        List<Compliance_Alert__c> alerts = [
            SELECT Id, Status__c, Severity__c
            FROM Compliance_Alert__c
            WHERE Record_Id__c = :acc.Id
        ];
        System.assertEquals(1, alerts.size(), 'Should create alert');
        System.assertEquals('Open', alerts[0].Status__c, 'Alert should be open');
    }

    @IsTest
    static void testValidateRecord_WarnViolation() {
        // Arrange
        Account acc = new Account(
            Name = 'Test Account',
            Description = 'This contains warn-keyword'
        );
        insert acc;

        // Act
        Test.startTest();
        ComplianceValidationResult result = ComplianceValidationService.validateRecord(acc, 'Description');
        Test.stopTest();

        // Assert
        System.assertEquals(false, result.isValid, 'Should be invalid');
        System.assertEquals('Warn', result.action, 'Should warn');
        System.assertEquals('High', result.severity, 'Should be high severity');
    }

    @IsTest
    static void testValidateRecord_NoViolation() {
        // Arrange
        Account acc = new Account(
            Name = 'Test Account',
            Description = 'This is clean content'
        );
        insert acc;

        // Act
        Test.startTest();
        ComplianceValidationResult result = ComplianceValidationService.validateRecord(acc, 'Description');
        Test.stopTest();

        // Assert
        System.assertEquals(true, result.isValid, 'Should be valid');
    }

    @IsTest
    static void testValidateRecord_NullRecord() {
        // Act
        Test.startTest();
        ComplianceValidationResult result = ComplianceValidationService.validateRecord(null, 'Description');
        Test.stopTest();

        // Assert
        System.assertEquals(true, result.isValid, 'Should handle null record gracefully');
    }

    @IsTest
    static void testValidateRecord_BlankFieldName() {
        // Arrange
        Account acc = new Account(Name = 'Test Account');
        insert acc;

        // Act
        Test.startTest();
        ComplianceValidationResult result = ComplianceValidationService.validateRecord(acc, '');
        Test.stopTest();

        // Assert
        System.assertEquals(true, result.isValid, 'Should handle blank field name gracefully');
    }

    @IsTest
    static void testCreateAlert() {
        // Arrange
        Compliance_Rule__c rule = [
            SELECT Id, Name__c, Severity__c
            FROM Compliance_Rule__c
            WHERE Name__c = 'Block Rule'
            LIMIT 1
        ];

        Account acc = new Account(Name = 'Test Account');
        insert acc;

        // Act
        Test.startTest();
        ComplianceValidationService.createAlert(
            rule,
            acc.Id,
            'Description',
            'Test content with block-keyword',
            'block-keyword',
            null
        );
        Test.stopTest();

        // Assert
        List<Compliance_Alert__c> alerts = [
            SELECT Id, Alert_Name__c, Rule__c, Record_Id__c, Field_Name__c,
                   Severity__c, Status__c, Matched_Content__c
            FROM Compliance_Alert__c
            WHERE Record_Id__c = :acc.Id
        ];

        System.assertEquals(1, alerts.size(), 'Should create 1 alert');
        System.assertEquals(rule.Id, alerts[0].Rule__c, 'Should link to rule');
        System.assertEquals(String.valueOf(acc.Id), alerts[0].Record_Id__c, 'Should link to record');
        System.assertEquals('Description', alerts[0].Field_Name__c, 'Should set field name');
        System.assertEquals('Critical', alerts[0].Severity__c, 'Should set severity');
        System.assertEquals('Open', alerts[0].Status__c, 'Should be open status');
    }

    @IsTest
    static void testCreateAlert_NullParameters() {
        // Act
        Test.startTest();
        ComplianceValidationService.createAlert(null, null, 'Description', 'Test', 'Test', null);
        Test.stopTest();

        // Assert - Should not throw exception
        List<Compliance_Alert__c> alerts = [SELECT Id FROM Compliance_Alert__c];
        System.assertEquals(0, alerts.size(), 'Should not create alert with null parameters');
    }

    @IsTest
    static void testValidateRecords_Bulk() {
        // Arrange
        List<Account> accounts = new List<Account>();
        for (Integer i = 0; i < 50; i++) {
            accounts.add(new Account(
                Name = 'Test Account ' + i,
                Description = i < 25 ? 'block-keyword' : 'Clean content'
            ));
        }
        insert accounts;

        // Act
        Test.startTest();
        Map<Id, ComplianceValidationResult> results = ComplianceValidationService.validateRecords(
            accounts,
            'Description'
        );
        Test.stopTest();

        // Assert
        System.assertEquals(50, results.size(), 'Should validate all records');

        Integer violationCount = 0;
        for (ComplianceValidationResult result : results.values()) {
            if (!result.isValid) {
                violationCount++;
            }
        }
        System.assertEquals(25, violationCount, 'Should find 25 violations');
    }

    @IsTest
    static void testGetOpenAlerts() {
        // Arrange
        Compliance_Rule__c rule = [
            SELECT Id, Name__c, Severity__c, Remediation_Message__c
            FROM Compliance_Rule__c
            WHERE Name__c = 'Block Rule'
            LIMIT 1
        ];

        Account acc = new Account(Name = 'Test Account');
        insert acc;

        // Create multiple alerts
        List<Compliance_Alert__c> alerts = new List<Compliance_Alert__c>();
        alerts.add(new Compliance_Alert__c(
            Alert_Name__c = 'Alert 1',
            Rule__c = rule.Id,
            Record_Id__c = acc.Id,
            Record_Type__c = 'Account',
            Field_Name__c = 'Description',
            Severity__c = 'Critical',
            Status__c = 'Open',
            Alert_Date__c = System.now()
        ));
        alerts.add(new Compliance_Alert__c(
            Alert_Name__c = 'Alert 2',
            Rule__c = rule.Id,
            Record_Id__c = acc.Id,
            Record_Type__c = 'Account',
            Field_Name__c = 'Description',
            Severity__c = 'High',
            Status__c = 'Resolved',
            Alert_Date__c = System.now()
        ));
        insert alerts;

        // Act
        Test.startTest();
        List<Compliance_Alert__c> openAlerts = ComplianceValidationService.getOpenAlerts(acc.Id);
        Test.stopTest();

        // Assert
        System.assertEquals(1, openAlerts.size(), 'Should return only open alerts');
        System.assertEquals('Open', openAlerts[0].Status__c, 'Alert should be open');
    }

    @IsTest
    static void testResolveAlert() {
        // Arrange
        Compliance_Rule__c rule = [
            SELECT Id
            FROM Compliance_Rule__c
            LIMIT 1
        ];

        Account acc = new Account(Name = 'Test Account');
        insert acc;

        Compliance_Alert__c alert = new Compliance_Alert__c(
            Alert_Name__c = 'Test Alert',
            Rule__c = rule.Id,
            Record_Id__c = acc.Id,
            Record_Type__c = 'Account',
            Field_Name__c = 'Description',
            Severity__c = 'High',
            Status__c = 'Open',
            Alert_Date__c = System.now()
        );
        insert alert;

        // Act
        Test.startTest();
        ComplianceValidationService.resolveAlert(alert.Id, 'False positive - content approved');
        Test.stopTest();

        // Assert
        Compliance_Alert__c resolvedAlert = [
            SELECT Id, Status__c, Resolution_Notes__c
            FROM Compliance_Alert__c
            WHERE Id = :alert.Id
        ];
        System.assertEquals('Resolved', resolvedAlert.Status__c, 'Alert should be resolved');
        System.assertEquals('False positive - content approved', resolvedAlert.Resolution_Notes__c, 'Should set resolution notes');
    }

    @IsTest
    static void testValidateRecord_BlockTakesPrecedenceOverWarn() {
        // Arrange
        Account acc = new Account(
            Name = 'Test Account',
            Description = 'This contains both block-keyword and warn-keyword'
        );
        insert acc;

        // Act
        Test.startTest();
        ComplianceValidationResult result = ComplianceValidationService.validateRecord(acc, 'Description');
        Test.stopTest();

        // Assert
        System.assertEquals('Block', result.action, 'Block should take precedence over Warn');
    }

    @IsTest
    static void testCreateAlert_LongTextTruncation() {
        // Arrange
        Compliance_Rule__c rule = [SELECT Id, Name__c, Severity__c FROM Compliance_Rule__c LIMIT 1];
        Account acc = new Account(Name = 'Test Account');
        insert acc;

        String longText = '';
        for (Integer i = 0; i < 5000; i++) {
            longText += 'a';
        }

        // Act
        Test.startTest();
        ComplianceValidationService.createAlert(rule, acc.Id, 'Description', longText, longText, null);
        Test.stopTest();

        // Assert
        Compliance_Alert__c alert = [
            SELECT Id, Original_Value__c, Matched_Content__c
            FROM Compliance_Alert__c
            WHERE Record_Id__c = :acc.Id
            LIMIT 1
        ];
        System.assert(alert.Original_Value__c.length() <= 32000, 'Original value should be truncated');
        System.assert(alert.Matched_Content__c.length() <= 4000, 'Matched content should be truncated');
    }
}
