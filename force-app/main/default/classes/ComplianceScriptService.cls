/**
 * @description Service class for compliance validation from custom scripts
 * Provides a simplified interface for Visit Engagement script validation
 * @author Nilotpal Paul
 * @date 2026-03-27
 */
public with sharing class ComplianceScriptService {

    /**
     * @description Validate text content for compliance (invocable from custom scripts)
     * Returns a simplified result object compatible with script validation format
     * @param textContent The text to validate
     * @return Map with validation result in script-compatible format
     */
    @AuraEnabled
    public static Map<String, Object> validateTextForScript(String textContent) {
        Map<String, Object> scriptResult = new Map<String, Object>();

        try {
            // Handle empty input
            if (String.isBlank(textContent)) {
                scriptResult.put('title', 'Compliance validation skipped - no content provided');
                scriptResult.put('status', 'success');
                return scriptResult;
            }

            // Check if Flow validation is available
            if (!ComplianceFlowService.isFlowValidationAvailable()) {
                scriptResult.put('title', 'Compliance validation skipped - Flow not available');
                scriptResult.put('status', 'success');
                return scriptResult;
            }

            // Invoke the compliance Flow
            FlowValidationResult flowResult = ComplianceFlowService.invokeComplianceFlow(
                textContent,
                'Visit_Logging_Compliance_Check'
            );

            // Convert Flow result to script format
            if (flowResult.isCompliant) {
                scriptResult.put('title', 'Compliance validation passed');
                scriptResult.put('status', 'success');
            } else {
                // Non-compliant: return error with formatted message
                scriptResult.put('title', flowResult.getErrorMessage());
                scriptResult.put('status', 'error');
                scriptResult.put('riskLevel', flowResult.riskLevel);
                scriptResult.put('reproductionOfConcern', flowResult.reproductionOfConcern);
            }

        } catch (Exception e) {
            // Fail-open: log error but don't block validation
            System.debug(LoggingLevel.ERROR, 'ComplianceScriptService error: ' + e.getMessage());
            System.debug(LoggingLevel.ERROR, 'Stack trace: ' + e.getStackTraceString());

            scriptResult.put('title', 'Compliance validation skipped - technical error occurred');
            scriptResult.put('status', 'success');
        }

        return scriptResult;
    }

    /**
     * @description Check if compliance validation is available and configured
     * @return Boolean indicating if validation is ready to use
     */
    @AuraEnabled
    public static Boolean isValidationAvailable() {
        return ComplianceFlowService.isFlowValidationAvailable();
    }

    /**
     * @description Get NextProviderVisitObjective from the ProviderVisit related to a Visit
     * @param visitId The Visit record ID
     * @return The objective text, or null if not found
     */
    @AuraEnabled(cacheable=true)
    public static String getObjectiveForVisit(String visitId) {
        if (String.isBlank(visitId)) {
            return null;
        }
        List<ProviderVisit> pvs = [
            SELECT NextProviderVisitObjective
            FROM ProviderVisit
            WHERE VisitId = :visitId
            AND NextProviderVisitObjective != null
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];
        return pvs.isEmpty() ? null : pvs[0].NextProviderVisitObjective;
    }
}
