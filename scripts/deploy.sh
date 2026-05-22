#!/bin/bash
set -e

echo "=============================================="
echo " LSC4CE Compliance Validation Framework"
echo " Deployment Script"
echo "=============================================="
echo ""

TARGET_ORG="${1:-}"
SKIP_AGENTFORCE=false

for arg in "$@"; do
    case $arg in
        --skip-agentforce) SKIP_AGENTFORCE=true; shift ;;
    esac
done

ORG_FLAG=""
if [ -n "$TARGET_ORG" ]; then
    ORG_FLAG="--target-org $TARGET_ORG"
    echo "Target org: $TARGET_ORG"
else
    echo "Target org: default (set via sf config)"
fi
echo ""

command -v sf >/dev/null 2>&1 || { echo "Error: Salesforce CLI (sf) not installed. Install from https://developer.salesforce.com/tools/salesforcecli"; exit 1; }

echo "[1/8] Deploying Custom Objects..."
sf project deploy start --source-dir force-app/main/default/objects $ORG_FLAG --wait 10
echo ""

echo "[2/8] Deploying Apex Classes..."
sf project deploy start --source-dir force-app/main/default/classes $ORG_FLAG --wait 10
echo ""

echo "[3/8] Deploying Triggers..."
sf project deploy start --source-dir force-app/main/default/triggers $ORG_FLAG --wait 10
echo ""

echo "[4/8] Deploying Flows..."
sf project deploy start --source-dir force-app/main/default/flows $ORG_FLAG --wait 10
echo ""

echo "[5/8] Deploying Prompt Templates..."
sf project deploy start --source-dir force-app/main/default/genAiPromptTemplates/Visit_Note_Mapper.genAiPromptTemplate-meta.xml $ORG_FLAG --wait 10 || echo "  Warning: Visit_Note_Mapper deployment failed (requires Einstein Generative AI)"
echo ""

echo "[6/8] Deploying Permission Sets..."
sf project deploy start --source-dir force-app/main/default/permissionsets $ORG_FLAG --wait 10
echo ""

echo "[7/8] Deploying Lightning Web Components..."
sf project deploy start --source-dir force-app/main/default/lwc $ORG_FLAG --wait 10
echo ""

if [ "$SKIP_AGENTFORCE" = true ]; then
    echo "[8/8] Skipping Agentforce configuration (--skip-agentforce flag set)"
    echo ""
    echo "  Note: Agentforce components (GenAiPlugin, PlannerBundle, Bot) cannot be"
    echo "  deployed via metadata API to a new org. They must be configured manually"
    echo "  through Agent Builder. See docs/CONFIGURATION.md for instructions."
else
    echo "[8/8] Deploying Agentforce Configuration..."
    echo "  Note: These components often fail on first deploy to a new org due to"
    echo "  platform limitations. If they fail, configure via Agent Builder instead."
    echo ""
    sf project deploy start --source-dir force-app/main/default/genAiPromptTemplates/Compliance_Check.genAiPromptTemplate-meta.xml $ORG_FLAG --wait 10 || echo "  Warning: Compliance_Check template failed (requires Data Library with SOP documents)"
    sf project deploy start --source-dir force-app/main/default/genAiPlugins $ORG_FLAG --wait 10 || echo "  Warning: GenAiPlugin failed (known platform limitation — configure via Agent Builder)"
    sf project deploy start --source-dir force-app/main/default/genAiPlannerBundles $ORG_FLAG --wait 10 || echo "  Warning: PlannerBundle failed (depends on GenAiPlugin — configure via Agent Builder)"
    sf project deploy start --source-dir force-app/main/default/bots $ORG_FLAG --wait 10 || echo "  Warning: Bot failed (depends on PlannerBundle — configure via Agent Builder)"
fi
echo ""

echo "=============================================="
echo " Running Apex Tests"
echo "=============================================="
sf apex run test --test-level RunLocalTests $ORG_FLAG --wait 10 --result-format human
echo ""

echo "=============================================="
echo " Assigning Permission Set"
echo "=============================================="
sf org assign permset --name Compliance_Framework_Admin $ORG_FLAG
echo ""

echo "=============================================="
echo " Deployment Complete!"
echo "=============================================="
echo ""
echo "Next steps (manual configuration required):"
echo ""
echo "  1. Load sample compliance rules:"
echo "     sf apex run --file data/sample-rules.apex $ORG_FLAG"
echo ""
echo "  2. Create Agentforce marker rule:"
echo "     sf apex run --file data/create-agentforce-marker-rule.apex $ORG_FLAG"
echo ""
echo "  3. Configure Data Library + Prompt Template (see docs/CONFIGURATION.md)"
echo "  4. Activate Background Validation Flow (see docs/CONFIGURATION.md)"
echo "  5. Configure DbSchema for AppAlerts (see docs/CONFIGURATION.md)"
echo ""
echo "Full documentation: docs/IMPLEMENTATION-GUIDE.md"
