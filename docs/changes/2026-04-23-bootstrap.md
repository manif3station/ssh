# ssh bootstrap

## Summary

Bootstrap the `ssh` skill with smart key registration, managed ssh-agent repair, and collector-backed key readiness checks.

## Included

- `dashboard ssh.add`
- `config/ssh/keys.txt` key registry
- `door-opener` collector configuration
- managed ssh-agent socket state
- shell-readable agent env file
- SSH config include for `IdentityAgent`
- saved agent env reuse for sessions that start without `SSH_AUTH_SOCK`
- managed ssh-agent files under `~/.ssh/ssh-agent` instead of the DD runtime root
