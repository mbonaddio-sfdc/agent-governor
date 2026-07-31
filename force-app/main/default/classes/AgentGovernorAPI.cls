@RestResource(urlMapping='/AgentGovernor/*')
global without sharing class AgentGovernorAPI {

    global class ResponseWrapper {
        public String status;       // "GO" or "STOP"
        public String reason;       // GO: "OK". STOP: "NOTFOUND", "INACTIVE", "QUOTA", "TIME", "WEEKEND"
        public Decimal samplingRate;
    }

    @HttpGet
    global static ResponseWrapper checkStatus() {
        ResponseWrapper resp = new ResponseWrapper();
        String key = RestContext.request.params.get('key');
        
        // 1. Fetch Configuration
        List<Agent_Governor_Configuration__c> configs = [
            SELECT Is_Green__c, Is_Active__c, Sampling_Rate__c, Current_Count__c, Daily_Limit__c,
                   Start_Hour__c, End_Hour__c, Time_Zone__c, Exclude_Weekends__c, Reset_Date__c
            FROM Agent_Governor_Configuration__c 
            WHERE Governor_Key__c = :key LIMIT 1
        ];

        // No record for this key at all. Distinct from INACTIVE (a record that exists
        // but has been deliberately switched off) so an integrator can tell a typo'd or
        // missing key apart from an intentional kill switch when debugging.
        if (configs.isEmpty()) {
            resp.status = 'STOP';
            resp.reason = 'NOTFOUND';
            return resp;
        }

        // Record exists but the human master switch is off.
        if (!configs[0].Is_Active__c) {
            resp.status = 'STOP';
            resp.reason = 'INACTIVE';
            return resp;
        }

        Agent_Governor_Configuration__c config = configs[0];

        // 2. Hard Quota Check (day-aware)
        // Is_Green__c is flipped false by GovernorEngine when the daily cap is hit, but the
        // reset-to-true only runs when a new MessagingSession fires the trigger. If we blindly
        // trusted a stale false flag we would deadlock: agent hidden -> no session -> no reset
        // -> agent stays hidden forever. So we only enforce QUOTA when the flag was set for
        // TODAY. If Reset_Date__c is in the past (or null), the quota is stale from an earlier
        // day: treat it as open and return GO. The first session that starts today then fires
        // the trigger and GovernorEngine self-heals the reset.
        if (!config.Is_Green__c) {
            Date localToday = GovernorEngine.getLocalToday(config.Time_Zone__c);
            if (config.Reset_Date__c == localToday) {
                resp.status = 'STOP';
                resp.reason = 'QUOTA';
                return resp;
            }
            // else: stale flag from a previous day -> quota is fresh, fall through to normal checks
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
        
        DateTime now = GovernorEngine.now(); // shared clock seam (real clock in production)
        String tzId = config.Time_Zone__c; // e.g., 'America/New_York'

        // A. Weekend Check
        // Use the ISO-8601 day-of-week NUMBER, which is locale-independent: format('u')
        // returns "1" (Monday) through "7" (Sunday), so 6 and 7 are the weekend. The
        // previous approach matched the English short names 'Sat'/'Sun' from format('EEE'),
        // which silently fails for a guest user whose locale renders those days in another
        // language — the check would never match and weekends would never be excluded.
        if (config.Exclude_Weekends__c) {
            Integer isoDayOfWeek = Integer.valueOf(now.format('u', tzId));
            if (isoDayOfWeek == 6 || isoDayOfWeek == 7) return 'WEEKEND';
        }

        // B. Operating Hours Check
        // Only enforce operating hours when BOTH bounds are set. A half-configured
        // window (one bound blank) is treated as "hours not configured" -> always open,
        // rather than silently applying a partial rule. Guarding explicitly here so the
        // behaviour is intentional, not a side effect of `hour < null` being false.
        // Same-day window only (e.g. 9 -> 17): open when start <= hour < end. Windows that
        // wrap past midnight are intentionally not supported — the Operating_Hours_Valid
        // validation rule enforces End Hour > Start Hour, which removes the ambiguity between
        // a genuine overnight window and a transposed pair (e.g. 17 -> 9).
        if (config.Start_Hour__c != null && config.End_Hour__c != null) {
            // format('H', tzId) returns 0-23
            Integer currentHour = Integer.valueOf(now.format('H', tzId));
            if (currentHour < config.Start_Hour__c || currentHour >= config.End_Hour__c) {
                return 'TIME';
            }
        }

        return 'OK';
    }
}