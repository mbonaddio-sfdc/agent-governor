# Agent Governor — Local Setup Guide

_Last updated: 2026-07-30. Written for a non-developer on macOS._

This guide gets your machine set up to manage Agent Governor with **Claude Code** driving
the **Salesforce CLI** — no VS Code required. You do this once. After that, you work by
telling Claude Code what you want in plain English.

> **Note on the folder layout.** This repo has the Salesforce project nested one level
> down. The important marker is the file **`sfdx-project.json`**. In this repo it lives in:
> `agent-governor/agent-governor/`. **All Salesforce CLI (`sf`) commands must be run from
> the folder that contains `sfdx-project.json`** — otherwise the CLI won't recognise it as
> a project. When in doubt, `cd` into that folder first.

---

## What you're installing (and why)

1. **Node.js** — a small runtime that both tools below rely on. Install it once.
2. **Salesforce CLI (`sf`)** — the engine that actually talks to your Salesforce org
   (retrieves code, deploys, runs tests). Claude Code drives this for you.
3. **Claude Code** — the AI agent that runs in your terminal, edits files, and runs the
   `sf` commands on your behalf.

GitHub Desktop (which you already have) handles committing and pushing to GitHub.

---

## Step 1 — Install Node.js

Go to <https://nodejs.org/en/download/> and install the **LTS** ("Long-Term Support")
version for macOS. Accept the defaults.

Then open the **Terminal** app (Applications → Utilities → Terminal) and confirm it worked:

```bash
node --version
```

You should see a version number (e.g. `v20.x` or higher). If you do, Node is installed.

---

## Step 2 — Install the Salesforce CLI

You have two options. The **npm** method is simplest since you just installed Node.

**Option A — npm (recommended here):**

```bash
npm install @salesforce/cli --global
```

**Option B — Mac installer package:** download the `.pkg` from
<https://developer.salesforce.com/tools/salesforcecli> (Apple Silicon Macs get
`sf-arm64.pkg`) and double-click to run it.

Confirm it installed:

```bash
sf version
```

You should see a version string. (If npm gives a permission error, do **not** use `sudo` —
see <https://docs.npmjs.com/getting-started/fixing-npm-permissions>.)

To update the CLI later: `sf update stable`.

---

## Step 3 — Install Claude Code

The npm method (you already have Node):

```bash
npm install -g @anthropic-ai/claude-code
```

Confirm it installed:

```bash
claude --version
```

> **Please verify the exact install command against the official docs**, since install
> methods change over time and I couldn't fetch the live page while writing this:
> <https://docs.claude.com/en/docs/claude-code>. There may also be a one-line native
> installer listed there that doesn't need Node — either is fine.

---

## Step 4 — Connect your Salesforce org

This is a one-time login that lets the CLI act on your org. Run it from the project folder:

```bash
cd "/Users/mbonaddio/Documents/Projects/agent-governor/agent-governor"
sf org login web --alias governor-prod
```

A browser window opens — log in to your Salesforce org as normal and approve access. The
`--alias governor-prod` just gives this connection a friendly name.

Check your connections:

```bash
sf org list
```

> **Working directly in a prod/demo org.** We don't use a sandbox or scratch org here — the
> Agentforce/MIAW licensing needed to actually exercise this solution isn't available in
> Developer Edition or scratch orgs. That's a deliberate choice. To stay safe, we **always
> validate before we deploy** (next section), we let git be our undo button (commit before
> and after every change), and we keep data-model changes additive (never delete a field
> until the replacement is proven).

---

## Step 5 — Start Claude Code in the project

```bash
cd "/Users/mbonaddio/Documents/Projects/agent-governor"
claude
```

On first launch it will guide you through signing in (with your Claude account or an API
key). After that, you just type what you want. For example:

> "Deploy the contentassets folder and the Agent_Governor application to governor-prod,
> then show me what changed."

---

## Your first three jobs (say these to Claude Code)

These are the immediate items we identified. You can paste them almost verbatim.

1. **Deploy the renamed app logo.**
   The logo ContentAsset now lives in the repo as `Agent_Governor_Logo` (it was renamed
   from the old `MB_`-prefixed name). Deploy it so the org matches:
   > "Deploy `force-app/main/default/contentassets` and
   > `force-app/main/default/applications/Agent_Governor.app-meta.xml` to governor-prod,
   > then delete the old `ContentAsset:MB_Agent_Ramp_for_Agentforce` from the org."

2. **Confirm the repo is in sync with the org.**
   > "Retrieve everything in `manifest/package.xml` from governor-prod and tell me if
   > anything changed compared to what's already in the repo."

   Then open **GitHub Desktop** — an empty Changes tab means you were in sync; if files
   appear, review and commit them.

3. **Then we start the hardening.** Come back here (this chat) and we'll work through
   `HARDENING_PLAN.md` — starting with Fix #1, the daily-reset deadlock.

---

## Handy commands (for reference — you can also just ask Claude Code)

Run these from the folder containing `sfdx-project.json`:

```bash
# See what's different between org and repo
sf project retrieve start --manifest manifest/package.xml --target-org governor-prod

# VALIDATE ONLY — compiles and runs tests, commits NOTHING to the org
sf project deploy validate --source-dir force-app --target-org governor-prod --test-level RunLocalTests

# If validation passed, deploy the already-validated job for real (use the Job ID it printed)
sf project deploy quick --job-id <JOB_ID_FROM_VALIDATE> --target-org governor-prod

# Run all Apex tests directly
sf apex run test --target-org governor-prod --wait 10 --result-format human
```

---

## How the two AIs fit together

- **This chat (Cowork)** = planning, reviewing, drafting code and docs. Can read the repo,
  can't reach your org.
- **Claude Code** = does the org work (retrieve / deploy / test) and can edit files too.
- They don't share memory. The **repo is the shared handoff** — that's why the plan lives
  in `HARDENING_PLAN.md`. Avoid editing the same file in both at the exact same moment.
