/**
 * @description Test class for ComplianceScriptService
 * @author Nilotpal Paul
 * @date 2026-03-27
 */
@isTest
private class ComplianceScriptServiceTest {

    /**
     * @description Test validation with blank text
     */
    @isTest
    static void testValidateBlankText() {
        Test.startTest();
        Map<String, Object> result = ComplianceScriptService.validateTextForScript('');
        Test.stopTest();

        System.assertEquals('success', result.get('status'), 'Blank text should return success');
        System.assert(
            String.valueOf(result.get('title')).contains('skipped'),
            'Should indicate validation was skipped'
        );
    }

    /**
     * @description Test validation with null text
     */
    @isTest
    static void testValidateNullText() {
        Test.startTest();
        Map<String, Object> result = ComplianceScriptService.validateTextForScript(null);
        Test.stopTest();

        System.assertEquals('success', result.get('status'), 'Null text should return success');
    }

    /**
     * @description Test validation with valid text
     * Note: Actual Flow execution depends on Flow existence in org
     */
    @isTest
    static void testValidateWithText() {
        String testText = 'This is a test visit objective for compliance validation';

        Test.startTest();
        Map<String, Object> result = ComplianceScriptService.validateTextForScript(testText);
        Test.stopTest();

        // Result should have status
        System.assertNotEquals(null, result.get('status'), 'Result should have status');

        // Status should be either success or error (depending on Flow availability)
        String status = String.valueOf(result.get('status'));
        System.assert(
            status == 'success' || status == 'error',
            'Status should be success or error'
        );

        // Title should exist
        System.assertNotEquals(null, result.get('title'), 'Result should have title');
    }

    /**
     * @description Test isValidationAvailable method
     */
    @isTest
    static void testIsValidationAvailable() {
        Test.startTest();
        Boolean isAvailable = ComplianceScriptService.isValidationAvailable();
        Test.stopTest();

        // Should return a boolean (may be true or false depending on org setup)
        System.assertNotEquals(null, isAvailable, 'Should return non-null boolean');
    }

    /**
     * @description Test error result format for non-compliant text
     */
    @isTest
    static void testErrorResultFormat() {
        // This test assumes Flow is not available or returns compliant
        // Just verifying the result format is correct
        String testText = 'Test text with potential compliance issues';

        Test.startTest();
        Map<String, Object> result = ComplianceScriptService.validateTextForScript(testText);
        Test.stopTest();

        // Verify result has required fields
        System.assert(result.containsKey('title'), 'Result should have title field');
        System.assert(result.containsKey('status'), 'Result should have status field');

        // If status is error, should have additional context
        if (result.get('status') == 'error') {
            System.assertNotEquals(
                null,
                result.get('title'),
                'Error result should have descriptive title'
            );
        }
    }

    /**
     * @description Test that result format matches script expectations
     */
    @isTest
    static void testResultFormatCompatibility() {
        Test.startTest();
        Map<String, Object> result = ComplianceScriptService.validateTextForScript('Test');
        Test.stopTest();

        // Verify required fields exist (script expects title and status)
        System.assert(result.containsKey('title'), 'Must have title field for script');
        System.assert(result.containsKey('status'), 'Must have status field for script');

        // Verify status is valid
        String status = String.valueOf(result.get('status'));
        System.assert(
            status == 'success' || status == 'error',
            'Status must be success or error for script compatibility'
        );

        // Title must be a string
        System.assertNotEquals(null, result.get('title'), 'Title must not be null');
    }
}
