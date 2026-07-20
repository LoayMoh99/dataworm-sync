#!/usr/bin/env bash
# =============================================================================
# Download the ClickHouse driver for Metabase into ./plugins.
# Metabase does not ship the ClickHouse driver, so it must be placed in the
# plugins directory that docker-compose mounts into the metabase container.
#
# Usage:
#   ./download-clickhouse-driver.sh              # latest release
#   DRIVER_VERSION=1.5.2 ./download-clickhouse-driver.sh
#
# After downloading, (re)start Metabase:  docker compose restart metabase
# =============================================================================
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p plugins

REPO="ClickHouse/metabase-clickhouse-driver"

if [[ -n "${DRIVER_VERSION:-}" ]]; then
    URL="https://github.com/${REPO}/releases/download/${DRIVER_VERSION}/clickhouse.metabase-driver.jar"
else
    # Resolve the latest release's asset via the redirect on /releases/latest.
    URL="https://github.com/${REPO}/releases/latest/download/clickhouse.metabase-driver.jar"
fi

echo ">> Downloading $URL"
curl -fL --retry 3 -o plugins/clickhouse.metabase-driver.jar "$URL"
echo ">> Saved to plugins/clickhouse.metabase-driver.jar"
echo ">> Now run: docker compose restart metabase"
