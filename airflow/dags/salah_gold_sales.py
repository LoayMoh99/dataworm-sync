from datetime import datetime, timedelta
from airflow import DAG
from airflow.operators.python import PythonOperator
import sys
import os

# إضافة فولدر الـ plugins للـ sys.path
plugins_folder = os.path.abspath(os.path.join(os.path.dirname(__file__), '../../../plugins'))
if plugins_folder not in sys.path:
    sys.path.append(plugins_folder)

# استدعاء ملف الـ utils المباشر
import utils.clickhouse as ch_utils

default_args = {
    'owner': 'salah',
    'depends_on_past': False,
    'email_on_failure': False,
    'retries': 1,
    'retry_delay': timedelta(minutes=5),
}

def create_gold_star_schema():
    # البحث عن اسم الدالة الموجودة داخل clickhouse.py ديناميكياً
    possible_names = ['execute_query', 'execute_clickhouse_query', 'run_query', 'execute']
    query_runner = None
    
    for name in possible_names:
        if hasattr(ch_utils, name):
            query_runner = getattr(ch_utils, name)
            break
            
    if not query_runner:
        # لو اسم الدالة مختلف خالص، هيجيب كل الدوال المتاحة جوه الملف ويختار أول واحدة
        functions = [getattr(ch_utils, f) for f in dir(ch_utils) if callable(getattr(ch_utils, f)) and not f.startswith("__")]
        if functions:
            query_runner = functions[0]

    if not query_runner:
        raise AttributeError("لم يتم العثور على أي دالة تنفيذ داخل utils/clickhouse.py")

    query_runner("CREATE DATABASE IF NOT EXISTS salah_gold;")

    query_runner("""
        CREATE TABLE IF NOT EXISTS salah_gold.dim_customers
        ENGINE = ReplacingMergeTree()
        ORDER BY customer_id AS
        SELECT 
            p.id AS customer_id,
            p.name AS customer_name,
            p.email,
            p.phone,
            c.name AS city_name,
            m.name AS governorate_name
        FROM salah_bronze.raw_res_partner p
        LEFT JOIN salah_bronze.raw_cities c ON p.city_id = c.id
        LEFT JOIN salah_bronze.raw_muhafazat m ON c.muhafazat_id = m.id;
    """)

    query_runner("""
        CREATE TABLE IF NOT EXISTS salah_gold.dim_products
        ENGINE = ReplacingMergeTree()
        ORDER BY product_id AS
        SELECT 
            p.id AS product_id,
            t.name AS product_name,
            c.name AS category_name,
            p.list_price AS unit_price,
            t.type AS product_type
        FROM salah_bronze.raw_product_product p
        LEFT JOIN salah_bronze.raw_product_template t ON p.product_tmpl_id = t.id
        LEFT JOIN salah_bronze.raw_product_category c ON t.categ_id = c.id;
    """)

    query_runner("""
        CREATE TABLE IF NOT EXISTS salah_gold.dim_locations
        ENGINE = ReplacingMergeTree()
        ORDER BY location_id AS
        SELECT 
            id AS location_id,
            name AS location_name,
            complete_name AS full_location_path,
            usage AS location_type
        FROM salah_bronze.raw_stock_location;
    """)

    query_runner("""
        CREATE TABLE IF NOT EXISTS salah_gold.fact_sales
        ENGINE = MergeTree()
        ORDER BY (order_id, line_id)
        AS
        SELECT 
            l.id AS line_id,
            o.id AS order_id,
            o.partner_id AS customer_id,
            l.product_id,
            o.warehouse_id AS location_id,
            l.product_uom_qty AS quantity,
            l.price_unit,
            l.price_subtotal AS subtotal_amount,
            l.price_total AS total_amount,
            o.state AS order_status,
            o.date_order AS order_date
        FROM salah_bronze.raw_sale_order o
        INNER JOIN salah_bronze.raw_sale_order_line l ON o.id = l.order_id;
    """)

with DAG(
    '01_salah_bronze_to_gold',
    default_args=default_args,
    description='Full Star Schema Gold Layer for Sales and Master Data',
    schedule_interval='@daily',
    start_date=datetime(2026, 7, 1),
    catchup=False,
    tags=['gold', 'star_schema', 'clickhouse'],
) as dag:

    build_gold = PythonOperator(
        task_id='build_gold_tables',
        python_callable=create_gold_star_schema
    )

    build_gold