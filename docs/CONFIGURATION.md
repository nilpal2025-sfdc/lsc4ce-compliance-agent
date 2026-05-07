# Post-Deployment Configuration

After running `scripts/deploy.sh`, these manual steps are required to fully enable all 5 validation methods.

---

## 1. Create Data Library (Required for Methods 1, 3, 5)

The LLM-based validation methods use RAG (Retrieval-Augmented Generation) grounded in your organization's compliance SOPs.

1. Navigate to **Setup > Data Library**
2. Click **New Library**
3. Name: `LSC Field Sales Compliance Library` (or your preferred name)
4. Upload your compliance SOP documents (PDF or text format)
   - Example: Off-Label Prevention SOP, Adverse Event Reporting SOP, Anti-Kickback Policy
5. Wait for indexing to complete (typically 5-30 minutes)
6. Note the **Retriever ID** — you'll need this in Step 2

## 2. Create Prompt Template (Required for Methods 1, 3, 5)

1. Navigate to **Setup > Prompt Templates**
2. Click **New Prompt Template**
3. Configure:
   - **Name:** `Compliance_Check`
   - **API Name:** `Compliance_Check`
   - **Type:** Flex (or Generation)
4. Add input parameters:
   - `Query` (String) — The text to evaluate
   - `RetrieverIdOrName` (String) — The Data Library retriever ID from Step 1
5. Set grounding source: Your Data Library from Step 1
6. Set the prompt instruction to evaluate text against compliance SOPs and return structured JSON with: Status, Risk Level, Assessment, Detected Violation, SOP Reference, Reproduction of Concern, Recommended Action, Corrective Verbiage

## 3. Update Flow Retriever ID (Required for Methods 1, 3, 5)

1. Navigate to **Setup > Flows**
2. Open `Visit_Logging_Compliance_Check`
3. Find the **Generate Prompt Response** element (`Compliance_Check_for_Voice_Visit_Logging`)
4. Update the `RetrieverIdOrName` input parameter to your Data Library's Retriever ID
5. Save and activate

## 4. Activate Background Validation Flow (Required for Method 3)

The background validation flow deploys in **Draft** status for safety.

1. Navigate to **Setup > Flows**
2. Find `ProviderVisit_Compliance_Background_Validation`
3. Click **Activate**

**Entry Conditions:** This flow fires when:
- `NextProviderVisitObjective` is not null AND has changed
- Record is created or updated

**What it does:** Runs the compliance check asynchronously after save, creates an AppAlert if non-compliant, and routes it to the rep's territory for mobile delivery.

## 5. Configure Agentforce Agent (Required for Method 1)

If you deployed with Agentforce configuration:

1. Navigate to **Setup > Agents** (or Einstein Copilot)
2. Find the `Compliant Visit Logging` agent
3. Verify the topic `PostCallVisitNotes` has two actions:
   - Action 1: `Visit_Logging_Compliance_Check` (compliance gate)
   - Action 2: `Visit_Note_Processor_Simple` (note processing)
4. Verify orchestration instructions enforce compliance-first ordering
5. Activate the agent

If you deployed with `--skip-agentforce`, create the agent manually per the instructions in [IMPLEMENTATION-GUIDE.md](IMPLEMENTATION-GUIDE.md#5-agentforce-agent-configuration).

## 6. Configure DbSchema for AppAlerts (Required for Method 3 on mobile)

For AppAlerts to reach the iPad:

1. Navigate to **Setup > Life Sciences Cloud > Mobile Configuration** (or use the LSC Admin Console)
2. Ensure `AppAlert` and `AppAlertTerritory` objects are included in the mobile metadata cache (DbSchema)
3. Set an appropriate sync interval (recommended: 15 minutes)
4. Users must have an active `UserTerritory2Association` for territory-based routing

## 7. Configure Custom Script in Visit Engagement (Required for Method 4)

1. Navigate to **Setup > Visit Engagement > Custom Scripts**
2. Add a new custom script configuration:
   - **Script:** `complianceValidationScript`
   - **Target Object:** ProviderVisit
   - **Trigger Event:** On Submit / On Action (per your preference)
3. The script validates `NextProviderVisitObjective` and `PreProviderVisitNotes` fields

## 8. Configure LWC on Visit Record Page (Required for Method 5)

1. Navigate to **Setup > Object Manager > ProviderVisit > Lightning Record Pages**
2. Edit the active record page
3. Add a new **Tab** → name it "Compliance"
4. Drag the `Compliance Validator (LMR Inline)` component into the tab
5. Set `mobileHeight` property (recommended: 400-500 for iPad)
6. Save and activate

---

## Verification

After completing all steps, verify the full solution:

```bash
# Check rules are active
sf data query --query "SELECT Name__c, Is_Active__c, Action__c FROM Compliance_Rule__c WHERE Is_Active__c = true" --target-org <alias>

# Check flows are active
sf data query --query "SELECT ApiName, ActiveVersionNumber FROM FlowDefinitionView WHERE ApiName LIKE '%Compliance%' OR ApiName = 'Visit_Note_Processor_Simple'" --target-org <alias>
```

### Test Each Method

| Method | Test |
|--------|------|
| 1 (Agentforce) | Open agent panel → "Log visit: discussed off-label use" → Should return violation |
| 2 (Trigger) | Save ProviderVisit with "off-label" in objective → Save blocked |
| 3 (Background) | Save compliant-to-keyword but semantically violating text → AppAlert created async |
| 4 (Custom Script) | On iPad Visit Engagement, enter violating text → Submit blocked |
| 5 (LWC) | On Visit record Compliance tab → Click "Validate" → Red card with violation |

---

## Org-Specific Values to Replace

| Value | Where | What to Replace With |
|-------|-------|---------------------|
| RAG Retriever ID | `Visit_Logging_Compliance_Check` flow | Your Data Library Retriever ID |
| Prompt Template | Flow element | Your `Compliance_Check` template reference |
| Territory Model | Background flow | Your active Territory2 model |
