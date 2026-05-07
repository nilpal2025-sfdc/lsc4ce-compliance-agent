// Sample Compliance Rules for Life Sciences Cloud
// Run with: sf apex run --file data/sample-rules.apex --target-org <alias>

List<Compliance_Rule__c> rules = new List<Compliance_Rule__c>();

rules.add(new Compliance_Rule__c(
    Name__c = 'Off-Label Promotion Detection',
    Description__c = 'Detects off-label promotion language in visit notes. Off-label promotion is prohibited under FDA regulations (21 USC 331). Any discussion of indications not on the approved label must be reported.',
    Rule_Type__c = 'Keyword_Match',
    Keywords__c = 'off-label,off label,unapproved use,not approved for,not indicated for,experimental use,unapproved indication',
    Severity__c = 'Critical',
    Action__c = 'Block',
    Is_Active__c = true,
    Target_Object__c = 'ProviderVisit',
    Target_Field__c = 'NextProviderVisitObjective',
    Remediation_Message__c = 'This text contains off-label promotion language. Remove all references to unapproved uses or indications. Only discuss FDA-approved indications per your organization\'s promotional compliance SOP.'
));

rules.add(new Compliance_Rule__c(
    Name__c = 'Unapproved Patient Population',
    Description__c = 'Detects discussion of unapproved patient populations (e.g., pediatric use for an adult-only approved drug).',
    Rule_Type__c = 'Keyword_Match',
    Keywords__c = 'pediatric,children,adolescent,juvenile,infant,neonatal,under 18',
    Severity__c = 'Critical',
    Action__c = 'Block',
    Is_Active__c = true,
    Target_Object__c = 'ProviderVisit',
    Target_Field__c = 'NextProviderVisitObjective',
    Remediation_Message__c = 'Reference to an unapproved patient population detected. If this drug is not approved for this population, remove the reference. Discuss only approved indications and populations.'
));

rules.add(new Compliance_Rule__c(
    Name__c = 'Adverse Event Reporting Flag',
    Description__c = 'Flags adverse event mentions for mandatory reporting. Per FDA 21 CFR 314.80, serious adverse events must be reported within 15 days.',
    Rule_Type__c = 'Pattern_Match',
    Pattern__c = '(?i)(adverse event|serious adverse|SAE|side effect|adverse reaction).{0,50}(serious|severe|hospitali|death|life.?threatening)',
    Severity__c = 'High',
    Action__c = 'Warn',
    Is_Active__c = true,
    Target_Object__c = 'ProviderVisit',
    Target_Field__c = 'NextProviderVisitObjective',
    Remediation_Message__c = 'A potential adverse event was detected in your visit notes. Please ensure this is reported to Medical Affairs / Pharmacovigilance within 24 hours per your organization\'s AE reporting SOP. This note will be saved but flagged for review.'
));

rules.add(new Compliance_Rule__c(
    Name__c = 'Anti-Kickback Language Detection',
    Description__c = 'Detects language suggesting inducements or kickbacks in exchange for prescribing. Violates the Anti-Kickback Statute (42 USC 1320a-7b).',
    Rule_Type__c = 'Keyword_Match',
    Keywords__c = 'free samples in exchange,gift,kickback,quid pro quo,pay for prescriptions,incentive to prescribe,reward for prescribing',
    Severity__c = 'Critical',
    Action__c = 'Block',
    Is_Active__c = true,
    Target_Object__c = 'ProviderVisit',
    Target_Field__c = 'NextProviderVisitObjective',
    Remediation_Message__c = 'Language suggesting inducements for prescribing is prohibited under the Anti-Kickback Statute. Remove this content immediately and consult Legal/Compliance.'
));

insert rules;
System.debug('Successfully created ' + rules.size() + ' sample compliance rules:');
for (Compliance_Rule__c r : rules) {
    System.debug('  - ' + r.Name__c + ' (' + r.Severity__c + ' / ' + r.Action__c + ')');
}
