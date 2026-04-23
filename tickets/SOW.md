# SOW-008

## Title

Create the `ssh` skill.

## Objective

Deliver a Developer Dashboard skill that prepares remembered SSH keys before the user needs them, keeps a usable ssh-agent available, and avoids repeated passphrase prompts across new DD prompt sessions and collectors.

## Deliverables

- `dashboard ssh.add` CLI command
- `dashboard ssh.list` CLI command
- `dashboard ssh.ls` CLI alias
- skill collector named `door-opener`
- key registry at `config/ssh/keys.txt`
- managed ssh-agent socket repair
- shell startup bridge for `~/.ssh/ssh-agent/agent.env`
- clear missing-key validation before registry writes
- table and JSON managed-key inspection output
- Docker-based tests with `100%` coverage
- README, docs, changelog, ticket records, release commit, and release push
