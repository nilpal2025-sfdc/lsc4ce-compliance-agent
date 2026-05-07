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

echo "[1/7] Deploying Custom Objects..."
sf project deploy start --source-dir force-app/main/default/objects $ORG_FLAG --wait 10
echo ""

echo "[2/7] Deploying Apex Classes..."
sf project deploy start --source-dir force-app/main/default/classes $ORG_FLAG --wait 10
echo ""

echo "[3/7] Deploying Triggers..."
sf project deploy start --source-dir force-app/main/default/triggers $ORG_FLAG --wait 10
echo ""

echo "[4/7] Deploying Flows..."
sf project deploy start --source-dir force-app/main/default/flows $ORG_FLAG --wait 10
echo ""

echo "[5/7] Deploying Permission Sets..."
sf project deploy start --source-dir force-app/main/default/permissionsets $ORG_FLAG --wait 10
echo ""

echo "[6/7] Deploying Lightning Web Components..."
sf project deploy start --source-dir force-app/main/default/lwc $ORG_FLAG --wait 10
echo ""

if [ "$SKIP_AGENTFORCE" = true ]; then
    echo "[7/7] Skipping Agentforce configuration (--skip-agentforce flag set)"
else
    echo "[7/7] Deploying Agentforce Configuration..."
    sf project deploy start --source-dir force-app/main/default/genAiPlugins $ORG_FLAG --wait 10 || echo "  Warning: genAiPlugins deployment failed (requires Einstein Agent license)"
    sf project deploy start --source-dir force-app/main/default/genAiPlannerBundles $ORG_FLAG --wait 10 || echo "  Warning: genAiPlannerBundles deployment failed (requires Einstein Agent license)"
    sf project deploy start --source-dir force-app/main/default/bots $ORG_FLAG --wait 10 || echo "  Warning: Bots deployment failed (requires Einstein Agent license)"
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
