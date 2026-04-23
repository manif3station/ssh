# EPIC-008

## Title

Create the `ssh` skill.

## Outcome

Add a smart SSH key helper that remembers configured keys, ensures an ssh-agent exists, shares the agent socket across sessions, and lets the DD collector prompt early for missing passphrases.

## Tickets

- `DD-031` Create the `ssh` skill records and baseline layout
- `DD-032` Define smart key registration and ssh-agent behavior
- `DD-033` Implement shared ssh-agent state across sessions
- `DD-034` Implement collector readiness checks
- `DD-035` Verify, document, commit, and push the `ssh` skill
