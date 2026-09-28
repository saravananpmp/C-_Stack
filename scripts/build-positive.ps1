# Builds the positive benchmark branch. Stops at the first failing step,
# since the positive branch is expected to pass every step cleanly.
$ErrorActionPreference = 'Stop'
Set-Location (Split-Path -Parent $PSScriptRoot)
. ./scripts/lib/common.ps1

$Variant = 'positive'
Reset-Artifacts -Variant $Variant

Write-Host "== Frontend build ($Variant) =="
Push-Location frontend
npm ci
if ($LASTEXITCODE -ne 0) { throw "npm ci failed" }
npm run typecheck
if ($LASTEXITCODE -ne 0) { throw "typecheck failed" }
npm run lint
if ($LASTEXITCODE -ne 0) { throw "lint failed" }
npm run test
if ($LASTEXITCODE -ne 0) { throw "test failed" }
npm run test:coverage
if ($LASTEXITCODE -ne 0) { throw "test:coverage failed" }
npm run build
if ($LASTEXITCODE -ne 0) { throw "build failed" }
Pop-Location

Copy-Item -Recurse -Force frontend/dist/* "artifacts/$Variant/frontend/"
if (Test-Path frontend/coverage) {
    Copy-Item -Recurse -Force frontend/coverage/* "artifacts/$Variant/coverage/frontend/"
}

Write-Host "== Backend build ($Variant) =="
dotnet restore backend/WestCoastFitness.sln
if ($LASTEXITCODE -ne 0) { throw "dotnet restore failed" }
dotnet build backend/WestCoastFitness.sln --configuration Release
if ($LASTEXITCODE -ne 0) { throw "dotnet build failed" }
dotnet test backend/WestCoastFitness.sln --configuration Release `
    --results-directory "artifacts/$Variant/tests" `
    --settings backend/tests/WestCoastFitness.Api.Tests/coverlet.runsettings
if ($LASTEXITCODE -ne 0) { throw "dotnet test failed" }

Get-ChildItem -Recurse -Path "artifacts/$Variant/tests" -Filter "coverage.cobertura.xml" |
    Copy-Item -Destination "artifacts/$Variant/coverage/backend/"

dotnet publish backend/src/WestCoastFitness.Api/WestCoastFitness.Api.csproj `
    --configuration Release `
    --output "artifacts/$Variant/backend"
if ($LASTEXITCODE -ne 0) { throw "dotnet publish failed" }

Write-BuildInfo -Variant $Variant

Write-Host "Positive build complete: artifacts/$Variant/"
