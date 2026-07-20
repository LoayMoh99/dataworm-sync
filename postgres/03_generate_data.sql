-- =============================================================================
-- CONFIGURABLE DATA GENERATOR (Odoo-inspired)
-- =============================================================================
-- Generates realistic, referentially-consistent volumes into the public schema.
-- Set-based (INSERT ... SELECT over generate_series) so it scales to millions
-- of rows. date_order / write_date are recency-weighted over a configurable
-- window so the ETL layer can demonstrate incremental loads on `write_date`.
--
-- Configure with -v flags (all optional; defaults shown):
--   psql -v ON_ERROR_STOP=1 \
--        -v n_customers=100000 \
--        -v n_products=20000 \
--        -v n_orders=10000000 \
--        -v history_days=730 \
--        -v tax_rate=0.15 \
--        -v seed=0.42 \
--        -f 03_generate_data.sql
--
-- Tip: start small (n_orders=100000) to validate, then scale up.
-- =============================================================================

\timing on

-- ---- Defaults for any value not supplied on the command line ----------------
\if :{?n_customers} \else \set n_customers 100000 \endif
\if :{?n_products}  \else \set n_products  20000  \endif
\if :{?n_orders}    \else \set n_orders    10000000 \endif
\if :{?history_days}\else \set history_days 730    \endif
\if :{?tax_rate}    \else \set tax_rate 0.15       \endif
\if :{?seed}        \else \set seed 0.42           \endif

\echo '>> Generating:' :n_customers 'partners,' :n_products 'products,' :n_orders 'orders'
\echo '>> History window:' :history_days 'days   Tax:' :tax_rate '  Seed:' :seed

-- Reproducible pseudo-randomness for this session.
SELECT setseed(:seed);

-- Pull live cardinalities of the reference tables into psql variables.
SELECT count(*) AS n_countries  FROM res_country       \gset
SELECT count(*) AS n_states     FROM res_country_state  \gset
SELECT count(*) AS n_categories FROM product_category   \gset
SELECT count(*) AS n_warehouses FROM stock_warehouse    \gset
\echo '>> Reference sizes:' :n_countries 'countries,' :n_states 'states,' :n_categories 'categories,' :n_warehouses 'warehouses'

-- =============================================================================
-- 1. res_partner (customers)
-- =============================================================================
\echo '>> [1/8] res_partner ...'
INSERT INTO res_partner
    (name, email, phone, street, city, state_id, country_id, is_company,
     customer_rank, supplier_rank, segment, active, create_date, write_date)
SELECT
    nm.fn || ' ' || nm.ln,
    lower(nm.fn || '.' || nm.ln || i || '@' ||
          (ARRAY['example.com','mailtest.io','acme.co','shopmail.net'])[1 + (i % 4)]),
    '+1-' || lpad(((i * 7919) % 1000)::text, 3, '0') || '-' ||
             lpad(((i * 104729) % 10000)::text, 4, '0'),
    (1 + (i % 900)) || ' ' ||
        (ARRAY['Main','Oak','Maple','Cedar','Pine','Elm','Lake','Hill'])[1 + (i % 8)] || ' St',
    st.name,
    st.id,
    st.country_id,
    random() < 0.15,                                   -- ~15% are companies
    1,                                                 -- customer_rank > 0 => customer
    0,
    (ARRAY['consumer','consumer','consumer','small_business','enterprise'])[1 + floor(random() * 5)::int],
    random() > 0.08,                                   -- ~8% archived/inactive
    now() - (floor(random() * (:history_days * 0.8)) || ' days')::interval,
    now() - (floor(random() * :history_days) || ' days')::interval
FROM generate_series(1, :n_customers) AS g(i)
CROSS JOIN LATERAL (
    SELECT
        (ARRAY['James','Mary','John','Patricia','Robert','Jennifer','Michael','Linda',
               'David','Elizabeth','Omar','Fatima','Wei','Yuki','Sofia','Lucas',
               'Aisha','Diego','Anna','Noah'])[1 + (i * 13) % 20]           AS fn,
        (ARRAY['Smith','Johnson','Williams','Brown','Jones','Garcia','Miller','Davis',
               'Rodriguez','Martinez','Khan','Nguyen','Chen','Tanaka','Rossi','Muller',
               'Ali','Silva','Novak','Kowalski'])[1 + (i * 29) % 20]        AS ln
) nm
-- Correlated (references g.i) so a single random state id is chosen per
-- partner, then joined (picking in the SELECT, not a WHERE against s.id, so
-- random() is rolled once rather than re-rolled per scanned state row).
CROSS JOIN LATERAL (SELECT g.i AS _i, 1 + floor(random() * :n_states)::int AS sid) pick
JOIN res_country_state st ON st.id = pick.sid;

-- =============================================================================
-- 2. product_template
-- =============================================================================
\echo '>> [2/8] product_template ...'
INSERT INTO product_template
    (name, categ_id, default_code, list_price, standard_price, type, active, create_date, write_date)
SELECT
    (ARRAY['Pro','Ultra','Max','Lite','Eco','Prime','Smart','Classic','Nano','Mega'])[1 + (i * 7) % 10]
        || ' ' ||
    (ARRAY['Widget','Gadget','Device','Kit','Bundle','Tool','Gear','Unit','Pack','Set'])[1 + (i * 11) % 10]
        || ' ' || i,
    1 + floor(random() * :n_categories)::int,
    'T' || lpad(i::text, 8, '0'),
    price.p,
    round((price.p * (0.45 + random() * 0.3))::numeric, 2),      -- cost 45-75% of price
    'product',
    random() > 0.05,                                             -- ~5% discontinued
    now() - (floor(random() * :history_days) || ' days')::interval,
    now() - (floor(random() * :history_days) || ' days')::interval
FROM generate_series(1, :n_products) AS g(i)
-- `g.i` reference correlates the LATERAL so random() runs per row.
CROSS JOIN LATERAL (SELECT round((5 + random() * 995)::numeric, 2) AS p, g.i AS _i) price;

-- =============================================================================
-- 3. product_product (one sellable variant per template)
-- =============================================================================
\echo '>> [3/8] product_product ...'
INSERT INTO product_product
    (product_tmpl_id, default_code, barcode, active, create_date, write_date)
SELECT
    t.id,
    'P'   || lpad(t.id::text, 8, '0'),
    '900' || lpad(t.id::text, 10, '0'),
    t.active,
    t.create_date,
    t.write_date
FROM product_template t;

-- =============================================================================
-- 4. sale_order (amounts filled in step 6, once lines exist)
-- =============================================================================
-- Warehouse picked first; state distribution ~ draft/sent 16%, sale 46%,
-- done 30%, cancel 8%. date_order recency-weighted (random()^1.6) toward now.
\echo '>> [4/8] sale_order ... (largest step)'
INSERT INTO sale_order
    (name, partner_id, warehouse_id, date_order, state, create_date, write_date)
SELECT
    'S' || lpad(i::text, 8, '0'),
    1 + floor(random() * :n_customers)::int,
    w.id,
    r.ord_ts,
    CASE
        WHEN r.st < 0.08 THEN 'cancel'
        WHEN r.st < 0.16 THEN 'draft'
        WHEN r.st < 0.24 THEN 'sent'
        WHEN r.st < 0.70 THEN 'sale'
        ELSE 'done'
    END,
    r.ord_ts,
    r.ord_ts
FROM generate_series(1, :n_orders) AS g(i)
-- `g.i` reference correlates the LATERAL -> random() is evaluated per order.
CROSS JOIN LATERAL (
    SELECT g.i AS _i,
           (now() - (power(random(), 1.6) * :history_days) * INTERVAL '1 day') AS ord_ts,
           random()                                                            AS st,
           (1 + floor(random() * :n_warehouses)::int)                         AS wh
) r
JOIN stock_warehouse w ON w.id = r.wh;

-- =============================================================================
-- 5. sale_order_line  (1-5 lines per order; price_total includes tax)
-- =============================================================================
\echo '>> [5/8] sale_order_line ...'
INSERT INTO sale_order_line
    (order_id, product_id, product_uom_qty, price_unit, discount,
     price_subtotal, price_total, create_date, write_date)
SELECT
    o.id,
    pp.id,
    li.qty,
    pt.list_price,
    li.disc,
    round((li.qty * pt.list_price * (1 - li.disc / 100))::numeric, 2)                     AS price_subtotal,
    round((li.qty * pt.list_price * (1 - li.disc / 100) * (1 + :tax_rate))::numeric, 2)   AS price_total,
    o.create_date,
    o.write_date
FROM sale_order o
-- Correlated (references o.id) so the line count varies per order.
CROSS JOIN LATERAL (SELECT 1 + floor(random() * 5)::int AS n_items, o.id AS _oid) cnt
CROSS JOIN LATERAL generate_series(1, cnt.n_items) AS line(n)
-- Correlated (references line.n) so each line gets its own product/qty/discount.
CROSS JOIN LATERAL (
    SELECT line.n                                                    AS _n,
           (1 + floor(random() * :n_products)::int)                  AS pid,
           (1 + floor(random() * 5)::int)                            AS qty,
           CASE WHEN random() < 0.25
                THEN round((random() * 30)::numeric, 2) ELSE 0 END   AS disc   -- percent
) li
JOIN product_product  pp ON pp.id = li.pid
JOIN product_template pt ON pt.id = pp.product_tmpl_id;

-- =============================================================================
-- 6. Roll line totals up onto sale_order (like Odoo's computed amount_* fields)
-- =============================================================================
-- Disable the write_date trigger for this bulk UPDATE so the historical
-- write_date spread from step 4 is preserved (otherwise every order would jump
-- to now() and incremental-backfill demos would be meaningless).
\echo '>> [6/8] sale_order amount_* rollup ...'
ALTER TABLE sale_order DISABLE TRIGGER trg_sale_order_write_date;
UPDATE sale_order so
SET amount_untaxed = agg.subtotal,
    amount_tax     = agg.total - agg.subtotal,
    amount_total   = agg.total
FROM (
    SELECT order_id,
           sum(price_subtotal) AS subtotal,
           sum(price_total)    AS total
    FROM sale_order_line
    GROUP BY order_id
) agg
WHERE agg.order_id = so.id;
ALTER TABLE sale_order ENABLE TRIGGER trg_sale_order_write_date;

-- =============================================================================
-- 7. account_payment  (one per order; amount = amount_total; state from order)
-- =============================================================================
\echo '>> [7/8] account_payment ...'
INSERT INTO account_payment
    (name, partner_id, sale_order_id, amount, payment_type, partner_type,
     journal, payment_method, state, payment_date, create_date, write_date)
SELECT
    'P' || lpad(o.id::text, 8, '0'),
    o.partner_id,
    o.id,
    o.amount_total,
    'inbound',
    'customer',
    (ARRAY['bank','bank','bank','cash'])[1 + floor(random() * 4)::int],
    (ARRAY['manual','electronic'])[1 + floor(random() * 2)::int],
    CASE o.state
        WHEN 'cancel' THEN 'cancelled'
        WHEN 'draft'  THEN 'draft'
        WHEN 'sent'   THEN 'draft'
        WHEN 'sale'   THEN 'posted'
        ELSE 'reconciled'
    END,
    CASE WHEN o.state IN ('sale','done')
         THEN o.date_order + (floor(random() * 120) || ' minutes')::interval
         ELSE NULL END,
    o.create_date,
    o.write_date
FROM sale_order o;

-- =============================================================================
-- 8. stock_quant  (one row per product x physical warehouse)
-- =============================================================================
\echo '>> [8/8] stock_quant ...'
INSERT INTO stock_quant
    (product_id, warehouse_id, quantity, reserved_quantity, create_date, write_date)
SELECT
    pp.id,
    w.id,
    qh.q,
    round((qh.q * random() * 0.3)::numeric, 3),        -- up to 30% of on-hand reserved
    now() - (floor(random() * :history_days) || ' days')::interval,
    now() - (floor(random() * 30) || ' days')::interval
FROM product_product pp
JOIN stock_warehouse w ON w.warehouse_type <> 'online'
-- Correlated (references pp.id) so on-hand qty varies per (product, warehouse).
CROSS JOIN LATERAL (SELECT floor(random() * 500)::numeric AS q, pp.id AS _p) qh;

-- =============================================================================
-- Refresh planner statistics after bulk load.
-- =============================================================================
\echo '>> ANALYZE ...'
ANALYZE res_partner, product_template, product_product, sale_order,
        sale_order_line, account_payment, stock_quant;

\echo '>> Data generation complete.'
