# EPIC-012

## Title

Use the active SSH agent socket.

## Outcome

Make `ssh.add`, collector checks, and list mode consistently use the live socket selected by `ensure_agent`, including systems where that socket differs from the default managed path.

## Tickets

- `DD-039` Fix active socket use for add, list, and collector
