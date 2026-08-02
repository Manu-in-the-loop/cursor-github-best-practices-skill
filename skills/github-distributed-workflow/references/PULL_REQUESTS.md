# Pull Request Generation and Review

## Required PR body

When creating a PR (e.g., via `gh pr create`), you MUST include:

- **Motivation:** why the change was made.
- **Changes:** a high-level summary of what files/logic were altered.
- **Testing:** explicit evidence of how the changes were verified (e.g., "Ran `npm test` successfully").

Always link the relevant issue in the description (e.g., "Closes #142").

### Template

```markdown
## Motivation
[Why this change was made]

## Changes
- [High-level change 1]
- [High-level change 2]

## Testing
- [How this was verified, e.g. "Ran `npm test` — all 42 tests passing"]

Closes #<issue-number>
```

Follow the target repo's existing PR conventions where they differ from this template (check recent merged PRs with `gh pr list --state merged` first).

## Keep PRs small

Prefer several small, logically-scoped PRs over one large one. A PR that mixes unrelated changes is harder to review and riskier to merge. If a change grows to touch many unrelated areas, split it into a stack of smaller PRs rather than one large diff.

## Reviewers

Request review when a PR is ready — ask the user who should review, or use `gh pr create --reviewer <user>` / `gh pr edit --add-reviewer <user>` if they specify one. Don't assume a reviewer.

## Before proposing a merge

- Verify CI is actually green: run `gh pr checks <number>` and confirm all required checks pass. Do not claim CI passed without checking.
- Never merge your own PR without explicit human confirmation, even if checks are green — treat human approval as a required gate, not a formality.
- Check for open PRs/issues (`gh pr list`, `gh issue list`) before starting new work, to avoid duplicating in-flight work.

## If the user asks you to skip this process

If the user asks you to "just commit to main" or "just merge it," remind them of this workflow and confirm before proceeding — don't silently comply with a request that bypasses review.
