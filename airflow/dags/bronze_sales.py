from datetime import datetime

from airflow import DAG
from airflow.operators.python import PythonOperator
import psycopg2
from psycopg2.extras import RealDictCursor
from clickhouse_connect import get_client
from pathlib import Path


def get_clickhouse_client():
    return get_client(
        host="clickhouse",
        port=8123,
        username="default",
        password="",
        database="default",
    )

def execute_sql_file(sql_file_path: str):
    client = get_clickhouse_client()

    sql = Path(sql_file_path).read_text(encoding="utf-8")

    client.command(sql)



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

def extract_sales():
    rows = fetch_table("sale_order")
    print(f"Extracted {len(rows)} rows")
    load_rows("sale_order", rows)
    print(f"Loaded {len(rows)} rows into nour_bronze.sale_order")


with DAG(
    dag_id="bronze_sales",
    start_date=datetime(2026, 1, 1),
    schedule=None,
    catchup=False,
) as dag:

    extract_sales_task = PythonOperator(
        task_id="extract_sales",
        python_callable=extract_sales,
    )