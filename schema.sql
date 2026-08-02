-- Night Shift Database Schema
-- Requires PostgreSQL 13+ (for gen_random_uuid())

CREATE TABLE IF NOT EXISTS nightshift_runs (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  started_at timestamptz NOT NULL DEFAULT now(),
  completed_at timestamptz,
  repos_scanned text[] NOT NULL DEFAULT '{}',
  tasks_created int DEFAULT 0,
  tasks_completed int DEFAULT 0,
  tasks_failed int DEFAULT 0,
  tokens_local int DEFAULT 0,
  tokens_cloud int DEFAULT 0,
  summary text
);

CREATE TABLE IF NOT EXISTS nightshift_tasks (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  run_id uuid NOT NULL REFERENCES nightshift_runs(id),
  repo text NOT NULL,
  category text NOT NULL,
  title text NOT NULL,
  description text NOT NULL,
  risk_level text NOT NULL DEFAULT 'low',
  branch_name text,
  status text NOT NULL DEFAULT 'pending',
  llm_tier text NOT NULL DEFAULT 'local',
  tokens_used_local int DEFAULT 0,
  tokens_used_cloud int DEFAULT 0,
  diff_summary text,
  error_message text,
  created_at timestamptz NOT NULL DEFAULT now(),
  completed_at timestamptz,
  reviewed_at timestamptz,
  review_decision text,
  review_reason text
);

CREATE TABLE IF NOT EXISTS lessons (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  task_id uuid REFERENCES nightshift_tasks(id),
  topic text NOT NULL,
  concept_category text NOT NULL,
  difficulty text NOT NULL DEFAULT 'beginner',
  what_changed text NOT NULL,
  why text NOT NULL,
  concept_explanation text NOT NULL,
  code_before text,
  code_after text,
  further_reading text[],
  vault_path text,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS learning_progress (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  lesson_id uuid NOT NULL REFERENCES lessons(id),
  viewed_at timestamptz NOT NULL DEFAULT now(),
  chat_messages int DEFAULT 0,
  understood boolean,
  quiz_score int
);

CREATE TABLE IF NOT EXISTS lesson_chats (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  lesson_id uuid NOT NULL REFERENCES lessons(id),
  role text NOT NULL,
  content text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);

-- Indexes
CREATE INDEX IF NOT EXISTS idx_nightshift_tasks_run_id ON nightshift_tasks(run_id);
CREATE INDEX IF NOT EXISTS idx_nightshift_tasks_status ON nightshift_tasks(status);
CREATE INDEX IF NOT EXISTS idx_lessons_task_id ON lessons(task_id);
CREATE INDEX IF NOT EXISTS idx_lesson_chats_lesson_id ON lesson_chats(lesson_id);
CREATE INDEX IF NOT EXISTS idx_learning_progress_lesson_id ON learning_progress(lesson_id);
