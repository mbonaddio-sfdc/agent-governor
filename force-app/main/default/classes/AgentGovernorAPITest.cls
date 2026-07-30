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
        
        // 2. Over Quota Config (Red) — quota exhausted TODAY.
        // Reset_Date__c = today (no time zone -> server date) so the day-aware quota
        // check treats this as a genuine same-day exhaustion and returns QUOTA.
        Agent_Governor_Configuration__c quotaConfig = new Agent_Governor_Configuration__c(
            Name = 'Over Quota Pilot',
            Governor_Key__c = 'quota-v1',
            Is_Active__c = true,
            Is_Green__c = false, // This will trigger the 'QUOTA' stop
            Reset_Date__c = Date.today()
        );

        // 2b. Stale Quota Config (Red flag left over from YESTERDAY).
        // Regression guard for the daily-reset deadlock: Is_Green is false but the flag
        // was set on a previous day, so the API must ignore it and return GO.
        Agent_Governor_Configuration__c staleQuotaConfig = new Agent_Governor_Configuration__c(
            Name = 'Stale Quota Pilot',
            Governor_Key__c = 'stale-quota-v1',
            Is_Active__c = true,
            Is_Green__c = false,
            Sampling_Rate__c = 100,
            Reset_Date__c = Date.today().addDays(-1)
        );

        // 3. Inactive Config
        Agent_Governor_Configuration__c inactiveConfig = new Agent_Governor_Configuration__c(
            Name = 'Inactive Pilot',
            Governor_Key__c = 'inactive-v1',
            Is_Active__c = false
        );

        // 4. (The "out of hours" config is built inside testOutOfHours itself, because it needs
        // a valid same-day window — End > Start, enforced by the Operating_Hours_Valid rule —
        // that deliberately excludes the current hour. See testOutOfHours below.)

        // 5. No Operating Hours Config — timezone set, but Start/End hours left blank.
        // Should be treated as "hours not configured" -> always open.
        Agent_Governor_Configuration__c noHoursConfig = new Agent_Governor_Configuration__c(
            Name = 'No Hours Pilot',
            Governor_Key__c = 'nohours-v1',
            Is_Active__c = true,
            Is_Green__c = true,
            Time_Zone__c = 'UTC',
            Exclude_Weekends__c = false
            // Start_Hour__c / End_Hour__c deliberately left null
        );

        insert new List<Agent_Governor_Configuration__c>{happyConfig, quotaConfig, staleQuotaConfig, inactiveConfig, noHoursConfig};
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

    // Regression guard for the daily-reset deadlock.
    // A red Is_Green flag left over from a PREVIOUS day must NOT keep the agent hidden:
    // the quota is fresh again today, so the API should return GO and let a new session
    // start (which then self-heals the reset via the trigger).
    @isTest
    static void testStaleQuotaResetsNextDay() {
        setupRestContext('stale-quota-v1');

        Test.startTest();
        AgentGovernorAPI.ResponseWrapper response = AgentGovernorAPI.checkStatus();
        Test.stopTest();

        System.assertEquals('GO', response.status, 'A quota flag set on a previous day must be ignored -> GO');
        System.assertEquals('OK', response.reason, 'Reason should be OK once the stale quota is bypassed');
    }

    // A config with a timezone but no Start/End hours must not silently apply a
    // partial hours rule — it should be treated as always open and return GO.
    @isTest
    static void testNoOperatingHoursIsOpen() {
        setupRestContext('nohours-v1');

        Test.startTest();
        AgentGovernorAPI.ResponseWrapper response = AgentGovernorAPI.checkStatus();
        Test.stopTest();

        System.assertEquals('GO', response.status, 'Blank operating hours should be treated as always open');
        System.assertEquals('OK', response.reason, 'Reason should be OK when hours are not configured');
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
        // Build a VALID same-day window (End > Start, per the Operating_Hours_Valid rule) that
        // deliberately excludes the CURRENT hour, so we get a deterministic "closed" result
        // without relying on the old invalid 0->0 sentinel. The window [startH, endH) is
        // constructed so the current hour is never inside it.
        Integer h = Integer.valueOf(DateTime.now().format('H', 'UTC'));
        Integer startH = (h == 0) ? 1 : 0;
        Integer endH   = (h == 0) ? 2 : h;   // hour is < startH (when h=0) or >= endH (when h>0) -> closed

        Agent_Governor_Configuration__c timeConfig = new Agent_Governor_Configuration__c(
            Name = 'Out of Hours Pilot',
            Governor_Key__c = 'time-v1',
            Is_Active__c = true,
            Is_Green__c = true,
            Time_Zone__c = 'UTC',
            Start_Hour__c = startH,
            End_Hour__c = endH,
            Exclude_Weekends__c = false
        );
        insert timeConfig;

        setupRestContext('time-v1');

        Test.startTest();
        AgentGovernorAPI.ResponseWrapper response = AgentGovernorAPI.checkStatus();
        Test.stopTest();

        System.assertEquals('STOP', response.status, 'Status should be STOP outside operating hours');
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

        // We can't mock DateTime.now() in standard Apex, but we CAN compute what today
        // actually is in the config's time zone and assert the exact expected branch. That
        // makes this meaningful (a broken weekend check now fails the test) instead of a
        // tautology, and across a week of runs it exercises both the weekend and weekday paths.
        String dayOfWeek = DateTime.now().format('EEE', 'UTC');
        Boolean isWeekend = (dayOfWeek == 'Sat' || dayOfWeek == 'Sun');

        if (isWeekend) {
            System.assertEquals('STOP', response.status, 'On a weekend the agent must be stopped');
            System.assertEquals('WEEKEND', response.reason, 'Reason should be WEEKEND on Sat/Sun');
        } else {
            System.assertEquals('GO', response.status, 'On a weekday the agent should be shown');
            System.assertEquals('OK', response.reason, 'Reason should be OK on a weekday');
        }
    }

    // Positive counterpart to testOutOfHours: a valid same-day window (End > Start) that
    // DOES include the current hour must return GO/OK. Built dynamically so it is deterministic
    // regardless of when the suite runs. Together the two tests exercise both the in-window and
    // out-of-window branches of the operating-hours check.
    @isTest
    static void testWithinOperatingHours() {
        // A window [0, 24) always includes the current hour (0-23) and satisfies End > Start.
        Agent_Governor_Configuration__c openConfig = new Agent_Governor_Configuration__c(
            Name = 'In Hours Pilot',
            Governor_Key__c = 'inhours-v1',
            Is_Active__c = true,
            Is_Green__c = true,
            Time_Zone__c = 'UTC',
            Start_Hour__c = 0,
            End_Hour__c = 24,
            Exclude_Weekends__c = false
        );
        insert openConfig;

        setupRestContext('inhours-v1');

        Test.startTest();
        AgentGovernorAPI.ResponseWrapper response = AgentGovernorAPI.checkStatus();
        Test.stopTest();

        System.assertEquals('GO', response.status, 'Within operating hours the agent should be shown');
        System.assertEquals('OK', response.reason, 'Reason should be OK within operating hours');
    }

    // The Operating_Hours_Valid rule must reject a transposed/equal window (End <= Start).
    // This proves the guardrail is live: an admin who enters Start 17, End 9 (a transposition)
    // or Start 9, End 9 (equal) is blocked at save time rather than silently mis-scheduling.
    @isTest
    static void testTransposedHoursRejected() {
        Boolean blocked = false;
        try {
            insert new Agent_Governor_Configuration__c(
                Name = 'Transposed Hours',
                Governor_Key__c = 'transposed-v1',
                Is_Active__c = true,
                Is_Green__c = true,
                Time_Zone__c = 'UTC',
                Start_Hour__c = 17,
                End_Hour__c = 9,
                Exclude_Weekends__c = false
            );
        } catch (DmlException e) {
            blocked = true;
            System.assert(
                e.getMessage().contains('End Hour must be later than Start Hour'),
                'Expected the Operating_Hours_Valid message, got: ' + e.getMessage()
            );
        }
        System.assertEquals(true, blocked, 'A transposed window (End <= Start) must be blocked by the validation rule');
    }
}