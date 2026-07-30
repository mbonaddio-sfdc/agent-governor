# Agent Governor — Client Wrapper

These are the small JavaScript snippets that go on your **website** (not in Salesforce).
Each one calls the Agent Governor API on your Salesforce Site, then decides whether to
show your Agentforce (Messaging for In-App and Web) agent to the current visitor.

There are three versions. **Pick one** based on how you want to deploy, copy it onto your
site, and edit the two config lines at the top.

| File | Use it when… | What happens when the agent is held back |
|------|--------------|------------------------------------------|
| `agent-governor-1-greenfield.js` | You have **no existing** chat/bot. | Nothing is shown. |
| `agent-governor-2-fallback.js` | You **already run** a bot and don't want visitors left with no chat. | Your **existing bot** is shown instead. |
| `agent-governor-3-high-volume.js` | You have **very high traffic** and want to minimise Salesforce API calls. | Nothing is shown — and most visitors never call the API at all. |

## How to use

1. Copy the relevant file's contents into a `<script>` tag on your page (or host the file
   and reference it with `<script src="…"></script>`).
2. Edit the configuration block at the top:
   - `GOVERNOR_SITE_BASE` — your Salesforce Site base URL **including the site's URL path
     prefix**, e.g. `https://mycompany.my.salesforce-sites.com/agentgovernor`. Do **not**
     add `/services/apexrest/…` — the script appends that for you. Confirm the exact
     address in Setup → Sites; older orgs use `.force.com`, newer ones
     `.my.salesforce-sites.com`.
   - `GOVERNOR_KEY` — the `Governor_Key__c` of the configuration record that governs this
     page (e.g. `pilot-v1`).
3. Paste your Agentforce / MIAW bootstrap code into the clearly-marked
   `initAgentforceMIAW()` function. In Scenario 2, also paste your **existing** bot's
   snippet into `initExistingBot()`.

## How the decision works

The Governor API returns `{ status, reason, samplingRate }`:

- `status` is `"GO"` or `"STOP"`. `STOP` reasons include `INACTIVE` (kill switch / not
  found), `QUOTA` (today's daily limit reached), `TIME` (outside operating hours) and
  `WEEKEND`.
- `samplingRate` is a decimal from 0 to 1 (e.g. `0.5` = 50%) and is only present on `GO`.

**Sampling is sticky per browser session.** The first time a visitor is rolled, the
result (in or out) is stored in `sessionStorage` and reused for the rest of their visit,
so the widget doesn't flicker on and off as they move between pages. A new visit re-rolls.
If `sessionStorage` is unavailable (strict privacy modes), it safely falls back to a
per-load roll.

**Fail-safe.** Every version has a hard request timeout (default 3 seconds). If the API is
slow, unreachable, or errors, the wrapper fails safe — Scenarios 1 and 3 show nothing;
Scenario 2 falls back to the existing bot.

## Scenario 1 vs 2 — what the control group sees

Both call the API on every page load and let Salesforce control the sampling rate centrally
(change it on the config record, no website edit needed).

- **Scenario 1 (greenfield):** sampled-out visitors see nothing.
- **Scenario 2 (fallback):** sampled-out visitors see the **existing bot**, giving you a
  clean A/B — new governed agent vs current bot — with the existing bot as an
  always-available safety net whenever the governed agent is held back. If you'd rather show
  nothing to the control group, swap the `initExistingBot()` call in the sampled-out branch
  for a no-op (there's a note in the file).

## Scenario 3 — the high-volume trade-off

Scenario 3 flips the order to save API calls: it **samples first in the browser** using a
hard-coded rate (`SAMPLING_RATE`, e.g. `0.05` for 5%), and only the sampled-in slice calls
the API — to check limits, operating hours and the kill switch. The other ~95% are decided
for free, client-side, with no API request.

Because the browser is now the sampler, **set that config record's Sampling Rate to 100% in
Salesforce** so the server doesn't sample again on top of the browser roll (otherwise your
real exposure would be `browser rate × server rate`). This wrapper deliberately ignores the
server's `samplingRate` for that reason.

Trade-off you're accepting: the sampling rate now lives in this website file, so changing it
means editing the site rather than a Salesforce field. Limits, hours and the kill switch are
still controlled centrally in Salesforce.
