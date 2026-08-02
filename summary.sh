#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/config.sh"

RUN_ID="${1:-}"
if [[ -z "$RUN_ID" ]]; then
  log "ERROR: Run ID missing"
  exit 1
fi

main() {
  local existing_summary
  existing_summary=$(db_query "SELECT summary FROM nightshift_runs WHERE id = '$RUN_ID' AND summary IS NOT NULL" | head -1)
  if [[ -n "$existing_summary" ]]; then
    log "Summary for run $RUN_ID already exists, skipping"
    exit 0
  fi

  local run_data
  run_data=$(db_query "SELECT tasks_created, tasks_completed, tasks_failed FROM nightshift_runs WHERE id = '$RUN_ID'" | head -1)
  IFS='|' read -r created completed failed <<< "$run_data"

  local task_details
  task_details=$(db_query "SELECT category, title, status, risk_level FROM nightshift_tasks WHERE run_id = '$RUN_ID' ORDER BY status, risk_level DESC")

  local lesson_count
  lesson_count=$(db_query "SELECT COUNT(*) FROM lessons l JOIN nightshift_tasks t ON l.task_id = t.id WHERE t.run_id = '$RUN_ID'")

  local skipped needs_claude
  skipped=$(db_query "SELECT COUNT(*) FROM nightshift_tasks WHERE run_id = '$RUN_ID' AND status = 'skipped'")
  needs_claude=$(db_query "SELECT COUNT(*) FROM nightshift_tasks WHERE run_id = '$RUN_ID' AND status = 'needs_claude'")

  local prompt="Create a brief summary (max 5 sentences) for this Night Shift run:
- Tasks created: $created
- Completed: $completed
- Failed: $failed
- Skipped: $skipped
- Needs Claude: $needs_claude
- Lessons generated: $lesson_count

Task details:
$task_details

Be factual and concise. Mention the most important changes."

  local summary
  summary=$(ollama_generate "$prompt")
  if [[ -z "$summary" ]]; then
    summary="Night Shift Run: $completed/$created tasks completed, $failed failed, $lesson_count lessons generated."
  fi

  local safe_summary
  safe_summary=$(echo "$summary" | sed "s/'/''/g" | head -c 2000)

  db_exec "UPDATE nightshift_runs SET completed_at = NOW(), summary = '$safe_summary' WHERE id = '$RUN_ID'"

  # Send notification (if ntfy configured)
  if [[ -n "$NTFY_URL" ]]; then
    local notify_msg="Night Shift done: ${completed}/${created} tasks completed"
    [[ "$failed" -gt 0 ]] && notify_msg="$notify_msg, $failed failed"
    [[ "$lesson_count" -gt 0 ]] && notify_msg="$notify_msg, $lesson_count new lessons"

    curl -s -o /dev/null \
      -H "Title: Night Shift Report" \
      -H "Priority: default" \
      -H "Tags: moon,robot" \
      -d "$notify_msg" \
      "$NTFY_URL" 2>/dev/null || log "WARNING: ntfy notification failed"

    log "Summary written: $notify_msg"
  else
    log "Summary written: $completed/$created tasks completed"
  fi
}

main
