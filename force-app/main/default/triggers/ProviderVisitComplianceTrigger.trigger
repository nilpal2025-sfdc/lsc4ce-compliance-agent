/**
 * @description Validates compliance rules on ProviderVisit before/after insert/update
 * @group Compliance Framework
 */
trigger ProviderVisitComplianceTrigger on ProviderVisit (before insert, before update, after insert, after update) {

    // BEFORE INSERT/UPDATE: Validate and block violations
    if (Trigger.isBefore) {
        // List of fields to validate
        Map<String, String> fieldsToValidate = new Map<String, String>{
            'NextProviderVisitObjective' => 'Next Visit Objective'  // Standard LSC field (no __c)
        };

        // Process each record
        for (ProviderVisit visit : Trigger.new) {

            // Validate each field
            for (String fieldName : fieldsToValidate.keySet()) {
                String fieldLabel = fieldsToValidate.get(fieldName);

                // Only validate if field has content
                Object fieldValue = visit.get(fieldName);
                if (fieldValue != null && String.isNotBlank(String.valueOf(fieldValue))) {

                    // Call validation service
                    ComplianceValidationResult result = ComplianceValidationService.validateRecord(
                        visit,
                        fieldName
                    );

                    // Handle result based on action
                    if (!result.isValid) {
                        if (result.action == 'Block') {
                            String errorMessage;

                            // Check if this is a Flow-based result
                            if (result.flowResult != null) {
                                // Use pre-formatted Flow message directly
                                errorMessage = result.message;
                            } else {
                                // Use rule-based enhanced message with 50-character context
                                errorMessage = result.buildEnhancedMessage(50);
                            }

                            // Add error to field (prevents save)
                            visit.addError(fieldName, errorMessage);
                        } else if (result.action == 'Warn') {
                            String warningMessage;

                            // Check if this is a Flow-based result
                            if (result.flowResult != null) {
                                // Use pre-formatted Flow message directly
                                warningMessage = result.message;
                            } else {
                                // Use rule-based enhanced message
                                warningMessage = result.buildEnhancedMessage(50);
                            }

                            // Log warning but allow save
                            System.debug(LoggingLevel.WARN,
                                'Compliance warning on ' + fieldLabel + ': ' + warningMessage
                            );
                            // Note: Warnings don't prevent save, but alert is created
                        }
                        // Log action: No user message, just audit log
                    }
                }
            }
        }
    }

    // AFTER INSERT: Update alerts with actual record IDs
    if (Trigger.isAfter && Trigger.isInsert) {
        ComplianceValidationService.updateAlertsWithRecordIds(Trigger.new);
    }
}
