trigger AgentGovernorTrigger on MessagingSession (after insert) {
    Set<Id> channelIds = new Set<Id>();
    for (MessagingSession ms : Trigger.new) {
        if (ms.MessagingChannelId != null) { channelIds.add(ms.MessagingChannelId); }
    }
    if (!channelIds.isEmpty()) { GovernorEngine.incrementAndEvaluate(channelIds); }
}