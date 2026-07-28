from datetime import datetime, timedelta
import clickhouse_connect
from airflow import DAG
from airflow.operators.python import PythonOperator
import pandas as pd
from sqlalchemy import create_engine

# 1. الإعدادات الافتراضية للـ DAG
default_args = {
    'owner': 'dataworm',
    'depends_on_past': False,
    'start_date': datetime(2026, 1, 1),
    'retries': 1,
    'retry_delay': timedelta(minutes=5),
}


# 2. الدالة الأساسية لاستخراج البيانات ونقلها لـ ClickHouse
def extract_postgres_to_bronze(table_name):
    # الاتصال بقاعدة بيانات postgres وقراءة الجدول
    pg_engine = create_engine(
        'postgresql://readonly_user:000@postgres:5432/warehouse'
    )
    query = f'SELECT * FROM {table_name}'
    df = pd.read_sql(query, pg_engine)

    # الاتصال بـ ClickHouse
    ch_client = clickhouse_connect.get_client(
        host='clickhouse',
        port=8123,
        username='dataworm',
        password='dataworm',
    )

    db_name = 'salah_bronze'
    target_table = f'raw_{table_name}'

    # التأكد من وجود داتابيز salah_bronze
    ch_client.command(f'CREATE DATABASE IF NOT EXISTS {db_name}')

    # إدخال البيانات في الجدول المجهز
    ch_client.insert_df(
        table=target_table,
        df=df,
        database=db_name
        create_table_params={'engine': 'MergeTree() ORDER BY tuple()'}
    )


# 3. تعريف الـ DAG
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