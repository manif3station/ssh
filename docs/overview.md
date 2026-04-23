# ssh overview

`ssh` is a Developer Dashboard skill that keeps remembered SSH keys ready before the user starts an SSH connection.

It records key paths in `config/ssh/keys.txt`, ensures there is a usable ssh-agent, shares a managed agent socket across shell sessions, and lets a DD collector prompt early when configured keys are missing from the agent.

The skill is intentionally proactive. It moves passphrase prompts to the beginning of the workflow, either when the user explicitly runs `dashboard ssh.add` or when the `door-opener` collector sees that remembered keys are absent from the agent.

## Runtime Design

- remembered keys live in `config/ssh/keys.txt`
- the managed socket is `~/.developer-dashboard/ssh-agent/agent.sock`
- the shell-readable env file is `~/.developer-dashboard/ssh-agent/agent.env`
- the SSH config bridge is `~/.ssh/developer-dashboard-ssh-agent.conf`
- the user's `~/.ssh/config` receives one managed `Include` line when needed

This design avoids the single-session trap. Starting an agent in one terminal is not enough unless later terminals and collectors can find the same socket. The stable socket plus `IdentityAgent` include gives `ssh` a persistent path to the same agent.
