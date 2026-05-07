/**
 * @description Wrapper class to encapsulate Flow validation output
 * @author Nilotpal Paul
 * @date 2026-03-26
 */
public class FlowValidationResult {

    // Compliance status fields
    public Boolean isCompliant { get; set; }
    public String status { get; set; }
    public String riskLevel { get; set; }

    // Assessment details
    public String assessment { get; set; }
    public String detectedViolation { get; set; }
    public String sopReference { get; set; }

    // Reproduction and remediation
    public String reproductionOfConcern { get; set; }
    public String recommendedAction { get; set; }
    public String correctiveVerbiage { get; set; }

    /**
     * @description Default constructor
     */
    public FlowValidationResult() {
        this.isCompliant = true;
        this.status = 'Compliant';
        this.riskLevel = 'Low';
    }

    /**
     * @description Format error message for user display
     * Optimized for single-line inline display with clear separators
     * @return Formatted error message string
     */
    public String getErrorMessage() {
        if (this.isCompliant) {
            return 'No compliance issues detected.';
        }

        List<String> parts = new List<String>();

        // Start with icon and status
        String header = '⚠️ ' + (String.isNotBlank(this.status) ? this.status : 'Non-Compliant');

        // Add risk level if available
        if (String.isNotBlank(this.riskLevel)) {
            header += ' (' + this.riskLevel + ' Risk)';
        }
        parts.add(header);

        // Add flagged content
        if (String.isNotBlank(this.reproductionOfConcern)) {
            parts.add('Found: "' + this.reproductionOfConcern + '"');
        }

        // Add corrective action
        if (String.isNotBlank(this.correctiveVerbiage)) {
            parts.add('Action: ' + this.correctiveVerbiage);
        }

        return String.join(parts, ' | ');
    }

    /**
     * @description Get detailed information as JSON
     * @return JSON string with all field values
     */
    public String toJSON() {
        Map<String, Object> resultMap = new Map<String, Object>{
            'isCompliant' => this.isCompliant,
            'status' => this.status,
            'riskLevel' => this.riskLevel,
            'assessment' => this.assessment,
            'detectedViolation' => this.detectedViolation,
            'sopReference' => this.sopReference,
            'reproductionOfConcern' => this.reproductionOfConcern,
            'recommendedAction' => this.recommendedAction,
            'correctiveVerbiage' => this.correctiveVerbiage
        };

        return JSON.serialize(resultMap);
    }
}
