/**
 * Agent Governor — Client Wrapper
 * SCENARIO 2: FALLBACK (customer already has an existing bot)
 * ------------------------------------------------------------------
 * Behaviour:
 *   - GO  + sampled IN   -> show the NEW governed Agentforce agent
 *   - GO  + sampled OUT  -> show the EXISTING bot (control group / baseline)
 *   - STOP (quota/hours/kill switch) -> show the EXISTING bot (fall back)
 *   - API error / timeout (fail-safe) -> show the EXISTING bot
 *
 * Use this when the customer already runs a chat deployment and does
 * not want visitors left with no chat when the governed agent is held
 * back. The existing bot is the always-available safety net; the new
 * governed agent only appears for sampled-in traffic when the Governor
 * says GO. That also gives you a clean A/B: new agent vs existing bot.
 *
 * NOTE: If you would rather show NOTHING (not the existing bot) to the
 * sampled-out control group, call showNothing() instead of
 * initExistingBot() in the "sampled out" branch below.
 * ------------------------------------------------------------------
 */
(function () {
    'use strict';

    // ===== 1. CONFIGURATION (edit these two lines) =========================
    // Your Salesforce Site base URL, including the site's URL path prefix.
    // Example: 'https://mycompany.my.salesforce-sites.com/agentgovernor'
    var GOVERNOR_SITE_BASE = 'https://YOUR_SITE.my.salesforce-sites.com/agentgovernor';

    // The Governor_Key__c of the configuration record that governs this page.
    var GOVERNOR_KEY = 'pilot-v1';

    // How long to wait for the Governor API before falling back (milliseconds).
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

    var apiUrl = buildApiUrl(GOVERNOR_SITE_BASE, GOVERNOR_KEY);

    fetchStatus(apiUrl)
        .then(function (data) {
            if (data.status === 'GO') {
                var rate = (typeof data.samplingRate === 'number') ? data.samplingRate : 1;
                if (stickyRoll(GOVERNOR_KEY, rate)) {
                    console.log(LOG + ' GO — sampled in. Initialising governed agent.');
                    initAgentforceMIAW();
                } else {
                    console.log(LOG + ' GO — sampled out (control). Falling back to existing bot.');
                    initExistingBot();
                }
            } else {
                console.log(LOG + ' STOP (' + data.reason + '). Falling back to existing bot.');
                initExistingBot();
            }
        })
        .catch(function (error) {
            console.error(LOG + ' API unavailable:', error.message);
            console.log(LOG + ' Fail-safe engaged — falling back to existing bot.');
            initExistingBot();
        });

    // ----- 2. NEW GOVERNED AGENTFORCE (MIAW) SNIPPET ======================
    // Paste your NEW Agentforce / MIAW bootstrap here. Runs only on
    // GO + sampled in.
    function initAgentforceMIAW() {
        // e.g. embedded_svc.init(...) / the new MIAW <script> bootstrap.
        console.log(LOG + ' New governed MIAW snippet executed.');
    }

    // ----- 3. EXISTING BOT SNIPPET ========================================
    // Paste the customer's CURRENT chat/bot bootstrap here (the code snippet
    // they already use today). This is the fallback / baseline experience.
    function initExistingBot() {
        // e.g. the existing bot's init() / <script> bootstrap.
        console.log(LOG + ' Existing bot snippet executed.');
    }
    // =======================================================================
})();
