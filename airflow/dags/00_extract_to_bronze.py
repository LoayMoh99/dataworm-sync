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
    # 1. الاتصال بـ Postgres وسحب البيانات
    pg_engine = create_engine(
        'postgresql://readonly_user:000@host.docker.internal:5432/warehouse'
    )
    query = f'SELECT * FROM {table_name}'
    df = pd.read_sql(query, pg_engine)

    # 2. الاتصال بـ ClickHouse باستخدام بيانات الاعتماد الصحيحة
    ch_client = clickhouse_connect.get_client(
        host='clickhouse',
        port=8123,
        username='dataworm',
        password='dataworm',
    )

    # 3. إنشاء قاعدة بيانات bronze لو مش موجودة
    ch_client.command('CREATE DATABASE IF NOT EXISTS bronze')

    # 4. إدخال البيانات في ClickHouse مباشرة
    # ملاحظة: insert_df بتكفّل بإنشاء الجدول أو الإدخال بشكل أوتوماتيكي وصحيح
    ch_client.insert_df(
        table=f'raw_{table_name}',
        df=df,
        database='bronze',
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