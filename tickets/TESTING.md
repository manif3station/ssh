# ssh testing

## Docker Commands

Functional pass:

```bash
docker compose -f ~/projects/skills/docker-compose.testing.yml run --rm perl-test bash -lc '
cd /workspace/skills/ssh
prove -lr t
'
```

Covered pass:

```bash
docker compose -f ~/projects/skills/docker-compose.testing.yml run --rm perl-test bash -lc '
cd /workspace/skills/ssh
cover -delete
HARNESS_PERL_SWITCHES=-MDevel::Cover prove -lr t
cover -report text
'
```

## Result

- Docker functional suite passed
- Docker covered suite passed
- `lib/SSH/Add.pm` reached `100.0%` statement coverage
- `lib/SSH/Add.pm` reached `100.0%` subroutine coverage
- tests cover explicit key registration, missing explicit-key rejection, default-key fallback, deduplication, missing default-key errors, quiet stale-agent health checks, managed ssh-agent startup, dead `SSH_AUTH_SOCK` repair, live socket reuse, saved agent env parsing, stable socket env writing, shell startup bridge writing, active `IdentityAgent` bridge writing, collector missing-key behavior, interactive collector prompting, non-interactive collector reporting, managed-key list table output, managed-key list JSON output, `loaded`/`not-loaded`/`missing-file` list statuses, active-socket add behavior when the live socket differs from the default path, already-loaded add skipping, and CLI `main` success/error paths

Latest covered result for `DD-040`:

```text
Files=7, Tests=116
lib/SSH/Add.pm    100.0   89.7   67.3  100.0
```

The gate uses the project-required module statement and subroutine thresholds for the skill implementation.

## Latest DD Source Proof

Verified through the latest DD source checkout at:

```bash
~/projects/developer-dashboard
```

The proof used a temporary home and fake `ssh-add`, `ssh-agent`, and `ssh-keygen` tools so the dispatch path was tested without touching real user keys or prompting for a passphrase.

Command shape:

```bash
perl -I~/projects/developer-dashboard/lib ~/projects/developer-dashboard/bin/dashboard ssh.add --collector
```

Observed result:

- valid JSON returned through the DD dotted skill command path
- `mode` was `collector`
- `status` was `ok`
- `loaded` was `0`
- `missing` was an empty list
- the reported agent path used the managed SSH socket under `~/.ssh/ssh-agent/agent.sock`
- `~/.ssh/ssh-agent/agent.env` was created
- no ssh-agent runtime file was created under `~/.developer-dashboard`
- missing explicit keys returned a clear `SSH key not found` message and did not create `config/ssh/keys.txt`
- missing explicit keys did not include a Perl file/line suffix
- successful explicit keys returned `registry`, `shell_env`, and `shell_source`
- the managed shell profile bridge was written for future shells
- `ssh.list` returned table output by default
- `ssh.list -o json` returned structured key status data
- `ssh.ls` matched the list command behavior
- a started agent socket different from the default managed path was used consistently by add and list code paths
- already-loaded keys were returned under `already_loaded` and did not trigger another `ssh-add` call

Latest DD source proof for `DD-038` used a temporary home with a generated no-passphrase test key and verified:

- `dashboard ssh.add demo_key` registered and loaded the key
- `dashboard ssh.list` printed a table with `KEY`, `STATUS`, `FILE`, and `FINGERPRINT`
- `dashboard ssh.list -o json` returned one `loaded` key row
- `dashboard ssh.ls -o json` returned the same list-mode JSON contract
- the reported `agent` field reflected the active socket used by the command
- `dashboard ssh.add --collector` returned `status: missing` with a nonzero exit when no GUI prompt path was available
- `dashboard ssh.add --collector` returned `status: prompted` after a successful askpass-backed add path in a GUI-capable non-interactive session

Latest DD source proof for `DD-039` used a temporary home, a generated no-passphrase key, and a deliberately stale `SSH_AUTH_SOCK=/dead/socket` environment. Verified:

- `dashboard ssh.add demo_key` succeeded and loaded the key
- `dashboard ssh.list -o json` returned the key as `loaded`
- both commands reported the active socket in their `agent` field
- the stale incoming `SSH_AUTH_SOCK` did not break add or list mode

Latest DD source proof for `DD-041` used the latest source checkout and verified two collector cases:

- non-GUI case: a fake `ssh-add -l` path with a remembered test key returned `rc=1`, `status=missing`, and one missing key
- GUI case: a temporary real `ssh-agent`, generated no-passphrase key, and `DISPLAY=:1` returned `rc=0`, `status=prompted`, and zero missing keys

## Installed DD Proof

The fixed skill was installed into the home DD skill root with:

```bash
cd ~
dashboard skills install ~/projects/skills/skills/ssh
```

Observed behavior:

- `dashboard ssh.add id_rsa` returned a clear missing-key error because `~/.ssh/id_rsa` was absent
- the stale `~/.ssh/id_rsa` registry entry was removed
- the valid `~/.ssh/id_ed25519` registry entry remained
- `dashboard ssh.list -o json` decoded successfully through the installed skill
- `dashboard ssh.ls -o json` decoded successfully through the installed skill alias
- the installed skill version is `0.06`
- the installed skill version is `0.07`
- the installed skill version is `0.08`

Installed DD proof for `DD-041` verified the same two collector cases through the installed `dashboard` command:

- non-GUI case: `dashboard ssh.add --collector` returned `rc=1`, `status=missing`, and one missing key
- GUI case: `dashboard ssh.add --collector` returned `rc=0`, `status=prompted`, and zero missing keys while using a temporary real agent and generated key

Latest covered result for `DD-041`:

```text
Files=7, Tests=141
lib/SSH/Add.pm    100.0   88.8   67.4  100.0
```

## Cleanup

- `cover_db` must be removed from the skill folder before release
