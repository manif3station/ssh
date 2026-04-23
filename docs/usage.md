# ssh usage

## Commands

Register and add a specific key:

```bash
dashboard ssh.add id_ed25519
```

If the key exists, the command registers `~/.ssh/id_ed25519`, starts or reuses a usable agent, and runs `ssh-add` immediately. The JSON result includes:

- `registry`: the installed skill registry path, normally `~/.developer-dashboard/skills/ssh/config/ssh/keys.txt`
- `shell_env`: the env file at `~/.ssh/ssh-agent/agent.env`
- `shell_source`: the command to update the current shell, `source ~/.ssh/ssh-agent/agent.env`

If the key does not exist, the command fails before writing to the registry:

```bash
dashboard ssh.add id_rsa
```

Expected behavior:

```text
SSH key not found: ~/.ssh/id_rsa ...
```

If that key was already remembered by an older failed run, the failed command removes the stale remembered entry and keeps the other keys.

Run with no argument to use the first existing default key:

```bash
dashboard ssh.add
```

Run the collector check:

```bash
dashboard ssh.add --collector
```

Installed through DD, the collector runs this command every 10 seconds through `config/config.json`.

## Key Registry

The key registry is:

```text
config/ssh/keys.txt
```

Bare key names are stored as home-relative paths such as:

```text
~/.ssh/id_ed25519
```

Duplicate paths are not written twice.

## Agent Behavior

The skill checks the current `SSH_AUTH_SOCK` first. If that socket is alive, it is reused and written to the managed env file.

If `SSH_AUTH_SOCK` is missing, the skill reads:

```text
~/.ssh/ssh-agent/agent.env
```

and reuses that saved socket when it is still alive.

If no saved socket is usable, the skill tries the stable DD-managed socket:

```text
~/.ssh/ssh-agent/agent.sock
```

If that is also missing or dead, the skill starts:

```bash
ssh-agent -a ~/.ssh/ssh-agent/agent.sock -s
```

The skill writes:

```text
~/.ssh/ssh-agent/agent.env
```

with the active `SSH_AUTH_SOCK`, and maintains an SSH config include so normal `ssh` commands can use the active shared socket even when a new shell did not inherit the environment variable.

The skill also appends one managed source line to the detected shell startup file:

```bash
[ -f "$HOME/.ssh/ssh-agent/agent.env" ] && . "$HOME/.ssh/ssh-agent/agent.env"
```

The selected file is `~/.bashrc` for bash, `~/.zshrc` for zsh, and `~/.profile` otherwise. This affects new shells. To update the current shell after the first successful add, run:

```bash
source ~/.ssh/ssh-agent/agent.env
```

The managed socket and env file are intentionally kept outside `~/.developer-dashboard` so DD runtime folders remain clean for users who track them with git.

## Collector Behavior

Collector mode compares remembered keys against `ssh-add -l` by fingerprint. If a key is remembered but missing:

- interactive collector runs explain the passphrase request and then run `ssh-add`
- non-interactive collector runs report the missing key in JSON and do not hang

Example missing-key payload shape:

```json
{"mode":"collector","status":"missing","missing":["~/.ssh/id_ed25519"]}
```
