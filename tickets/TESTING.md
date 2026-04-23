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
- tests cover explicit key registration, default-key fallback, deduplication, missing default-key errors, managed ssh-agent startup, dead `SSH_AUTH_SOCK` repair, live socket reuse, saved agent env parsing, stable socket env writing, active `IdentityAgent` bridge writing, collector missing-key behavior, interactive collector prompting, non-interactive collector reporting, and CLI `main` success/error paths

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

## Cleanup

- `cover_db` must be removed from the skill folder before release
