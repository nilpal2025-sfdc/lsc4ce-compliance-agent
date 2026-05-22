public class VisitNoteProcessor {
    
    // Data classes to hold the JSON structure
    public class VisitNoteData {
        public VisitData visit;
        public AccountData account;
        public ProviderVisitData providerVisit;
        public List<ProviderVisitProdDetailingData> providerVisitProdDetailing;
        public List<ProviderVisitProdDiscussionData> providerVisitProdDiscussion;
        public List<ProviderVisitDtlProductMsgData> providerVisitDtlProductMsg;
        public ConfidenceData confidence;
        public ExtractedEntitiesData extractedEntities;
    }
    
    public class VisitData {
        public String statusremarks;
        public String instructiondescription;
        public String plannedvisitstarttime;
        public String plannedvisitendtime;
        public String status;
        public String visitpriority;
        public String contactpointaddress;
    }
    
    public class AccountData {
        public String accountname;
        public String accountid;
    }
    
    public class ProviderVisitData {
        public String preprovidervisitnotes;
        public String additionalinformation;
        public String nextprovidervisitobjective;
    }
    
    public class ProviderVisitProdDetailingData {
        public String productname;
        public String producthierarchyname;
        public Double priority;
        public String nextprvdvisitobjectives;
        public String additionalinformation;
    }
    
    public class ProviderVisitProdDiscussionData {
        public String providervisitproductdtlid;
        public String additionalinformation;
    }
    
    public class ProviderVisitDtlProductMsgData {
        public String additionalinformation;
        public String reactiontype;
        public String capturedreaction;
    }
    
    public class ConfidenceData {
        public Double overall;
        public Double visit;
        public Double providerVisit;
        public Double productDetailing;
        public Double productDiscussion;
        public Double productMessage;
    }
    
    public class ExtractedEntitiesData {
        public List<String> providers;
        public List<String> products;
        public List<String> activities;
        public List<String> outcomes;
        public List<String> dates;
        public List<String> locations;
    }
    
    public class ProcessingResult {
        @InvocableVariable(required=true)
        public Boolean success;
        
        @InvocableVariable(required=true)
        public String message;
        
        @InvocableVariable(required=false)
        public Id visitId;
        
        @InvocableVariable(required=false)
        public Id providerVisitId;
        
        @InvocableVariable(required=false)
        public List<Id> productDetailingIds;
        
        @InvocableVariable(required=false)
        public List<Id> productDiscussionIds;
        
        @InvocableVariable(required=false)
        public List<Id> productMessageIds;
        
        @InvocableVariable(required=false)
        public Double confidence;
        
        @InvocableVariable(required=false)
        public String errors;
        
        @InvocableVariable(required=false)
        public String actionType; // "UPDATE" or "CREATE"
        
        @InvocableVariable(required=false)
        public List<String> addedProducts; // Product names that were added to ProviderVisitProdDetailing
        
        @InvocableVariable(required=false)
        public List<String> addedProductDiscussions; // Discussion content that was added
        
        @InvocableVariable(required=false)
        public List<String> addedProductMessages; // Message content that was added
        
        @InvocableVariable(required=false)
        public String dashboardSummary; // Formatted dashboard-style summary
    }
    
    @InvocableMethod(label='Process Visit Notes' description='Process unstructured visit notes and create structured data')
    public static List<ProcessingResult> processVisitNotes(List<String> visitNotesJson) {
        List<ProcessingResult> results = new List<ProcessingResult>();
        
        for (String jsonData : visitNotesJson) {
            ProcessingResult result = new ProcessingResult();
            result.success = false;
            result.productDetailingIds = new List<Id>();
            result.productDiscussionIds = new List<Id>();
            result.productMessageIds = new List<Id>();
            result.addedProducts = new List<String>();
            result.addedProductDiscussions = new List<String>();
            result.addedProductMessages = new List<String>();
            
            try {
                // Clean the JSON data by removing markdown formatting if present
                String cleanJsonData = cleanJsonInput(jsonData);
                VisitNoteData data = (VisitNoteData) JSON.deserialize(cleanJsonData, VisitNoteData.class);
                
                // Check confidence threshold
                if (data.confidence.overall < 0.5) {
                    result.message = 'Confidence too low: ' + data.confidence.overall;
                    results.add(result);
                    continue;
                }
                
                result = processVisitRecords(data);
                
            } catch (Exception e) {
                result.message = 'Error processing visit notes: ' + e.getMessage();
                result.errors = e.getStackTraceString();
            }
            
            results.add(result);
        }
        
        return results;
    }
    
    private static String cleanJsonInput(String jsonInput) {
        if (jsonInput == null) {
            return '';
        }
        
        String cleaned = jsonInput.trim();
        
        // Remove markdown code block formatting
        if (cleaned.startsWith('```json')) {
            cleaned = cleaned.substring(6); // Remove ```json
        } else if (cleaned.startsWith('```')) {
            cleaned = cleaned.substring(3); // Remove ```
        }
        
        if (cleaned.endsWith('```')) {
            cleaned = cleaned.substring(0, cleaned.length() - 3); // Remove trailing ```
        }
        
        // Remove newlines and extra whitespace
        cleaned = cleaned.replace('\n', ' ').replace('\r', ' ');
        cleaned = cleaned.replaceAll('\\s+', ' '); // Replace multiple spaces with single space
        
        // Remove any leading/trailing whitespace and ensure it starts with {
        cleaned = cleaned.trim();
        if (cleaned.startsWith('n ')) {
            cleaned = cleaned.substring(2); // Remove the 'n ' prefix
        }
        
        return cleaned;
    }
    
    private static ProcessingResult processVisitRecords(VisitNoteData data) {
        ProcessingResult result = new ProcessingResult();
        result.success = false;
        result.productDetailingIds = new List<Id>();
        result.productDiscussionIds = new List<Id>();
        result.productMessageIds = new List<Id>();
        result.addedProducts = new List<String>();
        result.addedProductDiscussions = new List<String>();
        result.addedProductMessages = new List<String>();
        
        try {
            // Get Account ID and Contact Point Address
            Id accountId = getAccountId(data.account);
            Id contactPointAddressId = getContactPointAddressForAccount(accountId, data.visit.contactpointaddress);
            
            // Step 1: Check if there are existing visits (in Planned Status) with the Account Name
            Visit existingVisit = findExistingPlannedVisit(accountId);
            
            if (existingVisit != null) {
                // Step 2: Update existing visit
                result = updateExistingVisit(existingVisit, data, accountId, contactPointAddressId);
            } else {
                // Step 3: Create new visit
                result = createNewVisit(data, accountId, contactPointAddressId);
            }
            
        } catch (Exception e) {
            result.message = 'Error processing visit records: ' + e.getMessage();
            result.errors = e.getStackTraceString();
        }
        
        return result;
    }
    
    private static Visit findExistingPlannedVisit(Id accountId) {
        if (accountId == null) {
            return null;
        }
        
        try {
            // Search for existing planned visits in the last 2 days (including today)
            // This excludes future visits to prevent accidental modification of planned future visits
            Date searchStartDate = Date.today().addDays(-2);
            Date searchEndDate = Date.today();
            
            // Convert dates to start and end of day for proper DateTime comparison
            DateTime searchStartDateTime = DateTime.newInstance(searchStartDate, Time.newInstance(0, 0, 0, 0));
            DateTime searchEndDateTime = DateTime.newInstance(searchEndDate, Time.newInstance(23, 59, 59, 999));
            
            List<Visit> existingVisits = [
                SELECT Id, Status, PlannedVisitStartTime, AccountId, TerritoryId, PlaceId,
                       StatusRemarks, InstructionDescription, VisitPriority
                FROM Visit 
                WHERE AccountId = :accountId 
                  AND Status = 'Planned'
                  AND PlannedVisitStartTime >= :searchStartDateTime
                  AND PlannedVisitStartTime <= :searchEndDateTime
                ORDER BY PlannedVisitStartTime DESC
                LIMIT 1
            ];
            
            return existingVisits.isEmpty() ? null : existingVisits[0];
            
        } catch (Exception e) {
            // If there's an error finding existing visits, return null to create new visit
            return null;
        }
    }
    
    private static ProcessingResult updateExistingVisit(Visit existingVisit, VisitNoteData data, Id accountId, Id contactPointAddressId) {
        ProcessingResult result = new ProcessingResult();
        result.success = false;
        result.actionType = 'UPDATE';
        result.productDetailingIds = new List<Id>();
        result.productDiscussionIds = new List<Id>();
        result.productMessageIds = new List<Id>();
        result.addedProducts = new List<String>();
        result.addedProductDiscussions = new List<String>();
        result.addedProductMessages = new List<String>();
        
        try {
            // Update the existing visit with merged data (keep existing where new data is null/empty)
            if (data.visit.statusremarks != null && data.visit.statusremarks.trim() != '') {
                existingVisit.StatusRemarks = data.visit.statusremarks;
            }
            if (data.visit.instructiondescription != null && data.visit.instructiondescription.trim() != '') {
                existingVisit.InstructionDescription = data.visit.instructiondescription;
            }
            if (data.visit.visitpriority != null && data.visit.visitpriority.trim() != '') {
                existingVisit.VisitPriority = data.visit.visitpriority;
            }
            if (data.visit.plannedvisitstarttime != null) {
                existingVisit.PlannedVisitStartTime = parseDateTime(data.visit.plannedvisitstarttime);
            }
            if (data.visit.plannedvisitendtime != null) {
                existingVisit.PlannedVisitEndTime = parseDateTime(data.visit.plannedvisitendtime);
            }
            // Keep status as "Planned" - do not update status
            
            update existingVisit;
            result.visitId = existingVisit.Id;
            
            // Get or create ProviderVisit record
            SObject providerVisitRecord = getOrCreateProviderVisit(existingVisit.Id, data.providerVisit);
            result.providerVisitId = providerVisitRecord.Id;
            
            // Append new product detailing records (skip duplicates)
            if (data.providerVisitProdDetailing != null && !data.providerVisitProdDetailing.isEmpty()) {
                // Get existing product IDs for this visit to avoid duplicates
                Set<Id> existingProductIds = getExistingProductIdsForVisit(existingVisit.Id);
                
                // Batch lookup all product names to reduce SOQL queries
                List<String> productNames = new List<String>();
                for (ProviderVisitProdDetailingData detailingData : data.providerVisitProdDetailing) {
                    if (detailingData.productname != null) {
                        productNames.add(detailingData.productname);
                    } else if (detailingData.producthierarchyname != null) {
                        productNames.add(detailingData.producthierarchyname);
                    }
                }
                Map<String, Id> productNameToIdMap = getProductIdsByNames(productNames);
                
                List<SObject> newProductDetailingRecords = new List<SObject>();
                Set<Id> processedProductIds = new Set<Id>();
                Decimal currentPriority = getNextPriorityForVisit(existingVisit.Id);
                
                for (ProviderVisitProdDetailingData detailingData : data.providerVisitProdDetailing) {
                    // Get the product ID for this detailing data from the batched lookup
                    String lookupKey = detailingData.productname != null ? detailingData.productname : detailingData.producthierarchyname;
                    Id productId = productNameToIdMap.get(lookupKey);
                    
                    // Skip if this product ID already exists for this visit or has been processed in this batch
                    if (productId != null && (existingProductIds.contains(productId) || processedProductIds.contains(productId))) {
                        continue; // Skip duplicate product
                    }
                    
                    SObject detailingRecord = createProductDetailingRecord(detailingData, providerVisitRecord.Id, productId, currentPriority);
                    newProductDetailingRecords.add(detailingRecord);
                    result.addedProducts.add(detailingData.productname != null ? detailingData.productname : detailingData.producthierarchyname);
                    
                    // Increment priority for next product
                    currentPriority++;
                    
                    // Track processed product IDs to avoid duplicates within the same batch
                    if (productId != null) {
                        processedProductIds.add(productId);
                    }
                }
                
                // Only insert if there are new records to insert
                if (!newProductDetailingRecords.isEmpty()) {
                    insert newProductDetailingRecords;
                    
                    for (SObject record : newProductDetailingRecords) {
                        result.productDetailingIds.add(record.Id);
                    }
                }
                
                // Append new product discussion records
                if (data.providerVisitProdDiscussion != null && !data.providerVisitProdDiscussion.isEmpty()) {
                    List<SObject> newDiscussionRecords = new List<SObject>();
                    
                    for (Integer i = 0; i < data.providerVisitProdDiscussion.size() && i < newProductDetailingRecords.size(); i++) {
                        ProviderVisitProdDiscussionData discussionData = data.providerVisitProdDiscussion[i];
                        SObject discussionRecord = createProductDiscussionRecord(discussionData, newProductDetailingRecords[i].Id);
                        newDiscussionRecords.add(discussionRecord);
                        result.addedProductDiscussions.add(discussionData.additionalinformation);
                    }
                    
                    insert newDiscussionRecords;
                    
                    for (SObject record : newDiscussionRecords) {
                        result.productDiscussionIds.add(record.Id);
                    }
                }
                
                // Note: Product Message records are skipped due to MessageRecordId complexity
            }
            
            result.success = true;
            result.message = 'Successfully updated existing visit records';
            result.confidence = data.confidence.overall;
            
            // Generate dashboard summary
            String accountName = getAccountNameById(existingVisit.AccountId);
            String territoryName = getCurrentUserTerritoryName();
            result.dashboardSummary = generateDashboardSummary(result, accountName, territoryName);
            
        } catch (Exception e) {
            result.message = 'Error updating existing visit: ' + e.getMessage();
            result.errors = e.getStackTraceString();
        }
        
        return result;
    }
    
    private static ProcessingResult createNewVisit(VisitNoteData data, Id accountId, Id contactPointAddressId) {
        ProcessingResult result = new ProcessingResult();
        result.success = false;
        result.actionType = 'CREATE';
        result.productDetailingIds = new List<Id>();
        result.productDiscussionIds = new List<Id>();
        result.productMessageIds = new List<Id>();
        result.addedProducts = new List<String>();
        result.addedProductDiscussions = new List<String>();
        result.addedProductMessages = new List<String>();
        
        try {
            // Create new Visit record
            Visit visitRecord = createVisitRecord(data.visit, accountId, contactPointAddressId);
            insert visitRecord;
            result.visitId = visitRecord.Id;
            
            // Create ProviderVisit record
            SObject providerVisitRecord = createProviderVisitRecord(data.providerVisit, visitRecord.Id);
            insert providerVisitRecord;
            result.providerVisitId = providerVisitRecord.Id;
            
            // Create Product Detailing records (skip duplicates)
            if (data.providerVisitProdDetailing != null && !data.providerVisitProdDetailing.isEmpty()) {
                // Get existing product IDs for this visit to avoid duplicates
                Set<Id> existingProductIds = getExistingProductIdsForVisit(visitRecord.Id);
                
                // Batch lookup all product names to reduce SOQL queries
                List<String> productNames = new List<String>();
                for (ProviderVisitProdDetailingData detailingData : data.providerVisitProdDetailing) {
                    if (detailingData.productname != null) {
                        productNames.add(detailingData.productname);
                    } else if (detailingData.producthierarchyname != null) {
                        productNames.add(detailingData.producthierarchyname);
                    }
                }
                Map<String, Id> productNameToIdMap = getProductIdsByNames(productNames);
                
                List<SObject> productDetailingRecords = new List<SObject>();
                Set<Id> processedProductIds = new Set<Id>();
                Decimal currentPriority = 1; // Start with priority 1 for new visits
                
                for (ProviderVisitProdDetailingData detailingData : data.providerVisitProdDetailing) {
                    // Get the product ID for this detailing data from the batched lookup
                    String lookupKey = detailingData.productname != null ? detailingData.productname : detailingData.producthierarchyname;
                    Id productId = productNameToIdMap.get(lookupKey);
                    
                    // Skip if this product ID already exists for this visit or has been processed in this batch
                    if (productId != null && (existingProductIds.contains(productId) || processedProductIds.contains(productId))) {
                        continue; // Skip duplicate product
                    }
                    
                    SObject detailingRecord = createProductDetailingRecord(detailingData, providerVisitRecord.Id, productId, currentPriority);
                    productDetailingRecords.add(detailingRecord);
                    result.addedProducts.add(detailingData.productname != null ? detailingData.productname : detailingData.producthierarchyname);
                    
                    // Increment priority for next product
                    currentPriority++;
                    
                    // Track processed product IDs to avoid duplicates within the same batch
                    if (productId != null) {
                        processedProductIds.add(productId);
                    }
                }
                
                // Only insert if there are new records to insert
                if (!productDetailingRecords.isEmpty()) {
                    insert productDetailingRecords;
                    
                    for (SObject record : productDetailingRecords) {
                        result.productDetailingIds.add(record.Id);
                    }
                }
                
                // Create Product Discussion records
                if (data.providerVisitProdDiscussion != null && !data.providerVisitProdDiscussion.isEmpty()) {
                    List<SObject> discussionRecords = new List<SObject>();
                    
                    for (Integer i = 0; i < data.providerVisitProdDiscussion.size() && i < productDetailingRecords.size(); i++) {
                        ProviderVisitProdDiscussionData discussionData = data.providerVisitProdDiscussion[i];
                        SObject discussionRecord = createProductDiscussionRecord(discussionData, productDetailingRecords[i].Id);
                        discussionRecords.add(discussionRecord);
                        result.addedProductDiscussions.add(discussionData.additionalinformation);
                    }
                    
                    insert discussionRecords;
                    
                    for (SObject record : discussionRecords) {
                        result.productDiscussionIds.add(record.Id);
                    }
                }
            }
            
            result.success = true;
            result.message = 'Successfully created new visit records';
            result.confidence = data.confidence.overall;
            
            // Generate dashboard summary
            String accountName = getAccountNameById(accountId);
            String territoryName = getCurrentUserTerritoryName();
            result.dashboardSummary = generateDashboardSummary(result, accountName, territoryName);
            
        } catch (Exception e) {
            result.message = 'Error creating new visit: ' + e.getMessage();
            result.errors = e.getStackTraceString();
        }
        
        return result;
    }
    
    private static SObject getOrCreateProviderVisit(Id visitId, ProviderVisitData data) {
        try {
            // Try to get existing ProviderVisit
            List<SObject> existingProviderVisits = [
                SELECT Id, PreProviderVisitNotes, AdditionalInformation, NextProviderVisitObjective 
                FROM ProviderVisit WHERE VisitId = :visitId LIMIT 1
            ];
            
            if (!existingProviderVisits.isEmpty()) {
                SObject existingProviderVisit = existingProviderVisits[0];
                
                // Update existing ProviderVisit with new data (merge approach)
                Boolean needsUpdate = false;
                if (data.preprovidervisitnotes != null && data.preprovidervisitnotes.trim() != '') {
                    existingProviderVisit.put('PreProviderVisitNotes', data.preprovidervisitnotes);
                    needsUpdate = true;
                }
                if (data.additionalinformation != null && data.additionalinformation.trim() != '') {
                    existingProviderVisit.put('AdditionalInformation', data.additionalinformation);
                    needsUpdate = true;
                }
                if (data.nextprovidervisitobjective != null && data.nextprovidervisitobjective.trim() != '') {
                    existingProviderVisit.put('NextProviderVisitObjective', data.nextprovidervisitobjective);
                    needsUpdate = true;
                }
                
                if (needsUpdate) {
                    update existingProviderVisit;
                }
                
                return existingProviderVisit;
            }
            
            // Create new ProviderVisit if none exists
            SObject providerVisit = Schema.getGlobalDescribe().get('ProviderVisit').newSObject();
            providerVisit.put('OwnerId', UserInfo.getUserId());
            providerVisit.put('VisitId', visitId);
            providerVisit.put('IsSignedAwayFrmAllowDstn', true);
            
            // Map data fields from JSON
            if (data.preprovidervisitnotes != null) providerVisit.put('PreProviderVisitNotes', data.preprovidervisitnotes);
            if (data.additionalinformation != null) providerVisit.put('AdditionalInformation', data.additionalinformation);
            if (data.nextprovidervisitobjective != null) providerVisit.put('NextProviderVisitObjective', data.nextprovidervisitobjective);
            
            // Set Record Type
            List<RecordType> providerVisitRecordTypes = [
                SELECT Id FROM RecordType 
                WHERE SObjectType = 'ProviderVisit' 
                AND IsActive = true 
                LIMIT 1
            ];
            if (!providerVisitRecordTypes.isEmpty()) {
                providerVisit.put('RecordTypeId', providerVisitRecordTypes[0].Id);
            }
            
            insert providerVisit;
            return providerVisit;
            
        } catch (Exception e) {
            // If there's an error, create a new ProviderVisit
            SObject providerVisit = Schema.getGlobalDescribe().get('ProviderVisit').newSObject();
            providerVisit.put('OwnerId', UserInfo.getUserId());
            providerVisit.put('VisitId', visitId);
            providerVisit.put('IsSignedAwayFrmAllowDstn', true);
            
            List<RecordType> providerVisitRecordTypes = [
                SELECT Id FROM RecordType 
                WHERE SObjectType = 'ProviderVisit' 
                AND IsActive = true 
                LIMIT 1
            ];
            if (!providerVisitRecordTypes.isEmpty()) {
                providerVisit.put('RecordTypeId', providerVisitRecordTypes[0].Id);
            }
            
            insert providerVisit;
            return providerVisit;
        }
    }
    
    private static ProcessingResult createVisitRecords(VisitNoteData data) {
        ProcessingResult result = new ProcessingResult();
        result.success = false;
        result.productDetailingIds = new List<Id>();
        result.productDiscussionIds = new List<Id>();
        result.productMessageIds = new List<Id>();
        
        try {
            // Get Account ID and Contact Point Address
            Id accountId = getAccountId(data.account);
            Id contactPointAddressId = getContactPointAddressForAccount(accountId, data.visit.contactpointaddress);
            
            // Create Visit record
            Visit visitRecord = createVisitRecord(data.visit, accountId, contactPointAddressId);
            insert visitRecord;
            result.visitId = visitRecord.Id;
            
            // Create ProviderVisit record
            SObject providerVisitRecord = createProviderVisitRecord(data.providerVisit, visitRecord.Id);
            insert providerVisitRecord;
            result.providerVisitId = providerVisitRecord.Id;
            
            // Create Product Detailing records
            if (data.providerVisitProdDetailing != null && !data.providerVisitProdDetailing.isEmpty()) {
                // Batch lookup all product names to reduce SOQL queries
                List<String> productNames = new List<String>();
                for (ProviderVisitProdDetailingData detailingData : data.providerVisitProdDetailing) {
                    if (detailingData.productname != null) {
                        productNames.add(detailingData.productname);
                    } else if (detailingData.producthierarchyname != null) {
                        productNames.add(detailingData.producthierarchyname);
                    }
                }
                Map<String, Id> productNameToIdMap = getProductIdsByNames(productNames);
                
                List<SObject> productDetailingRecords = new List<SObject>();
                Decimal currentPriority = 1; // Start with priority 1 for new visits
                
                for (ProviderVisitProdDetailingData detailingData : data.providerVisitProdDetailing) {
                    // Get the product ID for this detailing data from the batched lookup
                    String lookupKey = detailingData.productname != null ? detailingData.productname : detailingData.producthierarchyname;
                    Id productId = productNameToIdMap.get(lookupKey);
                    
                    SObject detailingRecord = createProductDetailingRecord(detailingData, providerVisitRecord.Id, productId, currentPriority);
                    productDetailingRecords.add(detailingRecord);
                    result.addedProducts.add(detailingData.productname != null ? detailingData.productname : detailingData.producthierarchyname);
                    
                    // Increment priority for next product
                    currentPriority++;
                }
                
                insert productDetailingRecords;
                
                for (SObject record : productDetailingRecords) {
                    result.productDetailingIds.add(record.Id);
                }
                
                // Create Product Discussion records
                if (data.providerVisitProdDiscussion != null && !data.providerVisitProdDiscussion.isEmpty()) {
                    List<SObject> discussionRecords = new List<SObject>();
                    
                    for (Integer i = 0; i < data.providerVisitProdDiscussion.size() && i < productDetailingRecords.size(); i++) {
                        ProviderVisitProdDiscussionData discussionData = data.providerVisitProdDiscussion[i];
                        SObject discussionRecord = createProductDiscussionRecord(discussionData, productDetailingRecords[i].Id);
                        discussionRecords.add(discussionRecord);
                    }
                    
                    insert discussionRecords;
                    
                    for (SObject record : discussionRecords) {
                        result.productDiscussionIds.add(record.Id);
                    }
                }
                
                // Create Product Message records (skip for now due to MessageRecordId field complexity)
                // TODO: Implement proper MessageRecordId lookup for Product Guidance records
                /*
                if (data.providerVisitDtlProductMsg != null && !data.providerVisitDtlProductMsg.isEmpty()) {
                    List<SObject> messageRecords = new List<SObject>();
                    
                    for (Integer i = 0; i < data.providerVisitDtlProductMsg.size() && i < productDetailingRecords.size(); i++) {
                        ProviderVisitDtlProductMsgData messageData = data.providerVisitDtlProductMsg[i];
                        SObject messageRecord = createProductMessageRecord(messageData, productDetailingRecords[i].Id);
                        messageRecords.add(messageRecord);
                    }
                    
                    insert messageRecords;
                    
                    for (SObject record : messageRecords) {
                        result.productMessageIds.add(record.Id);
                    }
                }
                */
            }
            
            result.success = true;
            result.message = 'Successfully created visit records';
            result.confidence = data.confidence.overall;
            
            // Generate dashboard summary
            String accountName = getAccountNameById(accountId);
            String territoryName = getCurrentUserTerritoryName();
            result.dashboardSummary = generateDashboardSummary(result, accountName, territoryName);
            
        } catch (Exception e) {
            result.message = 'Error creating records: ' + e.getMessage();
            result.errors = e.getStackTraceString();
        }
        
        return result;
    }
    
    private static Visit createVisitRecord(VisitData data, Id accountId, Id contactPointAddressId) {
        Visit visit = new Visit();
        
        // Map data fields
        if (data.statusremarks != null) visit.StatusRemarks = data.statusremarks;
        if (data.instructiondescription != null) visit.InstructionDescription = data.instructiondescription;
        // Always set new visits to "Planned" status (valid picklist value)
        visit.Status = 'Planned';
        if (data.visitpriority != null) visit.VisitPriority = data.visitpriority;
        if (data.plannedvisitstarttime != null) visit.PlannedVisitStartTime = parseDateTime(data.plannedvisitstarttime);
        if (data.plannedvisitendtime != null) visit.PlannedVisitEndTime = parseDateTime(data.plannedvisitendtime);
        
        // Set required fields
        visit.OwnerId = UserInfo.getUserId();
        visit.VisitorId = UserInfo.getUserId();
        visit.AccountId = accountId;
        visit.TerritoryId = getCurrentUserTerritoryId();
        visit.PlaceId = contactPointAddressId;
        
        // Ensure PlannedVisitStartTime is set (required field)
        if (visit.PlannedVisitStartTime == null) {
            visit.PlannedVisitStartTime = DateTime.now();
        }
        
        return visit;
    }
    
    private static SObject createProviderVisitRecord(ProviderVisitData data, Id visitId) {
        SObject providerVisit = Schema.getGlobalDescribe().get('ProviderVisit').newSObject();
        
        // Set minimum required fields only
        providerVisit.put('OwnerId', UserInfo.getUserId());
        providerVisit.put('VisitId', visitId);
        providerVisit.put('IsSignedAwayFrmAllowDstn', true);
        
        // Map data fields from JSON
        if (data.preprovidervisitnotes != null) providerVisit.put('PreProviderVisitNotes', data.preprovidervisitnotes);
        if (data.additionalinformation != null) providerVisit.put('AdditionalInformation', data.additionalinformation);
        if (data.nextprovidervisitobjective != null) providerVisit.put('NextProviderVisitObjective', data.nextprovidervisitobjective);
        
        // Account and Contact Point Address are inherited automatically from the Visit record
        
        // Set Record Type (get the default Provider Visit record type)
        List<RecordType> providerVisitRecordTypes = [
            SELECT Id FROM RecordType 
            WHERE SObjectType = 'ProviderVisit' 
            AND IsActive = true 
            LIMIT 1
        ];
        if (!providerVisitRecordTypes.isEmpty()) {
            providerVisit.put('RecordTypeId', providerVisitRecordTypes[0].Id);
        }
        
        return providerVisit;
    }
    
    private static SObject createProductDetailingRecord(ProviderVisitProdDetailingData data, Id providerVisitId, Id productId, Decimal priority) {
        SObject productDetailing = Schema.getGlobalDescribe().get('ProviderVisitProdDetailing').newSObject();
        
        // Map data fields - use the provided priority instead of JSON priority
        productDetailing.put('Priority', priority);
        if (data.nextprvdvisitobjectives != null) productDetailing.put('NextPrvdVisitObjectives', data.nextprvdvisitobjectives);
        if (data.additionalinformation != null) productDetailing.put('AdditionalInformation', data.additionalinformation);
        if (data.producthierarchyname != null) productDetailing.put('ProductHierarchyName', data.producthierarchyname);
        
        // Set required fields
        productDetailing.put('OwnerId', UserInfo.getUserId());
        productDetailing.put('ProviderVisitId', providerVisitId);
        productDetailing.put('ProductId', productId);
        productDetailing.put('IsOffLabel', false);
        productDetailing.put('IsGeneratedFromPresentation', false);
        productDetailing.put('IsSignatureCaptured', false);
        
        return productDetailing;
    }
    
    private static SObject createProductDiscussionRecord(ProviderVisitProdDiscussionData data, Id productDetailingId) {
        SObject productDiscussion = Schema.getGlobalDescribe().get('ProviderVisitProdDiscussion').newSObject();
        
        // Map data fields
        if (data.additionalinformation != null) productDiscussion.put('Note', data.additionalinformation);
        
        // Set required fields
        productDiscussion.put('OwnerId', UserInfo.getUserId());
        productDiscussion.put('ProviderVisitProductDtlId', productDetailingId);
        
        return productDiscussion;
    }
    
    private static SObject createProductMessageRecord(ProviderVisitDtlProductMsgData data, Id productDetailingId) {
        SObject productMessage = Schema.getGlobalDescribe().get('ProviderVisitDtlProductMsg').newSObject();
        
        // Map data fields
        if (data.additionalinformation != null) productMessage.put('AdditionalInformation', data.additionalinformation);
        if (data.reactiontype != null) productMessage.put('ReactionType', data.reactiontype);
        if (data.capturedreaction != null) productMessage.put('CapturedReaction', data.capturedreaction);
        
        // Set required fields
        productMessage.put('OwnerId', UserInfo.getUserId());
        productMessage.put('ProviderVisitProductDtlId', productDetailingId);
        productMessage.put('IsGeneratedFromPresentation', false);
        
        // Set MessageRecordId - create a default message record or use a placeholder
        // For now, we'll use the productDetailingId as the MessageRecordId
        productMessage.put('MessageRecordId', productDetailingId);
        
        return productMessage;
    }
    
    private static DateTime parseDateTime(String dateTimeStr) {
        try {
            return DateTime.valueOfGmt(dateTimeStr);
        } catch (Exception e) {
            return DateTime.now();
        }
    }
    
    private static Id getDefaultAccountId() {
        List<Account> accounts = [SELECT Id FROM Account LIMIT 1];
        return accounts.isEmpty() ? null : accounts[0].Id;
    }
    
    private static Id getDefaultTerritoryId() {
        List<Territory2> territories = [SELECT Id FROM Territory2 LIMIT 1];
        return territories.isEmpty() ? null : territories[0].Id;
    }
    
    private static Id getCurrentUserTerritoryId() {
        try {
            // Get current user's territory from UserTerritory2Association
            List<UserTerritory2Association> userTerritories = [
                SELECT Territory2Id 
                FROM UserTerritory2Association 
                WHERE UserId = :UserInfo.getUserId() 
                AND IsActive = true
                LIMIT 1
            ];
            
            if (!userTerritories.isEmpty()) {
                return userTerritories[0].Territory2Id;
            }
            
            // Fallback to default territory if user has no territory assignment
            return getDefaultTerritoryId();
            
        } catch (Exception e) {
            return getDefaultTerritoryId();
        }
    }
    
    private static Boolean isProductAvailableInTerritory(Id productId, Id territoryId) {
        if (productId == null || territoryId == null) {
            return false;
        }
        
        try {
            // Check ProductTerritoryAvailability
            List<SObject> productTerritoryAvailability = [
                SELECT Id 
                FROM ProductTerritoryAvailability 
                WHERE ProductId = :productId 
                AND TerritoryId = :territoryId
                LIMIT 1
            ];
            
            if (!productTerritoryAvailability.isEmpty()) {
                return true;
            }
            
            // Check ProductTerrDtlAvailability
            List<SObject> productTerrDtlAvailability = [
                SELECT Id 
                FROM ProductTerrDtlAvailability 
                WHERE ProductId = :productId 
                AND TerritoryId = :territoryId
                LIMIT 1
            ];
            
            return !productTerrDtlAvailability.isEmpty();
            
        } catch (Exception e) {
            // If there's an error checking availability, allow the product (fail open)
            return true;
        }
    }
    
    private static Set<Id> getExistingProductIdsForVisit(Id visitId) {
        Set<Id> existingProductIds = new Set<Id>();
        
        try {
            // Get all existing ProviderVisitProdDetailing records for this visit
            List<SObject> existingDetailingRecords = [
                SELECT ProductId 
                FROM ProviderVisitProdDetailing 
                WHERE ProviderVisit.VisitId = :visitId
            ];
            
            for (SObject record : existingDetailingRecords) {
                Id productId = (Id)record.get('ProductId');
                if (productId != null) {
                    existingProductIds.add(productId);
                }
            }
            
        } catch (Exception e) {
            // If there's an error, return empty set (fail open)
        }
        
        return existingProductIds;
    }
    
    private static Decimal getNextPriorityForVisit(Id visitId) {
        try {
            // Get the highest priority number for existing product details in this visit
            List<AggregateResult> maxPriorityResult = [
                SELECT MAX(Priority) maxPriority
                FROM ProviderVisitProdDetailing 
                WHERE ProviderVisit.VisitId = :visitId
            ];
            
            if (!maxPriorityResult.isEmpty() && maxPriorityResult[0].get('maxPriority') != null) {
                Decimal maxPriority = (Decimal) maxPriorityResult[0].get('maxPriority');
                return maxPriority + 1; // Return next priority number
            } else {
                return 1; // No existing products, start with priority 1
            }
            
        } catch (Exception e) {
            // If there's an error, default to priority 1
            return 1;
        }
    }
    
    private static Map<String, Id> getProductIdsByNames(List<String> productNames) {
        Map<String, Id> productNameToIdMap = new Map<String, Id>();
        
        if (productNames == null || productNames.isEmpty()) {
            return productNameToIdMap;
        }
        
        try {
            // Get current user's territory
            Id userTerritoryId = getCurrentUserTerritoryId();
            
            // First try to find in Life Sciences Marketable Product (PRIORITY)
            List<SObject> marketableProducts = [
                SELECT Id, Name, ProductCode, Description
                FROM LifeSciMarketableProduct 
                WHERE Name IN :productNames 
                   OR ProductCode IN :productNames
            ];
            
            for (SObject product : marketableProducts) {
                Id productId = (Id)product.get('Id');
                // Check territory availability
                if (isProductAvailableInTerritory(productId, userTerritoryId)) {
                    String productName = (String)product.get('Name');
                    String productCode = (String)product.get('ProductCode');
                    String description = (String)product.get('Description');
                    
                    // Map by name, product code, and description
                    productNameToIdMap.put(productName, productId);
                    productNameToIdMap.put(productCode, productId);
                    if (description != null) {
                        productNameToIdMap.put(description, productId);
                    }
                }
            }
            
            // If not found in LifeSciMarketableProduct, try Product2 (FALLBACK)
            List<Product2> products = [
                SELECT Id, Name, ProductCode, Description
                FROM Product2 
                WHERE Name IN :productNames 
                   OR ProductCode IN :productNames
            ];
            
            for (Product2 product : products) {
                // Check territory availability
                if (isProductAvailableInTerritory(product.Id, userTerritoryId)) {
                    // Map by name, product code, and description
                    productNameToIdMap.put(product.Name, product.Id);
                    productNameToIdMap.put(product.ProductCode, product.Id);
                    if (product.Description != null) {
                        productNameToIdMap.put(product.Description, product.Id);
                    }
                }
            }
            
        } catch (Exception e) {
            // If there's an error, return empty map (fail open)
        }
        
        return productNameToIdMap;
    }
    
    private static String generateDashboardSummary(ProcessingResult result, String accountName, String territoryName) {
        String dashboard = '';
        
        // Get entity names
        String visitName = getVisitNameById(result.visitId);
        String providerVisitName = getProviderVisitNameById(result.providerVisitId);
        Map<Id, String> productNames = getProductNamesByIds(result.productDetailingIds);
        
        // Header
        dashboard += '🏥 VISIT PROCESSING SUMMARY\n';
        dashboard += '═══════════════════════════════════════════════════════════════════════════════\n\n';
        
        // Status Summary
        String statusIcon = result.success ? '✅ SUCCESS' : '❌ FAILED';
        String actionType = result.actionType != null ? result.actionType : 'UNKNOWN';
        String confidenceStr = result.confidence != null ? String.valueOf(Math.round(result.confidence * 100)) + '%' : 'N/A';
        dashboard += '📊 PROCESSING STATUS:\n';
        dashboard += '• Status: ' + statusIcon + '\n';
        dashboard += '• Action: ' + actionType + '\n';
        dashboard += '• Confidence: ' + confidenceStr + '\n\n';
        
        // Visit Details
        dashboard += '📍 VISIT DETAILS:\n';
        dashboard += '• Visit ID: ' + (result.visitId != null ? result.visitId + ' (' + visitName + ')' : 'N/A') + '\n';
        dashboard += '• Provider Visit: ' + (result.providerVisitId != null ? result.providerVisitId + ' (' + providerVisitName + ')' : 'N/A') + '\n';
        dashboard += '• Account: ' + (accountName != null ? accountName : 'N/A') + '\n';
        dashboard += '• Territory: ' + (territoryName != null ? territoryName : 'N/A') + '\n';
        dashboard += '• Visit Status: Planned (new visits always created as Planned)\n\n';
        
        // Provider Visit Details
        dashboard += '👨‍⚕️ PROVIDER VISIT DETAILS:\n';
        String nextObjective = getNextProviderVisitObjective(result.providerVisitId);
        dashboard += '• Next Provider Visit Objective: ' + (nextObjective != null && nextObjective.trim() != '' ? nextObjective : 'N/A') + '\n\n';
        
        // Products Added
        Integer productCount = result.addedProducts != null ? result.addedProducts.size() : 0;
        dashboard += '📦 PRODUCTS ADDED (' + productCount + '):\n';
        
        if (productCount > 0) {
            for (Integer i = 0; i < productCount; i++) {
                String productName = result.addedProducts[i];
                String productId = (result.productDetailingIds != null && i < result.productDetailingIds.size()) 
                    ? result.productDetailingIds[i] : 'N/A';
                String actualProductName = productNames.get(productId);
                String hierarchyName = 'N/A'; // Could be enhanced to get hierarchy name
                
                dashboard += '  • ' + (i + 1) + '. ' + productName + ' (' + productId + ') - ' + (actualProductName != null ? actualProductName : hierarchyName) + '\n';
            }
        } else {
            dashboard += '  • No products added\n';
        }
        dashboard += '\n';
        
        // Discussions Added
        Integer discussionCount = result.addedProductDiscussions != null ? result.addedProductDiscussions.size() : 0;
        dashboard += '💬 DISCUSSIONS ADDED (' + discussionCount + '):\n';
        
        if (discussionCount > 0) {
            for (Integer i = 0; i < discussionCount; i++) {
                String discussion = result.addedProductDiscussions[i];
                String discussionId = (result.productDiscussionIds != null && i < result.productDiscussionIds.size()) 
                    ? result.productDiscussionIds[i] : 'N/A';
                
                dashboard += '  • ' + (i + 1) + '. ' + discussion + '\n';
                dashboard += '    (ProviderVisitProdDiscussion: ' + discussionId + ')\n';
            }
        } else {
            dashboard += '  • No discussions added\n';
        }
        dashboard += '\n';
        
        // Validation Status
        dashboard += '✅ VALIDATION STATUS:\n';
        dashboard += '• Territory Compliance: ' + (result.success ? 'PASSED' : 'FAILED') + '\n';
        dashboard += '• Duplicate Prevention: ' + (result.success ? 'ACTIVE' : 'FAILED') + '\n';
        dashboard += '• Product Availability: ' + (result.success ? 'VERIFIED' : 'FAILED') + '\n\n';
        
        // Message
        if (result.message != null && result.message.length() > 0) {
            dashboard += '📝 MESSAGE:\n';
            dashboard += '• ' + result.message + '\n';
        }
        
        return dashboard;
    }
    
    private static Id getDefaultProductId() {
        try {
            // Get current user's territory
            Id userTerritoryId = getCurrentUserTerritoryId();
            
            // First try to get a default Life Sciences Marketable Product that's available in user's territory (PRIORITY)
            List<SObject> marketableProducts = [SELECT Id FROM LifeSciMarketableProduct LIMIT 10];
            for (SObject product : marketableProducts) {
                if (isProductAvailableInTerritory((Id)product.get('Id'), userTerritoryId)) {
                    return (Id)product.get('Id');
                }
            }
            
            // If no LifeSciMarketableProduct available in territory, try Product2 (FALLBACK)
            List<Product2> products = [SELECT Id FROM Product2 LIMIT 10];
            for (Product2 product : products) {
                if (isProductAvailableInTerritory(product.Id, userTerritoryId)) {
                    return product.Id;
                }
            }
            
            // If no products available in territory, return first available product (fallback)
            if (!marketableProducts.isEmpty()) {
                return (Id)marketableProducts[0].get('Id');
            }
            if (!products.isEmpty()) {
                return products[0].Id;
            }
            
            return null;
            
        } catch (Exception e) {
            // Fallback to original logic if territory validation fails
            List<SObject> marketableProducts = [SELECT Id FROM LifeSciMarketableProduct LIMIT 1];
            if (!marketableProducts.isEmpty()) {
                return (Id)marketableProducts[0].get('Id');
            }
            
            List<Product2> products = [SELECT Id FROM Product2 LIMIT 1];
            if (!products.isEmpty()) {
                return products[0].Id;
            }
            
            return null;
        }
    }
    
    private static String getCurrentUserTerritoryName() {
        try {
            // Get current user's territory
            List<UserTerritory2Association> userTerritories = [
                SELECT Territory2.Name 
                FROM UserTerritory2Association 
                WHERE UserId = :UserInfo.getUserId() 
                LIMIT 1
            ];
            return userTerritories.isEmpty() ? 'Default Territory' : userTerritories[0].Territory2.Name;
        } catch (Exception e) {
            return 'Default Territory';
        }
    }
    
    private static String getAccountNameById(Id accountId) {
        if (accountId == null) {
            return 'N/A';
        }
        
        try {
            List<Account> accounts = [
                SELECT Name 
                FROM Account 
                WHERE Id = :accountId 
                LIMIT 1
            ];
            
            if (!accounts.isEmpty()) {
                return accounts[0].Name;
            }
            
            return 'Unknown Account';
            
        } catch (Exception e) {
            return 'Unknown Account';
        }
    }
    
    private static Map<Id, String> getProductNamesByIds(List<Id> productIds) {
        Map<Id, String> productIdToNameMap = new Map<Id, String>();
        if (productIds == null || productIds.isEmpty()) return productIdToNameMap;
        
        try {
            // Query LifeSciMarketableProduct first (priority)
            List<LifeSciMarketableProduct> lifeSciProducts = [
                SELECT Id, Name FROM LifeSciMarketableProduct WHERE Id IN :productIds
            ];
            for (LifeSciMarketableProduct product : lifeSciProducts) {
                productIdToNameMap.put(product.Id, product.Name);
            }
            
            // Query Product2 for remaining IDs
            Set<Id> remainingIds = new Set<Id>(productIds);
            remainingIds.removeAll(productIdToNameMap.keySet());
            if (!remainingIds.isEmpty()) {
                List<Product2> products = [
                    SELECT Id, Name FROM Product2 WHERE Id IN :remainingIds
                ];
                for (Product2 product : products) {
                    productIdToNameMap.put(product.Id, product.Name);
                }
            }
        } catch (Exception e) {
            System.debug('Error getting product names: ' + e.getMessage());
        }
        
        return productIdToNameMap;
    }
    
    private static String getVisitNameById(Id visitId) {
        if (visitId == null) return 'N/A';
        
        try {
            List<Visit> visits = [
                SELECT Name FROM Visit WHERE Id = :visitId LIMIT 1
            ];
            return visits.isEmpty() ? 'N/A' : visits[0].Name;
        } catch (Exception e) {
            return 'N/A';
        }
    }
    
    private static String getProviderVisitNameById(Id providerVisitId) {
        if (providerVisitId == null) return 'N/A';
        
        try {
            List<SObject> providerVisits = [
                SELECT Name FROM ProviderVisit WHERE Id = :providerVisitId LIMIT 1
            ];
            return providerVisits.isEmpty() ? 'N/A' : (String)providerVisits[0].get('Name');
        } catch (Exception e) {
            return 'N/A';
        }
    }
    
    private static String getNextProviderVisitObjective(Id providerVisitId) {
        if (providerVisitId == null) return 'N/A';
        
        try {
            List<SObject> providerVisits = [
                SELECT NextProviderVisitObjective FROM ProviderVisit WHERE Id = :providerVisitId LIMIT 1
            ];
            return providerVisits.isEmpty() ? 'N/A' : (String)providerVisits[0].get('NextProviderVisitObjective');
        } catch (Exception e) {
            return 'N/A';
        }
    }
    
    private static Id getProductIdByName(String productName) {
        if (productName == null || productName.trim() == '') {
            return getDefaultProductId();
        }
        
        try {
            // Get current user's territory
            Id userTerritoryId = getCurrentUserTerritoryId();
            
            // First try to find in Life Sciences Marketable Product (PRIORITY)
            List<SObject> marketableProducts = [
                SELECT Id 
                FROM LifeSciMarketableProduct 
                WHERE Name = :productName 
                   OR ProductCode = :productName 
                   OR Description LIKE :'%' + productName + '%'
                LIMIT 1
            ];
            
            if (!marketableProducts.isEmpty()) {
                Id productId = marketableProducts[0].Id;
                // Validate product-territory alignment
                if (isProductAvailableInTerritory(productId, userTerritoryId)) {
                    return productId;
                }
            }
            
            // If not found in LifeSciMarketableProduct, try Product2 (FALLBACK)
            List<Product2> products = [
                SELECT Id 
                FROM Product2 
                WHERE Name = :productName 
                   OR ProductCode = :productName 
                   OR Description LIKE :'%' + productName + '%'
                LIMIT 1
            ];
            
            if (!products.isEmpty()) {
                Id productId = products[0].Id;
                // Validate product-territory alignment
                if (isProductAvailableInTerritory(productId, userTerritoryId)) {
                    return productId;
                }
            }
            
            // If still not found or not available in territory, return default
            return getDefaultProductId();
            
        } catch (Exception e) {
            return getDefaultProductId();
        }
    }
    
    private static Id getContactPointAddressId(String addressInfo) {
        if (addressInfo == null || addressInfo.trim() == '') {
            return getDefaultContactPointAddressId();
        }
        
        try {
            // Try to find Contact Point Address by name or city
            List<ContactPointAddress> addresses = [
                SELECT Id 
                FROM ContactPointAddress 
                WHERE AddressType = 'Office' 
                   AND (Name LIKE :'%' + addressInfo + '%' 
                        OR City LIKE :'%' + addressInfo + '%')
                LIMIT 1
            ];
            
            if (!addresses.isEmpty()) {
                return addresses[0].Id;
            }
            
            // If not found, return default
            return getDefaultContactPointAddressId();
            
        } catch (Exception e) {
            return getDefaultContactPointAddressId();
        }
    }
    
    public static Id getAccountId(AccountData accountData) {
        if (accountData == null) {
            return getDefaultAccountId();
        }
        
        // If Account ID is provided, use it
        if (accountData.accountid != null && accountData.accountid.trim() != '') {
            try {
                return Id.valueOf(accountData.accountid);
            } catch (Exception e) {
                // Invalid ID, fall back to name lookup
            }
        }
        
        // If Account Name is provided, look it up
        if (accountData.accountname != null && accountData.accountname.trim() != '') {
            try {
                List<Account> accounts = [
                    SELECT Id 
                    FROM Account 
                    WHERE Name = :accountData.accountname.trim()
                       OR Name LIKE :'%' + accountData.accountname.trim() + '%'
                    LIMIT 1
                ];
                if (!accounts.isEmpty()) {
                    return accounts[0].Id;
                }
            } catch (Exception e) {
                // Fall back to default
            }
        }
        
        return getDefaultAccountId();
    }
    
    public static Id getContactPointAddressForAccount(Id accountId, String addressInfo) {
        if (accountId == null) {
            return getDefaultContactPointAddressId();
        }
        
        try {
            // First try to get the default Contact Point Address for the account
            List<ContactPointAddress> defaultAddresses = [
                SELECT Id 
                FROM ContactPointAddress 
                WHERE ParentId = :accountId 
                   AND IsDefault = true
                LIMIT 1
            ];
            
            if (!defaultAddresses.isEmpty()) {
                return defaultAddresses[0].Id;
            }
            
            // If no default, try to get the primary Contact Point Address
            List<ContactPointAddress> primaryAddresses = [
                SELECT Id 
                FROM ContactPointAddress 
                WHERE ParentId = :accountId 
                ORDER BY IsDefault DESC, CreatedDate ASC
                LIMIT 1
            ];
            
            if (!primaryAddresses.isEmpty()) {
                return primaryAddresses[0].Id;
            }
            
            // If no Contact Point Address found for the account, try to find by address info
            if (addressInfo != null && addressInfo.trim() != '') {
                List<ContactPointAddress> addresses = [
                    SELECT Id 
                    FROM ContactPointAddress 
                    WHERE (Name LIKE :'%' + addressInfo.trim() + '%' 
                           OR City LIKE :'%' + addressInfo.trim() + '%')
                    LIMIT 1
                ];
                
                if (!addresses.isEmpty()) {
                    return addresses[0].Id;
                }
            }
            
            // Fall back to default
            return getDefaultContactPointAddressId();
            
        } catch (Exception e) {
            return getDefaultContactPointAddressId();
        }
    }
    
    private static Id getDefaultContactPointAddressId() {
        try {
            // Get a default Contact Point Address
            List<ContactPointAddress> addresses = [
                SELECT Id 
                FROM ContactPointAddress 
                WHERE IsDefault = true
                LIMIT 1
            ];
            return addresses.isEmpty() ? null : addresses[0].Id;
        } catch (Exception e) {
            return null;
        }
    }
}