/**
 * @description Wrapper class for compliance validation results
 * @group Compliance Framework
 */
public class ComplianceValidationResult {
    @AuraEnabled public Boolean isValid { get; set; }
    @AuraEnabled public String severity { get; set; }
    @AuraEnabled public String action { get; set; }
    @AuraEnabled public String message { get; set; }
    @AuraEnabled public String matchedContent { get; set; }
    @AuraEnabled public Compliance_Rule__c rule { get; set; }
    @AuraEnabled public String originalText { get; set; }
    @AuraEnabled public List<String> violations { get; set; }

    // Store full Flow result for additional context
    public FlowValidationResult flowResult { get; set; }

    // Store temporary ID for before insert alerts (to be updated in after insert)
    public String tempId { get; set; }

    /**
     * @description Constructor for valid result
     */
    public ComplianceValidationResult() {
        this.isValid = true;
        this.severity = null;
        this.action = null;
        this.message = null;
        this.matchedContent = null;
        this.rule = null;
        this.originalText = null;
    }

    /**
     * @description Constructor for failed validation result
     * @param rule The compliance rule that was violated
     * @param matchedContent The content that matched the rule
     * @param originalText The original text that was validated
     */
    public ComplianceValidationResult(Compliance_Rule__c rule, String matchedContent, String originalText) {
        this.isValid = false;
        this.severity = rule.Severity__c;
        this.action = rule.Action__c;
        this.message = rule.Remediation_Message__c;
        this.matchedContent = matchedContent;
        this.rule = rule;
        this.originalText = originalText;
    }

    /**
     * @description Build enhanced error message with specific details
     * @param contextLength Number of characters to show on each side of the matched content
     * @return User-friendly error message with matched keyword and context
     */
    public String buildEnhancedMessage(Integer contextLength) {
        List<String> parts = new List<String>();

        // Header with rule name and severity
        String header = '❌ ' + (rule != null ? rule.Name__c : 'Compliance Violation');
        if (String.isNotBlank(severity)) {
            header += ' - ' + severity;
        }
        parts.add(header);
        parts.add('');

        // Matched content
        if (String.isNotBlank(matchedContent)) {
            parts.add('Found: "' + matchedContent + '" in your text');
            parts.add('');
        }

        // Problem explanation (from first sentence of remediation message)
        String problem = extractProblemStatement(message);
        if (String.isNotBlank(problem)) {
            parts.add('Problem: ' + problem);
            parts.add('');
        }

        // Text excerpt with context
        if (String.isNotBlank(originalText) && String.isNotBlank(matchedContent)) {
            String excerpt = extractExcerpt(originalText, matchedContent, contextLength);
            if (String.isNotBlank(excerpt)) {
                parts.add('Text excerpt: "...' + excerpt + '..."');
                parts.add('');
            }
        }

        // Action required (from remediation message)
        String action = extractActionStatement(message);
        if (String.isNotBlank(action)) {
            parts.add('Action required: ' + action);
        }

        return String.join(parts, '\n');
    }

    /**
     * @description Extract problem statement from remediation message (first sentence)
     * @param remediationMessage The full remediation message
     * @return First sentence or first 100 characters
     */
    private String extractProblemStatement(String remediationMessage) {
        if (String.isBlank(remediationMessage)) {
            return null;
        }

        Integer periodIndex = remediationMessage.indexOf('.');
        if (periodIndex > 0 && periodIndex < 150) {
            return remediationMessage.substring(0, periodIndex + 1).trim();
        }

        return remediationMessage.length() > 100 ?
               remediationMessage.substring(0, 100) + '...' :
               remediationMessage;
    }

    /**
     * @description Extract action-oriented statement from remediation message
     * @param remediationMessage The full remediation message
     * @return Action-oriented sentence or full message
     */
    private String extractActionStatement(String remediationMessage) {
        if (String.isBlank(remediationMessage)) {
            return null;
        }

        String lowerMessage = remediationMessage.toLowerCase();
        List<String> actionKeywords = new List<String>{'please', 'remove', 'ensure', 'report', 'complete', 'revise', 'must'};

        for (String keyword : actionKeywords) {
            if (lowerMessage.contains(keyword)) {
                Integer keywordIndex = lowerMessage.indexOf(keyword);
                // Find sentence containing this keyword
                Integer sentenceStart = remediationMessage.lastIndexOf('.', keywordIndex);
                sentenceStart = sentenceStart < 0 ? 0 : sentenceStart + 1;

                Integer sentenceEnd = remediationMessage.indexOf('.', keywordIndex);
                sentenceEnd = sentenceEnd < 0 ? remediationMessage.length() : sentenceEnd + 1;

                return remediationMessage.substring(sentenceStart, sentenceEnd).trim();
            }
        }

        return remediationMessage;
    }

    /**
     * @description Extract text excerpt around the matched content
     * @param text The original text
     * @param matched The matched keywords (comma-separated)
     * @param contextLength Number of characters to include on each side
     * @return Text excerpt showing context around the violation
     */
    private String extractExcerpt(String text, String matched, Integer contextLength) {
        if (String.isBlank(text) || String.isBlank(matched)) {
            return null;
        }

        // Find first matched keyword in original text
        String lowerText = text.toLowerCase();
        List<String> keywords = matched.toLowerCase().split(',');

        Integer matchIndex = -1;
        Integer matchLength = 0;

        for (String keyword : keywords) {
            keyword = keyword.trim();
            Integer index = lowerText.indexOf(keyword);
            if (index >= 0) {
                matchIndex = index;
                matchLength = keyword.length();
                break;
            }
        }

        if (matchIndex < 0) {
            return null;
        }

        // Extract context around match
        Integer startIndex = Math.max(0, matchIndex - contextLength);
        Integer endIndex = Math.min(text.length(), matchIndex + matchLength + contextLength);

        String excerpt = text.substring(startIndex, endIndex);

        // Trim to word boundaries
        if (startIndex > 0) {
            Integer spaceIndex = excerpt.indexOf(' ');
            if (spaceIndex > 0 && spaceIndex < excerpt.length()) {
                excerpt = excerpt.substring(spaceIndex + 1);
            }
        }

        if (endIndex < text.length()) {
            Integer spaceIndex = excerpt.lastIndexOf(' ');
            if (spaceIndex > 0) {
                excerpt = excerpt.substring(0, spaceIndex);
            }
        }

        return excerpt.trim();
    }
}
