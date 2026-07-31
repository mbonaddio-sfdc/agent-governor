public without sharing class GovernorEngine {

    // ---- Clock seam (test determinism) --------------------------------------
    // Tests can pin "now" so the weekend, operating-hours and day-rollover logic is
    // deterministic and independent of when the suite happens to run. Production never
    // sets this, so now() returns the real clock. Kept @TestVisible so the override is
    // not part of the class's callable surface at runtime; now() is public because the
    // read path (AgentGovernorAPI) shares the same clock.
    @TestVisible private static DateTime overrideNow = null;

    public static DateTime now() {
        return (overrideNow != null) ? overrideNow : DateTime.now();
    }

    /**
     * Returns "today's" date for the given IANA time zone (e.g. 'Australia/Sydney').
     * Shared by the increment path (GovernorEngine) and the read path (AgentGovernorAPI)
     * so both agree on when a new day has started. Falls back to server date if null.
     */
    public static Date getLocalToday(String tzId) {
        if (tzId != null) {
            return Date.valueOf(now().format('yyyy-MM-dd', tzId));
        }
        return Date.today();
    }

    @future
    public static void incrementAndEvaluate(Set<Id> channelIds) {
        List<Agent_Governor_Configuration__c> configsToUpdate = new List<Agent_Governor_Configuration__c>();
        
        // Lock rows to prevent race conditions
        List<Agent_Governor_Configuration__c> configs = [
            SELECT Id, Current_Count__c, Daily_Limit__c, Is_Green__c, Reset_Date__c, Time_Zone__c 
            FROM Agent_Governor_Configuration__c 
            WHERE Linked_Channel_Id__c IN :channelIds 
            FOR UPDATE
        ];
        
        for (Agent_Governor_Configuration__c c : configs) {
            
            // 1. Calculate "Today" based on the Record's specific Time Zone
            Date localToday = getLocalToday(c.Time_Zone__c);

            // 2. Auto-Reset Logic
            // If the last reset date is NOT the same as "Local Today", reset the counter.
            if (c.Reset_Date__c != localToday) {
                c.Current_Count__c = 0;
                c.Reset_Date__c = localToday;
                c.Is_Green__c = true;
            }

            // 3. Increment
            c.Current_Count__c = (c.Current_Count__c == null ? 0 : c.Current_Count__c) + 1;
            
            // 4. Check Hard Limit
            // Only enforce a count cap when a Daily_Limit is actually configured.
            // A blank limit means "no daily conversation cap" — the admin can still
            // gate exposure via Is_Active, sampling and operating hours. We guard the
            // null here explicitly so this is intentional, not an accident of how
            // Apex evaluates `count >= null` (which is false).
            if (c.Daily_Limit__c != null && c.Current_Count__c >= c.Daily_Limit__c) {
                c.Is_Green__c = false; // quota exhausted for today
            }
            
            configsToUpdate.add(c);
        }
        
        if (!configsToUpdate.isEmpty()) update configsToUpdate;
    }
}