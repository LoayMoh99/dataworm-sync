"""cupcake Silver ETL — Postgres (public) -> ClickHouse cupcakeSilver.

One DAG per source table (dag_id ``cupcake_silver_<table>``), generated from
``cupcake_tables.SILVER_TABLES``. Each DAG:

  * runs @daily, catchup off;
  * pulls only rows whose ``write_date`` is newer than the stored high-water
    mark (full backfill on first run);
  * upserts them into a ``ReplacingMergeTree(write_date)`` mirror — daily patch
    updates: changed rows overwrite by newest write_date, new rows append;
  * records the run (new high-water + row count) in cupcakeSilver._etl_checkpoints;
  * publishes the Airflow Asset ``clickhouse://cupcakeSilver/<table>`` that the
    Gold DAGs subscribe to.
"""

from __future__ import annotations

from datetime import datetime, timezone

from airflow import DAG
from airflow.operators.python import PythonOperator

import cupcake_common as cc
from cupcake_tables import SILVER_TABLES


def _create_table_ddl(spec: dict) -> str:
    cols = ",\n    ".join(f"`{name}` {ch_type}" for name, ch_type, _ in spec["columns"])
    return (
        f"CREATE TABLE IF NOT EXISTS {cc.SILVER_DB}.{spec['name']} (\n"
        f"    {cols}\n"
        f") ENGINE = ReplacingMergeTree(write_date)\n"
        f"ORDER BY ({spec['order_by']})"
    )


def _extract_sql(spec: dict) -> str:
    select_list = ",\n    ".join(f"{expr} AS \"{name}\"" for name, _, expr in spec["columns"])
    return (
        f"SELECT\n    {select_list}\n"
        f"FROM public.{spec['name']}\n"
        f"WHERE write_date > %(cursor)s\n"
        f"ORDER BY write_date"
    )


def make_loader(spec: dict):
    """Build the incremental extract+load callable for one table."""
    col_names = [name for name, _, _ in spec["columns"]]
    table = spec["name"]

    def _load(**_):
        cc.ensure_checkpoints_table()
        ch = cc.get_ch_client(cc.SILVER_DB)
        ch.command(_create_table_ddl(spec))

        cursor_value = cc.get_checkpoint(table)
        high_water = cursor_value
        total = 0

        conn = cc.get_pg_conn()
        try:
            # Server-side cursor so a multi-million-row table streams instead of
            # materialising in memory.
            pg = conn.cursor(name=f"cupcake_extract_{table}")
            pg.itersize = cc.EXTRACT_CHUNK
            pg.execute(_extract_sql(spec), {"cursor": cursor_value})
            while True:
                rows = pg.fetchmany(cc.EXTRACT_CHUNK)
                if not rows:
                    break
                values = [[row[c] for c in col_names] for row in rows]
                ch.insert(f"{cc.SILVER_DB}.{table}", values, column_names=col_names)
                total += len(rows)
                for row in rows:
                    wd = row["write_date"]
                    if wd.tzinfo is None:
                        wd = wd.replace(tzinfo=timezone.utc)
                    if wd > high_water:
                        high_water = wd
            pg.close()
        finally:
            conn.close()

        cc.record_checkpoint(table, high_water, total)
        print(f"[{table}] loaded {total} rows; high-water -> {high_water.isoformat()}")

    return _load


# --- Generate one DAG per Silver table --------------------------------------
for _spec in SILVER_TABLES:
    _dag_id = f"cupcake_silver_{_spec['name']}"
    with DAG(
        dag_id=_dag_id,
        description=f"Incremental load public.{_spec['name']} -> {cc.SILVER_DB}.{_spec['name']}",
        start_date=datetime(2026, 1, 1),
        schedule="@daily",
        catchup=False,
        tags=["cupcake", "silver"],
        default_args={"owner": "cupcake", "retries": 1},
    ) as dag:
        PythonOperator(
            task_id=f"load_{_spec['name']}",
            python_callable=make_loader(_spec),
            outlets=[cc.silver_asset(_spec["name"])],
        )

    # Register the DAG object under a module-global name so Airflow discovers it.
    globals()[_dag_id] = dag
