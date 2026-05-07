/**
 * @description Service class to invoke Salesforce Flows for compliance validation
 * @author Nilotpal Paul
 * @date 2026-03-26
 */
public class ComplianceFlowService {

    private static final String DEFAULT_FLOW_NAME = 'Visit_Logging_Compliance_Check';
    private static final String INPUT_VARIABLE_NAME = 'VoiceTextUtterance';

    // Cache Flow availability to avoid repeated SOQL queries in bulk operations
    private static Boolean flowAvailabilityCache = null;

    /**
     * @description Check if Flow-based validation is available
     * Verifies Flow exists and is active
     * @return True if Flow validation can be used
     */
    public static Boolean isFlowValidationAvailable() {
        // Return cached value if available
        if (flowAvailabilityCache != null) {
            return flowAvailabilityCache;
        }

        try {
            // Query for the Flow definition
            List<FlowDefinitionView> flows = [
                SELECT ApiName, IsActive
                FROM FlowDefinitionView
                WHERE ApiName = :DEFAULT_FLOW_NAME
                AND IsActive = true
                LIMIT 1
            ];

            flowAvailabilityCache = !flows.isEmpty();
            return flowAvailabilityCache;

        } catch (Exception e) {
            System.debug('Error checking Flow availability: ' + e.getMessage());
            flowAvailabilityCache = false;
            return false;
        }
    }

    /**
     * @description Invoke compliance Flow with text content
     * @param textContent The text to validate
     * @param flowName The Flow API name to invoke
     * @return FlowValidationResult with Flow output
     */
    public static FlowValidationResult invokeComplianceFlow(
        String textContent,
        String flowName
    ) {
        if (String.isBlank(textContent)) {
            return createEmptyResult();
        }

        if (String.isBlank(flowName)) {
            flowName = DEFAULT_FLOW_NAME;
        }

        try {
            // Prepare input variables for Flow
            Map<String, Object> flowInputs = new Map<String, Object>();
            flowInputs.put(INPUT_VARIABLE_NAME, textContent);

            // Invoke Flow
            Flow.Interview flowInterview = Flow.Interview.createInterview(flowName, flowInputs);
            flowInterview.start();

            // Extract output variables
            Map<String, Object> flowOutputs = flowInterview.getVariableValue('allOutputs') != null
                ? (Map<String, Object>) flowInterview.getVariableValue('allOutputs')
                : new Map<String, Object>();

            // Parse Flow output into structured result
            return parseFlowOutput(flowOutputs, flowInterview);

        } catch (Exception e) {
            System.debug('Error invoking Flow: ' + e.getMessage());
            System.debug('Stack trace: ' + e.getStackTraceString());

            // Return error result
            return createErrorResult(e.getMessage());
        }
    }

    /**
     * @description Parse Flow output variables into FlowValidationResult
     * @param flowOutputs Map of output variable names to values
     * @param flowInterview The Flow interview instance
     * @return Parsed FlowValidationResult
     */
    private static FlowValidationResult parseFlowOutput(
        Map<String, Object> flowOutputs,
        Flow.Interview flowInterview
    ) {
        FlowValidationResult result = new FlowValidationResult();

        try {
            // Extract output variables from Flow
            result.status = getFlowVariable(flowInterview, 'ComplianceStatus');
            result.riskLevel = getFlowVariable(flowInterview, 'RiskLevel');
            result.assessment = getFlowVariable(flowInterview, 'ComplianceAssessment');
            result.detectedViolation = getFlowVariable(flowInterview, 'DetectedViolation');
            result.sopReference = getFlowVariable(flowInterview, 'SOPReference');
            result.reproductionOfConcern = getFlowVariable(flowInterview, 'ReproductionOfConcern');
            result.recommendedAction = getFlowVariable(flowInterview, 'RecommendedAction');
            result.correctiveVerbiage = getFlowVariable(flowInterview, 'CorrectiveVerbiage');

            // Determine if compliant based on status
            result.isCompliant = isCompliantStatus(result.status);

        } catch (Exception e) {
            System.debug('Error parsing Flow output: ' + e.getMessage());
            result.isCompliant = true; // Default to compliant on parse error
        }

        return result;
    }

    /**
     * @description Get Flow variable value as String
     * @param flowInterview The Flow interview instance
     * @param variableName The variable name to extract
     * @return String value of the variable, or null if not found
     */
    private static String getFlowVariable(Flow.Interview flowInterview, String variableName) {
        try {
            Object value = flowInterview.getVariableValue(variableName);
            return value != null ? String.valueOf(value) : null;
        } catch (Exception e) {
            System.debug('Error getting Flow variable ' + variableName + ': ' + e.getMessage());
            return null;
        }
    }

    /**
     * @description Determine if status indicates compliance
     * CRITICAL: Only exact match of "Compliant" should pass
     * Anything else (including "Non-Compliant", blank, null) should block
     * @param status The compliance status from Flow
     * @return True ONLY if status exactly equals "Compliant" (case-insensitive)
     */
    private static Boolean isCompliantStatus(String status) {
        if (String.isBlank(status)) {
            return false; // Fail-safe: blank/null should block
        }

        // Exact match required - "Non-Compliant" must NOT pass
        return 'Compliant'.equalsIgnoreCase(status.trim());
    }

    /**
     * @description Create empty result for blank input
     * @return FlowValidationResult indicating compliant
     */
    private static FlowValidationResult createEmptyResult() {
        FlowValidationResult result = new FlowValidationResult();
        result.isCompliant = true;
        result.status = 'No content to validate';
        return result;
    }

    /**
     * @description Create error result when Flow invocation fails
     * @param errorMessage The error message
     * @return FlowValidationResult indicating compliant (fail-open)
     */
    private static FlowValidationResult createErrorResult(String errorMessage) {
        FlowValidationResult result = new FlowValidationResult();
        result.isCompliant = true; // Fail-open: don't block on Flow errors
        result.status = 'Flow validation unavailable';
        result.assessment = 'Error: ' + errorMessage;
        return result;
    }
}
