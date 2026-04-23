# EPIC-013

## Title

Skip re-adding loaded keys.

## Outcome

Make `ssh.add` idempotent for already loaded keys so users are not prompted for the same passphrase again when the key fingerprint is already present in the active agent.

## Tickets

- `DD-040` Skip `ssh-add` when key fingerprint is already loaded
