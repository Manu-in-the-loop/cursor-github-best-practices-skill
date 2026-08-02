---
name: github-distributed-workflow
description: Enforces GitHub best practices for distributed development, including strict branching, semantic commits, and Pull Request generation. Use whenever interacting with Git, committing code, or creating PRs.
---

# GitHub Distributed Workflow Rules

You are operating in a distributed development environment. Your primary goal when interacting with Git and GitHub is to make your work highly visible, easily auditable, and safe for human review.

A local hook (`git-guard.ps1`, installed separately — see this repo's README) mechanically blocks commits to `main`/`master`, hard force-pushes, and staged secrets as a backstop. Treat that as a safety net, not a substitute — follow every rule below proactively.

## Hard rules (never violate)

- Never work directly on `main` or `master`. Always branch first.
- Never commit secrets, credentials, or `.env*` files.
- Never force-push (`--force`/`-f`) a branch that has an open PR; use `--force-with-lease` only on your own unshared branch.
- Never amend a commit you did not create in the current session, or one that has already been pushed.
- Never merge your own PR, or claim CI passed, without actually checking.
- Never add a `Co-authored-by: Cursor` (or any other AI-agent) trailer to a commit. Commits are attributed solely to the human contributor's own configured git identity.

## 1. Branching strategy

- Always branch from the latest upstream `main` before starting work. Run `git fetch origin` and `git pull`.
- **Naming convention:** `<type>/<issue-number>-<short-description>` (e.g., `feat/142-auth-tokens`, `fix/89-race-condition`).
- Full detail, including worktree isolation for risky/exploratory changes: [references/BRANCHING.md](references/BRANCHING.md).

## 2. Verification (the pre-commit loop)

- **Test before commit:** run the project's test suite or linter before staging files. Do not commit failing code.
- **Diff review:** always run `git diff` before creating a commit. Verify you are not leaving behind debugging artifacts (e.g., `console.log`, temporary comments) or unrelated files.

## 3. Commit conventions

- Use Conventional Commits format: `type(scope): description`.
- Allowed types: `feat`, `fix`, `docs`, `style`, `refactor`, `test`, `chore`.
- **Keep commits atomic.** If a change does two different things, split it into two separate commits.
- Full detail, including single-author attribution and amend rules: [references/COMMITS.md](references/COMMITS.md).

## 4. Pull request generation

- When creating a PR (e.g., via `gh pr create`), you MUST include:
  - **Motivation:** why the change was made.
  - **Changes:** a high-level summary of what files/logic were altered.
  - **Testing:** explicit evidence of how the changes were verified (e.g., "Ran `npm test` successfully").
- Always link the relevant issue in the description (e.g., "Closes #142").
- Prefer several small, reviewable PRs over one large one.
- Verify CI is green (`gh pr checks`) before proposing a merge; never self-merge without explicit human confirmation.
- Full detail, including the PR body template and review process: [references/PULL_REQUESTS.md](references/PULL_REQUESTS.md).

## 5. Conflict resolution

- If you encounter a merge conflict, do NOT blindly accept "ours" or "theirs".
- Analyze the semantic intent of both changes.
- Propose and implement a resolution that preserves the intended functionality of both branches.
- Full detail: [references/CONFLICT_RESOLUTION.md](references/CONFLICT_RESOLUTION.md).

## Additional resources

- Security checklist and trust boundaries (sensitive files, push ownership): [references/SECURITY.md](references/SECURITY.md)
- Branching detail: [references/BRANCHING.md](references/BRANCHING.md)
- Commit detail: [references/COMMITS.md](references/COMMITS.md)
- Pull request detail: [references/PULL_REQUESTS.md](references/PULL_REQUESTS.md)
- Conflict resolution detail: [references/CONFLICT_RESOLUTION.md](references/CONFLICT_RESOLUTION.md)
