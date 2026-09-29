# Leading - West Coast Fitness Club

Benchmark repository comparing a `WestCoastFitness-positive` and `WestCoastFitness-negative`
implementation of the same application, technology stack, and toolchain.

## Branches

- `WestCoastFitness-positive` — implementation intended to pass the supplied metric thresholds.
- `WestCoastFitness-negative` — implementation intended to violate the supplied metric thresholds.

Both branches share the same technology baseline (Node.js 22 LTS, React, Vite, TypeScript,
.NET SDK 8, ASP.NET Core 8, EF Core 8, PostgreSQL 16.x, PowerShell 7.4+, Bash 5.x) and the same
metric tooling and thresholds. They differ only in code/test/security/dependency/history quality.

Each branch builds independently into its own `artifacts/<branch>/` tree; see
`scripts/build.ps1` / `scripts/build.sh` for the branch-aware build entry point.

_Re-run trigger: 2026-09-29T15:14:17Z_
