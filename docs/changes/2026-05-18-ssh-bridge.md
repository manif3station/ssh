# 2026-05-18 ssh.bridge Governance

## Summary

Promoted the manually added `ssh.bridge` script into a first-class `ssh` skill command with a dedicated module, release-governed tests, and user documentation.

## What Changed

- added `lib/SSH/Bridge.pm` as the tested bridge runtime
- kept `cli/bridge` as the skill entrypoint wrapper for `dashboard ssh.bridge`
- reused the managed ssh-agent flow from the `ssh` skill before connecting
- made bridge hosts ending in `.b` add optional `RemoteForward <port> localhost:22`, `ExitOnForwardFailure=yes`, `ServerAliveInterval=60`, `SessionType=none`, and `RequestTTY=no` directly through SSH command-line options
- made interactive bridge runs fall back to terminal `ssh-add ~/.ssh/id_ed25519` prompting when no bridge passphrase environment variable is set

## Proof

- `prove -lr t` passes with the bridge tests included
- Docker tests and Docker coverage are recorded in `tickets/TESTING.md`
