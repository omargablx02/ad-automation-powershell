# Changelog

All notable changes to this project are documented in this file.
The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the
project uses [Semantic Versioning](https://semver.org/).

## [1.0.0] - 2026-11-05

### Added

- `Auto_OU.ps1` — build an OU tree from a CSV with a placeholder domain.
- `AddUser.ps1` — numbered user series with a forced password change.
- `AddUser_csv.ps1` — users from a CSV, with column validation.
- `ADComputer.ps1` — computer objects protected from accidental deletion.
- `Move_ADComputer.ps1` — move a computer between OUs, protection handled.
- `Remove_Computer.ps1` — unlock, confirm, delete.
- `Remove.ps1` — remove the numbered user series.
- `Remove_csv.ps1` — remove the users listed in a CSV.
- Sample `users.csv` (20 names) and `OUs_To_Create.csv` (6 OUs under one root).
- README with screenshots from the recorded lab run.

### Changed

- Domain, DN and UPN suffix are read with `Get-ADDomain` instead of being hardcoded.
- CSV defaults resolve from `$PSScriptRoot`, so the folder runs from any path.
- Passwords are read with `Read-Host -AsSecureString`; nothing is stored on disk.
- Every create/remove reports `[ OK ]`, `[SKIP]`, `[DEL ]` or `[FAIL]` per object, then
  a `Created / Skipped / Failed` summary.

### Added (tooling)

- `-WhatIf` and `-Confirm` support on every mutating script.
- `-Force` on `Remove_Computer.ps1` for unattended runs.
- Parameter validation on names, counts and OU names.
- PSScriptAnalyzer settings and a GitHub Actions workflow that parses every script with
  Windows PowerShell 5.1 and lints the repository on each push.
