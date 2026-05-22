# Post-Deployment Configuration

After running `scripts/deploy.sh`, Method 2 (keyword/pattern trigger) is immediately active. The steps below enable the remaining LLM-based methods (1, 3, 5) and mobile/iPad features (3, 4).

**Time estimate:** ~30-45 minutes for Steps 1-4. Steps 5-8 are optional depending on which methods you need.

---

## 1. Create Data Library (Required for Methods 1, 3, 5)

The LLM-based validation methods use RAG (Retrieval-Augmented Generation) grounded in your organization's compliance SOPs. A [Data Library](https://help.salesforce.com/s/articleView?id=sf.generative_ai_ground_data_library.htm) is a container for documents that Einstein can search during validation.

1. Navigate to **Setup → search "Data Library" → Data Library**
2. Click **New Library**
3. Name: `LSC Field Sales Compliance Library`
4. Upload your compliance SOP documents (PDF or text format)
   - Example: Off-Label Prevention SOP, Adverse Event Reporting SOP, Anti-Kickback Policy
   - If you don't have SOPs yet, create a simple text file with your compliance rules for testing
5. Wait for indexing to complete (a green "Ready" status appears — typically 5-30 minutes)
6. Note the **Retriever ID**:
   - On the Data Library detail page, find the **Retriever** section
   - Copy the ID value (starts with `0pD` or similar) — you'll need this in Steps 2 and 3

## 2. Create Prompt Template (Required for Methods 1, 3, 5)

A [Prompt Template](https://help.salesforce.com/s/articleView?id=sf.prompt_builder_about.htm) tells Einstein how to evaluate visit notes against your compliance SOPs. You'll create one from scratch (don't deploy the repo's version — it references the source org's Data Library).

1. Navigate to **Setup → search "Prompt Builder" → Prompt Builder**
2. Click **New Prompt Template**
3. Configure:
   - **Name:** `Compliance_Check`
   - **API Name:** `Compliance_Check`
   - **Template Type:** Flex
4. Add **Input** parameters (click "+ Add Input"):
   - `Query` (Type: Text, Required: Yes) — The visit note text to evaluate
5. Add **Grounding** (click "Add Data Source"):
   - Select your Data Library from Step 1
   - Search input: map to `{!$Input:Query}`
6. Set the **Prompt Instruction** — copy the text below into the template body:

```
System Role: You are a Senior Compliance Auditor for Salesforce Life Sciences Cloud. Your goal is to identify definitive regulatory violations in Field Rep notes. You must distinguish between administrative mentions (e.g., "I discussed [Product] with [Doctor]") and promotional claims (e.g., "[Product] works for [Unapproved Disease]"). Do not flag interactions that merely name an approved product without further context suggesting off-label discussion.

Input Data:
Field Rep Utterance: {!$Input:Query}
Retrieved SOP Context: {!$EinsteinSearch:YOUR_DATA_LIBRARY_RETRIEVER.results}

Analysis Protocol:
- Contextual Validation: Does the utterance contain a specific medical claim, a patient population, or a clinical trial keyword? If the utterance is a general statement of a meeting occurring, it is Compliant.
- Negative Evidence Check: Before flagging a violation, you must identify a specific "Prohibited Element" (e.g., an unapproved indication like HFpEF, or a pipeline keyword like "Phase III").
- Strict Construction: Do not infer or hallucinate details not present in the text. If the text says "I discussed Immunexis," and the SOP lists Immunexis as an approved product, this is a standard activity.

Response Schema:
Compliance Review Summary
Status: [Compliant | Non-Compliant | Flagged for Review]
Risk Level: [None | Low | Medium | High]

Detailed Findings
Assessment: (Provide a concise professional justification for the status.)
Detected Violation: (N/A if compliant. Otherwise, describe the specific breach.)
SOP Reference: (Cite the specific clause from the retrieved context if a violation exists.)
Reproduction of Concern: (Quote the exact segment that triggered the flag.)

Remediation Guidance
Recommended Action: (e.g., "No action required" or "Corrective training.")
Corrective Verbiage: (Rewrite the ORIGINAL Field Rep Utterance with ONLY the violating portion replaced by the nearest approved indication. Preserve ALL non-violating content exactly as written.)
```

> **Important:** Replace `YOUR_DATA_LIBRARY_RETRIEVER` in the prompt with the reference name that Prompt Builder generates when you add your Data Library as a grounding source. It will look something like `File_LSC_Field_Sales_Compliance_Library_XXXXX`.

7. Click **Save** then **Activate**

## 3. Deploy and Configure Compliance Check Flow (Required for Methods 1, 3, 5)

These flows are excluded from the default deployment (via `.forceignore`) because they depend on the Data Library and Prompt Template you just configured. Deploy them now:

```bash
sf project deploy start \
  --source-dir force-app/main/default/flows/Visit_Logging_Compliance_Check.flow-meta.xml \
  --target-org my-org

sf project deploy start \
  --source-dir force-app/main/default/flows/ProviderVisit_Compliance_Background_Validation.flow-meta.xml \
  --target-org my-org
```

> **If the flow deploy fails** with "can't find Compliance_Check action": the prompt template API name doesn't match. Verify your template is named exactly `Compliance_Check` in Setup → Prompt Builder.

After deploying, update the Retriever ID in the flow:

1. Navigate to **Setup → search "Flows" → Flows**
2. Open `Visit_Logging_Compliance_Check` (click the flow name, not "Edit")
3. Click **Edit** to open in Flow Builder
4. Find the **Generate Prompt Response** element (named `Compliance_Check_for_Voice_Visit_Logging`)
5. Click it → find the `RetrieverIdOrName` input parameter
6. Replace the value with your Data Library's Retriever ID from Step 1
7. Click **Save** → **Activate**

## 4. Activate Background Validation Flow (Required for Method 3)

The background validation flow was deployed in **Draft** status for safety.

1. Navigate to **Setup → Flows**
2. Find `ProviderVisit_Compliance_Background_Validation`
3. Click **Activate**

**What this flow does:** After a ProviderVisit record is saved, it runs the compliance check asynchronously. If non-compliant, it creates an AppAlert and routes it to the rep's territory for mobile delivery.

**Entry Conditions:** Fires when `NextProviderVisitObjective` is not null AND has changed.

## 5. Configure Agentforce Agent (Required for Method 1)

If your org has Agentforce licensing, configure the compliance-first agent:

1. Navigate to **Setup → search "Agents" → Agents** (or "Einstein Copilot")
2. Click **New Agent** (or edit an existing one)
3. Create a Topic called `PostCallVisitNotes`:
   - Add two Actions in this order:
     - Action 1: `Visit_Logging_Compliance_Check` (the flow from Step 3)
     - Action 2: `Visit_Note_Processor_Simple` (already deployed)
   - Add instructions: "Always run the compliance check BEFORE processing visit notes. Only call Visit_Note_Processor_Simple if the compliance check returns Compliant status."
4. Add sample utterances: "Log my visit notes", "Process my post-call notes", "I just met with Dr. Smith"
5. Click **Activate**

> **Reference:** The full agent configuration (instructions, utterances, orchestration logic) is in `force-app/main/default/genAiPlannerBundles/Compliant_Visit_Logging/` — use it as a guide when configuring manually.

If you're not using Agentforce, skip this step. Methods 2-5 work independently.

## 6. Configure DbSchema for AppAlerts (Required for Method 3 on mobile)

For AppAlerts to reach the iPad via [LSC Mobile](https://help.salesforce.com/s/articleView?id=sf.ls_mobile_setup.htm):

1. Navigate to **Setup → search "Life Sciences" → Life Sciences Cloud → Mobile Configuration** (or use the LSC Admin Console)
2. Ensure `AppAlert` and `AppAlertTerritory` objects are included in the mobile metadata cache (DbSchema)
3. Set sync interval to 15 minutes (recommended)
4. Verify: Users must have an active Territory assignment (`UserTerritory2Association` record) for alert routing to work

## 7. Configure Custom Script in Visit Engagement (Required for Method 4)

1. Navigate to **Setup → search "Visit Engagement" → Visit Engagement → Custom Scripts**
2. Add a new custom script configuration:
   - **Script:** `complianceValidationScript`
   - **Target Object:** ProviderVisit
   - **Trigger Event:** On Submit / On Action (per your preference)
3. The script validates `NextProviderVisitObjective` and `PreProviderVisitNotes` fields client-side

## 8. Configure LWC on Visit Record Page (Required for Method 5)

1. Navigate to **Setup → Object Manager → search "ProviderVisit" → Lightning Record Pages**
2. Edit the active record page (click the page name → **Edit**)
3. Add a new **Tab** in the page layout → name it "Compliance"
4. In the Components panel (left sidebar), search for `Compliance Validator`
5. Drag the `Compliance Validator (LMR Inline)` component into the Compliance tab
6. In the component properties (right panel), set `mobileHeight` to `450`
7. Click **Save** → **Activate** (choose "Assign as Org Default" if prompted)

---

## Verification

After completing all steps, verify the full solution:

```bash
# Check rules are active
sf data query --query "SELECT Name__c, Is_Active__c, Action__c FROM Compliance_Rule__c WHERE Is_Active__c = true" --target-org my-org

# Check flows are active
sf data query --query "SELECT ApiName, ActiveVersionNumber FROM FlowDefinitionView WHERE ApiName LIKE '%Compliance%' OR ApiName = 'Visit_Note_Processor_Simple'" --target-org my-org
```

### Test Each Method

| Method | How to Test |
|--------|-------------|
| 1 (Agentforce) | Open agent panel → type "Log visit: discussed off-label use of Cordim for HFpEF" → Should return compliance violation with corrective verbiage |
| 2 (Trigger) | Edit a ProviderVisit → set objective to "Discussed off-label use" → Save → Save is blocked with error |
| 3 (Background) | Save a ProviderVisit with subtly non-compliant text (passes keyword check but fails semantic) → Check `Compliance_Alert__c` records after ~1 minute |
| 4 (Custom Script) | On iPad in Visit Engagement, enter "off-label" in the objective field → Submit is blocked |
| 5 (LWC) | Open a ProviderVisit record → Compliance tab → Click "Validate" → Red violation card appears |

---

## Org-Specific Values to Replace

| Value | Where | What to Replace With |
|-------|-------|---------------------|
| Retriever ID | `Visit_Logging_Compliance_Check` flow, `RetrieverIdOrName` parameter | Your Data Library Retriever ID (from Step 1) |
| Data Library reference | `Compliance_Check` prompt template grounding source | Your Data Library name |
| Territory Model | Background validation flow routing | Your active Territory2 model |

---

## Glossary

| Term | Meaning |
|------|---------|
| **RAG** | Retrieval-Augmented Generation — LLM queries a knowledge base (your SOPs) before answering |
| **Data Library** | A Salesforce feature that indexes documents for Einstein to search |
| **Prompt Template** | A reusable instruction set that tells Einstein how to process input and format output |
| **GenAiPlugin / PlannerBundle** | Salesforce metadata types that define Agentforce agent topics and orchestration |
| **DbSchema** | The mobile metadata cache configuration — controls which objects sync to iPad |
| **AppAlert** | A mobile notification record routed by territory — appears on the LSC iPad app |
| **Territory2** | Salesforce Enterprise Territory Management — used for alert routing |
| **`.forceignore`** | A file that tells Salesforce CLI which metadata to skip during deploy/push operations |
