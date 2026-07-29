from datetime import datetime
import os
from airflow import DAG
from airflow.operators.python import PythonOperator
from clickhouse_connect import get_client

SQL_SILVER_DIR = "/opt/airflow/sql/silver/sales"

def get_clickhouse_client(database="nour_silver"):
    return get_client(
        host="clickhouse",
        port=8123,
        username="dataworm",
        password="dataworm",
        database=database,
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

def build_silver_locations():
    run_sql_file("locations")
    run_sql_file("transform_locations")
    print("Built silver.locations")

def build_silver_products():
    run_sql_file("products")
    run_sql_file("transform_products")
    print("Built silver.products")

def build_silver_sales():
    run_sql_file("sales")
    run_sql_file("transform_sales")
    print("Built silver.sales")

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

    build_locations_task = PythonOperator(
    task_id="build_silver_locations",
    python_callable=build_silver_locations,
    )
    build_products_task = PythonOperator(
    task_id="build_silver_products",
    python_callable=build_silver_products,
    )

    build_sales_task = PythonOperator(
    task_id="build_silver_sales",
    python_callable=build_silver_sales,
    )

build_customers_task >> build_locations_task >> build_products_task >> build_sales_task

