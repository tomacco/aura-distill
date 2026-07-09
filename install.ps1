# aura-distill installer (Windows / PowerShell)
# https://github.com/tomacco/aura-distill
#
# Usage:
#   irm https://raw.githubusercontent.com/tomacco/aura-distill/main/install.ps1 | iex

$ErrorActionPreference = 'Stop'

$Version  = '1.1.6'
$Build    = '20260515-01'
$Repo     = 'https://raw.githubusercontent.com/tomacco/aura-distill/main'

# Resolve home (works on PS 5.1 and PS 7+, Windows and cross-platform)
$ClaudeHome  = if ($env:USERPROFILE) { Join-Path $env:USERPROFILE '.claude' } else { Join-Path $HOME '.claude' }
$CmdDir      = Join-Path $ClaudeHome 'commands'
$DistillDir  = Join-Path $ClaudeHome 'distill'
$RulesDir    = Join-Path $ClaudeHome 'rules'
$ClaudeMd    = Join-Path $ClaudeHome 'CLAUDE.md'
$SettingsJson = Join-Path $ClaudeHome 'settings.json'

$EmDash = [char]0x2014
$DistillLine = @"
# Distill $EmDash knowledge system (github.com/tomacco/aura-distill)

GATE: If ~/.claude/distill/.needs-migration exists AND its content does not start with "migrated", tell the user: "Run /distill to migrate existing memories." Do NOT proceed until addressed or declined.
"@

# Enable ANSI escape sequences on Windows conhost when available
try {
    if ($PSVersionTable.PSVersion.Major -lt 6) {
        $Host.UI.RawUI.ForegroundColor = $Host.UI.RawUI.ForegroundColor  # touch to ensure VT init
    }
} catch {}

$ESC    = [char]27
$CYAN   = "$ESC[0;36m"
$PURPLE = "$ESC[0;35m"
$GREEN  = "$ESC[0;32m"
$RED    = "$ESC[0;31m"
$YELLOW = "$ESC[0;33m"
$DIM    = "$ESC[2m"
$BOLD   = "$ESC[1m"
$RESET  = "$ESC[0m"

function Write-Done  { param([string]$m) Write-Host "  ${GREEN}OK${RESET}  $m" }
function Write-Skip  { param([string]$m) Write-Host "  ${DIM} . ${RESET} $m" }
function Write-Warn  { param([string]$m) Write-Host "  ${YELLOW}!${RESET}  $m" }
function Write-Fail  { param([string]$m) Write-Host "  ${RED}x${RESET}  $m" }
function Write-Info  { param([string]$m) Write-Host "  ${CYAN}i${RESET}  $m" }

function Write-Header {
    Clear-Host
    Write-Host ''
    Write-Host "${PURPLE}        ,--------------------------------------."
    Write-Host '        |                                      |'
    Write-Host '        |      aura-distill                  |'
    Write-Host '        |                                      |'
    Write-Host "        '--------------------------------------'${RESET}"
    Write-Host ''
    Write-Host "  ${DIM}every session makes all sessions better${RESET}"
    Write-Host "  ${DIM}say what matters. it's listening.${RESET}"
    Write-Host ''
    Write-Host "  ${DIM}v$Version (build $Build)${RESET}"
    Write-Host ''
}

function Write-Section {
    param([string]$title)
    Write-Host ''
    Write-Host "  ${PURPLE}==${RESET} ${BOLD}$title${RESET}"
    Write-Host ''
}

function Get-File {
    param(
        [Parameter(Mandatory=$true)][string]$Url,
        [Parameter(Mandatory=$true)][string]$Destination
    )
    $parent = Split-Path -Parent $Destination
    if (-not (Test-Path $parent)) { New-Item -ItemType Directory -Force -Path $parent | Out-Null }
    # PS 5.1 requires -UseBasicParsing; harmless on PS 7+
    Invoke-WebRequest -Uri $Url -OutFile $Destination -UseBasicParsing
}

# === MAIN ===

Write-Header

# Detect existing installation
$existingVersion = ''
$versionFile = Join-Path $DistillDir '.version'
if (Test-Path $versionFile) {
    $existingVersion = (Get-Content $versionFile -Raw).Trim()
    Write-Info "Existing installation: v$existingVersion -> v$Version"
    Write-Host ''
}

Write-Section 'Core files'

# Ensure directories exist
foreach ($d in @($CmdDir, $DistillDir,
                 (Join-Path $DistillDir 'craft'),
                 (Join-Path $DistillDir 'ops'),
                 (Join-Path $DistillDir 'profile'),
                 (Join-Path $DistillDir 'projects'),
                 (Join-Path $DistillDir 'feedback'),
                 (Join-Path $DistillDir 'archive'))) {
    if (-not (Test-Path $d)) { New-Item -ItemType Directory -Force -Path $d | Out-Null }
}

Get-File "$Repo/distill.md"          (Join-Path $CmdDir 'distill.md')
Write-Done "distill.md ${DIM}(command)${RESET}"

Get-File "$Repo/distill-process.md"  (Join-Path $DistillDir 'distill-process.md')
Write-Done "distill-process.md ${DIM}(process engine)${RESET}"

Get-File "$Repo/distill-monitor.md"  (Join-Path $DistillDir 'distill-monitor.md')
Write-Done "distill-monitor.md ${DIM}(session monitor)${RESET}"

# Version
Set-Content -Path $versionFile -Value $Version -Encoding utf8 -NoNewline

# Spine
$spinePath = Join-Path $DistillDir 'SPINE.md'
if (-not (Test-Path $spinePath)) {
    $spine = @(
        '# Distill Knowledge Index',
        '',
        '<!-- This file is managed by aura-distill. Max 80 lines. -->',
        '<!-- Each entry: - [Title](path.md) -- when to read this -->'
    ) -join "`n"
    Set-Content -Path $spinePath -Value $spine -Encoding utf8
    Write-Done "SPINE.md ${DIM}(knowledge index)${RESET}"
} else {
    Write-Skip "SPINE.md ${DIM}(preserved)${RESET}"
}

# === KNOWLEDGE RETRIEVAL (rules file) ===

Write-Section 'Knowledge retrieval'

if (-not (Test-Path $RulesDir)) { New-Item -ItemType Directory -Force -Path $RulesDir | Out-Null }
Get-File "$Repo/rules/distill.md" (Join-Path $RulesDir 'distill.md')
Write-Done "rules/distill.md ${DIM}(auto-loads every session)${RESET}"

# === TOKEN SAVER (agent presets) ===
# Full control via env var (installer runs through `irm | iex`, so no CLI flags):
#   $env:DISTILL_TOKEN_SAVER = 'off'     -> skip/disable
#   $env:DISTILL_TOKEN_SAVER = 'remove'  -> remove the preset files
# The choice persists in distill/.token-saver across updates.
# What it is and why: https://tomacco.github.io/aura-distill/token-saving.html

Write-Section 'Token Saver'

$AgentsDir = Join-Path $ClaudeHome 'agents'
$TsMarker  = Join-Path $DistillDir '.token-saver'
$TokenSaver = if ($env:DISTILL_TOKEN_SAVER) { $env:DISTILL_TOKEN_SAVER.ToLower() } else { 'auto' }
if ($TokenSaver -eq 'auto' -and (Test-Path $TsMarker) -and ((Get-Content $TsMarker -Raw).Trim() -eq 'disabled')) {
    $TokenSaver = 'off'
}

function Install-TokenSaverAgent {
    param([string]$name)
    $target = Join-Path $AgentsDir "$name.md"
    if ((Test-Path $target) -and -not (Select-String -Path $target -Pattern 'aura-distill' -Quiet)) {
        Write-Warn "agents/$name.md exists and isn't ours -- preserved untouched"
        return
    }
    # Download to temp and validate before touching the target; never abort the
    # whole install on a failed optional download.
    $tmp = [System.IO.Path]::GetTempFileName()
    try {
        Get-File "$Repo/agents/$name.md" $tmp
        $body = Get-Content $tmp -Raw
        if ($body -match 'aura-distill' -and $body -match "name: $name") {
            Move-Item -Force $tmp $target
            Write-Done "agents/$name.md ${DIM}(preset subagent)${RESET}"
        } else {
            Remove-Item $tmp -Force -ErrorAction SilentlyContinue
            Write-Warn "agents/$name.md download invalid -- skipped (re-run the installer to retry)"
        }
    } catch {
        Remove-Item $tmp -Force -ErrorAction SilentlyContinue
        Write-Warn "agents/$name.md download failed -- skipped (re-run the installer to retry)"
    }
}

if ($TokenSaver -eq 'remove' -or $TokenSaver -eq 'off') {
    foreach ($a in @('scribe', 'scout')) {
        $t = Join-Path $AgentsDir "$a.md"
        if ((Test-Path $t) -and (Select-String -Path $t -Pattern 'aura-distill' -Quiet)) {
            Remove-Item $t -Force
            Write-Done "Removed agents/$a.md"
        }
    }
    Set-Content -Path $TsMarker -Value 'disabled' -Encoding utf8 -NoNewline
    Write-Skip "Token Saver ${DIM}(off -- enable anytime: `$env:DISTILL_TOKEN_SAVER='on'; re-run)${RESET}"
} else {
    if (-not (Test-Path $AgentsDir)) { New-Item -ItemType Directory -Force -Path $AgentsDir | Out-Null }
    Install-TokenSaverAgent 'scribe'
    Install-TokenSaverAgent 'scout'
    Set-Content -Path $TsMarker -Value 'enabled' -Encoding utf8 -NoNewline
    Write-Info 'Two lightweight subagent presets -- local files only, nothing is collected or sent anywhere.'
    Write-Info "What they do & the research: ${CYAN}https://tomacco.github.io/aura-distill/token-saving.html${RESET}"
    Write-Info "Not for you? ${DIM}`$env:DISTILL_TOKEN_SAVER='remove'; re-run the installer${RESET}"
}

# === SESSION INTEGRATION ===

Write-Section 'Session integration'

# Disable auto-memory (distill owns knowledge management)
if (Test-Path $SettingsJson) {
    try {
        $raw = Get-Content $SettingsJson -Raw
        $settings = $raw | ConvertFrom-Json
        if ($settings.PSObject.Properties.Name -contains 'autoMemoryEnabled') {
            Write-Skip 'Auto-memory already configured in settings.json'
        } else {
            $settings | Add-Member -NotePropertyName 'autoMemoryEnabled' -NotePropertyValue $false -Force
            $settings | ConvertTo-Json -Depth 20 | Set-Content -Path $SettingsJson -Encoding utf8
            Write-Done "Disabled auto-memory ${DIM}(distill owns knowledge)${RESET}"
        }
    } catch {
        Write-Warn "Could not parse $SettingsJson -- leaving untouched. Add `"autoMemoryEnabled`": false manually."
    }
} else {
    '{ "autoMemoryEnabled": false }' | Set-Content -Path $SettingsJson -Encoding utf8
    Write-Done 'Created settings.json with auto-memory disabled'
}

if (Test-Path $ClaudeMd) {
    $claudeMdContent = Get-Content $ClaudeMd -Raw
    if ($claudeMdContent -match 'aura-distill') {
        Write-Done "CLAUDE.md ${DIM}(already configured)${RESET}"
    } elseif ($claudeMdContent -match 'distill') {
        # Older reference -- strip lines containing 'distill', then append fresh block
        $cleaned = (Get-Content $ClaudeMd | Where-Object { $_ -notmatch 'distill' }) -join "`n"
        Set-Content -Path $ClaudeMd -Value ($cleaned + "`n`n" + $DistillLine) -Encoding utf8
        Write-Done "CLAUDE.md ${DIM}(upgraded)${RESET}"
    } else {
        Add-Content -Path $ClaudeMd -Value ("`n" + $DistillLine) -Encoding utf8
        Write-Done 'CLAUDE.md configured'
    }
} else {
    Set-Content -Path $ClaudeMd -Value $DistillLine -Encoding utf8
    Write-Done 'Created CLAUDE.md'
}

# === MEMORY MIGRATION CHECK ===

$memoryFiles = @()
if (Test-Path $ClaudeHome) {
    $memoryFiles = Get-ChildItem -Path $ClaudeHome -Filter '*.md' -Recurse -ErrorAction SilentlyContinue |
        Where-Object { $_.FullName -match '\\memory\\' -and $_.FullName -notmatch '\\distill\\' }
}
$migratedFlag = Join-Path $DistillDir '.migrated'
if ($memoryFiles.Count -gt 0 -and -not (Test-Path $migratedFlag)) {
    Write-Host ''
    Write-Host "  ${CYAN}==${RESET} ${BOLD}Existing memories detected${RESET}"
    Write-Host ''
    Write-Host "  Found ${BOLD}$($memoryFiles.Count)${RESET} memory files from Claude's built-in system."
    Write-Host "  Since distill now owns knowledge management, these won't be"
    Write-Host '  read by the auto-memory system anymore.'
    Write-Host ''
    Write-Host "  ${BOLD}On your next session, run ${CYAN}/distill${RESET}${BOLD} -- it will:${RESET}"
    Write-Host '    - Read your existing memories'
    Write-Host "    - Ingest them into distill's tiered system"
    Write-Host '    - Apply quality checks and proper categorization'
    Write-Host '    - Your old files stay untouched (as backup)'
    Write-Host ''
    $UtcNow = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
    Set-Content -Path (Join-Path $DistillDir '.needs-migration') -Value "pending $UtcNow" -NoNewline
}

# === COMPLETE ===

Write-Host ''
Write-Host ''
Write-Host "  ${GREEN}---------------------------------------${RESET}"
Write-Host ''
Write-Host "  ${GREEN}${BOLD}Installed${RESET}"
Write-Host "  ${DIM}Zero dependencies. Just files.${RESET}"
Write-Host ''
Write-Host "  ${DIM}Version:  ${RESET}v$Version"
Write-Host "  ${DIM}Command:  ${RESET}/distill"
Write-Host "  ${DIM}Knowledge:${RESET} $DistillDir"
Write-Host ''
if ($existingVersion) {
    Write-Host "  ${CYAN}Upgraded${RESET} v$existingVersion -> v$Version"
    Write-Host ''
    $TsAnnounced = Join-Path $DistillDir '.token-saver-announced'
    if ((Test-Path $TsMarker) -and ((Get-Content $TsMarker -Raw).Trim() -eq 'enabled') -and -not (Test-Path $TsAnnounced)) {
        Write-Host "  ${BOLD}${PURPLE}NEW $EmDash Token Saver${RESET}"
        Write-Host "  Two preset subagents (${BOLD}scribe${RESET}, ${BOLD}scout${RESET}) that skip the tool-schema tax:"
        Write-Host "  a text-only job now boots at ~2k tokens instead of ~19-27k. Local files only,"
        Write-Host "  fully yours, nothing collected. The 5-minute read on what changed and the"
        Write-Host "  research behind it: ${CYAN}https://tomacco.github.io/aura-distill/token-saving.html${RESET}"
        Write-Host "  ${DIM}Opt out anytime: `$env:DISTILL_TOKEN_SAVER='remove'; re-run the installer${RESET}"
        Write-Host ''
        Set-Content -Path $TsAnnounced -Value '1' -Encoding utf8 -NoNewline
    }
}
Write-Host "  ${DIM}Uninstall (keeps your learnings):${RESET}"
Write-Host "    ${DIM}Remove-Item -Recurse -Force `$HOME\.claude\distill, `$HOME\.claude\commands\distill.md, `$HOME\.claude\rules\distill.md${RESET}"
Write-Host ''
Write-Host "  ${PURPLE}say what matters. it's listening.${RESET}"
Write-Host ''
