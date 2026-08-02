#!/usr/bin/env bash
# Pro Feature: Generates learning lessons from completed tasks
# Requires: Anthropic API key (ANTHROPIC_API_KEY) or Ollama
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/config.sh"

TASK_ID="${1:-}"
if [[ -z "$TASK_ID" ]]; then
  log "ERROR: Task ID missing"
  exit 1
fi

main() {
  local existing
  existing=$(db_query "SELECT id FROM lessons WHERE task_id = '$TASK_ID' LIMIT 1")
  if [[ -n "$existing" ]]; then
    log "Lesson for task $TASK_ID already exists, skipping"
    exit 0
  fi

  local task_data
  task_data=$(db_query "SELECT repo, category, title, description, branch_name FROM nightshift_tasks WHERE id = '$TASK_ID' AND status = 'completed'" | head -1)
  if [[ -z "$task_data" ]]; then
    log "Task $TASK_ID not found or not completed"
    exit 1
  fi

  IFS='|' read -r repo category title description branch_name <<< "$task_data"

  # Resolve repo path
  local repo_path=""
  for rp in "${REPOS[@]}"; do
    if [[ "$(basename "$rp")" == "$repo" ]]; then
      repo_path="$rp"
      break
    fi
  done

  local diff_content=""
  if [[ -n "$repo_path" ]] && [[ -d "$repo_path" ]] && [[ -n "$branch_name" ]]; then
    cd "$repo_path"
    local base_branch="develop"
    git rev-parse --verify "$base_branch" &>/dev/null || base_branch="main"
    diff_content=$(git diff "$base_branch...$branch_name" 2>/dev/null | head -300 || true)
  fi

  local prompt
  prompt="You are an experienced programming teacher. Create a lesson that explains a programming concept based on this real code change.

IMPORTANT:
- Explain the CONCEPT, not just the change
- Use the actual code as an example
- Write for someone who is learning to code but is not a beginner
- Include 2-3 exercises they can try on their own codebase

Respond as JSON:
{
  \"topic\": \"Short title\",
  \"concept_category\": \"TypeScript|Next.js|React|Database|Security|Testing|DevOps|Architecture|Performance\",
  \"difficulty\": \"beginner|intermediate|advanced\",
  \"what_changed\": \"What was changed (2-3 sentences)\",
  \"why\": \"Why this matters (2-3 sentences)\",
  \"concept_explanation\": \"The concept explained in detail (8-15 sentences)\",
  \"exercises\": \"2-3 exercises\",
  \"key_takeaway\": \"One sentence summary\"
}

Repository: $repo
Category: $category
Title: $title
Description: $description

Code Diff:
$diff_content"

  local response
  response=$(claude_generate "$prompt")

  local topic concept_category difficulty what_changed why concept_explanation
  topic=$(echo "$response" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('topic','$title'))" 2>/dev/null || echo "$title")
  concept_category=$(echo "$response" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('concept_category','$category'))" 2>/dev/null || echo "$category")
  difficulty=$(echo "$response" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('difficulty','beginner'))" 2>/dev/null || echo "beginner")
  what_changed=$(echo "$response" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('what_changed',''))" 2>/dev/null || echo "$description")
  why=$(echo "$response" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('why',''))" 2>/dev/null || echo "Improves code quality")
  concept_explanation=$(echo "$response" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('concept_explanation',''))" 2>/dev/null || echo "See diff for details")

  topic=$(echo "$topic" | sed "s/'/''/g" | head -c 200)
  concept_category=$(echo "$concept_category" | sed "s/'/''/g" | head -c 50)
  what_changed=$(echo "$what_changed" | sed "s/'/''/g" | head -c 1000)
  why=$(echo "$why" | sed "s/'/''/g" | head -c 1000)
  concept_explanation=$(echo "$concept_explanation" | sed "s/'/''/g" | head -c 4000)

  local code_before="" code_after=""
  if [[ -n "$diff_content" ]]; then
    code_before=$(echo "$diff_content" | grep "^-[^-]" | head -20 | sed 's/^-//' | sed "s/'/''/g")
    code_after=$(echo "$diff_content" | grep "^+[^+]" | head -20 | sed 's/^+//' | sed "s/'/''/g")
  fi

  local lesson_id
  lesson_id=$(db_query "INSERT INTO lessons (task_id, topic, concept_category, difficulty, what_changed, why, concept_explanation, code_before, code_after)
    VALUES ('$TASK_ID', '$topic', '$concept_category', '$difficulty', '$what_changed', '$why', '$concept_explanation', '$code_before', '$code_after')
    RETURNING id" | tail -1)

  log "Lesson created: $lesson_id - $topic"
}

main
