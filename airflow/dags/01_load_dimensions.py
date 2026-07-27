from datetime import datetime, timedelta
from airflow import DAG
from airflow.operators.python import PythonOperator
from airflow.providers.postgres.hooks.postgres import PostgresHook
from airflow_clickhouse_plugin.hooks.clickhouse import ClickHouseHook

# 1. إعدادات الـ DAG الأساسية
default_args = {
    'owner': 'data_team',
    'start_date': datetime(2026, 1, 1),
    'retries': 1,
    'retry_delay': timedelta(minutes=5),
}

dag = DAG(
    '01_load_all_dimensions',
    default_args=default_args,
    description='تعبئة ونقل كل جداول الأبعاد من Postgres إلى ClickHouse',
    schedule='@daily',
    catchup=False
)

# --------------------------------------------------
# Task 1: تعبئة جدول التواريخ dim_date تلقائياً
# --------------------------------------------------
def load_dim_date():
    ch = ClickHouseHook(clickhouse_conn_id='clickhouse_dw')
    query = """
    INSERT INTO dim_date
    SELECT
        toYYYYMMDD(d) as date_key,
        d as full_date,
        toDayOfWeek(d) as day_of_week,
        formatDateTime(d, '%W') as day_name,
        toMonth(d) as month_number,
        formatDateTime(d, '%B') as month_name,
        toQuarter(d) as quarter,
        toYear(d) as year,
        if(toDayOfWeek(d) IN (5, 6), 1, 0) as is_weekend
    FROM (
        SELECT arrayJoin(timeSlots(toDateTime('2023-01-01 00:00:00'), toIntervalYear(5), 86400)) as ts,
               toDate(ts) as d
    )
    """
    ch.run(query)

# --------------------------------------------------
# Task 2: نقل المدن والمحافظات لـ dim_geography
# --------------------------------------------------
def load_dim_geography():
    pg = PostgresHook(postgres_conn_id='postgres_oltp')
    ch = ClickHouseHook(clickhouse_conn_id='clickhouse_dw')

    sql = """
        SELECT 
            c.id AS city_id, c.name AS city_en, c.name_ar AS city_ar,
            m.id AS m_id, m.name AS m_en, m.name_ar AS m_ar, m.code AS m_code
        FROM muhafazat m
        LEFT JOIN cities c ON c.muhafaza_id = m.id
    """
    rows = pg.get_records(sql)
    data = []
    for r in rows:
        city_id, c_en, c_ar, m_id, m_en, m_ar, m_code = r
        geo_sk = city_id if city_id else (m_id * 100000)
        data.append((geo_sk, city_id, c_en, c_ar, m_id, m_en, m_ar, m_code))

    ch.run("INSERT INTO dim_geography VALUES", data)

# --------------------------------------------------
# Task 3: نقل العملاء والموردين لـ dim_partner
# --------------------------------------------------
def load_dim_partner():
    pg = PostgresHook(postgres_conn_id='postgres_oltp')
    ch = ClickHouseHook(clickhouse_conn_id='clickhouse_dw')

    sql = """
        SELECT 
            id, name, partner_type, LOWER(TRIM(email)), phone, segment,
            is_company::int, street, city, city_id, muhafaza_id, active::int, create_date
        FROM res_partner
    """
    rows = pg.get_records(sql)
    data = []
    for r in rows:
        p_id, name, p_type, email, phone, segment, is_comp, street, city_raw, city_id, m_id, active, created = r
        geo_sk = city_id if city_id else (m_id * 100000 if m_id else None)
        
        # (partner_sk, partner_id, partner_name, partner_type, email, phone, segment, is_company, street_address, city_raw, geography_sk, is_active, valid_from, valid_to, is_current)
        data.append((
            p_id, p_id, name, p_type, email, phone, segment, 
            is_comp, street, city_raw, geo_sk, active, created, None, 1
        ))

    ch.run("INSERT INTO dim_partner VALUES", data)

# --------------------------------------------------
# Task 4: نقل المنتجات لـ dim_product
# --------------------------------------------------
def load_dim_product():
    pg = PostgresHook(postgres_conn_id='postgres_oltp')
    ch = ClickHouseHook(clickhouse_conn_id='clickhouse_dw')

    sql = """
        SELECT 
            pp.id AS product_id,
            pt.id AS template_id,
            pp.name AS product_name,
            pp.default_code,
            pp.barcode,
            pp.color,
            pp.size,
            pt.list_price,
            pt.standard_price,
            pp.price_extra,
            pc.id AS category_id,
            pc.name AS category_name,
            pc.complete_name,
            pt.type,
            pp.active::int,
            pp.create_date
        FROM product_product pp
        JOIN product_template pt ON pp.product_tmpl_id = pt.id
        JOIN product_category pc ON pt.categ_id = pc.id
    """
    rows = pg.get_records(sql)
    data = []
    for r in rows:
        p_id, t_id, name, code, barcode, color, size, l_price, s_price, p_extra, c_id, c_name, c_comp, p_type, active, created = r
        data.append((
            p_id, p_id, t_id, name, code, barcode, color, size,
            l_price, s_price, p_extra, c_id, c_name, c_comp,
            p_type, active, created, None, 1
        ))

    ch.run("INSERT INTO dim_product VALUES", data)

# --------------------------------------------------
# تعريف الـ Tasks وترتيب التنفيذ
# --------------------------------------------------
t_date = PythonOperator(task_id='load_dim_date', python_callable=load_dim_date, dag=dag)
t_geo = PythonOperator(task_id='load_dim_geography', python_callable=load_dim_geography, dag=dag)
t_partner = PythonOperator(task_id='load_dim_partner', python_callable=load_dim_partner, dag=dag)
t_prod = PythonOperator(task_id='load_dim_product', python_callable=load_dim_product, dag=dag)

# الترتيب: التاريخ والجغرافيا أولاً، ثم العملاء والمنتجات
[t_date, t_geo] >> t_partner >> t_prod