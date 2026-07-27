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