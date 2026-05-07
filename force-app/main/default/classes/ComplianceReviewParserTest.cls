@IsTest
private class ComplianceReviewParserTest {

    @IsTest
    static void testParseStructuredJson() {
        String payload = '{"response":{"text":{"Compliance Review Summary":{"Status":"Non-Compliant","Risk Level":"High","Detailed Findings":{"Assessment":"Off-label promotion detected","Detected Violation":"Discussed unapproved pediatric indication","SOP Reference":"SOP-COMP-001 Section 8.2","Reproduction of Concern":"for pediatric patients"},"Remediation Guidance":{"Recommended Action":"Remove pediatric reference","Corrective Verbiage":"Discussed approved adult indications only"}}}}}';

        ComplianceReviewParser.ComplianceReviewInput input = new ComplianceReviewParser.ComplianceReviewInput();
        input.rawPayload = payload;

        List<ComplianceReviewParser.ComplianceReviewOutput> results =
            ComplianceReviewParser.parseComplianceReview(new List<ComplianceReviewParser.ComplianceReviewInput>{ input });

        System.assertEquals(1, results.size());
        ComplianceReviewParser.ComplianceReviewOutput out = results[0];
        System.assertEquals('Non-Compliant', out.status);
        System.assertEquals('High', out.riskLevel);
        System.assertEquals('Off-label promotion detected', out.assessment);
        System.assertEquals('Discussed unapproved pediatric indication', out.detectedViolation);
        System.assertEquals('SOP-COMP-001 Section 8.2', out.sopReference);
        System.assertEquals('for pediatric patients', out.reproductionOfConcern);
        System.assertEquals('Remove pediatric reference', out.recommendedAction);
        System.assertEquals('Discussed approved adult indications only', out.correctiveVerbiage);
    }

    @IsTest
    static void testParsePlainText() {
        String textContent = 'Status: Non-Compliant\n'
            + 'Risk Level: Medium\n'
            + 'Assessment: Promotional language detected in visit notes\n'
            + 'Detected Violation: Superlative claims about drug efficacy\n'
            + 'SOP Reference: SOP-2024-001 Section 2.1\n'
            + 'Reproduction of Concern: best drug on the market\n'
            + 'Recommended Action: Remove superlative claims\n'
            + 'Corrective Verbiage: Clinically studied medication with demonstrated efficacy';
        String payload = '{"response":{"text":"' + textContent.replace('\n', '\\n') + '"}}';

        ComplianceReviewParser.ComplianceReviewInput input = new ComplianceReviewParser.ComplianceReviewInput();
        input.rawPayload = payload;

        List<ComplianceReviewParser.ComplianceReviewOutput> results =
            ComplianceReviewParser.parseComplianceReview(new List<ComplianceReviewParser.ComplianceReviewInput>{ input });

        System.assertEquals(1, results.size());
        ComplianceReviewParser.ComplianceReviewOutput out = results[0];
        System.assertEquals('Non-Compliant', out.status);
        System.assertEquals('Medium', out.riskLevel);
        System.assert(out.assessment.contains('Promotional language'));
        System.assert(out.detectedViolation.contains('Superlative'));
        System.assertEquals('SOP-2024-001 Section 2.1', out.sopReference);
        System.assertEquals('best drug on the market', out.reproductionOfConcern);
        System.assertEquals('Remove superlative claims', out.recommendedAction);
        System.assert(out.correctiveVerbiage.contains('Clinically studied'));
    }

    @IsTest
    static void testCompliantStructuredJson() {
        String payload = '{"response":{"text":{"Compliance Review Summary":{"Status":"Compliant","Risk Level":"None","Detailed Findings":{"Assessment":"No compliance violations detected","Detected Violation":"N/A","SOP Reference":"N/A","Reproduction of Concern":"N/A"},"Remediation Guidance":{"Recommended Action":"No action required","Corrective Verbiage":"N/A"}}}}}';

        ComplianceReviewParser.ComplianceReviewInput input = new ComplianceReviewParser.ComplianceReviewInput();
        input.rawPayload = payload;

        List<ComplianceReviewParser.ComplianceReviewOutput> results =
            ComplianceReviewParser.parseComplianceReview(new List<ComplianceReviewParser.ComplianceReviewInput>{ input });

        ComplianceReviewParser.ComplianceReviewOutput out = results[0];
        System.assertEquals('Compliant', out.status);
        System.assertEquals('None', out.riskLevel);
        System.assertEquals('No compliance violations detected', out.assessment);
        System.assertEquals('', out.detectedViolation, 'N/A should be filtered to empty');
        System.assertEquals('', out.sopReference, 'N/A should be filtered to empty');
        System.assertEquals('No action required', out.recommendedAction);
    }

    @IsTest
    static void testEmptyPayload() {
        ComplianceReviewParser.ComplianceReviewInput input = new ComplianceReviewParser.ComplianceReviewInput();
        input.rawPayload = '';

        List<ComplianceReviewParser.ComplianceReviewOutput> results =
            ComplianceReviewParser.parseComplianceReview(new List<ComplianceReviewParser.ComplianceReviewInput>{ input });

        System.assertEquals(1, results.size());
        System.assertEquals('', results[0].status);
        System.assertEquals('', results[0].riskLevel);
    }

    @IsTest
    static void testNullPayload() {
        ComplianceReviewParser.ComplianceReviewInput input = new ComplianceReviewParser.ComplianceReviewInput();
        input.rawPayload = null;

        List<ComplianceReviewParser.ComplianceReviewOutput> results =
            ComplianceReviewParser.parseComplianceReview(new List<ComplianceReviewParser.ComplianceReviewInput>{ input });

        System.assertEquals(1, results.size());
        System.assertEquals('', results[0].status);
    }

    @IsTest
    static void testInvalidJson() {
        ComplianceReviewParser.ComplianceReviewInput input = new ComplianceReviewParser.ComplianceReviewInput();
        input.rawPayload = 'this is not json at all {{{';

        List<ComplianceReviewParser.ComplianceReviewOutput> results =
            ComplianceReviewParser.parseComplianceReview(new List<ComplianceReviewParser.ComplianceReviewInput>{ input });

        System.assertEquals(1, results.size());
        System.assertEquals('', results[0].status);
    }

    @IsTest
    static void testNullInputList() {
        List<ComplianceReviewParser.ComplianceReviewOutput> results =
            ComplianceReviewParser.parseComplianceReview(null);

        System.assertEquals(0, results.size());
    }

    @IsTest
    static void testEmptyInputList() {
        List<ComplianceReviewParser.ComplianceReviewOutput> results =
            ComplianceReviewParser.parseComplianceReview(new List<ComplianceReviewParser.ComplianceReviewInput>());

        System.assertEquals(0, results.size());
    }

    @IsTest
    static void testMultipleInputs() {
        ComplianceReviewParser.ComplianceReviewInput input1 = new ComplianceReviewParser.ComplianceReviewInput();
        input1.rawPayload = '{"response":{"text":"Status: Compliant\\nRisk Level: None\\nAssessment: No issues"}}';

        ComplianceReviewParser.ComplianceReviewInput input2 = new ComplianceReviewParser.ComplianceReviewInput();
        input2.rawPayload = '{"response":{"text":"Status: Non-Compliant\\nRisk Level: Critical\\nAssessment: Violation found"}}';

        List<ComplianceReviewParser.ComplianceReviewOutput> results =
            ComplianceReviewParser.parseComplianceReview(
                new List<ComplianceReviewParser.ComplianceReviewInput>{ input1, input2 }
            );

        System.assertEquals(2, results.size());
        System.assertEquals('Compliant', results[0].status);
        System.assertEquals('Non-Compliant', results[1].status);
        System.assertEquals('Critical', results[1].riskLevel);
    }

    @IsTest
    static void testPartialFields() {
        String payload = '{"response":{"text":"Status: Non-Compliant\\nRisk Level: Low\\nAssessment: Minor issue detected"}}';

        ComplianceReviewParser.ComplianceReviewInput input = new ComplianceReviewParser.ComplianceReviewInput();
        input.rawPayload = payload;

        List<ComplianceReviewParser.ComplianceReviewOutput> results =
            ComplianceReviewParser.parseComplianceReview(new List<ComplianceReviewParser.ComplianceReviewInput>{ input });

        ComplianceReviewParser.ComplianceReviewOutput out = results[0];
        System.assertEquals('Non-Compliant', out.status);
        System.assertEquals('Low', out.riskLevel);
        System.assertEquals('Minor issue detected', out.assessment);
        System.assertEquals('', out.detectedViolation);
        System.assertEquals('', out.sopReference);
        System.assertEquals('', out.reproductionOfConcern);
    }
}
