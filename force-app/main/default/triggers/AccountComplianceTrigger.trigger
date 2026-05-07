/**
 * @description Validates compliance rules on Account before/after insert/update
 * @group Compliance Framework
 * @note This is a demo trigger using Account as proxy for ProviderVisit
 */
trigger AccountComplianceTrigger on Account (before insert, before update, after insert, after update) {

    // BEFORE INSERT/UPDATE: Validate and block violations
    if (Trigger.isBefore) {
        // List of fields to validate
        Map<String, String> fieldsToValidate = new Map<String, String>{
            'Description' => 'Visit Notes'
        };

        // Process each record
        for (Account record : Trigger.new) {

            // Validate each field
            for (String fieldName : fieldsToValidate.keySet()) {
                String fieldLabel = fieldsToValidate.get(fieldName);

                // Only validate if field has content
                Object fieldValue = record.get(fieldName);
                if (fieldValue != null && String.isNotBlank(String.valueOf(fieldValue))) {

                    // Call validation service
                    ComplianceValidationResult result = ComplianceValidationService.validateRecord(
                        record,
                        fieldName
                    );

                    // Handle result based on action
                    if (!result.isValid) {
                        if (result.action == 'Block') {
                            // Add error to field (prevents save)
                            record.addError(fieldName, result.message);
                        } else if (result.action == 'Warn') {
                            // Log warning but allow save
                            System.debug(LoggingLevel.WARN,
                                'Compliance warning on ' + fieldLabel + ': ' + result.message
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
