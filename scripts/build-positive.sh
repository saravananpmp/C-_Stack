#!/usr/bin/env bash
# Builds the positive benchmark branch. Stops at the first failing step,
# since the positive branch is expected to pass every step cleanly.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
source scripts/lib/common.sh

VARIANT=positive
clean_artifacts "$VARIANT"

echo "== Frontend build (${VARIANT}) =="
pushd frontend >/dev/null
npm ci
npm run typecheck
npm run lint
npm run test
npm run test:coverage
npm run build
popd >/dev/null

cp -r frontend/dist/. "artifacts/${VARIANT}/frontend/"
[ -d frontend/coverage ] && cp -r frontend/coverage/. "artifacts/${VARIANT}/coverage/frontend/"

echo "== Backend build (${VARIANT}) =="
dotnet restore backend/WestCoastFitness.sln
dotnet build backend/WestCoastFitness.sln --configuration Release
dotnet test backend/WestCoastFitness.sln --configuration Release \
  --results-directory "artifacts/${VARIANT}/tests" \
  --settings backend/tests/WestCoastFitness.Api.Tests/coverlet.runsettings

find "artifacts/${VARIANT}/tests" -name "coverage.cobertura.xml" -exec cp {} "artifacts/${VARIANT}/coverage/backend/" \;

dotnet publish backend/src/WestCoastFitness.Api/WestCoastFitness.Api.csproj \
  --configuration Release \
  --output "artifacts/${VARIANT}/backend"

write_build_info "$VARIANT"

echo "Positive build complete: artifacts/${VARIANT}/"
