trigger AgentGovernorTrigger on MessagingSession (after insert) {
    Set<Id> channelIds = new Set<Id>();
    for (MessagingSession ms : Trigger.new) {
        if (ms.MessagingChannelId != null) { channelIds.add(ms.MessagingChannelId); }
    }
    if (channelIds.isEmpty()) { return; }

    // Good-neighbour guard: only spin up the async counter when at least one of these
    // channels is actually governed by a config record. Without this, EVERY MessagingSession
    // insert org-wide — including channels that have nothing to do with Agent Governor —
    // would enqueue an @future and eat into the org's shared asynchronous limits. This
    // pre-check is one cheap, selective query because Linked_Channel_ID__c is an indexed
    // External ID. The @future re-queries FOR UPDATE and filters precisely, so passing the
    // full channel set here is safe; the point is simply not to enqueue it for nothing.
    Boolean anyGoverned = ![
        SELECT Id FROM Agent_Governor_Configuration__c
        WHERE Linked_Channel_ID__c IN :channelIds
        LIMIT 1
    ].isEmpty();

    if (anyGoverned) {
        GovernorEngine.incrementAndEvaluate(channelIds);
    }
}
