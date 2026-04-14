@RestResource(urlMapping='/AgentGovernor/*')
global without sharing class AgentGovernorAPI {

    global class ResponseWrapper {
        public String status;       // "GO" or "STOP"
        public String reason;       // "OK", "QUOTA", "PACING", "TIME", "WEEKEND"
        public Decimal samplingRate;
    }

    @HttpGet
    global static ResponseWrapper checkStatus() {
        ResponseWrapper resp = new ResponseWrapper();
        String key = RestContext.request.params.get('key');
        
        // 1. Fetch Configuration
        List<Agent_Governor_Configuration__c> configs = [
            SELECT Is_Green__c, Is_Active__c, Sampling_Rate__c, Current_Count__c, Daily_Limit__c,
                   Start_Hour__c, End_Hour__c, Time_Zone__c, Exclude_Weekends__c
            FROM Agent_Governor_Configuration__c 
            WHERE Governor_Key__c = :key LIMIT 1
        ];

        if (configs.isEmpty() || !configs[0].Is_Active__c) { 
            resp.status = 'STOP'; 
            resp.reason = 'INACTIVE';
            return resp; 
        }
        
        Agent_Governor_Configuration__c config = configs[0];

        // 2. Hard Quota Check
        if (!config.Is_Green__c) {
            resp.status = 'STOP'; 
            resp.reason = 'QUOTA';
            return resp;
        }

        // 3. Time & Logic Check
        String logicResult = checkTimeLogic(config);
        
        if (logicResult != 'OK') {
            resp.status = 'STOP';
            resp.reason = logicResult;
            return resp;
        }

        // 4. Success
        resp.status = 'GO';
        resp.reason = 'OK';
        resp.samplingRate = (config.Sampling_Rate__c != null) ? (config.Sampling_Rate__c / 100) : 1.0;
        return resp;
    }

    private static String checkTimeLogic(Agent_Governor_Configuration__c config) {
        // If no Time Zone is set, we assume it is always open (UTC) or skip checks
        if (config.Time_Zone__c == null) return 'OK'; 
        
        DateTime now = DateTime.now();
        String tzId = config.Time_Zone__c; // e.g., 'America/New_York'
        
        // A. Weekend Check
        if (config.Exclude_Weekends__c) {
            // format('EEE', tzId) returns 'Sat', 'Sun', 'Mon', etc.
            String dayOfWeek = now.format('EEE', tzId); 
            if (dayOfWeek == 'Sat' || dayOfWeek == 'Sun') return 'WEEKEND';
        }

        // B. Operating Hours Check
        // format('H', tzId) returns 0-23
        Integer currentHour = Integer.valueOf(now.format('H', tzId)); 
        
        if (currentHour < config.Start_Hour__c || currentHour >= config.End_Hour__c) {
            return 'TIME';
        }

        return 'OK';
    }
}