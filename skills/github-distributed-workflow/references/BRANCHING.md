# Branching Strategy

## Core rules

- **Never work on `main`.**
- Always branch from the latest upstream `main` before starting work. Run `git fetch origin` and `git pull`.
- **Naming convention:** `<type>/<issue-number>-<short-description>` (e.g., `feat/142-auth-tokens`, `fix/89-race-condition`).

## Isolation for risky or exploratory work

- If a change is exploratory (an approach that might not pan out) or higher-risk, prefer creating it on its own dedicated branch rather than layering it onto an existing feature branch. This gives a clean rollback point without losing unrelated work.
- Where the environment supports it, use a separate git worktree per parallel line of work so one line of work cannot accidentally leak into another checkout's working tree.

## Before pushing

- Confirm the remote and branch name before pushing: run `git remote -v` and `git branch --show-current` (or state them explicitly) so a typo in the target is caught before it lands, rather than after.
- Never push directly to `main`/`master`. All changes land there via a reviewed pull request.

## Verifying branch state

Run `git status` and `git branch --show-current` before staging or committing anything, especially after switching context (e.g., resuming a session). Do not assume you're still on the branch you created earlier without checking.
