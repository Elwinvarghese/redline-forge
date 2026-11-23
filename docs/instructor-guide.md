# Instructor guide (do not share with learners)

## Objectives and solutions

1. **Search — easy/medium.** `/builds/search?query=` is a string-built `ILIKE` search. Learners should identify the six-column result shape and retrieve the `search` flag from the `flags` table through the lab's SQLi path.
2. **Restricted build — medium.** `/builds/view?id=` concatenates an integer predicate. The normal query has six selected columns. Learners use column reasoning and a `UNION` to retrieve the `union` flag or the restricted record. SQL errors are deliberately controlled, so reconnaissance rather than stack traces is required.
3. **Telemetry — medium/hard.** `/telemetry/check?session=` returns a deterministic 200 “record located” versus 404 “no record.” Learners use boolean inference to recover the `blind` flag, without timing techniques.
4. **Remediation — verification.** `/secure/builds/search?query=` is the equivalent parameterized route. An injection-like input is treated as data and does not alter query structure. Instructors can award `RFM{secure_build_verified}` after this demonstration.

Flags are in `database/seed.sql`; replace the four values before delivery, then reset the volume. They are not displayed by normal pages.

## Test and reset

Run `pytest tests` inside an environment with app dependencies, then `docker compose up --build -d`, browse core pages, and use `docker compose logs`. Run `./scripts/reset.sh` to restore seeds.

## Clean-room QA notes

Navigation exposes builds and telemetry without lab labels. The build registry leads naturally to search and record lookup. Telemetry exposes valid-looking session-code format and a status oracle. No flag route, debug endpoint, DB host port, or external dependency is provided.
