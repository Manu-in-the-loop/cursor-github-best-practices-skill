# cursor-github-best-practices-skill

A [Cursor](https://cursor.com) Agent Skill + Hook pair that enforces safe, auditable Git and GitHub practices for distributed projects with multiple contributors, across every project on your machine.

## What it is

Two complementary pieces that work together:

- **`skills/github-distributed-workflow/`**: an Agent Skill teaching Cursor the judgment-based rules of a good Git/GitHub workflow: branching strategy, Conventional Commits, pull request structure, and semantic merge conflict resolution.
- **`hooks/`**: a Cursor Hook that mechanically enforces the three riskiest failure modes (committing to `main`, force-pushing a shared branch, committing a secret) so the rules hold even if the agent's instructions get overridden or ignored.

## How it's used

Once installed, the skill **auto-invokes**, so you never need to ask Cursor to "use the github skill." It automatically applies whenever the agent runs `git`, creates a commit, or opens a pull request, in any project. Its hard rules (never work on `main`, never commit secrets, never force-push a PR branch, test before committing, verify CI before merging) are summarized in [`SKILL.md`](skills/github-distributed-workflow/SKILL.md), which links out to detailed guidance in `references/` for branching, commits, pull requests, security, and conflict resolution.

## How it works

This repo implements a two-layer safety model, because instructions alone are advisory:

1. **Instructional layer (the skill).** Cursor reads `SKILL.md` (and the linked reference files) for anything requiring judgment: how to name a branch, what a good PR description looks like, how to resolve a merge conflict without blindly picking a side.
2. **Deterministic layer (the hook).** `git-guard.ps1` runs *before* any `git commit`/`git push` the agent attempts, and mechanically denies the action, regardless of what the agent "decided", if it detects:
   - a commit being made directly on `main` or `master`,
   - a hard force-push (`--force`/`-f`, as opposed to `--force-with-lease`),
   - a staged secret (common API key/token patterns, private key blocks, or a staged `.env*` file).

The hook is a backstop, not a substitute for judgment: it catches the three most dangerous mistakes deterministically, while the skill covers everything else.

## Cursor-specific features used

- **Agent Skills**: `SKILL.md` YAML frontmatter (`name`, `description`) for auto-discovery, auto-invocation (no `disable-model-invocation` flag, so the skill loads on relevant context rather than only when named), and progressive disclosure via a `references/` folder so `SKILL.md` stays short while detailed guidance is a click away.
- **Cursor Hooks**: `hooks.json` registers a `beforeShellExecution` hook matched against `git (commit|push)` commands. The hook script communicates over stdin/stdout JSON and returns a `permission` (`allow`/`deny`) with an `agent_message` (shown to the agent) and `user_message` (shown to you). `failClosed: false` means a bug in the hook script fails open, so it will never accidentally block legitimate git usage.

## Repo structure

```
cursor-github-best-practices-skill/
├── skills/
│   └── github-distributed-workflow/
│       ├── SKILL.md                    # Auto-invoked rules + links to reference files
│       └── references/
│           ├── BRANCHING.md
│           ├── COMMITS.md
│           ├── PULL_REQUESTS.md
│           ├── SECURITY.md
│           └── CONFLICT_RESOLUTION.md
└── hooks/
    ├── hooks.json                      # beforeShellExecution registration
    └── git-guard.ps1                   # Deterministic enforcement (PowerShell)
```

## Install

This is a **personal** skill/hook pair, meant to apply across all of your projects, so install it under your Cursor user directory (`~/.cursor/`), not inside a single repo.

0. Clone this repo and `cd` into it (the commands below use paths relative to the repo root):

   ```powershell
   git clone https://github.com/Manu-in-the-loop/cursor-github-best-practices-skill.git
   Set-Location cursor-github-best-practices-skill
   ```

1. Copy the skill folder:

   ```powershell
   Copy-Item -Recurse -Force "skills\github-distributed-workflow" "$env:USERPROFILE\.cursor\skills\github-distributed-workflow"
   ```

2. Copy the hook script:

   ```powershell
   New-Item -ItemType Directory -Force "$env:USERPROFILE\.cursor\hooks" | Out-Null
   Copy-Item -Force "hooks\git-guard.ps1" "$env:USERPROFILE\.cursor\hooks\git-guard.ps1"
   ```

3. Install `hooks.json`:
   - If you don't already have `$env:USERPROFILE\.cursor\hooks.json`, copy `hooks\hooks.json` there directly.
   - If you already have one, merge the `beforeShellExecution` entry from `hooks\hooks.json` into your existing file instead of overwriting it.

4. Restart Cursor (or check the **Hooks** settings tab) to confirm the hook loaded.

## Notes

- The hook script is PowerShell (native to Windows, no bash/WSL/Node dependency). If you're on macOS/Linux, port the logic in `git-guard.ps1` to a shell script and update the `command` in `hooks.json` accordingly.
- This skill/hook pair does not replace server-side protection. Enable branch protection rules / rulesets on your GitHub repositories (requiring PRs and passing checks before merging to `main`); that is the one control that holds even outside of Cursor.
- **Keep a project folder open.** `git-guard.ps1` decides which repo to check using the `cwd` Cursor includes in the hook payload. If no project folder is open (e.g. an empty chat window), or the agent changes directories with an inline `cd`/`Set-Location` instead of the tool's own working-directory setting, Cursor may not supply a usable `cwd`. The script is deliberately fail-open in that case (it allows the command rather than risk checking the wrong repo), so its protection only applies with a project folder open and a `cwd` present.

## Context/prompt overhead

Cursor loads skills via progressive disclosure: only a skill's `name`/`description` sits in context at all times; the full body and `references/` load only when actually relevant. Measured with `tiktoken` (`cl100k_base`) against this repo's files, plus real timings from the Cursor Hooks log:

| Cost | When it's paid | Size |
| --- | --- | --- |
| Idle (registry entry) | Every session, git work or not | 47 tokens |
| Active (`SKILL.md` body) | Only when the agent is doing git/PR work | 917 tokens |
| Worst case (+ all 5 `references/*.md`) | Rare, usually only 1-2 are needed | ~3,000 tokens |
| Hook (`git-guard.ps1`) | N/A, runs as an external process | 0 tokens |
| Hook latency | Only on `git commit`/`git push` | ~2s (PowerShell process spawn) |

47 idle tokens is smaller than this sentence, and the ~3K-token worst case is a one-time, occasional cost against a 200K-token context window (Cursor's default for Claude Sonnet/Opus models, per [Cursor's models & pricing docs](https://cursor.com/docs/models-and-pricing), up to 1M with Max Mode), not a per-message tax. The hook never touches the LLM context at all.

## License

[MIT](LICENSE)
