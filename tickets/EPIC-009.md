# EPIC-009

## Title

Keep `ssh` agent runtime outside DD root.

## Outcome

Move volatile ssh-agent socket and env files to `~/.ssh/ssh-agent` so users who track their Developer Dashboard root with git do not pick up unnecessary runtime files.

## Tickets

- `DD-036` Move managed ssh-agent files under `~/.ssh/ssh-agent`
