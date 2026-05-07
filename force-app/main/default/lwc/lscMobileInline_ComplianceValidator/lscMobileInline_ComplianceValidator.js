import { LightningElement, api } from 'lwc';
import validateTextForScript from '@salesforce/apex/ComplianceScriptService.validateTextForScript';
import isValidationAvailable from '@salesforce/apex/ComplianceScriptService.isValidationAvailable';
import getObjectiveForVisit from '@salesforce/apex/ComplianceScriptService.getObjectiveForVisit';

export default class LscMobileInline_ComplianceValidator extends LightningElement {
    @api recordId;
    @api objectApiName;
    @api mobileHeight;

    objectiveText = '';
    objectiveLoaded = false;
    validationResult;
    isLoading = false;
    error;
    serviceAvailable = true;

    connectedCallback() {
        this.loadObjective();
        this.checkService();
    }

    async loadObjective() {
        if (!this.recordId) {
            this.objectiveLoaded = true;
            return;
        }
        try {
            const result = await getObjectiveForVisit({ visitId: this.recordId });
            this.objectiveText = result || '';
        } catch (e) {
            this.error = 'Could not load objective';
        }
        this.objectiveLoaded = true;
    }

    async checkService() {
        try {
            this.serviceAvailable = await isValidationAvailable();
        } catch (e) {
            this.serviceAvailable = false;
        }
    }

    get hasObjective() {
        return this.objectiveText && this.objectiveText.trim().length > 0;
    }

    get hasResult() {
        return !!this.validationResult;
    }

    get isCompliant() {
        return this.hasResult && this.validationResult.status === 'success';
    }

    get isNonCompliant() {
        return this.hasResult && this.validationResult.status === 'error';
    }

    get resultCardClass() {
        if (this.isCompliant) return 'result-card compliant';
        if (this.isNonCompliant) return 'result-card non-compliant';
        return 'result-card';
    }

    get riskBadgeClass() {
        if (!this.validationResult?.riskLevel) return 'risk-badge';
        const level = this.validationResult.riskLevel.toLowerCase();
        if (level === 'high' || level === 'critical') return 'risk-badge risk-high';
        if (level === 'medium') return 'risk-badge risk-medium';
        return 'risk-badge risk-low';
    }

    get hasRiskLevel() {
        return this.isNonCompliant && !!this.validationResult?.riskLevel;
    }

    get hasFlaggedContent() {
        return this.isNonCompliant && !!this.validationResult?.reproductionOfConcern;
    }

    get validateDisabled() {
        return !this.hasObjective || !this.serviceAvailable || this.isLoading;
    }

    get showUnavailable() {
        return this.objectiveLoaded && !this.serviceAvailable;
    }

    get showNoObjective() {
        return this.objectiveLoaded && !this.hasObjective && !this.error;
    }

    async handleValidate() {
        this.isLoading = true;
        this.error = null;
        this.validationResult = null;

        try {
            this.validationResult = await validateTextForScript({
                textContent: this.objectiveText
            });
        } catch (e) {
            this.error = 'Validation failed';
        } finally {
            this.isLoading = false;
        }
    }
}
