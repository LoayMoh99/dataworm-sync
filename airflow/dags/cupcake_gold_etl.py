"""cupcake Gold ETL — cupcakeSilver -> cupcakeGold star schema.

One DAG per Gold table (dag_id ``cupcake_gold_<table>``). Each Gold DAG is
*asset-scheduled*: it fires when the Silver Assets it depends on have been
refreshed. e.g. ``cupcake_gold_fact_sales`` runs once both
``cupcakeSilver/sale_order`` and ``cupcakeSilver/sale_order_line`` update.

The transform itself is a ``.sql`` file under ``sql/cupcake/gold/`` that runs
entirely inside ClickHouse (CREATE DATABASE -> CREATE TABLE -> TRUNCATE ->
INSERT..SELECT ... FINAL). Full-refresh from Silver each run: idempotent, and
correct because Silver already holds the deduplicated current state.
"""

from __future__ import annotations

import os
from datetime import datetime
from pathlib import Path

from airflow import DAG
from airflow.operators.python import PythonOperator

import cupcake_common as cc

SQL_BASE = Path(os.environ.get("AIRFLOW_HOME", "/opt/airflow")) / "sql" / "cupcake" / "gold"

# entity -> (sql file relative to SQL_BASE, Silver source tables it depends on)
GOLD_ENTITIES = {
    "dim_date":       ("dimensions/dim_date.sql",      []),
    "dim_customer":   ("dimensions/dim_customer.sql",  ["res_partner", "cities", "muhafazat"]),
    "dim_vendor":     ("dimensions/dim_vendor.sql",    ["res_partner", "cities", "muhafazat"]),
    "dim_product":    ("dimensions/dim_product.sql",   ["product_product", "product_template", "product_category"]),
    "dim_location":   ("dimensions/dim_location.sql",  ["stock_location", "cities", "muhafazat"]),
    "fact_sales":     ("facts/fact_sales.sql",         ["sale_order", "sale_order_line"]),
    "fact_payments":  ("facts/fact_payments.sql",      ["account_payment"]),
    "fact_purchases": ("facts/fact_purchases.sql",     ["purchase_order", "purchase_order_line"]),
    "fact_inventory": ("facts/fact_inventory.sql",     ["stock_quant"]),
}


def make_transform(sql_relpath: str):
    def _run(**_):
        sql_text = (SQL_BASE / sql_relpath).read_text(encoding="utf-8")
        cc.run_ch_script(sql_text)
        print(f"[gold] applied {sql_relpath}")

    return _run


for _entity, (_sql, _deps) in GOLD_ENTITIES.items():
    _dag_id = f"cupcake_gold_{_entity}"
    # Depend on the Silver Assets; dim_date has no source so it runs @daily.
    _schedule = [cc.silver_asset(t) for t in _deps] if _deps else "@daily"

    with DAG(
        dag_id=_dag_id,
        description=f"Build {cc.GOLD_DB}.{_entity} from {cc.SILVER_DB}",
        start_date=datetime(2026, 1, 1),
        schedule=_schedule,
        catchup=False,
        tags=["cupcake", "gold"],
        default_args={"owner": "cupcake", "retries": 1},
    ) as dag:
        PythonOperator(
            task_id=f"build_{_entity}",
            python_callable=make_transform(_sql),
            outlets=[cc.gold_asset(_entity)],
        )

    globals()[_dag_id] = dag
