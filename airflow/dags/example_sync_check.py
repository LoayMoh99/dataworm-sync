"""Example DAG to verify the CI/CD sync pipeline delivers DAGs to the server."""

from __future__ import annotations

import pendulum
from airflow.decorators import dag, task


@dag(
    dag_id="example_sync_check",
    description="Sanity check: this DAG arrived via the sync-dags pipeline.",
    start_date=pendulum.datetime(2026, 1, 1, tz="UTC"),
    schedule=None,
    catchup=False,
    tags=["example", "ci-cd"],
)
def example_sync_check():
    @task
    def hello() -> str:
        message = "DAG synced successfully from the dataworm-sync repo"
        print(message)
        return message

    hello()


example_sync_check()
