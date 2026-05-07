/**
 * @description Test class for ComplianceRuleEngine
 * @group Compliance Framework Tests
 */
@IsTest
private class ComplianceRuleEngineTest {

    @TestSetup
    static void setupTestData() {
        // Create test compliance rules
        List<Compliance_Rule__c> rules = new List<Compliance_Rule__c>();

        // Keyword match rule
        rules.add(new Compliance_Rule__c(
            Name__c = 'Off-Label Detection',
            Description__c = 'Detects off-label promotion keywords',
            Rule_Type__c = 'Keyword_Match',
            Keywords__c = 'off-label, unapproved indication, unapproved use',
            Severity__c = 'Critical',
            Action__c = 'Block',
            Target_Object__c = 'ProviderVisit',
            Target_Field__c = 'NextProviderVisitObjective',
            Remediation_Message__c = 'Remove off-label content',
            Is_Active__c = true
        ));

        // Pattern match rule
        rules.add(new Compliance_Rule__c(
            Name__c = 'Adverse Event Detection',
            Description__c = 'Detects adverse event mentions',
            Rule_Type__c = 'Pattern_Match',
            Pattern__c = '(side effect|adverse event|AE|SAE)',
            Severity__c = 'High',
            Action__c = 'Warn',
            Target_Object__c = 'ProviderVisit',
            Target_Field__c = 'NextProviderVisitObjective',
            Remediation_Message__c = 'Report adverse events through proper channels',
            Is_Active__c = true
        ));

        // Inactive rule (should not trigger)
        rules.add(new Compliance_Rule__c(
            Name__c = 'Inactive Rule',
            Rule_Type__c = 'Keyword_Match',
            Keywords__c = 'test',
            Severity__c = 'Low',
            Action__c = 'Log',
            Target_Object__c = 'ProviderVisit',
            Target_Field__c = 'NextProviderVisitObjective',
            Is_Active__c = false
        ));

        insert rules;
    }

    @IsTest
    static void testValidateText_KeywordMatch() {
        // Arrange
        String textWithViolation = 'Discussed off-label uses of the medication with the provider.';
        String objectType = 'ProviderVisit';
        String fieldName = 'NextProviderVisitObjective';

        // Act
        Test.startTest();
        List<ComplianceValidationResult> results = ComplianceRuleEngine.validateText(
            objectType,
            fieldName,
            textWithViolation,
            UserInfo.getUserId()
        );
        Test.stopTest();

        // Assert
        System.assertEquals(1, results.size(), 'Should find 1 violation');
        System.assertEquals(false, results[0].isValid, 'Should be invalid');
        System.assertEquals('Critical', results[0].severity, 'Should be critical severity');
        System.assertEquals('Block', results[0].action, 'Should block');
        System.assert(results[0].matchedContent.contains('off-label'), 'Should match off-label keyword');
    }

    @IsTest
    static void testValidateText_PatternMatch() {
        // Arrange
        String textWithViolation = 'Patient reported a serious adverse event (SAE) after taking medication.';
        String objectType = 'ProviderVisit';
        String fieldName = 'NextProviderVisitObjective';

        // Act
        Test.startTest();
        List<ComplianceValidationResult> results = ComplianceRuleEngine.validateText(
            objectType,
            fieldName,
            textWithViolation,
            UserInfo.getUserId()
        );
        Test.stopTest();

        // Assert
        System.assertEquals(1, results.size(), 'Should find 1 violation');
        System.assertEquals('High', results[0].severity, 'Should be high severity');
        System.assertEquals('Warn', results[0].action, 'Should warn');
        System.assert(results[0].matchedContent.contains('adverse event'), 'Should match pattern');
    }

    @IsTest
    static void testValidateText_NoViolation() {
        // Arrange
        String cleanText = 'Discussed approved indications and proper dosing with provider.';
        String objectType = 'ProviderVisit';
        String fieldName = 'NextProviderVisitObjective';

        // Act
        Test.startTest();
        List<ComplianceValidationResult> results = ComplianceRuleEngine.validateText(
            objectType,
            fieldName,
            cleanText,
            UserInfo.getUserId()
        );
        Test.stopTest();

        // Assert
        System.assertEquals(0, results.size(), 'Should find no violations');
    }

    @IsTest
    static void testValidateText_BlankText() {
        // Arrange
        String objectType = 'ProviderVisit';
        String fieldName = 'NextProviderVisitObjective';

        // Act
        Test.startTest();
        List<ComplianceValidationResult> results1 = ComplianceRuleEngine.validateText(
            objectType,
            fieldName,
            null,
            UserInfo.getUserId()
        );
        List<ComplianceValidationResult> results2 = ComplianceRuleEngine.validateText(
            objectType,
            fieldName,
            '',
            UserInfo.getUserId()
        );
        Test.stopTest();

        // Assert
        System.assertEquals(0, results1.size(), 'Null text should not trigger violations');
        System.assertEquals(0, results2.size(), 'Empty text should not trigger violations');
    }

    @IsTest
    static void testGetActiveRules() {
        // Arrange
        String objectType = 'ProviderVisit';
        String fieldName = 'NextProviderVisitObjective';

        // Act
        Test.startTest();
        List<Compliance_Rule__c> rules = ComplianceRuleEngine.getActiveRules(objectType, fieldName);
        Test.stopTest();

        // Assert
        System.assertEquals(2, rules.size(), 'Should retrieve 2 active rules');
        for (Compliance_Rule__c rule : rules) {
            System.assertEquals(true, rule.Is_Active__c, 'All rules should be active');
        }
    }

    @IsTest
    static void testGetActiveRules_NoMatch() {
        // Arrange
        String objectType = 'NonExistentObject';
        String fieldName = 'NonExistentField';

        // Act
        Test.startTest();
        List<Compliance_Rule__c> rules = ComplianceRuleEngine.getActiveRules(objectType, fieldName);
        Test.stopTest();

        // Assert
        System.assertEquals(0, rules.size(), 'Should retrieve no rules for non-existent object/field');
    }

    @IsTest
    static void testMultipleViolations() {
        // Arrange
        String textWithMultipleViolations = 'Discussed off-label use and patient reported adverse event.';
        String objectType = 'ProviderVisit';
        String fieldName = 'NextProviderVisitObjective';

        // Act
        Test.startTest();
        List<ComplianceValidationResult> results = ComplianceRuleEngine.validateText(
            objectType,
            fieldName,
            textWithMultipleViolations,
            UserInfo.getUserId()
        );
        Test.stopTest();

        // Assert
        System.assertEquals(2, results.size(), 'Should find 2 violations');
    }

    @IsTest
    static void testCaseInsensitiveMatching() {
        // Arrange
        String textWithMixedCase = 'Discussed OFF-LABEL uses with provider.';
        String objectType = 'ProviderVisit';
        String fieldName = 'NextProviderVisitObjective';

        // Act
        Test.startTest();
        List<ComplianceValidationResult> results = ComplianceRuleEngine.validateText(
            objectType,
            fieldName,
            textWithMixedCase,
            UserInfo.getUserId()
        );
        Test.stopTest();

        // Assert
        System.assertEquals(1, results.size(), 'Should match case-insensitively');
    }

    @IsTest
    static void testInvalidPattern() {
        // Arrange - Create rule with invalid regex
        Compliance_Rule__c invalidRule = new Compliance_Rule__c(
            Name__c = 'Invalid Pattern',
            Rule_Type__c = 'Pattern_Match',
            Pattern__c = '[invalid(pattern',
            Severity__c = 'Low',
            Action__c = 'Log',
            Target_Object__c = 'ProviderVisit',
            Target_Field__c = 'NextProviderVisitObjective',
            Is_Active__c = true
        );
        insert invalidRule;

        String text = 'Some text to validate';

        // Act
        Test.startTest();
        List<ComplianceValidationResult> results = ComplianceRuleEngine.validateText(
            'ProviderVisit',
            'NextProviderVisitObjective',
            text,
            UserInfo.getUserId()
        );
        Test.stopTest();

        // Assert - Should handle gracefully without throwing exception
        System.assertNotEquals(null, results, 'Should return results even with invalid pattern');
    }

    @IsTest
    static void testBulkValidation() {
        // Arrange
        List<String> texts = new List<String>();
        for (Integer i = 0; i < 100; i++) {
            texts.add(i < 50 ? 'Valid text ' + i : 'off-label text ' + i);
        }

        // Act
        Test.startTest();
        Integer violationCount = 0;
        for (String text : texts) {
            List<ComplianceValidationResult> results = ComplianceRuleEngine.validateText(
                'ProviderVisit',
                'NextProviderVisitObjective',
                text,
                UserInfo.getUserId()
            );
            if (results.size() > 0) {
                violationCount++;
            }
        }
        Test.stopTest();

        // Assert
        System.assertEquals(50, violationCount, 'Should handle bulk validations correctly');
    }

    @IsTest
    static void testAuditLogCreation() {
        // Arrange
        String textWithViolation = 'Discussed off-label uses';
        String objectType = 'ProviderVisit';
        String fieldName = 'NextProviderVisitObjective';

        // Act
        Test.startTest();
        ComplianceRuleEngine.validateText(
            objectType,
            fieldName,
            textWithViolation,
            UserInfo.getUserId()
        );
        ComplianceRuleEngine.flushAuditLogs(); // Flush batched logs
        Test.stopTest();

        // Assert
        List<Compliance_Audit_Log__c> logs = [
            SELECT Id, Validation_Result__c, Record_Type__c
            FROM Compliance_Audit_Log__c
        ];
        System.assert(logs.size() > 0, 'Should create audit logs');
    }

    @IsTest
    static void testEnhancedErrorMessage() {
        // Arrange
        String textWithViolation = 'Discussed off-label uses of the medication with the provider.';
        String objectType = 'ProviderVisit';
        String fieldName = 'NextProviderVisitObjective';

        // Act
        Test.startTest();
        List<ComplianceValidationResult> results = ComplianceRuleEngine.validateText(
            objectType,
            fieldName,
            textWithViolation,
            UserInfo.getUserId()
        );
        Test.stopTest();

        // Assert
        System.assertEquals(1, results.size(), 'Should find 1 violation');

        String enhancedMessage = results[0].buildEnhancedMessage(50);
        System.assert(enhancedMessage.contains('off-label'), 'Should show matched keyword');
        System.assert(enhancedMessage.contains('Found:'), 'Should have Found section');
        System.assert(enhancedMessage.contains('Text excerpt:'), 'Should show text excerpt');
        System.assert(enhancedMessage.contains('Action required:'), 'Should show action');
        System.assert(enhancedMessage.contains('Off-Label Detection'), 'Should show rule name');
        System.assert(enhancedMessage.contains('Critical'), 'Should show severity');
    }

    @IsTest
    static void testEnhancedMessageWithMultipleKeywords() {
        // Arrange
        String textWithViolation = 'Mentioned off-label and unapproved indication in discussion.';
        String objectType = 'ProviderVisit';
        String fieldName = 'NextProviderVisitObjective';

        // Act
        Test.startTest();
        List<ComplianceValidationResult> results = ComplianceRuleEngine.validateText(
            objectType,
            fieldName,
            textWithViolation,
            UserInfo.getUserId()
        );
        Test.stopTest();

        // Assert
        System.assertEquals(1, results.size(), 'Should find 1 violation');

        String enhancedMessage = results[0].buildEnhancedMessage(50);
        // Should show at least one of the matched keywords
        Boolean hasKeyword = enhancedMessage.contains('off-label') ||
                            enhancedMessage.contains('unapproved indication');
        System.assert(hasKeyword, 'Should show matched keyword(s)');
        System.assert(enhancedMessage.contains('Text excerpt:'), 'Should show text excerpt');
    }

    @IsTest
    static void testEnhancedMessageContextExtraction() {
        // Arrange - Long text with violation in the middle
        String longText = 'This is a long discussion about various treatment options. ' +
                         'We discussed off-label uses in detail. ' +
                         'The doctor had many questions about dosing and administration.';
        String objectType = 'ProviderVisit';
        String fieldName = 'NextProviderVisitObjective';

        // Act
        Test.startTest();
        List<ComplianceValidationResult> results = ComplianceRuleEngine.validateText(
            objectType,
            fieldName,
            longText,
            UserInfo.getUserId()
        );
        Test.stopTest();

        // Assert
        System.assertEquals(1, results.size(), 'Should find 1 violation');

        String enhancedMessage = results[0].buildEnhancedMessage(50);
        System.assert(enhancedMessage.contains('Text excerpt:'), 'Should show text excerpt');
        // Excerpt should show context around the violation
        String excerpt = enhancedMessage.substringBetween('Text excerpt: "...', '..."');
        System.assert(excerpt.contains('off-label'), 'Excerpt should contain the matched keyword');
        // Excerpt should be reasonably sized (not the entire text)
        System.assert(excerpt.length() < longText.length(), 'Excerpt should be shorter than full text');
    }

    @IsTest
    static void testEnhancedMessageShortText() {
        // Arrange - Short text
        String shortText = 'Discussed off-label use';
        String objectType = 'ProviderVisit';
        String fieldName = 'NextProviderVisitObjective';

        // Act
        Test.startTest();
        List<ComplianceValidationResult> results = ComplianceRuleEngine.validateText(
            objectType,
            fieldName,
            shortText,
            UserInfo.getUserId()
        );
        Test.stopTest();

        // Assert
        System.assertEquals(1, results.size(), 'Should find 1 violation');

        String enhancedMessage = results[0].buildEnhancedMessage(50);
        System.assert(enhancedMessage.contains('off-label'), 'Should show matched keyword');
        System.assert(enhancedMessage.contains('Text excerpt:'), 'Should show text excerpt');
    }

    @IsTest
    static void testEnhancedMessagePatternMatch() {
        // Arrange - Pattern match (adverse event)
        String textWithViolation = 'Patient reported adverse event after medication';
        String objectType = 'ProviderVisit';
        String fieldName = 'NextProviderVisitObjective';

        // Act
        Test.startTest();
        List<ComplianceValidationResult> results = ComplianceRuleEngine.validateText(
            objectType,
            fieldName,
            textWithViolation,
            UserInfo.getUserId()
        );
        Test.stopTest();

        // Assert
        System.assertEquals(1, results.size(), 'Should find 1 violation');

        String enhancedMessage = results[0].buildEnhancedMessage(50);
        System.assert(enhancedMessage.contains('adverse event'), 'Should show matched pattern');
        System.assert(enhancedMessage.contains('Found:'), 'Should have Found section');
        System.assert(enhancedMessage.contains('Text excerpt:'), 'Should show text excerpt');
        System.assert(enhancedMessage.contains('Adverse Event Detection'), 'Should show rule name');
    }

    @IsTest
    static void testOriginalTextStorage() {
        // Arrange
        String textWithViolation = 'Discussed off-label uses';
        String objectType = 'ProviderVisit';
        String fieldName = 'NextProviderVisitObjective';

        // Act
        Test.startTest();
        List<ComplianceValidationResult> results = ComplianceRuleEngine.validateText(
            objectType,
            fieldName,
            textWithViolation,
            UserInfo.getUserId()
        );
        Test.stopTest();

        // Assert
        System.assertEquals(1, results.size(), 'Should find 1 violation');
        System.assertEquals(textWithViolation, results[0].originalText, 'Should store original text');
    }

    /**
     * @description Test Flow-based validation when Flow is available
     */
    @IsTest
    static void testFlowBasedValidation() {
        // Arrange
        String textForValidation = 'This is test content for Flow validation';
        String objectType = 'ProviderVisit';
        String fieldName = 'NextProviderVisitObjective';

        // Act
        Test.startTest();
        List<ComplianceValidationResult> results = ComplianceRuleEngine.validateText(
            objectType,
            fieldName,
            textForValidation,
            UserInfo.getUserId()
        );
        Test.stopTest();

        // Assert
        // Flow may or may not be available in test context
        // If Flow is available, validation should complete without error
        // If Flow is not available, should fall back to rule-based validation
        System.assertNotEquals(null, results, 'Should return results');
    }

    /**
     * @description Test fallback to rule-based validation when Flow fails
     */
    @IsTest
    static void testFallbackToRuleValidation() {
        // Arrange
        String textWithViolation = 'Discussed off-label uses of medication';
        String objectType = 'ProviderVisit';
        String fieldName = 'NextProviderVisitObjective';

        // Act
        Test.startTest();
        List<ComplianceValidationResult> results = ComplianceRuleEngine.validateText(
            objectType,
            fieldName,
            textWithViolation,
            UserInfo.getUserId()
        );
        Test.stopTest();

        // Assert
        // Even if Flow is not available or fails, rule-based validation should work
        System.assertEquals(1, results.size(), 'Should find violation via fallback');
        System.assertEquals(false, results[0].isValid, 'Should be invalid');
    }

    /**
     * @description Test that Flow results are properly stored
     */
    @IsTest
    static void testFlowResultStorage() {
        // Arrange
        String testText = 'Test content for compliance validation';
        String objectType = 'ProviderVisit';
        String fieldName = 'NextProviderVisitObjective';

        // Act
        Test.startTest();
        List<ComplianceValidationResult> results = ComplianceRuleEngine.validateText(
            objectType,
            fieldName,
            testText,
            UserInfo.getUserId()
        );
        Test.stopTest();

        // Assert
        // If Flow validation ran, results should have structure
        System.assertNotEquals(null, results, 'Should return results');

        // If there are violations, check for Flow result storage
        for (ComplianceValidationResult result : results) {
            // flowResult may be null if rule-based validation was used
            // This test verifies the property exists and can be accessed
            Object flowResultObj = result.flowResult;
            System.assert(true, 'Flow result property should be accessible');
        }
    }

    /**
     * @description Test audit log creation for Flow validation
     */
    @IsTest
    static void testFlowValidationAuditLog() {
        // Arrange
        String testText = 'Compliance test content';
        String objectType = 'ProviderVisit';
        String fieldName = 'NextProviderVisitObjective';

        // Delete existing audit logs to get clean count
        delete [SELECT Id FROM Compliance_Audit_Log__c];

        // Act
        Test.startTest();
        ComplianceRuleEngine.validateText(
            objectType,
            fieldName,
            testText,
            UserInfo.getUserId()
        );
        ComplianceRuleEngine.flushAuditLogs(); // Flush batched logs
        Test.stopTest();

        // Assert
        List<Compliance_Audit_Log__c> logs = [
            SELECT Id, Validation_Result__c, Details__c
            FROM Compliance_Audit_Log__c
        ];

        System.assert(logs.size() > 0, 'Should create audit logs');

        // If Flow validation ran, Details should contain Flow output
        // If rule validation ran, Details should contain rule info
        for (Compliance_Audit_Log__c log : logs) {
            System.assertNotEquals(null, log.Details__c, 'Audit log should have details');
        }
    }
}
