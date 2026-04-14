@isTest
private class GovernorEngineTest {

    @testSetup
    static void setupData() {
        // 1. We need real Channel IDs to link to our Configs, 
        // so we insert dummy Messaging Channels (Setup Objects) first.
        User thisUser = [SELECT Id FROM User WHERE Id = :UserInfo.getUserId()];
        
        MessagingChannel ch1 = new MessagingChannel(MasterLabel='Ch1', DeveloperName='Ch1', MessageType='Text', MessagingPlatformKey='+111');
        MessagingChannel ch2 = new MessagingChannel(MasterLabel='Ch2', DeveloperName='Ch2', MessageType='Text', MessagingPlatformKey='+222');
        MessagingChannel ch3 = new MessagingChannel(MasterLabel='Ch3', DeveloperName='Ch3', MessageType='Text', MessagingPlatformKey='+333');
        
        System.runAs(thisUser) {
            insert new List<MessagingChannel>{ch1, ch2, ch3};
        }

        // 2. Config A: The "Kill Switch" Scenario 
        // Sitting at 4, Limit is 5. One more chat should trip the switch.
        Agent_Governor_Configuration__c configKillSwitch = new Agent_Governor_Configuration__c(
            Name = 'Kill Switch Test',
            Governor_Key__c = 'ks-1',
            Linked_Channel_Id__c = ch1.Id,
            Current_Count__c = 4,
            Daily_Limit__c = 5,
            Is_Green__c = true,
            Reset_Date__c = Date.today(),
            Time_Zone__c = 'America/New_York'
        );

        // 3. Config B: The "Auto-Reset" Scenario
        // Count is maxed out, but the Reset Date was yesterday. It should wipe clean to 1.
        Agent_Governor_Configuration__c configReset = new Agent_Governor_Configuration__c(
            Name = 'Reset Test',
            Governor_Key__c = 'rst-1',
            Linked_Channel_Id__c = ch2.Id,
            Current_Count__c = 50,
            Daily_Limit__c = 10,
            Is_Green__c = false, // Currently dead
            Reset_Date__c = Date.today().addDays(-1), // Yesterday
            Time_Zone__c = 'UTC'
        );

        // 4. Config C: The "No Time Zone" Fallback Scenario
        Agent_Governor_Configuration__c configNoTz = new Agent_Governor_Configuration__c(
            Name = 'No TZ Test',
            Governor_Key__c = 'notz-1',
            Linked_Channel_Id__c = ch3.Id,
            Current_Count__c = 1,
            Daily_Limit__c = 10,
            Is_Green__c = true,
            Reset_Date__c = Date.today()
            // Time_Zone__c deliberately left null
        );

        insert new List<Agent_Governor_Configuration__c>{configKillSwitch, configReset, configNoTz};
    }

    @isTest
    static void testEngineLogic() {
        // Gather the IDs of our dummy channels to pass to the Engine
        Map<Id, MessagingChannel> channels = new Map<Id, MessagingChannel>([SELECT Id FROM MessagingChannel]);
        Set<Id> channelIds = channels.keySet();

        // Execution
        Test.startTest();
        
        // Calling the @future method directly
        GovernorEngine.incrementAndEvaluate(channelIds);
        
        // Test.stopTest() forces the @future method to execute immediately
        Test.stopTest(); 

        // Verification
        List<Agent_Governor_Configuration__c> results = [
            SELECT Name, Current_Count__c, Is_Green__c, Reset_Date__c 
            FROM Agent_Governor_Configuration__c
        ];

        for (Agent_Governor_Configuration__c res : results) {
            if (res.Name == 'Kill Switch Test') {
                System.assertEquals(5, res.Current_Count__c, 'Count should increment to 5');
                System.assertEquals(false, res.Is_Green__c, 'Kill switch should be flipped OFF');
            } 
            else if (res.Name == 'Reset Test') {
                System.assertEquals(1, res.Current_Count__c, 'Old count should be wiped, and new session makes it 1');
                System.assertEquals(true, res.Is_Green__c, 'Kill switch should be flipped back ON for the new day');
                System.assertEquals(Date.today(), res.Reset_Date__c, 'Reset date should be updated to today');
            } 
            else if (res.Name == 'No TZ Test') {
                System.assertEquals(2, res.Current_Count__c, 'Fallback logic should increment count to 2');
            }
        }
    }
}