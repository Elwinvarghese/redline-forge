# ForgeTrack Lab Completion Write-up

## Status

**Implementation:** complete.  
**Runtime verification after latest schema changes:** pending a clean Docker volume reset.

## Architecture

ForgeTrack has a Flask web application on host port `8080`, a PostgreSQL 16 database with no host database-port mapping, a public web edge network, and a private database network. The runtime database account is `forge_app`; schema ownership belongs to `forge_owner`.

## Implemented experience

- Motorsport dashboard with fleet readiness, workshop priorities, race programme, and pit-wall bulletin.
- Visual garage of real-world vehicle models with vehicle profile dialogs.
- Race Centre with event intelligence and entry lists.
- Local, SVG-based circuit-reference maps; no third-party map service is required.
- Authenticated team chat with parameterized persistence.
- Role-aware operations controls:
  - Crew may add and update vehicles, add driver accounts, and update all performance statistics.
  - Racers may view shared operations information and update only their own performance statistics.
- Audit records for management actions.

## Challenge design

The only intentional injection routes remain `/builds/search`, `/builds/view`, and `/telemetry/check`. The normal authenticated operations features use parameterized database queries.

## Recommended final QA

After the instructor approves the lab-volume reset, run:

```powershell
docker compose down -v
docker compose up --build -d
docker compose ps
```

Then verify the public routes, sign in using instructor-issued credentials, create a test vehicle and driver, update a vehicle and a driver statistic, confirm the audit records, and perform the walkthrough in `docs/walkthrough.md`.

## Reset note

`docker compose down -v` destroys only the local `redline-forge_pgdata` volume. It restores all fictional seed data, flags, accounts, events, and test state when recreated.
