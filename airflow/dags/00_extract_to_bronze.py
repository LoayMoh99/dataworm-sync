from datetime import datetime, timedelta
from airflow import DAG
from airflow.operators.python import PythonOperator
import pandas as pd
from sqlalchemy import create_engine
import clickhouse_connect

# --------------------------------------------------
# 1. Connection Configurations
# --------------------------------------------------
POSTGRES_URI = 'postgresql://readonly_user:000@postgres:5432/warehouse'

CLICKHOUSE_HOST = 'clickhouse'
CLICKHOUSE_PORT = 8123
CLICKHOUSE_USER = 'dataworm'
CLICKHOUSE_PASSWORD = 'dataworm'
CLICKHOUSE_DB = 'salah_bronze'

# قائمة الجداول اللي محتاج تنقلها كـ Raw Data
TABLES_TO_EXTRACT = [
    'res_partner',
    'sale_order',
    'sale_order_line',
    'product_product',
    'product_template',
    'product_category',
    'stock_location',
    'cities',
    'muhafazat',
    # ضيف أي أسامي جداول تانية تحبها هنا
]

# --------------------------------------------------
# 2. Schema Mapping & Ingestion Function
# --------------------------------------------------
def map_pandas_to_clickhouse(dtype):
    """تحويل أنواع بيانات Pandas إلى ClickHouse"""
    dtype_str = str(dtype)
    if 'int' in dtype_str:
        return 'Nullable(Int64)'
    elif 'float' in dtype_str:
        return 'Nullable(Float64)'
    elif 'datetime' in dtype_str:
        return 'Nullable(DateTime64(3))'
    elif 'bool' in dtype_str:
        return 'Nullable(Bool)'
    else:
        return 'Nullable(String)'

def extract_and_load_table(table_name):
    print(f"--- Starting Pipeline for Table: {table_name} ---")
    
    # أ. السحب من PostgreSQL
    pg_engine = create_engine(POSTGRES_URI)
    query = f"SELECT * FROM {table_name};"
    df = pd.read_sql(query, pg_engine)
    print(f"Fetched {len(df)} rows from PostgreSQL table: {table_name}")

    # ب. إنشاء الـ Schema تلقائياً
    columns_schema = []
    for col_name, dtype in df.dtypes.items():
        ch_type = map_pandas_to_clickhouse(dtype)
        columns_schema.append(f"`{col_name}` {ch_type}")
    
    schema_sql = ",\n  ".join(columns_schema)
    target_table = f"raw_{table_name}"
    
    create_table_query = f"""
    CREATE TABLE IF NOT EXISTS {CLICKHOUSE_DB}.{target_table} (
      {schema_sql}
    ) ENGINE = MergeTree()
    ORDER BY tuple();
    """

    # ج. الاتصال بـ ClickHouse والمسح والتكريت ثم الإدخال
    ch_client = clickhouse_connect.get_client(
        host=CLICKHOUSE_HOST,
        port=CLICKHOUSE_PORT,
        username=CLICKHOUSE_USER,
        password=CLICKHOUSE_PASSWORD
    )
    
    # 1. مسح الجدول القديم
    ch_client.command(f"DROP TABLE IF EXISTS {CLICKHOUSE_DB}.{target_table}")
    
    # 2. إنشاء الجدول الجديد
    ch_client.command(create_table_query)
    print(f"Created table {CLICKHOUSE_DB}.{target_table}")
    
    # 3. إدخال البيانات
    if not df.empty:
        ch_client.insert_df(
            table=target_table,
            df=df,
            database=CLICKHOUSE_DB
        )
        print(f"Successfully inserted {len(df)} rows into {CLICKHOUSE_DB}.{target_table}")
    else:
        print("DataFrame is empty, skipped insertion.")

# --------------------------------------------------
# 3. Airflow DAG Definition
# --------------------------------------------------
default_args = {
    'owner': 'salah',
    'start_date': datetime(2026, 1, 1),
    'retries': 1,
    'retry_delay': timedelta(minutes=5),
}

with DAG(
    dag_id='postgres_to_clickhouse_bronze_all_tables',
    default_args=default_args,
    schedule='@daily',
    catchup=False,
    tags=['bronze', 'ingestion', 'postgres', 'clickhouse']
) as dag:

    # عمل Loop ينشئ Task مستقل لكل جدول في القائمة
    for table in TABLES_TO_EXTRACT:
        task = PythonOperator(
            task_id=f'ingest_{table}',
            python_callable=extract_and_load_table,
            op_kwargs={'table_name': table}
        )