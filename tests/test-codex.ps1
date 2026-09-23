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

    # Always-On preferences rule (same as install.sh): the section is kept byte for
    # byte unless it equals the shipped template ignoring whitespace.
    $mark = '## Always-On User Preferences'
    function Test-PrefsCase([string]$Name, [string]$Section, [bool]$ExpectKept) {
        $h = New-TestHome; $homes.Add($h); Invoke-TestInstall $h
        $rules = Join-Path $h '.claude/rules/distill.md'
        $text = [System.IO.File]::ReadAllText($rules)
        $idx = [regex]::Match($text, '(?m)^## Always-On User Preferences').Index
        $Section = $Section.Replace('@STORE@', (Join-Path $h '.aura-distill'))
        $new = if ($Section -eq 'MISSING') { "OLD-FILE-WITHOUT-HEADING`n" } else { $text.Substring(0, $idx) + $Section }
        [System.IO.File]::WriteAllText($rules, $new, (New-Object System.Text.UTF8Encoding($false)))
        Invoke-TestInstall $h
        $after = [System.IO.File]::ReadAllText($rules)
        $m = [regex]::Match($after, '(?m)^## Always-On User Preferences')
        $afterSection = if ($m.Success) { $after.Substring($m.Index) } else { '' }
        if ($ExpectKept) { Assert-True ($afterSection -ceq $Section) "install.ps1 keeps $Name preferences byte for byte" }
        else { Assert-True ($m.Success -and $afterSection -cne $Section -and -not $after.Contains('OLD-FILE-WITHOUT-HEADING') -and -not $after.Contains('{DISTILL' + '_DIR}')) "install.ps1 replaces $Name with the release's section, placeholder resolved" }
    }
    Test-PrefsCase 'bullet-only' "$mark`n`n- Answer in bullet points.`n- Never use emoji.`n" $true
    Test-PrefsCase 'prose' "$mark`n`nKeep answers short; ask before large refactors.`n" $true
    Test-PrefsCase 'non-ASCII' "$mark`n`n- Responde en español, sin «adornos» ¿vale? — ûÿ`n" $true
    $templateSection = [System.IO.File]::ReadAllText((Join-Path $RepoRoot 'rules/distill.md'))
    $templateSection = $templateSection.Substring([regex]::Match($templateSection, '(?m)^## Always-On User Preferences').Index).Replace('{DISTILL' + '_DIR}', '@STORE@')
    Test-PrefsCase 'an untouched template (whitespace differs)' (($templateSection -replace "`n", "  `n") + "`n`n") $false
    Test-PrefsCase 'a file without the heading' 'MISSING' $false
    $freshRules = [System.IO.File]::ReadAllText((Join-Path $fresh '.claude/rules/distill.md'))
    Assert-True (-not $freshRules.Contains('{DISTILL' + '_DIR}')) 'install.ps1 resolves the store path in rules/distill.md when no preferences are kept'

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
    foreach ($testPath in $homes) {
        Remove-Item -LiteralPath $testPath -Recurse -Force -ErrorAction SilentlyContinue
        if (Test-Path -LiteralPath $testPath) { Write-Warning "Could not remove isolated test directory: $testPath" }
    }
}

Write-Host "`n$Passed passed, $Failed failed"
if ($Failed -gt 0) { exit 1 }
