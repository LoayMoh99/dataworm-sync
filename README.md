# dataworm — Analytics Platform

An end-to-end, production-style analytics platform: an Odoo-inspired OLTP source
in PostgreSQL, incremental ETL into a ClickHouse warehouse (Bronze → Silver →
Gold), and BI dashboards in Metabase — all in Docker Compose.

```
PostgreSQL (OLTP, Odoo-inspired)
      ↓  incremental extract on write_date
Bronze (raw staging)  →  Silver (dimensions)  →  Gold (facts)  →  KPI tables
      ↓
ClickHouse (warehouse)  →  Metabase (dashboards)
```

## Services

| Service | Image | Port | Role |
|---------|-------|------|------|
| `postgres`   | `postgres:16`                     | 5432 | OLTP source system |
| `clickhouse` | `clickhouse/clickhouse-server:24.8` | 8123 (HTTP) / 9000 | Data warehouse |
| `metabase`   | `metabase/metabase:latest`         | 3000 | BI / dashboards |
| `airflow`    | `apache/airflow:3.3.0` (extended) | 8080 | ETL orchestration — CeleryExecutor stack ([`docker-compose.airflow.yml`](docker-compose.airflow.yml)) |
| `seed`       | `postgres:16` (one-shot)           | —    | Builds schema + generates data |

Airflow runs from its **own** compose file — a proper distributed
CeleryExecutor stack (dedicated metadata Postgres + Redis + separate
apiserver/scheduler/worker/triggerer/dag-processor) with persistent run
history. It joins the main stack's network so DAGs reach `postgres` and
`clickhouse` by service name.

Credentials and volumes are hardcoded in [`docker-compose.yml`](docker-compose.yml)
(user/password `dataworm`, db `warehouse` — demo values; change for anything real).

## Quick start

```bash
# 1. Start the long-running services
docker compose up -d postgres clickhouse metabase

# 2. Build the OLTP schema and generate data (one-shot job)
docker compose --profile seed up seed

# 3. Start orchestration (separate CeleryExecutor Airflow stack)
docker compose -f docker-compose.airflow.yml build
docker compose -f docker-compose.airflow.yml up -d

# 4. (optional) Give Metabase the ClickHouse driver, then restart it
./metabase/download-clickhouse-driver.sh
docker compose restart metabase
```

- **Metabase** — via Caddy at https://dataworm-metabase.dev1.mnt.group; add a
  **ClickHouse** database
  (host `clickhouse`, port `8123`, db `warehouse`, user/password `dataworm`).
- **Airflow** — via Caddy at https://dataworm-airflow.dev1.mnt.group (login
  `admin` / `admin`). A distributed
  **CeleryExecutor** stack defined in
  [`docker-compose.airflow.yml`](docker-compose.airflow.yml): dedicated metadata
  Postgres + Redis broker + separate apiserver / scheduler / worker / triggerer
  / dag-processor, so **run history is persistent** and tasks run in parallel.
  The image ([`docker/airflow/Dockerfile`](docker/airflow/Dockerfile)) extends
  `apache/airflow:3.3.0` with the postgres/fab/celery providers. Config/secrets
  are hardcoded in the compose file; the `postgres_source` connection is
  pre-wired. Enable the Celery **flower** UI (:5555) with `--profile flower`.

### Seeding volumes

The `seed` service uses demo-sized defaults (10K customers / 200 vendors / 2K
products / 200K sales / 30K purchases) for a fast run. For full portfolio scale,
edit the `seed` service environment in `docker-compose.yml`, or override inline:

```bash
docker compose --profile seed run \
  -e N_CUSTOMERS=100000 -e N_VENDORS=2000 -e N_PRODUCTS=20000 \
  -e N_ORDERS=10000000 -e N_PURCHASE_ORDERS=1000000 seed
```

The source is an **Odoo-inspired, Egypt-based** model (customers located by
governorate/city, product variants, vendor pricelist + purchases, partial
payments) and is **intentionally un-cleaned** — see
[postgres/README.md](postgres/README.md) for the schema and the "dirty by
design" notes the ETL is meant to clean. Re-running the `seed` service rebuilds
the schema from scratch (it drops and recreates the OLTP tables).

## Repository layout

```
.
├── docker-compose.yml          # postgres + clickhouse + metabase + seed (data plane)
├── docker-compose.airflow.yml  # Airflow CeleryExecutor stack (orchestration)
├── docker/
│   └── airflow/Dockerfile      # extends apache/airflow:3.3.0 with providers (build context)
├── postgres/               # OLTP schema + SQL data generator  (see postgres/README.md)
│   ├── 01_schema.sql
│   ├── 02_seed_reference.sql
│   ├── 03_generate_data.sql
│   ├── 04_summary.sql
│   └── seed.sh
├── airflow/
│   ├── dags/               # DAGs, organized by layer
│   │   ├── example_source_healthcheck.py   # source connectivity smoke test
│   │   ├── bronze/  silver/  gold/  reporting/  monitoring/
│   ├── sql/                # ETL transform SQL (bronze/silver/gold/reporting)
│   ├── plugins/
│   └── config/
└── metabase/
    ├── plugins/            # ClickHouse driver jar is mounted from here
    └── download-clickhouse-driver.sh
```

## Status

- [x] PostgreSQL OLTP source (Odoo-inspired schema) + configurable data generator
- [x] Docker Compose stack (PostgreSQL, ClickHouse, Metabase, Airflow)
- [x] Airflow orchestration (distributed CeleryExecutor) + source connection + DAG scaffold
- [ ] Bronze/Silver/Gold DAGs + ClickHouse warehouse DDL
- [ ] Metabase dashboards

See [postgres/README.md](postgres/README.md) for the source schema and generator
details.
