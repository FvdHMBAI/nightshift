# Changelog

All notable changes to Night Shift will be documented in this file.

## [0.3.0] - 2026-08-02

### Added
- Test suite (`tests/test-nightshift.sh`) covering config parsing, helper functions, lock mechanism, task categories, schema validation, and language checks
- GitHub Actions CI with shellcheck, tests, and English-only enforcement
- Example files: morning report, crontab configurations, multi-repo setup
- Architecture diagram in README
- Comparison table: Night Shift vs Devin vs CodeRabbit vs Sweep
- FAQ section in README
- Extending Night Shift guide for custom task categories

### Changed
- README rewritten for competitive positioning and clarity
- Worker resolves repo paths from REPOS array (supports absolute paths)
- Improved stash handling with recovery instructions on failure

## [0.2.0] - 2026-08-01

### Added
- Lesson generator for educational content from completed fixes
- Morning summary with automatic catch-up for missed summaries
- ntfy.sh notification support
- Install script with dependency checks and cron setup
- Security fix fallback: individual package upgrades when `npm audit fix` is ineffective
- Build verification (Next.js) after dependency updates
- RAM monitoring with configurable threshold
- Task timeout with TERM signal handling
- LLM output length guard for docs fixes

### Changed
- Worker stashes uncommitted changes instead of skipping repos
- Security fixes include TypeScript compilation check with rollback

## [0.1.0] - 2026-07-25

### Added
- Initial release
- Coordinator with multi-repo scanning
- Worker with lint-fix, type-fix, security, docs categories
- PostgreSQL schema for runs, tasks, lessons
- Ollama integration for local LLM analysis
- Claude API support (optional)
- Branch-per-fix workflow with backup tags
- Lockfile-based concurrency prevention
