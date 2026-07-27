from airflow import DAG
from airflow.operators.python import PythonOperator
from datetime import datetime

from plugins.utils.postgres import fetch_table


def test_postgres_connection():
    rows = fetch_table("sale_order")

    print(f"Fetched {len(rows)} rows")

    if rows:
        print(rows[0])


with DAG(
    dag_id="postgres_connection_test",
    start_date=datetime(2026, 1, 1),
    schedule=None,
    catchup=False,
) as dag:

    test_connection = PythonOperator(
        task_id="test_postgres_connection",
        python_callable=test_postgres_connection,
    )