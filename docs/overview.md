# ssh overview

`ssh` is a Developer Dashboard skill that keeps remembered SSH keys ready before the user starts an SSH connection.

It records key paths in `~/.ssh/keys.txt`, ensures there is a usable ssh-agent, shares a managed agent socket across shell sessions, and lets a DD collector prompt early when configured keys are missing from the agent.

The skill is intentionally proactive. It moves passphrase prompts to the beginning of the workflow, either when the user explicitly runs `dashboard ssh.add` or when the `door-opener` collector sees that remembered keys are absent from the agent.

The skill also includes `dashboard ssh.list` and the alias `dashboard ssh.ls` so users can inspect the registry without opening `~/.ssh/keys.txt`. List mode reports each managed key, its expanded filesystem path, whether it is loaded in `ssh-add -l`, and its fingerprint when available.

It now also ships `dashboard ssh.bridge`, which reuses the same managed ssh-agent flow for direct bridge connections and adds the required command-line SSH options automatically for hosts ending in `.b`, including an optional remote-forward port.

## Runtime Design

- remembered keys live in `~/.ssh/keys.txt`
- `dashboard ssh.list` reads that registry and reports `loaded`, `not-loaded`, or `missing-file`
- `dashboard ssh.bridge` ensures `~/.ssh/id_ed25519` is loaded before it runs `ssh`
- the managed socket is `~/.ssh/ssh-agent/agent.sock`
- the shell-readable env file is `~/.ssh/ssh-agent/agent.env`
- a shell startup bridge sources `~/.ssh/ssh-agent/agent.env` from `~/.bashrc`, `~/.zshrc`, or `~/.profile`
- the SSH config bridge is `~/.ssh/developer-dashboard-ssh-agent.conf`
- the user's `~/.ssh/config` receives one managed `Include` line when needed

This design avoids the single-session trap. Starting an agent in one terminal is not enough unless later terminals and collectors can find the same socket. The saved env file lets the skill rediscover a live socket when `SSH_AUTH_SOCK` is missing, and the managed `IdentityAgent` include gives `ssh` a persistent path to the active shared agent.

The skill now uses that active socket consistently for `ssh.add`, list mode, and collector checks. That avoids failures on systems where the actual live socket selected by `ssh-agent` differs from the default managed path.

`ssh.add` is now idempotent for already loaded keys. If the key fingerprint is already present in the active agent, the skill records that under `already_loaded` and skips another `ssh-add` passphrase prompt.

The collector now has three explicit prompt modes when remembered keys are missing:

- interactive terminal: explain the reason and run `ssh-add` in the terminal
- non-interactive desktop session: explain the reason and run `ssh-add` through a GUI askpass backend
- non-interactive without GUI support: return `missing` and a nonzero exit so DD can show an alert indicator state

The current shell cannot inherit environment changes from the completed `dashboard ssh.add` child process. After the first successful add, users can run `source ~/.ssh/ssh-agent/agent.env` to update the current shell immediately; later shells get the same value from the managed startup bridge.

For bridge hosts ending in `.b`, `dashboard ssh.bridge` can inject `RemoteForward <port> localhost:22` along with `ExitOnForwardFailure=yes`, `ServerAliveInterval=60`, `SessionType=none`, and `RequestTTY=no` through `ssh -o ...` arguments instead of asking the user to maintain that behavior manually in `~/.ssh/config`.

When the bridge identity is not already loaded, interactive bridge runs now fall back to plain terminal `ssh-add ~/.ssh/id_ed25519` prompting before they try the SSH connection. Non-interactive bridge runs still require one of the documented bridge passphrase environment variables.

Explicit keys are validated before registration. If `dashboard ssh.add id_rsa` points to a missing `~/.ssh/id_rsa`, the skill returns a clear `SSH key not found` error and does not write the missing key to `~/.ssh/keys.txt`. If the missing key is already present from an older failed run, the skill removes that stale entry and leaves the rest of the registry intact.

If an older installed skill still has a remembered-key file at `config/ssh/keys.txt`, the next command run moves that legacy file into `~/.ssh/keys.txt` before add, list, or collector logic continues.

The socket and env file stay under `~/.ssh/ssh-agent`, not under `~/.developer-dashboard`, because some users track their DD runtime root with git and should not see volatile SSH agent files in that tree.
