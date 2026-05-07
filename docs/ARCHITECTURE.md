# Architecture

## High-Level Architecture

```mermaid
flowchart TB
    subgraph "User Surfaces"
        AF[Agentforce Panel]
        WEB[Web Lightning UI]
        IPAD[iPad Visit Agent]
    end

    subgraph "Method 1: Agentforce LLM"
        AF --> FLOW1[Visit_Logging_Compliance_Check]
        FLOW1 --> PT[Prompt Template + RAG]
        PT --> PARSER[ComplianceReviewParser]
    end

    subgraph "Method 2: Keyword/Pattern Trigger"
        WEB --> TRIGGER[ProviderVisitComplianceTrigger]
        IPAD --> TRIGGER
        TRIGGER --> ENGINE[ComplianceRuleEngine]
        ENGINE --> RULES[(Compliance_Rule__c)]
    end

    subgraph "Method 3: Background LLM + AppAlert"
        TRIGGER --> |after save| BGFLOW[Background Validation Flow]
        BGFLOW --> FLOW1
        BGFLOW --> APPALERT[AppAlert + Territory]
        APPALERT --> |sync| IPAD
    end

    subgraph "Method 4: Custom Script"
        IPAD --> |pre-save| SCRIPT[complianceValidationScript.js]
        SCRIPT --> RULES
    end

    subgraph "Method 5: On-Demand LWC"
        WEB --> LWC[lscMobileInline_ComplianceValidator]
        LWC --> FLOW1
    end

    subgraph "Data Layer"
        PARSER --> ALERT[(Compliance_Alert__c)]
        ENGINE --> ALERT
        BGFLOW --> ALERT
        PARSER --> AUDIT[(Compliance_Audit_Log__c)]
        ENGINE --> AUDIT
    end
```

## Validation Method Comparison

| # | Method | Timing | Validation Type | Blocks Save? | Network Required? |
|---|--------|--------|-----------------|:---:|:---:|
| 1 | Agentforce LLM | Pre-save (conversational) | Semantic (LLM + RAG) | Yes (agent refuses) | Yes |
| 2 | Keyword/Pattern Trigger | On save (synchronous) | Deterministic | Yes (if Block) | No |
| 3 | Background LLM + AppAlert | Post-save (async) | Semantic (LLM + RAG) | No (advisory) | Yes |
| 4 | Custom Script | Pre-save (client-side) | Deterministic | Yes (if Block) | No |
| 5 | LWC Compliance Tab | On-demand (button) | Semantic (LLM + RAG) | No (advisory) | Yes |

## Class Dependency Graph

```mermaid
graph TD
    TRIGGER[ProviderVisitComplianceTrigger] --> SERVICE[ComplianceValidationService]
    SERVICE --> ENGINE[ComplianceRuleEngine]
    ENGINE --> FLOW_SVC[ComplianceFlowService]
    ENGINE --> RESULT[ComplianceValidationResult]
    FLOW_SVC --> FLOW_RESULT[FlowValidationResult]
    CONTROLLER[ComplianceValidationController] --> SERVICE
    CONTROLLER --> FLOW_SVC
    SCRIPT_SVC[ComplianceScriptService] --> FLOW_SVC
    LWC[lscMobileInline_ComplianceValidator] --> SCRIPT_SVC
    FLOW[Visit_Logging_Compliance_Check] --> PARSER[ComplianceReviewParser]
```

## Data Model

```mermaid
erDiagram
    Compliance_Rule__c {
        AutoNumber Name
        Text Name__c
        Picklist Rule_Type__c
        LongText Keywords__c
        LongText Pattern__c
        Picklist Severity__c
        Picklist Action__c
        Checkbox Is_Active__c
        Text Target_Object__c
        Text Target_Field__c
        LongText Remediation_Message__c
    }

    Compliance_Alert__c {
        AutoNumber Name
        Text Alert_Name__c
        DateTime Alert_Date__c
        Lookup Rule__c
        Text Record_Id__c
        Text Record_Type__c
        Picklist Severity__c
        Picklist Status__c
        Lookup User__c
        LongText Original_Value__c
        LongText Matched_Content__c
        Lookup App_Alert_Id__c
    }

    Compliance_Audit_Log__c {
        AutoNumber Name
        Lookup Rule__c
        Text Record_Id__c
        Text Record_Type__c
        Text Validation_Result__c
        Lookup User__c
        DateTime Timestamp__c
        Number Execution_Time_Ms__c
        LongText Details__c
    }

    Compliance_Rule__c ||--o{ Compliance_Alert__c : "violated by"
    Compliance_Rule__c ||--o{ Compliance_Audit_Log__c : "evaluated in"
```

## Method 2 Sequence (Trigger — Primary Real-Time Validation)

```mermaid
sequenceDiagram
    participant Rep as Field Rep
    participant SF as Salesforce Save
    participant Trigger as ProviderVisitComplianceTrigger
    participant Service as ComplianceValidationService
    participant Engine as ComplianceRuleEngine
    participant DB as Salesforce DB

    Rep->>SF: Save ProviderVisit (NextProviderVisitObjective = text)
    SF->>Trigger: before insert/update
    Trigger->>Service: validateRecord(visit, 'NextProviderVisitObjective')
    Service->>Engine: validateText('ProviderVisit', field, text, id)
    Engine->>DB: Query active rules (cached)
    DB-->>Engine: List of Compliance_Rule__c
    loop Each active rule
        Engine->>Engine: matchesKeywords() or matchesPattern()
        Engine->>Engine: logValidation() (batch)
    end
    Engine-->>Service: List of ComplianceValidationResult
    Service->>DB: createAlertImmediate() if violation
    Service-->>Trigger: ComplianceValidationResult
    alt action = Block
        Trigger->>SF: visit.addError(field, enhancedMessage)
        SF-->>Rep: Save blocked with error message
    else action = Warn
        Trigger->>Trigger: System.debug(warning)
        SF-->>Rep: Save succeeds (alert created silently)
    end
```

## Method 3 Sequence (Background LLM + AppAlert)

```mermaid
sequenceDiagram
    participant iPad as iPad (Offline)
    participant Sync as Mobile Sync
    participant SF as Salesforce
    participant BGFlow as Background Validation Flow
    participant LLM as Visit_Logging_Compliance_Check
    participant DB as Salesforce DB

    iPad->>iPad: Rep writes visit notes offline
    iPad->>Sync: Sync to server
    Sync->>SF: Insert/Update ProviderVisit
    SF->>BGFlow: Record-Triggered (After Save)
    BGFlow->>LLM: Subflow call (text = objective)
    LLM-->>BGFlow: ComplianceStatus, RiskLevel, etc.
    alt Non-Compliant
        BGFlow->>DB: Create Compliance_Alert__c
        BGFlow->>DB: Create AppAlert
        BGFlow->>DB: Create AppAlertTerritory
        DB-->>iPad: Next sync delivers notification
    else Compliant
        Note over BGFlow: No action needed
    end
```

## Key Design Decisions

| Decision | Rationale |
|----------|-----------|
| LLM disabled in sync trigger path | LLM calls (2-5s) would cause mobile sync timeouts for batch operations |
| Fail-open on errors | A broken compliance system must not halt all field operations |
| Rule caching per-transaction | Prevents repeated SOQL during bulk saves (e.g., 200 visits syncing) |
| Batch audit log flushing | Single DML for all audit logs prevents governor limit issues |
| Temp ID pattern for before-insert | Alerts need record IDs; before-insert records have none yet |
| Exact-match "Compliant" only | Any ambiguous LLM response (blank, partial, etc.) is treated as non-compliant |
