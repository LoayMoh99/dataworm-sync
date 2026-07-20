-- =============================================================================
-- OLTP SOURCE SCHEMA (PostgreSQL) — Odoo-inspired ERP model
-- =============================================================================
-- Table & column names follow Odoo's core sales/inventory schema so this looks
-- like an extract from a real Odoo ERP:
--
--   res_country / res_country_state   geography
--   res_partner                       customers/contacts
--   product_category                  category tree (parent_id, complete_name)
--   product_template / product_product template + sellable variant
--   stock_warehouse / stock_quant     warehouses + on-hand stock
--   sale_order / sale_order_line       sales orders + lines
--   account_payment                    customer payments
--
-- Like Odoo, every table carries `create_date` / `write_date`; `write_date` is
-- the canonical cursor for incremental extraction in the Bronze layer. A
-- BEFORE UPDATE trigger bumps `write_date` to now() on every change.
--
-- Lives in the `public` schema. Re-running drops and recreates these tables.
--
-- Run:  psql -v ON_ERROR_STOP=1 -f 01_schema.sql
-- =============================================================================

BEGIN;

DROP TABLE IF EXISTS
    account_payment, sale_order_line, sale_order, stock_quant,
    product_product, product_template, product_category,
    res_partner, stock_warehouse, res_country_state, res_country,
    etl_checkpoints CASCADE;
DROP FUNCTION IF EXISTS set_write_date() CASCADE;

-- -----------------------------------------------------------------------------
-- Geography
-- -----------------------------------------------------------------------------

CREATE TABLE res_country (
    id          SERIAL PRIMARY KEY,
    name        TEXT        NOT NULL,
    code        CHAR(2)     NOT NULL UNIQUE,     -- ISO 3166-1 alpha-2
    create_date TIMESTAMPTZ NOT NULL DEFAULT now(),
    write_date  TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE res_country_state (          -- acts as the "region" dimension
    id          SERIAL PRIMARY KEY,
    country_id  INT         NOT NULL REFERENCES res_country (id),
    name        TEXT        NOT NULL,
    code        TEXT        NOT NULL,
    create_date TIMESTAMPTZ NOT NULL DEFAULT now(),
    write_date  TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (country_id, name)
);

-- -----------------------------------------------------------------------------
-- Partners (customers)
-- -----------------------------------------------------------------------------

CREATE TABLE res_partner (
    id             BIGSERIAL PRIMARY KEY,
    name           TEXT        NOT NULL,
    email          TEXT        NOT NULL UNIQUE,
    phone          TEXT,
    street         TEXT,
    city           TEXT,
    state_id       INT         REFERENCES res_country_state (id),
    country_id     INT         REFERENCES res_country (id),
    is_company     BOOLEAN     NOT NULL DEFAULT FALSE,
    customer_rank  INT         NOT NULL DEFAULT 0,     -- Odoo: >0 => is a customer
    supplier_rank  INT         NOT NULL DEFAULT 0,
    segment        TEXT        NOT NULL,               -- consumer / small_business / enterprise
    active         BOOLEAN     NOT NULL DEFAULT TRUE,  -- Odoo archiving flag
    create_date    TIMESTAMPTZ NOT NULL DEFAULT now(),
    write_date     TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- -----------------------------------------------------------------------------
-- Products
-- -----------------------------------------------------------------------------

CREATE TABLE product_category (
    id            SERIAL PRIMARY KEY,
    name          TEXT        NOT NULL,
    parent_id     INT         REFERENCES product_category (id),
    complete_name TEXT        NOT NULL UNIQUE,          -- 'Electronics / Laptops'
    create_date   TIMESTAMPTZ NOT NULL DEFAULT now(),
    write_date    TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE product_template (
    id             BIGSERIAL PRIMARY KEY,
    name           TEXT          NOT NULL,
    categ_id       INT           NOT NULL REFERENCES product_category (id),
    default_code   TEXT          NOT NULL UNIQUE,       -- internal reference
    list_price     NUMERIC(12,2) NOT NULL CHECK (list_price     >= 0),  -- sale price
    standard_price NUMERIC(12,2) NOT NULL CHECK (standard_price >= 0),  -- cost
    type           TEXT          NOT NULL DEFAULT 'product',            -- consu/service/product
    active         BOOLEAN       NOT NULL DEFAULT TRUE,
    create_date    TIMESTAMPTZ   NOT NULL DEFAULT now(),
    write_date     TIMESTAMPTZ   NOT NULL DEFAULT now()
);

CREATE TABLE product_product (           -- sellable variant of a template
    id              BIGSERIAL PRIMARY KEY,
    product_tmpl_id BIGINT      NOT NULL REFERENCES product_template (id),
    default_code    TEXT        NOT NULL UNIQUE,
    barcode         TEXT        UNIQUE,
    active          BOOLEAN     NOT NULL DEFAULT TRUE,
    create_date     TIMESTAMPTZ NOT NULL DEFAULT now(),
    write_date      TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- -----------------------------------------------------------------------------
-- Warehouses & stock
-- -----------------------------------------------------------------------------

CREATE TABLE stock_warehouse (
    id             SERIAL PRIMARY KEY,
    name           TEXT        NOT NULL,
    code           TEXT        NOT NULL UNIQUE,
    state_id       INT         REFERENCES res_country_state (id),
    warehouse_type TEXT        NOT NULL,       -- flagship / standard / outlet / online
    create_date    TIMESTAMPTZ NOT NULL DEFAULT now(),
    write_date     TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE stock_quant (
    id                BIGSERIAL PRIMARY KEY,
    product_id        BIGINT        NOT NULL REFERENCES product_product (id),
    warehouse_id      INT           NOT NULL REFERENCES stock_warehouse (id),
    quantity          NUMERIC(12,3) NOT NULL CHECK (quantity >= 0),
    reserved_quantity NUMERIC(12,3) NOT NULL DEFAULT 0,
    create_date       TIMESTAMPTZ   NOT NULL DEFAULT now(),
    write_date        TIMESTAMPTZ   NOT NULL DEFAULT now(),
    UNIQUE (product_id, warehouse_id)
);

-- -----------------------------------------------------------------------------
-- Sales
-- -----------------------------------------------------------------------------

CREATE TABLE sale_order (
    id             BIGSERIAL PRIMARY KEY,
    name           TEXT          NOT NULL UNIQUE,       -- 'S00000001'
    partner_id     BIGINT        NOT NULL REFERENCES res_partner (id),
    warehouse_id   INT           NOT NULL REFERENCES stock_warehouse (id),
    date_order     TIMESTAMPTZ   NOT NULL,
    state          TEXT          NOT NULL,              -- draft/sent/sale/done/cancel
    amount_untaxed NUMERIC(14,2) NOT NULL DEFAULT 0,
    amount_tax     NUMERIC(14,2) NOT NULL DEFAULT 0,
    amount_total   NUMERIC(14,2) NOT NULL DEFAULT 0,
    create_date    TIMESTAMPTZ   NOT NULL DEFAULT now(),
    write_date     TIMESTAMPTZ   NOT NULL DEFAULT now()
);

CREATE TABLE sale_order_line (
    id              BIGSERIAL PRIMARY KEY,
    order_id        BIGINT        NOT NULL REFERENCES sale_order (id),
    product_id      BIGINT        NOT NULL REFERENCES product_product (id),
    product_uom_qty NUMERIC(12,3) NOT NULL CHECK (product_uom_qty > 0),
    price_unit      NUMERIC(12,2) NOT NULL CHECK (price_unit >= 0),
    discount        NUMERIC(5,2)  NOT NULL DEFAULT 0 CHECK (discount BETWEEN 0 AND 100), -- percent
    price_subtotal  NUMERIC(14,2) NOT NULL,             -- untaxed
    price_total     NUMERIC(14,2) NOT NULL,             -- taxed
    create_date     TIMESTAMPTZ   NOT NULL DEFAULT now(),
    write_date      TIMESTAMPTZ   NOT NULL DEFAULT now()
);

CREATE TABLE account_payment (
    id             BIGSERIAL PRIMARY KEY,
    name           TEXT          NOT NULL UNIQUE,       -- 'P00000001'
    partner_id     BIGINT        NOT NULL REFERENCES res_partner (id),
    sale_order_id  BIGINT        NOT NULL REFERENCES sale_order (id),  -- simplified link
    amount         NUMERIC(14,2) NOT NULL CHECK (amount >= 0),
    payment_type   TEXT          NOT NULL DEFAULT 'inbound',
    partner_type   TEXT          NOT NULL DEFAULT 'customer',
    journal        TEXT          NOT NULL,              -- bank / cash
    payment_method TEXT          NOT NULL,              -- manual / electronic
    state          TEXT          NOT NULL,              -- draft/posted/sent/reconciled/cancelled
    payment_date   TIMESTAMPTZ,
    create_date    TIMESTAMPTZ   NOT NULL DEFAULT now(),
    write_date     TIMESTAMPTZ   NOT NULL DEFAULT now()
);

-- -----------------------------------------------------------------------------
-- Indexes for incremental extraction (write_date) & join-heavy fact builds
-- -----------------------------------------------------------------------------

CREATE INDEX idx_res_partner_write_date       ON res_partner       (write_date);
CREATE INDEX idx_product_template_write_date   ON product_template  (write_date);
CREATE INDEX idx_product_product_write_date    ON product_product   (write_date);
CREATE INDEX idx_sale_order_write_date         ON sale_order        (write_date);
CREATE INDEX idx_sale_order_date_order         ON sale_order        (date_order);
CREATE INDEX idx_sale_order_partner_id         ON sale_order        (partner_id);
CREATE INDEX idx_sale_order_line_order_id      ON sale_order_line   (order_id);
CREATE INDEX idx_sale_order_line_product_id    ON sale_order_line   (product_id);
CREATE INDEX idx_sale_order_line_write_date     ON sale_order_line  (write_date);
CREATE INDEX idx_account_payment_order_id      ON account_payment   (sale_order_id);
CREATE INDEX idx_account_payment_write_date     ON account_payment  (write_date);
CREATE INDEX idx_stock_quant_write_date         ON stock_quant      (write_date);

-- -----------------------------------------------------------------------------
-- ETL checkpoint bookkeeping (used by the Bronze layer for incremental loads)
-- -----------------------------------------------------------------------------

CREATE TABLE etl_checkpoints (
    table_name      TEXT PRIMARY KEY,
    last_write_date TIMESTAMPTZ,
    last_id         BIGINT,
    rows_loaded     BIGINT      NOT NULL DEFAULT 0,
    checkpoint_ts   TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- -----------------------------------------------------------------------------
-- Auto-maintain write_date on UPDATE so CDC-style incrementals stay honest
-- -----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION set_write_date() RETURNS trigger AS $$
BEGIN
    NEW.write_date = now();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DO $$
DECLARE t TEXT;
BEGIN
    FOREACH t IN ARRAY ARRAY[
        'res_country','res_country_state','res_partner','product_category',
        'product_template','product_product','stock_warehouse','stock_quant',
        'sale_order','sale_order_line','account_payment'
    ] LOOP
        EXECUTE format(
            'CREATE TRIGGER trg_%1$s_write_date
               BEFORE UPDATE ON %1$s
               FOR EACH ROW EXECUTE FUNCTION set_write_date();', t);
    END LOOP;
END $$;

COMMIT;

\echo 'OLTP (Odoo-inspired) tables created in schema public.'
