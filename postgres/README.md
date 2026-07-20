# PostgreSQL OLTP Seeding (Odoo-inspired)

The **source system** for the ETL platform: a normalized OLTP schema modeled on
**Odoo's** core sales/inventory tables, plus a configurable, set-based data
generator. Data has recency-weighted timestamps so the Bronze layer can
demonstrate incremental extraction on Odoo's canonical cursor, `write_date`.

## Files (run in order)

| File | Purpose |
|------|---------|
| `01_schema.sql`        | Creates the OLTP tables (schema `public`), indexes, `write_date` triggers, and the `etl_checkpoints` table. **Drops and recreates these tables.** |
| `02_seed_reference.sql`| Seeds static dimensions: `res_country`, `res_country_state`, a 2-level `product_category` tree, and `stock_warehouse` (idempotent). |
| `03_generate_data.sql` | Generates partners, products, orders, lines, payments, stock. Volumes configurable. |
| `04_summary.sql`       | Row counts + integrity/recency checks. |
| `seed.sh`              | Runs all four in order using libpq env vars. |

## Schema (Odoo table names)

```
res_country ─┐
             ├─ res_country_state ──┐
             │        │             │
   res_partner◄───────┘         stock_warehouse
        │                           │      │
        │            product_category│      │
        │                  │         │      │
        │          product_template  │      │
        │                  │         │      │
        │          product_product ──┴── stock_quant
        │                  │
     sale_order ───► sale_order_line
        │                  (price_total incl. tax)
   account_payment
   (amount = sale_order.amount_total = Σ line.price_total)
```

Every table has `create_date` / `write_date`; a BEFORE UPDATE trigger bumps
`write_date` to `now()` — the same field Odoo connectors use as the incremental
cursor. Odoo conventions preserved: `res_partner.active`/`customer_rank`,
`product_category.complete_name`, `product_template` (price/cost) vs
`product_product` (sellable variant), `sale_order.state`
(draft/sent/sale/done/cancel), and computed `amount_untaxed/tax/total`.

## Usage

Connection comes from libpq env vars (`PGHOST`, `PGPORT`, `PGUSER`,
`PGPASSWORD`, `PGDATABASE`) or `DATABASE_URL`. In the Docker stack this all runs
via the `seed` service — see the top-level [README](../README.md).

```bash
# Full portfolio scale: 100K partners / 20K products / 10M orders
./seed.sh

# Small smoke test (seconds)
N_CUSTOMERS=2000 N_PRODUCTS=500 N_ORDERS=20000 ./seed.sh
```

Or call `psql` directly:

```bash
psql -v ON_ERROR_STOP=1 -f 01_schema.sql
psql -v ON_ERROR_STOP=1 -f 02_seed_reference.sql
psql -v ON_ERROR_STOP=1 \
     -v n_customers=100000 -v n_products=20000 -v n_orders=10000000 \
     -v history_days=730 -v tax_rate=0.15 -v seed=0.42 \
     -f 03_generate_data.sql
psql -v ON_ERROR_STOP=1 -f 04_summary.sql
```

### Generator knobs

| Variable | `seed.sh` env | Default | Meaning |
|----------|---------------|---------|---------|
| `n_customers` | `N_CUSTOMERS` | 100000 | `res_partner` rows |
| `n_products`  | `N_PRODUCTS`  | 20000  | `product_template`/`product_product` rows |
| `n_orders`    | `N_ORDERS`    | 10000000 | `sale_order` rows (each fans out to 1–5 lines) |
| `history_days`| `HISTORY_DAYS`| 730    | size of the timestamp window ending "now" |
| `tax_rate`    | `TAX_RATE`    | 0.15   | tax applied to `price_total` / `amount_tax` |
| `seed`        | `SEED`        | 0.42   | `setseed()` value for reproducible runs |

## What makes the data realistic

- **Recency-weighted orders** (`random()^1.6`) — more orders near "now", so a
  "last 7 days" incremental slice is always non-empty.
- **Derived consistency** — a line's `price_total` = `price_subtotal × (1+tax)`;
  `sale_order.amount_total` is rolled up from its lines; a payment's `amount`
  equals its order's `amount_total`, and its `state` follows the order state.
- **Designed distributions** — order state ≈ 46% sale / 30% done / 8% sent /
  8% draft / 8% cancel; ~8% archived partners; ~5% discontinued products;
  discounts on ~25% of lines.
- `04_summary.sql` verifies 0 tax mismatches, 0 payment mismatches, 0 orphans.

## Implementation notes

- The generator is **set-based** (`INSERT ... SELECT` over `generate_series`)
  and scales to millions of rows; `sale_order` / `sale_order_line` dominate
  wall-clock. `ANALYZE` runs at the end.
- `sale_order.amount_*` is backfilled with the `write_date` trigger temporarily
  disabled, so the historical `write_date` spread survives the rollup (otherwise
  every order would jump to `now()` and incremental-backfill demos would break).
- All `random()` lives either inline in the `SELECT` list or inside
  **correlated** LATERAL subqueries, and random ids are chosen in the SELECT
  (then joined) rather than in a `WHERE col = random()` — an uncorrelated
  volatile sub-select is evaluated once (freezing the value), and `random()` in
  a `WHERE` equality re-rolls per scanned row (matching nothing).
- `stock_quant` is generated for physical warehouses only
  (`warehouse_type <> 'online'`), one row per (product, warehouse).
- `product_product` is 1:1 with `product_template` here; Odoo supports many
  variants per template.
