#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/config.sh"

TASK_ID="${1:-}"
if [[ -z "$TASK_ID" ]]; then
  log "ERROR: Task ID missing"
  exit 1
fi

main() {
  local task_data
  task_data=$(db_query "SELECT repo, category, title, description, risk_level, llm_tier, run_id FROM nightshift_tasks WHERE id = '$TASK_ID'" | head -1)
  if [[ -z "$task_data" ]]; then
    log "ERROR: Task $TASK_ID not found"
    exit 1
  fi

  IFS='|' read -r repo category title description risk_level llm_tier run_id <<< "$task_data"

  # Resolve repo path — supports both basename and absolute path in REPOS
  local repo_path=""
  for rp in "${REPOS[@]}"; do
    if [[ "$(basename "$rp")" == "$repo" ]]; then
      repo_path="$rp"
      break
    fi
  done
  if [[ -z "$repo_path" ]]; then
    repo_path="$repo"
  fi

  local branch_name="nightshift/${category}-$(date +%Y%m%d)-$(echo "$title" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/-/g' | head -c 40)"

  log "Worker started: [$category] $title (Repo: $repo)"
  local safe_branch
  safe_branch=$(sql_escape "$branch_name")
  db_exec "UPDATE nightshift_tasks SET status = 'running', branch_name = '$safe_branch' WHERE id = '$TASK_ID'"

  # Skip complex tasks
  if [[ "$llm_tier" == "heavy" ]]; then
    log "Task requires Claude (heavy tier), marking as needs_claude"
    db_exec "UPDATE nightshift_tasks SET status = 'needs_claude', completed_at = NOW() WHERE id = '$TASK_ID'"
    exit 0
  fi

  if [[ ! -d "$repo_path" ]]; then
    fail_task "Repo directory not found: $repo_path"
    exit 1
  fi

  cd "$repo_path"

  # Stash uncommitted changes
  local dirty_src
  dirty_src=$(git status --porcelain 2>/dev/null | grep -v 'package-lock.json' | grep -v '.cache/' | grep -v 'node_modules/' | grep -v '^\?\?' || true)
  local stashed=false
  if [[ -n "$dirty_src" ]]; then
    log "Stashing uncommitted changes in $repo"
    if git stash push -u -m "nightshift-auto-stash-$(date +%Y%m%d-%H%M%S)" --quiet 2>/dev/null; then
      stashed=true
    else
      log "WARNING: git stash failed, skipping"
      db_exec "UPDATE nightshift_tasks SET status = 'skipped', error_message = 'git stash failed', completed_at = NOW() WHERE id = '$TASK_ID'"
      exit 0
    fi
  fi

  # Create backup tag
  local base_branch="develop"
  if ! git rev-parse --verify "$base_branch" &>/dev/null; then
    base_branch="main"
  fi
  local backup_tag="nightshift-backup/$(date +%Y%m%d-%H%M%S)-${repo}"
  git tag "$backup_tag" "$base_branch" 2>/dev/null || true

  # Create branch
  git checkout "$base_branch" --quiet 2>/dev/null
  git pull origin "$base_branch" --quiet 2>/dev/null || true
  git checkout -b "$branch_name" --quiet 2>/dev/null

  # Timeout handler
  local worker_pid=$$
  (sleep "$MAX_TASK_DURATION" && kill -TERM "$worker_pid" 2>/dev/null) &
  local timeout_pid=$!
  handle_timeout() {
    db_exec "UPDATE nightshift_tasks SET status = 'failed', error_message = 'Timeout after ${MAX_TASK_DURATION}s', completed_at = NOW() WHERE id = '$TASK_ID' AND status = 'running'"
    log "Task $TASK_ID: Timeout after ${MAX_TASK_DURATION}s"
    exit 1
  }
  trap handle_timeout TERM
  trap 'kill '"$timeout_pid"' 2>/dev/null || true
    cleanup_branch "'"$base_branch"'" "'"$branch_name"'" || true
    if '"$stashed"'; then
      if ! git stash pop --quiet 2>/dev/null; then
        log "WARNING: git stash pop failed. Changes saved in stash, recover manually with: git stash list"
      fi
    fi' EXIT

  # Execute task
  local success=false
  case "$category" in
    lint-fix)
      execute_lint_fix && success=true
      ;;
    type-fix)
      execute_type_fix && success=true
      ;;
    docs)
      execute_docs_fix "$title" "$description" && success=true
      ;;
    security)
      execute_security_fix && success=true
      ;;
    test-coverage)
      log "Test coverage tasks require Claude, marking as needs_claude"
      db_exec "UPDATE nightshift_tasks SET status = 'needs_claude', completed_at = NOW() WHERE id = '$TASK_ID'"
      cleanup_branch "$base_branch" "$branch_name"
      exit 0
      ;;
    *)
      log "Unknown category: $category, skipping"
      db_exec "UPDATE nightshift_tasks SET status = 'skipped', error_message = 'Category not supported: $category', completed_at = NOW() WHERE id = '$TASK_ID'"
      cleanup_branch "$base_branch" "$branch_name"
      exit 0
      ;;
  esac

  if ! $success; then
    if [[ "$category" == "security" ]]; then
      log "Security fix not applicable, marking as skipped"
      db_exec "UPDATE nightshift_tasks SET status = 'skipped', error_message = 'No auto-fixable vulnerabilities', completed_at = NOW() WHERE id = '$TASK_ID'"
    else
      fail_task "execute_${category}_fix could not be applied"
    fi
    cleanup_branch "$base_branch" "$branch_name"
    exit 0
  fi

  # Check for relevant changes
  local relevant_changes
  relevant_changes=$(git status --porcelain 2>/dev/null | grep -v '.cache/' || true)
  if [[ -z "$relevant_changes" ]]; then
    log "No relevant changes after execution"
    db_exec "UPDATE nightshift_tasks SET status = 'skipped', error_message = 'No changes needed', completed_at = NOW() WHERE id = '$TASK_ID'"
    cleanup_branch "$base_branch" "$branch_name"
    exit 0
  fi

  # Commit + Push
  git add -A -- ':!.cache'
  local diff_stat
  diff_stat=$(git diff --cached --stat | tail -1)
  git commit -m "nightshift: [$category] $title" --quiet 2>/dev/null
  if ! git push origin "$branch_name" --quiet 2>/dev/null; then
    log "WARNING: git push failed for $branch_name, branch exists only locally"
  fi

  local safe_diff
  safe_diff=$(sql_escape "$diff_stat")
  db_exec "UPDATE nightshift_tasks SET status = 'completed', diff_summary = '$safe_diff', completed_at = NOW() WHERE id = '$TASK_ID'"
  log "Task completed: $diff_stat"

  # Generate lesson (Pro feature)
  if [[ -f "$SCRIPT_DIR/lesson-generator.sh" ]]; then
    "$SCRIPT_DIR/lesson-generator.sh" "$TASK_ID" &
  fi

  git checkout "$base_branch" --quiet 2>/dev/null
}

execute_lint_fix() {
  if [[ -f "node_modules/.bin/eslint" ]]; then
    npx eslint --fix src/ --quiet 2>/dev/null || true
    return 0
  fi
  return 1
}

execute_type_fix() {
  local errors
  errors=$(npx tsc --noEmit 2>&1 | grep "error TS" | head -3 || true)
  if [[ -z "$errors" ]]; then
    return 1
  fi

  while IFS= read -r error_line; do
    local file_path line_num error_msg
    file_path=$(echo "$error_line" | cut -d'(' -f1)
    line_num=$(echo "$error_line" | grep -o '([0-9]*,' | tr -d '(,')
    error_msg=$(echo "$error_line" | sed 's/.*error TS[0-9]*: //')

    [[ ! -f "$file_path" ]] && continue

    local file_content
    file_content=$(sed -n "$((line_num > 3 ? line_num - 3 : 1)),$((line_num + 3))p" "$file_path" 2>/dev/null || true)
    [[ -z "$file_content" ]] && continue

    local fix
    fix=$(ollama_generate "Fix this TypeScript error. Return ONLY the corrected lines, no explanation.

Error: $error_msg
File: $(basename "$file_path"), line $line_num

Context:
$file_content")

    local fix_lines
    fix_lines=$(echo "$fix" | wc -l)
    if [[ "$fix_lines" -le 10 ]] && [[ -n "$fix" ]]; then
      local start_line=$((line_num > 3 ? line_num - 3 : 1))
      local end_line=$((line_num + 3))
      local tmp_file
      tmp_file=$(mktemp)
      {
        sed -n "1,$((start_line - 1))p" "$file_path"
        echo "$fix"
        sed -n "$((end_line + 1)),\$p" "$file_path"
      } > "$tmp_file"
      mv "$tmp_file" "$file_path"
      log "TypeScript fix applied in $file_path:$line_num"
    fi
  done <<< "$errors"

  if npx tsc --noEmit 2>/dev/null; then
    return 0
  fi
  return 1
}

execute_docs_fix() {
  local title="$1"
  local description="$2"

  if [[ "$title" == *"README"* ]]; then
    local current_readme=""
    [[ -f "README.md" ]] && current_readme=$(cat README.md)

    local repo_name
    repo_name=$(basename "$(pwd)")

    local new_content
    new_content=$(ollama_generate "Improve this README.md for the repository '$repo_name'. Add missing sections (Installation, Usage, Architecture). Keep existing content. Return ONLY the markdown content.

Current README:
$current_readme")

    if [[ -z "$new_content" ]]; then
      return 1
    fi
    if [[ ${#new_content} -le ${#current_readme} ]]; then
      log "LLM output shorter than original README, skipping"
      return 1
    fi
    if [[ ${#new_content} -gt 50000 ]]; then
      log "LLM output too large (${#new_content} bytes), skipping"
      return 1
    fi
    local first_line
    first_line=$(echo "$new_content" | head -1)
    if [[ "$first_line" == '```'* ]]; then
      new_content=$(echo "$new_content" | sed '1d;$d')
    fi
    echo "$new_content" > README.md
    return 0
  fi
  return 1
}

execute_security_fix() {
  if [[ ! -f "package.json" ]]; then
    log "No package.json, skipping"
    return 1
  fi

  if [[ ! -d "node_modules" ]]; then
    log "node_modules missing, installing..."
    timeout 300 npm ci --ignore-scripts 2>>"${LOG_DIR}/worker-${TASK_ID}.err" || timeout 300 npm install --ignore-scripts 2>>"${LOG_DIR}/worker-${TASK_ID}.err" || {
      log "npm install failed"
      return 1
    }
  fi

  timeout 120 npm audit fix 2>>"${LOG_DIR}/worker-${TASK_ID}.err" || true

  if [[ -n "$(git diff --name-only 2>/dev/null | grep package)" ]]; then
    if [[ -f "tsconfig.json" ]] && [[ -f "node_modules/.bin/tsc" ]]; then
      if ! timeout 120 npx tsc --noEmit 2>>"${LOG_DIR}/worker-${TASK_ID}.err"; then
        log "TypeScript errors after npm audit fix, rolling back"
        git checkout -- package.json package-lock.json 2>/dev/null
        npm install --ignore-scripts 2>/dev/null || true
        return 1
      fi
    fi
    return 0
  fi

  # Fallback: upgrade individual fixable packages
  local fixable
  fixable=$(npm audit --json 2>/dev/null | jq -r '.vulnerabilities | to_entries[] | select((.value.fixAvailable == true) or (.value.fixAvailable | type == "object" and .isSemVerMajor == false)) | (if .value.fixAvailable | type == "object" then .value.fixAvailable.name else .key end)' 2>/dev/null | sort -u | head -5)
  if [[ -n "$fixable" ]]; then
    log "npm audit fix ineffective, trying individual packages: $fixable"
    for pkg in $fixable; do
      timeout 60 npm update "$pkg" 2>>"${LOG_DIR}/worker-${TASK_ID}.err" || true
    done
    if [[ -n "$(git diff --name-only 2>/dev/null | grep package)" ]]; then
      if [[ -f "tsconfig.json" ]] && [[ -f "node_modules/.bin/tsc" ]]; then
        if ! timeout 120 npx tsc --noEmit 2>>"${LOG_DIR}/worker-${TASK_ID}.err"; then
          log "TypeScript errors after npm update, rolling back"
          git checkout -- package.json package-lock.json 2>/dev/null
          timeout 120 npm install --ignore-scripts 2>/dev/null || true
          return 1
        fi
      fi
      return 0
    fi
  fi

  log "npm audit: vulnerabilities not auto-fixable (semver-major or no fix available)"
  return 1
}

fail_task() {
  local error_msg="$1"
  local safe_msg
  safe_msg=$(sql_escape "$(echo "$error_msg" | head -c 500)")
  db_exec "UPDATE nightshift_tasks SET status = 'failed', error_message = '$safe_msg', completed_at = NOW() WHERE id = '$TASK_ID'"
  log "Task failed: $error_msg"
}

cleanup_branch() {
  local base_branch="$1"
  local branch_name="$2"
  cd "$(git rev-parse --show-toplevel 2>/dev/null || echo /tmp)" 2>/dev/null || true
  if ! git checkout "$base_branch" --quiet 2>/dev/null; then
    log "WARNING: cleanup could not switch to $base_branch, forcing reset"
    git checkout -f "$base_branch" --quiet 2>/dev/null || true
  fi
  git branch -D "$branch_name" 2>/dev/null || true
}

main
