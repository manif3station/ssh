# SOW-008

## Title

Create the `ssh` skill.

## Objective

Deliver a Developer Dashboard skill that prepares remembered SSH keys before the user needs them, keeps a usable ssh-agent available, avoids repeated passphrase prompts across new DD prompt sessions and collectors, and ships with an explicit MIT license for reuse and distribution.

## Deliverables

- `dashboard ssh.add` CLI command
- `dashboard ssh.list` CLI command
- `dashboard ssh.ls` CLI alias
- `dashboard ssh.bridge` CLI command
- skill collector named `door-opener`
- key registry at `~/.ssh/keys.txt`
- managed ssh-agent socket repair
- shell startup bridge for `~/.ssh/ssh-agent/agent.env`
- bridge SSH option injection for `*.b` hosts
- clear missing-key validation before registry writes
- table and JSON managed-key inspection output
- active-socket use across add, list, and collector flows
- idempotent `ssh.add` behavior for already loaded keys
- bridge reuse of the default `~/.ssh/id_ed25519` identity through the managed agent
- GUI askpass prompting for missing remembered keys during non-interactive collector runs when a desktop session is available
- nonzero collector exit behavior for missing keys when no GUI prompt path is available
- explicit MIT license and README license documentation
- Docker-based tests with `100%` coverage
- README, docs, changelog, ticket records, release commit, and release push
