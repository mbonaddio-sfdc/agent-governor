# Agent Governor — Hardening & Release Plan (v0.5 → v1.0)

_Last updated: 2026-07-30_

## Purpose

This document is the working map for taking Agent Governor from its current state
(roughly a v0.5 — functional, but with a couple of real bugs) to a publishable v1.0
that other people can pull from the GitHub repo and deploy into their own Salesforce
org. It captures **what needs fixing, why it matters, how we'll fix it, and how we'll
prove it works** before publishing.

It's written to be readable by a non-developer. Each item explains the problem in plain
language first, then the technical detail for whoever (or whatever) applies the fix.

## Where things stand today (v0.5)

The solution is further along than the original PDF brief. Already done:

- **Timezone-aware operating hours** — `checkTimeLogic` uses the record's IANA timezone
  (e.g. `Australia/Sydney`) rather than the org's clock. Good.
- **Automatic daily counter reset** — a `Reset_Date__c` field wipes the daily count when
  a new local day begins. Good (but see Fix #1 — the reset has a trap).
- **Three Apex test classes exist** — `AgentGovernorAPITest`, `GovernorEngineTest`,
  `AgentGovernorTriggerTest`.

Current data model (`Agent_Governor_Configuration__c`): `Governor_Key__c`,
`Linked_Channel_Id__c`, `Is_Active__c`, `Is_Green__c`, `Daily_Limit__c`,
`Current_Count__c`, `Sampling_Rate__c`, `Start_Hour__c`, `End_Hour__c`, `Time_Zone__c`,
`Exclude_Weekends__c`, `Reset_Date__c`.

Current logic: the **API** (`AgentGovernorAPI`) reads config and returns GO/STOP to the
website. The **trigger** (`AgentGovernorTrigger`) fires when a chat session is created and
calls `GovernorEngine.incrementAndEvaluate`, which counts the chat, resets the daily
counter when the date rolls over, and trips the kill switch when the cap is hit.

## Ground rules before we start

Two habits that matter more than any single fix:

1. **Git becomes the source of truth — not the org.** From here on, the repo is the
   canonical copy. We make changes in the repo, deploy them *to* the org, and never treat
   the org as the master again. This is what makes "other people pull the code down" work
   cleanly.

2. **We work directly in the prod/demo org — so validate before every deploy.** A sandbox
   or scratch org isn't an option here (the Agentforce/MIAW licensing this solution needs
   isn't available in Developer Edition or scratch orgs). Instead, every change is run
   through a **validation-only deploy** first: Salesforce compiles it and runs the Apex
   tests *without committing anything*. Only once that passes do we deploy for real. Git is
   the undo button (commit before and after), and data-model changes stay additive (we
   never delete a field until its replacement is proven). Because it's a prod org,
   Salesforce also enforces the 75% test-coverage bar automatically — useful discipline.

## The fixes, in priority order

### Fix #1 — CRITICAL: the daily reset can deadlock (permanent lockout)

**The problem in plain language.** When the daily chat cap is reached, the code switches
the agent off by setting `Is_Green__c` to false. The code that switches it back *on* for
the next day only runs when a new chat session is created. But once the agent is off, the
website stops showing it, so no new chat is ever created — which means the "switch it back
on tomorrow" code never runs. The agent stays dead until someone manually re-checks the
box. Effectively, the first time you hit your daily limit, the pilot silently stops for
good.

**Why it matters.** This defeats the core promise of the product ("launch small, ramp up
safely"). A customer sets a 50-chat daily cap, hits it on day one, and the agent never
comes back on day two. It fails silently, which is the worst kind of failure.

**Why the tests didn't catch it.** `GovernorEngineTest` calls `incrementAndEvaluate`
directly, so the reset always runs in the test. The real world routes through the API,
which is gated by the very flag the reset is supposed to clear.

**Proposed fix.** Decouple the reset from the increment path. The cleanest approach: move
the "has the day rolled over?" check into the **read path** so the API itself recognises a
new day and treats the agent as available again. Concretely, the API (or a shared helper)
should, on each request: compute the local date; if `Reset_Date__c` is in the past, treat
the record as reset (count 0, green) for the purpose of this check. A scheduled Apex job
that resets counters at local midnight is a valid alternative, but the read-path check is
more robust because it doesn't depend on a job firing. We'll also add a test that
reproduces the deadlock (cap hit → next day → API should return GO).

### Fix #2 — HIGH: separate the manual kill switch from the automated quota flag

**The problem in plain language.** One field, `Is_Green__c`, is doing two unrelated jobs:
it's the human "emergency off" switch described in the brief, *and* it's the automated
"we've hit the daily cap" flag. Because the daily reset flips it back to true every morning,
if you manually switch the agent off, tomorrow's reset switches it back on — overriding
your decision.

**Why it matters.** The "business kill switch — instantly pull the agent" is a headline
feature. If it can be silently undone overnight by the system, it isn't trustworthy.

**Proposed fix.** Split into two fields with clear, separate meanings:
- **`Is_Active__c`** (already exists) or a dedicated **`Kill_Switch__c`** = *human intent*.
  Only a person changes it. The system never touches it.
- **A new `Quota_Reached__c`** (or similar) = *system state*. The engine sets/clears this
  automatically; the daily reset only ever touches this one.

The API returns STOP if the human switch is off **or** the quota flag is set. The reset
logic only clears the quota flag. This keeps human intent and system state from fighting.

### Fix #3 — MEDIUM: guard against blank values (null-safety)

**The problem in plain language.** If an admin creates a config record but leaves the
daily limit blank, the counting code crashes. Same if the operating-hours fields are blank
but a timezone is set. Because this happens inside a background process, it fails silently
and is hard to diagnose.

**Proposed fix.** Before comparing against `Daily_Limit__c`, `Start_Hour__c`, and
`End_Hour__c`, check for null and either skip that check or apply a sensible default. Add
test cases with blank values so this stays fixed. Consider making key fields required at
the object level so bad records can't be created in the first place.

### Fix #4 — MEDIUM: bring the client-side JS wrapper into the repo

**The problem in plain language.** The JavaScript snippet that goes on the customer's
website (the piece that actually calls the API and decides whether to show the agent) is
described in the brief but isn't in the repo. Since the plan is for people to pull the repo
and deploy it, they currently can't — a critical piece is missing.

**Why it matters.** Without the wrapper, the repo is only half the product. This also lets
us verify two things we couldn't check from the brief: whether sampling is "sticky" per
visitor (a returning visitor should get a consistent experience, which needs a cookie or
localStorage flag), and whether the API URL is built correctly.

**Proposed fix.** Add the wrapper to the repo — either as a Salesforce **static resource**
(so it deploys with everything else) or, at minimum, as a documented snippet in the README
with clear placeholders. While adding it, make sampling sticky (store the "in/out" decision
per visitor) and confirm the endpoint URL.

### Fix #5 — LOW: tighten the tests and write a real README

**The problems in plain language.** A few tests look like they pass but don't actually
check anything meaningful: the weekend test asserts the result is "GO or STOP" (always
true), and the trigger test confirms a chat record was created but never checks that the
count went up. Also, overnight operating windows (e.g. 22:00–06:00) aren't supported. And
the README is still the default Salesforce boilerplate.

**Proposed fix.** Make the weekend and trigger tests assert real outcomes (inject or
control the date/time so the result is deterministic; verify the count incremented).
Decide whether overnight windows need supporting for v1.0 (if not, document the limitation).
Replace the README with a real one (see the release checklist below).

## The test loop (how we verify each change)

For every fix, the loop is the same:

1. Make the change in the repo (code + matching test).
2. **Validate** against the org (compiles + runs tests, commits nothing):
   `sf project deploy validate --source-dir force-app --target-org governor-prod --test-level RunLocalTests`
3. If validation is green, **deploy for real** — quick-deploy the validated job:
   `sf project deploy quick --job-id <JOB_ID>` (Claude Code can run all of this for you).
4. Commit via GitHub Desktop with a clear message; push.

Only once a fix validates and deploys cleanly do we move to the next one. Tag v1.0 when the
whole checklist is done.

## Release checklist (v1.0 publish)

- [ ] Fixes #1–#3 applied, validated and deployed to the org, tests green
- [ ] JS wrapper in the repo (Fix #4), sampling sticky, URL confirmed
- [ ] Tests tightened; overall Apex coverage comfortably above the 75% minimum
- [ ] Real **README** written: what it is, prerequisites, step-by-step deploy
      instructions, how to configure a Governor record, how to embed the wrapper
- [ ] A **"Deploy to Salesforce" button** added to the README (optional but nice — lets
      people install straight from the repo)
- [ ] `LICENSE` file added (decide how others may use it)
- [ ] Confirm the repo matches the org exactly (retrieve once more, diff, commit)
- [ ] Tag the release `v1.0.0` in GitHub

## Open questions

- **Is the repo currently in sync with your org, or stale?** Determines whether we retrieve
  a fresh copy from the org before starting, so we're editing the true current version.
- **Overnight operating windows** — do any real use cases need them for v1.0, or can we
  document that as a known limitation?
- **Licensing** — how do you want others to be allowed to use this (permissive like MIT,
  or something more restrictive)?
