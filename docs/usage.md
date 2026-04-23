# ssh usage

## Commands

Register and add a specific key:

```bash
dashboard ssh.add id_ed25519
```

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

The skill checks the current `SSH_AUTH_SOCK` first. If that socket is alive, it is reused.

If `SSH_AUTH_SOCK` is missing or points at a dead agent, the skill tries the stable DD-managed socket:

```text
~/.developer-dashboard/ssh-agent/agent.sock
```

If that is also missing or dead, the skill starts:

```bash
ssh-agent -a ~/.developer-dashboard/ssh-agent/agent.sock -s
```

The skill writes:

```text
~/.developer-dashboard/ssh-agent/agent.env
```

with the active `SSH_AUTH_SOCK`, and maintains an SSH config include so normal `ssh` commands can use the stable socket even when a new shell did not inherit the environment variable.

## Collector Behavior

Collector mode compares remembered keys against `ssh-add -l` by fingerprint. If a key is remembered but missing:

- interactive collector runs explain the passphrase request and then run `ssh-add`
- non-interactive collector runs report the missing key in JSON and do not hang

Example missing-key payload shape:

```json
{"mode":"collector","status":"missing","missing":["~/.ssh/id_ed25519"]}
```
