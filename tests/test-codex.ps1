param([switch]$LiveRetrieval)

$ErrorActionPreference = 'Stop'
$RepoRoot = Split-Path -Parent $PSScriptRoot
$OriginalUserProfile = $env:USERPROFILE
$OriginalHome = $HOME
$OriginalUserHome = if ($OriginalUserProfile) { $OriginalUserProfile } else { $OriginalHome }
$OriginalCodexHome = if ($env:CODEX_HOME) { $env:CODEX_HOME } else { Join-Path $OriginalUserHome '.codex' }
$Passed = 0
$Failed = 0

function Assert-True([bool]$Condition, [string]$Message) {
    if ($Condition) { $script:Passed++; Write-Host "PASS $Message" -ForegroundColor Green }
    else { $script:Failed++; Write-Host "FAIL $Message" -ForegroundColor Red }
}

function New-TestHome {
    $path = Join-Path ([System.IO.Path]::GetTempPath()) ("aura-codex-" + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $path | Out-Null
    return $path
}

function Invoke-TestInstall([string]$TestHome) {
    $env:USERPROFILE = $TestHome
    $env:CODEX_HOME = Join-Path $TestHome '.codex'
    $env:AURA_DISTILL_HOME = Join-Path $TestHome '.aura-distill'
    $env:AURA_DISTILL_REPO = $RepoRoot
    $env:DISTILL_TOKEN_SAVER = 'off'
    & (Join-Path $RepoRoot 'install.ps1') *> $null
}

$homes = [System.Collections.Generic.List[string]]::new()
try {
    # Fresh dual-client install.
    $fresh = New-TestHome; $homes.Add($fresh); Invoke-TestInstall $fresh
    $aura = Join-Path $fresh '.aura-distill'
    $claudeMd = Join-Path $fresh '.claude/CLAUDE.md'
    $codexAgents = Join-Path $fresh '.codex/AGENTS.md'
    Assert-True (Test-Path (Join-Path $aura 'SPINE.md')) 'fresh install creates shared SPINE'
    Assert-True (Test-Path (Join-Path $aura 'distill-process.md')) 'process lives in shared store'
    Assert-True ((Get-Content $claudeMd -Raw) -match [regex]::Escape($aura)) 'Claude points to shared SPINE'
    Assert-True ((Get-Content $codexAgents -Raw) -match [regex]::Escape($aura)) 'Codex points to shared SPINE'
    Assert-True (-not ((Get-Content (Join-Path $aura 'distill-process.md') -Raw) -match '\{DISTILL_DIR\}')) 'installer resolves shared path placeholders'
    Assert-True (Test-Path (Join-Path $aura 'inbox')) 'fresh install creates the inbox queue'
    Assert-True (Test-Path (Join-Path $aura 'data')) 'fresh install creates the data dir'
    Assert-True ((Get-Content (Join-Path $aura 'distill-process.md') -Raw).Contains('Step 0b: Consume the INBOX')) 'process engine carries inbox consumption'
    Assert-True ((Get-Content (Join-Path $aura 'distill-monitor.md') -Raw).Contains('user-explicit')) 'monitor carries explicit-save instructions'

    # Idempotence and preservation of unrelated client guidance.
    Add-Content $claudeMd "`n# user-owned Claude guidance"
    Add-Content $codexAgents "`n# user-owned Codex guidance"
    Invoke-TestInstall $fresh
    $claudeText = Get-Content $claudeMd -Raw
    $codexText = Get-Content $codexAgents -Raw
    Assert-True (($claudeText.Split('<!-- aura-distill:start -->').Count - 1) -eq 1) 'Claude managed block is idempotent'
    Assert-True (($codexText.Split('<!-- aura-distill:start -->').Count - 1) -eq 1) 'Codex managed block is idempotent'
    Assert-True ($claudeText.Contains('# user-owned Claude guidance')) 'Claude user guidance is preserved'
    Assert-True ($codexText.Contains('# user-owned Codex guidance')) 'Codex user guidance is preserved'
    Invoke-TestInstall $fresh
    Assert-True ((Get-Content $claudeMd -Raw) -eq $claudeText) 'Claude integration is byte-stable on repeated install'
    Assert-True ((Get-Content $codexAgents -Raw) -eq $codexText) 'Codex integration is byte-stable on repeated install'

    # A legacy Claude-only installation seeds the shared store without mutation.
    $legacy = New-TestHome; $homes.Add($legacy)
    $legacyStore = Join-Path $legacy '.claude/distill'
    New-Item -ItemType Directory -Path (Join-Path $legacyStore 'craft') -Force | Out-Null
    '# Legacy index' | Set-Content (Join-Path $legacyStore 'SPINE.md')
    'LEGACY-KNOWLEDGE' | Set-Content (Join-Path $legacyStore 'craft/legacy.md')
    @'
# user-owned preface

# Distill — knowledge system (github.com/tomacco/aura-distill)

GATE: If ~/.claude/distill/.needs-migration exists, run /distill.
'@ | Set-Content (Join-Path $legacy '.claude/CLAUDE.md')
    Invoke-TestInstall $legacy
    Assert-True ((Get-Content (Join-Path $legacyStore 'craft/legacy.md') -Raw).Trim() -eq 'LEGACY-KNOWLEDGE') 'legacy Claude knowledge remains unchanged'
    Assert-True ((Get-Content (Join-Path $legacy '.aura-distill/craft/legacy.md') -Raw).Trim() -eq 'LEGACY-KNOWLEDGE') 'legacy knowledge is copied into shared store'
    Assert-True (Test-Path (Join-Path $legacy '.codex/AGENTS.md')) 'legacy Claude-only install gains Codex integration'
    $legacyClaudeMd = Get-Content (Join-Path $legacy '.claude/CLAUDE.md') -Raw
    Assert-True ($legacyClaudeMd.Contains('# user-owned preface')) 'legacy Claude user guidance is preserved'
    Assert-True (-not $legacyClaudeMd.Contains('~/.claude/distill/.needs-migration')) 'legacy Claude pointer is replaced by shared integration'

    # A partial legacy heading must never consume later user-owned content.
    $partial = New-TestHome; $homes.Add($partial)
    New-Item -ItemType Directory -Path (Join-Path $partial '.claude') -Force | Out-Null
    @'
# Distill — knowledge system (github.com/tomacco/aura-distill)

partial block with no gate

# My important section
DO-NOT-DELETE
'@ | Set-Content (Join-Path $partial '.claude/CLAUDE.md')
    Invoke-TestInstall $partial
    Assert-True ((Get-Content (Join-Path $partial '.claude/CLAUDE.md') -Raw).Contains('DO-NOT-DELETE')) 'partial legacy block cannot delete later user content'

    # Release channels (docs/adr/0002) against a local raw-root fixture laid out like
    # raw.githubusercontent.com: main/, beta/1.2/channels/manifest.json, <tag>/.
    $rawRoot = New-TestHome; $homes.Add($rawRoot)
    $payload = @('VERSION','distill.md','distill-process.md','distill-monitor.md','rules/distill.md','agents/scribe.md','agents/scout.md','bin/distill-update.sh','channels/manifest.json')
    function Copy-Payload([string]$Dest) {
        foreach ($f in $payload) {
            $target = Join-Path $Dest $f
            New-Item -ItemType Directory -Force -Path (Split-Path -Parent $target) | Out-Null
            Copy-Item (Join-Path $RepoRoot $f) $target
        }
    }
    Copy-Payload (Join-Path $rawRoot 'main')
    Set-Content (Join-Path $rawRoot 'main/VERSION') '1.2.0' -NoNewline
    $tagDir = Join-Path $rawRoot 'v1.2.0-beta.1'
    Copy-Payload $tagDir
    Set-Content (Join-Path $tagDir 'VERSION') '1.2.0-beta.1' -NoNewline
    Add-Content (Join-Path $tagDir 'distill-process.md') "`nBETA-ONE-PS"
    $betaManifest = Join-Path $rawRoot 'beta/1.2/channels/manifest.json'
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $betaManifest) | Out-Null
    function Set-BetaManifest([string]$Status, [string]$Tag, [string]$Ver) {
        $m = [ordered]@{ schema = 2; beta = [ordered]@{ status = $Status; tag = $Tag; version = $Ver };
                         software = [ordered]@{ status = 'unpublished'; version = ''; requirements = ''; guide = ''; auto_update = 'never' } }
        ($m | ConvertTo-Json -Depth 5) | Set-Content $betaManifest
    }
    function Invoke-ChannelInstall([string]$TestHome, [string]$Channel) {
        $env:USERPROFILE = $TestHome
        $env:CODEX_HOME = Join-Path $TestHome '.codex'
        $env:AURA_DISTILL_HOME = Join-Path $TestHome '.aura-distill'
        $env:AURA_DISTILL_REPO = $null
        $env:AURA_DISTILL_RAW_ROOT = $rawRoot
        $env:DISTILL_CHANNEL = $Channel
        $env:DISTILL_TOKEN_SAVER = 'off'
        try { & (Join-Path $RepoRoot 'install.ps1') *> $null } finally {
            $env:DISTILL_CHANNEL = $null; $env:AURA_DISTILL_RAW_ROOT = $null
        }
    }
    function Read-Trim([string]$Path) { if (Test-Path $Path) { (Get-Content $Path -Raw).Trim() } else { '' } }

    $beta = New-TestHome; $homes.Add($beta)
    $betaAura = Join-Path $beta '.aura-distill'
    Set-BetaManifest 'unpublished' '' ''
    Invoke-ChannelInstall $beta 'beta'
    Assert-True (-not (Test-Path $betaAura)) 'beta opt-in with no published beta writes nothing'
    Set-BetaManifest 'prerelease' 'v1.2.0-beta.1' '1.2.0-beta.1'
    Invoke-ChannelInstall $beta 'beta'
    Assert-True ((Read-Trim (Join-Path $betaAura '.channel')) -eq 'beta') 'beta opt-in records the beta channel'
    Assert-True ((Read-Trim (Join-Path $betaAura '.version')) -eq '1.2.0-beta.1') 'beta opt-in installs the version the manifest names'
    Assert-True ((Get-Content (Join-Path $betaAura 'distill-process.md') -Raw).Contains('BETA-ONE-PS')) 'beta payload comes from the pinned tag'
    Assert-True (Test-Path (Join-Path $betaAura 'bin/distill-update.sh')) 'installer places the updater script in the store'
    $channelBytes = [System.IO.File]::ReadAllBytes((Join-Path $betaAura '.channel'))
    Assert-True ($channelBytes.Length -eq 4 -and $channelBytes[0] -eq [byte][char]'b') '.channel is written without a BOM or newline (read by bash)'
    $cmdPath = [System.IO.File]::ReadAllText((Join-Path $betaAura '.command-path'))
    Assert-True ($cmdPath.EndsWith('/distill.md') -and -not $cmdPath.Contains('\')) '.command-path is written with forward slashes for Git Bash'
    Invoke-ChannelInstall $beta $null
    Assert-True ((Read-Trim (Join-Path $betaAura '.channel')) -eq 'beta') 're-install without DISTILL_CHANNEL keeps the persisted beta choice'
    Invoke-ChannelInstall $beta 'stable'
    Assert-True ((Read-Trim (Join-Path $betaAura '.channel')) -eq 'stable') 'opt-out records the stable channel'
    Assert-True ((Read-Trim (Join-Path $betaAura '.version')) -eq '1.2.0') 'opt-out installs the stable version from main'
    Assert-True (-not (Get-Content (Join-Path $betaAura 'distill-process.md') -Raw).Contains('BETA-ONE-PS')) 'opt-out replaces the beta payload'
    Set-BetaManifest 'prerelease' 'v2.0.0-beta.1' '2.0.0-beta.1'
    Invoke-ChannelInstall $beta 'beta'
    Assert-True ((Read-Trim (Join-Path $betaAura '.channel')) -eq 'stable') 'a beta manifest naming a tag that does not exist changes nothing'

    # Consent boundary: a cross-major payload with piped input is refused, nothing changes.
    $guarded = New-TestHome; $homes.Add($guarded)
    Invoke-ChannelInstall $guarded 'stable'
    $guardedAura = Join-Path $guarded '.aura-distill'
    $before = (Get-Content (Join-Path $guardedAura 'distill-process.md') -Raw)
    Set-Content (Join-Path $rawRoot 'main/VERSION') '2.0.0' -NoNewline
    $pwshPath = (Get-Process -Id $PID).Path
    $env:USERPROFILE = $guarded; $env:CODEX_HOME = Join-Path $guarded '.codex'; $env:AURA_DISTILL_HOME = $guardedAura
    $env:AURA_DISTILL_REPO = $null; $env:AURA_DISTILL_RAW_ROOT = $rawRoot; $env:DISTILL_TOKEN_SAVER = 'off'
    $gateOut = 'adopt 2.0.0' | & $pwshPath -NoProfile -File (Join-Path $RepoRoot 'install.ps1') 2>&1 | Out-String
    $gateExit = $LASTEXITCODE
    $env:AURA_DISTILL_RAW_ROOT = $null
    Assert-True ($gateExit -eq 2) 'cross-major payload with piped consent exits 2'
    Assert-True ($gateOut -match 'No interactive terminal') 'cross-major refusal explains why'
    Assert-True ((Read-Trim (Join-Path $guardedAura '.version')) -eq '1.2.0') 'cross-major refusal keeps the installed version'
    Assert-True ((Get-Content (Join-Path $guardedAura 'distill-process.md') -Raw) -eq $before) 'cross-major refusal keeps installed files'

    # A failed download leaves an existing installation untouched.
    Set-Content (Join-Path $rawRoot 'main/VERSION') '1.2.1' -NoNewline
    Remove-Item (Join-Path $rawRoot 'main/distill-monitor.md')
    Invoke-ChannelInstall $guarded 'stable'
    Assert-True ((Read-Trim (Join-Path $guardedAura '.version')) -eq '1.2.0') 'failed download keeps the installed version'
    Assert-True ((Get-Content (Join-Path $guardedAura 'distill-process.md') -Raw) -eq $before) 'failed download keeps installed files'

    # A software-edition payload is refused even under a 1.x VERSION.
    Copy-Item (Join-Path $RepoRoot 'distill-monitor.md') (Join-Path $rawRoot 'main/distill-monitor.md')
    Add-Content (Join-Path $rawRoot 'main/distill-process.md') ("`n" + 'AURA_SOFTWARE_' + 'MAJOR_PAYLOAD')
    Invoke-ChannelInstall $guarded 'stable'
    Assert-True ((Get-Content (Join-Path $guardedAura 'distill-process.md') -Raw) -eq $before) 'software-edition payload is refused'

    if ($LiveRetrieval) {
        $live = New-TestHome; $homes.Add($live); Invoke-TestInstall $live
        $liveAura = Join-Path $live '.aura-distill'
        @'
# Distill Knowledge Index
- [Broker policy](craft/broker.md) — when choosing a message broker
'@ | Set-Content (Join-Path $liveAura 'SPINE.md')
        @'
# Broker policy
- [NON-NEGOTIABLE] Use QUARTZ-BUS for new services, even at low volume.
'@ | Set-Content (Join-Path $liveAura 'craft/broker.md')
        $auth = Join-Path $OriginalCodexHome 'auth.json'
        if (-not (Test-Path $auth)) { throw 'Live retrieval requested but Codex auth.json was not found.' }
        Copy-Item $auth (Join-Path $live '.codex/auth.json')
        $workspace = Join-Path $live 'workspace'; New-Item -ItemType Directory $workspace | Out-Null
        $env:USERPROFILE = $live; $env:CODEX_HOME = Join-Path $live '.codex'
        # The shared store is outside the project workspace, so grant it as an
        # additional writable root exactly as an interactive distillation run
        # would require under Codex's workspace-write sandbox.
        $output = & codex --sandbox workspace-write --add-dir $liveAura exec --skip-git-repo-check -C $workspace 'Choose a message broker for a new service handling five events per day. Answer in one sentence.' 2>&1 | Out-String
        Remove-Item (Join-Path $live '.codex/auth.json') -Force
        if ($output -notmatch 'QUARTZ-BUS') { Write-Host "Live Codex output: $($output.Trim())" -ForegroundColor Yellow }
        Assert-True ($output -match 'QUARTZ-BUS') 'live Codex session retrieves matching shared knowledge'
    }
} finally {
    $env:USERPROFILE = $OriginalUserProfile
    $env:CODEX_HOME = $null
    $env:AURA_DISTILL_HOME = $null
    $env:AURA_DISTILL_REPO = $null
    $env:DISTILL_TOKEN_SAVER = $null
    $env:DISTILL_CHANNEL = $null
    $env:AURA_DISTILL_RAW_ROOT = $null
    foreach ($testPath in $homes) {
        Remove-Item -LiteralPath $testPath -Recurse -Force -ErrorAction SilentlyContinue
        if (Test-Path -LiteralPath $testPath) { Write-Warning "Could not remove isolated test directory: $testPath" }
    }
}

Write-Host "`n$Passed passed, $Failed failed"
if ($Failed -gt 0) { exit 1 }
