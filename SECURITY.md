# Security policy

## Supported versions

The `main` branch is the supported version. Fixes land there first.

## Reporting a problem

Please **do not** open a public issue for a security problem.

Use GitHub's private reporting form: **Security → Report a vulnerability** on
<https://github.com/omargablx02/ad-automation-powershell>. If that is not available,
open a regular issue that describes the impact only, without reproduction details, and
ask for a private channel.

Expect an initial reply within a few days.

## Scope

These scripts perform privileged operations against Active Directory. In scope:

- Anything that writes to the wrong container, or acts on the wrong object, because of
  a parsing or validation flaw.
- Any path where a credential, password or token is written to disk, logged, or exposed
  in the console.
- Any input (CSV row, OU name, computer name) that can be used to inject an unexpected
  LDAP filter or distinguished name.
- Deletion or protection-bypass paths that can run without confirmation.

Out of scope:

- Misconfiguration of the lab itself (weak domain passwords, missing backups).
- Running the scripts with Domain Administrator rights and then complaining they are
  powerful. They are supposed to be.

## Design commitments

- No password is stored in the repository or written to disk.
- New accounts are created with `ChangePasswordAtLogon` forced.
- Destructive scripts require an explicit confirmation unless `-Force` is passed.
- Objects are created with accidental-deletion protection on.
