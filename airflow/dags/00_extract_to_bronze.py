from datetime import datetime, timedelta
import clickhouse_connect
from airflow import DAG
from airflow.operators.python import PythonOperator
import pandas as pd
from sqlalchemy import create_engine

default_args = {
    'owner': 'dataworm',
    'depends_on_past': False,
    'start_date': datetime(2026, 1, 1),
    'retries': 1,
    'retry_delay': timedelta(minutes=5),
}
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


def extract_postgres_to_bronze(table_name):
    pg_engine = create_engine(
        'postgresql://dataworm:12dataworm@postgres:5432/warehouse'
    )
    query = f'SELECT * FROM {table_name}'
    df = pd.read_sql(query, pg_engine)

    ch_client = clickhouse_connect.get_client(
        host='clickhouse',
        port=8123,
        username='dataworm',
        password='dataworm',
        database='salah_bronze'
    )

    ch_client.command('CREATE DATABASE IF NOT EXISTS salah_bronze')

    ch_client.insert_df(
        table=table_name,
        df=df,
        database='salah_bronze',
    )


with DAG(
    '00_extract_to_bronze',
    default_args=default_args,
    schedule='@daily',
    catchup=False,
) as dag:

    previous_task = None
    for table in TABLES:
        task = PythonOperator(
            task_id=f'extract_{table}',
            python_callable=extract_postgres_to_bronze,
            op_kwargs={'table_name': table},
        )
        if previous_task:
            previous_task >> task
        previous_task = task