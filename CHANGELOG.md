# Changelog

All notable changes to this project are documented in this file.
The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the
project uses [Semantic Versioning](https://semver.org/).

## [1.2.0] - 2026-11-19

### Added

- `Copy-ADUser.ps1` — clones a template account into a new user: same OU, Title,
  Department, Company, Manager, Office, address fields, phone, description, logon hours,
  Logon Workstations, `PasswordNeverExpires`, `CannotChangePassword` and every
  non-privileged group. The password and the SID are never copied; thirteen built-in
  privileged groups are matched by SID and skipped.
- The new account is named after the person (`CN=Firstname_Lastname`) while the SAM stays
  short. The home folder follows the SAM (`Home\ea`), the roaming profile follows the full
  name (`Profiles\Eslam_Ali`). `-DisplayName`, `-HomeFolderName` and `-ProfileFolderName`
  override either convention.
- New home and profile folders break NTFS inheritance and grant Full Control only to the
  new user, Administrators and SYSTEM.
- A folder that already exists with a stale ACL is repaired instead of skipped: the
  script compares the SID on the folder with the new account's SID, reports `[WARN]` and
  adds the missing entry, so an account recreated with a new RID still reaches its files.
  The missing entry is granted by SID, not by `DOMAIN\sam`, so the repair does not depend
  on the file server resolving the new account name yet.
- Folder ACL writes now stop on error instead of reporting success when `Set-Acl` failed.
- Interactive runs ask for the two folder roots with a default of `\\<this computer>\Home`
  and `\\<this computer>\Profiles`; a single dash skips that folder.
- Eight Pester tests for the copy rules, including the stale-SID folder case — 39 tests
  in total.

### Changed

- README: nine scripts, a new row in the contents table, the copy rules in the safety
  model, and the naming conventions under Notes and limits.

## [1.1.0] - 2026-11-05

### Added

- Pester 5 test suite (`tests/AdAutomation.Tests.ps1`) covering all eight scripts with
  in-memory AD cmdlet stubs — 31 tests, no domain controller required.
- Pester step in the CI workflow, alongside the existing parse, lint and CSV checks.

### Fixed

- `Auto_OU.ps1` now orders rows by OU depth and then by path length, so a parent is
  always queued before its children.
- `Auto_OU.ps1` validates every row before creating anything: empty `Name`/`Path`, an
  invalid character in `Name`, a leftover `DC=company` placeholder, or a path outside
  the current domain aborts the run with the row numbers listed.
- `Remove_Computer.ps1` no longer asks the Y/N question when `-WhatIf` is used.

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
