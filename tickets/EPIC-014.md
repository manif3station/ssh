# EPIC-014

## Title

Prompt missing remembered keys early in collector mode.

## Outcome

Make `ssh.door-opener` react correctly when remembered keys are missing from the active agent: prompt through a GUI askpass path when a desktop session exists, and otherwise return a nonzero collector result so DD can show an alert state instead of hanging.

## Tickets

- `DD-041` Add collector GUI askpass prompting and red-indicator exit behavior
