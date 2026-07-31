# Data Dictionary — `Agent_Governor_Configuration__c`

Each record represents one governed Agentforce (MIAW) deployment. The client-side wrapper
on the website identifies its record by `Governor_Key__c`, and the Governor evaluates that
record's controls to decide whether to show the agent.

The fields fall into three groups: **identity/mapping**, **controls** (the four levers you
set), and **system-managed** (written automatically — do not edit by hand).

## Identity & mapping

| API Name | Label | Type | Purpose |
|----------|-------|------|---------|
| `Governor_Key__c` | Governor Key | Text (50) | **Required, unique** external ID that maps the website wrapper script to this record. Set this value in the wrapper's `GOVERNOR_KEY`. Being required prevents a keyless record the wrapper could never match; being unique prevents two records answering to the same key. Indexed (External ID) so the guest lookup is fast. If a request arrives with a key that matches no record, the API returns `STOP` / `NOTFOUND`. |
| `Linked_Channel_ID__c` | Linked Channel ID | Text (18) | Salesforce ID of the Messaging (MIAW) Channel whose conversations should be counted against this record's daily limit. Indexed (External ID) so the trigger's "is this channel governed?" pre-check stays cheap even in a high-traffic org. |

## Controls (you set these)

| API Name | Label | Type | Default | Purpose |
|----------|-------|------|---------|---------|
| `Is_Active__c` | Is Active | Checkbox | `false` | **Master on/off switch.** If unchecked, the API returns `STOP` immediately, ignoring all other rules. This is the human kill switch. |
| `Sampling_Rate__c` | Sampling Rate | Percent (7,4) | — | Percentage of visitors permitted to see the agent (impression sampling). Returned to the wrapper as a 0–1 decimal. Blank = 100%. |
| `Daily_Limit__c` | Daily Limit | Number (18,0) | — | Target maximum conversations per calendar day. Blank = no cap. **Soft ceiling:** the count is incremented asynchronously after a session starts, so a burst of near-simultaneous conversations can slightly overshoot this number before the quota flag flips. Size it as a budget with headroom, not a precise cutoff. |
| `Start_Hour__c` | Start Hour | Number (0–23) | — | Hour at which traffic is allowed to start (in `Time_Zone__c`). |
| `End_Hour__c` | End Hour | Number (0–24) | — | Hour at which traffic is blocked (in `Time_Zone__c`). **Must be later than Start Hour** — enforced by the `Operating_Hours_Valid` validation rule. Operating hours apply only when **both** Start and End are set; otherwise the agent is treated as always open. Overnight windows that cross midnight are not supported. |
| `Time_Zone__c` | Time Zone | Picklist (IANA IDs) | — | IANA time zone ID (e.g. `Australia/Sydney`, `UTC`) used to calculate "start of day" for the daily reset and to evaluate operating hours. **Required whenever operating hours are set or Exclude Weekends is on** (enforced by `Time_Zone_Required_With_Schedule`). |
| `Exclude_Weekends__c` | Exclude Weekends | Checkbox | `false` | When checked, blocks traffic on Saturday and Sunday (evaluated in `Time_Zone__c`). Requires a Time Zone to take effect. |

## System-managed (do not edit by hand)

| API Name | Label | Type | Default | Purpose |
|----------|-------|------|---------|---------|
| `Current_Count__c` | Current Count | Number (18,0) | — | Running count of conversations today. Incremented automatically by the trigger when a new `MessagingSession` starts. |
| `Is_Green__c` | Is Green | Checkbox | `false` | System quota flag. Checked = quota open; unchecked = today's `Daily_Limit__c` has been reached. Managed by the engine; resets automatically on the next day. To switch the agent off manually, use `Is_Active__c` instead. |
| `Reset_Date__c` | Reset Date | Date | — | The last date the counter was zeroed, used to perform the once-per-day reset and prevent double-resets. |

## How the controls combine

On each request the API returns `STOP` (and a reason) if **any** of these is true, checked
in order: no record matches the key (`NOTFOUND`); the record exists but `Is_Active__c` is
false (`INACTIVE`); today's quota is exhausted (`QUOTA`); it is a weekend and weekends are
excluded (`WEEKEND`); or the current time is outside operating hours (`TIME`). `NOTFOUND` and
`INACTIVE` are kept distinct so an integrator can tell a mistyped/missing key apart from an
intentional kill switch. Otherwise it returns `GO` with the sampling rate, and the wrapper
performs the final impression-sampling roll in the browser.

## Validation rules

These rules run when an admin saves a configuration record. They catch misconfigurations
that would otherwise fail silently at runtime. They do not affect the read-only API path.

| Rule | Fires when | Why |
|------|-----------|-----|
| `Operating_Hours_Valid` | Both hours set and `End_Hour__c` ≤ `Start_Hour__c` | Blocks a transposed window (e.g. Start 17, End 9) and an equal window (e.g. 9→9). Same-day windows only; overnight is not supported. |
| `Operating_Hours_Both_Or_Neither` | Exactly one of Start / End is set | Forces hours to be a pair, so a half-filled window isn't silently treated as "always open." |
| `Sampling_Rate_In_Range` | `Sampling_Rate__c` < 0 or > 100 | Keeps the sampling percentage sane; blank is allowed and means 100%. |
| `Time_Zone_Required_With_Schedule` | `Time_Zone__c` blank while hours are set or `Exclude_Weekends__c` is on | A schedule with no time zone is skipped at runtime; this ensures the schedule actually takes effect. |
