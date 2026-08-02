# Night Shift

**Your code improves while you sleep.**

Night Shift is an autonomous code improvement system that runs overnight and fixes lint errors, TypeScript issues, security vulnerabilities, and documentation gaps across your repositories. Every morning you wake up to a summary of what changed and why.

```
┌─────────────┐     ┌──────────┐     ┌──────────┐     ┌──────────┐
│ Coordinator │────▶│ Scanner  │────▶│  Tasks   │────▶│ Workers  │
│  (cron)     │     │ per repo │     │ (DB)     │     │ parallel │
└─────────────┘     └──────────┘     └──────────┘     └────┬─────┘
                                                           │
                    ┌──────────┐     ┌──────────┐          │
                    │ Summary  │◀────│ Commits  │◀─────────┘
                    │ (notify) │     │ (branch) │
                    └──────────┘     └──────────┘
```

## What it fixes

| Category | What it does | How |
|----------|-------------|-----|
| **Lint** | Auto-fixes ESLint errors | `eslint --fix` |
| **Types** | Fixes TypeScript compilation errors | LLM-assisted analysis |
| **Security** | Patches npm vulnerabilities | `npm audit fix` + individual upgrades |
| **Docs** | Expands thin README files | LLM-generated content |

Every fix is committed to its own branch (`nightshift/lint-fix-20260801-...`) so you can review before merging.

## Quick Start

### 1. Prerequisites

- **PostgreSQL** (13+) for task tracking
- **Ollama** with a model (default: `qwen3:8b`) for local LLM analysis
- **Node.js** repos with ESLint / TypeScript (for lint/type fixes)
- Linux with `bash`, `curl`, `jq`, `python3`

### 2. Install

```bash
git clone https://github.com/FvdHMBAI/nightshift.git
cd nightshift

# Edit config.sh — add your repos and database connection
vim config.sh

# Run installer (creates DB tables, cron jobs, checks dependencies)
./install.sh
```

### 3. Configure

Edit `config.sh`:

```bash
# Your repositories
REPOS=(
  "$HOME/projects/my-frontend"
  "$HOME/projects/my-api"
  "$HOME/projects/my-backend"
)

# Database (PostgreSQL)
NIGHTSHIFT_DB_URL="postgresql://postgres:postgres@localhost:5432/nightshift"

# Or via Docker container
# NIGHTSHIFT_DB_MODE="docker"
# NIGHTSHIFT_DB_CONTAINER="my-postgres"

# LLM (Ollama is default, Claude is optional)
OLLAMA_MODEL="qwen3:8b"
# ANTHROPIC_API_KEY="sk-ant-..."  # Optional: better type fixes

# Notifications (optional, ntfy.sh compatible)
# NIGHTSHIFT_NTFY_URL="https://ntfy.sh/my-nightshift"
```

### 4. Run

Night Shift runs automatically via cron (22:00 nightly, 06:00 morning summary).

Manual run:
```bash
./coordinator.sh     # Full scan + fix cycle
./summary-morning.sh # Generate summary for last run
```

## How it works

1. **Scan** — Coordinator checks each repo for ESLint errors, TypeScript issues, npm vulnerabilities, missing tests, and thin docs
2. **Classify** — Findings become tasks with risk levels (`low` / `medium` / `high`)
3. **Execute** — Workers pick up tasks (up to 3 in parallel), create branches, apply fixes
4. **Verify** — TypeScript compilation check after every fix. If it breaks, automatic rollback
5. **Report** — Summary via ntfy notification + database record

### Safety

- Every fix runs on its own branch — your main/develop stays untouched
- Backup tags created before any changes
- TypeScript compilation check after npm security fixes (rollback on failure)
- RAM monitoring — stops if memory gets low
- Task timeout (2h default) prevents runaway processes
- Lockfile prevents concurrent runs
- Uncommitted changes are stashed and restored

## Database

Night Shift uses PostgreSQL to track runs, tasks, and lessons:

```bash
# Apply schema
psql $NIGHTSHIFT_DB_URL -f schema.sql

# Check recent runs
psql $NIGHTSHIFT_DB_URL -c "SELECT started_at, tasks_created, tasks_completed, tasks_failed FROM nightshift_runs ORDER BY started_at DESC LIMIT 5"
```

## Pro Features

The lesson generator (`lesson-generator.sh`) creates educational content from every completed fix — explaining the programming concept behind the change. Requires an Anthropic API key for best results.

## Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `NIGHTSHIFT_DB_URL` | `postgresql://postgres:postgres@localhost:5432/nightshift` | PostgreSQL connection |
| `NIGHTSHIFT_DB_MODE` | `postgres` | `postgres` or `docker` |
| `NIGHTSHIFT_DB_CONTAINER` | — | Docker container name (if mode=docker) |
| `OLLAMA_URL` | `http://localhost:11434/api/generate` | Ollama API endpoint |
| `OLLAMA_MODEL` | `qwen3:8b` | Ollama model for analysis |
| `ANTHROPIC_API_KEY` | — | Claude API key (optional, Pro features) |
| `NIGHTSHIFT_NTFY_URL` | — | ntfy.sh notification endpoint |
| `NIGHTSHIFT_LOG_DIR` | `/var/log/nightshift` | Log directory |
| `NIGHTSHIFT_LESSON_DIR` | `./lessons` | Lesson output directory |

## License

MIT — see [LICENSE](LICENSE)

---

Built by [Prompt & Build](https://promptandbuild.de) — running 13+ SaaS products with AI agents.
