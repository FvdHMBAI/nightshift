#!/usr/bin/env bash
# Example: Multi-repo Night Shift configuration
# Copy this to config.local.sh and adjust paths

# Source defaults
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/config.sh"

# ─── Your Repositories ───
REPOS=(
  "$HOME/projects/web-app"
  "$HOME/projects/api-server"
  "$HOME/projects/admin-panel"
  "$HOME/projects/mobile-backend"
  "$HOME/projects/shared-lib"
)

# ─── Database (Docker example) ───
DB_MODE="docker"
DB_CONTAINER="my-postgres"
DB_NAME="nightshift"
DB_USER="postgres"

# ─── LLM ───
# Local Ollama for routine tasks (free)
OLLAMA_MODEL="qwen3:8b"

# Claude for complex type fixes and lesson generation (optional)
# export ANTHROPIC_API_KEY="sk-ant-..."

# ─── Tuning ───
MAX_TASKS=20              # More repos = more findings
MAX_WORKERS=4             # Adjust to your CPU cores
MAX_TASK_DURATION=3600    # 1h per task (faster timeout)
MIN_FREE_RAM_MB=4096      # 4 GB minimum for multiple workers

# ─── Notifications ───
NTFY_URL="https://ntfy.sh/my-nightshift-alerts"
