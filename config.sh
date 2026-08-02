#!/usr/bin/env bash
# Night Shift Configuration
# Edit this file to match your environment

# ─── Repositories to scan ───
# Add absolute paths to your git repos
REPOS=(
  # "$HOME/projects/my-app"
  # "$HOME/projects/my-api"
)

# ─── Limits ───
MAX_TASKS=15              # Max tasks per run
MAX_WORKERS=3             # Parallel workers
MAX_TASK_DURATION=7200    # 2 hours per task
MIN_FREE_RAM_MB=3072      # 3 GB minimum

# ─── Paths ───
NIGHTSHIFT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_DIR="${NIGHTSHIFT_LOG_DIR:-/var/log/nightshift}"
LOCKFILE="/tmp/nightshift.lock"
LESSON_DIR="${NIGHTSHIFT_LESSON_DIR:-$NIGHTSHIFT_DIR/lessons}"

# ─── Database ───
# Option 1: PostgreSQL (recommended for production)
#   DB_MODE="postgres"
#   DB_URL="postgresql://user:pass@localhost:5432/nightshift"
# Option 2: Docker container (e.g. Supabase)
#   DB_MODE="docker"
#   DB_CONTAINER="my-postgres-container"
#   DB_NAME="nightshift"
#   DB_USER="postgres"
DB_MODE="${NIGHTSHIFT_DB_MODE:-postgres}"
DB_URL="${NIGHTSHIFT_DB_URL:-postgresql://postgres:postgres@localhost:5432/nightshift}"
DB_CONTAINER="${NIGHTSHIFT_DB_CONTAINER:-}"
DB_NAME="${NIGHTSHIFT_DB_NAME:-nightshift}"
DB_USER="${NIGHTSHIFT_DB_USER:-postgres}"

# ─── LLM Provider ───
# Ollama (local, free)
OLLAMA_URL="${OLLAMA_URL:-http://localhost:11434/api/generate}"
OLLAMA_MODEL="${OLLAMA_MODEL:-qwen3:8b}"

# Anthropic (cloud, optional — set ANTHROPIC_API_KEY env var)
ANTHROPIC_KEY="${ANTHROPIC_API_KEY:-}"
CLAUDE_MODEL="${NIGHTSHIFT_CLAUDE_MODEL:-claude-sonnet-4-6}"

# ─── Notifications (optional) ───
# ntfy.sh compatible endpoint
NTFY_URL="${NIGHTSHIFT_NTFY_URL:-}"

# ─── Helper Functions ───

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "${LOG_DIR}/nightshift.log"
}

sql_escape() {
  local val="$1"
  val=$(printf '%s' "$val" | tr -d '\000')
  val="${val//\\/\\\\}"
  val="${val//\'/\'\'}"
  printf '%s' "$val"
}

db_query() {
  if [[ "$DB_MODE" == "docker" ]] && [[ -n "$DB_CONTAINER" ]]; then
    docker exec "$DB_CONTAINER" psql -U "$DB_USER" -d "$DB_NAME" -t -A -c "$1" 2>/dev/null
  else
    psql "$DB_URL" -t -A -c "$1" 2>/dev/null
  fi
}

db_exec() {
  if [[ "$DB_MODE" == "docker" ]] && [[ -n "$DB_CONTAINER" ]]; then
    docker exec "$DB_CONTAINER" psql -U "$DB_USER" -d "$DB_NAME" -c "$1" >/dev/null 2>/dev/null
  else
    psql "$DB_URL" -c "$1" >/dev/null 2>/dev/null
  fi
}

ollama_generate() {
  local prompt="$1"
  local result
  result=$(curl -s --max-time 120 "$OLLAMA_URL" \
    -d "{\"model\":\"$OLLAMA_MODEL\",\"prompt\":\"$prompt\",\"stream\":false}" \
    2>/dev/null)
  echo "$result" | python3 -c "import sys,json; print(json.load(sys.stdin).get('response',''))" 2>/dev/null
}

claude_generate() {
  local prompt="$1"
  if [[ -n "$ANTHROPIC_KEY" ]]; then
    local result
    result=$(curl -s --max-time 90 "https://api.anthropic.com/v1/messages" \
      -H "x-api-key: $ANTHROPIC_KEY" \
      -H "anthropic-version: 2023-06-01" \
      -H "content-type: application/json" \
      -d "$(jq -n --arg model "$CLAUDE_MODEL" --arg prompt "$prompt" \
        '{model: $model, max_tokens: 4096, temperature: 0.3, messages: [{role: "user", content: $prompt}]}')" 2>/dev/null) || result=""
    echo "$result" | jq -r '.content[0].text // ""' 2>/dev/null | sed '/^```/d'
  else
    ollama_generate "$prompt"
  fi
}

check_ram() {
  local free_mb
  free_mb=$(free -m | awk '/^Mem:/{print $7}')
  if [[ "$free_mb" -lt "$MIN_FREE_RAM_MB" ]]; then
    log "WARNING: Only ${free_mb}MB RAM free (minimum: ${MIN_FREE_RAM_MB}MB)"
    return 1
  fi
  return 0
}

acquire_lock() {
  if [[ -f "$LOCKFILE" ]]; then
    local pid
    pid=$(cat "$LOCKFILE" 2>/dev/null)
    if kill -0 "$pid" 2>/dev/null; then
      log "ERROR: Night Shift already running (PID $pid)"
      return 1
    fi
    log "Stale lockfile found, removing..."
    rm -f "$LOCKFILE"
  fi
  echo $$ > "$LOCKFILE"
  return 0
}

release_lock() {
  rm -f "$LOCKFILE"
}
