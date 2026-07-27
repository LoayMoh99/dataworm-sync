from datetime import datetime
import os
from airflow import DAG
from airflow.operators.python import PythonOperator
import psycopg2
from psycopg2.extras import RealDictCursor
from clickhouse_connect import get_client

SQL_BRONZE_DIR = "/opt/airflow/sql/bronze"

TABLES = [
    "sale_order",
    "sale_order_line",
    "res_partner",
    "product_product",
    "product_template",
    "product_category",
    "stock_location",
    "cities",
    "muhafazat",
]
def create_table(table_name: str):
    path = os.path.join(SQL_BRONZE_DIR, f"{table_name}.sql")
    with open(path, "r") as f:
        ddl = f.read()
    client = get_clickhouse_client()
    client.command(ddl)
    print(f"Ensured table exists: nour_bronze.{table_name}")

def get_clickhouse_client():
    return get_client(
        host="clickhouse",
        port=8123,
        username="dataworm",
        password="dataworm",
        database="nour_bronze",
    )





def load_rows(table_name, rows):
    if not rows:
        print(f"No rows to load for {table_name}")
        return
    columns = list(rows[0].keys())
    values = [list(row.values()) for row in rows]
    client = get_clickhouse_client()
    client.insert(table_name, values, column_names=columns)




def get_postgres_connection():
    return psycopg2.connect(
        host="postgres",
        port=5432,
        database="warehouse",
        user="dataworm",
        password="12datawrom3",
        cursor_factory=RealDictCursor,
    )

def fetch_table(table_name):
    conn = get_postgres_connection()

    cur = conn.cursor()

    cur.execute(f"SELECT * FROM {table_name}")

    rows = cur.fetchall()

    cur.close()
    conn.close()

    return rows



def create_and_load(table_name: str):
    create_table(table_name)
    rows = fetch_table(table_name)
    print(f"Extracted {len(rows)} rows from {table_name}")
    load_rows(table_name, rows)
    print(f"Loaded {len(rows)} rows into nour_bronze.{table_name}")


with DAG(
    dag_id="bronze_sales",
    start_date=datetime(2026, 1, 1),
    schedule=None,
    catchup=False,
) as dag:

    previous_task = None
    for table in TABLES:
        task = PythonOperator(
            task_id=f"load_{table}",
            python_callable=create_and_load,
            op_kwargs={"table_name": table},
        )
        if previous_task:
            previous_task >> task
        previous_task = task