# Security and Trust Boundaries

## Never commit secrets

Never stage or commit:
- API keys, access tokens, passwords, or private keys, whether hardcoded or in a variable assignment.
- `.env`, `.env.local`, or any other environment file containing real values.
- Cloud provider credential files (AWS `credentials`/`config`, GCP service account JSON, Azure profile files).
- `-----BEGIN ... PRIVATE KEY-----` blocks of any kind.

Before staging, mentally re-check any file that looks configuration- or credential-shaped. A local hook also scans staged diffs for common secret signatures as a backstop — see this repo's README — but do not rely on it as your only check.

## Sensitive files require explicit confirmation

Treat the following as requiring explicit human confirmation before modifying, even when a task seems to imply it:
- CI/CD workflow files (`.github/workflows/**`, `.gitlab-ci.yml`, etc.) — these control what runs with repo credentials and are a common supply-chain attack target.
- Branch protection / repository settings.
- `CODEOWNERS`, security policies, and dependency lockfiles when the change isn't the explicit purpose of the task.

If a task seems to require touching one of these, say so explicitly and confirm before proceeding, rather than doing it silently as a side effect.

## Trust boundary for push

- You may commit on your own feature branch and push it.
- **Never force-push (`--force`/`-f`) a branch that has an open PR** or that other people may have already pulled. If a history rewrite is genuinely needed on a branch you own exclusively, use `--force-with-lease`, not `--force`.
- Always state the remote and branch name before pushing (`git remote -v`, `git branch --show-current`) so a mistake is visible before it lands.
- Never push directly to `main`/`master` under any circumstance — all changes land there via a reviewed pull request.

## Human-in-the-loop merge gate

Automated checks (linting, tests, secret scans) are a first line of defense, not a replacement for review. Even when all checks are green:
- Never merge a PR without explicit human approval.
- Surface scan/check results to the human reviewer rather than deciding on their behalf.
