/**
 * Agent Governor — Client Wrapper
 * SCENARIO 1: GREENFIELD (no existing bot/agent)
 * ------------------------------------------------------------------
 * Behaviour:
 *   - GO  + sampled IN   -> show the governed Agentforce agent
 *   - GO  + sampled OUT  -> show NOTHING (control group)
 *   - STOP (quota/hours/kill switch) -> show NOTHING
 *   - API error / timeout (fail-safe) -> show NOTHING
 *
 * Use this when the customer has no existing chat deployment, so
 * "don't show the agent" simply means an empty page.
 *
 * The sampling decision is sticky for the browser session, so a
 * visitor sees a consistent experience as they navigate the site.
 * ------------------------------------------------------------------
 */
(function () {
    'use strict';

    // ===== 1. CONFIGURATION (edit these two lines) =========================
    // Your Salesforce Site base URL, including the site's URL path prefix.
    // Example: 'https://mycompany.my.salesforce-sites.com/agentgovernor'
    // Do NOT include '/services/apexrest/...' here — the code appends it.
    var GOVERNOR_SITE_BASE = 'https://YOUR_SITE.my.salesforce-sites.com/agentgovernor';

    // The Governor_Key__c of the configuration record that governs this page.
    var GOVERNOR_KEY = 'pilot-v1';

    // How long to wait for the Governor API before failing safe (milliseconds).
    var API_TIMEOUT_MS = 3000;
    // =======================================================================

    var LOG = '[Agent Governor]';

    // ----- Helpers ---------------------------------------------------------

    // Build a clean endpoint URL regardless of trailing slashes in the base.
    function buildApiUrl(base, key) {
        var trimmed = base.replace(/\/+$/, '');
        return trimmed + '/services/apexrest/AgentGovernor/?key=' + encodeURIComponent(key);
    }

    // fetch() with a hard timeout so a slow/hung Site fails safe promptly.
    function fetchStatus(url) {
        var controller = new AbortController();
        var timer = setTimeout(function () { controller.abort(); }, API_TIMEOUT_MS);
        return fetch(url, { method: 'GET', cache: 'no-store', signal: controller.signal })
            .then(function (response) {
                clearTimeout(timer);
                if (!response.ok) { throw new Error('Governor API returned ' + response.status); }
                return response.json();
            });
    }

    // Sticky per-session sampling: roll once, then remember for the visit.
    // Returns true if this visitor is sampled IN.
    function stickyRoll(key, rate) {
        var storageKey = 'agentGovernor:' + key;
        try {
            var cached = sessionStorage.getItem(storageKey);
            if (cached !== null) { return cached === 'in'; }
            var inSample = Math.random() < rate;
            sessionStorage.setItem(storageKey, inSample ? 'in' : 'out');
            return inSample;
        } catch (e) {
            // sessionStorage blocked (e.g. strict privacy mode) -> non-sticky fallback.
            return Math.random() < rate;
        }
    }

    // ----- Main flow -------------------------------------------------------

    var apiUrl = buildApiUrl(GOVERNOR_SITE_BASE, GOVERNOR_KEY);

    fetchStatus(apiUrl)
        .then(function (data) {
            if (data.status === 'GO') {
                var rate = (typeof data.samplingRate === 'number') ? data.samplingRate : 1;
                if (stickyRoll(GOVERNOR_KEY, rate)) {
                    console.log(LOG + ' GO — sampled in. Initialising agent.');
                    initAgentforceMIAW();
                } else {
                    console.log(LOG + ' GO — sampled out (control group). Showing nothing.');
                }
            } else {
                console.log(LOG + ' STOP (' + data.reason + '). Showing nothing.');
            }
        })
        .catch(function (error) {
            console.error(LOG + ' API unavailable:', error.message);
            console.log(LOG + ' Fail-safe engaged — showing nothing.');
        });

    // ----- 2. YOUR AGENTFORCE (MIAW) SNIPPET ==============================
    // Paste your standard Agentforce / Messaging for In-App and Web bootstrap
    // code inside this function. It only runs when the Governor says GO and
    // this visitor is sampled in.
    function initAgentforceMIAW() {
        // e.g. embedded_svc.init(...) / the MIAW <script> bootstrap goes here.
        console.log(LOG + ' MIAW snippet executed.');
    }
    // =======================================================================
})();
