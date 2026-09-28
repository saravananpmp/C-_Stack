#!/usr/bin/env bash
# Shared metric-collection steps used by run-positive-metrics.sh and
# run-negative-metrics.sh. Each function is best-effort: if the underlying
# tool is missing or errors out, it records a note instead of aborting the
# whole metrics run, since collection must continue on the negative branch
# and there's no reason to duplicate that logic per branch.

metric_lint() {
  local variant="$1"
  local out="artifacts/${variant}/lint"
  echo "== lint (${variant}) =="

  (cd frontend && npx oxlint --format json > "../${out}/frontend-oxlint.json" 2>"../${out}/frontend-oxlint.stderr.log")
  local frontend_status=$?

  dotnet build backend/WestCoastFitness.sln --configuration Release \
    > "${out}/backend-build-warnings.log" 2>&1
  local backend_status=$?

  if [ "$frontend_status" -ne 0 ] || [ "$backend_status" -ne 0 ]; then
    echo "lint: frontend exit=${frontend_status}, backend build exit=${backend_status} (see ${out}/)"
  fi
}

metric_sca() {
  local variant="$1"
  local out="artifacts/${variant}/sca"
  echo "== sca / dependency scan (${variant}) =="

  (cd frontend && npm audit --json > "../${out}/frontend-npm-audit.json" 2>"../${out}/frontend-npm-audit.stderr.log")

  dotnet list backend/WestCoastFitness.sln package --vulnerable --include-transitive \
    > "${out}/backend-vulnerable-packages.txt" 2>&1
}

metric_sast() {
  local variant="$1"
  local out="artifacts/${variant}/sast"
  echo "== sast (${variant}) =="

  if command -v semgrep >/dev/null 2>&1; then
    semgrep --config auto --json --output "${out}/semgrep.json" \
      frontend/src backend/src > "${out}/semgrep.log" 2>&1 || true
  else
    echo "semgrep not found on PATH; skipping SAST scan." > "${out}/SKIPPED.txt"
  fi
}

metric_duplication() {
  local variant="$1"
  local out="artifacts/${variant}/duplication"
  echo "== duplication (${variant}) =="

  if npx --yes jscpd --version >/dev/null 2>&1; then
    npx --yes jscpd frontend/src backend/src \
      --reporters json,console \
      --output "${out}" \
      > "${out}/jscpd.log" 2>&1 || true
  else
    echo "jscpd could not be resolved (no network/registry access); skipping duplication scan." > "${out}/SKIPPED.txt"
  fi
}

metric_mutation() {
  local variant="$1"
  local out="artifacts/${variant}/mutation"
  echo "== mutation testing (${variant}) =="

  (
    cd backend/tests/WestCoastFitness.Api.Tests
    dotnet tool run dotnet-stryker --config-file stryker-config.json \
      --output "../../../${out}/backend"
  ) > "${out}/backend-stryker.log" 2>&1 || echo "Stryker.NET run failed or is unavailable; see ${out}/backend-stryker.log" > "${out}/backend-SKIPPED.txt"

  (
    cd frontend
    npx --yes stryker run > "../${out}/frontend-stryker.log" 2>&1
    mkdir -p "../${out}/frontend"
    [ -d reports/mutation ] && cp -r reports/mutation/. "../${out}/frontend/"
  ) || echo "StrykerJS run failed or is unavailable; see ${out}/frontend-stryker.log" > "${out}/frontend-SKIPPED.txt"
}

metric_summary() {
  local variant="$1"
  local out="artifacts/${variant}/metrics/summary.json"

  local frontend_cobertura="artifacts/${variant}/coverage/frontend/cobertura-coverage.xml"
  local backend_cobertura
  backend_cobertura="$(find "artifacts/${variant}/coverage/backend" -name '*.xml' 2>/dev/null | head -n1)"

  local frontend_line_rate="null"
  local backend_line_rate="null"

  if [ -f "$frontend_cobertura" ]; then
    frontend_line_rate="$(grep -o 'line-rate="[0-9.]*"' "$frontend_cobertura" | head -n1 | grep -o '[0-9.]*')"
    frontend_line_rate="${frontend_line_rate:-null}"
  fi

  if [ -n "$backend_cobertura" ] && [ -f "$backend_cobertura" ]; then
    backend_line_rate="$(grep -o 'line-rate="[0-9.]*"' "$backend_cobertura" | head -n1 | grep -o '[0-9.]*')"
    backend_line_rate="${backend_line_rate:-null}"
  fi

  cat > "$out" <<JSON
{
  "branch": "${variant}",
  "frontendLineCoverage": ${frontend_line_rate},
  "backendLineCoverage": ${backend_line_rate},
  "generatedAtUtc": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
}
JSON

  echo "Metrics summary written to ${out}"
}
