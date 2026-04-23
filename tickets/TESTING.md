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
- tests cover explicit key registration, missing explicit-key rejection, default-key fallback, deduplication, missing default-key errors, quiet stale-agent health checks, managed ssh-agent startup, dead `SSH_AUTH_SOCK` repair, live socket reuse, saved agent env parsing, stable socket env writing, shell startup bridge writing, active `IdentityAgent` bridge writing, collector missing-key behavior, interactive collector prompting, non-interactive collector reporting, and CLI `main` success/error paths

Latest covered result for `DD-037`:

```text
Files=6, Tests=89
lib/SSH/Add.pm    100.0   90.4   63.6  100.0
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

## Cleanup

- `cover_db` must be removed from the skill folder before release
