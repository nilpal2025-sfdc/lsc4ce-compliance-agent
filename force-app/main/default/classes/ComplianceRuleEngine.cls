/**
 * @description Core rule evaluation engine for compliance validation
 * @group Compliance Framework
 */
public with sharing class ComplianceRuleEngine {

    private static final String FLOW_NAME = 'Visit_Logging_Compliance_Check';
    // DISABLE Flow validation for synchronous Save/Submit operations (mobile sync performance)
    // LLM validation still runs via ProviderVisit_Compliance_Background_Validation Flow (async)
    private static final Boolean ENABLE_FLOW_VALIDATION = false;
    private static final Boolean FALLBACK_TO_RULES = true; // Fallback on Flow error

    // Batch logging: collect logs in memory and insert in bulk
    private static List<Compliance_Audit_Log__c> pendingLogs = new List<Compliance_Audit_Log__c>();

    // Cache active rules to avoid repeated SOQL queries in bulk operations
    private static Map<String, List<Compliance_Rule__c>> rulesCache = new Map<String, List<Compliance_Rule__c>>();

    /**
     * @description Validate text against compliance rules
     * @param objectType The API name of the object being validated
     * @param fieldName The API name of the field being validated
     * @param textValue The text value to validate
     * @param recordId The ID of the record being validated
     * @return List of validation results (empty if all rules pass)
     */
    public static List<ComplianceValidationResult> validateText(
        String objectType,
        String fieldName,
        String textValue,
        Id recordId
    ) {
        // Route to Flow-based validation if enabled and available
        if (ENABLE_FLOW_VALIDATION && ComplianceFlowService.isFlowValidationAvailable()) {
            try {
                return validateWithFlow(objectType, fieldName, textValue, recordId);
            } catch (Exception e) {
                System.debug(LoggingLevel.ERROR, 'Flow validation failed, falling back to rules: ' + e.getMessage());
                if (FALLBACK_TO_RULES) {
                    return validateWithRules(objectType, fieldName, textValue, recordId);
                } else {
                    throw e;
                }
            }
        } else {
            // Use rule-based validation
            return validateWithRules(objectType, fieldName, textValue, recordId);
        }
    }

    /**
     * @description Validate text using rule-based validation (keyword/pattern matching)
     * @param objectType The API name of the object being validated
     * @param fieldName The API name of the field being validated
     * @param textValue The text value to validate
     * @param recordId The ID of the record being validated
     * @return List of validation results (empty if all rules pass)
     */
    private static List<ComplianceValidationResult> validateWithRules(
        String objectType,
        String fieldName,
        String textValue,
        Id recordId
    ) {
        List<ComplianceValidationResult> results = new List<ComplianceValidationResult>();

        if (String.isBlank(textValue)) {
            return results;
        }

        try {
            List<Compliance_Rule__c> activeRules = getActiveRules(objectType, fieldName);

            for (Compliance_Rule__c rule : activeRules) {
                Long startTime = System.currentTimeMillis();
                Boolean ruleViolated = false;
                String matchedContent = '';

                // Execute rule based on type
                if (rule.Rule_Type__c == 'Keyword_Match' && String.isNotBlank(rule.Keywords__c)) {
                    if (matchesKeywords(textValue, rule.Keywords__c)) {
                        ruleViolated = true;
                        matchedContent = extractMatchedKeywords(textValue, rule.Keywords__c);
                    }
                } else if (rule.Rule_Type__c == 'Pattern_Match' && String.isNotBlank(rule.Pattern__c)) {
                    if (matchesPattern(textValue, rule.Pattern__c)) {
                        ruleViolated = true;
                        matchedContent = extractMatchedPattern(textValue, rule.Pattern__c);
                    }
                }

                Long executionTime = System.currentTimeMillis() - startTime;

                // Create validation result
                if (ruleViolated) {
                    results.add(new ComplianceValidationResult(rule, matchedContent, textValue));
                }

                // Log the validation
                logValidation(rule, recordId, objectType, ruleViolated ? 'Fail' : 'Pass', executionTime, matchedContent);
            }

        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'ComplianceRuleEngine.validateText error: ' + e.getMessage());
            System.debug(LoggingLevel.ERROR, 'Stack trace: ' + e.getStackTraceString());
        }

        return results;
    }

    /**
     * @description Validate text using Flow-based semantic validation
     * @param objectType The API name of the object being validated
     * @param fieldName The API name of the field being validated
     * @param textValue The text value to validate
     * @param recordId The ID of the record being validated
     * @return List of validation results (empty if compliant)
     */
    private static List<ComplianceValidationResult> validateWithFlow(
        String objectType,
        String fieldName,
        String textValue,
        Id recordId
    ) {
        List<ComplianceValidationResult> results = new List<ComplianceValidationResult>();

        if (String.isBlank(textValue)) {
            return results;
        }

        Long startTime = System.currentTimeMillis();

        try {
            // Invoke Flow
            FlowValidationResult flowResult =
                ComplianceFlowService.invokeComplianceFlow(textValue, FLOW_NAME);

            Long executionTime = System.currentTimeMillis() - startTime;

            // Convert to ComplianceValidationResult if non-compliant
            if (!flowResult.isCompliant) {
                ComplianceValidationResult result = new ComplianceValidationResult();
                result.isValid = false;
                result.severity = mapRiskLevelToSeverity(flowResult.riskLevel);
                result.action = 'Block'; // Block on non-compliance
                result.message = flowResult.getErrorMessage();
                result.matchedContent = flowResult.reproductionOfConcern;
                result.violations = new List<String>{ flowResult.detectedViolation };
                result.flowResult = flowResult; // Store full Flow result

                results.add(result);
            }

            // Log Flow validation to audit trail
            logFlowValidation(flowResult, recordId, objectType, fieldName, executionTime);

        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'ComplianceRuleEngine.validateWithFlow error: ' + e.getMessage());
            System.debug(LoggingLevel.ERROR, 'Stack trace: ' + e.getStackTraceString());
            throw e;
        }

        return results;
    }

    /**
     * @description Map Flow risk level to severity
     * @param riskLevel The risk level from Flow
     * @return Mapped severity
     */
    private static String mapRiskLevelToSeverity(String riskLevel) {
        if (String.isBlank(riskLevel)) {
            return 'Medium';
        }

        Map<String, String> riskToSeverity = new Map<String, String>{
            'Critical' => 'Critical',
            'High' => 'High',
            'Medium' => 'Medium',
            'Low' => 'Low'
        };

        return riskToSeverity.containsKey(riskLevel) ? riskToSeverity.get(riskLevel) : 'Medium';
    }

    /**
     * @description Log Flow validation to audit trail
     * @param flowResult The Flow validation result
     * @param recordId The record being validated
     * @param recordType The object type
     * @param fieldName The field being validated
     * @param executionTime Execution time in milliseconds
     */
    private static void logFlowValidation(
        FlowValidationResult flowResult,
        Id recordId,
        String recordType,
        String fieldName,
        Long executionTime
    ) {
        try {
            Compliance_Audit_Log__c log = new Compliance_Audit_Log__c(
                Record_Id__c = String.valueOf(recordId),
                Record_Type__c = recordType,
                Field_Name__c = fieldName,
                Validation_Result__c = flowResult.isCompliant ? 'Pass' : 'Fail',
                User__c = UserInfo.getUserId(),
                Timestamp__c = System.now(),
                Execution_Time_Ms__c = executionTime,
                Details__c = flowResult.toJSON()
            );

            // Insert asynchronously to avoid blocking main transaction
            Database.insert(log, false);

        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'ComplianceRuleEngine.logFlowValidation error: ' + e.getMessage());
        }
    }

    /**
     * @description Get active compliance rules for a specific object and field
     * @param objectType The API name of the object
     * @param fieldName The API name of the field
     * @return List of active compliance rules
     */
    public static List<Compliance_Rule__c> getActiveRules(String objectType, String fieldName) {
        // Create cache key
        String cacheKey = objectType + '|' + fieldName;

        // Check cache first
        if (rulesCache.containsKey(cacheKey)) {
            return rulesCache.get(cacheKey);
        }

        try {
            List<Compliance_Rule__c> rules = [
                SELECT Id, Name__c, Description__c, Rule_Type__c, Keywords__c,
                       Pattern__c, Severity__c, Action__c, Remediation_Message__c,
                       Target_Object__c, Target_Field__c, Is_Active__c
                FROM Compliance_Rule__c
                WHERE Is_Active__c = true
                AND Target_Object__c = :objectType
                AND Target_Field__c = :fieldName
                ORDER BY Severity__c ASC
                LIMIT 200
            ];

            // Store in cache
            rulesCache.put(cacheKey, rules);
            return rules;

        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'ComplianceRuleEngine.getActiveRules error: ' + e.getMessage());
            List<Compliance_Rule__c> emptyList = new List<Compliance_Rule__c>();
            rulesCache.put(cacheKey, emptyList); // Cache empty result too
            return emptyList;
        }
    }

    /**
     * @description Check if text matches any keywords (case-insensitive)
     * @param text The text to check
     * @param keywords Comma-separated list of keywords
     * @return True if any keyword is found
     */
    private static Boolean matchesKeywords(String text, String keywords) {
        if (String.isBlank(text) || String.isBlank(keywords)) {
            return false;
        }

        String lowerText = text.toLowerCase();
        List<String> keywordList = keywords.split(',');

        for (String keyword : keywordList) {
            String trimmedKeyword = keyword.trim().toLowerCase();
            if (String.isNotBlank(trimmedKeyword) && lowerText.contains(trimmedKeyword)) {
                return true;
            }
        }

        return false;
    }

    /**
     * @description Check if text matches a regex pattern
     * @param text The text to check
     * @param patternString The regex pattern
     * @return True if pattern matches
     */
    private static Boolean matchesPattern(String text, String patternString) {
        if (String.isBlank(text) || String.isBlank(patternString)) {
            return false;
        }

        try {
            Pattern p = Pattern.compile(patternString);
            Matcher m = p.matcher(text);
            return m.find();
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'ComplianceRuleEngine.matchesPattern error: ' + e.getMessage());
            return false;
        }
    }

    /**
     * @description Extract matched keywords from text
     * @param text The text to search
     * @param keywords Comma-separated list of keywords
     * @return Comma-separated list of matched keywords
     */
    private static String extractMatchedKeywords(String text, String keywords) {
        if (String.isBlank(text) || String.isBlank(keywords)) {
            return '';
        }

        List<String> matched = new List<String>();
        String lowerText = text.toLowerCase();
        List<String> keywordList = keywords.split(',');

        for (String keyword : keywordList) {
            String trimmedKeyword = keyword.trim().toLowerCase();
            if (String.isNotBlank(trimmedKeyword) && lowerText.contains(trimmedKeyword)) {
                matched.add(trimmedKeyword);
            }
        }

        return String.join(matched, ', ');
    }

    /**
     * @description Extract matched pattern content from text
     * @param text The text to search
     * @param patternString The regex pattern
     * @return Matched content (first match)
     */
    private static String extractMatchedPattern(String text, String patternString) {
        if (String.isBlank(text) || String.isBlank(patternString)) {
            return '';
        }

        try {
            Pattern p = Pattern.compile(patternString);
            Matcher m = p.matcher(text);
            if (m.find()) {
                return m.group(0);
            }
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'ComplianceRuleEngine.extractMatchedPattern error: ' + e.getMessage());
        }

        return '';
    }

    /**
     * @description Log validation execution to audit log
     * @param rule The compliance rule that was executed
     * @param recordId The record being validated
     * @param recordType The object type
     * @param result The validation result (Pass/Fail/Error)
     * @param executionTime Execution time in milliseconds
     * @param matchedContent Content that matched the rule
     */
    private static void logValidation(
        Compliance_Rule__c rule,
        Id recordId,
        String recordType,
        String result,
        Long executionTime,
        String matchedContent
    ) {
        try {
            Compliance_Audit_Log__c log = new Compliance_Audit_Log__c(
                Rule__c = rule.Id,
                Record_Id__c = String.valueOf(recordId),
                Record_Type__c = recordType,
                Validation_Result__c = result,
                User__c = UserInfo.getUserId(),
                Timestamp__c = System.now(),
                Execution_Time_Ms__c = executionTime,
                Details__c = JSON.serialize(new Map<String, Object>{
                    'rule_name' => rule.Name__c,
                    'rule_type' => rule.Rule_Type__c,
                    'severity' => rule.Severity__c,
                    'action' => rule.Action__c,
                    'matched_content' => matchedContent
                })
            );

            // Add to batch for bulk insert later
            pendingLogs.add(log);

        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'ComplianceRuleEngine.logValidation error: ' + e.getMessage());
        }
    }

    /**
     * @description Flush all pending audit logs to database
     * Call this after bulk operations to avoid DML limits
     */
    public static void flushAuditLogs() {
        if (pendingLogs.isEmpty()) {
            return;
        }

        try {
            // Insert all logs in one DML operation
            Database.insert(pendingLogs, false);
            System.debug('Flushed ' + pendingLogs.size() + ' audit logs');
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'ComplianceRuleEngine.flushAuditLogs error: ' + e.getMessage());
        } finally {
            // Clear the list regardless of success/failure
            pendingLogs.clear();
        }
    }
}
