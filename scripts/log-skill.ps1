# Devin skill-usage telemetry hook (Windows / PowerShell 5.1+).
# Reads the hook event JSON on stdin and, when it is a skill use, appends one
# JSON line (skill, user, time, ...) to a local file. Fails open: always exits
# 0 and prints nothing, so it can never block or alter the agent.
$ErrorActionPreference = 'Stop'
$logFile = if ($env:SKILL_TELEMETRY_FILE) { $env:SKILL_TELEMETRY_FILE } else { Join-Path $HOME '.devin\skill-telemetry\skill-usage.jsonl' }
$logDir = Split-Path -Parent $logFile
try {
    $raw = [Console]::In.ReadToEnd()
    if (-not $raw) { exit 0 }
    $evt = $raw | ConvertFrom-Json

    $skill = $null; $eventKind = $null; $plugin = $null; $skillPath = $null
    if ($evt.hook_event_name -eq 'PostToolUse' -and $evt.tool_name -match '^(skill_invoke|skill)$' -and $evt.tool_response.success -eq $true) {
        $skill = [string]$evt.tool_input.skill
        $eventKind = 'activated'
        if ($evt.tool_response.output -match '(?m)^Source:\s*(.+)$') { $skillPath = $Matches[1].Trim() }
        if (-not $skillPath -and $evt.tool_provenance) { $skillPath = $evt.tool_provenance.path }
        if ($skill -match '^([^:]+):(.+)$') { $plugin = $Matches[1] }
        elseif ($evt.tool_provenance) { $plugin = $evt.tool_provenance.plugin }
    } elseif ($evt.hook_event_name -eq 'UserPromptSubmit' -and $evt.prompt -match '^\s*/([A-Za-z0-9][A-Za-z0-9_:.\-]*)') {
        $skill = $Matches[1]
        $eventKind = 'user_invoked'
    }
    if (-not $skill) { exit 0 }
    if (-not $plugin -and $skill -match '^([^:]+):(.+)$') { $plugin = $Matches[1] }

    # Identity: explicit override > git author env > Devin git author file (cloud) > git config > OS user.
    $osUser = if ($env:USERDOMAIN) { "$($env:USERDOMAIN)\$($env:USERNAME)" } else { $env:USERNAME }
    $user = $env:SKILL_TELEMETRY_USER; $source = 'override'
    if (-not $user -and $env:GIT_AUTHOR_EMAIL) { $user = $env:GIT_AUTHOR_EMAIL; $source = 'git_author_env' }
    if (-not $user) {
        $devinDir = if ($env:DEVIN_DIR) { $env:DEVIN_DIR } else { 'C:\ProgramData\devin' }
        $ga = Join-Path $devinDir 'git_author'
        if (Test-Path $ga) {
            $m = Select-String -Path $ga -Pattern 'GIT_AUTHOR_EMAIL="?([^"\r\n]+)' | Select-Object -First 1
            if ($m) { $user = $m.Matches[0].Groups[1].Value; $source = 'devin_git_author' }
        }
    }
    if (-not $user -and (Get-Command git -ErrorAction SilentlyContinue)) {
        $g = (& git config --global user.email 2>$null)
        if ($g) { $user = "$g".Trim(); $source = 'git_config' }
    }
    if (-not $user) { $user = $osUser; $source = 'os_user' }

    $record = [ordered]@{
        timestamp   = [DateTimeOffset]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ss.fffZ')
        event       = 'skill_used'
        skill       = $skill
        event_kind  = $eventKind
        plugin      = [string]$plugin
        user        = $user
        user_source = $source
        os_user     = $osUser
        host        = $env:COMPUTERNAME
        session_id  = [string]$evt.session_id
        prompt_id   = [string]$evt.prompt_id
        hook_event  = [string]$evt.hook_event_name
        tool_use_id = [string]$evt.tool_use_id
        skill_path  = [string]$skillPath
        cwd         = [string]$env:DEVIN_PROJECT_DIR
    }
    $line = ConvertTo-Json -InputObject $record -Compress
    New-Item -ItemType Directory -Force -Path $logDir | Out-Null
    [IO.File]::AppendAllText($logFile, $line + "`n")
} catch {
    try {
        New-Item -ItemType Directory -Force -Path $logDir | Out-Null
        [IO.File]::AppendAllText((Join-Path $logDir 'errors.log'), "$([DateTimeOffset]::UtcNow.ToString('o')) $($_.Exception.Message)`n")
    } catch {}
}
exit 0
