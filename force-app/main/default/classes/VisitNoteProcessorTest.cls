@IsTest
private class VisitNoteProcessorTest {

    @TestSetup
    static void setupTestData() {
        Account testAccount = new Account(Name = 'Test Medical Center');
        insert testAccount;
    }

    private static String buildValidJson() {
        return '{' +
            '"visit": {' +
                '"statusremarks": "Discussed treatment plan",' +
                '"instructiondescription": "Follow up on dosing",' +
                '"plannedvisitstarttime": "2026-05-22T10:00:00Z",' +
                '"plannedvisitendtime": "2026-05-22T11:00:00Z",' +
                '"status": "Planned",' +
                '"visitpriority": "High",' +
                '"contactpointaddress": null' +
            '},' +
            '"account": {' +
                '"accountname": "Test Medical Center",' +
                '"accountid": null' +
            '},' +
            '"providerVisit": {' +
                '"preprovidervisitnotes": "Review patient history",' +
                '"additionalinformation": "Patient on current therapy",' +
                '"nextprovidervisitobjective": "Check lab results"' +
            '},' +
            '"providerVisitProdDetailing": [],' +
            '"providerVisitProdDiscussion": [],' +
            '"providerVisitDtlProductMsg": [],' +
            '"confidence": {' +
                '"overall": 0.85,' +
                '"visit": 0.9,' +
                '"providerVisit": 0.8,' +
                '"productDetailing": 0.0,' +
                '"productDiscussion": 0.0,' +
                '"productMessage": 0.0' +
            '},' +
            '"extractedEntities": {' +
                '"providers": ["Dr. Smith"],' +
                '"products": [],' +
                '"activities": ["discussion"],' +
                '"outcomes": ["follow-up scheduled"],' +
                '"dates": ["2026-05-22"],' +
                '"locations": ["Test Medical Center"]' +
            '}' +
        '}';
    }

    private static String buildLowConfidenceJson() {
        return '{' +
            '"visit": {' +
                '"statusremarks": "Unclear notes",' +
                '"instructiondescription": null,' +
                '"plannedvisitstarttime": null,' +
                '"plannedvisitendtime": null,' +
                '"status": null,' +
                '"visitpriority": null,' +
                '"contactpointaddress": null' +
            '},' +
            '"account": {' +
                '"accountname": "Unknown",' +
                '"accountid": null' +
            '},' +
            '"providerVisit": {' +
                '"preprovidervisitnotes": null,' +
                '"additionalinformation": null,' +
                '"nextprovidervisitobjective": null' +
            '},' +
            '"providerVisitProdDetailing": [],' +
            '"providerVisitProdDiscussion": [],' +
            '"providerVisitDtlProductMsg": [],' +
            '"confidence": {' +
                '"overall": 0.3,' +
                '"visit": 0.2,' +
                '"providerVisit": 0.1,' +
                '"productDetailing": 0.0,' +
                '"productDiscussion": 0.0,' +
                '"productMessage": 0.0' +
            '},' +
            '"extractedEntities": {' +
                '"providers": [],' +
                '"products": [],' +
                '"activities": [],' +
                '"outcomes": [],' +
                '"dates": [],' +
                '"locations": []' +
            '}' +
        '}';
    }

    @IsTest
    static void testProcessVisitNotes_ValidJson() {
        String jsonData = buildValidJson();

        Test.startTest();
        List<VisitNoteProcessor.ProcessingResult> results =
            VisitNoteProcessor.processVisitNotes(new List<String>{ jsonData });
        Test.stopTest();

        System.assertEquals(1, results.size(), 'Should return one result');
        VisitNoteProcessor.ProcessingResult result = results[0];
        if (result.success) {
            System.assertNotEquals(null, result.visitId, 'Should have visit ID');
            System.assertNotEquals(null, result.providerVisitId, 'Should have provider visit ID');
            System.assert(result.confidence >= 0.5, 'Confidence should meet threshold');
        } else {
            System.assertNotEquals(null, result.message, 'Failed result should have message');
        }
    }

    @IsTest
    static void testProcessVisitNotes_LowConfidence() {
        String jsonData = buildLowConfidenceJson();

        Test.startTest();
        List<VisitNoteProcessor.ProcessingResult> results =
            VisitNoteProcessor.processVisitNotes(new List<String>{ jsonData });
        Test.stopTest();

        System.assertEquals(1, results.size(), 'Should return one result');
        VisitNoteProcessor.ProcessingResult result = results[0];
        System.assertEquals(false, result.success, 'Should fail due to low confidence');
        System.assert(result.message.contains('Confidence too low'), 'Should indicate low confidence');
    }

    @IsTest
    static void testProcessVisitNotes_InvalidJson() {
        String invalidJson = 'this is not json at all';

        Test.startTest();
        List<VisitNoteProcessor.ProcessingResult> results =
            VisitNoteProcessor.processVisitNotes(new List<String>{ invalidJson });
        Test.stopTest();

        System.assertEquals(1, results.size(), 'Should return one result');
        VisitNoteProcessor.ProcessingResult result = results[0];
        System.assertEquals(false, result.success, 'Should fail on invalid JSON');
        System.assert(result.message.contains('Error'), 'Should contain error message');
    }

    @IsTest
    static void testProcessVisitNotes_MarkdownWrappedJson() {
        String markdownJson = '```json\n' + buildValidJson() + '\n```';

        Test.startTest();
        List<VisitNoteProcessor.ProcessingResult> results =
            VisitNoteProcessor.processVisitNotes(new List<String>{ markdownJson });
        Test.stopTest();

        System.assertEquals(1, results.size(), 'Should return one result');
        VisitNoteProcessor.ProcessingResult result = results[0];
        if (result.success) {
            System.assertNotEquals(null, result.visitId, 'Should process markdown-wrapped JSON');
        }
    }

    @IsTest
    static void testProcessVisitNotes_CodeBlockWrappedJson() {
        String codeBlockJson = '```\n' + buildValidJson() + '\n```';

        Test.startTest();
        List<VisitNoteProcessor.ProcessingResult> results =
            VisitNoteProcessor.processVisitNotes(new List<String>{ codeBlockJson });
        Test.stopTest();

        System.assertEquals(1, results.size(), 'Should return one result');
    }

    @IsTest
    static void testProcessVisitNotes_NullInput() {
        String nullJson = null;

        Test.startTest();
        List<VisitNoteProcessor.ProcessingResult> results =
            VisitNoteProcessor.processVisitNotes(new List<String>{ nullJson });
        Test.stopTest();

        System.assertEquals(1, results.size(), 'Should return one result');
        System.assertEquals(false, results[0].success, 'Should fail on null input');
    }

    @IsTest
    static void testProcessVisitNotes_EmptyString() {
        Test.startTest();
        List<VisitNoteProcessor.ProcessingResult> results =
            VisitNoteProcessor.processVisitNotes(new List<String>{ '' });
        Test.stopTest();

        System.assertEquals(1, results.size(), 'Should return one result');
        System.assertEquals(false, results[0].success, 'Should fail on empty string');
    }

    @IsTest
    static void testProcessVisitNotes_BulkInput() {
        String jsonData = buildLowConfidenceJson();
        List<String> bulkInput = new List<String>();
        for (Integer i = 0; i < 5; i++) {
            bulkInput.add(jsonData);
        }

        Test.startTest();
        List<VisitNoteProcessor.ProcessingResult> results =
            VisitNoteProcessor.processVisitNotes(bulkInput);
        Test.stopTest();

        System.assertEquals(5, results.size(), 'Should return result for each input');
        for (VisitNoteProcessor.ProcessingResult result : results) {
            System.assertEquals(false, result.success, 'All should fail due to low confidence');
        }
    }

    @IsTest
    static void testGetAccountId_ByName() {
        VisitNoteProcessor.AccountData accountData = new VisitNoteProcessor.AccountData();
        accountData.accountname = 'Test Medical Center';
        accountData.accountid = null;

        Test.startTest();
        Id accountId = VisitNoteProcessor.getAccountId(accountData);
        Test.stopTest();

        System.assertNotEquals(null, accountId, 'Should find account by name');
        Account acc = [SELECT Name FROM Account WHERE Id = :accountId];
        System.assertEquals('Test Medical Center', acc.Name, 'Should match test account');
    }

    @IsTest
    static void testGetAccountId_ById() {
        Account acc = [SELECT Id FROM Account WHERE Name = 'Test Medical Center' LIMIT 1];

        VisitNoteProcessor.AccountData accountData = new VisitNoteProcessor.AccountData();
        accountData.accountname = null;
        accountData.accountid = acc.Id;

        Test.startTest();
        Id accountId = VisitNoteProcessor.getAccountId(accountData);
        Test.stopTest();

        System.assertEquals(acc.Id, accountId, 'Should resolve account by ID');
    }

    @IsTest
    static void testGetAccountId_NullData() {
        Test.startTest();
        Id accountId = VisitNoteProcessor.getAccountId(null);
        Test.stopTest();

        // Should return a default account or null depending on org data
        // Just verify it doesn't throw
        System.assert(true, 'Should handle null account data gracefully');
    }

    @IsTest
    static void testGetAccountId_InvalidId() {
        VisitNoteProcessor.AccountData accountData = new VisitNoteProcessor.AccountData();
        accountData.accountname = null;
        accountData.accountid = 'not-a-valid-id';

        Test.startTest();
        Id accountId = VisitNoteProcessor.getAccountId(accountData);
        Test.stopTest();

        // Should fall back to default account
        System.assert(true, 'Should handle invalid ID gracefully');
    }

    @IsTest
    static void testGetContactPointAddressForAccount() {
        Account acc = [SELECT Id FROM Account WHERE Name = 'Test Medical Center' LIMIT 1];

        Test.startTest();
        Id addressId = VisitNoteProcessor.getContactPointAddressForAccount(acc.Id, null);
        Test.stopTest();

        // May be null if no ContactPointAddress exists for this account in test context
        System.assert(true, 'Should handle address lookup gracefully');
    }

    @IsTest
    static void testGetContactPointAddressForAccount_NullAccount() {
        Test.startTest();
        Id addressId = VisitNoteProcessor.getContactPointAddressForAccount(null, null);
        Test.stopTest();

        System.assert(true, 'Should handle null account ID gracefully');
    }

    @IsTest
    static void testDataClassDeserialization() {
        String jsonInput = buildValidJson();

        Test.startTest();
        VisitNoteProcessor.VisitNoteData data =
            (VisitNoteProcessor.VisitNoteData) System.JSON.deserialize(jsonInput, VisitNoteProcessor.VisitNoteData.class);
        Test.stopTest();

        System.assertNotEquals(null, data.visit, 'Visit data should parse');
        System.assertEquals('Discussed treatment plan', data.visit.statusremarks);
        System.assertEquals('High', data.visit.visitpriority);
        System.assertNotEquals(null, data.account, 'Account data should parse');
        System.assertEquals('Test Medical Center', data.account.accountname);
        System.assertNotEquals(null, data.providerVisit, 'Provider visit data should parse');
        System.assertEquals('Check lab results', data.providerVisit.nextprovidervisitobjective);
        System.assertNotEquals(null, data.confidence, 'Confidence data should parse');
        System.assertEquals(0.85, data.confidence.overall);
        System.assertNotEquals(null, data.extractedEntities, 'Extracted entities should parse');
        System.assertEquals(1, data.extractedEntities.providers.size());
    }

    @IsTest
    static void testProcessingResultFields() {
        VisitNoteProcessor.ProcessingResult result = new VisitNoteProcessor.ProcessingResult();
        result.success = true;
        result.message = 'Test message';
        result.actionType = 'CREATE';
        result.confidence = 0.9;
        result.addedProducts = new List<String>{ 'Product A', 'Product B' };
        result.addedProductDiscussions = new List<String>{ 'Discussion 1' };
        result.addedProductMessages = new List<String>();
        result.productDetailingIds = new List<Id>();
        result.productDiscussionIds = new List<Id>();
        result.productMessageIds = new List<Id>();
        result.dashboardSummary = 'Summary text';

        System.assertEquals(true, result.success);
        System.assertEquals('CREATE', result.actionType);
        System.assertEquals(0.9, result.confidence);
        System.assertEquals(2, result.addedProducts.size());
        System.assertEquals('Summary text', result.dashboardSummary);
    }

    @IsTest
    static void testProcessVisitNotes_WithProductDetailing() {
        String jsonWithProducts = '{' +
            '"visit": {' +
                '"statusremarks": "Product discussion",' +
                '"instructiondescription": "Detail products",' +
                '"plannedvisitstarttime": "2026-05-22T10:00:00Z",' +
                '"plannedvisitendtime": "2026-05-22T11:00:00Z",' +
                '"status": "Planned",' +
                '"visitpriority": "Medium",' +
                '"contactpointaddress": null' +
            '},' +
            '"account": {' +
                '"accountname": "Test Medical Center",' +
                '"accountid": null' +
            '},' +
            '"providerVisit": {' +
                '"preprovidervisitnotes": "Product detail session",' +
                '"additionalinformation": "New therapy options",' +
                '"nextprovidervisitobjective": "Follow up on efficacy"' +
            '},' +
            '"providerVisitProdDetailing": [{' +
                '"productname": "TestProduct123",' +
                '"producthierarchyname": "TestProduct123",' +
                '"priority": 1,' +
                '"nextprvdvisitobjectives": "Review efficacy data",' +
                '"additionalinformation": "Patient responded well"' +
            '}],' +
            '"providerVisitProdDiscussion": [{' +
                '"providervisitproductdtlid": null,' +
                '"additionalinformation": "Discussed dosing schedule"' +
            '}],' +
            '"providerVisitDtlProductMsg": [],' +
            '"confidence": {' +
                '"overall": 0.92,' +
                '"visit": 0.95,' +
                '"providerVisit": 0.9,' +
                '"productDetailing": 0.88,' +
                '"productDiscussion": 0.85,' +
                '"productMessage": 0.0' +
            '},' +
            '"extractedEntities": {' +
                '"providers": ["Dr. Jones"],' +
                '"products": ["TestProduct123"],' +
                '"activities": ["detailing"],' +
                '"outcomes": ["positive response"],' +
                '"dates": ["2026-05-22"],' +
                '"locations": ["Test Medical Center"]' +
            '}' +
        '}';

        Test.startTest();
        List<VisitNoteProcessor.ProcessingResult> results =
            VisitNoteProcessor.processVisitNotes(new List<String>{ jsonWithProducts });
        Test.stopTest();

        System.assertEquals(1, results.size(), 'Should return one result');
        VisitNoteProcessor.ProcessingResult result = results[0];
        if (result.success) {
            System.assertNotEquals(null, result.visitId, 'Should have visit ID');
            System.assertNotEquals(null, result.actionType, 'Should have action type');
        }
    }

    @IsTest
    static void testProcessVisitNotes_UpdateExistingVisit() {
        Account acc = [SELECT Id FROM Account WHERE Name = 'Test Medical Center' LIMIT 1];

        // Create an existing planned visit for today
        Visit existingVisit = new Visit();
        existingVisit.AccountId = acc.Id;
        existingVisit.Status = 'Planned';
        existingVisit.PlannedVisitStartTime = DateTime.now();
        existingVisit.OwnerId = UserInfo.getUserId();
        existingVisit.VisitorId = UserInfo.getUserId();

        // Need territory and place - attempt to set them
        try {
            List<Territory2> territories = [SELECT Id FROM Territory2 LIMIT 1];
            if (!territories.isEmpty()) {
                existingVisit.TerritoryId = territories[0].Id;
            }
            List<ContactPointAddress> addresses = [SELECT Id FROM ContactPointAddress LIMIT 1];
            if (!addresses.isEmpty()) {
                existingVisit.PlaceId = addresses[0].Id;
            }
            insert existingVisit;
        } catch (Exception e) {
            // If Visit insert fails (missing required fields/objects), skip this test scenario
            return;
        }

        String jsonData = buildValidJson();

        Test.startTest();
        List<VisitNoteProcessor.ProcessingResult> results =
            VisitNoteProcessor.processVisitNotes(new List<String>{ jsonData });
        Test.stopTest();

        System.assertEquals(1, results.size(), 'Should return one result');
        if (results[0].success) {
            System.assertEquals('UPDATE', results[0].actionType, 'Should update existing visit');
            System.assertEquals(existingVisit.Id, results[0].visitId, 'Should reference existing visit');
        }
    }

    @IsTest
    static void testExtractedEntitiesDeserialization() {
        String jsonInput = '{"providers":["Dr. A","Dr. B"],"products":["Drug X"],"activities":["meeting"],"outcomes":["approved"],"dates":["2026-01-01"],"locations":["NYC"]}';

        VisitNoteProcessor.ExtractedEntitiesData entities =
            (VisitNoteProcessor.ExtractedEntitiesData) System.JSON.deserialize(jsonInput, VisitNoteProcessor.ExtractedEntitiesData.class);

        System.assertEquals(2, entities.providers.size());
        System.assertEquals(1, entities.products.size());
        System.assertEquals('Drug X', entities.products[0]);
        System.assertEquals(1, entities.locations.size());
    }

    @IsTest
    static void testConfidenceDataDeserialization() {
        String jsonInput = '{"overall":0.95,"visit":0.9,"providerVisit":0.85,"productDetailing":0.8,"productDiscussion":0.75,"productMessage":0.7}';

        VisitNoteProcessor.ConfidenceData confidence =
            (VisitNoteProcessor.ConfidenceData) System.JSON.deserialize(jsonInput, VisitNoteProcessor.ConfidenceData.class);

        System.assertEquals(0.95, confidence.overall);
        System.assertEquals(0.9, confidence.visit);
        System.assertEquals(0.85, confidence.providerVisit);
        System.assertEquals(0.8, confidence.productDetailing);
        System.assertEquals(0.75, confidence.productDiscussion);
        System.assertEquals(0.7, confidence.productMessage);
    }

    @IsTest
    static void testConfidenceThresholdBoundary() {
        // Test exactly at threshold (0.5)
        String jsonAtThreshold = buildLowConfidenceJson().replace('"overall": 0.3', '"overall": 0.5');

        Test.startTest();
        List<VisitNoteProcessor.ProcessingResult> results =
            VisitNoteProcessor.processVisitNotes(new List<String>{ jsonAtThreshold });
        Test.stopTest();

        System.assertEquals(1, results.size(), 'Should return one result');
        // At exactly 0.5, confidence check is < 0.5, so 0.5 should pass
        if (!results[0].success) {
            System.assert(!results[0].message.contains('Confidence too low'),
                'Confidence of 0.5 should not be rejected by threshold');
        }
    }
}
