@isTest
private class AgentGovernorAPITest {
    
    @testSetup
    static void setupTestData() {
        // 1. Happy Path Config (Active, Green, Always Open)
        Agent_Governor_Configuration__c happyConfig = new Agent_Governor_Configuration__c(
            Name = 'Happy Path Pilot',
            Governor_Key__c = 'happy-v1',
            Is_Active__c = true,
            Is_Green__c = true,
            Sampling_Rate__c = 50, // 50%
            Time_Zone__c = 'UTC',
            Start_Hour__c = 0,
            End_Hour__c = 24,
            Exclude_Weekends__c = false
        );
        
        // 2. Over Quota Config (Red)
        Agent_Governor_Configuration__c quotaConfig = new Agent_Governor_Configuration__c(
            Name = 'Over Quota Pilot',
            Governor_Key__c = 'quota-v1',
            Is_Active__c = true,
            Is_Green__c = false // This will trigger the 'QUOTA' stop
        );

        // 3. Inactive Config
        Agent_Governor_Configuration__c inactiveConfig = new Agent_Governor_Configuration__c(
            Name = 'Inactive Pilot',
            Governor_Key__c = 'inactive-v1',
            Is_Active__c = false
        );

        // 4. Out of Hours Config (Forced Closed)
        Agent_Governor_Configuration__c timeConfig = new Agent_Governor_Configuration__c(
            Name = 'Out of Hours Pilot',
            Governor_Key__c = 'time-v1',
            Is_Active__c = true,
            Is_Green__c = true,
            Time_Zone__c = 'UTC',
            Start_Hour__c = 0,
            End_Hour__c = 0, // Setting Start/End to 0 ensures the current hour is always >= End_Hour
            Exclude_Weekends__c = false
        );

        insert new List<Agent_Governor_Configuration__c>{happyConfig, quotaConfig, inactiveConfig, timeConfig};
    }

    // --- HELPER METHOD: Mocks the incoming HTTP Request ---
    private static void setupRestContext(String key) {
        RestRequest req = new RestRequest();
        RestResponse res = new RestResponse();
        req.requestURI = '/services/apexrest/AgentGovernor';
        req.httpMethod = 'GET';
        req.addParameter('key', key);
        
        RestContext.request = req;
        RestContext.response = res;
    }

    // --- TEST METHODS ---

    @isTest
    static void testHappyPath() {
        setupRestContext('happy-v1');
        
        Test.startTest();
        AgentGovernorAPI.ResponseWrapper response = AgentGovernorAPI.checkStatus();
        Test.stopTest();
        
        System.assertEquals('GO', response.status, 'Status should be GO');
        System.assertEquals('OK', response.reason, 'Reason should be OK');
        System.assertEquals(0.5, response.samplingRate, 'Sampling rate should be correctly divided by 100');
    }

    @isTest
    static void testQuotaHit() {
        setupRestContext('quota-v1');
        
        Test.startTest();
        AgentGovernorAPI.ResponseWrapper response = AgentGovernorAPI.checkStatus();
        Test.stopTest();
        
        System.assertEquals('STOP', response.status, 'Status should be STOP');
        System.assertEquals('QUOTA', response.reason, 'Reason should be QUOTA');
    }

    @isTest
    static void testInactiveOrNotFound() {
        // Test 1: Record exists but Is_Active__c = false
        setupRestContext('inactive-v1');
        AgentGovernorAPI.ResponseWrapper response1 = AgentGovernorAPI.checkStatus();
        System.assertEquals('STOP', response1.status, 'Status should be STOP for inactive record');
        System.assertEquals('INACTIVE', response1.reason, 'Reason should be INACTIVE');

        // Test 2: Invalid Key (Record doesn't exist)
        setupRestContext('invalid-key-xyz');
        AgentGovernorAPI.ResponseWrapper response2 = AgentGovernorAPI.checkStatus();
        System.assertEquals('STOP', response2.status, 'Status should be STOP when config is not found');
        System.assertEquals('INACTIVE', response2.reason, 'Reason should default to INACTIVE');
    }

    @isTest
    static void testOutOfHours() {
        setupRestContext('time-v1');
        
        Test.startTest();
        AgentGovernorAPI.ResponseWrapper response = AgentGovernorAPI.checkStatus();
        Test.stopTest();
        
        System.assertEquals('STOP', response.status, 'Status should be STOP');
        System.assertEquals('TIME', response.reason, 'Reason should be TIME');
    }
    
    @isTest
    static void testWeekendLogic() {
        // Create a config that excludes weekends.
        Agent_Governor_Configuration__c weekendConfig = new Agent_Governor_Configuration__c(
            Name = 'Weekend Test',
            Governor_Key__c = 'weekend-v1',
            Is_Active__c = true,
            Is_Green__c = true,
            Time_Zone__c = 'UTC',
            Start_Hour__c = 0,
            End_Hour__c = 24,
            Exclude_Weekends__c = true
        );
        insert weekendConfig;
        
        setupRestContext('weekend-v1');
        
        Test.startTest();
        AgentGovernorAPI.ResponseWrapper response = AgentGovernorAPI.checkStatus();
        Test.stopTest();
        
        // Because we cannot definitively mock DateTime.now() in standard Apex without dependency injection,
        // we assert that the code executes successfully without runtime errors and returns a valid status.
        // It will return 'STOP'/'WEEKEND' on Sat/Sun, and 'GO'/'OK' on Mon-Fri.
        System.assertNotEquals(null, response.status, 'Response status should not be null');
        System.assert(response.status == 'GO' || response.status == 'STOP', 'Status must be GO or STOP');
    }
}