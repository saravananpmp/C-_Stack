# Shared metric-collection steps used by run-positive-metrics.ps1 and
# run-negative-metrics.ps1. Each function is best-effort: if the underlying
# tool is missing or errors out, it records a note instead of aborting the
# whole metrics run, since collection must continue on the negative branch
# and there's no reason to duplicate that logic per branch.

function Invoke-LintMetric {
    param([string]$Variant)
    $out = "artifacts/$Variant/lint"
    Write-Host "== lint ($Variant) =="

    Push-Location frontend
    npx oxlint --format json 1> "../$out/frontend-oxlint.json" 2> "../$out/frontend-oxlint.stderr.log"
    Pop-Location

    dotnet build backend/WestCoastFitness.sln --configuration Release *> "$out/backend-build-warnings.log"
}

function Invoke-ScaMetric {
    param([string]$Variant)
    $out = "artifacts/$Variant/sca"
    Write-Host "== sca / dependency scan ($Variant) =="

    Push-Location frontend
    npm audit --json 1> "../$out/frontend-npm-audit.json" 2> "../$out/frontend-npm-audit.stderr.log"
    Pop-Location

    dotnet list backend/WestCoastFitness.sln package --vulnerable --include-transitive *> "$out/backend-vulnerable-packages.txt"
}

function Invoke-SastMetric {
    param([string]$Variant)
    $out = "artifacts/$Variant/sast"
    Write-Host "== sast ($Variant) =="

    if (Get-Command semgrep -ErrorAction SilentlyContinue) {
        semgrep --config auto --json --output "$out/semgrep.json" frontend/src backend/src *> "$out/semgrep.log"
    }
    else {
        "semgrep not found on PATH; skipping SAST scan." | Set-Content "$out/SKIPPED.txt"
    }
}

function Invoke-DuplicationMetric {
    param([string]$Variant)
    $out = "artifacts/$Variant/duplication"
    Write-Host "== duplication ($Variant) =="

    try {
        npx --yes jscpd frontend/src backend/src --reporters json,console --output "$out" *> "$out/jscpd.log"
    }
    catch {
        "jscpd could not be resolved (no network/registry access); skipping duplication scan." | Set-Content "$out/SKIPPED.txt"
    }
}

function Invoke-MutationMetric {
    param([string]$Variant)
    $out = "artifacts/$Variant/mutation"
    Write-Host "== mutation testing ($Variant) =="

    try {
        Push-Location backend/tests/WestCoastFitness.Api.Tests
        dotnet tool run dotnet-stryker --config-file stryker-config.json --output "../../../$out/backend" *> "../../../$out/backend-stryker.log"
        Pop-Location
    }
    catch {
        Pop-Location -ErrorAction SilentlyContinue
        "Stryker.NET run failed or is unavailable; see $out/backend-stryker.log" | Set-Content "$out/backend-SKIPPED.txt"
    }

    try {
        Push-Location frontend
        npx --yes stryker run *> "../$out/frontend-stryker.log"
        if (Test-Path reports/mutation) {
            New-Item -ItemType Directory -Force -Path "../$out/frontend" | Out-Null
            Copy-Item -Recurse -Force reports/mutation/* "../$out/frontend/"
        }
        Pop-Location
    }
    catch {
        Pop-Location -ErrorAction SilentlyContinue
        "StrykerJS run failed or is unavailable; see $out/frontend-stryker.log" | Set-Content "$out/frontend-SKIPPED.txt"
    }
}

function Write-MetricsSummary {
    param([string]$Variant)
    $out = "artifacts/$Variant/metrics/summary.json"

    $frontendCobertura = "artifacts/$Variant/coverage/frontend/cobertura-coverage.xml"
    $backendCobertura = Get-ChildItem -Recurse -Path "artifacts/$Variant/coverage/backend" -Filter "*.xml" -ErrorAction SilentlyContinue | Select-Object -First 1

    $frontendLineRate = $null
    $backendLineRate = $null

    if (Test-Path $frontendCobertura) {
        $content = Get-Content $frontendCobertura -Raw
        if ($content -match 'line-rate="([0-9.]+)"') { $frontendLineRate = [double]$Matches[1] }
    }

    if ($backendCobertura) {
        $content = Get-Content $backendCobertura.FullName -Raw
        if ($content -match 'line-rate="([0-9.]+)"') { $backendLineRate = [double]$Matches[1] }
    }

    $summary = [ordered]@{
        branch                 = $Variant
        frontendLineCoverage   = $frontendLineRate
        backendLineCoverage    = $backendLineRate
        generatedAtUtc         = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
    }

    $summary | ConvertTo-Json | Set-Content -Path $out -Encoding utf8
    Write-Host "Metrics summary written to $out"
}
