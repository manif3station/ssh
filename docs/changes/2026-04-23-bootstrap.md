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
- quiet stale-agent health checks so raw `ssh-add -l` socket errors are not leaked during `ssh.add`
- explicit missing-key validation before registry writes or `ssh-add`
- stale registry cleanup when an explicit missing key was remembered by an older failed run
- clean user-facing error messages without Perl source file suffixes for expected command failures
- shell startup bridge for `~/.ssh/ssh-agent/agent.env`
- successful add output that includes the registry, shell env file, and source command
- `dashboard ssh.list` and `dashboard ssh.ls` for managed-key inspection
- table and JSON output modes for key listing
- loaded, not-loaded, and missing-file status reporting for remembered keys
- active-socket use for add, list, and collector flows when the live socket differs from the default managed path
- already-loaded detection so `ssh.add` skips repeated passphrase prompts
