# Commit Conventions

## Verification (the pre-commit loop)

- **Test before commit:** run the project's test suite or linter before staging files. Do not commit failing code.
- **Diff review:** always run `git diff` (or `git diff --cached` once staged) to review your own changes before creating a commit. Verify you are not leaving behind debugging artifacts (e.g., `console.log`, temporary comments) or unrelated/unintended files.

## Format

Use Conventional Commits format: `type(scope): description`.

| Type | Use for |
|------|---------|
| `feat` | New feature |
| `fix` | Bug fix |
| `docs` | Documentation only |
| `style` | Formatting, no logic change |
| `refactor` | Code restructuring, no behavior change |
| `test` | Adding or updating tests |
| `chore` | Build process, tooling, dependencies |

- Subject line: imperative mood, scoped, under ~72 characters — e.g. `fix(cart): correct total when last coupon is removed`.
- Body: explain **why**, not what — the diff already shows what changed.

## Atomicity

**Keep commits atomic.** If a change does two different things, split it into two separate commits. Each commit should represent one logical, reviewable unit that could be reverted independently.

## Attribution: single-author commits only

**Never add a `Co-authored-by: Cursor`, `Co-authored-by: Cursor Agent`, or any other AI-agent trailer to a commit.** Commits are attributed solely to the human contributor whose repository/session this is — using the identity already configured via `git config user.name` / `user.email`. Do not introduce a second author, bot, or agent identity into the commit metadata or message body.

If a tool or IDE feature auto-inserts such a trailer, treat it as unwanted and remove it from the commit message before finalizing (e.g., edit the message during `git commit` rather than accepting an auto-populated trailer line).

Do not attempt line- or commit-level AI attribution at all — the repository's contributor history should read as the work of its owner.

## Amending

Only amend a commit if **both** are true:
- You created it in the current session, **and**
- It has not been pushed anywhere yet.

Never amend a commit you didn't just create, and never amend a commit that's already been pushed — amending rewrites history and can silently break a collaborator's branch.

## Examples

**Input:** Added user authentication with JWT tokens
```
feat(auth): implement JWT-based authentication

Add login endpoint and token validation middleware.
```

**Input:** Fixed bug where dates displayed incorrectly
```
fix(reports): correct date formatting in timezone conversion

Use UTC timestamps consistently across report generation.
```
