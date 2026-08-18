# Test runner for aura-distill Antigravity (agy) connector
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..\..')
Write-Host "Testing Antigravity connector in: $repoRoot"

$passCount = 0
$failCount = 0

function Assert-True([bool]$condition, [string]$message) {
    if ($condition) {
        Write-Host "  [PASS] $message" -ForegroundColor Green
        $global:passCount++
    } else {
        Write-Host "  [FAIL] $message" -ForegroundColor Red
        $global:failCount++
    }
}

# Test 1: Check skills/distill/SKILL.md
$skillPath = Join-Path $repoRoot 'skills\distill\SKILL.md'
Assert-True (Test-Path $skillPath) "skills/distill/SKILL.md exists"
if (Test-Path $skillPath) {
    $content = Get-Content $skillPath -Raw
    Assert-True ($content -match 'name:\s*distill') "SKILL.md contains name: distill frontmatter"
    Assert-True ($content -match 'SPINE\.md') "SKILL.md references SPINE.md"
    Assert-True ($content -match 'invoke_subagent') "SKILL.md references Antigravity subagent invocation"
}

# Test 2: Check rules/distill-agy.md
$rulePath = Join-Path $repoRoot 'rules\distill-agy.md'
Assert-True (Test-Path $rulePath) "rules/distill-agy.md exists"
if (Test-Path $rulePath) {
    $ruleContent = Get-Content $rulePath -Raw
    Assert-True ($ruleContent -match 'SPINE\.md') "rules/distill-agy.md references SPINE.md"
    Assert-True ($ruleContent -match '\[NON-NEGOTIABLE\]') "rules/distill-agy.md contains cognitive markers"
    Assert-True ($ruleContent -match 'Memory Pressure') "rules/distill-agy.md contains active memory pressure monitoring"
    Assert-True ($ruleContent -match 'origin') "rules/distill-agy.md contains origin tracking"
}

# Test 3: Check plugins/aura-distill/plugin.json
$pluginPath = Join-Path $repoRoot 'plugins\aura-distill\plugin.json'
Assert-True (Test-Path $pluginPath) "plugins/aura-distill/plugin.json exists"
if (Test-Path $pluginPath) {
    $pluginJson = Get-Content $pluginPath -Raw | ConvertFrom-Json
    Assert-True ($pluginJson.name -eq 'aura-distill') "plugin.json has name aura-distill"
    Assert-True ($pluginJson.skills -contains 'skills/distill') "plugin.json declares skills/distill"
    Assert-True ($pluginJson.rules -contains 'rules/distill-agy.md') "plugin.json declares rules/distill-agy.md"
}

# Test 4: Check bin/distill-recent-agy.ps1 with fixture
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
} finally {
    if (Test-Path $tempBrain) {
        Remove-Item -Recurse -Force $tempBrain -ErrorAction SilentlyContinue
    }
}

Write-Host ""
Write-Host "Summary: $passCount passed, $failCount failed."
if ($failCount -gt 0) { exit 1 }
