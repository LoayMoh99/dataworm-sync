"""Shared helpers for the cupcake_* ETL pipeline (Postgres -> ClickHouse).

Connections, database bootstrap, incremental checkpoint bookkeeping, Airflow
Asset wiring and a tiny multi-statement SQL runner. Lives in plugins/ so it is
importable from any DAG file as ``import cupcake_common``.

Layers:
    Postgres (warehouse, readonly_user)  --incremental on write_date-->  cupcakeSilver
    cupcakeSilver  --in-ClickHouse INSERT..SELECT-->  cupcakeGold (star schema)
"""

from __future__ import annotations

import re
from datetime import datetime, timezone

import psycopg2
from psycopg2.extras import RealDictCursor
from clickhouse_connect import get_client

# --- Airflow Asset import (3.x = airflow.sdk.Asset, 2.x = datasets.Dataset) ---
try:  # Airflow 3.x
    from airflow.sdk import Asset
except ImportError:  # pragma: no cover - fallback for Airflow 2.x
    from airflow.datasets import Dataset as Asset  # type: ignore

# --- Connection settings (demo creds; match docker-compose) ------------------
# Source OLTP: read-only user as requested.
PG_CONN = dict(
    host="postgres",
    port=5432,
    dbname="warehouse",
    user="readonly_user",
    password="000",
)

# Warehouse: ClickHouse over the HTTP interface (8123), same as the working
# bronze experiments.
CH_CONN = dict(host="clickhouse", port=8123, username="dataworm", password="dataworm")

SILVER_DB = "cupcakeSilver"
GOLD_DB = "cupcakeGold"
CHECKPOINTS_TABLE = "_etl_checkpoints"

EPOCH = datetime(1970, 1, 1, tzinfo=timezone.utc)

# Insert this many source rows per round-trip when streaming a big table.
EXTRACT_CHUNK = 50_000


# --- Connections -------------------------------------------------------------
def get_pg_conn():
    """Read-only connection to the OLTP source; rows come back as dicts."""
    return psycopg2.connect(cursor_factory=RealDictCursor, **PG_CONN)


def get_ch_client(database: str | None = None):
    """ClickHouse HTTP client, optionally bound to a database."""
    kwargs = dict(CH_CONN)
    if database:
        kwargs["database"] = database
    return get_client(**kwargs)


# --- Airflow Assets ----------------------------------------------------------
def silver_asset(table: str) -> Asset:
    """The Asset a Silver table produces / a Gold DAG subscribes to."""
    return Asset(f"clickhouse://{SILVER_DB}/{table}")


def gold_asset(table: str) -> Asset:
    return Asset(f"clickhouse://{GOLD_DB}/{table}")


# --- SQL runner --------------------------------------------------------------
def run_ch_script(sql_text: str, database: str | None = None) -> None:
    """Execute a ``;``-separated batch of ClickHouse statements in order.

    ``--`` line comments are stripped first, so a semicolon inside a comment
    can't split a statement (which would leave a comment-only fragment that
    ClickHouse rejects as an empty query). The cupcake SQL files use no ``--``
    inside string literals, so this is safe.
    """
    client = get_ch_client(database)
    cleaned = re.sub(r"--[^\n]*", "", sql_text)
    for stmt in cleaned.split(";"):
        stmt = stmt.strip()
        if stmt:
            client.command(stmt)


# --- Incremental checkpoint bookkeeping -------------------------------------
def ensure_checkpoints_table() -> None:
    """Append-only high-water-mark log; also the audit of every incremental run."""
    client = get_ch_client()
    client.command(f"CREATE DATABASE IF NOT EXISTS {SILVER_DB}")
    client.command(
        f"""
        CREATE TABLE IF NOT EXISTS {SILVER_DB}.{CHECKPOINTS_TABLE} (
            table_name      String,
            last_write_date DateTime64(3, 'UTC'),
            rows_loaded     UInt64,
            run_ts          DateTime64(3, 'UTC') DEFAULT now64(3)
        ) ENGINE = MergeTree
        ORDER BY (table_name, run_ts)
        """
    )


def get_checkpoint(table: str) -> datetime:
    """High-water mark for a table's write_date, or EPOCH on first run."""
    client = get_ch_client()
    res = client.query(
        f"SELECT max(last_write_date) FROM {SILVER_DB}.{CHECKPOINTS_TABLE} "
        f"WHERE table_name = {{t:String}}",
        parameters={"t": table},
    )
    val = res.result_rows[0][0] if res.result_rows else None
    if not val:
        return EPOCH
    if val.tzinfo is None:  # clickhouse-connect may hand back naive UTC
        val = val.replace(tzinfo=timezone.utc)
    return val


def record_checkpoint(table: str, last_write_date: datetime, rows_loaded: int) -> None:
    client = get_ch_client()
    client.insert(
        f"{SILVER_DB}.{CHECKPOINTS_TABLE}",
        [[table, last_write_date, rows_loaded]],
        column_names=["table_name", "last_write_date", "rows_loaded"],
    )
