# Builds the negative benchmark branch. Unlike build-positive.ps1, this does
# NOT stop at the first failing step: the negative branch is expected to
# violate quality gates, and every failure must still be collected so the
# full evidence set (tests, coverage, lint, etc.) ends up in artifacts/negative/.
Set-Location (Split-Path -Parent $PSScriptRoot)
. ./scripts/lib/common.ps1

$Variant = 'negative'
Reset-Artifacts -Variant $Variant

$Failures = [System.Collections.Generic.List[string]]::new()

Push-Location frontend
Invoke-Step -Name "frontend npm ci" -Action { npm ci } -Failures $Failures
Invoke-Step -Name "frontend typecheck" -Action { npm run typecheck } -Failures $Failures
Invoke-Step -Name "frontend lint" -Action { npm run lint } -Failures $Failures
Invoke-Step -Name "frontend test" -Action { npm run test } -Failures $Failures
Invoke-Step -Name "frontend test:coverage" -Action { npm run test:coverage } -Failures $Failures
Invoke-Step -Name "frontend build" -Action { npm run build } -Failures $Failures
Pop-Location

New-Item -ItemType Directory -Force -Path "artifacts/$Variant/frontend" | Out-Null
if (Test-Path frontend/dist) {
    Copy-Item -Recurse -Force frontend/dist/* "artifacts/$Variant/frontend/"
}
if (Test-Path frontend/coverage) {
    Copy-Item -Recurse -Force frontend/coverage/* "artifacts/$Variant/coverage/frontend/"
}

Invoke-Step -Name "backend restore" -Action { dotnet restore backend/WestCoastFitness.sln } -Failures $Failures
Invoke-Step -Name "backend build" -Action { dotnet build backend/WestCoastFitness.sln --configuration Release } -Failures $Failures
Invoke-Step -Name "backend test" -Action {
    dotnet test backend/WestCoastFitness.sln --configuration Release `
        --results-directory "artifacts/$Variant/tests" `
        --settings backend/tests/WestCoastFitness.Api.Tests/coverlet.runsettings
} -Failures $Failures

if (Test-Path "artifacts/$Variant/tests") {
    Get-ChildItem -Recurse -Path "artifacts/$Variant/tests" -Filter "coverage.cobertura.xml" -ErrorAction SilentlyContinue |
        Copy-Item -Destination "artifacts/$Variant/coverage/backend/" -ErrorAction SilentlyContinue
}

Invoke-Step -Name "backend publish" -Action {
    dotnet publish backend/src/WestCoastFitness.Api/WestCoastFitness.Api.csproj `
        --configuration Release `
        --output "artifacts/$Variant/backend"
} -Failures $Failures

Write-BuildInfo -Variant $Variant

if ($Failures.Count -gt 0) {
    $Failures | Set-Content -Path "artifacts/$Variant/metrics/build-failures.txt"
    Write-Host "Negative build finished with $($Failures.Count) failing step(s) (expected for this branch): $($Failures -join ', ')"
}
else {
    Write-Host "Negative build finished with no failing steps."
}
