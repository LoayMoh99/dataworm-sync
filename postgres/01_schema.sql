-- =============================================================================
-- OLTP SOURCE SCHEMA (PostgreSQL) — Odoo-inspired ERP model (Egypt edition)
-- =============================================================================
-- Table & column names follow Odoo's core sales/purchase/inventory schema so
-- this looks like an extract from a real Odoo ERP running an Egyptian retailer:
--
--   muhafazat / cities                geography (governorates + their cities)
--   res_partner                       customers AND vendors (rank columns)
--   product_category                  category tree (parent_id, complete_name)
--   product_template / product_product template + MANY sellable variants
--   product_supplierinfo              vendor pricelist (which vendor sells what)
--   stock_location / stock_quant      flat physical locations + on-hand stock
--   sale_order / sale_order_line       sales orders + lines
--   account_payment                    customer payments (full / partial / none)
--   purchase_order / purchase_order_line  vendor purchases (completed or not)
--
-- Like Odoo, every table carries `create_date` / `write_date`; `write_date` is
-- the canonical cursor for incremental extraction. A BEFORE UPDATE trigger
-- bumps `write_date` to now() on every change.
--
-- IMPORTANT: this is *raw* source data, intentionally NOT cleaned. Expect
-- inconsistent casing/whitespace, mixed phone formats, null contact fields,
-- free-text `city` that disagrees with `city_id`, and duplicate/near-duplicate
-- partners (email is deliberately NOT unique). Cleaning is the ETL's job.
--
-- NOTE: there is no `etl_checkpoints` table here on purpose — incremental
-- bookkeeping is owned by whoever builds the pipeline, not by the source.
--
-- Lives in the `public` schema. Re-running drops and recreates these tables.
--
-- Run:  psql -v ON_ERROR_STOP=1 -f 01_schema.sql
-- =============================================================================

BEGIN;

DROP TABLE IF EXISTS
    account_payment, sale_order_line, sale_order,
    purchase_order_line, purchase_order, product_supplierinfo,
    stock_quant, product_product, product_template, product_category,
    res_partner, stock_location, cities, muhafazat,
    etl_checkpoints,                       -- dropped if a previous run created it
    res_country_state, res_country         -- superseded by muhafazat / cities
    CASCADE;
DROP FUNCTION IF EXISTS set_write_date() CASCADE;

-- -----------------------------------------------------------------------------
-- Geography — Egypt governorates (muhafazat) and their cities
-- -----------------------------------------------------------------------------

CREATE TABLE muhafazat (                   -- governorate ("muhafaza")
    id          SERIAL PRIMARY KEY,
    name        TEXT        NOT NULL,       -- English name
    name_ar     TEXT        NOT NULL,       -- Arabic name
    code        TEXT        NOT NULL UNIQUE,-- ISO 3166-2 (e.g. 'EG-C')
    create_date TIMESTAMPTZ NOT NULL DEFAULT now(),
    write_date  TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE cities (
    id           SERIAL PRIMARY KEY,
    muhafaza_id  INT         NOT NULL REFERENCES muhafazat (id),
    name         TEXT        NOT NULL,
    name_ar      TEXT,
    create_date  TIMESTAMPTZ NOT NULL DEFAULT now(),
    write_date   TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (muhafaza_id, name)
);

-- -----------------------------------------------------------------------------
-- Partners — customers AND vendors (one table, distinguished by partner_type).
-- Location is a governorate (+ optional city).
-- NOTE: email is intentionally NOT UNIQUE — duplicate partners are part of the
-- "dirty source" this project is built to clean.
-- -----------------------------------------------------------------------------

CREATE TABLE res_partner (
    id             BIGSERIAL PRIMARY KEY,
    name           TEXT        NOT NULL,
    email          TEXT,                                    -- may be null / dup / messy
    phone          TEXT,                                    -- mixed formats / null
    street         TEXT,
    city           TEXT,                                    -- FREE TEXT, often != city_id
    city_id        INT         REFERENCES cities (id),      -- canonical city (nullable)
    muhafaza_id    INT         NOT NULL REFERENCES muhafazat (id),
    is_company     BOOLEAN     NOT NULL DEFAULT FALSE,
    partner_type   TEXT        NOT NULL CHECK (partner_type IN ('customer','vendor')),  -- role
    segment        TEXT,                                     -- consumer/small_business/enterprise (customers only)
    active         BOOLEAN     NOT NULL DEFAULT TRUE,        -- Odoo archiving flag
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

-- Many variants per template (color / size / price_extra), Odoo-style.
CREATE TABLE product_product (
    id              BIGSERIAL PRIMARY KEY,
    product_tmpl_id BIGINT        NOT NULL REFERENCES product_template (id),
    default_code    TEXT          NOT NULL UNIQUE,
    barcode         TEXT          UNIQUE,                -- nullable; some missing
    name            TEXT          NOT NULL,             -- variant display name
    color           TEXT,                               -- variant attribute
    size            TEXT,                               -- variant attribute
    price_extra     NUMERIC(12,2) NOT NULL DEFAULT 0,   -- added to template list_price
    active          BOOLEAN       NOT NULL DEFAULT TRUE,
    create_date     TIMESTAMPTZ   NOT NULL DEFAULT now(),
    write_date      TIMESTAMPTZ   NOT NULL DEFAULT now()
);

-- Vendor pricelist: which vendor(s) can supply a product, at what price / lead.
CREATE TABLE product_supplierinfo (
    id          BIGSERIAL PRIMARY KEY,
    product_id  BIGINT        NOT NULL REFERENCES product_product (id),
    partner_id  BIGINT        NOT NULL REFERENCES res_partner (id),   -- vendor
    price       NUMERIC(12,2) NOT NULL CHECK (price >= 0),            -- vendor price
    min_qty     NUMERIC(12,3) NOT NULL DEFAULT 1,
    delay       INT           NOT NULL DEFAULT 7,                     -- lead time (days)
    create_date TIMESTAMPTZ   NOT NULL DEFAULT now(),
    write_date  TIMESTAMPTZ   NOT NULL DEFAULT now(),
    UNIQUE (product_id, partner_id)
);

-- -----------------------------------------------------------------------------
-- Locations & stock — flat physical locations; a product can sit in several,
-- with quantity on-hand and part of it reserved. (No UNIQUE(product,location):
-- Odoo allows multiple quant rows per product/location.)
-- -----------------------------------------------------------------------------

CREATE TABLE stock_location (
    id             SERIAL PRIMARY KEY,
    name           TEXT        NOT NULL,
    code           TEXT        NOT NULL UNIQUE,
    location_type  TEXT        NOT NULL,       -- warehouse / store / transit
    muhafaza_id    INT         REFERENCES muhafazat (id),
    city_id        INT         REFERENCES cities (id),
    create_date    TIMESTAMPTZ NOT NULL DEFAULT now(),
    write_date     TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE stock_quant (
    id                BIGSERIAL PRIMARY KEY,
    product_id        BIGINT        NOT NULL REFERENCES product_product (id),
    location_id       INT           NOT NULL REFERENCES stock_location (id),
    quantity          NUMERIC(12,3) NOT NULL CHECK (quantity >= 0),
    reserved_quantity NUMERIC(12,3) NOT NULL DEFAULT 0,
    create_date       TIMESTAMPTZ   NOT NULL DEFAULT now(),
    write_date        TIMESTAMPTZ   NOT NULL DEFAULT now()
);

-- -----------------------------------------------------------------------------
-- Sales
-- -----------------------------------------------------------------------------

CREATE TABLE sale_order (
    id             BIGSERIAL PRIMARY KEY,
    name           TEXT          NOT NULL UNIQUE,       -- 'S00000001'
    partner_id     BIGINT        NOT NULL REFERENCES res_partner (id),
    location_id    INT           NOT NULL REFERENCES stock_location (id),
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

-- Customer payments. Unlike a naive model, an order may have zero, one, several
-- (partial), or a single full payment — so SUM(payments) rarely equals
-- amount_total. That open-balance messiness is intentional.
CREATE TABLE account_payment (
    id             BIGSERIAL PRIMARY KEY,
    name           TEXT          NOT NULL UNIQUE,       -- 'P00000001-1'
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
-- Purchases (from vendors)
-- -----------------------------------------------------------------------------

CREATE TABLE purchase_order (
    id             BIGSERIAL PRIMARY KEY,
    name           TEXT          NOT NULL UNIQUE,       -- 'PO0000001'
    partner_id     BIGINT        NOT NULL REFERENCES res_partner (id),  -- vendor
    location_id    INT           REFERENCES stock_location (id),        -- destination
    date_order     TIMESTAMPTZ   NOT NULL,
    state          TEXT          NOT NULL,              -- draft/sent/purchase/done/cancel
    amount_untaxed NUMERIC(14,2) NOT NULL DEFAULT 0,
    amount_tax     NUMERIC(14,2) NOT NULL DEFAULT 0,
    amount_total   NUMERIC(14,2) NOT NULL DEFAULT 0,
    create_date    TIMESTAMPTZ   NOT NULL DEFAULT now(),
    write_date     TIMESTAMPTZ   NOT NULL DEFAULT now()
);

CREATE TABLE purchase_order_line (
    id             BIGSERIAL PRIMARY KEY,
    order_id       BIGINT        NOT NULL REFERENCES purchase_order (id),
    product_id     BIGINT        NOT NULL REFERENCES product_product (id),
    product_qty    NUMERIC(12,3) NOT NULL CHECK (product_qty > 0),
    price_unit     NUMERIC(12,2) NOT NULL CHECK (price_unit >= 0),      -- vendor cost
    price_subtotal NUMERIC(14,2) NOT NULL,
    price_total    NUMERIC(14,2) NOT NULL,
    create_date    TIMESTAMPTZ   NOT NULL DEFAULT now(),
    write_date     TIMESTAMPTZ   NOT NULL DEFAULT now()
);

-- -----------------------------------------------------------------------------
-- Indexes for incremental extraction (write_date) & join-heavy fact builds
-- -----------------------------------------------------------------------------

CREATE INDEX idx_cities_muhafaza_id            ON cities             (muhafaza_id);
CREATE INDEX idx_res_partner_write_date        ON res_partner        (write_date);
CREATE INDEX idx_res_partner_muhafaza_id       ON res_partner        (muhafaza_id);
CREATE INDEX idx_res_partner_city_id           ON res_partner        (city_id);
CREATE INDEX idx_res_partner_type              ON res_partner        (partner_type);
CREATE INDEX idx_product_template_write_date   ON product_template   (write_date);
CREATE INDEX idx_product_product_write_date    ON product_product    (write_date);
CREATE INDEX idx_product_product_tmpl_id       ON product_product    (product_tmpl_id);
CREATE INDEX idx_supplierinfo_product_id       ON product_supplierinfo (product_id);
CREATE INDEX idx_supplierinfo_partner_id       ON product_supplierinfo (partner_id);
CREATE INDEX idx_sale_order_write_date         ON sale_order         (write_date);
CREATE INDEX idx_sale_order_date_order         ON sale_order         (date_order);
CREATE INDEX idx_sale_order_partner_id         ON sale_order         (partner_id);
CREATE INDEX idx_sale_order_line_order_id      ON sale_order_line    (order_id);
CREATE INDEX idx_sale_order_line_product_id    ON sale_order_line    (product_id);
CREATE INDEX idx_sale_order_line_write_date    ON sale_order_line    (write_date);
CREATE INDEX idx_account_payment_order_id      ON account_payment    (sale_order_id);
CREATE INDEX idx_account_payment_write_date    ON account_payment    (write_date);
CREATE INDEX idx_purchase_order_write_date     ON purchase_order     (write_date);
CREATE INDEX idx_purchase_order_partner_id     ON purchase_order     (partner_id);
CREATE INDEX idx_purchase_order_line_order_id  ON purchase_order_line (order_id);
CREATE INDEX idx_purchase_order_line_product   ON purchase_order_line (product_id);
CREATE INDEX idx_stock_quant_product_id        ON stock_quant        (product_id);
CREATE INDEX idx_stock_quant_location_id       ON stock_quant        (location_id);
CREATE INDEX idx_stock_quant_write_date        ON stock_quant        (write_date);

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
        'muhafazat','cities','res_partner','product_category',
        'product_template','product_product','product_supplierinfo',
        'stock_location','stock_quant','sale_order','sale_order_line',
        'account_payment','purchase_order','purchase_order_line'
    ] LOOP
        EXECUTE format(
            'CREATE TRIGGER trg_%1$s_write_date
               BEFORE UPDATE ON %1$s
               FOR EACH ROW EXECUTE FUNCTION set_write_date();', t);
    END LOOP;
END $$;

COMMIT;

\echo 'OLTP (Odoo-inspired, Egypt edition) tables created in schema public.'
