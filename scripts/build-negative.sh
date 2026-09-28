#!/usr/bin/env bash
# Builds the negative benchmark branch. Unlike build-positive.sh, this does
# NOT stop at the first failing step: the negative branch is expected to
# violate quality gates, and every failure must still be collected so the
# full evidence set (tests, coverage, lint, etc.) ends up in artifacts/negative/.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
source scripts/lib/common.sh

VARIANT=negative
clean_artifacts "$VARIANT"

FAILURES=()

pushd frontend >/dev/null
run_step "frontend npm ci" npm ci
run_step "frontend typecheck" npm run typecheck
run_step "frontend lint" npm run lint
run_step "frontend test" npm run test
run_step "frontend test:coverage" npm run test:coverage
run_step "frontend build" npm run build
popd >/dev/null

mkdir -p "artifacts/${VARIANT}/frontend"
[ -d frontend/dist ] && cp -r frontend/dist/. "artifacts/${VARIANT}/frontend/"
[ -d frontend/coverage ] && cp -r frontend/coverage/. "artifacts/${VARIANT}/coverage/frontend/"

run_step "backend restore" dotnet restore backend/WestCoastFitness.sln
run_step "backend build" dotnet build backend/WestCoastFitness.sln --configuration Release
run_step "backend test" dotnet test backend/WestCoastFitness.sln --configuration Release \
  --results-directory "artifacts/${VARIANT}/tests" \
  --settings backend/tests/WestCoastFitness.Api.Tests/coverlet.runsettings

find "artifacts/${VARIANT}/tests" -name "coverage.cobertura.xml" -exec cp {} "artifacts/${VARIANT}/coverage/backend/" \; 2>/dev/null || true

run_step "backend publish" dotnet publish backend/src/WestCoastFitness.Api/WestCoastFitness.Api.csproj \
  --configuration Release \
  --output "artifacts/${VARIANT}/backend"

write_build_info "$VARIANT"

if [ "${#FAILURES[@]}" -gt 0 ]; then
  printf '%s\n' "${FAILURES[@]}" > "artifacts/${VARIANT}/metrics/build-failures.txt"
  echo "Negative build finished with ${#FAILURES[@]} failing step(s) (expected for this branch): ${FAILURES[*]}"
else
  echo "Negative build finished with no failing steps."
fi
