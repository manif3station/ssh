# ssh overview

`ssh` is a Developer Dashboard skill that keeps remembered SSH keys ready before the user starts an SSH connection.

It records key paths in `config/ssh/keys.txt`, ensures there is a usable ssh-agent, shares a managed agent socket across shell sessions, and lets a DD collector prompt early when configured keys are missing from the agent.

The skill is intentionally proactive. It moves passphrase prompts to the beginning of the workflow, either when the user explicitly runs `dashboard ssh.add` or when the `door-opener` collector sees that remembered keys are absent from the agent.

## Runtime Design

- remembered keys live in `config/ssh/keys.txt`
- the managed socket is `~/.ssh/ssh-agent/agent.sock`
- the shell-readable env file is `~/.ssh/ssh-agent/agent.env`
- the SSH config bridge is `~/.ssh/developer-dashboard-ssh-agent.conf`
- the user's `~/.ssh/config` receives one managed `Include` line when needed

This design avoids the single-session trap. Starting an agent in one terminal is not enough unless later terminals and collectors can find the same socket. The saved env file lets the skill rediscover a live socket when `SSH_AUTH_SOCK` is missing, and the managed `IdentityAgent` include gives `ssh` a persistent path to the active shared agent.

The socket and env file stay under `~/.ssh/ssh-agent`, not under `~/.developer-dashboard`, because some users track their DD runtime root with git and should not see volatile SSH agent files in that tree.
