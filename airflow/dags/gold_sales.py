from datetime import date, datetime, timedelta
import os
from airflow import DAG
from airflow.operators.python import PythonOperator
from clickhouse_connect import get_client

SQL_GOLD_DIR = "/opt/airflow/sql/gold"

def get_clickhouse_client(database="nour_gold"):
    return get_client(
        host="clickhouse",
        port=8123,
        username="dataworm",
        password="dataworm",
        database=database,
    )

def run_sql_file(file_name: str):
    path = os.path.join(SQL_GOLD_DIR, f"{file_name}.sql")
    with open(path, "r") as f:
        sql = f.read()
    client = get_clickhouse_client()
    statements = [s.strip() for s in sql.split(";") if s.strip()]
    for statement in statements:
        client.command(statement)

def generate_dim_date():
    start = date(2023, 1, 1)
    end = date(2027, 12, 31)
    rows = []
    current = start
    while current <= end:
        rows.append([
            int(current.strftime("%Y%m%d")),
            current,
            current.year,
            (current.month - 1) // 3 + 1,
            current.month,
            current.strftime("%B"),
            current.day,
            current.isoweekday(),
            current.strftime("%A"),
            current.isoweekday() in (6, 7),
        ])
        current += timedelta(days=1)

    columns = ["date_key", "full_date", "year", "quarter", "month",
               "month_name", "day", "day_of_week", "day_name", "is_weekend"]

    client = get_clickhouse_client()
    client.command("TRUNCATE TABLE nour_gold.dim_date")
    client.insert("dim_date", rows, column_names=columns)
    print(f"Loaded {len(rows)} rows into nour_gold.dim_date")

def build_dim_date():
    run_sql_file("dim_date")
    generate_dim_date()
    print("Built dim_date")

def build_fact_sales():
    run_sql_file("fact_sales")
    run_sql_file("transform_fact_sales")
    print("Built FactSales")

with DAG(
    dag_id="gold_sales",
    start_date=datetime(2026, 1, 1),
    schedule=None,
    catchup=False,
) as dag:

    build_dim_date_task = PythonOperator(
        task_id="build_dim_date",
        python_callable=build_dim_date,
    )

    build_fact_sales_task = PythonOperator(
    task_id="build_fact_sales",
    python_callable=build_fact_sales,
    )

build_dim_date_task >> build_fact_sales_task