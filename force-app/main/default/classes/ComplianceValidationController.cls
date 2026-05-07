public with sharing class ComplianceValidationController {

    @AuraEnabled
    public static Map<String, Object> validateObjective(Id visitId, String objectiveText) {
        Map<String, Object> response = new Map<String, Object>();

        if (String.isBlank(objectiveText) || objectiveText.trim().length() < 5) {
            response.put('isCompliant', true);
            response.put('status', 'No content to validate');
            return response;
        }

        // Layer 1: Rules-based validation
        ComplianceValidationResult rulesResult = runRulesValidation(visitId, objectiveText);

        if (!rulesResult.isValid && rulesResult.action == 'Block') {
            response.put('isCompliant', false);
            response.put('source', 'rules');
            response.put('status', 'Non-Compliant');
            response.put('severity', rulesResult.severity);
            response.put('message', rulesResult.message);
            response.put('matchedContent', rulesResult.matchedContent);
            return response;
        }

        // Layer 2: LLM-based semantic validation via Flow
        if (ComplianceFlowService.isFlowValidationAvailable()) {
            FlowValidationResult flowResult = ComplianceFlowService.invokeComplianceFlow(
                objectiveText, null
            );

            if (!flowResult.isCompliant) {
                createFlowAlert(visitId, objectiveText, flowResult);

                response.put('isCompliant', false);
                response.put('source', 'llm');
                response.put('status', flowResult.status);
                response.put('riskLevel', flowResult.riskLevel);
                response.put('assessment', flowResult.assessment);
                response.put('detectedViolation', flowResult.detectedViolation);
                response.put('sopReference', flowResult.sopReference);
                response.put('recommendedAction', flowResult.recommendedAction);
                response.put('correctiveVerbiage', flowResult.correctiveVerbiage);
                return response;
            }
        }

        // Include rules warnings even if LLM passed
        if (!rulesResult.isValid && rulesResult.action == 'Warn') {
            response.put('isCompliant', true);
            response.put('hasWarning', true);
            response.put('status', 'Compliant with warnings');
            response.put('message', rulesResult.message);
            response.put('matchedContent', rulesResult.matchedContent);
            return response;
        }

        response.put('isCompliant', true);
        response.put('status', 'Compliant');
        return response;
    }

    @AuraEnabled(cacheable=true)
    public static Map<String, Object> getVisitObjective(Id visitId) {
        Map<String, Object> result = new Map<String, Object>();
        try {
            List<ProviderVisit> visits = [
                SELECT Id, NextProviderVisitObjective, VisitId, AccountId
                FROM ProviderVisit
                WHERE VisitId = :visitId
                LIMIT 1
            ];

            if (!visits.isEmpty()) {
                result.put('objectiveText', visits[0].NextProviderVisitObjective);
                result.put('providerVisitId', visits[0].Id);
                result.put('accountId', visits[0].AccountId);
            }
        } catch (Exception e) {
            result.put('error', e.getMessage());
        }
        return result;
    }

    private static ComplianceValidationResult runRulesValidation(Id visitId, String objectiveText) {
        try {
            List<ComplianceValidationResult> results = ComplianceRuleEngine.validateText(
                'ProviderVisit',
                'NextProviderVisitObjective',
                objectiveText,
                visitId
            );

            for (ComplianceValidationResult r : results) {
                if (r.action == 'Block') return r;
            }
            for (ComplianceValidationResult r : results) {
                if (r.action == 'Warn') return r;
            }
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'Rules validation error: ' + e.getMessage());
        }
        return new ComplianceValidationResult();
    }

    private static void createFlowAlert(Id visitId, String objectiveText, FlowValidationResult flowResult) {
        try {
            ComplianceValidationService.createAlert(
                null,
                visitId,
                'NextProviderVisitObjective',
                objectiveText,
                flowResult.detectedViolation,
                flowResult
            );
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'Alert creation error: ' + e.getMessage());
        }
    }
}
