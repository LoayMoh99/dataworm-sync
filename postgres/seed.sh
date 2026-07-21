#!/usr/bin/env bash
# =============================================================================
# seed.sh — build the OLTP schema and generate data in one shot.
# =============================================================================
# Usage:
#   ./seed.sh                       # defaults (100K customers / 20K products / 10M orders)
#   N_CUSTOMERS=1000 N_ORDERS=50000 N_PRODUCTS=500 ./seed.sh   # small smoke test
#
# Connection is taken from standard libpq env vars (PGHOST, PGPORT, PGUSER,
# PGPASSWORD, PGDATABASE) or a DATABASE_URL, so it works locally and in Docker.
# =============================================================================
set -euo pipefail

cd "$(dirname "$0")"

# Volumes (override via environment).
N_CUSTOMERS="${N_CUSTOMERS:-100000}"
N_VENDORS="${N_VENDORS:-2000}"
N_PRODUCTS="${N_PRODUCTS:-20000}"
N_ORDERS="${N_ORDERS:-10000000}"
N_PURCHASE_ORDERS="${N_PURCHASE_ORDERS:-1000000}"
QUANTS_PER_PRODUCT="${QUANTS_PER_PRODUCT:-10}"
HISTORY_DAYS="${HISTORY_DAYS:-730}"
TAX_RATE="${TAX_RATE:-0.15}"
SEED="${SEED:-0.42}"

# Connection: DATABASE_URL wins if set, else rely on PG* env vars.
PSQL=(psql -v ON_ERROR_STOP=1 --quiet)
if [[ -n "${DATABASE_URL:-}" ]]; then
    PSQL+=("$DATABASE_URL")
fi

echo ">> 01_schema.sql"
"${PSQL[@]}" -f 01_schema.sql

echo ">> 02_seed_reference.sql"
"${PSQL[@]}" -f 02_seed_reference.sql

echo ">> 03_generate_data.sql  (customers=$N_CUSTOMERS vendors=$N_VENDORS products=$N_PRODUCTS orders=$N_ORDERS purchase_orders=$N_PURCHASE_ORDERS)"
"${PSQL[@]}" \
    -v n_customers="$N_CUSTOMERS" \
    -v n_vendors="$N_VENDORS" \
    -v n_products="$N_PRODUCTS" \
    -v n_orders="$N_ORDERS" \
    -v n_purchase_orders="$N_PURCHASE_ORDERS" \
    -v quants_per_product="$QUANTS_PER_PRODUCT" \
    -v history_days="$HISTORY_DAYS" \
    -v tax_rate="$TAX_RATE" \
    -v seed="$SEED" \
    -f 03_generate_data.sql

echo ">> 04_summary.sql"
"${PSQL[@]}" -f 04_summary.sql

echo ">> Done."
