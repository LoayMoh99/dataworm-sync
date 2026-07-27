from airflow import DAG
from airflow.operators.python import PythonOperator
from datetime import datetime, timedelta
import pandas as pd
from sqlalchemy import create_engine
import clickhouse_connect

default_args = {
    'owner': 'airflow',
    'depends_on_past': False,
    'start_date': datetime(2026, 1, 1),
    'retries': 1,
    'retry_delay': timedelta(minutes=5),
}

# 1. الاتصال بـ Postgres وسحب البيانات الخام
def extract_postgres_to_bronze(table_name):
    pg_engine = create_engine('postgresql://airflow:airflow@postgres:5432/postgres')
    query = f"SELECT * FROM {table_name}"
    df = pd.read_sql(query, pg_engine)
    
    # 2. الاتصال بـ ClickHouse وكتابة البيانات في طبقة bronze
    ch_client = clickhouse_connect.get_client(host='clickhouse', port=8123, username='default', password='')
    
    # إنشاء الجدول في bronze لو مش موجود
    ch_client.command(f"CREATE TABLE IF NOT EXISTS bronze.raw_{table_name} ENGINE = Log AS SELECT * FROM memory WHERE 1=0")
    
    # إدراج البيانات
    ch_client.insert_df(f"bronze.raw_{table_name}", df)
    print(f"Successfully loaded {len(df)} rows into bronze.raw_{table_name}")

with DAG(
    '00_extract_to_bronze',
    default_args=default_args,
    description='Extract raw data from Postgres to ClickHouse Bronze layer',
    schedule='@daily',
    catchup=False,
) as dag:

    # يمكنك إضافة بقية الجداول التي تريد سحبها هنا
    extract_customers = PythonOperator(
        task_id='extract_customers_to_bronze',
        python_callable=extract_postgres_to_bronze,
        op_kwargs={'table_name': 'customers'},
    )

    extract_customers