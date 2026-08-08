# Night Shift

[![Part of AgentStack](https://img.shields.io/badge/Part%20of-AgentStack-blue?style=flat-square)](https://github.com/FvdHMBAI/agent-stack)
[![CI](https://github.com/FvdHMBAI/nightshift/actions/workflows/ci.yml/badge.svg)](https://github.com/FvdHMBAI/nightshift/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![GitHub Stars](https://img.shields.io/github/stars/FvdHMBAI/nightshift?style=social)](https://github.com/FvdHMBAI/nightshift/stargazers)

**Your codebase improves while you sleep.**

Every morning I wake up to 3-5 PRs my AI created overnight. Each one a real fix -- lint errors, security patches, documentation gaps. All committed, tested, ready to merge.

No SaaS subscription. No data leaving my server. Just a cron job, a local LLM, and a codebase that gets cleaner every night without anyone touching it.

Night Shift scans your repositories overnight, finds lint errors, TypeScript issues, security vulnerabilities, and documentation gaps -- fixes them automatically, commits each fix to its own branch, and sends you a morning summary. Self-hosted, free, runs with your own LLM.

<p align="center">
  <img src="demo/demo.gif" alt="Night Shift Demo" width="700">
</p>

```
                         Night Shift Architecture

  +--------------------------------------------------------------------+
  |                        COORDINATOR (cron)                          |
  |  Runs nightly . checks RAM . creates run record . orchestrates     |
  +-----------.--------------------------------------.-----------------+
              |                                      |
              v                                      v
  +---------------------+              +---------------------------+
  |   SCANNER (per repo) |              |   WORKER POOL (parallel)  |
  |                      |              |                           |
  |  . ESLint errors     |   tasks      |  Worker 1: lint-fix       |
  |  . TypeScript issues |---------->   |  Worker 2: security       |
  |  . npm audit         |   (DB)       |  Worker 3: type-fix       |
  |  . Missing tests     |              |                           |
  |  . Thin docs         |              |  Each worker:             |
  +----------------------+              |  1. Create branch         |
                                        |  2. Apply fix             |
                                        |  3. Verify (tsc)          |
                                        |  4. Commit + push         |
                                        |  5. Rollback on failure   |
                                        +-----------+---------------+
                                                    |
              +-------------------------------------+
              v
  +---------------------+     +---------------------+
  |   LESSON GENERATOR   |     |    MORNING SUMMARY   |
  |  (optional, Pro)     |     |                      |
  |                      |     |  . ntfy notification  |
  |  Explains the WHY    |     |  . DB summary record  |
  |  behind each fix     |     |  . Run statistics     |
  +----------------------+     +----------------------+
```

---

## In Production

Night Shift is not a concept. It runs every night on a self-hosted Hetzner server alongside 225 cron jobs, scanning 5 repositories while the team sleeps.

It is part of the infrastructure behind 233 commits in 30 days -- automated maintenance that compounds. Lint fixes, dependency patches, security upgrades, documentation improvements. Each one small. Together, they keep the codebase from decaying.

The morning summary arrives via ntfy. Most fixes merge without discussion. The ones that need attention are flagged and waiting on their own branch.

---

## Why Night Shift?

| | Night Shift | Devin | CodeRabbit | Sweep (dead) |
|---|---|---|---|---|
| **Cost** | Free (self-hosted) | $500/mo | $15/mo+ | Shut down |
| **Your data** | Stays on your server | Sent to cloud | Sent to cloud | -- |
| **LLM choice** | Ollama / Claude / GPT | Proprietary | Proprietary | -- |
| **Approach** | Overnight batch fixes | Interactive agent | PR review only | Issue->PR |
| **What it fixes** | Lint, types, security, docs | Everything (slowly) | Nothing (reviews only) | Issues |
| **Safety** | Branch per fix, auto-rollback | Full repo access | Read-only | Full access |
| **Setup** | 5 minutes | Account + billing | GitHub app | -- |

**Night Shift is not trying to be Devin.** It handles the boring, repetitive maintenance that piles up -- the kind of work nobody wants to do but everybody benefits from. It runs when you're asleep, uses your own LLM, and every fix lands on its own branch for you to review.

## What it fixes

| Category | Detection | Fix method | Verification |
|----------|-----------|------------|--------------|
| **Lint** | `eslint --quiet` | `eslint --fix` | Re-lint |
| **Types** | `tsc --noEmit` | LLM-assisted patch | `tsc --noEmit` re-check |
| **Security** | `npm audit` (high/critical) | `npm audit fix` + individual upgrades | TypeScript + build check |
| **Docs** | README < 20 lines | LLM-generated expansion | Length check |
| **Deps** | `npm outdated` | `npm update` (minor/patch only) | TypeScript + Next.js build |

Every fix runs on its own branch (`nightshift/lint-fix-20260801-eslint-no-unused-vars`), so you always review before merging.

## Quick Start

### Prerequisites

- **Linux** with bash 4+, curl, jq, python3
- **PostgreSQL 13+** for task tracking
- **Ollama** (recommended) or Anthropic API key for LLM analysis
- **Node.js** repos with ESLint / TypeScript

### Install

```bash
git clone https://github.com/FvdHMBAI/nightshift.git
cd nightshift

# 1. Configure
cp config.sh config.local.sh   # keep your settings separate
vim config.local.sh             # add repos, DB connection, LLM

# 2. Install (creates tables, cron jobs, checks deps)
./install.sh

# 3. Test run
./coordinator.sh
```

### Configuration

Edit `config.sh` (or create `config.local.sh` that sources and overrides it):

```bash
# Repositories to scan (absolute paths)
REPOS=(
  "$HOME/projects/my-frontend"
  "$HOME/projects/my-api"
  "$HOME/projects/my-backend"
)

# Database
DB_MODE="postgres"                    # or "docker"
DB_URL="postgresql://user:pass@localhost:5432/nightshift"
# DB_CONTAINER="my-postgres"          # if mode=docker

# LLM -- Ollama is default (free, local)
OLLAMA_MODEL="qwen3:8b"              # any Ollama model
# ANTHROPIC_API_KEY="sk-ant-..."      # optional: better type/doc fixes

# Limits
MAX_TASKS=15                          # max tasks per run
MAX_WORKERS=3                         # parallel workers
MAX_TASK_DURATION=7200                # 2h timeout per task
MIN_FREE_RAM_MB=3072                  # abort if < 3GB free

# Notifications (ntfy.sh compatible)
# NTFY_URL="https://ntfy.sh/my-nightshift"
```

## How it works

```
22:00  Coordinator starts
       |-- Check RAM, create run record
       |-- For each repo:
       |   |-- git fetch origin develop
       |   |-- ESLint scan -> findings
       |   |-- TypeScript scan -> findings
       |   |-- npm audit -> findings
       |   |-- Test coverage check -> findings
       |   +-- README length check -> findings
       |
       |-- Classify findings -> tasks (low/medium/high risk)
       |
       |-- Run workers (up to 3 parallel):
       |   |-- Create nightshift/* branch
       |   |-- Apply fix
       |   |-- Verify (tsc --noEmit, build check)
       |   |-- If broken -> rollback, mark failed
       |   |-- If clean -> commit, push, mark completed
       |   +-- Generate lesson (optional)
       |
       +-- Generate summary -> DB + ntfy notification

06:00  Morning summary (catches any unfinished runs)
```

### Safety guarantees

1. **Branch isolation** -- every fix gets its own branch. Your main/develop is never touched.
2. **Backup tags** -- created before any changes, recoverable with `git tag -l 'nightshift-backup/*'`.
3. **Compilation verification** -- TypeScript check after every npm change. Breaks -> automatic rollback.
4. **Stash protection** -- uncommitted work is stashed before, restored after.
5. **RAM monitoring** -- stops spawning workers if memory drops below threshold.
6. **Task timeout** -- 2-hour default prevents runaway processes.
7. **Lockfile** -- prevents concurrent coordinator runs.
8. **Risk classification** -- high-risk tasks (security) are flagged, complex ones deferred to Claude.

## Database

Night Shift uses PostgreSQL to track every run, task, and generated lesson:

```sql
-- Recent runs
SELECT started_at, tasks_created, tasks_completed, tasks_failed, summary
FROM nightshift_runs ORDER BY started_at DESC LIMIT 5;

-- Failed tasks (what to investigate)
SELECT repo, category, title, error_message
FROM nightshift_tasks WHERE status = 'failed'
ORDER BY created_at DESC LIMIT 10;

-- Lessons generated
SELECT topic, concept_category, difficulty, created_at
FROM lessons ORDER BY created_at DESC LIMIT 10;
```

## Lesson Generator (Pro)

Every completed fix generates a learning lesson explaining the programming concept behind the change -- not just what was fixed, but why it matters. Stored in the database with topic, difficulty, code before/after, and exercises.

Works best with an Anthropic API key but falls back to Ollama.

## Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `NIGHTSHIFT_DB_URL` | `postgresql://...localhost:5432/nightshift` | PostgreSQL connection |
| `NIGHTSHIFT_DB_MODE` | `postgres` | `postgres` or `docker` |
| `NIGHTSHIFT_DB_CONTAINER` | -- | Docker container (if mode=docker) |
| `NIGHTSHIFT_DB_NAME` | `nightshift` | Database name (docker mode) |
| `NIGHTSHIFT_DB_USER` | `postgres` | Database user (docker mode) |
| `OLLAMA_URL` | `http://localhost:11434/api/generate` | Ollama endpoint |
| `OLLAMA_MODEL` | `qwen3:8b` | Local LLM model |
| `ANTHROPIC_API_KEY` | -- | Claude API (optional, Pro features) |
| `NIGHTSHIFT_CLAUDE_MODEL` | `claude-sonnet-4-6` | Claude model |
| `NIGHTSHIFT_NTFY_URL` | -- | ntfy.sh notification URL |
| `NIGHTSHIFT_LOG_DIR` | `/var/log/nightshift` | Log directory |
| `NIGHTSHIFT_LESSON_DIR` | `./lessons` | Lesson output directory |

## Extending Night Shift

Add custom task categories by:

1. Adding a scanner in `coordinator.sh` -> `scan_repo()` that outputs `repo|category|title|description`
2. Adding a handler in `worker.sh` -> `case "$category" in your-category) execute_your_fix && success=true ;;`
3. That's it. The coordinator/worker/summary pipeline handles the rest.

## FAQ

**Can it break my code?**
Every fix runs on its own branch. If TypeScript compilation fails after a fix, the change is rolled back automatically. Your working branches are never modified.

**Does it support monorepos?**
Yes. Add the monorepo root to `REPOS`. The scanner checks for ESLint, TypeScript, and npm audit at the configured paths.

**What LLMs does it support?**
Any Ollama model (local, free) or Anthropic Claude (cloud, paid). The TypeScript fixer and doc generator use the LLM; lint and security fixes are deterministic tools.

**How much does it cost to run?**
With Ollama: $0. With Claude API: typically $0.02-0.10 per run depending on findings. The system logs token usage per task.

**Can I run it manually?**
Yes: `./coordinator.sh` runs a full cycle. `./summary-morning.sh` generates/sends the summary.

## How It Compares

| | Night Shift | Renovate / Dependabot | CodeRabbit | Devin | Sweep (dead) |
|---|---|---|---|---|---|
| **Scope** | Lint + types + security + docs + deps | Dependencies only | Review only (no fixes) | Everything (interactive) | Issue-to-PR |
| **Runs when** | Overnight (cron) | On dependency update | On PR creation | On demand | On issue creation |
| **LLM choice** | Ollama (free) or Claude | None (rule-based) | Proprietary | Proprietary | Proprietary |
| **Self-hosted** | Yes | Partial (GitHub app) | No (SaaS) | No (cloud) | No |
| **Branch isolation** | Yes (one branch per fix) | Yes | N/A (no changes) | No (works in-place) | Yes |
| **Auto-rollback** | Yes (tsc fails = revert) | No | N/A | No | No |
| **Cost** | $0 (Ollama) / ~$0.05/run (Claude) | Free tier | $15/mo+ | $500/mo | Shut down |
| **Data stays local** | Yes | Partial | No | No | No |
| **Verification** | TypeScript + build check | CI pipeline | None | Manual review | CI pipeline |
| **Lesson generation** | Yes (Pro: explains WHY) | No | No | No | No |

**Different category.** Renovate and Dependabot handle one slice (dependency updates). CodeRabbit reviews but never fixes. Devin is a full interactive agent ($500/mo). Night Shift covers the boring maintenance layer between those tools: lint, types, security, docs. It runs unattended, on your hardware, with your LLM, and every fix is isolated on its own branch.

---

## Part of the Ecosystem

Night Shift does not run alone. It is one tool in a system of open-source agents that handle governance, routing, and autonomy for AI-driven development:

| Tool | What it does | Repository |
|------|-------------|------------|
| **GuardRail** | AI governance framework -- policy enforcement, compliance gates, audit trails | [github.com/FvdHMBAI/guardrail](https://github.com/FvdHMBAI/guardrail) |
| **Model Router** | Intelligent LLM routing -- cost optimization, fallback chains, token tracking | [github.com/FvdHMBAI/model-router](https://github.com/FvdHMBAI/model-router) |
| **Graphify Toolkit** | Codebase-to-knowledge-graph -- impact analysis, dependency mapping, cross-repo queries | [github.com/FvdHMBAI/graphify-toolkit](https://github.com/FvdHMBAI/graphify-toolkit) |
| **Autonomie-OS** | Agent autonomy framework -- self-directed task discovery, execution loops, escalation | [github.com/FvdHMBAI/autonomie-os](https://github.com/FvdHMBAI/autonomie-os) |

Together they form [AgentStack](https://github.com/FvdHMBAI/agent-stack) -- the infrastructure layer for running AI agents in production without giving up control.

## Part of AgentStack

This tool is free and always will be. For teams that need the full governance stack (GuardRail Pro + Compliance Shield + priority support), see [AgentStack Pro](https://github.com/FvdHMBAI/agent-stack/blob/main/BUNDLE.md) (EUR 79/dev/month).

---

## Built by

**Frederik von der Heyden** -- Solo-Founder building AI infrastructure for production use. Night Shift runs every night on his own server, fixing his own code. What you see here is what he uses.

Learn KI-Governance: [lernen.promptandbuild.de](https://lernen.promptandbuild.de)
Newsletter: [promptandbuild.de](https://promptandbuild.de)

## License

MIT -- see [LICENSE](LICENSE)

---

Built by [Prompt & Build](https://promptandbuild.de). Running 13+ SaaS products with AI agents.

<p align="center">
  If Night Shift saves you maintenance time, consider giving it a <a href="https://github.com/FvdHMBAI/nightshift">star</a>. It helps others find it.
</p>
