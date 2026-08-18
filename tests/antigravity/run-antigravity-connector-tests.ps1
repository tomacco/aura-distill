# Test runner for the aura-distill Antigravity (agy) connector.
# Validates the plugin against Antigravity's documented discovery layout
# (agy-customizations reference: plugin.json is a MARKER; content is discovered
# structurally at plugins/<name>/skills/<skill>/SKILL.md and
# plugins/<name>/rules/AGENTS.md). A structural check is not a live discovery
# test -- end-to-end validation inside Antigravity itself is tracked on #67.
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..\..')
Write-Host "Testing Antigravity connector in: $repoRoot"

$script:passCount = 0
$script:failCount = 0

function Assert-True([bool]$condition, [string]$message) {
    if ($condition) {
        Write-Host "  [PASS] $message" -ForegroundColor Green
        $script:passCount++
    } else {
        Write-Host "  [FAIL] $message" -ForegroundColor Red
        $script:failCount++
    }
}

$pluginRoot = Join-Path $repoRoot 'plugins\aura-distill'

# Test 1: plugin.json is a valid Antigravity marker (supported fields only)
$manifestPath = Join-Path $pluginRoot 'plugin.json'
Assert-True (Test-Path $manifestPath) "plugins/aura-distill/plugin.json exists"
if (Test-Path $manifestPath) {
    $manifest = Get-Content $manifestPath -Raw | ConvertFrom-Json
    Assert-True ($manifest.name -eq 'aura-distill') "plugin.json has name aura-distill"
    $supported = @('name', 'disabled')
    $unsupported = @($manifest.PSObject.Properties.Name | Where-Object { $supported -notcontains $_ })
    Assert-True ($unsupported.Count -eq 0) "plugin.json uses only Antigravity-supported fields (found: $($unsupported -join ', '))"
}

# Test 2: skill sits at the DISCOVERED path inside the plugin
$skillPath = Join-Path $pluginRoot 'skills\distill\SKILL.md'
Assert-True (Test-Path $skillPath) "plugins/aura-distill/skills/distill/SKILL.md exists (discovery path)"
if (Test-Path $skillPath) {
    $content = Get-Content $skillPath -Raw
    Assert-True ($content -match 'name:\s*distill') "SKILL.md contains name: distill frontmatter"
    Assert-True ($content -match 'SPINE\.md') "SKILL.md references SPINE.md"
    Assert-True ($content -match 'invoke_subagent') "SKILL.md references Antigravity subagent invocation"
    Assert-True ($content -match '\.needs-migration') "SKILL.md gates on pending migration"
    Assert-True ($content -match 'idle <ISO_TIMESTAMP>') "SKILL.md resets .status on spawn failure"
    Assert-True ($content -match 'AURA_DISTILL_HOME') "SKILL.md resolves the shared store via AURA_DISTILL_HOME"
    Assert-True ($content -notmatch '\.agents/distill') "SKILL.md does not invent a workspace-local store"
}

# Test 3: rules sit at the DISCOVERED path and defer to the canonical monitor
$rulePath = Join-Path $pluginRoot 'rules\AGENTS.md'
Assert-True (Test-Path $rulePath) "plugins/aura-distill/rules/AGENTS.md exists (discovery path)"
if (Test-Path $rulePath) {
    $ruleContent = Get-Content $rulePath -Raw
    Assert-True ($ruleContent -match 'SPINE\.md') "rules/AGENTS.md references SPINE.md"
    Assert-True ($ruleContent -match 'distill-monitor\.md') "rules/AGENTS.md defers to the canonical monitor (INBOX, pressure)"
    Assert-True ($ruleContent -match '\.needs-migration') "rules/AGENTS.md carries the migration gate"
    Assert-True ($ruleContent -match '\[NON-NEGOTIABLE\]') "rules/AGENTS.md contains cognitive markers"
    Assert-True ($ruleContent -match 'origin') "rules/AGENTS.md contains origin tracking"
    Assert-True ($ruleContent -notmatch '\{DISTILL_DIR\}/bin') "rules/AGENTS.md does not point at a nonexistent knowledge-dir bin/"
}

# Test 4: no stale duplicates outside the plugin (single canonical location)
Assert-True (-not (Test-Path (Join-Path $repoRoot 'skills'))) "no root-level skills/ duplicate"
Assert-True (-not (Test-Path (Join-Path $repoRoot 'rules\distill-agy.md'))) "no root-level rules/distill-agy.md duplicate"

# Test 5: bin/distill-recent-agy.ps1 behaves against a fixture
$scriptPath = Join-Path $repoRoot 'bin\distill-recent-agy.ps1'
Assert-True (Test-Path $scriptPath) "bin/distill-recent-agy.ps1 exists"

$tempBrain = Join-Path ([System.IO.Path]::GetTempPath()) ("agy_test_brain_" + [System.Guid]::NewGuid().ToString())
try {
    $sessDir = Join-Path $tempBrain "sess-12345678\.system_generated\logs"
    New-Item -ItemType Directory -Force -Path $sessDir | Out-Null

    $fixtureJsonl = @'
{"step_index":0,"source":"USER_EXPLICIT","type":"USER_INPUT","status":"DONE","created_at":"2026-08-18T18:00:00Z","content":"<USER_REQUEST>\nRefactor the memory caching engine\n</USER_REQUEST>"}
{"step_index":1,"source":"MODEL","type":"PLANNER_RESPONSE","status":"DONE","created_at":"2026-08-18T18:05:00Z","content":"Caching engine refactored and all unit tests are passing cleanly."}
'@
    Set-Content -Path (Join-Path $sessDir "transcript.jsonl") -Value $fixtureJsonl -Encoding utf8

    $nowMs = [DateTimeOffset]::Parse("2026-08-18T19:00:00Z").ToUnixTimeMilliseconds()
    $out = & powershell -ExecutionPolicy Bypass -File $scriptPath -BrainDir $tempBrain -NowMs $nowMs
    $outStr = $out -join "`n"

    Assert-True ($outStr -match 'Antigravity Session Time Index') "Output contains Time Index header"
    Assert-True ($outStr -match 'Refactor the memory caching engine') "Output extracted prompt correctly"
    Assert-True ($outStr -match 'left off: Caching engine refactored') "Output extracted left off correctly"
    Assert-True ($outStr -match '\[sess-123\]') "Output shows the session dir id"
} finally {
    if (Test-Path $tempBrain) {
        Remove-Item -Recurse -Force $tempBrain -ErrorAction SilentlyContinue
    }
}

Write-Host ""
Write-Host "Summary: $script:passCount passed, $script:failCount failed."
if ($script:failCount -gt 0) { exit 1 }
