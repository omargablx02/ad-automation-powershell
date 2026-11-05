# Active Directory Automation — PowerShell

Eight small PowerShell scripts for the repetitive parts of AD administration:
create users, create computers, move objects between OUs, and delete them safely.

Every script detects the domain at runtime, checks what already exists, and ends the
run with a per-object result. Built and recorded on Windows Server 2022 + a Windows 7
client, domain `bash.local`.

<p align="center">
  <img src="docs/01-title.jpg" width="49%" alt="Title card of the walkthrough">
  <img src="docs/02-users.jpg" width="49%" alt="Users created in a loop">
  <img src="docs/03-computers.jpg" width="49%" alt="Computer objects protected from deletion">
  <img src="docs/04-ou-tree.jpg" width="49%" alt="OU tree built from a CSV">
</p>

The demo run: **11 users in a loop → 10 users from CSV → 5 computers → 6 OUs**, plus a
real logon on the client with an account the script had just created.

---

## What is in the box

| File | What it does |
|---|---|
| `Auto_OU.ps1` | Builds an OU tree from `OUs_To_Create.csv`, parents first |
| `AddUser.ps1` | Creates numbered users (`User140` … `User150`) in a chosen OU |
| `AddUser_csv.ps1` | Creates users from `users.csv` (Firstname, Lastname) |
| `ADComputer.ps1` | Creates a computer object, protected from accidental deletion |
| `Move_ADComputer.ps1` | Moves a computer between OUs, protection handled for you |
| `Remove_Computer.ps1` | Deletes a computer safely: unlock → confirm → remove |
| `Remove.ps1` | Removes the numbered user series |
| `Remove_csv.ps1` | Removes the users listed in `users.csv` |
| `users.csv` | Sample input: 20 clean names |
| `OUs_To_Create.csv` | Sample OU tree with a placeholder domain |

---

## Requirements

| Item | Detail |
|---|---|
| PowerShell | 5.1 or later (Windows PowerShell is fine) |
| Module | `RSAT-AD-PowerShell` — `Install-WindowsFeature RSAT-AD-PowerShell` on the server, or RSAT on a workstation |
| Rights | Domain Administrator, or delegated rights on the target OUs |
| Execution policy | `Set-ExecutionPolicy -Scope Process Bypass -Force` in the session you run from |
| Host | A domain-joined machine that can reach a domain controller |

Each script starts with `#Requires -RunAsAdministrator` and imports the AD module with
`-ErrorAction Stop`, so it fails fast and clearly when the environment is wrong.

---

## Quick start

Copy the folder to the server (for example `C:\AD_Automation_Release`), then run from an
elevated PowerShell inside it. CSV paths default to `$PSScriptRoot`, so the folder works
from any location.

```powershell
Set-ExecutionPolicy -Scope Process Bypass -Force
Set-Location C:\AD_Automation_Release

# 1. Build the OU tree
.\Auto_OU.ps1

# 2. Numbered users (prompts for a password)
.\AddUser.ps1 -StartAt 140 -Count 11 -OUName Sales_Marketing

# 3. Users from CSV
.\AddUser_csv.ps1 -CsvPath .\users.csv -OUName Sales_Marketing

# 4. A computer, protected on creation
.\ADComputer.ps1 -ComputerName PC-IT-01 -OUName IT_Department

# 5. Move it to another OU (interactive: source OU, destination OU, computer)
.\Move_ADComputer.ps1

# 6. Delete it (interactive confirmation)
.\Remove_Computer.ps1 -ComputerName PC-IT-01

# 7. Clean up the numbered users
.\Remove.ps1 -StartAt 140 -Count 11

# 8. Clean up the CSV users
.\Remove_csv.ps1 -CsvPath .\users.csv
```

`AddUser.ps1` and `AddUser_csv.ps1` ask for the account password with
`Read-Host -AsSecureString`. Nothing is stored on disk and no password is hardcoded.

---

## CSV formats

**users.csv**

```csv
Firstname,Lastname
Ahmed,Hassan
Mohamed,Mansour
```

The SAM is `firstname_lastname` in lower case (`ahmed_hassan`) and the UPN is
`sam@<domain DNS root>`. Duplicate names are skipped, not treated as errors.

**OUs_To_Create.csv**

```csv
Name,Path
Corporate_HQ,"DC=company,DC=local"
IT_Department,"OU=Corporate_HQ,DC=company,DC=local"
Human_Resources,"OU=Corporate_HQ,DC=company,DC=local"
```

`Auto_OU.ps1` replaces the literal `DC=company,DC=local` with the domain of the machine
it runs on (`(Get-ADDomain).DistinguishedName`), sorts rows by path length so parents
exist before children, and creates each OU with accidental-deletion protection on.

---

## Why the scripts look like this

1. **The domain is detected, never typed.** `Get-ADDomain` supplies the DN and the UPN
   suffix. There is no `DC=bash,DC=local` in the code, so the same folder works in
   another lab.
2. **Check before writing.** Every create checks the object first and prints `[SKIP]`
   instead of throwing "already exists". Re-running a script is safe.
3. **Protection by default.** Computers and OUs are created with
   `-ProtectedFromAccidentalDeletion $true`. Deletion is an explicit act.
4. **Unlock, act, re-lock.** A protected object cannot be moved or deleted;
   `Move_ADComputer.ps1` lifts protection only for the move and re-enables it on the
   target. `Remove_Computer.ps1` lifts it only after a typed confirmation.
5. **One failure must not stop the batch.** Each object runs inside its own `try/catch`;
   a bad row is counted and the loop continues.
6. **Every run prints a result.** `Created / Skipped / Failed`, or
   `Deleted / Not found / Failed`, so the operator does not have to read the transcript.
7. **No stored credentials.** The password is read once as a `SecureString`, and
   `ChangePasswordAtLogon` is forced for new accounts.
8. **Names resolve to DNs.** OUs and objects are looked up by name and converted to a
   distinguished name, so a typo gives a clear message instead of writing to the wrong
   container.

---

## Notes and limits

- The scripts are interactive where a human decision is required (password, move
  source/destination, delete confirmation). Wrap them or add parameters for fully
  unattended runs.
- `Auto_OU.ps1` expects the placeholder `DC=company,DC=local` in the CSV. With your own
  CSV, either keep the placeholder or write full DNs.
- `Remove_Computer.ps1` requires typing `Y`. Any other answer cancels and changes nothing.
- `ADComputer.ps1` falls back to `CN=Computers` when the requested OU does not exist,
  and says so in yellow.
- Tested on Windows Server 2022 with Windows PowerShell 5.1.

---

## Video

The recorded walkthrough shows the whole flow end to end, including a logon on a
Windows 7 client with an account the script created: 2:24, captioned, no audio.

Lab: `bash.local` · Windows Server 2022 DC · Windows 7 client.

---

## License

MIT — use it, change it, ship it. See [LICENSE](LICENSE).
