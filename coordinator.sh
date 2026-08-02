#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/config.sh"

mkdir -p "$LOG_DIR"

main() {
  log "=== Night Shift Coordinator started ==="

  if ! acquire_lock; then
    exit 1
  fi
  trap 'release_lock; log "=== Night Shift finished ==="' EXIT

  if ! check_ram; then
    log "Not enough RAM, aborting"
    exit 1
  fi

  # Create run
  local run_id
  run_id=$(db_query "INSERT INTO nightshift_runs (repos_scanned) VALUES ('{$(IFS=,; echo "${REPOS[*]##*/}")}') RETURNING id" | head -1)
  if [[ -z "$run_id" ]]; then
    log "ERROR: Could not create run"
    exit 1
  fi
  log "Run created: $run_id"

  # System status
  log "--- System Status ---"
  log "RAM free: $(free -m | awk '/^Mem:/{print $7}')MB"
  log "Disk free: $(df -h / | awk 'NR==2{print $4}')"
  log "Ollama: $(curl -s -o /dev/null -w '%{http_code}' http://localhost:11434/api/tags 2>/dev/null || echo 'OFFLINE')"
  log "--- Repo Status ---"
  for rp in "${REPOS[@]}"; do
    local rn=$(basename "$rp")
    local rchanges=$(git -C "$rp" status --porcelain 2>/dev/null | wc -l)
    local rbranch=$(git -C "$rp" branch --show-current 2>/dev/null)
    log "  $rn: Branch=$rbranch, Changes=$rchanges"
  done
  log "---"

  # Phase 1: Scan repos
  local all_findings=""
  local repos_scanned=0
  for repo_path in "${REPOS[@]}"; do
    local repo_name
    repo_name=$(basename "$repo_path")
    if [[ ! -d "$repo_path" ]]; then
      log "WARNING: Repo not found: $repo_path"
      continue
    fi
    log "Scanning $repo_name..."
    local findings
    findings=$(scan_repo "$repo_path" "$repo_name")
    if [[ -n "$findings" ]]; then
      all_findings="${all_findings}${findings}\n"
    fi
    repos_scanned=$((repos_scanned + 1))
  done

  if [[ -z "$all_findings" ]]; then
    log "No findings, ending run"
    db_exec "UPDATE nightshift_runs SET completed_at = NOW(), summary = 'No findings' WHERE id = '$run_id'"
    exit 0
  fi

  # Phase 2: Classify findings and create tasks
  log "Classifying findings..."
  local task_count=0
  while IFS='|' read -r repo category title description; do
    [[ -z "$repo" ]] && continue
    [[ "$task_count" -ge "$MAX_TASKS" ]] && break

    local risk_level="low"
    local llm_tier="local"

    case "$category" in
      security) risk_level="high" ;;
      architecture) risk_level="medium"; llm_tier="heavy" ;;
      complex-refactor) risk_level="medium"; llm_tier="heavy" ;;
      *) risk_level="low" ;;
    esac

    local safe_title safe_desc safe_repo safe_category
    safe_title=$(sql_escape "$title")
    safe_desc=$(sql_escape "$description")
    safe_repo=$(sql_escape "$repo")
    safe_category=$(sql_escape "$category")

    db_exec "INSERT INTO nightshift_tasks (run_id, repo, category, title, description, risk_level, llm_tier)
             VALUES ('$run_id', '$safe_repo', '$safe_category', '$safe_title', '$safe_desc', '$risk_level', '$llm_tier')"
    task_count=$((task_count + 1))
    log "  Task created: [$category] $title ($risk_level)"
  done < <(echo -e "$all_findings")

  db_exec "UPDATE nightshift_runs SET tasks_created = $task_count WHERE id = '$run_id'"
  log "$task_count tasks created"

  # Phase 3: Run workers
  if [[ "$task_count" -gt 0 ]]; then
    log "Starting workers..."
    run_workers "$run_id"
  fi

  # Phase 4: Generate summary
  log "Generating summary..."
  "$SCRIPT_DIR/summary.sh" "$run_id" || log "WARNING: Summary generation failed"

  # Clean up old backup tags (older than 7 days)
  for repo_path in "${REPOS[@]}"; do
    if [[ -d "$repo_path/.git" ]]; then
      while read -r tag; do
        local tag_date
        tag_date=$(echo "$tag" | grep -oP '\d{8}' | head -1)
        if [[ -n "$tag_date" ]]; then
          local tag_epoch
          tag_epoch=$(date -d "$tag_date" +%s 2>/dev/null || echo 0)
          local now_epoch
          now_epoch=$(date +%s)
          if [[ $((now_epoch - tag_epoch)) -gt 604800 ]]; then
            git -C "$repo_path" tag -d "$tag" 2>/dev/null || true
          fi
        fi
      done < <(git -C "$repo_path" tag -l 'nightshift-backup/*' 2>/dev/null)
    fi
  done

  db_exec "UPDATE nightshift_runs SET completed_at = NOW() WHERE id = '$run_id'"
  log "=== Night Shift Run $run_id complete ==="
}

scan_repo() {
  local repo_path="$1"
  local repo_name="$2"
  local findings=""

  cd "$repo_path" || return

  # Update git
  local default_branch="develop"
  if ! git rev-parse --verify "$default_branch" &>/dev/null; then
    default_branch="main"
  fi
  git fetch origin "$default_branch" --quiet 2>/dev/null || true

  # 1. ESLint Check
  if [[ -f "node_modules/.bin/eslint" ]] && [[ -f ".eslintrc.json" || -f ".eslintrc.js" || -f "eslint.config.mjs" || -f "eslint.config.js" ]]; then
    local eslint_output
    eslint_output=$(npx eslint --quiet --format json src/ 2>/dev/null | python3 -c "
import sys, json
try:
  data = json.load(sys.stdin)
  errors = []
  for f in data:
    for m in f.get('messages', []):
      if m.get('severity', 0) >= 2:
        errors.append({'file': f['filePath'], 'rule': m.get('ruleId',''), 'message': m.get('message','')})
  for e in errors[:5]:
    print(f\"{e['rule']}: {e['message']} in {e['file'].split('/')[-1]}\")
except: pass
" 2>/dev/null || true)
    if [[ -n "$eslint_output" ]]; then
      while IFS= read -r line; do
        findings="${findings}${repo_name}|lint-fix|ESLint: ${line}|Auto lint fix\n"
      done <<< "$eslint_output"
    fi
  fi

  # 2. TypeScript Check
  if [[ -f "tsconfig.json" ]] && [[ -f "node_modules/.bin/tsc" ]]; then
    local tsc_errors
    tsc_errors=$(npx tsc --noEmit 2>&1 | grep "error TS" | head -5 || true)
    if [[ -n "$tsc_errors" ]]; then
      while IFS= read -r line; do
        local short_err
        short_err=$(echo "$line" | sed 's|.*/||' | head -c 200)
        findings="${findings}${repo_name}|type-fix|TypeScript: ${short_err}|Fix TypeScript error\n"
      done <<< "$tsc_errors"
    fi
  fi

  # 3. npm audit (only when auto-fixable vulnerabilities exist)
  if [[ -f "package.json" ]]; then
    local audit_json
    audit_json=$(npm audit --json 2>/dev/null || true)
    local audit_count fixable_count
    audit_count=$(echo "$audit_json" | python3 -c "
import sys, json
try:
  data = json.load(sys.stdin)
  vulns = data.get('metadata', {}).get('vulnerabilities', {})
  high = vulns.get('high', 0) + vulns.get('critical', 0)
  if high > 0: print(f'{high}')
except: pass
" 2>/dev/null || true)
    fixable_count=$(echo "$audit_json" | python3 -c "
import sys, json
try:
  data = json.load(sys.stdin)
  fixable = 0
  for name, v in data.get('vulnerabilities', {}).items():
    fa = v.get('fixAvailable')
    if fa is True or (isinstance(fa, dict) and not fa.get('isSemVerMajor', True)):
      fixable += 1
  if fixable > 0: print(f'{fixable}')
except: pass
" 2>/dev/null || true)
    if [[ -n "$audit_count" ]] && [[ "$audit_count" -gt 0 ]] && [[ -n "$fixable_count" ]] && [[ "$fixable_count" -gt 0 ]]; then
      findings="${findings}${repo_name}|security|${audit_count} critical npm vulnerabilities (${fixable_count} fixable)|Run npm audit fix\n"
    fi
  fi

  # 4. Missing tests (API routes without test files)
  local untested_count=0
  if [[ -d "src" ]]; then
    while IFS= read -r src_file; do
      local base_name
      base_name=$(basename "$src_file" .ts)
      base_name=$(basename "$base_name" .tsx)
      if ! find . -name "${base_name}.test.*" -o -name "${base_name}.spec.*" 2>/dev/null | grep -q .; then
        untested_count=$((untested_count + 1))
      fi
    done < <(find src/app/api -name "route.ts" 2>/dev/null | head -10)
    if [[ "$untested_count" -gt 0 ]]; then
      findings="${findings}${repo_name}|test-coverage|${untested_count} API routes without tests|Create tests for untested API routes\n"
    fi
  fi

  # 5. Documentation gaps
  if [[ -f "README.md" ]]; then
    local readme_lines
    readme_lines=$(wc -l < README.md)
    if [[ "$readme_lines" -lt 20 ]]; then
      findings="${findings}${repo_name}|docs|README.md too short (${readme_lines} lines)|Expand README\n"
    fi
  fi

  echo -e "$findings"
}

run_workers() {
  local run_id="$1"
  local task_ids
  task_ids=$(db_query "SELECT id FROM nightshift_tasks WHERE run_id = '$run_id' AND status = 'pending' ORDER BY
    CASE risk_level WHEN 'low' THEN 1 WHEN 'medium' THEN 2 WHEN 'high' THEN 3 ELSE 4 END,
    created_at ASC")

  local running_pids=()
  local completed=0
  local failed=0

  while IFS= read -r task_id; do
    [[ -z "$task_id" ]] && continue

    while [[ "${#running_pids[@]}" -ge "$MAX_WORKERS" ]]; do
      local new_pids=()
      for pid in "${running_pids[@]}"; do
        if kill -0 "$pid" 2>/dev/null; then
          new_pids+=("$pid")
        else
          if wait "$pid" 2>/dev/null; then
            completed=$((completed + 1))
          else
            failed=$((failed + 1))
          fi
        fi
      done
      running_pids=("${new_pids[@]}")
      if [[ "${#running_pids[@]}" -ge "$MAX_WORKERS" ]]; then
        sleep 5
      fi
    done

    if ! check_ram; then
      log "Not enough RAM, skipping remaining tasks"
      break
    fi

    log "Starting worker for task $task_id"
    "$SCRIPT_DIR/worker.sh" "$task_id" &
    running_pids+=($!)
  done <<< "$task_ids"

  for pid in "${running_pids[@]}"; do
    if wait "$pid" 2>/dev/null; then
      completed=$((completed + 1))
    else
      failed=$((failed + 1))
    fi
  done

  local real_completed real_failed real_skipped
  real_completed=$(db_query "SELECT COUNT(*) FROM nightshift_tasks WHERE run_id = '$run_id' AND status = 'completed'" | head -1)
  real_failed=$(db_query "SELECT COUNT(*) FROM nightshift_tasks WHERE run_id = '$run_id' AND status = 'failed'" | head -1)
  real_skipped=$(db_query "SELECT COUNT(*) FROM nightshift_tasks WHERE run_id = '$run_id' AND status IN ('skipped','needs_claude')" | head -1)
  db_exec "UPDATE nightshift_runs SET tasks_completed = ${real_completed:-0}, tasks_failed = ${real_failed:-0} WHERE id = '$run_id'"
  log "Workers done: ${real_completed:-0} completed, ${real_failed:-0} failed, ${real_skipped:-0} skipped"
}

main "$@"
