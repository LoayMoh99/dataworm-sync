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
    # 1. قراءة البيانات من PostgreSQL
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

    db_name = 'salah_bronze'
    target_table = f'raw_{table_name}'

    # إنشاء قاعدة البيانات لو مش موجودة
    ch_client.command(f'CREATE DATABASE IF NOT EXISTS {db_name}')

    # 3. بناء واستعلام إنشاء الجدول تلقائيًا
    columns_with_types = []
    for col, dtype in df.dtypes.items():
        ch_type = 'Nullable(String)'
        if 'int' in str(dtype):
            ch_type = 'Nullable(Int64)'
        elif 'float' in str(dtype):
            ch_type = 'Nullable(Float64)'
        elif 'datetime' in str(dtype):
            ch_type = 'Nullable(DateTime64(3))'
        columns_with_types.append(f'`{col}` {ch_type}')

    create_table_query = f"""
    CREATE TABLE IF NOT EXISTS {db_name}.{target_table} (
        {', '.join(columns_with_types)}
    ) ENGINE = MergeTree() ORDER BY tuple();
    """
    
    ch_client.command(create_table_query)

    # 4. إدخال البيانات (بدون أي arguments زيادة)
    ch_client.insert_df(
        table=target_table,
        df=df,
        database=db_name
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