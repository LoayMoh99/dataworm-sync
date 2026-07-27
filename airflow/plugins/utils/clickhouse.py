from clickhouse_connect import get_client
from pathlib import Path


def get_clickhouse_client():
    return get_client(
        host="clickhouse",
        port=8123,
        username="default",
        password="",
        database="default",
    )

def execute_sql_file(sql_file_path: str):
    client = get_clickhouse_client()

    sql = Path(sql_file_path).read_text(encoding="utf-8")

    client.command(sql)



def load_rows(table_name, rows):
    if not rows:
        print(f"No rows to load for {table_name}")
        return
    columns = list(rows[0].keys())
    values = [list(row.values()) for row in rows]
    client = get_clickhouse_client()
    client.insert(table_name, values, column_names=columns)