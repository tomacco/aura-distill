# aura-distill installer (Windows / PowerShell)
# https://github.com/tomacco/aura-distill
#
# Usage:
#   irm https://raw.githubusercontent.com/tomacco/aura-distill/main/install.ps1 | iex
#
# Release channel (docs/adr/0002), persisted in the knowledge directory:
#   $env:DISTILL_CHANNEL = 'beta'    -> opt in to published beta releases
#   $env:DISTILL_CHANNEL = 'stable'  -> back to the stable line (the default)

$ErrorActionPreference = 'Stop'

$Version  = '1.1.23'
$Build    = '20260515-01'
$RawRoot  = if ($env:AURA_DISTILL_RAW_ROOT) { $env:AURA_DISTILL_RAW_ROOT } else { 'https://raw.githubusercontent.com/tomacco/aura-distill' }
$BetaManifest = if ($env:AURA_DISTILL_CHANNEL_MANIFEST) { $env:AURA_DISTILL_CHANNEL_MANIFEST } else { "$RawRoot/beta/1.2/channels/manifest.json" }
$Repo     = if ($env:AURA_DISTILL_REPO) { $env:AURA_DISTILL_REPO } else { "$RawRoot/main" }
# This installer belongs to the files-only line with this major version. It never
# installs another major without typed consent, and never a software edition.
$LineMajor = 1
$SoftwareMarker = 'AURA_SOFTWARE_' + 'MAJOR_PAYLOAD'
$Placeholder = '{DISTILL' + '_DIR}'

# Resolve home (works on PS 5.1 and PS 7+, Windows and cross-platform)
$ClaudeHome  = if ($env:USERPROFILE) { Join-Path $env:USERPROFILE '.claude' } else { Join-Path $HOME '.claude' }
$UserHome    = if ($env:USERPROFILE) { $env:USERPROFILE } else { $HOME }
$AuraHome    = if ($env:AURA_DISTILL_HOME) { $env:AURA_DISTILL_HOME } else { Join-Path $UserHome '.aura-distill' }
$CodexHome   = if ($env:CODEX_HOME) { $env:CODEX_HOME } else { Join-Path $UserHome '.codex' }
$CmdDir      = Join-Path $ClaudeHome 'commands'
$DistillDir  = $AuraHome
$LegacyDistillDir = Join-Path $ClaudeHome 'distill'
$RulesDir    = Join-Path $ClaudeHome 'rules'
$ClaudeMd    = Join-Path $ClaudeHome 'CLAUDE.md'
$CodexAgents = Join-Path $CodexHome 'AGENTS.md'
$SettingsJson = Join-Path $ClaudeHome 'settings.json'

$EmDash = [char]0x2014
$ManagedStart = '<!-- aura-distill:start -->'
$ManagedEnd = '<!-- aura-distill:end -->'

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
    try { Clear-Host } catch { }
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
    if (Test-Path -LiteralPath $Url) {
        Copy-Item -LiteralPath $Url -Destination $Destination -Force
    } else {
        # PS 5.1 requires -UseBasicParsing; harmless on PS 7+
        Invoke-WebRequest -Uri $Url -OutFile $Destination -UseBasicParsing
    }
}

# Consent boundary for a payload whose major differs from this installer's line
# (docs/adr/0001, "The consent boundary"). Runs before anything is written. Consent
# needs a human at a console typing the exact phrase; redirected input or output,
# a non-interactive host or any other answer keeps the current installation.
function Request-MajorConsent {
    param([string]$Target)
    Write-Host ''
    Write-Host "  ${BOLD}aura-distill v$Target is a major change from the v$LineMajor line this installer belongs to.${RESET}"
    Write-Host '  Read the release notes before continuing: https://github.com/tomacco/aura-distill/releases'
    Write-Host '  Your current installation and knowledge stay as they are unless you consent here.'
    $interactive = [Environment]::UserInteractive -and -not [Console]::IsInputRedirected -and -not [Console]::IsOutputRedirected
    if (-not $interactive) {
        Write-Host '  No interactive terminal: consent cannot be given here. Kept your current installation. Nothing was installed or changed.'
        return $false
    }
    $answer = Read-Host "  Type ""adopt $Target"" to continue, or press Enter to keep your current installation"
    if ($answer -ne "adopt $Target") {
        Write-Host '  Kept your current installation. Nothing was installed or changed.'
        return $false
    }
    return $true
}

# === MAIN ===

Write-Header

# === CHANNEL AND PAYLOAD (nothing is written before this block succeeds) ===
# Refusals stop the script without closing the caller's session under `irm | iex`.

$channelFile = Join-Path $DistillDir '.channel'
$Channel = if ($env:DISTILL_CHANNEL) { $env:DISTILL_CHANNEL.Trim().ToLower() }
           elseif (Test-Path $channelFile) { (Get-Content $channelFile -Raw).Trim([char]0xFEFF, ' ', "`r", "`n", "`t").ToLower() }
           else { 'stable' }
if (-not $Channel) { $Channel = 'stable' }
if ($Channel -ne 'stable' -and $Channel -ne 'beta') {
    Write-Fail "Unknown channel '$Channel' (use `$env:DISTILL_CHANNEL='stable' or 'beta'). Nothing was changed."
    if ($PSCommandPath) { exit 1 }; return
}

$Stage = Join-Path ([System.IO.Path]::GetTempPath()) ('aura-distill-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force -Path $Stage | Out-Null
$payloadError = $null
try {
    if ($Channel -eq 'beta' -and -not $env:AURA_DISTILL_REPO) {
        $manifestFile = Join-Path $Stage 'manifest.json'
        try { Get-File $BetaManifest $manifestFile } catch { throw 'Could not read the beta channel manifest.' }
        try { $beta = (Get-Content $manifestFile -Raw | ConvertFrom-Json).beta } catch { $beta = $null }
        if (-not $beta) { throw 'The beta channel manifest is missing or malformed.' }
        switch ([string]$beta.status) {
            'prerelease' { }
            'stable' { }
            'unpublished' { throw 'No beta release is published yet.' }
            'closed' { throw "The beta channel is closed. Install stable with `$env:DISTILL_CHANNEL='stable'." }
            default { throw 'The beta channel manifest is missing or malformed.' }
        }
        $betaTag = [string]$beta.tag
        if ($betaTag -cnotmatch '^v[0-9]+\.[0-9]+\.[0-9]+(-beta\.[0-9]+)?$' -or $betaTag.Substring(1) -ne [string]$beta.version) {
            throw 'The beta channel manifest names an invalid release.'
        }
        if ($betaTag.Substring(1).Split('.')[0] -ne [string]$LineMajor) {
            throw "The beta channel now names $betaTag, a different major version. This installer only installs the v$LineMajor line; that release needs its own installer and your consent."
        }
        $Repo = "$RawRoot/$betaTag"
    }

    # Download the whole payload to a temp dir and validate it before touching
    # anything: a failed or partial download must leave an existing install intact.
    $PayloadVersion = ''
    try {
        Get-File "$Repo/VERSION" (Join-Path $Stage 'VERSION')
        $PayloadVersion = (Get-Content (Join-Path $Stage 'VERSION') -Raw).Trim()
    } catch { }
    $valid = $PayloadVersion -cmatch '^[0-9]+\.[0-9]+\.[0-9]+(-beta\.[0-9]+)?$'
    foreach ($f in @('distill.md', 'distill-process.md', 'distill-monitor.md')) {
        $dest = Join-Path $Stage $f
        try { Get-File "$Repo/$f" $dest } catch { $valid = $false; continue }
        $body = Get-Content $dest -Raw
        if (-not $body -or -not $body.StartsWith('# ')) { $valid = $false }
        elseif ($body.Contains($SoftwareMarker)) {
            throw "$Repo serves a software-edition payload. This files-only installer never installs it; use that edition's own installer."
        }
    }
    if (-not $valid) { throw "Download failed or returned invalid files from $Repo." }
    if ($Channel -eq 'stable' -and $PayloadVersion.Contains('-') -and -not $env:AURA_DISTILL_REPO) {
        throw "The stable endpoint reports a prerelease ($PayloadVersion); refusing."
    }
} catch {
    $payloadError = $_.Exception.Message
}
if ($payloadError) {
    Remove-Item -LiteralPath $Stage -Recurse -Force -ErrorAction SilentlyContinue
    Write-Fail "$payloadError Nothing was changed."
    if ($PSCommandPath) { exit 1 }; return
}
if ($PayloadVersion.Split('.')[0] -ne [string]$LineMajor) {
    if (-not (Request-MajorConsent $PayloadVersion)) {
        Remove-Item -LiteralPath $Stage -Recurse -Force -ErrorAction SilentlyContinue
        if ($PSCommandPath) { exit 2 }; return
    }
}
# Optional in older payloads (main before the 1.2 line has no updater script).
$UpdaterStage = Join-Path $Stage 'distill-update.sh'
$HaveUpdater = $false
try {
    Get-File "$Repo/bin/distill-update.sh" $UpdaterStage
    $updaterLines = Get-Content $UpdaterStage
    $HaveUpdater = ($updaterLines.Count -gt 1) -and ($updaterLines[1] -like '# aura-distill-updater*') -and -not ((Get-Content $UpdaterStage -Raw).Contains($SoftwareMarker))
} catch { $HaveUpdater = $false }

# Detect existing installation
$existingVersion = ''
$versionFile = Join-Path $DistillDir '.version'
if (Test-Path $versionFile) {
    $existingVersion = (Get-Content $versionFile -Raw).Trim()
    Write-Info "Existing installation: v$existingVersion -> v$PayloadVersion ($Channel channel)"
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
                 (Join-Path $DistillDir 'archive'),
                 (Join-Path $DistillDir 'data'),
                 (Join-Path $DistillDir 'inbox'))) {
    if (-not (Test-Path $d)) { New-Item -ItemType Directory -Force -Path $d | Out-Null }
}

# Seed the new client-neutral store from a legacy Claude installation. Copying
# keeps existing users' files and configuration untouched.
$legacyMarker = Join-Path $DistillDir '.legacy-imported'
if ((Test-Path $LegacyDistillDir) -and ($LegacyDistillDir -ne $DistillDir) -and -not (Test-Path $legacyMarker)) {
    Copy-Item -Path (Join-Path $LegacyDistillDir '*') -Destination $DistillDir -Recurse -Force -ErrorAction SilentlyContinue
    "copied from $LegacyDistillDir on $((Get-Date).ToUniversalTime().ToString('s'))Z" | Set-Content $legacyMarker -NoNewline
    Write-Info 'Existing Claude knowledge copied to shared store; legacy files preserved'
} elseif ((Test-Path $LegacyDistillDir) -and (Test-Path $legacyMarker)) {
    Write-Info "Shared store was already seeded; $LegacyDistillDir left untouched (set AURA_DISTILL_HOME for an isolated profile)"
}

function Install-CoreFile {
    param([string]$Name, [string]$Target)
    $resolved = (Get-Content (Join-Path $Stage $Name) -Raw).Replace($Placeholder, $DistillDir)
    $tmpTarget = "$Target.aura-new"
    [System.IO.File]::WriteAllText($tmpTarget, $resolved, (New-Object System.Text.UTF8Encoding($false)))
    Move-Item -Force -LiteralPath $tmpTarget -Destination $Target
}
Install-CoreFile 'distill.md' (Join-Path $CmdDir 'distill.md')
Write-Done "distill.md ${DIM}(command)${RESET}"

Install-CoreFile 'distill-process.md' (Join-Path $DistillDir 'distill-process.md')
Write-Done "distill-process.md ${DIM}(process engine)${RESET}"

Install-CoreFile 'distill-monitor.md' (Join-Path $DistillDir 'distill-monitor.md')
Write-Done "distill-monitor.md ${DIM}(session monitor)${RESET}"

if ($HaveUpdater) {
    $binDir = Join-Path $DistillDir 'bin'
    if (-not (Test-Path $binDir)) { New-Item -ItemType Directory -Force -Path $binDir | Out-Null }
    Copy-Item -Force -LiteralPath $UpdaterStage -Destination (Join-Path $binDir 'distill-update.sh.aura-new')
    Move-Item -Force -LiteralPath (Join-Path $binDir 'distill-update.sh.aura-new') -Destination (Join-Path $binDir 'distill-update.sh')
    Write-Done "bin/distill-update.sh ${DIM}(updater; follows the $Channel channel)${RESET}"
}
Remove-Item -LiteralPath $Stage -Recurse -Force -ErrorAction SilentlyContinue

# Version, channel and command path (read by bin/distill-update.sh under Git Bash).
# Written without a byte-order mark: Windows PowerShell 5.1's `-Encoding utf8` adds one,
# and a BOM-prefixed .channel would no longer read as "beta".
$NoBom = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText($versionFile, $PayloadVersion, $NoBom)
[System.IO.File]::WriteAllText($channelFile, $Channel, $NoBom)
# .command-path lists every profile's dispatcher that shares this store (one per line,
# LF, no BOM); add ours once.
$cmdPathFile = Join-Path $DistillDir '.command-path'
$ourCmd = (Join-Path $CmdDir 'distill.md') -replace '\\', '/'
$cmdLines = @()
if (Test-Path $cmdPathFile) {
    $cmdLines = @(([System.IO.File]::ReadAllText($cmdPathFile)).TrimStart([char]0xFEFF) -split "`r?`n" | Where-Object { $_ })
}
if ($cmdLines -notcontains $ourCmd) { $cmdLines += $ourCmd }
[System.IO.File]::WriteAllText($cmdPathFile, (($cmdLines -join "`n") + "`n"), $NoBom)

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

# Preserve the user's synced Always-On preferences across updates (like SPINE).
# /distill writes real content into this section; overwriting it is data loss.
$rulesTarget = Join-Path $RulesDir 'distill.md'
$prefsMark = '## Always-On User Preferences'
$preservedPrefs = $null
if (Test-Path $rulesTarget) {
    $existing = Get-Content $rulesTarget -Raw
    $idx = $existing.IndexOf($prefsMark)
    if ($idx -ge 0) {
        $section = $existing.Substring($idx)
        # Only preserve real content (a bold rule line), not the empty template
        if ($section -match "(?m)^\*\*") { $preservedPrefs = $section }
    }
}
$rulesTmp = [System.IO.Path]::GetTempFileName()
try {
    Get-File "$Repo/rules/distill.md" $rulesTmp
    $fresh = (Get-Content $rulesTmp -Raw).Replace('{DISTILL_DIR}', $DistillDir)
    if ($fresh -match 'Distill') {
        if ($preservedPrefs) {
            $freshIdx = $fresh.IndexOf($prefsMark)
            $body = if ($freshIdx -ge 0) { $fresh.Substring(0, $freshIdx) } else { $fresh }
            [System.IO.File]::WriteAllText($rulesTarget, ($body + $preservedPrefs), (New-Object System.Text.UTF8Encoding($false)))
            Write-Done "rules/distill.md ${DIM}(auto-loads every session; your preferences preserved)${RESET}"
        } else {
            Move-Item -Force $rulesTmp $rulesTarget
            Write-Done "rules/distill.md ${DIM}(auto-loads every session)${RESET}"
        }
    } else {
        Write-Warn 'rules/distill.md download invalid -- existing file left untouched'
    }
} catch {
    Write-Warn 'rules/distill.md download failed -- existing file left untouched'
} finally {
    Remove-Item $rulesTmp -Force -ErrorAction SilentlyContinue
}

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

function Set-AuraIntegration {
    param([string]$Path, [string]$Label, [ValidateSet('claude','codex')][string]$Client)
    $parent = Split-Path -Parent $Path
    if (-not (Test-Path $parent)) { New-Item -ItemType Directory -Force -Path $parent | Out-Null }
    $existing = if (Test-Path $Path) { Get-Content $Path -Raw } else { '' }
    $pattern = '(?s)\r?\n?' + [regex]::Escape($ManagedStart) + '.*?' + [regex]::Escape($ManagedEnd) + '\r?\n?'
    $cleaned = [regex]::Replace($existing, $pattern, '').TrimEnd()
    if ($Label -eq 'CLAUDE.md') {
        $legacyPattern = '(?ms)\r?\n?# Distill . knowledge system \(github\.com/tomacco/aura-distill\)\r?\n\r?\nGATE:.*?(?=\r?\n#|\z)'
        $cleaned = [regex]::Replace($cleaned, $legacyPattern, '').TrimEnd()
    }
    $clientGuidance = if ($Client -eq 'codex') {
        "Read $DistillDir/distill-monitor.md for the full retrieval and memory-pressure behavior. When the user asks to distill, read $DistillDir/distill-process.md and run that process in an isolated sub-agent when supported.`r`n"
    } else { '' }
    $block = @"
$ManagedStart
# Aura Distill shared knowledge

Before doing any work, read $DistillDir/SPINE.md. When the request or an announced action matches a SPINE entry, read the linked file before responding and apply it.

$clientGuidance
If $DistillDir/.needs-migration exists and does not start with "migrated", tell the user to ask you to distill/migrate existing memories before proceeding.
$ManagedEnd
"@
    $content = if ($cleaned) { "$cleaned`r`n`r`n$block" } else { $block }
    Set-Content -Path $Path -Value $content -Encoding utf8
    Write-Done "$Label configured"
}

Set-AuraIntegration $ClaudeMd 'CLAUDE.md' 'claude'
Set-AuraIntegration $CodexAgents 'Codex AGENTS.md' 'codex'

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
Write-Host "  ${DIM}Version:  ${RESET}v$PayloadVersion ${DIM}($Channel channel)${RESET}"
Write-Host "  ${DIM}Command:  ${RESET}/distill"
Write-Host "  ${DIM}Knowledge:${RESET} $DistillDir"
Write-Host ''
if ($existingVersion) {
    Write-Host "  ${CYAN}Upgraded${RESET} v$existingVersion -> v$PayloadVersion"
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
if ($Channel -eq 'beta') {
    Write-Host "  ${BOLD}Beta channel.${RESET} /distill updates follow published beta releases only."
    Write-Host "  ${DIM}Back to stable: `$env:DISTILL_CHANNEL='stable'; re-run this installer${RESET}"
    Write-Host ''
}
Write-Host "  ${DIM}Uninstall (keeps your learnings):${RESET}"
Write-Host "    ${DIM}Remove Claude adapters and the managed aura-distill blocks from CLAUDE.md and ~/.codex/AGENTS.md; keep ~/.aura-distill for your learnings.${RESET}"
Write-Host ''
Write-Host "  ${PURPLE}say what matters. it's listening.${RESET}"
Write-Host ''
