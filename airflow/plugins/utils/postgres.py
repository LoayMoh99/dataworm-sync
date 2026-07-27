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




if __name__ == "__main__":
    rows = fetch_table("sale_order")

    print(f"Fetched {len(rows)} rows")

    if rows:
        print(rows[0])