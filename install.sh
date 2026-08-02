#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/config.sh"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

ok()   { echo -e "  ${GREEN}[OK]${NC} $1"; }
warn() { echo -e "  ${YELLOW}[WARN]${NC} $1"; }
fail() { echo -e "  ${RED}[FAIL]${NC} $1"; }

ERRORS=0

echo "============================================"
echo "  Night Shift — Installation"
echo "  $(date '+%Y-%m-%d %H:%M:%S')"
echo "============================================"
echo ""

# --- 1. Directories ---
echo "1. Directories..."
mkdir -p "$LOG_DIR"
ok "Log directory: $LOG_DIR"
mkdir -p "$LESSON_DIR"
ok "Lesson directory: $LESSON_DIR"

# --- 2. Make scripts executable ---
echo ""
echo "2. Scripts..."
for script in "$SCRIPT_DIR"/*.sh; do
  chmod +x "$script"
done
ok "All scripts in $SCRIPT_DIR are executable"

# --- 3. Database tables ---
echo ""
echo "3. Database tables..."

db_exec "$(cat "$SCRIPT_DIR/schema.sql")" && ok "Schema applied" || { fail "Schema failed"; ERRORS=$((ERRORS + 1)); }

# --- 4. Cron jobs ---
echo ""
echo "4. Cron jobs..."

CRON_COORDINATOR="0 22 * * * $SCRIPT_DIR/coordinator.sh >> $LOG_DIR/cron.log 2>&1"
CRON_SUMMARY="0 6 * * * $SCRIPT_DIR/summary-morning.sh >> $LOG_DIR/morning.log 2>&1"

install_cron() {
  local marker="$1"
  local line="$2"
  local script_path="$3"
  local existing
  existing=$(crontab -l 2>/dev/null || true)

  if echo "$existing" | grep -qF "$script_path"; then
    ok "Cron already installed: $marker"
    return
  fi

  echo "$existing" | {
    cat
    echo "# $marker"
    echo "$line"
  } | crontab -
  ok "Cron installed: $marker"
}

install_cron "Night Shift Coordinator (22:00)" "$CRON_COORDINATOR" "coordinator.sh"
install_cron "Night Shift Morning Summary (06:00)" "$CRON_SUMMARY" "summary-morning.sh"

# --- 5. Ollama ---
echo ""
echo "5. Ollama..."

if curl -s --max-time 5 "http://localhost:11434/api/tags" >/dev/null 2>&1; then
  ok "Ollama running"
  if curl -s --max-time 5 "http://localhost:11434/api/tags" | python3 -c "
import sys,json
models = [m['name'] for m in json.load(sys.stdin).get('models',[])]
if '$OLLAMA_MODEL' in models or '${OLLAMA_MODEL}:latest' in models:
  print('found')
" 2>/dev/null | grep -q "found"; then
    ok "Model $OLLAMA_MODEL available"
  else
    warn "Model $OLLAMA_MODEL not found — run: ollama pull $OLLAMA_MODEL"
    ERRORS=$((ERRORS + 1))
  fi
else
  warn "Ollama not reachable (http://localhost:11434)"
  warn "Install: https://ollama.com"
  ERRORS=$((ERRORS + 1))
fi

# --- 6. Database connection ---
echo ""
echo "6. Database..."

if db_query "SELECT 1" >/dev/null 2>&1; then
  ok "Database reachable"
  run_count=$(db_query "SELECT count(*) FROM nightshift_runs" 2>/dev/null || echo "0")
  task_count=$(db_query "SELECT count(*) FROM nightshift_tasks" 2>/dev/null || echo "0")
  ok "Data: $run_count runs, $task_count tasks"
else
  fail "Database not reachable"
  echo "    Configure DB_URL in config.sh or set NIGHTSHIFT_DB_URL env var"
  ERRORS=$((ERRORS + 1))
fi

# --- 7. Repos ---
echo ""
echo "7. Repos..."

if [[ ${#REPOS[@]} -eq 0 ]]; then
  warn "No repos configured — edit config.sh REPOS array"
  ERRORS=$((ERRORS + 1))
else
  for repo_path in "${REPOS[@]}"; do
    if [[ -d "$repo_path/.git" ]]; then
      ok "$(basename "$repo_path")"
    else
      warn "Not found: $repo_path"
      ERRORS=$((ERRORS + 1))
    fi
  done
fi

# --- 8. RAM ---
echo ""
echo "8. RAM..."

FREE_MB=$(free -m | awk '/^Mem:/{print $7}')
if [[ "$FREE_MB" -ge "$MIN_FREE_RAM_MB" ]]; then
  ok "${FREE_MB}MB free (minimum: ${MIN_FREE_RAM_MB}MB)"
else
  warn "Only ${FREE_MB}MB free (minimum: ${MIN_FREE_RAM_MB}MB)"
  ERRORS=$((ERRORS + 1))
fi

# --- Result ---
echo ""
echo "============================================"
if [[ "$ERRORS" -eq 0 ]]; then
  echo -e "  ${GREEN}Installation complete — no errors${NC}"
else
  echo -e "  ${YELLOW}Installation complete with $ERRORS warning(s)${NC}"
fi
echo ""
echo "  Coordinator:  nightly at 22:00"
echo "  Summary:      morning at 06:00"
echo "  Logs:         $LOG_DIR"
echo ""
echo "  Next: edit config.sh to add your repos"
echo "============================================"
