# Architecture

`Student browser → Flask web container (8080, forge_edge network) → PostgreSQL container (internal forge_internal network)`.

The web container is attached to both networks; PostgreSQL is attached only to the internal network and has no host port mapping. `forge_owner` owns the `forge` schema; `forge_app` receives only schema usage plus SELECT/INSERT/UPDATE and sequence usage. Flask uses `forge_app`.
