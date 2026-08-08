<h1 align="center">Night Shift</h1>

<p align="center">
  <a href="https://github.com/FvdHMBAI/agent-stack"><img src="https://img.shields.io/badge/Part%20of-AgentStack-blue?style=flat-square" alt="Part of AgentStack"></a>
</p>

<p align="center">
  <strong>Your codebase improves while you sleep.</strong>
</p>

<p align="center">
  <a href="https://github.com/FvdHMBAI/nightshift/actions"><img src="https://github.com/FvdHMBAI/nightshift/actions/workflows/ci.yml/badge.svg" alt="CI"></a>&nbsp;
  <a href="https://github.com/FvdHMBAI/nightshift/stargazers"><img src="https://img.shields.io/github/stars/FvdHMBAI/nightshift?style=social" alt="GitHub Stars"></a>&nbsp;
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-blue.svg" alt="MIT License"></a>
</p>

<p align="center">
  <a href="#quick-start">Quick Start</a> ·
  <a href="#what-it-fixes">What It Fixes</a> ·
  <a href="#how-it-compares">Comparison</a> ·
  <a href="#architecture">Architecture</a> ·
  <a href="#agentstack-ecosystem">Ecosystem</a>
</p>

---

I used to start every Monday reviewing the same lint errors, the same type mismatches, the same outdated dependencies. Now I wake up to a branch per fix, each one verified, each one ready to merge.

Night Shift turned Monday mornings from cleanup into code review.

It scans your repositories overnight, finds lint errors, TypeScript issues, security vulnerabilities, and documentation gaps. Fixes them automatically. Commits each fix to its own branch. Sends you a morning summary. Self-hosted, free, runs with your own LLM.

---

<p align="center">
  <img src="demo/demo.gif" alt="Night Shift Demo" width="700">
</p>

---

## Morning Summary

This is what arrives on your phone before your first coffee:

```
 Night Shift Run Complete
 2026-08-07 | 5 repos | 22:00 - 02:47

 FIXED (12 branches ready to merge)
   my-frontend
     nightshift/lint-fix-no-unused-vars        eslint --fix
     nightshift/type-fix-missing-null-check     LLM patch + tsc verified
     nightshift/deps-update-minor-patch         npm update (13 packages)

   my-api
     nightshift/lint-fix-prefer-const           eslint --fix
     nightshift/security-fix-express-4.19       npm audit fix + build OK
     nightshift/type-fix-async-return           LLM patch + tsc verified
     nightshift/docs-expand-readme              24 lines -> 89 lines

   my-backend
     nightshift/lint-fix-unused-imports         eslint --fix
     nightshift/type-fix-optional-chain         LLM patch + tsc verified
     nightshift/security-fix-jsonwebtoken       npm audit fix + build OK

   shared-lib
     nightshift/lint-fix-consistent-return      eslint --fix
     nightshift/deps-update-minor-patch         npm update (7 packages)

 ROLLED BACK (2 tasks)
     my-frontend  type-fix-complex-generic     tsc failed after patch
     my-api       deps-update-major            build broke, reverted

 STATS
   Tasks created:   14
   Tasks completed: 12 (85.7%)
   Tasks failed:     2 (auto-rolled back)
   LLM tokens used: 23,400 (Ollama qwen3:8b, $0.00)
   Duration:         4h 47m
```

Every branch is isolated. Nothing touches your working code. You review, you merge, you move on.

---

## Why Night Shift?

| | Night Shift | Devin | CodeRabbit | Sweep (dead) |
|---|---|---|---|---|
| **Cost** | Free (self-hosted) | $500/mo | $15/mo+ | Shut down |
| **Your data** | Stays on your server | Sent to cloud | Sent to cloud | N/A |
| **LLM choice** | Ollama / Claude / GPT | Proprietary | Proprietary | N/A |
| **Approach** | Overnight batch fixes | Interactive agent | PR review only | Issue to PR |
| **What it fixes** | Lint, types, security, docs | Everything (slowly) | Nothing (reviews only) | Issues |
| **Safety** | Branch per fix, auto-rollback | Full repo access | Read-only | Full access |
| **Setup** | 5 minutes | Account + billing | GitHub app | N/A |

**Night Shift is not trying to be Devin.** It handles the boring, repetitive maintenance that piles up. The kind of work nobody wants to do but everybody benefits from. It runs when you sleep, uses your own LLM, and every fix lands on its own branch for you to review.

---

## What it fixes

| Category | Detection | Fix method | Verification |
|----------|-----------|------------|--------------|
| **Lint** | `eslint --quiet` | `eslint --fix` | Re-lint |
| **Types** | `tsc --noEmit` | LLM-assisted patch | `tsc --noEmit` re-check |
| **Security** | `npm audit` (high/critical) | `npm audit fix` + individual upgrades | TypeScript + build check |
| **Docs** | README < 20 lines | LLM-generated expansion | Length check |
| **Deps** | `npm outdated` | `npm update` (minor/patch only) | TypeScript + Next.js build |

Every fix runs on its own branch (`nightshift/lint-fix-20260801-eslint-no-unused-vars`), so you always review before merging.

---

<a id="architecture"></a>

## Architecture

```
                         Night Shift Architecture

  ┌────────────────────────────────────────────────────────────────────┐
  │                        COORDINATOR (cron)                         │
  │  Runs nightly · checks RAM · creates run record · orchestrates    │
  └───────────┬──────────────────────────────────────┬────────────────┘
              │                                      │
              ▼                                      ▼
  ┌─────────────────────┐              ┌─────────────────────────┐
  │   SCANNER (per repo) │              │   WORKER POOL (parallel) │
  │                      │              │                          │
  │  • ESLint errors     │   tasks      │  Worker 1: lint-fix      │
  │  • TypeScript issues │──────────▶   │  Worker 2: security      │
  │  • npm audit         │   (DB)       │  Worker 3: type-fix      │
  │  • Missing tests     │              │                          │
  │  • Thin docs         │              │  Each worker:            │
  └──────────────────────┘              │  1. Create branch        │
                                        │  2. Apply fix            │
                                        │  3. Verify (tsc)         │
                                        │  4. Commit + push        │
                                        │  5. Rollback on failure  │
                                        └───────────┬──────────────┘
                                                    │
              ┌─────────────────────────────────────┘
              ▼
  ┌─────────────────────┐     ┌─────────────────────┐
  │   LESSON GENERATOR   │     │    MORNING SUMMARY   │
  │  (optional, Pro)     │     │                      │
  │                      │     │  • ntfy notification  │
  │  Explains the WHY    │     │  • DB summary record  │
  │  behind each fix     │     │  • Run statistics     │
  └──────────────────────┘     └──────────────────────┘
```

### Safety guarantees

1. **Branch isolation.** Every fix gets its own branch. Your main/develop is never touched.
2. **Backup tags.** Created before any changes, recoverable with `git tag -l 'nightshift-backup/*'`.
3. **Compilation verification.** TypeScript check after every npm change. Breaks? Automatic rollback.
4. **Stash protection.** Uncommitted work is stashed before, restored after.
5. **RAM monitoring.** Stops spawning workers if memory drops below threshold.
6. **Task timeout.** 2-hour default prevents runaway processes.
7. **Lockfile.** Prevents concurrent coordinator runs.
8. **Risk classification.** High-risk tasks are flagged, complex ones deferred to a stronger model.

---

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
cp config.sh config.local.sh
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
DB_MODE="postgres"
DB_URL="postgresql://user:pass@localhost:5432/nightshift"

# LLM: Ollama is default (free, local)
OLLAMA_MODEL="qwen3:8b"
# ANTHROPIC_API_KEY="sk-ant-..."   # optional: better type/doc fixes

# Limits
MAX_TASKS=15
MAX_WORKERS=3
MAX_TASK_DURATION=7200              # 2h timeout per task
MIN_FREE_RAM_MB=3072                # abort if < 3GB free

# Notifications (ntfy.sh compatible)
# NTFY_URL="https://ntfy.sh/my-nightshift"
```

---

## How it works

```
22:00  Coordinator starts
       ├── Check RAM, create run record
       ├── For each repo:
       │   ├── git fetch origin develop
       │   ├── ESLint scan
       │   ├── TypeScript scan
       │   ├── npm audit
       │   ├── Test coverage check
       │   └── README length check
       │
       ├── Classify findings into tasks (low/medium/high risk)
       │
       ├── Run workers (up to 3 parallel):
       │   ├── Create nightshift/* branch
       │   ├── Apply fix
       │   ├── Verify (tsc --noEmit, build check)
       │   ├── If broken: rollback, mark failed
       │   ├── If clean: commit, push, mark completed
       │   └── Generate lesson (optional)
       │
       └── Generate summary, send to DB + ntfy

06:00  Morning summary (catches any unfinished runs)
```

---

## Lesson Generator (Pro)

Every completed fix generates a learning lesson explaining the programming concept behind the change. Not just what was fixed, but why it matters. Stored in the database with topic, difficulty, code before/after, and exercises.

Works best with an Anthropic API key but falls back to Ollama.

---

## Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `NIGHTSHIFT_DB_URL` | `postgresql://...localhost:5432/nightshift` | PostgreSQL connection |
| `NIGHTSHIFT_DB_MODE` | `postgres` | `postgres` or `docker` |
| `NIGHTSHIFT_DB_CONTAINER` | n/a | Docker container (if mode=docker) |
| `NIGHTSHIFT_DB_NAME` | `nightshift` | Database name (docker mode) |
| `NIGHTSHIFT_DB_USER` | `postgres` | Database user (docker mode) |
| `OLLAMA_URL` | `http://localhost:11434/api/generate` | Ollama endpoint |
| `OLLAMA_MODEL` | `qwen3:8b` | Local LLM model |
| `ANTHROPIC_API_KEY` | n/a | Claude API (optional, Pro features) |
| `NIGHTSHIFT_CLAUDE_MODEL` | `claude-sonnet-4-6` | Claude model |
| `NIGHTSHIFT_NTFY_URL` | n/a | ntfy.sh notification URL |
| `NIGHTSHIFT_LOG_DIR` | `/var/log/nightshift` | Log directory |
| `NIGHTSHIFT_LESSON_DIR` | `./lessons` | Lesson output directory |

---

## Extending Night Shift

Add custom task categories by:

1. Adding a scanner in `coordinator.sh` that outputs `repo|category|title|description`
2. Adding a handler in `worker.sh` with a `case "$category"` branch
3. That's it. The coordinator/worker/summary pipeline handles the rest.

---

## FAQ

**Can it break my code?**
Every fix runs on its own branch. If TypeScript compilation fails after a fix, the change is rolled back automatically. Your working branches are never modified.

**Does it support monorepos?**
Yes. Add the monorepo root to `REPOS`. The scanner checks for ESLint, TypeScript, and npm audit at the configured paths.

**What LLMs does it support?**
Any Ollama model (local, free) or Anthropic Claude (cloud, paid). The TypeScript fixer and doc generator use the LLM. Lint and security fixes are deterministic tools.

**How much does it cost to run?**
With Ollama: $0. With Claude API: typically $0.02-0.10 per run depending on findings. The system logs token usage per task.

**Can I run it manually?**
Yes: `./coordinator.sh` runs a full cycle. `./summary-morning.sh` generates/sends the summary.

---

<a id="agentstack-ecosystem"></a>

## AgentStack Ecosystem

Night Shift is one piece of a complete AI operations stack. Each tool solves one problem well:

| Tool | What it does | Link |
|------|-------------|------|
| **[GuardRail](https://github.com/FvdHMBAI/guardrail)** | Pre-execution security for AI agents. Blocks dangerous commands before they run. | [Repo](https://github.com/FvdHMBAI/guardrail) |
| **[Model Router](https://github.com/FvdHMBAI/model-router)** | Shell-native LLM routing. One config, every model, zero dependencies. | [Repo](https://github.com/FvdHMBAI/model-router) |
| **Night Shift** | Overnight codebase maintenance. You are here. | |
| **[Graphify Toolkit](https://github.com/FvdHMBAI/graphify-toolkit)** | Turn any codebase into a queryable knowledge graph. | [Repo](https://github.com/FvdHMBAI/graphify-toolkit) |
| **[Autonomie OS](https://github.com/FvdHMBAI/autonomie-os)** | Self-improving AI agent framework. Learns from every session. | [Repo](https://github.com/FvdHMBAI/autonomie-os) |

All five tools are open source, self-hosted, and work together. GuardRail protects. Model Router picks the right model. Night Shift maintains the code. Graphify maps the architecture. Autonomie OS makes agents smarter over time.

---

## Learn More

Want to understand how these tools fit into a complete AI governance strategy? The free course covers guard design, model routing, autonomous operations, and more:

**[KI-Governance Kurs](https://lernen.promptandbuild.de)** (18 lessons, free)

---

## License

MIT. See [LICENSE](LICENSE).

---

<p align="center">
  Built by <a href="https://promptandbuild.de">Prompt & Build</a>.
</p>

<p align="center">
  If Night Shift saves you maintenance time, consider giving it a <a href="https://github.com/FvdHMBAI/nightshift">star</a>. It helps others find it.
</p>
