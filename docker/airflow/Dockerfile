# =============================================================================
# dataworm Airflow image — extends the official 3.3.0 image with the providers
# the DAGs need, baked in at build time (reproducible; no reinstall on every
# container start, unlike _PIP_ADDITIONAL_REQUIREMENTS).
#
# Build:  docker compose -f docker-compose.airflow.yml build
# =============================================================================
ARG AIRFLOW_VERSION=3.3.0
FROM apache/airflow:${AIRFLOW_VERSION}

ARG AIRFLOW_VERSION=3.3.0
# Match the Python of the base image (3.3.0 ships on 3.12).
ARG PYTHON_VERSION=3.12

USER airflow

# Providers pinned via the official constraints file for this Airflow release so
# the resolver can't drag in an incompatible combination.
#   - postgres : OLTP source hooks (PostgresHook) used by the Bronze DAGs
#   - fab      : FabAuthManager (login / RBAC UI) referenced in the compose
#   - celery   : CeleryExecutor runtime (separate distribution in Airflow 3.x)
RUN pip install --no-cache-dir \
      "apache-airflow-providers-postgres" \
      "apache-airflow-providers-fab" \
      "apache-airflow-providers-celery" \
      --constraint "https://raw.githubusercontent.com/apache/airflow/constraints-${AIRFLOW_VERSION}/constraints-${PYTHON_VERSION}.txt"

# ---- Optional: ClickHouse warehouse access from DAGs -----------------------
# Uncomment to let DAGs write to the ClickHouse warehouse (Bronze -> Silver ->
# Gold). Installed without the constraints file since it's a third-party plugin.
RUN pip install --no-cache-dir "airflow-clickhouse-plugin" "clickhouse-connect"
