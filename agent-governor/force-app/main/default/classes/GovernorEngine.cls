public without sharing class GovernorEngine {

    /**
     * Returns "today's" date for the given IANA time zone (e.g. 'Australia/Sydney').
     * Shared by the increment path (GovernorEngine) and the read path (AgentGovernorAPI)
     * so both agree on when a new day has started. Falls back to server date if null.
     */
    public static Date getLocalToday(String tzId) {
        if (tzId != null) {
            return Date.valueOf(DateTime.now().format('yyyy-MM-dd', tzId));
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
            if (c.Current_Count__c >= c.Daily_Limit__c) {
                c.Is_Green__c = false; // Kill Switch
            }
            
            configsToUpdate.add(c);
        }
        
        if (!configsToUpdate.isEmpty()) update configsToUpdate;
    }
}