/**
 * @description Service layer for compliance validation logic
 * @group Compliance Framework
 */
public with sharing class ComplianceValidationService {

    // Store mapping of temporary IDs to actual alert IDs for before insert updates
    private static Map<String, Id> tempIdToAlertId = new Map<String, Id>();

    /**
     * @description Generate temporary identifier for before insert alerts
     * Must be 18 characters or less to fit in Record_Id__c field
     * Format: TEMP followed by 14 digits (timestamp milliseconds)
     */
    private static String generateTempId() {
        return 'T' + String.valueOf(System.now().getTime()).right(17);
    }

    /**
     * @description Validate a record field against compliance rules
     * @param record The record to validate
     * @param fieldName The field to validate
     * @return Validation result with any violations
     */
    public static ComplianceValidationResult validateRecord(SObject record, String fieldName) {
        try {
            if (record == null || String.isBlank(fieldName)) {
                return new ComplianceValidationResult();
            }

            String objectType = record.getSObjectType().getDescribe().getName();
            String textValue = String.valueOf(record.get(fieldName));
            Id recordId = record.Id;

            List<ComplianceValidationResult> results = ComplianceRuleEngine.validateText(
                objectType,
                fieldName,
                textValue,
                recordId
            );

            // Return first blocking violation, or first warning, or valid result
            ComplianceValidationResult blockingViolation = null;
            ComplianceValidationResult warningViolation = null;

            for (ComplianceValidationResult result : results) {
                if (result.action == 'Block') {
                    blockingViolation = result;
                    break;
                } else if (result.action == 'Warn' && warningViolation == null) {
                    warningViolation = result;
                }
            }

            if (blockingViolation != null) {
                // Create alert immediately, regardless of recordId
                // For before insert (recordId is null), we'll update it in after insert
                String tempId = createAlertImmediate(
                    blockingViolation.rule,
                    recordId,
                    objectType,
                    fieldName,
                    textValue,
                    blockingViolation.matchedContent,
                    blockingViolation.flowResult
                );
                // Store tempId for after insert update if needed
                if (recordId == null && String.isNotBlank(tempId)) {
                    blockingViolation.tempId = tempId;
                }
                return blockingViolation;
            } else if (warningViolation != null) {
                // Create alert immediately, regardless of recordId
                String tempId = createAlertImmediate(
                    warningViolation.rule,
                    recordId,
                    objectType,
                    fieldName,
                    textValue,
                    warningViolation.matchedContent,
                    warningViolation.flowResult
                );
                // Store tempId for after insert update if needed
                if (recordId == null && String.isNotBlank(tempId)) {
                    warningViolation.tempId = tempId;
                }
                return warningViolation;
            }

            return new ComplianceValidationResult();

        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'ComplianceValidationService.validateRecord error: ' + e.getMessage());
            System.debug(LoggingLevel.ERROR, 'Stack trace: ' + e.getStackTraceString());
            return new ComplianceValidationResult();
        }
    }

    /**
     * @description Update alerts created during before insert with actual record IDs
     * Call this from after insert trigger
     * @param records The records that were just inserted
     */
    public static void updateAlertsWithRecordIds(List<SObject> records) {
        try {
            if (tempIdToAlertId.isEmpty()) {
                return;
            }

            System.debug(LoggingLevel.INFO, 'Updating ' + tempIdToAlertId.size() + ' alerts with record IDs');

            List<Compliance_Alert__c> alertsToUpdate = new List<Compliance_Alert__c>();

            // Query alerts created with temp IDs
            Set<Id> alertIds = new Set<Id>(tempIdToAlertId.values());
            Map<Id, Compliance_Alert__c> existingAlerts = new Map<Id, Compliance_Alert__c>([
                SELECT Id, Record_Id__c, Alert_Date__c
                FROM Compliance_Alert__c
                WHERE Id IN :alertIds
            ]);

            // Match temp IDs to actual record IDs
            for (SObject record : records) {
                Id recordId = record.Id;
                if (recordId == null) continue;

                // Find matching alert by looking for temp IDs (start with 'T')
                for (String tempId : tempIdToAlertId.keySet()) {
                    if (tempId.startsWith('T')) {
                        Id alertId = tempIdToAlertId.get(tempId);
                        Compliance_Alert__c alert = existingAlerts.get(alertId);

                        if (alert != null && alert.Record_Id__c == tempId) {
                            alert.Record_Id__c = String.valueOf(recordId);
                            alertsToUpdate.add(alert);
                            break;  // Found the match, move to next record
                        }
                    }
                }
            }

            if (!alertsToUpdate.isEmpty()) {
                update alertsToUpdate;
                System.debug(LoggingLevel.INFO, 'Updated ' + alertsToUpdate.size() + ' alerts with actual record IDs');
            }

            // Clear temp mappings
            tempIdToAlertId.clear();

        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'ComplianceValidationService.updateAlertsWithRecordIds error: ' + e.getMessage());
            tempIdToAlertId.clear(); // Clear to prevent retry loops
        }
    }

    /**
     * @description Create a compliance alert immediately (used in before trigger)
     * @param rule The compliance rule that was violated (may be null for Flow-based validation)
     * @param recordId The ID of the record (may be null for before insert)
     * @param objectType The object type name
     * @param fieldName The field that violated the rule
     * @param originalValue The original text value
     * @param matchedContent The content that matched the rule
     * @param flowResult The Flow validation result (may be null for rule-based validation)
     * @return Temporary ID if recordId was null, otherwise null
     */
    private static String createAlertImmediate(
        Compliance_Rule__c rule,
        Id recordId,
        String objectType,
        String fieldName,
        String originalValue,
        String matchedContent,
        FlowValidationResult flowResult
    ) {
        try {
            String tempId = null;
            String recordIdValue;

            // If recordId is null (before insert), generate temp ID
            if (recordId == null) {
                tempId = generateTempId();
                recordIdValue = tempId;  // Temp ID is already 18 chars, no prefix needed
            } else {
                recordIdValue = String.valueOf(recordId);
            }

            // Query for ProviderVisit details if applicable
            String territoryName = 'No Territory';
            String accountName = 'No Account';
            Id agentforceRuleId = null;

            if (objectType == 'ProviderVisit' && recordId != null) {
                try {
                    List<ProviderVisit> visits = [
                        SELECT TerritoryName, AccountId
                        FROM ProviderVisit
                        WHERE Id = :recordId
                        LIMIT 1
                    ];

                    if (!visits.isEmpty() && visits[0].TerritoryName != null) {
                        territoryName = visits[0].TerritoryName;
                    }

                    if (!visits.isEmpty() && visits[0].AccountId != null) {
                        List<Account> accounts = [
                            SELECT Name
                            FROM Account
                            WHERE Id = :visits[0].AccountId
                            LIMIT 1
                        ];
                        if (!accounts.isEmpty()) {
                            accountName = accounts[0].Name;
                        }
                    }
                } catch (Exception e) {
                    System.debug(LoggingLevel.WARN, 'Failed to query Visit/Account details: ' + e.getMessage());
                }
            }

            // If this is a flow-based validation (rule is null), get Agentforce rule
            if (rule == null) {
                try {
                    List<Compliance_Rule__c> agentforceRules = [
                        SELECT Id
                        FROM Compliance_Rule__c
                        WHERE Name__c = 'Agentforce Evaluation'
                        LIMIT 1
                    ];
                    if (!agentforceRules.isEmpty()) {
                        agentforceRuleId = agentforceRules[0].Id;
                    }
                } catch (Exception e) {
                    System.debug(LoggingLevel.WARN, 'Failed to query Agentforce rule: ' + e.getMessage());
                }
            }

            // Build alert name with new format
            String alertName = 'Compliance Issue - ' + System.now().format('yyyy-MM-dd HH:mm') +
                              ' | ' + territoryName +
                              ' | Visit: ' + recordIdValue +
                              ' | Account: ' + accountName;

            // Determine severity: from rule if available, otherwise from Flow Risk_Level
            String severity = null;
            if (rule != null) {
                severity = rule.Severity__c;
            } else if (flowResult != null) {
                severity = flowResult.riskLevel;
            }

            Compliance_Alert__c alert = new Compliance_Alert__c(
                Alert_Name__c = alertName,
                Rule__c = rule != null ? rule.Id : agentforceRuleId,
                Record_Id__c = recordIdValue,
                Record_Type__c = objectType,
                Field_Name__c = fieldName,
                Original_Value__c = originalValue != null && originalValue.length() > 32000
                    ? originalValue.substring(0, 32000)
                    : originalValue,
                Matched_Content__c = matchedContent != null && matchedContent.length() > 4000
                    ? matchedContent.substring(0, 4000)
                    : matchedContent,
                Severity__c = severity,
                Status__c = 'Open',
                User__c = UserInfo.getUserId(),
                Alert_Date__c = System.now()
            );

            // Add Flow-specific fields if Flow result is available
            if (flowResult != null) {
                alert.Risk_Level__c = flowResult.riskLevel;
                alert.SOP_Reference__c = flowResult.sopReference != null && flowResult.sopReference.length() > 255
                    ? flowResult.sopReference.substring(0, 255)
                    : flowResult.sopReference;
                alert.Corrective_Verbiage__c = flowResult.correctiveVerbiage != null && flowResult.correctiveVerbiage.length() > 32000
                    ? flowResult.correctiveVerbiage.substring(0, 32000)
                    : flowResult.correctiveVerbiage;
                alert.Detected_Violation__c = flowResult.detectedViolation != null && flowResult.detectedViolation.length() > 32000
                    ? flowResult.detectedViolation.substring(0, 32000)
                    : flowResult.detectedViolation;
            }

            // Insert immediately
            Database.SaveResult sr = Database.insert(alert, false);
            if (!sr.isSuccess()) {
                for (Database.Error err : sr.getErrors()) {
                    System.debug(LoggingLevel.ERROR,
                        'Failed to create Compliance_Alert__c: ' + err.getStatusCode() + ' - ' + err.getMessage());
                    System.debug(LoggingLevel.ERROR, 'Fields: ' + err.getFields());
                }
                return null;
            } else {
                System.debug(LoggingLevel.INFO, 'Created Compliance_Alert__c immediately: ' + sr.getId());

                // Store mapping for after insert update if tempId was used
                if (tempId != null) {
                    tempIdToAlertId.put(tempId, sr.getId());
                }

                return tempId;
            }

        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'ComplianceValidationService.createAlertImmediate error: ' + e.getMessage());
            return null;
        }
    }

    /**
     * @description Create a compliance alert for a rule violation (legacy method for backward compatibility)
     * @param rule The compliance rule that was violated (may be null for Flow-based validation)
     * @param recordId The ID of the record
     * @param fieldName The field that violated the rule
     * @param originalValue The original text value
     * @param matchedContent The content that matched the rule
     * @param flowResult The Flow validation result (may be null for rule-based validation)
     */
    public static void createAlert(
        Compliance_Rule__c rule,
        Id recordId,
        String fieldName,
        String originalValue,
        String matchedContent,
        FlowValidationResult flowResult
    ) {
        // Delegate to createAlertImmediate
        if (recordId == null) {
            System.debug(LoggingLevel.ERROR, 'Cannot create alert: recordId is null (use createAlertImmediate instead)');
            return;
        }

        String objectType = String.valueOf(recordId.getSObjectType());
        createAlertImmediate(rule, recordId, objectType, fieldName, originalValue, matchedContent, flowResult);
    }

    /**
     * @description Validate multiple records (bulk operation)
     * @param records List of records to validate
     * @param fieldName The field to validate
     * @return Map of record ID to validation result
     */
    public static Map<Id, ComplianceValidationResult> validateRecords(
        List<SObject> records,
        String fieldName
    ) {
        Map<Id, ComplianceValidationResult> resultMap = new Map<Id, ComplianceValidationResult>();

        try {
            for (SObject record : records) {
                if (record.Id != null) {
                    ComplianceValidationResult result = validateRecord(record, fieldName);
                    resultMap.put(record.Id, result);
                }
            }

            // Flush audit logs after bulk operation
            ComplianceRuleEngine.flushAuditLogs();

        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'ComplianceValidationService.validateRecords error: ' + e.getMessage());
        }

        return resultMap;
    }

    /**
     * @description Get all open alerts for a record
     * @param recordId The record ID
     * @return List of open alerts
     */
    public static List<Compliance_Alert__c> getOpenAlerts(Id recordId) {
        try {
            return [
                SELECT Id, Alert_Name__c, Rule__r.Name__c, Severity__c, Status__c,
                       Field_Name__c, Matched_Content__c, Alert_Date__c,
                       Rule__r.Remediation_Message__c,
                       Risk_Level__c, SOP_Reference__c, Corrective_Verbiage__c,
                       Detected_Violation__c
                FROM Compliance_Alert__c
                WHERE Record_Id__c = :String.valueOf(recordId)
                AND Status__c = 'Open'
                ORDER BY Severity__c ASC, Alert_Date__c DESC
                LIMIT 100
            ];
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'ComplianceValidationService.getOpenAlerts error: ' + e.getMessage());
            return new List<Compliance_Alert__c>();
        }
    }

    /**
     * @description Resolve a compliance alert
     * @param alertId The alert ID
     * @param resolutionNotes Notes about the resolution
     */
    public static void resolveAlert(Id alertId, String resolutionNotes) {
        try {
            Compliance_Alert__c alert = new Compliance_Alert__c(
                Id = alertId,
                Status__c = 'Resolved',
                Resolution_Notes__c = resolutionNotes
            );
            update alert;
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'ComplianceValidationService.resolveAlert error: ' + e.getMessage());
        }
    }
}
