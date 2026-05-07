/**
 * Invocable Apex class to parse compliance review response text into structured outputs.
 * Input: JSON with response.text (e.g. from an AI/LLM response).
 * Output: Separate fields for Status, Risk Level, Assessment, Detected Violation,
 *         SOP Reference, Reproduction of Concern, Recommended Action, Corrective Verbiage.
 */
public with sharing class ComplianceReviewParser {

    private static final Set<String> FIELD_LABELS = new Set<String>{
        'Status', 'Risk Level', 'Assessment', 'Detected Violation',
        'SOP Reference', 'Reproduction of Concern', 'Recommended Action', 'Corrective Verbiage'
    };

    @InvocableMethod(
        label='Parse Compliance Review'
        description='Parses compliance review response text into structured output fields.'
        category='Compliance'
    )
    public static List<ComplianceReviewOutput> parseComplianceReview(List<ComplianceReviewInput> inputs) {
        List<ComplianceReviewOutput> results = new List<ComplianceReviewOutput>();
        if (inputs == null || inputs.isEmpty()) {
            return results;
        }
        for (ComplianceReviewInput input : inputs) {
            results.add(parseOne(input));
        }
        return results;
    }

    private static String extractTextFromPayload(String rawPayload) {
        try {
            Map<String, Object> root = (Map<String, Object>) JSON.deserializeUntyped(rawPayload);
            Object responseObj = root.get('response');
            if (!(responseObj instanceof Map<String, Object>)) {
                return null;
            }
            Map<String, Object> response = (Map<String, Object>) responseObj;
            Object textObj = response.get('text');
            if (textObj == null) {
                return null;
            }
            if (textObj instanceof String) {
                return (String) textObj;
            }
            if (textObj instanceof Map<String, Object>) {
                structuredText = (Map<String, Object>) textObj;
                return null;
            }
            return String.valueOf(textObj);
        } catch (Exception e) {
            return null;
        }
    }

    private static Map<String, Object> structuredText;

    private static ComplianceReviewOutput parseOne(ComplianceReviewInput input) {
        ComplianceReviewOutput out = new ComplianceReviewOutput();
        out.status = out.riskLevel = out.assessment = out.detectedViolation = '';
        out.sopReference = out.reproductionOfConcern = out.recommendedAction = out.correctiveVerbiage = '';
        String rawInput = input != null ? input.rawPayload : null;
        if (String.isBlank(rawInput)) {
            return out;
        }
        structuredText = null;
        String text = extractTextFromPayload(rawInput);
        if (structuredText != null) {
            Map<String, String> parsed = parseStructuredJson(structuredText);
            out.status = get(parsed, 'Status');
            out.riskLevel = get(parsed, 'Risk Level');
            out.assessment = get(parsed, 'Assessment');
            out.detectedViolation = get(parsed, 'Detected Violation');
            out.sopReference = get(parsed, 'SOP Reference');
            out.reproductionOfConcern = get(parsed, 'Reproduction of Concern');
            out.recommendedAction = get(parsed, 'Recommended Action');
            out.correctiveVerbiage = get(parsed, 'Corrective Verbiage');
            return out;
        }
        if (String.isBlank(text)) {
            return out;
        }
        Map<String, String> parsed = parseComplianceText(text);
        out.status = get(parsed, 'Status');
        out.riskLevel = get(parsed, 'Risk Level');
        out.assessment = get(parsed, 'Assessment');
        out.detectedViolation = get(parsed, 'Detected Violation');
        out.sopReference = get(parsed, 'SOP Reference');
        out.reproductionOfConcern = get(parsed, 'Reproduction of Concern');
        out.recommendedAction = get(parsed, 'Recommended Action');
        out.correctiveVerbiage = get(parsed, 'Corrective Verbiage');
        return out;
    }

    private static Map<String, String> parseStructuredJson(Map<String, Object> root) {
        Map<String, String> result = new Map<String, String>();
        Map<String, Object> summary = null;
        Map<String, Object> findings = null;
        Map<String, Object> remediation = null;

        if (root.containsKey('Compliance Review Summary')) {
            summary = (Map<String, Object>) root.get('Compliance Review Summary');
        } else {
            summary = root;
        }

        if (summary != null) {
            putIfPresent(result, 'Status', summary.get('Status'));
            putIfPresent(result, 'Risk Level', summary.get('Risk Level'));

            Object findingsObj = summary.get('Detailed Findings');
            if (findingsObj instanceof Map<String, Object>) {
                findings = (Map<String, Object>) findingsObj;
            }

            Object remediationObj = summary.get('Remediation Guidance');
            if (remediationObj instanceof Map<String, Object>) {
                remediation = (Map<String, Object>) remediationObj;
            }
        }

        if (findings != null) {
            putIfPresent(result, 'Assessment', findings.get('Assessment'));
            putIfPresent(result, 'Detected Violation', findings.get('Detected Violation'));
            putIfPresent(result, 'SOP Reference', findings.get('SOP Reference'));
            putIfPresent(result, 'Reproduction of Concern', findings.get('Reproduction of Concern'));
        }

        if (remediation != null) {
            putIfPresent(result, 'Recommended Action', remediation.get('Recommended Action'));
            putIfPresent(result, 'Corrective Verbiage', remediation.get('Corrective Verbiage'));
        }

        return result;
    }

    private static void putIfPresent(Map<String, String> result, String key, Object value) {
        if (value != null) {
            String strVal = String.valueOf(value);
            if (strVal != 'N/A') {
                result.put(key, strVal);
            }
        }
    }

    private static Map<String, String> parseComplianceText(String text) {
        Map<String, String> result = new Map<String, String>();
        if (String.isBlank(text)) {
            return result;
        }
        String normalized = text.replace('\r\n', '\n').replace('\r', '\n');
        List<String> lines = normalized.split('\n');
        String currentLabel = null;
        String currentValue = '';
        for (String line : lines) {
            String trimmed = line.trim();
            if (String.isBlank(trimmed)) {
                continue;
            }
            Boolean isFieldLine = false;
            for (String label : FIELD_LABELS) {
                if (trimmed.startsWith(label + ':')) {
                    if (currentLabel != null) {
                        result.put(currentLabel, currentValue.trim());
                    }
                    currentLabel = label;
                    currentValue = trimmed.substring(label.length() + 1).trim();
                    isFieldLine = true;
                    break;
                }
            }
            if (!isFieldLine && currentLabel != null) {
                if (trimmed == 'Compliance Review Summary' || trimmed == 'Detailed Findings' || trimmed == 'Remediation Guidance') {
                    result.put(currentLabel, currentValue.trim());
                    currentLabel = null;
                } else {
                    currentValue += ' ' + trimmed;
                }
            }
        }
        if (currentLabel != null) {
            result.put(currentLabel, currentValue.trim());
        }
        return result;
    }

    private static String get(Map<String, String> parsed, String key) {
        String value = parsed.get(key);
        return value != null ? value : '';
    }

    // --- Invocable Input ---
    public class ComplianceReviewInput {
        @InvocableVariable(label='Raw payload' description='JSON string with response.text (e.g. AI compliance review response).' required=true)
        public String rawPayload;
    }

    // --- Invocable Output ---
    public class ComplianceReviewOutput {
        @InvocableVariable(label='Status' description='Compliant | Non-Compliant | Flagged for Review')
        public String status;
        @InvocableVariable(label='Risk Level' description='None | Low | Medium | High')
        public String riskLevel;
        @InvocableVariable(label='Assessment' description='Concise professional justification for the status.')
        public String assessment;
        @InvocableVariable(label='Detected Violation' description='Specific breach or N/A if compliant.')
        public String detectedViolation;
        @InvocableVariable(label='SOP Reference' description='Specific clause from context if a violation exists.')
        public String sopReference;
        @InvocableVariable(label='Reproduction of Concern' description='Exact segment that triggered the flag.')
        public String reproductionOfConcern;
        @InvocableVariable(label='Recommended Action' description='e.g. No action required or Corrective training.')
        public String recommendedAction;
        @InvocableVariable(label='Corrective Verbiage' description='Approved compliant alternative if applicable.')
        public String correctiveVerbiage;
    }
}