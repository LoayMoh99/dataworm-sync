"""
Bronze extraction example — Postgres OLTP source → row counts / sample rows.

Demonstrates the wiring you get out of the box in this stack:
  * the pre-wired `postgres_source` connection (see docker-compose.yml:138),
  * PostgresHook to read from the seeded Odoo-style schema,
  * a small task graph (probe -> per-table extract -> summarize).

This DAG is intentionally self-contained: it reads from Postgres and logs what
it finds, so it runs with the stock apache/airflow:2.10.5 image without extra
providers. To actually land the data in ClickHouse, add the ClickHouse provider
to _PIP_ADDITIONAL_REQUIREMENTS in docker-compose.yml and swap the `_extract`
body to write via ClickHouseHook / clickhouse-connect.
"""

from __future__ import annotations

import pendulum
from airflow.decorators import dag, task
from airflow.providers.postgres.hooks.postgres import PostgresHook

SOURCE_CONN_ID = "postgres_source"

# Bronze = raw pull, one landing per source table. Keep this list in sync with
# postgres/01_schema.sql.
SOURCE_TABLES = [
    "res_partner",
    "product_product",
    "sale_order",
    "sale_order_line",
    "account_payment",
]


@dag(
    dag_id="bronze_extract_sales",
    description="Example Bronze extraction from the Postgres OLTP source.",
    start_date=pendulum.datetime(2024, 1, 1, tz="UTC"),
    schedule="@daily",
    catchup=False,
    default_args={"retries": 1, "retry_delay": pendulum.duration(minutes=2)},
    tags=["bronze", "example", "postgres"],
)
def bronze_extract_sales():
    @task
    def probe_source() -> str:
        """Confirm the source connection works before doing any real work."""
        hook = PostgresHook(postgres_conn_id=SOURCE_CONN_ID)
        version = hook.get_first("SELECT version();")[0]
        print(f"Connected to source: {version}")
        return version

    @task
    def extract_table(table: str) -> dict:
        """Read a source table's row count + a small sample (stand-in for a load)."""
        hook = PostgresHook(postgres_conn_id=SOURCE_CONN_ID)
        (row_count,) = hook.get_first(f"SELECT count(*) FROM {table};")
        sample = hook.get_records(f"SELECT * FROM {table} LIMIT 3;")
        print(f"[{table}] rows={row_count} sample_fetched={len(sample)}")
        return {"table": table, "rows": row_count}

    @task
    def summarize(results: list[dict]) -> None:
        total = sum(r["rows"] for r in results)
        print("Bronze extraction summary:")
        for r in sorted(results, key=lambda x: x["table"]):
            print(f"  {r['table']:<20} {r['rows']:>12,} rows")
        print(f"  {'TOTAL':<20} {total:>12,} rows")

    # probe first; then fan out one extract task per table; then summarize.
    probed = probe_source()
    extracted = extract_table.expand(table=SOURCE_TABLES)
    probed >> extracted  # order the probe before the dynamic extracts
    summarize(extracted)


bronze_extract_sales()
