# EPIC-010

## Title

Repair installed `ssh.add` agent flow.

## Outcome

Make the installed `ssh.add` command reliable in normal shell use by removing noisy stale-agent checks, rejecting missing keys clearly, exposing the installed registry path, and giving shells a managed way to source the shared agent env file.

## Tickets

- `DD-037` Fix shell agent bridge and missing-key UX
