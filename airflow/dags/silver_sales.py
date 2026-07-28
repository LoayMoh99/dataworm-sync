from datetime import datetime
import os
from airflow import DAG
from airflow.operators.python import PythonOperator
from clickhouse_connect import get_client

SQL_SILVER_DIR = "/opt/airflow/sql/sales/silver"

def get_clickhouse_client(database="nour_silver"):
    return get_client(
        host="clickhouse",
        port=8123,
        username="dataworm",
        password="dataworm",
        database="nour_silver",
    )

def run_sql_file(file_name: str):
    path = os.path.join(SQL_SILVER_DIR, f"{file_name}.sql")
    with open(path, "r") as f:
        sql = f.read()
    client = get_clickhouse_client()
    client.command(sql)

def build_silver_customers():
    run_sql_file("customers")            # create table
    run_sql_file("transform_customers")  # populate it
    print("Built silver.customers")


with DAG(
    dag_id="silver_sales",
    start_date=datetime(2026, 1, 1),
    schedule=None,
    catchup=False,
) as dag:

    build_customers_task = PythonOperator(
        task_id="build_silver_customers",
        python_callable=build_silver_customers,
    )