@isTest
private class AgentGovernorTriggerTest {

    @isTest
    static void testTriggerFiresEngine() {
        
        // Grab the current user to run the setup DML context
        User thisUser = [SELECT Id FROM User WHERE Id = :UserInfo.getUserId()];
        
        MessagingChannel testChannel;

        // 1. Setup Prerequisite: Messaging Channel (Setup Object)
        // Wrapped in System.runAs to prevent MIXED_DML_OPERATION
        System.runAs(thisUser) {
            testChannel = new MessagingChannel(
                MasterLabel = 'Test Governor Channel',
                DeveloperName = 'Test_Governor_Channel',
                MessageType = 'Text',
                MessagingPlatformKey = '+15555559999'
            );
            insert testChannel;
        }

        // 2. Setup Prerequisite: Messaging End User (Non-Setup Object)
        MessagingEndUser testUser = new MessagingEndUser(
            Name = 'Test User',
            MessagingChannelId = testChannel.Id,
            MessageType = 'Text',
            MessagingPlatformKey = '+15555551234',
            MessagingConsentStatus = 'ImplicitlyOptedIn'
        );
        insert testUser;

        // 2b. A Governor config linked to that channel, so we can prove the trigger
        // actually incremented its counter — not merely that the session row inserted.
        // Reset_Date stamped as today (in the config's TZ) so the engine increments
        // rather than performing a new-day reset.
        Agent_Governor_Configuration__c config = new Agent_Governor_Configuration__c(
            Name = 'Trigger Count Test',
            Governor_Key__c = 'trigger-v1',
            Linked_Channel_Id__c = testChannel.Id,
            Current_Count__c = 0,
            Daily_Limit__c = 10,
            Is_Green__c = true,
            Time_Zone__c = 'UTC',
            Reset_Date__c = GovernorEngine.getLocalToday('UTC')
        );
        insert config;

        // 3. Create the actual Messaging Session to fire the trigger
        MessagingSession testSession = new MessagingSession(
            MessagingChannelId = testChannel.Id,
            MessagingEndUserId = testUser.Id,
            Status = 'Active'
        );

        // 4. Test Execution
        Test.startTest();
        
        // This insert fires the AgentGovernorTrigger -> which calls GovernorEngine
        insert testSession; 
        
        Test.stopTest();

        // 5. Assertions
        System.assertNotEquals(null, testSession.Id, 'Messaging Session should be inserted successfully.');

        // The trigger fires GovernorEngine.incrementAndEvaluate (@future), forced to run by
        // Test.stopTest() above. Confirm the linked config's counter actually advanced 0 -> 1.
        Agent_Governor_Configuration__c updated = [
            SELECT Current_Count__c FROM Agent_Governor_Configuration__c
            WHERE Governor_Key__c = 'trigger-v1' LIMIT 1
        ];
        System.assertEquals(1, updated.Current_Count__c, 'Trigger should have incremented the daily count to 1');
    }
}