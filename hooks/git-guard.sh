#!/usr/bin/env bash
# git-guard.sh
#
# Deterministic backstop for the github-distributed-workflow Cursor skill.
# Runs as a beforeShellExecution hook matched against "git commit" / "git push".
# Blocks: commits to main/master, hard force-pushes, and staged secrets.
# Fails open (allows the command) on any unexpected error, since hooks.json
# sets "failClosed": false for this hook.
#
# Compatible with bash 3.2+ (macOS /bin/bash) and bash 4+/5 (Homebrew/Linux).
# JSON parse/emit prefers python3, then jq; fails open if neither is available.

set +e

allow() {
  trap - EXIT ERR
  printf '%s\n' '{"permission":"allow"}'
  exit 0
}

# Emit a deny result. Arguments: agent_message, user_message.
deny() {
  trap - EXIT ERR
  local agent_message="$1"
  local user_message="$2"

  if command -v python3 >/dev/null 2>&1; then
    AGENT_MESSAGE="$agent_message" USER_MESSAGE="$user_message" python3 - <<'PY'
import json, os
print(json.dumps({
    "permission": "deny",
    "agent_message": os.environ["AGENT_MESSAGE"],
    "user_message": os.environ["USER_MESSAGE"],
}, separators=(",", ":")))
PY
  elif command -v jq >/dev/null 2>&1; then
    jq -nc --arg a "$agent_message" --arg u "$user_message" \
      '{permission:"deny",agent_message:$a,user_message:$u}'
  else
    # Minimal fallback escaper (messages are plain ASCII prose).
    json_escape() {
      local s=$1
      s=${s//\\/\\\\}
      s=${s//\"/\\\"}
      s=${s//$'\n'/\\n}
      s=${s//$'\r'/\\r}
      s=${s//$'\t'/\\t}
      printf '%s' "$s"
    }
    printf '{"permission":"deny","agent_message":"%s","user_message":"%s"}\n' \
      "$(json_escape "$agent_message")" \
      "$(json_escape "$user_message")"
  fi
  exit 0
}

# Fail open on unexpected errors / early exits from the main body.
trap 'allow' ERR
trap 'allow' EXIT

# --- Read and parse stdin JSON (UTF-8, optional BOM) ----------------------
stdin=$(cat)
if [ -z "$(printf '%s' "$stdin" | tr -d '[:space:]')" ]; then
  allow
fi

# Strip UTF-8 BOM if present.
stdin="${stdin#$'\xEF\xBB\xBF'}"

command=""
target_dir=""

if command -v python3 >/dev/null 2>&1; then
  eval "$(COMMAND_JSON="$stdin" python3 - <<'PY'
import json, os, shlex, sys
raw = os.environ.get("COMMAND_JSON", "").lstrip("\ufeff").strip()
if not raw:
    sys.exit(0)
data = json.loads(raw)
print("command=" + shlex.quote(data.get("command") or ""))
print("target_dir=" + shlex.quote(data.get("cwd") or ""))
PY
)" || allow
elif command -v jq >/dev/null 2>&1; then
  command=$(printf '%s' "$stdin" | jq -r '.command // empty') || allow
  target_dir=$(printf '%s' "$stdin" | jq -r '.cwd // empty') || true
else
  # No JSON tool available — fail open.
  allow
fi

if [ -z "$(printf '%s' "$command" | tr -d '[:space:]')" ]; then
  allow
fi

# Hook scripts are spawned from ~/.cursor regardless of which project the
# command targets, so all git diagnostics below MUST run against the
# target repo's directory (from the payload), not the process's own cwd.
# If neither is available, skip the checks and allow (fail-open) rather
# than risk evaluating the wrong repository.
if [ -z "$target_dir" ]; then
  target_dir="${CURSOR_PROJECT_DIR:-}"
fi
if [ -z "$target_dir" ] || [ ! -d "$target_dir" ]; then
  allow
fi
cd -- "$target_dir" || allow

# 1. Block commits directly to main/master.
if printf '%s' "$command" | grep -Eq 'git[[:space:]]+commit'; then
  branch=$(git branch --show-current 2>/dev/null | tr -d '[:space:]') || branch=""
  if [ "$branch" = "main" ] || [ "$branch" = "master" ]; then
    deny \
      "Blocked by git-guard: attempted to commit directly to '${branch}'. Create a feature branch first, e.g. git checkout -b feat/<issue>-<short-description>, per the github-distributed-workflow skill." \
      "git-guard blocked a commit to '${branch}'. Create and switch to a feature branch before committing."
  fi
fi

# 2. Block hard force-pushes (allow --force-with-lease).
# Strip --force-with-lease first so a remaining --force / -f token is a deny.
if printf '%s' "$command" | grep -Eq 'git[[:space:]]+push'; then
  normalized=$(printf '%s' "$command" | sed 's/--force-with-lease//g')
  if printf '%s' "$normalized" | grep -Eq '(^|[[:space:]])--force([[:space:]]|$)' || \
     printf '%s' "$normalized" | grep -Eq '(^|[[:space:]])-f([[:space:]]|$)'; then
    deny \
      "Blocked by git-guard: hard force-push detected (--force/-f). Never force-push a branch with an open PR. If this branch is exclusively yours and a rewrite is truly needed, use --force-with-lease instead." \
      "git-guard blocked a hard force-push. Use --force-with-lease if you own this branch exclusively, and never force-push a shared branch."
  fi
fi

# 3. Scan for likely secrets before allowing a commit.
#
# IMPORTANT: beforeShellExecution evaluates the *entire* multi-line
# command as one unit BEFORE any of it runs. If `git add` and
# `git commit` are batched into the same call (a very common pattern),
# `git diff --cached` at hook time still reflects the PRE-add state, so
# checking only already-staged content misses newly-added files. To
# compensate, this also scans: (a) the raw command text itself, which
# catches secrets being freshly written to a file inline in the same
# command, and (b) the on-disk content of any file path arguments passed
# to `git add` within this command, which catches files already written
# to disk (e.g. by an earlier edit) that are about to be staged+committed
# together.
if printf '%s' "$command" | grep -Eq 'git[[:space:]]+commit'; then
  diff=$(git diff --cached 2>/dev/null) || diff=""
  staged_files=$(git diff --cached --name-only 2>/dev/null) || staged_files=""

  # Extract file path arguments from any `git add ...` invocations.
  # Split shell chaining operators onto separate lines first so multiple
  # `git add` calls in one compound command are each matched.
  added_files=""
  normalized_cmd=$(printf '%s\n' "$command" | sed -E 's/[[:space:]]*&&[[:space:]]*/\n/g; s/[[:space:]]*\|\|[[:space:]]*/\n/g; s/[[:space:]]*;[[:space:]]*/\n/g')
  add_lines=$(printf '%s\n' "$normalized_cmd" | grep -oE 'git[[:space:]]+add[[:space:]]+.+' || true)
  while IFS= read -r add_line || [ -n "$add_line" ]; do
    [ -z "$add_line" ] && continue
    add_args=$(printf '%s' "$add_line" | sed -E 's/^git[[:space:]]+add[[:space:]]+//')
    # Iterate whitespace-separated tokens; skip flags. Disable globbing so a
    # literal "*" argument is not expanded by the shell during word-splitting.
    old_ifs=$IFS
    IFS=$' \t'
    set -f
    # shellcheck disable=SC2086
    set -- $add_args
    set +f
    IFS=$old_ifs
    for t in "$@"; do
      case "$t" in
        -*) continue ;;
      esac
      # Strip surrounding quotes if present.
      t="${t#\"}"; t="${t%\"}"
      t="${t#\'}"; t="${t%\'}"
      [ -z "$t" ] && continue
      # Deduplicate via newline-delimited list.
      if ! printf '%s\n' "$added_files" | grep -Fxq -- "$t"; then
        added_files="${added_files}${t}"$'\n'
      fi
    done
  done <<EOF
$add_lines
EOF

  on_disk_content=""
  while IFS= read -r f; do
    [ -z "$f" ] && continue
    [ "$f" = "." ] || [ "$f" = "*" ] && continue
    if [ -f "$f" ]; then
      on_disk_content="${on_disk_content}$(cat "$f" 2>/dev/null || true)"$'\n'
    fi
  done <<EOF
$added_files
EOF

  matched=0
  # Use grep -e/-- so patterns starting with '-' (private keys) are not
  # misread as options by BSD grep on macOS.
  # AWS access key
  for target in "$diff" "$command" "$on_disk_content"; do
    [ -z "$target" ] && continue
    if printf '%s' "$target" | grep -Eqe 'AKIA[0-9A-Z]{16}'; then matched=1; break; fi
  done
  # GitHub token
  if [ "$matched" -eq 0 ]; then
    for target in "$diff" "$command" "$on_disk_content"; do
      [ -z "$target" ] && continue
      if printf '%s' "$target" | grep -Eqe 'gh[pousr]_[A-Za-z0-9]{20,}'; then matched=1; break; fi
    done
  fi
  # Slack token
  if [ "$matched" -eq 0 ]; then
    for target in "$diff" "$command" "$on_disk_content"; do
      [ -z "$target" ] && continue
      if printf '%s' "$target" | grep -Eqe 'xox[baprs]-[A-Za-z0-9-]{10,}'; then matched=1; break; fi
    done
  fi
  # Private key block
  if [ "$matched" -eq 0 ]; then
    for target in "$diff" "$command" "$on_disk_content"; do
      [ -z "$target" ] && continue
      if printf '%s' "$target" | grep -Eqe '-----BEGIN[ A-Z]*PRIVATE KEY-----'; then matched=1; break; fi
    done
  fi
  # Generic assigned secret (case-insensitive)
  # ANSI-C quoting so single/double quotes in the character class are literal.
  generic_secret_re=$'(password|secret|token|api_key)[[:space:]]*[:=][[:space:]]*[\'"][^\'"]{8,}[\'"]'
  if [ "$matched" -eq 0 ]; then
    for target in "$diff" "$command" "$on_disk_content"; do
      [ -z "$target" ] && continue
      if printf '%s' "$target" | grep -Eiqe "$generic_secret_re"; then
        matched=1
        break
      fi
    done
  fi

  env_files=""
  while IFS= read -r f; do
    [ -z "$f" ] && continue
    # Match paths whose basename is .env or .env.<anything>
    # (equivalent to (^|[/\\])\.env(\..+)?$).
    base=$(basename "$f")
    if [ "$base" = ".env" ] || printf '%s' "$base" | grep -Eq '^\.env\.'; then
      if ! printf '%s\n' "$env_files" | grep -Fxq -- "$f"; then
        env_files="${env_files}${f}"$'\n'
      fi
    fi
  done <<EOF
$staged_files
$added_files
EOF

  env_count=0
  env_list=""
  while IFS= read -r f; do
    [ -z "$f" ] && continue
    env_count=$((env_count + 1))
    if [ -z "$env_list" ]; then
      env_list="$f"
    else
      env_list="${env_list}, ${f}"
    fi
  done <<EOF
$env_files
EOF

  if [ "$matched" -gt 0 ] || [ "$env_count" -gt 0 ]; then
    reasons=""
    if [ "$matched" -gt 0 ]; then
      reasons="possible secret pattern(s) found"
    fi
    if [ "$env_count" -gt 0 ]; then
      if [ -n "$reasons" ]; then
        reasons="${reasons}; .env file(s) staged: ${env_list}"
      else
        reasons=".env file(s) staged: ${env_list}"
      fi
    fi

    deny \
      "Blocked by git-guard: potential secret detected in this commit (${reasons}). Unstage the affected file(s) and confirm explicitly with the user before committing if this is a false positive." \
      "git-guard flagged a possible secret in this commit (${reasons}). Please review before continuing."
  fi
fi

allow
