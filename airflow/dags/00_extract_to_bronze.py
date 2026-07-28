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


def extract_postgres_to_bronze(table_name):
    # 1. القراءة من PostgreSQL
    pg_engine = create_engine(
        'postgresql://readonly_user:000@postgres:5432/warehouse'
    )
    query = f'SELECT * FROM {table_name}'
    df = pd.read_sql(query, pg_engine)

    # 2. الاتصال بـ ClickHouse
    ch_client = clickhouse_connect.get_client(
        host='clickhouse',
        port=8123,
        username='dataworm',
        password='dataworm',
    )

    # 3. إنشاء قاعدة البيانات لو مش موجودة
    ch_client.command('CREATE DATABASE IF NOT EXISTS bronze')

    target_table = f'raw_{table_name}'

    # 4. إنشاء الجدول أوتوماتيكياً بناءً على الـ DataFrame الممرر
    ch_client.create_table(
        table=target_table,
        database='bronze',
        df=df,
        engine='MergeTree',
        order_by='tuple()'  # ClickHouse يتطلب order_by للمحرك MergeTree
    )

    # 5. إدخال البيانات
    ch_client.insert_df(
        table=target_table,
        df=df,
        database='bronze'
    )


with DAG(
    '00_extract_to_bronze',
    default_args=default_args,
    schedule='@daily',
    catchup=False,
) as dag:

    task_extract_res_partner = PythonOperator(
        task_id='extract_res_partner',
        python_callable=extract_postgres_to_bronze,
        op_kwargs={'table_name': 'res_partner'},
    )