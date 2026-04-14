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
    }
}