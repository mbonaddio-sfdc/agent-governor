public without sharing class GovernorEngine {
    
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
            Date localToday;
            
            if (c.Time_Zone__c != null) {
                // Force the date to match the configured IANA Time Zone (e.g., Australia/Sydney)
                String dateString = DateTime.now().format('yyyy-MM-dd', c.Time_Zone__c);
                localToday = Date.valueOf(dateString);
            } else {
                // Fallback to Server Date if no Time Zone is set
                localToday = Date.today();
            }

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