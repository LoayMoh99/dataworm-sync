from datetime import datetime

from airflow import DAG
from airflow.operators.python import PythonOperator

from postgres import fetch_table


def extract_sales():
    rows = fetch_table("sale_order")

    print(f"Extracted {len(rows)} sale orders")

    if rows:
        print(rows[0])


with DAG(
    dag_id="bronze_sales",
    start_date=datetime(2026, 1, 1),
    schedule=None,
    catchup=False,
    tags=["bronze", "sales"],
) as dag:

    extract_sales_task = PythonOperator(
        task_id="extract_sales",
        python_callable=extract_sales,
    )