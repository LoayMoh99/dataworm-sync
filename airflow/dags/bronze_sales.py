from datetime import datetime

from airflow import DAG
from airflow.operators.python import PythonOperator

from postgres import fetch_table
import psycopg2
from psycopg2.extras import RealDictCursor




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