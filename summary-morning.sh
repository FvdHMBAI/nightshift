#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/config.sh"

mkdir -p "$LOG_DIR"

main() {
  log "=== Morning Summary started ==="

  local latest_run_id
  latest_run_id=$(db_query "SELECT id FROM nightshift_runs WHERE started_at > NOW() - INTERVAL '24 hours' AND completed_at IS NULL ORDER BY started_at DESC LIMIT 1")

  if [[ -n "$latest_run_id" ]]; then
    log "Open run found: $latest_run_id — generating summary"
    "$SCRIPT_DIR/summary.sh" "$latest_run_id"
  else
    local last_complete
    last_complete=$(db_query "SELECT id FROM nightshift_runs WHERE completed_at IS NOT NULL ORDER BY started_at DESC LIMIT 1")
    if [[ -n "$last_complete" ]]; then
      local has_summary
      has_summary=$(db_query "SELECT summary FROM nightshift_runs WHERE id = '$last_complete' AND summary IS NOT NULL" | head -1)
      if [[ -z "$has_summary" ]]; then
        log "Last run without summary: $last_complete — generating retroactively"
        "$SCRIPT_DIR/summary.sh" "$last_complete"
      else
        log "Last run already has summary, nothing to do"
      fi
    else
      log "No runs found"
    fi
  fi

  log "=== Morning Summary finished ==="
}

main
