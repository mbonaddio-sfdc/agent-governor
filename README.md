![Public Sector Accelerators logo](docs/Logo_GPSAccelerators_v01.png)

# Agent Governor

Agent Governor is a lightweight safety and throttling layer that sits between a customer's
public website and an Agentforce (Messaging for In-App and Web) deployment. It decouples
*deployment* from *exposure* so you can launch a new agent to a tiny, controlled slice of
traffic, review the transcripts, tune, and ramp up — instead of stalling on go-live for
fear of the blast radius. It gives non-technical owners four simple levers — impression
sampling, a daily conversation limit, operating hours, and a master on/off switch — all
managed from a single Salesforce record, with a fail-safe that hides the agent if anything
is unavailable.

Accelerator Listing: [insert URL to the public listing on the Accelerator site](https://gpsaccelerators.developer.salesforce.com/) `[TBD — once published]`


## Description

Many organisations complete an Agentforce build but then hesitate to switch it on for the
public, because a live conversational agent feels all-or-nothing. Agent Governor solves this
"sandbox trap" by putting a small, configurable gate in front of the agent.

When a visitor loads a page, a small JavaScript wrapper calls an unauthenticated Salesforce
Sites endpoint (running as a guest user). That endpoint reads the matching
`Agent_Governor_Configuration__c` record and evaluates four controls:

* **Impression sampling** — only a set percentage of visitors are eligible to see the agent.
* **Daily conversation limit** — a hard cap on conversations per calendar day, reset
  automatically at the start of the next day in the configured time zone.
* **Operating hours** — time-of-day and weekend windows, evaluated in an IANA time zone.
* **Master switch** — a single checkbox to turn the agent on or off instantly.

The endpoint returns `GO` or `STOP` (with a reason). On `GO`, the wrapper performs a final,
session-sticky sampling roll in the browser and then boots the standard Agentforce/MIAW
snippet. If the endpoint is unreachable or errors, the wrapper **fails safe** and does not
show the agent. As sessions start, a trigger increments the daily counter so the limit is
enforced automatically.

The whole solution is native Salesforce metadata plus a small client-side script — there is
no middleware to host.

In practice, Agent Governor lets you:

* **Launch small** — show the agent to as little as 1% of live traffic with impression
  sampling, keeping the "blast radius" mathematically contained.
* **Observe and refine** — cap interactions with a daily limit so your team gets a
  manageable, focused batch of real transcripts to review before widening the audience.
* **Scale safely** — restrict the agent to operating hours when human experts are online to
  handle escalations.
* **Stay in control** — flip the master switch in Salesforce to pull the agent offline
  instantly, with no website redeploy.

> Screenshots and an architecture diagram will be added to the [/docs/](/docs/) folder. `[TBD]`


## Scope and limitations (please read)

Agent Governor is a **rollout-control** tool, not a security or compliance control. Being
clear about what it does *not* do is what makes it safe to rely on for what it *does* do.

* **Exposure is not a security boundary.** The Governor decides whether your *website chooses
  to show* the agent — it does not restrict who can reach the underlying Agentforce/MIAW
  endpoint. The sampling roll, operating-hours check and daily cap all run in the visitor's
  browser (or a guest endpoint the browser calls), so a technically-minded visitor who
  inspects the page can start a conversation with your already-deployed MIAW channel
  directly, regardless of the Governor's decision. Treat the Governor as a way to control the
  *volume and timing of normal traffic*, and secure the agent itself with MIAW's own
  pre-chat, authentication, and channel settings.

* **CORS is not a control.** The CORS allowlist (setup Step 3) only tells *browsers* which
  origins may read the endpoint's response; it is a convenience for legitimate first-party
  pages, not a gate. It does not authenticate callers and is trivially bypassed by any
  non-browser client. Do not rely on CORS to keep anyone out — the endpoint is deliberately
  public and returns only a `GO`/`STOP` decision, never record data.

* **The daily limit is a soft ceiling, not a hard gate.** The counter is incremented
  *asynchronously* after each conversation starts (a trigger enqueues an `@future` job), and
  the `GO`/`STOP` read happens before that write settles. Under a burst of near-simultaneous
  sessions, several can be admitted in the window before the flag flips, so actual
  conversations for the day can slightly **overshoot** the configured limit. Size the limit
  as a budget with headroom, not as a precise cutoff.

* **Fail-safe, not fail-secure.** If the endpoint is slow or unreachable the wrapper hides the
  agent (or falls back to your existing bot). This protects the visitor experience; it is not
  a guarantee about the agent's own availability.


## Key Assets

This Accelerator includes the following assets:

* An **unmanaged package** (link below; metadata is also found in the
  [/force-app/main/default/](/force-app/main/default/) folder) that includes:
    * **Apex** — `AgentGovernorAPI` (the public REST endpoint) and `GovernorEngine` (the
      rules engine and daily-reset logic), an `AgentGovernorTrigger` on `MessagingSession`
      that increments the daily counter, plus three Apex test classes.
    * **Custom object** — `Agent_Governor_Configuration__c` (12 fields; see the data
      dictionary below).
    * **App & UI metadata** — an *Agent Governor* Lightning app, a custom tab, two
      FlexiPages, a page layout, a permission set, and a branding image (ContentAsset).
* **Client-side wrapper scripts** — three ready-to-use deployment variants (greenfield,
  fallback-to-existing-bot, and high-volume) with a setup guide, in the
  [/client/](/client/) folder.
* **Documentation**, including:
    * This readme file.
    * A [data dictionary](/docs/DATA_DICTIONARY.md) for the configuration object.
    * A white paper with detailed setup guidance (to be added to [/docs/](/docs/)). `[TBD]`

Unmanaged package install link: `[TBD — add package URL once created]`


## Before You Install

**License Requirements** `[Required — confirm exact SKUs for your org]`
* An **Agentforce Agent** (or Einstein Bot) with **Messaging for In-App and Web (MIAW)**
  configured — a deployed messaging channel/embedded service. Agent Governor controls the
  *traffic* to the agent; it does not build the underlying bot. For the *fallback* wrapper
  variant, you also need an existing chat/bot deployment on the site.
* A **Salesforce Site** so the Apex REST endpoint can be exposed to a guest user.
* **Optional: Experience Cloud** — only if you deploy the agent to a community/portal rather
  than an external corporate website.

**Accelerator or Technology-Specific Assumptions**
* You have already built and activated an Agentforce/MIAW deployment ready to govern, and you
  know its messaging channel ID.
* You have identified your **target web property** (an Experience Cloud site or an external
  website such as `www.yourcompany.com.au`) and can add or edit its page `<head>` markup.
* You are able to configure a Salesforce Site and grant its guest user access to the
  `AgentGovernorAPI` Apex class.

**General Assumptions**
* **Validate in a sandbox, then run the pilot in production.** As with any Accelerator, install
  and test it in a sandbox or scratch org first — confirm the deploy, the guest endpoint and
  the wrapper all behave before you touch production. That said, Agent Governor is *designed*
  to end up in production: its entire purpose is to expose a live agent to a small, controlled
  slice of **real** traffic. So unlike a typical Accelerator that stays in a test org, the
  intended path is sandbox-validated → deployed to production → run governed at a low sampling
  rate, then ramped. Do the go-live in production deliberately (start with **Is Active** off,
  a low **Sampling Rate**, and a modest **Daily Limit**), not as an experiment in a sandbox
  that never sees live visitors.
* If you do not have a Salesforce org licensed to you, try one of our industry solutions for
  free with one of our [trial environments](https://gpsaccelerators.developer.salesforce.com/trials).
* You are using this Accelerator with Salesforce Lightning Experience (LEX), not Classic.


## Installation

You can install Agent Governor either from the unmanaged package or directly from source.

> **Installation prerequisite — enable Messaging first.** Agent Governor includes
> `AgentGovernorTrigger`, a trigger on the **`MessagingSession`** object. That object only
> exists once **Messaging for In-App and Web (MIAW)** is enabled in the target org. If
> Messaging is not enabled, the install (or source deploy) will **fail** on that component
> with a "no such entity `MessagingSession`" error. Enable Agentforce / MIAW in the target
> org *before* you install.

### Option A — Unmanaged package (recommended)

1. Log in to your target org (sandbox or test environment recommended).
2. Open the package install URL: `[TBD — add package URL once created]`
3. Choose **Install for Admins Only** (you can broaden access later via the permission set).
4. Approve the third-party access prompt if shown, and wait for the install to complete.

> **Note — an unmanaged package cannot be upgraded.** Installing an unmanaged package places a
> one-time copy of the metadata into the target org, which that org then owns outright. There
> is no upgrade path: fixes and new versions **cannot be pushed** to orgs that already
> installed it. To adopt a later release, an installer re-deploys from source (Option B) or
> installs a freshly uploaded package. This is an accepted trade-off for an accelerator (the
> code is meant to be adapted, not centrally maintained), but it's worth understanding before
> you standardise on the package link.

### Option B — Deploy from source (Salesforce CLI)

Requires [Salesforce CLI](https://developer.salesforce.com/tools/salesforcecli) and a
cloned copy of this repository.

```bash
# Authorise your org (opens a browser)
sf org login web --alias my-org

# Deploy the metadata and run the local tests
sf project deploy start --source-dir force-app --target-org my-org --test-level RunLocalTests
```

A one-click **Deploy to Salesforce** button will be added here once the repository is
published: `[TBD]`


## Post-Install Setup & Configuration

Once the package (or source) is deployed, complete these steps in order to activate the
Governor.

### Step 1 — Assign access

Agent Governor ships with a permission set named **Agent Governor**. Assign it to the users
who will manage the Governor, via **Setup → Permission Sets → Agent Governor → Manage
Assignments → Add Assignments**.

The permission set grants:

* Visibility of the **Agent Governor** app and the **Agent Governor Configurations** tab.
* **Read / Create / Edit / Delete** on the `Agent_Governor_Configuration__c` object and
  **Read / Edit** on all twelve of its fields, so admins can create and tune configuration
  records.
* Apex class access to `AgentGovernorAPI` and `GovernorEngine`.

It deliberately does *not* include *View All* or *Modify All*, so assigned admins see
configuration records under your org's normal sharing model.

> Assign this permission set to **admins only**. The Site guest user does **not** need it —
> it only needs the Apex class enabled, which you do directly on the guest profile in Step 2.
> (Assigning this full set to a guest user would over-grant object create/edit/delete access.)

#### For release-team operators — use the scoped set instead

If **business users on your release team** need to tune the live controls (flip the kill
switch, adjust the sampling rate or daily limit, change the active window) but should **not**
have admin-level rights, assign them the separate **Agent Governor - Release Team** permission
set rather than the full **Agent Governor** set above. It is least-privilege by design:

* **Read + Edit** on the operator controls only: `Is_Active__c`, `Sampling_Rate__c`,
  `Daily_Limit__c`, `Start_Hour__c`, `End_Hour__c`, `Time_Zone__c`, `Exclude_Weekends__c`.
* **Read-only** on the system-managed fields (`Current_Count__c`, `Is_Green__c`,
  `Reset_Date__c`) so operators can see the live throttle state but cannot edit it and
  accidentally desync the counter or green/red state.
* Object **Read + Edit** but **no Create and no Delete** — operators tune existing
  configuration records, they don't stand up or remove them.
* **No Apex class access** — operators work through the UI, not the engine classes.

Keep the full **Agent Governor** set for admins who deploy, create records, and manage the
Apex classes; give release-team operators the **Agent Governor - Release Team** set.

### Step 2 — Create the public API endpoint (Salesforce Sites)

Because the wrapper runs on a public web page, the visitor's browser has no Salesforce login.
A Salesforce Site acts as a secure, unauthenticated gateway that evaluates the traffic rules
as a guest user. We recommend a **dedicated** Site used only for Agent Governor — it keeps
security isolated and lets you cleanly decommission later without touching other web
infrastructure.

1. Go to **Setup → Sites** and create a new site (e.g. named `Agent Governor API`).
2. Set the Active Site Home Page to any default page (e.g. `UnderConstruction`) and save.
3. Click **Public Access Settings** to open the Site's Guest User profile.
4. Under **Enabled Apex Class Access**, add `AgentGovernorAPI`. This is the only guest grant
   the endpoint requires.
5. Note the Site's base URL — you'll need it for the wrapper.

> **You do not need to grant the guest user Read access to the `Agent_Governor_Configuration__c`
> object or its fields.** `AgentGovernorAPI` and `GovernorEngine` are declared `without sharing`
> and use system-mode SOQL, so they read the configuration regardless of the guest user's
> object, field, or record permissions — and the endpoint only ever returns a `GO`/`STOP`
> decision (never raw record data) to the browser. If you later harden the Apex to run its
> queries in user mode (`WITH USER_MODE` / `WITH SECURITY_ENFORCED`), you **must** then grant
> the guest user Read on the object and its fields, or the query will throw.

### Step 3 — Configure CORS (external websites only)

If the agent lives on an external website (not an Experience Cloud site), the browser's call
to Salesforce is blocked by cross-origin security until you allow the origin.

1. Go to **Setup → CORS** and click **New**.
2. Add your website's exact origin (e.g. `https://www.yourcompany.com.au`) to the Allowed
   Origins list.

### Step 4 — Create a Governor configuration record

Open the *Agent Governor* app → **Agent Governor Configurations** tab → **New**, then set:

* **Governor Key** — a unique string (e.g. `pilot-v1`); you'll reference it in the wrapper.
* **Linked Channel ID** — the 18-character record ID of the MIAW `MessagingChannel` your
  agent uses (it typically starts with `0Mj`). To find it, open the channel under **Setup →
  Messaging Settings** and look in the page URL for the `0Mj…` fragment (it may be
  URL-encoded, e.g. `recordId=0Mj…` or `address=%2F0Mj…`) — copy the full 18 characters.
  If you can't spot it there, run `SELECT Id, MasterLabel, DeveloperName FROM MessagingChannel`
  in the Developer Console (or **Setup → Query Editor**) and copy the `Id` for your channel.
  **Make sure it starts with `0Mj` (the messaging channel), not `0ej`** — the latter is the
  Embedded Service **deployment** ID from the web snippet, which is easy to grab by mistake.
* **The guardrails** — **Sampling Rate** (e.g. 5%), **Daily Limit** (e.g. 50), **Start/End
  Hour** with a **Time Zone**, and **Exclude Weekends** as needed.
* **Is Active** — check this when you're ready to go live. This is the master on/off switch.

> Leave the system-managed fields (**Is Green**, **Current Count**, **Reset Date**) alone —
> the engine sets them automatically. In particular, **Is Green is not a manual kill switch**:
> it is the system quota flag and resets daily on its own. To turn the agent off manually, use
> **Is Active**. See the [data dictionary](/docs/DATA_DICTIONARY.md) for every field.

### Step 5 — Add the wrapper to your website

From the [/client/](/client/) folder, choose the variant that matches your scenario
(greenfield, fallback-to-existing-bot, or high-volume). Set `GOVERNOR_SITE_BASE` to your
Site's base URL (from Step 2) and `GOVERNOR_KEY` to the key from Step 4, paste your standard
Agentforce/MIAW snippet into the marked `initAgentforceMIAW()` function, then place the script
in the `<head>` of your website (or the **Head Markup** of your Experience Cloud builder). The
[client README](/client/README.md) explains each variant.

> Screenshots for these steps will be added to the [/docs/](/docs/) folder. `[TBD]`


## Decommissioning (tear-down)

Agent Governor is designed to be a temporary bridge. Once your pilot is complete and you're
ready for a full, ungoverned rollout, you can remove it cleanly:

1. Remove the wrapper script from your website and replace it with your standard, ungoverned
   MIAW snippet.
2. In **Setup → Sites**, deactivate the *Agent Governor API* site.
3. Uninstall the Agent Governor package (or delete the deployed metadata).

This leaves your agent running at full scale with no residual configuration or technical debt.


## FAQs

**_Q: The agent isn't showing up — is it broken?_**

A: Usually not. The wrapper deliberately hides the agent when a control says so. Open the
browser console: it logs the reason (`NOTFOUND`, `INACTIVE`, `QUOTA`, `TIME`, `WEEKEND`, or
"sampled out"). `NOTFOUND` means no configuration record matched the **Governor Key** in your
wrapper — check the key is spelled exactly as on the record (distinct from `INACTIVE`, which
means the record exists but **Is Active** is unchecked). Otherwise confirm the daily limit
isn't reached and you're within operating hours.

**_Q: Does the widget flicker on and off as a visitor browses?_**

A: No. The sampling decision is sticky for the browser session, so a visitor gets a
consistent experience across page views.

**_Q: What happens if the Salesforce endpoint is slow or down?_**

A: The wrapper has a short request timeout and fails safe — the greenfield and high-volume
variants show nothing, and the fallback variant reverts to your existing bot.

**_Q: On a very high-traffic site, does every page load call Salesforce?_**

A: Not with the high-volume variant. It samples in the browser first using a hard-coded
rate, and only the sampled-in slice calls the API — conserving API requests.

**_Q: Do I have to create a dedicated Salesforce Site for the API?_**

A: It's recommended for clean security isolation and easy decommissioning, but not strictly
required. If your organisation already uses Experience Cloud, you can expose the
`AgentGovernorAPI` class via your existing Experience Cloud guest user profile instead.

**_Q: It works on our Experience Cloud site but not on our external website. Why?_**

A: External origins are blocked by cross-origin security until you allowlist them. Add your
website's exact origin under **Setup → CORS** (see Step 3 of the setup).


## Additional Resources

* [Agentforce](https://www.salesforce.com/agentforce/)
* [Messaging for In-App and Web](https://help.salesforce.com/s/articleView?id=sf.miaw_intro.htm)
* [Salesforce Sites](https://help.salesforce.com/s/articleView?id=sf.sites_overview.htm)
* [Apex REST](https://developer.salesforce.com/docs/atlas.en-us.apexcode.meta/apexcode/apex_rest_intro.htm)
* [Salesforce CLI](https://developer.salesforce.com/tools/salesforcecli)


## Revision History

**1.0 Initial release (`[TBD date]`)** — First public release of Agent Governor:
impression sampling, daily conversation limits, operating hours, and a master switch, with
three client-side wrapper variants and a fail-safe design.


## Acknowledgements

* `[Your name]` — [`[TBD GitHub profile]`](https://github.com/)


## Terms of Use

Thank you for using Global Public Sector (GPS) Accelerators. Accelerators are provided by
Salesforce.com, Inc., located at 1 Market Street, San Francisco, CA 94105, United States.

By using this site and these accelerators, you are agreeing to these terms. Please read them
carefully.

Accelerators are not supported by Salesforce, they are supplied as-is, and are meant to be a
starting point for your organization. Salesforce is not liable for the use of accelerators.

For more about the Accelerator program, visit: [https://gpsaccelerators.developer.salesforce.com/](https://gpsaccelerators.developer.salesforce.com/)
