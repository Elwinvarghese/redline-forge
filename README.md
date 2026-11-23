> **LAB ONLY — INTENTIONALLY VULNERABLE.** All credentials, flags and sudo rules in this repository are fictional and for an isolated TryHackMe-style VM. Never deploy this code or these settings publicly.

# Redline Forge Motorsport — ForgeTrack

An isolated, fictional SQL injection training laboratory for authorized learners. It runs Flask and PostgreSQL in Docker; the database is reachable only from the private Compose network.

## Start

```sh
docker compose up --build -d
docker compose ps
```

Open `http://localhost:8080`. Stop with `docker compose down`. Reset all data with `./scripts/reset.sh` (or `docker compose down -v` followed by `docker compose up --build -d`). This intentionally destroys the lab's database volume.

## Requirements

Docker Engine with Compose v2. The application image supplies Python 3.12 and the pinned Flask/psycopg2 dependencies. No external services, host-file access, or database host port are required.

## Troubleshooting

Use `docker compose logs web` and `docker compose logs db`. If port 8080 is occupied, change only the left side of the `ports` mapping in `docker-compose.yml`. Recreate the database after changing either SQL initialization file.

## Safety

The SQL injection routes are deliberately vulnerable and must remain in this isolated lab. Never deploy this Compose file, credentials, or application pattern to production.

## Team access

The lab includes fictional seeded crew and racer accounts. Credentials are intentionally omitted from the web login page; instructors can issue them separately. Team chat is authenticated and stores messages in the isolated lab database.
