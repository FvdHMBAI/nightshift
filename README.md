<h1 align="center">
  <br>
  <img src="https://img.shields.io/badge/%F0%9F%8C%99-Night%20Shift-blue?style=for-the-badge&labelColor=0d1117&color=8b5cf6" alt="Night Shift" height="40">
  <br>
  Your codebase improves while you sleep.
  <br>
</h1>

<p align="center">
  <a href="https://github.com/FvdHMBAI/nightshift/actions"><img src="https://github.com/FvdHMBAI/nightshift/actions/workflows/ci.yml/badge.svg" alt="CI"></a>&nbsp;
  <a href="https://github.com/FvdHMBAI/nightshift/stargazers"><img src="https://img.shields.io/github/stars/FvdHMBAI/nightshift?style=social" alt="GitHub Stars"></a>&nbsp;
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-blue.svg" alt="MIT License"></a>
</p>

<p align="center">
  <a href="#the-story">Story</a> · 
  <a href="#quick-start">Quick Start</a> · 
  <a href="#how-it-compares">Comparison</a> · 
  <a href="#what-it-fixes">What It Fixes</a> · 
  <a href="#architecture">Architecture</a> · 
  <a href="#the-agentstack-ecosystem">Ecosystem</a>
</p>

---

## The Story

Every Monday morning, the same feeling: 14 ESLint warnings, 3 TypeScript errors nobody owns, two `npm audit` findings from last week's dependency bump. Not urgent enough to fix during a sprint. Too annoying to ignore.

So we built a cron job that fixes them overnight.

Night Shift scans your repositories while you sleep. It finds lint errors, TypeScript issues, security vulnerabilities, and documentation gaps. It fixes them automatically, commits each fix to its own branch, and sends you a morning summary. You review. You merge. You move on to the work that matters.

No SaaS account. No cloud dependency. Your LLM, your server, your code.

```
  ┌──────────────────────────────────────────────────────────────┐
  │  Morning Summary: Night Shift Run #247                       │
  │                                                              │
  │  Scanned: 5 repos                                            │
  │  Fixed:   12 issues (4 lint, 3 types, 2 security, 3 docs)   │
  │  Branches: 12 ready for review                               │
  │  Duration: 23 minutes                                        │
  │  Cost:     EUR 0.00 (Ollama local)                           │
  │                                                              │
  │  ✓ All fixes verified. No regressions detected.              │
  └──────────────────────────────────────────────────────────────┘
```

<p align="center">
  <img src="demo/demo.gif" alt="Night Shift Demo" width="700">
</p>

---

<table>
  <tr>
    <td align="center"><strong>225</strong><br><sub>Cron Jobs in Production</sub></td>
    <td align="center"><strong>81</strong><br><sub>Containers Monitored</sub></td>
    <td align="center"><strong>1,048</strong><br><sub>Autonomous Tasks Completed</sub></td>
    <td align="center"><strong>89%</strong><br><sub>Success Rate</sub></td>
  </tr>
</table>

<p align="center"><sub>Numbers from a live system running 13 applications. Night Shift is one of 225 automated jobs.</sub></p>

---

## Quick Start

### Prerequisites

- bash 4+, jq, git
- Node.js 18+ (for the repos you want to scan)
- One of: Ollama (free), Claude API key, or OpenAI API key

### Install

```bash
git clone https://github.com/FvdHMBAI/nightshift.git
cd nightshift && ./install.sh
```

### Configure

```bash
nightshift init
# Creates ~/.nightshift/config.json with sensible defaults
```

Add your repos:

```bash
nightshift add /home/developer/my-project
nightshift add /home/developer/another-project
```

### Run

```bash
# Manual run (foreground)
nightshift run

# Schedule nightly at 2 AM
nightshift schedule 02:00
```

That's it. Tomorrow morning you'll have branches ready for review.

## How It Compares

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

## What It Fixes

| Category | Detection | Fix method | Verification |
|----------|-----------|------------|--------------|
| **Lint** | `eslint --quiet` | `eslint --fix` | Re-lint |
| **Types** | `tsc --noEmit` | LLM-assisted patch | `tsc --noEmit` re-check |
| **Security** | `npm audit` (high/critical) | `npm audit fix` + individual upgrades | TypeScript + build check |
| **Docs** | README < 20 lines | LLM-generated expansion | Length check |
| **Deps** | `npm outdated` | `npm update` (minor/patch only) | TypeScript + Next.js build |

Every fix runs on its own branch (`nightshift/lint-fix-20260801-eslint-no-unused-vars`), so you always review before merging.

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
  │  ESLint errors       │   tasks      │  Worker 1: lint-fix      │
  │  TypeScript issues   │────────▶     │  Worker 2: security      │
  │  npm audit           │   (DB)       │  Worker 3: type-fix      │
  │  Missing tests       │              │                          │
  │  Thin docs           │              │  Each worker:            │
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
  │                      │     │  ntfy notification   │
  │  Explains the WHY    │     │  DB summary record   │
  │  behind each fix     │     │  Run statistics      │
  └──────────────────────┘     └──────────────────────┘
```

Each scanner detects issues. Each worker fixes one issue on a dedicated branch. If the fix breaks the build, the worker rolls back automatically. No partial fixes, no broken code.

## Safety First

Night Shift never pushes to your main branch. Every fix gets its own branch, its own commit message, and its own verification step. You review, you merge, you stay in control.

Built-in safety checks:
- **RAM check** before starting (skips run if memory is low)
- **Branch isolation** (one branch per fix, never touches main)
- **Auto-rollback** (if TypeScript or build fails after fix, the branch is deleted)
- **Dry-run mode** (`nightshift run --dry-run` shows what would change without touching code)

Works with [GuardRail](https://github.com/FvdHMBAI/guardrail) for defense in depth. GuardRail blocks dangerous commands. Night Shift only runs safe, predefined operations.

## Configuration

Edit `~/.nightshift/config.json`:

```json
{
  "repos": [
    "/home/developer/my-project",
    "/home/developer/another-project"
  ],
  "schedule": "02:00",
  "model_tier": "local",
  "max_workers": 3,
  "categories": ["lint", "types", "security", "docs"],
  "notify": {
    "ntfy": "https://ntfy.sh/my-nightshift-channel"
  }
}
```

## CLI

```bash
nightshift run              # Run now (foreground)
nightshift run --dry-run    # Show what would change
nightshift schedule 02:00   # Set nightly schedule
nightshift add /path/repo   # Add a repository
nightshift remove /path     # Remove a repository
nightshift status           # Show last run summary
nightshift logs             # View run history
```

## LLM Support

Night Shift routes models through [Model Router](https://github.com/FvdHMBAI/model-router) when available. Without it, direct provider support:

| Provider | Model | Cost | Best for |
|----------|-------|------|----------|
| **Ollama** | qwen3:8b | Free | Type fixes, doc generation |
| **Anthropic** | Claude Sonnet | ~$0.01/fix | Complex type errors |
| **OpenAI** | GPT-4o | ~$0.01/fix | Alternative provider |

Default is Ollama. Your code never leaves your machine.

## The AgentStack Ecosystem

Night Shift is one of five open-source tools for AI governance:

| Tool | What it does |
|---|---|
| **[GuardRail](https://github.com/FvdHMBAI/guardrail)** | Pre-execution security. 172 guards, 96% enforcement rate. |
| **[Model Router](https://github.com/FvdHMBAI/model-router)** | Shell-native LLM routing. One config, every model. |
| **Night Shift** | Overnight code improvement (you are here). |
| **[Graphify Toolkit](https://github.com/FvdHMBAI/graphify-toolkit)** | Turn any codebase into a queryable knowledge graph. |
| **[Autonomie OS](https://github.com/FvdHMBAI/autonomie-os)** | Self-improving agent framework. Learns from every session. |

Each tool works standalone. Together, they form a governance layer for AI-assisted development.

**Learn the principles behind this stack:** [18 free lessons on KI-Governance](https://lernen.promptandbuild.de)

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md). Browse [good first issues](https://github.com/FvdHMBAI/nightshift/issues?q=is%3Aissue+is%3Aopen+label%3A%22good+first+issue%22).

## License

MIT. See [LICENSE](LICENSE).

---

<p align="center">
  Built by <a href="https://promptandbuild.de">Prompt & Build</a>.<br>
  Part of <a href="https://github.com/FvdHMBAI/agent-stack">AgentStack</a>: the complete governance layer for AI agents.
</p>
