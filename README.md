# ssh

## Description

`ssh` is a Developer Dashboard skill that prepares remembered SSH keys before the user tries to connect.

## Value

It keeps SSH access flowing by asking for passphrases early through `dashboard ssh.add` and the DD collector path instead of interrupting the user later during an actual SSH connection.

## Problem It Solves

Users often discover too late that their SSH key is not loaded. They try to connect, SSH fails or prompts unexpectedly, and then they have to stop what they were doing to run `ssh-add`.

Some systems also start shells without `SSH_AUTH_SOCK`, or leave new terminal sessions unaware of the agent started by another session. That causes repeated passphrase prompts and breaks the DD prompt or collector flow.

## What It Does To Solve It

`ssh` records the keys the user wants DD to manage, ensures a usable ssh-agent exists, keeps a stable managed socket path, and checks remembered keys through a collector named `door-opener`.

The managed socket lives at:

```text
~/.ssh/ssh-agent/agent.sock
```

The skill also writes:

```text
~/.ssh/ssh-agent/agent.env
```

That file contains a shell-readable `SSH_AUTH_SOCK` export for shells or helper workflows that want to source the current managed agent socket. The skill deliberately keeps these files under `~/.ssh/ssh-agent` instead of `~/.developer-dashboard` so users who track their DD root with git do not pick up volatile SSH runtime files.

To make ordinary `ssh` commands work even when a new terminal does not inherit `SSH_AUTH_SOCK`, the skill writes a managed include file:

```text
~/.ssh/developer-dashboard-ssh-agent.conf
```

and adds this line to `~/.ssh/config` when it is not already present:

```text
Include ~/.ssh/developer-dashboard-ssh-agent.conf
```

The include points `IdentityAgent` at the active shared agent socket. If a live socket is already recorded in `agent.env`, new sessions can reuse it. If no live socket exists, the skill starts a managed agent at the stable DD socket and updates the include to that socket.

## Developer Dashboard Feature Added

This skill adds:

- `dashboard ssh.add`
- a skill collector named `ssh.door-opener`
- prompt and indicator integration through the configured collector icon `🚪`

## Installation

Install through Developer Dashboard:

```bash
dashboard skills install git@github.mf:manif3station/ssh.git
```

## CLI Usage

Register and add an explicit key:

```bash
dashboard ssh.add id_ed25519
```

This stores `~/.ssh/id_ed25519` in `config/ssh/keys.txt` and immediately runs `ssh-add` for that key.

Register and add the first available default key:

```bash
dashboard ssh.add
```

The default order is:

- `~/.ssh/id_rsa`
- `~/.ssh/id_ed25519`

Collector mode:

```bash
dashboard ssh.add --collector
```

Collector mode reads the remembered keys, checks `ssh-add -l`, explains missing keys before prompting, and avoids hanging in non-interactive environments.

## Key Registry

Remembered keys are stored in:

```text
config/ssh/keys.txt
```

Examples:

```text
~/.ssh/id_rsa
~/.ssh/id_ed25519
/opt/keys/work_ed25519
```

Rules:

- bare key names such as `id_ed25519` become `~/.ssh/id_ed25519`
- `~/...` paths stay home-relative in the registry
- absolute paths stay absolute
- duplicate key entries are not written twice

## Practical Examples

Normal case:

```bash
dashboard ssh.add id_ed25519
```

Absolute path case:

```bash
dashboard ssh.add ~/.ssh/work_ed25519
```

No default key exists:

```bash
dashboard ssh.add
```

The command exits with a clear message explaining that no default key was found.

Collector check:

```bash
dashboard ssh.add --collector
```

If a remembered key is missing from `ssh-add -l` and the collector is running with an interactive terminal, the skill explains why it is asking for the passphrase before it runs `ssh-add`.

If the collector is non-interactive, it reports the missing key in JSON instead of hanging on a passphrase prompt.

Inspect skill metadata:

```bash
dashboard skills usage ssh
```

Uninstall:

```bash
dashboard skills uninstall ssh
```

## Edge Cases

- duplicate keys are not written twice
- missing `SSH_AUTH_SOCK` starts or reuses the managed agent
- a dead `SSH_AUTH_SOCK` starts or reuses the managed agent
- a live existing `SSH_AUTH_SOCK` is reused and written to the shell-readable env file
- when a new session has no `SSH_AUTH_SOCK`, the skill reads the saved env file and reuses that socket if it is still alive
- collector mode does not hang when there is no interactive terminal
- the skill does not overwrite the user's existing `~/.ssh/config`; it adds a managed include block only when needed
- if a configured key has no `.pub` file, the collector treats it as missing because it cannot safely compare the fingerprint against `ssh-add -l`

## Documentation

See:

- `docs/overview.md`
- `docs/usage.md`
- `docs/changes/2026-04-23-bootstrap.md`
