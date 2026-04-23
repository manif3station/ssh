# ssh collector prompting

## Summary

Tighten `ssh.door-opener` so missing remembered keys are surfaced early and correctly for both desktop and non-desktop environments.

## Included

- non-interactive collector runs now use an askpass-backed `ssh-add` path when a desktop session and supported askpass backend are available
- interactive collector runs still explain why the passphrase is needed before running `ssh-add`
- non-GUI non-interactive collector runs now return status `missing` and a nonzero exit so DD can show an alert indicator state
- tests cover terminal prompt mode, GUI askpass mode, and non-GUI alert mode
