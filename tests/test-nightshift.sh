#!/usr/bin/env bash
# Night Shift Test Suite
# Run: ./tests/test-nightshift.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

# ─── Test Framework ───

TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0
FAILURES=""

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

assert_eq() {
  local expected="$1" actual="$2" msg="${3:-assertion}"
  TESTS_RUN=$((TESTS_RUN + 1))
  if [[ "$expected" == "$actual" ]]; then
    TESTS_PASSED=$((TESTS_PASSED + 1))
  else
    TESTS_FAILED=$((TESTS_FAILED + 1))
    FAILURES="${FAILURES}\n  FAIL: ${msg}\n    expected: '${expected}'\n    actual:   '${actual}'"
    echo -e "  ${RED}FAIL${NC} $msg"
    return 0
  fi
  echo -e "  ${GREEN}PASS${NC} $msg"
}

assert_contains() {
  local haystack="$1" needle="$2" msg="${3:-contains assertion}"
  TESTS_RUN=$((TESTS_RUN + 1))
  if echo "$haystack" | grep -qF "$needle"; then
    TESTS_PASSED=$((TESTS_PASSED + 1))
    echo -e "  ${GREEN}PASS${NC} $msg"
  else
    TESTS_FAILED=$((TESTS_FAILED + 1))
    FAILURES="${FAILURES}\n  FAIL: ${msg}\n    expected to contain: '${needle}'\n    in: '${haystack}'"
    echo -e "  ${RED}FAIL${NC} $msg"
  fi
}

assert_not_empty() {
  local value="$1" msg="${2:-not empty assertion}"
  TESTS_RUN=$((TESTS_RUN + 1))
  if [[ -n "$value" ]]; then
    TESTS_PASSED=$((TESTS_PASSED + 1))
    echo -e "  ${GREEN}PASS${NC} $msg"
  else
    TESTS_FAILED=$((TESTS_FAILED + 1))
    FAILURES="${FAILURES}\n  FAIL: ${msg} (was empty)"
    echo -e "  ${RED}FAIL${NC} $msg"
  fi
}

assert_file_exists() {
  local path="$1" msg="${2:-file exists}"
  TESTS_RUN=$((TESTS_RUN + 1))
  if [[ -f "$path" ]]; then
    TESTS_PASSED=$((TESTS_PASSED + 1))
    echo -e "  ${GREEN}PASS${NC} $msg"
  else
    TESTS_FAILED=$((TESTS_FAILED + 1))
    FAILURES="${FAILURES}\n  FAIL: ${msg} (not found: $path)"
    echo -e "  ${RED}FAIL${NC} $msg"
  fi
}

assert_executable() {
  local path="$1" msg="${2:-is executable}"
  TESTS_RUN=$((TESTS_RUN + 1))
  if [[ -x "$path" ]]; then
    TESTS_PASSED=$((TESTS_PASSED + 1))
    echo -e "  ${GREEN}PASS${NC} $msg"
  else
    TESTS_FAILED=$((TESTS_FAILED + 1))
    FAILURES="${FAILURES}\n  FAIL: ${msg} (not executable: $path)"
    echo -e "  ${RED}FAIL${NC} $msg"
  fi
}

# ─── Test: File Structure ───

echo ""
echo "=== File Structure ==="

assert_file_exists "$PROJECT_DIR/config.sh" "config.sh exists"
assert_file_exists "$PROJECT_DIR/coordinator.sh" "coordinator.sh exists"
assert_file_exists "$PROJECT_DIR/worker.sh" "worker.sh exists"
assert_file_exists "$PROJECT_DIR/summary.sh" "summary.sh exists"
assert_file_exists "$PROJECT_DIR/summary-morning.sh" "summary-morning.sh exists"
assert_file_exists "$PROJECT_DIR/lesson-generator.sh" "lesson-generator.sh exists"
assert_file_exists "$PROJECT_DIR/install.sh" "install.sh exists"
assert_file_exists "$PROJECT_DIR/schema.sql" "schema.sql exists"

# ─── Test: Scripts are executable ───

echo ""
echo "=== Executability ==="

for script in coordinator.sh worker.sh summary.sh summary-morning.sh lesson-generator.sh install.sh; do
  assert_executable "$PROJECT_DIR/$script" "$script is executable"
done

# ─── Test: Config Parsing ───

echo ""
echo "=== Config Parsing ==="

# Source config in a subshell to test defaults
config_output=$(bash -c "
  source '$PROJECT_DIR/config.sh'
  echo \"MAX_TASKS=\$MAX_TASKS\"
  echo \"MAX_WORKERS=\$MAX_WORKERS\"
  echo \"MAX_TASK_DURATION=\$MAX_TASK_DURATION\"
  echo \"MIN_FREE_RAM_MB=\$MIN_FREE_RAM_MB\"
  echo \"DB_MODE=\$DB_MODE\"
  echo \"OLLAMA_MODEL=\$OLLAMA_MODEL\"
" 2>/dev/null || echo "CONFIG_PARSE_FAILED")

assert_contains "$config_output" "MAX_TASKS=15" "MAX_TASKS default is 15"
assert_contains "$config_output" "MAX_WORKERS=3" "MAX_WORKERS default is 3"
assert_contains "$config_output" "MAX_TASK_DURATION=7200" "MAX_TASK_DURATION default is 7200"
assert_contains "$config_output" "MIN_FREE_RAM_MB=3072" "MIN_FREE_RAM_MB default is 3072"
assert_contains "$config_output" "DB_MODE=postgres" "DB_MODE default is postgres"
assert_contains "$config_output" "OLLAMA_MODEL=qwen3:8b" "OLLAMA_MODEL default is qwen3:8b"

# Test config override via env vars
override_output=$(bash -c "
  export OLLAMA_MODEL='llama3:8b'
  export NIGHTSHIFT_DB_MODE='docker'
  source '$PROJECT_DIR/config.sh'
  echo \"OLLAMA_MODEL=\$OLLAMA_MODEL\"
  echo \"DB_MODE=\$DB_MODE\"
" 2>/dev/null || echo "OVERRIDE_FAILED")

assert_contains "$override_output" "OLLAMA_MODEL=llama3:8b" "OLLAMA_MODEL overridable via env"
assert_contains "$override_output" "DB_MODE=docker" "DB_MODE overridable via env"

# ─── Test: Helper Functions ───

echo ""
echo "=== Helper Functions ==="

# sql_escape
escape_result=$(bash -c "
  source '$PROJECT_DIR/config.sh'
  sql_escape \"it's a test\"
" 2>/dev/null)
assert_eq "it''s a test" "$escape_result" "sql_escape escapes single quotes"

escape_backslash=$(bash -c "
  source '$PROJECT_DIR/config.sh'
  sql_escape 'path\\\\to\\\\file'
" 2>/dev/null)
assert_eq 'path\\\\to\\\\file' "$escape_backslash" "sql_escape escapes backslashes"

# log function
log_output=$(bash -c "
  export NIGHTSHIFT_LOG_DIR='/tmp/nightshift-test-$$'
  mkdir -p \$NIGHTSHIFT_LOG_DIR
  source '$PROJECT_DIR/config.sh'
  log 'test message'
  cat \$NIGHTSHIFT_LOG_DIR/nightshift.log
  rm -rf \$NIGHTSHIFT_LOG_DIR
" 2>/dev/null)
assert_contains "$log_output" "test message" "log() writes to log file"
assert_contains "$log_output" "[20" "log() includes timestamp"

# check_ram (should succeed on any real machine)
ram_result=$(bash -c "
  source '$PROJECT_DIR/config.sh'
  MIN_FREE_RAM_MB=1
  if check_ram; then echo 'RAM_OK'; else echo 'RAM_LOW'; fi
" 2>/dev/null)
assert_eq "RAM_OK" "$ram_result" "check_ram passes with MIN_FREE_RAM_MB=1"

ram_fail=$(bash -c "
  export NIGHTSHIFT_LOG_DIR='/tmp/nightshift-test-ram-$$'
  mkdir -p \$NIGHTSHIFT_LOG_DIR
  source '$PROJECT_DIR/config.sh'
  MIN_FREE_RAM_MB=999999
  if check_ram; then echo 'RAM_OK'; else echo 'RAM_LOW'; fi
  rm -rf \$NIGHTSHIFT_LOG_DIR
" 2>/dev/null | tail -1)
assert_eq "RAM_LOW" "$ram_fail" "check_ram fails with MIN_FREE_RAM_MB=999999"

# ─── Test: Lock Mechanism ───

echo ""
echo "=== Lock Mechanism ==="

lock_result=$(bash -c "
  export NIGHTSHIFT_LOG_DIR='/tmp/nightshift-test-$$'
  mkdir -p \$NIGHTSHIFT_LOG_DIR
  source '$PROJECT_DIR/config.sh'
  LOCKFILE='/tmp/nightshift-test-lock-$$'
  if acquire_lock; then echo 'ACQUIRED'; else echo 'BLOCKED'; fi
  if [[ -f \$LOCKFILE ]]; then echo 'FILE_EXISTS'; fi
  release_lock
  if [[ -f \$LOCKFILE ]]; then echo 'STILL_EXISTS'; else echo 'CLEANED'; fi
  rm -rf \$NIGHTSHIFT_LOG_DIR
" 2>/dev/null)
assert_contains "$lock_result" "ACQUIRED" "acquire_lock succeeds"
assert_contains "$lock_result" "FILE_EXISTS" "lockfile created"
assert_contains "$lock_result" "CLEANED" "release_lock removes lockfile"

# Stale lock test
stale_result=$(bash -c "
  export NIGHTSHIFT_LOG_DIR='/tmp/nightshift-test-$$'
  mkdir -p \$NIGHTSHIFT_LOG_DIR
  source '$PROJECT_DIR/config.sh'
  LOCKFILE='/tmp/nightshift-test-lock-stale-$$'
  echo 99999999 > \$LOCKFILE
  if acquire_lock; then echo 'ACQUIRED_STALE'; else echo 'BLOCKED_STALE'; fi
  release_lock
  rm -rf \$NIGHTSHIFT_LOG_DIR
" 2>/dev/null)
assert_contains "$stale_result" "ACQUIRED_STALE" "acquire_lock removes stale lockfile"

# ─── Test: Task Categories ───

echo ""
echo "=== Task Categories ==="

# Check that worker.sh handles all documented categories
worker_categories=$(grep -oP "^\s+\K[a-z-]+\)" "$PROJECT_DIR/worker.sh" | tr -d ')' | sort)
for cat in lint-fix type-fix docs security test-coverage; do
  TESTS_RUN=$((TESTS_RUN + 1))
  if echo "$worker_categories" | grep -qF "$cat"; then
    TESTS_PASSED=$((TESTS_PASSED + 1))
    echo -e "  ${GREEN}PASS${NC} worker handles category: $cat"
  else
    TESTS_FAILED=$((TESTS_FAILED + 1))
    FAILURES="${FAILURES}\n  FAIL: worker missing category: $cat"
    echo -e "  ${RED}FAIL${NC} worker missing category: $cat"
  fi
done

# Check wildcard fallback
wildcard_fallback=$(grep -c '^\s*\*)' "$PROJECT_DIR/worker.sh" || echo "0")
TESTS_RUN=$((TESTS_RUN + 1))
if [[ "$wildcard_fallback" -ge 1 ]]; then
  TESTS_PASSED=$((TESTS_PASSED + 1))
  echo -e "  ${GREEN}PASS${NC} worker has wildcard fallback for unknown categories"
else
  TESTS_FAILED=$((TESTS_FAILED + 1))
  FAILURES="${FAILURES}\n  FAIL: worker missing wildcard fallback"
  echo -e "  ${RED}FAIL${NC} worker missing wildcard fallback"
fi

# ─── Test: Risk Classification ───

echo ""
echo "=== Risk Classification ==="

# Verify risk classification in coordinator
risk_cases=$(grep -A2 'case.*category.*in' "$PROJECT_DIR/coordinator.sh" | grep -E 'security|architecture|complex-refactor' || echo "")
assert_not_empty "$risk_cases" "coordinator classifies security/architecture as higher risk"

# ─── Test: Schema Validity ───

echo ""
echo "=== Schema ==="

# Check all required tables
schema_content=$(cat "$PROJECT_DIR/schema.sql")
assert_contains "$schema_content" "nightshift_runs" "schema defines nightshift_runs table"
assert_contains "$schema_content" "nightshift_tasks" "schema defines nightshift_tasks table"
assert_contains "$schema_content" "lessons" "schema defines lessons table"
assert_contains "$schema_content" "learning_progress" "schema defines learning_progress table"
assert_contains "$schema_content" "lesson_chats" "schema defines lesson_chats table"

# Check indexes
assert_contains "$schema_content" "idx_nightshift_tasks_run_id" "schema has run_id index"
assert_contains "$schema_content" "idx_nightshift_tasks_status" "schema has status index"

# ─── Test: Shellcheck (if available) ───

echo ""
echo "=== Shellcheck ==="

if command -v shellcheck &>/dev/null; then
  shellcheck_pass=true
  for script in config.sh coordinator.sh worker.sh summary.sh summary-morning.sh lesson-generator.sh install.sh; do
    TESTS_RUN=$((TESTS_RUN + 1))
    sc_output=$(shellcheck -S warning "$PROJECT_DIR/$script" 2>&1 || true)
    sc_errors=$(echo "$sc_output" | grep -c "^In " || echo "0")
    if [[ "$sc_errors" -eq 0 ]]; then
      TESTS_PASSED=$((TESTS_PASSED + 1))
      echo -e "  ${GREEN}PASS${NC} shellcheck: $script"
    else
      TESTS_FAILED=$((TESTS_FAILED + 1))
      FAILURES="${FAILURES}\n  FAIL: shellcheck: $script ($sc_errors warnings)"
      echo -e "  ${RED}FAIL${NC} shellcheck: $script ($sc_errors warnings)"
      shellcheck_pass=false
    fi
  done
else
  echo -e "  ${YELLOW}SKIP${NC} shellcheck not installed"
fi

# ─── Test: No German Strings in Code ───

echo ""
echo "=== Language Check (English only) ==="

german_found=false
for script in config.sh coordinator.sh worker.sh summary.sh summary-morning.sh lesson-generator.sh install.sh; do
  TESTS_RUN=$((TESTS_RUN + 1))
  german_lines=$(grep -cE 'ä|ö|ü|ß' "$PROJECT_DIR/$script" 2>/dev/null | tr -d '[:space:]' || echo "0")
  german_lines="${german_lines:-0}"
  if [[ "$german_lines" -eq 0 ]]; then
    TESTS_PASSED=$((TESTS_PASSED + 1))
    echo -e "  ${GREEN}PASS${NC} $script: no German strings"
  else
    TESTS_FAILED=$((TESTS_FAILED + 1))
    FAILURES="${FAILURES}\n  FAIL: $script has $german_lines German string(s)"
    echo -e "  ${RED}FAIL${NC} $script: $german_lines German string(s)"
    german_found=true
  fi
done

# ─── Test: Cleanup Function ───

echo ""
echo "=== Cleanup Functions ==="

# Verify cleanup_branch exists and is called in worker
cleanup_calls=$(grep -c 'cleanup_branch' "$PROJECT_DIR/worker.sh" 2>/dev/null | tr -d '[:space:]' || echo "0")
TESTS_RUN=$((TESTS_RUN + 1))
if [[ "$cleanup_calls" -ge 3 ]]; then
  TESTS_PASSED=$((TESTS_PASSED + 1))
  echo -e "  ${GREEN}PASS${NC} cleanup_branch called $cleanup_calls times in worker.sh"
else
  TESTS_FAILED=$((TESTS_FAILED + 1))
  FAILURES="${FAILURES}\n  FAIL: cleanup_branch only called $cleanup_calls times (expected >=3)"
  echo -e "  ${RED}FAIL${NC} cleanup_branch only called $cleanup_calls times"
fi

# Verify EXIT trap in worker (may be multi-line)
trap_exists=$(grep -c 'EXIT' "$PROJECT_DIR/worker.sh" 2>/dev/null | tr -d '[:space:]' || echo "0")
TESTS_RUN=$((TESTS_RUN + 1))
if [[ "$trap_exists" -ge 1 ]]; then
  TESTS_PASSED=$((TESTS_PASSED + 1))
  echo -e "  ${GREEN}PASS${NC} worker.sh has EXIT trap"
else
  TESTS_FAILED=$((TESTS_FAILED + 1))
  FAILURES="${FAILURES}\n  FAIL: worker.sh missing EXIT trap"
  echo -e "  ${RED}FAIL${NC} worker.sh missing EXIT trap"
fi

# Verify TERM trap for timeout
term_trap=$(grep -c 'trap.*handle_timeout.*TERM' "$PROJECT_DIR/worker.sh" 2>/dev/null || echo "0")
TESTS_RUN=$((TESTS_RUN + 1))
if [[ "$term_trap" -ge 1 ]]; then
  TESTS_PASSED=$((TESTS_PASSED + 1))
  echo -e "  ${GREEN}PASS${NC} worker.sh has TERM trap for timeout"
else
  TESTS_FAILED=$((TESTS_FAILED + 1))
  FAILURES="${FAILURES}\n  FAIL: worker.sh missing TERM trap for timeout"
  echo -e "  ${RED}FAIL${NC} worker.sh missing TERM trap"
fi

# ─── Test: Summary Generation ───

echo ""
echo "=== Summary ==="

# Verify summary.sh reads run data
summary_content=$(cat "$PROJECT_DIR/summary.sh")
assert_contains "$summary_content" "nightshift_runs" "summary.sh queries nightshift_runs"
assert_contains "$summary_content" "nightshift_tasks" "summary.sh queries nightshift_tasks"
assert_contains "$summary_content" "ntfy" "summary.sh supports ntfy notifications"

# Verify morning summary handles edge cases
morning_content=$(cat "$PROJECT_DIR/summary-morning.sh")
assert_contains "$morning_content" "No runs found" "morning summary handles no-runs case"
assert_contains "$morning_content" "already has summary" "morning summary skips existing summaries"

# ─── Results ───

echo ""
echo "============================================"
if [[ "$TESTS_FAILED" -eq 0 ]]; then
  echo -e "  ${GREEN}ALL $TESTS_RUN TESTS PASSED${NC}"
else
  echo -e "  ${RED}$TESTS_FAILED/$TESTS_RUN TESTS FAILED${NC}"
  echo -e "$FAILURES"
fi
echo "  Passed: $TESTS_PASSED  Failed: $TESTS_FAILED  Total: $TESTS_RUN"
echo "============================================"

exit "$TESTS_FAILED"
