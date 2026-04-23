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

`dashboard ssh.add` also adds a managed shell startup line to the detected shell profile:

```bash
[ -f "$HOME/.ssh/ssh-agent/agent.env" ] && . "$HOME/.ssh/ssh-agent/agent.env"
```

The target profile is `~/.bashrc` for bash, `~/.zshrc` for zsh, and `~/.profile` otherwise. This makes new shells pick up the managed agent socket. The current already-open shell cannot be modified by a child process, so after the first add you can update the current shell with:

```bash
source ~/.ssh/ssh-agent/agent.env
```

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
- `dashboard ssh.list`
- `dashboard ssh.ls`
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

Successful output includes the exact installed registry and shell env paths:

```json
{"mode":"add","added":["~/.ssh/id_ed25519"],"registry":".../skills/ssh/config/ssh/keys.txt","shell_env":"~/.ssh/ssh-agent/agent.env","shell_source":"source ~/.ssh/ssh-agent/agent.env"}
```

The `agent` field reports the active socket actually used for `ssh-add`. This matters on systems where the live agent socket can differ from the default managed socket path.

If the key does not exist, the command fails before registering the key or calling `ssh-add`:

```bash
dashboard ssh.add id_rsa
```

Example error:

```text
SSH key not found: ~/.ssh/id_rsa (expanded path: ~/.ssh/id_rsa). Create the key first or pass an existing key path.
```

If that missing key was already present from an older failed run, the command removes that stale entry from the registry while keeping other remembered keys.

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

List managed keys as a table:

```bash
dashboard ssh.list
```

`dashboard ssh.ls` is an alias:

```bash
dashboard ssh.ls
```

The table includes:

- `KEY`: the registry entry from `config/ssh/keys.txt`
- `STATUS`: `loaded`, `not-loaded`, or `missing-file`
- `FILE`: the expanded filesystem path used by the program
- `FINGERPRINT`: the key fingerprint when the public key or private key can be read

JSON output:

```bash
dashboard ssh.list -o json
```

Table output can also be requested explicitly:

```bash
dashboard ssh.list -o table
```

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

Inspect managed keys:

```bash
dashboard ssh.list
```

Inspect managed keys as JSON:

```bash
dashboard ssh.ls -o json
```

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
- explicit missing keys are rejected before registration or `ssh-add`
- stale remembered entries for explicitly missing keys are removed during that rejection
- missing `SSH_AUTH_SOCK` starts or reuses the managed agent
- a dead `SSH_AUTH_SOCK` starts or reuses the managed agent without leaking raw `ssh-add -l` errors
- add, collector, and list mode all use the active socket selected by `ensure_agent`
- a live existing `SSH_AUTH_SOCK` is reused and written to the shell-readable env file
- when a new session has no `SSH_AUTH_SOCK`, the skill reads the saved env file and reuses that socket if it is still alive
- new shells source `~/.ssh/ssh-agent/agent.env` through the managed shell profile bridge
- the current shell may need `source ~/.ssh/ssh-agent/agent.env` after the first successful add
- collector mode does not hang when there is no interactive terminal
- list mode works when no keys are configured and returns an empty table or empty JSON list
- list mode marks a remembered key as `missing-file` when the key file no longer exists
- list mode marks a remembered key as `not-loaded` when the file exists but its fingerprint is absent from `ssh-add -l`
- list mode marks a remembered key as `loaded` when the fingerprint is present in `ssh-add -l`
- the skill does not overwrite the user's existing `~/.ssh/config`; it adds a managed include block only when needed
- if a configured key has no `.pub` file, the collector treats it as missing because it cannot safely compare the fingerprint against `ssh-add -l`

## Documentation

See:

- `docs/overview.md`
- `docs/usage.md`
- `docs/changes/2026-04-23-bootstrap.md`
