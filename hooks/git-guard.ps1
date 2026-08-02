#!/usr/bin/env pwsh
# git-guard.ps1
#
# Deterministic backstop for the github-distributed-workflow Cursor skill.
# Runs as a beforeShellExecution hook matched against "git commit" / "git push".
# Blocks: commits to main/master, hard force-pushes, and staged secrets.
# Fails open (allows the command) on any unexpected error, since hooks.json
# sets "failClosed": false for this hook.

function Write-Result {
    param(
        [string]$Permission,
        [string]$AgentMessage,
        [string]$UserMessage
    )
    $result = @{ permission = $Permission }
    if ($AgentMessage) { $result.agent_message = $AgentMessage }
    if ($UserMessage) { $result.user_message = $UserMessage }
    Write-Output ($result | ConvertTo-Json -Compress)
}

function Allow {
    Write-Result -Permission 'allow'
    exit 0
}

function Deny {
    param([string]$AgentMessage, [string]$UserMessage)
    Write-Result -Permission 'deny' -AgentMessage $AgentMessage -UserMessage $UserMessage
    exit 0
}

try {
    # NOTE: Reading stdin via $input or [Console]::In on Windows PowerShell
    # decodes bytes using the console's InputEncoding, which defaults to the
    # legacy OEM codepage (e.g. CP437) when no real console is attached (as
    # is the case for a process spawned directly by Cursor). That mangles the
    # UTF-8 BOM Cursor prepends (and any non-ASCII content) before it ever
    # reaches ConvertFrom-Json. Reading the raw stdin stream directly and
    # decoding it explicitly as UTF-8 avoids this entirely.
    $rawStream = [Console]::OpenStandardInput()
    $reader = New-Object System.IO.StreamReader($rawStream, [System.Text.UTF8Encoding]::new($false))
    $stdin = $reader.ReadToEnd()
    if ([string]::IsNullOrWhiteSpace($stdin)) { Allow }

    # Defensively strip a leading BOM character too, in case it survives as
    # literal U+FEFF in some invocation contexts.
    $stdin = $stdin.TrimStart([char]0xFEFF)

    $data = $stdin | ConvertFrom-Json
    $command = $data.command
    if ([string]::IsNullOrWhiteSpace($command)) { Allow }

    # Hook scripts are spawned from ~/.cursor regardless of which project the
    # command targets, so all git diagnostics below MUST run against the
    # target repo's directory (from the payload), not the process's own cwd.
    # If neither is available (e.g. no workspace/folder open, or the command
    # changed directory via an inline `cd`/`Set-Location` instead of the
    # tool's own working-directory parameter), we cannot safely infer which
    # repo is being targeted. Silently falling back to the process's own
    # launch directory is unsafe if it happens to itself be a git repo (e.g.
    # a dotfiles repo at ~/.cursor) - it would evaluate the WRONG repo's
    # branch/staged changes. In that case, skip the checks and allow, per
    # this hook's documented fail-open behavior, rather than risk a
    # misleading pass/fail based on an unrelated repository.
    $targetDir = $data.cwd
    if ([string]::IsNullOrWhiteSpace($targetDir)) { $targetDir = $env:CURSOR_PROJECT_DIR }
    if ([string]::IsNullOrWhiteSpace($targetDir) -or -not (Test-Path -LiteralPath $targetDir)) { Allow }
    Set-Location -LiteralPath $targetDir

    # 1. Block commits directly to main/master.
    if ($command -match 'git\s+commit') {
        $branch = $null
        try { $branch = (git branch --show-current 2>$null) } catch { $branch = $null }
        if ($branch) { $branch = $branch.Trim() }

        if ($branch -eq 'main' -or $branch -eq 'master') {
            Deny `
                "Blocked by git-guard: attempted to commit directly to '$branch'. Create a feature branch first, e.g. git checkout -b feat/<issue>-<short-description>, per the github-distributed-workflow skill." `
                "git-guard blocked a commit to '$branch'. Create and switch to a feature branch before committing."
        }
    }

    # 2. Block hard force-pushes (allow --force-with-lease).
    if ($command -match 'git\s+push' -and $command -match '(^|\s)(--force(?!-with-lease)|-f)(\s|$)') {
        Deny `
            "Blocked by git-guard: hard force-push detected ('--force'/'-f'). Never force-push a branch with an open PR. If this branch is exclusively yours and a rewrite is truly needed, use --force-with-lease instead." `
            "git-guard blocked a hard force-push. Use --force-with-lease if you own this branch exclusively, and never force-push a shared branch."
    }

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
    if ($command -match 'git\s+commit') {
        $diff = $null
        try { $diff = (git diff --cached 2>$null) -join "`n" } catch { $diff = '' }

        $stagedFiles = @()
        try { $stagedFiles = (git diff --cached --name-only 2>$null) } catch { $stagedFiles = @() }

        # Extract file path arguments from any `git add ...` invocations in
        # this command so their current on-disk content can be scanned too.
        $addedFiles = @()
        $addMatches = [regex]::Matches($command, 'git\s+add\s+([^\n\r]+)')
        foreach ($m in $addMatches) {
            $argLine = $m.Groups[1].Value
            $tokens = $argLine -split '\s+' | Where-Object { $_ -and $_ -notmatch '^-' }
            foreach ($t in $tokens) {
                $addedFiles += ($t.Trim('"', "'"))
            }
        }

        $onDiskContent = @()
        foreach ($f in ($addedFiles | Select-Object -Unique)) {
            if ($f -eq '.' -or $f -eq '*') { continue }
            $full = Join-Path -Path (Get-Location) -ChildPath $f
            if (Test-Path -LiteralPath $full -PathType Leaf) {
                try { $onDiskContent += (Get-Content -LiteralPath $full -Raw -ErrorAction Stop) } catch {}
            }
        }

        $secretPatterns = @(
            'AKIA[0-9A-Z]{16}',                                       # AWS access key
            'gh[pousr]_[A-Za-z0-9]{20,}',                             # GitHub token
            'xox[baprs]-[A-Za-z0-9-]{10,}',                           # Slack token
            '-----BEGIN[ A-Z]*PRIVATE KEY-----',                      # Private key block
            '(?i)(password|secret|token|api_key)\s*[:=]\s*[''"][^''"]{8,}[''"]'  # Generic assigned secret
        )

        $scanTargets = @($diff, $command) + $onDiskContent
        $matchedPatterns = @()
        foreach ($pattern in $secretPatterns) {
            foreach ($target in $scanTargets) {
                if ($target -and ($target -match $pattern)) {
                    $matchedPatterns += $pattern
                    break
                }
            }
        }

        $envFiles = @($stagedFiles | Where-Object { $_ -match '(^|[\\/])\.env(\..+)?$' })
        $envFiles += @($addedFiles | Where-Object { $_ -match '(^|[\\/])\.env(\..+)?$' })
        $envFiles = @($envFiles | Select-Object -Unique)

        if ($matchedPatterns.Count -gt 0 -or $envFiles.Count -gt 0) {
            $reasons = @()
            if ($matchedPatterns.Count -gt 0) { $reasons += "possible secret pattern(s) found" }
            if ($envFiles.Count -gt 0) { $reasons += ".env file(s) staged: $($envFiles -join ', ')" }
            $reasonText = $reasons -join '; '

            Deny `
                "Blocked by git-guard: potential secret detected in this commit ($reasonText). Unstage the affected file(s) and confirm explicitly with the user before committing if this is a false positive." `
                "git-guard flagged a possible secret in this commit ($reasonText). Please review before continuing."
        }
    }

    Allow
}
catch {
    # Never let a bug in this script block legitimate git usage.
    Allow
}
