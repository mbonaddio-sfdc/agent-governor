/**
 * Agent Governor — Client Wrapper
 * SCENARIO 3: HIGH VOLUME (conserve API requests)
 * ------------------------------------------------------------------
 * The problem: on a very high-traffic site, calling the Governor API on
 * every single page load burns a Salesforce API request every time —
 * even for the ~95% of visitors who will never be shown the agent.
 *
 * The fix: sample FIRST, in the browser, using a hard-coded rate. Only
 * the small sampled-in slice ever calls the API (to check limits, hours
 * and the kill switch). Everyone else is decided for free, client-side.
 *
 * Behaviour:
 *   - sampled OUT (the majority) -> show NOTHING, no API call
 *   - sampled IN -> call API:
 *         GO   -> show the governed Agentforce agent
 *         STOP -> show NOTHING
 *         error/timeout (fail-safe) -> show NOTHING
 *
 * IMPORTANT — avoid double sampling:
 *   The browser rate below is the ONLY sampler. Set the Sampling Rate on
 *   this configuration record in Salesforce to 100% so the server does
 *   not sample again on top of it. This wrapper deliberately ignores the
 *   server's samplingRate. Trade-off: to change the rate you edit this
 *   file on the website, not a Salesforce field.
 * ------------------------------------------------------------------
 */
(function () {
    'use strict';

    // ===== 1. CONFIGURATION (edit these) ===================================
    // Hard-coded sampling rate, 0.0–1.0. e.g. 0.05 = 5% of visitors.
    var SAMPLING_RATE = 0.05;

    // Your Salesforce Site base URL, including the site's URL path prefix.
    // Example: 'https://mycompany.my.salesforce-sites.com/agentgovernor'
    var GOVERNOR_SITE_BASE = 'https://YOUR_SITE.my.salesforce-sites.com/agentgovernor';

    // The Governor_Key__c of the configuration record that governs this page.
    // (Set that record's Sampling Rate to 100% — see note above.)
    var GOVERNOR_KEY = 'pilot-v1';

    // How long to wait for the Governor API before failing safe (milliseconds).
    var API_TIMEOUT_MS = 3000;
    // =======================================================================

    var LOG = '[Agent Governor]';

    // ----- Helpers ---------------------------------------------------------

    function buildApiUrl(base, key) {
        var trimmed = base.replace(/\/+$/, '');
        return trimmed + '/services/apexrest/AgentGovernor/?key=' + encodeURIComponent(key);
    }

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
    function stickyRoll(key, rate) {
        var storageKey = 'agentGovernor:' + key;
        try {
            var cached = sessionStorage.getItem(storageKey);
            if (cached !== null) { return cached === 'in'; }
            var inSample = Math.random() < rate;
            sessionStorage.setItem(storageKey, inSample ? 'in' : 'out');
            return inSample;
        } catch (e) {
            return Math.random() < rate;
        }
    }

    // ----- Main flow -------------------------------------------------------

    // Step 1: sample in the browser FIRST. No API call for sampled-out visitors.
    if (!stickyRoll(GOVERNOR_KEY, SAMPLING_RATE)) {
        console.log(LOG + ' Sampled out (' + Math.round(SAMPLING_RATE * 100) + '% rate). No API call, showing nothing.');
        return;
    }

    // Step 2: only sampled-in visitors reach here and call the API to check
    // limits / operating hours / kill switch. The server's samplingRate is
    // intentionally ignored (see the double-sampling note at the top).
    console.log(LOG + ' Sampled in. Checking Governor for limits/hours...');

    var apiUrl = buildApiUrl(GOVERNOR_SITE_BASE, GOVERNOR_KEY);

    fetchStatus(apiUrl)
        .then(function (data) {
            if (data.status === 'GO') {
                console.log(LOG + ' GO. Initialising agent.');
                initAgentforceMIAW();
            } else {
                console.log(LOG + ' STOP (' + data.reason + '). Showing nothing.');
            }
        })
        .catch(function (error) {
            console.error(LOG + ' API unavailable:', error.message);
            console.log(LOG + ' Fail-safe engaged — showing nothing.');
        });

    // ----- 2. YOUR AGENTFORCE (MIAW) SNIPPET ==============================
    // Paste your Agentforce / MIAW bootstrap here. Runs only when sampled in
    // AND the Governor returns GO.
    function initAgentforceMIAW() {
        // e.g. embedded_svc.init(...) / the MIAW <script> bootstrap goes here.
        console.log(LOG + ' MIAW snippet executed.');
    }
    // =======================================================================
})();
