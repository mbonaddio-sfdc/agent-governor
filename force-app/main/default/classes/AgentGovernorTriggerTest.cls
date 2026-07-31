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

    // Good-neighbour guard: a MessagingSession on a channel that NO config is watching must
    // NOT enqueue the async counter. Without the pre-check in the trigger, every session
    // insert org-wide would spend an @future from the org's shared async budget. We prove the
    // guard by inserting a session on an unlinked channel and asserting no future was queued.
    @isTest
    static void testTriggerSkipsUngovernedChannel() {
        User thisUser = [SELECT Id FROM User WHERE Id = :UserInfo.getUserId()];

        MessagingChannel otherChannel;
        System.runAs(thisUser) {
            otherChannel = new MessagingChannel(
                MasterLabel = 'Ungoverned Channel',
                DeveloperName = 'Ungoverned_Channel',
                MessageType = 'Text',
                MessagingPlatformKey = '+15555550000'
            );
            insert otherChannel;
        }

        MessagingEndUser otherUser = new MessagingEndUser(
            Name = 'Ungoverned User',
            MessagingChannelId = otherChannel.Id,
            MessageType = 'Text',
            MessagingPlatformKey = '+15555554321',
            MessagingConsentStatus = 'ImplicitlyOptedIn'
        );
        insert otherUser;

        // Deliberately NO Agent_Governor_Configuration__c pointing at otherChannel.

        MessagingSession session = new MessagingSession(
            MessagingChannelId = otherChannel.Id,
            MessagingEndUserId = otherUser.Id,
            Status = 'Active'
        );

        Test.startTest();
        insert session; // fires the trigger; the guard should short-circuit before enqueuing
        // getFutureCalls() counts @future invocations made so far in THIS transaction. The
        // enqueue (if any) happens synchronously inside the trigger during the insert above,
        // so we read the counter before stopTest() flushes the async queue.
        System.assertEquals(0, Limits.getFutureCalls(),
            'An ungoverned channel must not enqueue the async counter (@future)');
        Test.stopTest();

        System.assertNotEquals(null, session.Id, 'The session itself must still insert normally');
    }
}