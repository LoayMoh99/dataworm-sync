-- =============================================================================
-- CONFIGURABLE DATA GENERATOR (Odoo-inspired, Egypt edition)
-- =============================================================================
-- Generates realistic, referentially-consistent volumes into the public schema.
-- Set-based (INSERT ... SELECT over generate_series) so it scales to millions
-- of rows. Timestamps are recency-weighted so the ETL layer can demonstrate
-- incremental loads on `write_date`.
--
-- This data is intentionally *dirty* (see the DIRTINESS notes below) so the
-- Silver cleaning layer has real work to do: inconsistent casing/whitespace,
-- mixed phone formats, null contacts, free-text `city` that disagrees with
-- `city_id`, and duplicate/near-duplicate customers.
--
-- Configure with -v flags (all optional; defaults shown):
--   psql -v ON_ERROR_STOP=1 \
--        -v n_customers=100000 \
--        -v n_vendors=2000 \
--        -v n_products=20000 \
--        -v n_orders=10000000 \
--        -v n_purchase_orders=1000000 \
--        -v quants_per_product=10 \
--        -v history_days=730 \
--        -v tax_rate=0.15 \
--        -v seed=0.42 \
--        -f 03_generate_data.sql
--
-- Tip: start small (n_orders=20000) to validate, then scale up.
-- =============================================================================

\timing on

-- ---- Defaults for any value not supplied on the command line ----------------
\if :{?n_customers}       \else \set n_customers 100000  \endif
\if :{?n_vendors}         \else \set n_vendors 2000      \endif
\if :{?n_products}        \else \set n_products 20000    \endif
\if :{?n_orders}          \else \set n_orders 10000000   \endif
\if :{?n_purchase_orders} \else \set n_purchase_orders 1000000 \endif
\if :{?quants_per_product}\else \set quants_per_product 10   \endif
\if :{?history_days}      \else \set history_days 730     \endif
\if :{?tax_rate}          \else \set tax_rate 0.15        \endif
\if :{?seed}              \else \set seed 0.42            \endif

\echo '>> Generating:' :n_customers 'customers,' :n_vendors 'vendors,' :n_products 'products,' :n_orders 'sale orders,' :n_purchase_orders 'purchase orders'
\echo '>> History window:' :history_days 'days   Tax:' :tax_rate '  Seed:' :seed

-- Reproducible pseudo-randomness for this session.
SELECT setseed(:seed);

-- Pull live cardinalities of the reference tables into psql variables.
SELECT count(*) AS n_muhafazat  FROM muhafazat        \gset
SELECT count(*) AS n_cities     FROM cities           \gset
SELECT count(*) AS n_categories FROM product_category \gset
SELECT count(*) AS n_locations  FROM stock_location   \gset
\echo '>> Reference sizes:' :n_muhafazat 'governorates,' :n_cities 'cities,' :n_categories 'categories,' :n_locations 'stock locations'

-- =============================================================================
-- 1. res_partner — CUSTOMERS  (ids 1 .. n_customers)
-- =============================================================================
-- DIRTINESS: name casing/whitespace noise; some null / uppercased / space-
-- padded / duplicate emails; mixed phone formats + ~15% null; free-text `city`
-- that often disagrees with `city_id`; ~20% null city_id (governorate only).
\echo '>> [1/13] res_partner (customers) ...'
INSERT INTO res_partner
    (name, email, phone, street, city, city_id, muhafaza_id, is_company,
     partner_type, segment, active, create_date, write_date)
SELECT
    -- name with realistic casing/whitespace noise
    CASE (i % 7)
        WHEN 0 THEN upper(nm.fn || ' ' || nm.ln)
        WHEN 1 THEN lower(nm.fn || ' ' || nm.ln)
        WHEN 2 THEN '  ' || nm.fn || ' ' || nm.ln || '  '
        WHEN 3 THEN nm.fn || '  ' || nm.ln
        ELSE nm.fn || ' ' || nm.ln
    END,
    -- email: null / uppercased / space-padded / duplicate (no numeric suffix)
    CASE
        WHEN random() < 0.08 THEN NULL
        WHEN random() < 0.20 THEN upper(em.addr)
        WHEN random() < 0.30 THEN ' ' || em.addr
        ELSE em.addr
    END,
    ph.num,
    (1 + (i % 200)) || ' ' ||
        (ARRAY['Tahrir','El Nasr','Ramses','El Gomhoreya','El Haram','Corniche',
               'Makram Ebeid','El Thawra','Salah Salem','El Merghany'])[1 + (i % 10)] || ' St',
    -- free-text city: matches / lowercased / uppercased / typo'd / null
    CASE
        WHEN random() < 0.10 THEN NULL
        WHEN random() < 0.35 THEN lower(ci.name)
        WHEN random() < 0.50 THEN upper(ci.name)
        WHEN random() < 0.62 THEN ci.name || ' '
        ELSE ci.name
    END,
    CASE WHEN random() < 0.20 THEN NULL ELSE ci.id END,     -- ~20% only know governorate
    ci.muhafaza_id,
    random() < 0.15,                                        -- ~15% are companies
    'customer',
    (ARRAY['consumer','consumer','consumer','small_business','enterprise'])[1 + floor(random() * 5)::int],
    random() > 0.08,                                        -- ~8% archived/inactive
    now() - (floor(random() * (:history_days * 0.8)) || ' days')::interval,
    now() - (floor(random() * :history_days) || ' days')::interval
FROM generate_series(1, :n_customers) AS g(i)
CROSS JOIN LATERAL (
    SELECT
        (ARRAY['Mohamed','Ahmed','Mahmoud','Mostafa','Omar','Ali','Hassan','Khaled',
               'Youssef','Amr','Mona','Fatma','Aya','Sara','Nour','Heba',
               'Doaa','Yasmin','Salma','Nada'])[1 + (i * 13) % 20]           AS fn,
        (ARRAY['Hassan','Ali','Ibrahim','Mahmoud','Abdelrahman','Mohamed','Saad','Farouk',
               'ElSayed','Mansour','Khalil','Salem','Fahmy','Zaki','Nassar','Habib',
               'Sabry','Rashad','Fawzy','Gaber'])[1 + (i * 29) % 20]         AS ln
) nm
-- email address built from the name (sometimes without the numeric suffix so
-- duplicate emails occur across same-name partners).
CROSS JOIN LATERAL (
    SELECT lower(nm.fn || '.' || nm.ln)
           || CASE WHEN random() < 0.10 THEN '' ELSE i::text END
           || '@'
           || (ARRAY['gmail.com','yahoo.com','hotmail.com','outlook.com'])[1 + (i % 4)] AS addr
) em
-- Egyptian-style phone with several formats and ~15% missing. The inner
-- subquery references `i` so it stays CORRELATED (else random() freezes once
-- for the whole insert and every partner gets the same phone).
CROSS JOIN LATERAL (
    SELECT
        CASE
            WHEN random() < 0.15 THEN NULL
            WHEN random() < 0.55 THEN '01' || d.op || d.s
            WHEN random() < 0.80 THEN '+20 1' || d.op || ' ' || left(d.s, 4) || ' ' || right(d.s, 4)
            ELSE '01' || d.op || '-' || left(d.s, 4) || '-' || right(d.s, 4)
        END AS num
    FROM (
        SELECT
            (ARRAY['0','1','2','5'])[1 + floor(random() * 4)::int]    AS op,
            lpad((floor(random() * 100000000))::bigint::text, 8, '0') AS s,
            i AS _i
    ) d
) ph
-- Pick one random city per customer, then derive its governorate.
CROSS JOIN LATERAL (SELECT g.i AS _i, 1 + floor(random() * :n_cities)::int AS cid) pick
JOIN cities ci ON ci.id = pick.cid;

-- =============================================================================
-- 2. res_partner — VENDORS  (ids n_customers+1 .. n_customers+n_vendors)
-- =============================================================================
\echo '>> [2/13] res_partner (vendors) ...'
INSERT INTO res_partner
    (name, email, phone, street, city, city_id, muhafaza_id, is_company,
     partner_type, segment, active, create_date, write_date)
SELECT
    (ARRAY['Nile','Delta','Cairo','Alex','Giza','Pyramid','Sphinx','Sahara',
           'Horus','Pharaoh','Sinai','Luxor','Aswan','Mediterranean','Oasis'])[1 + (i * 7) % 15]
        || ' ' ||
    (ARRAY['Trading','Imports','Distribution','Wholesale','Supplies','Group',
           'Logistics','Commercial','Enterprises','Co.'])[1 + (i * 11) % 10]
        || ' ' || i,
    'info@vendor' || i || '.' ||
        (ARRAY['com','net','com.eg'])[1 + (i % 3)],
    '02-' || lpad(((i * 7919) % 100000000)::text, 8, '0'),   -- Cairo-style landline
    (1 + (i % 100)) || ' Industrial Zone',
    ci.name,
    ci.id,
    ci.muhafaza_id,
    TRUE,                                                    -- vendors are companies
    'vendor',
    NULL,                                                    -- segment is a customer concept
    random() > 0.03,                                         -- ~3% inactive
    now() - (floor(random() * :history_days) || ' days')::interval,
    now() - (floor(random() * :history_days) || ' days')::interval
FROM generate_series(1, :n_vendors) AS g(i)
CROSS JOIN LATERAL (SELECT g.i AS _i, 1 + floor(random() * :n_cities)::int AS cid) pick
JOIN cities ci ON ci.id = pick.cid;

-- =============================================================================
-- 3. product_template
-- =============================================================================
\echo '>> [3/13] product_template ...'
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
    round((price.p * (0.45 + random() * 0.3))::numeric, 2),      -- cost 45-75% of price (EGP)
    'product',
    random() > 0.05,                                             -- ~5% discontinued
    now() - (floor(random() * :history_days) || ' days')::interval,
    now() - (floor(random() * :history_days) || ' days')::interval
FROM generate_series(1, :n_products) AS g(i)
CROSS JOIN LATERAL (SELECT round((50 + random() * 19950)::numeric, 2) AS p, g.i AS _i) price;

-- =============================================================================
-- 4. product_product — MANY variants per template (1-5), color/size/price_extra
-- =============================================================================
-- product_product ids are contiguous from 1 (fresh table), which later steps
-- rely on for random variant selection.
\echo '>> [4/13] product_product (variants) ...'
INSERT INTO product_product
    (product_tmpl_id, default_code, barcode, name, color, size, price_extra, active, create_date, write_date)
SELECT
    t.id,
    'P' || lpad(t.id::text, 8, '0') || '-' || v.k,
    CASE WHEN random() < 0.05 THEN NULL                          -- ~5% missing barcode
         ELSE '620' || lpad((row_number() OVER ())::text, 10, '0') END,
    t.name
        || CASE WHEN attr.color IS NOT NULL THEN ' - ' || attr.color ELSE '' END
        || CASE WHEN attr.size  IS NOT NULL THEN ' / '  || attr.size  ELSE '' END,
    attr.color,
    attr.size,
    CASE WHEN random() < 0.5 THEN 0 ELSE round((random() * 500)::numeric, 2) END,
    t.active AND (random() > 0.03),                              -- a few variants archived
    t.create_date,
    t.write_date
FROM product_template t
-- 1-5 variants per template.
CROSS JOIN LATERAL (SELECT 1 + floor(random() * 5)::int AS n_var, t.id AS _t) c
CROSS JOIN LATERAL generate_series(1, c.n_var) AS v(k)
-- Per-variant attributes (some null so not every product is a "real" variant).
CROSS JOIN LATERAL (
    SELECT
        CASE WHEN random() < 0.85
             THEN (ARRAY['Black','White','Silver','Blue','Red','Green','Gold','Gray'])[1 + floor(random() * 8)::int]
             END AS color,
        CASE WHEN random() < 0.60
             THEN (ARRAY['S','M','L','XL','64GB','128GB','256GB','One Size'])[1 + floor(random() * 8)::int]
             END AS size,
        v.k AS _k
) attr;

-- =============================================================================
-- 5. product_supplierinfo — vendor pricelist (1-3 vendors per product)
-- =============================================================================
-- Vendor is chosen by a deterministic offset so the 1-3 vendors of a product
-- are always distinct (satisfies UNIQUE(product_id, partner_id)) without an
-- expensive DISTINCT. Vendor price ≈ product cost ± 15%.
\echo '>> [5/13] product_supplierinfo ...'
SELECT count(*) AS n_variants FROM product_product \gset
\echo '>>   variants generated:' :n_variants
INSERT INTO product_supplierinfo
    (product_id, partner_id, price, min_qty, delay, create_date, write_date)
SELECT
    pp.id,
    :n_customers + 1 + ((pp.id * 7 + v.k * 13) % :n_vendors),    -- distinct vendor per k
    round((pt.standard_price * (0.85 + random() * 0.30))::numeric, 2),
    (ARRAY[1,5,10,20,50])[1 + floor(random() * 5)::int],
    3 + floor(random() * 30)::int,                               -- lead time 3-32 days
    pp.create_date,
    pp.write_date
FROM product_product pp
JOIN product_template pt ON pt.id = pp.product_tmpl_id
CROSS JOIN LATERAL (SELECT 1 + floor(random() * 3)::int AS nv, pp.id AS _p) c
CROSS JOIN LATERAL generate_series(1, c.nv) AS v(k);

-- =============================================================================
-- 6. sale_order  (amounts filled in step 8, once lines exist)
-- =============================================================================
-- location picked first; state ≈ cancel 8% / draft 8% / sent 8% / sale 46% /
-- done 30%. date_order recency-weighted (random()^1.6) toward now.
\echo '>> [6/13] sale_order ... (largest step)'
INSERT INTO sale_order
    (name, partner_id, location_id, date_order, state, create_date, write_date)
SELECT
    'S' || lpad(i::text, 8, '0'),
    1 + floor(random() * :n_customers)::int,                     -- customers only
    r.loc,
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
CROSS JOIN LATERAL (
    SELECT g.i AS _i,
           (now() - (power(random(), 1.6) * :history_days) * INTERVAL '1 day') AS ord_ts,
           random()                                              AS st,
           (1 + floor(random() * :n_locations)::int)            AS loc
) r;

-- =============================================================================
-- 7. sale_order_line  (1-5 lines/order; price_unit = list_price + price_extra)
-- =============================================================================
\echo '>> [7/13] sale_order_line ...'
INSERT INTO sale_order_line
    (order_id, product_id, product_uom_qty, price_unit, discount,
     price_subtotal, price_total, create_date, write_date)
SELECT
    o.id,
    pp.id,
    li.qty,
    pt.list_price + pp.price_extra                                                    AS price_unit,
    li.disc,
    round((li.qty * (pt.list_price + pp.price_extra) * (1 - li.disc / 100))::numeric, 2)                   AS price_subtotal,
    round((li.qty * (pt.list_price + pp.price_extra) * (1 - li.disc / 100) * (1 + :tax_rate))::numeric, 2) AS price_total,
    o.create_date,
    o.write_date
FROM sale_order o
CROSS JOIN LATERAL (SELECT 1 + floor(random() * 5)::int AS n_items, o.id AS _oid) cnt
CROSS JOIN LATERAL generate_series(1, cnt.n_items) AS line(n)
CROSS JOIN LATERAL (
    SELECT line.n                                                    AS _n,
           (1 + floor(random() * :n_variants)::int)                  AS pid,     -- pick a variant
           (1 + floor(random() * 5)::int)                            AS qty,
           CASE WHEN random() < 0.25
                THEN round((random() * 30)::numeric, 2) ELSE 0 END   AS disc     -- percent
) li
JOIN product_product  pp ON pp.id = li.pid
JOIN product_template pt ON pt.id = pp.product_tmpl_id;

-- =============================================================================
-- 8. Roll sale_order_line totals up onto sale_order (Odoo computed amount_*)
-- =============================================================================
-- Disable the write_date trigger for the bulk UPDATE so the historical
-- write_date spread survives (else every order jumps to now()).
\echo '>> [8/13] sale_order amount_* rollup ...'
ALTER TABLE sale_order DISABLE TRIGGER trg_sale_order_write_date;
UPDATE sale_order so
SET amount_untaxed = agg.subtotal,
    amount_tax     = agg.total - agg.subtotal,
    amount_total   = agg.total
FROM (
    SELECT order_id, sum(price_subtotal) AS subtotal, sum(price_total) AS total
    FROM sale_order_line GROUP BY order_id
) agg
WHERE agg.order_id = so.id;
ALTER TABLE sale_order ENABLE TRIGGER trg_sale_order_write_date;

-- =============================================================================
-- 9. account_payment  (0..N per order: full / partial / unpaid)
-- =============================================================================
-- Payment behaviour by order state:
--   cancel        -> no payment
--   draft / sent  -> ~20% leave a small deposit (10-30%), rest unpaid
--   sale / done   -> ~55% paid in full, ~30% partial (1-2 installments, 30-90%),
--                    ~15% unpaid
-- => SUM(payments) usually != amount_total (realistic open balances).
\echo '>> [9/13] account_payment ...'
INSERT INTO account_payment
    (name, partner_id, sale_order_id, amount, payment_type, partner_type,
     journal, payment_method, state, payment_date, create_date, write_date)
SELECT
    'P' || lpad(o.id::text, 8, '0') || '-' || pay.k,
    o.partner_id,
    o.id,
    round((o.amount_total * sc.frac / sc.n_pay)::numeric, 2),
    'inbound',
    'customer',
    (ARRAY['bank','bank','bank','cash'])[1 + floor(random() * 4)::int],
    (ARRAY['manual','electronic'])[1 + floor(random() * 2)::int],
    sc.pay_state,
    CASE WHEN sc.pay_state = 'draft' THEN NULL
         ELSE o.date_order + (pay.k * (5 + floor(random() * 40)) || ' days')::interval END,
    o.create_date,
    o.write_date
FROM sale_order o
-- `o.id` keeps this CORRELATED so rr re-rolls per order (else it freezes once
-- and every order lands in the same payment bucket).
CROSS JOIN LATERAL (SELECT random() AS rr, o.id AS _oid) q
CROSS JOIN LATERAL (
    SELECT
        CASE
            WHEN o.state = 'cancel' THEN 0
            WHEN o.state IN ('draft','sent') THEN CASE WHEN random() < 0.20 THEN 1 ELSE 0 END
            WHEN q.rr < 0.55 THEN 1                                   -- full
            WHEN q.rr < 0.85 THEN 1 + floor(random() * 2)::int        -- partial: 1 or 2 installments
            ELSE 0                                                    -- unpaid
        END AS n_pay,
        CASE
            WHEN o.state IN ('draft','sent') THEN 0.10 + random() * 0.20   -- deposit
            WHEN q.rr < 0.55 THEN 1.0                                      -- full
            WHEN q.rr < 0.85 THEN 0.30 + random() * 0.60                   -- partial 30-90%
            ELSE 0
        END AS frac,
        CASE
            WHEN o.state IN ('draft','sent') THEN 'draft'
            WHEN o.state = 'done' AND q.rr < 0.55 THEN 'reconciled'
            ELSE 'posted'
        END AS pay_state
) sc
CROSS JOIN LATERAL generate_series(1, sc.n_pay) AS pay(k);

-- =============================================================================
-- 10. purchase_order  (amounts filled in step 12, once lines exist)
-- =============================================================================
-- state ≈ cancel 10% / draft 10% / sent 10% / purchase 45% / done 25%.
-- 'purchase' and 'done' are the completed ones.
\echo '>> [10/13] purchase_order ...'
INSERT INTO purchase_order
    (name, partner_id, location_id, date_order, state, create_date, write_date)
SELECT
    'PO' || lpad(i::text, 7, '0'),
    :n_customers + 1 + floor(random() * :n_vendors)::int,        -- vendors only
    r.loc,
    r.ord_ts,
    CASE
        WHEN r.st < 0.10 THEN 'cancel'
        WHEN r.st < 0.20 THEN 'draft'
        WHEN r.st < 0.30 THEN 'sent'
        WHEN r.st < 0.75 THEN 'purchase'
        ELSE 'done'
    END,
    r.ord_ts,
    r.ord_ts
FROM generate_series(1, :n_purchase_orders) AS g(i)
CROSS JOIN LATERAL (
    SELECT g.i AS _i,
           (now() - (power(random(), 1.5) * :history_days) * INTERVAL '1 day') AS ord_ts,
           random()                                              AS st,
           (1 + floor(random() * :n_locations)::int)            AS loc
) r;

-- =============================================================================
-- 11. purchase_order_line  (1-5 lines drawn from the vendor's pricelist)
-- =============================================================================
-- Lines only reference products the PO's vendor actually supplies
-- (product_supplierinfo), at that vendor's price. A vendor with no pricelist
-- entries yields a PO with no lines (amount stays 0) — that's fine.
\echo '>> [11/13] purchase_order_line ...'
INSERT INTO purchase_order_line
    (order_id, product_id, product_qty, price_unit, price_subtotal, price_total, create_date, write_date)
SELECT
    po.id,
    si.product_id,
    q.qty,
    si.price,
    round((q.qty * si.price)::numeric, 2),
    round((q.qty * si.price * (1 + :tax_rate))::numeric, 2),
    po.create_date,
    po.write_date
FROM purchase_order po
CROSS JOIN LATERAL (
    SELECT s.product_id, s.price
    FROM product_supplierinfo s
    WHERE s.partner_id = po.partner_id
    ORDER BY random()
    LIMIT (1 + floor(random() * 5)::int)
) si
CROSS JOIN LATERAL (SELECT (5 + floor(random() * 100))::numeric AS qty, si.product_id AS _p) q;

-- =============================================================================
-- 12. Roll purchase_order_line totals up onto purchase_order
-- =============================================================================
\echo '>> [12/13] purchase_order amount_* rollup ...'
ALTER TABLE purchase_order DISABLE TRIGGER trg_purchase_order_write_date;
UPDATE purchase_order po
SET amount_untaxed = agg.subtotal,
    amount_tax     = agg.total - agg.subtotal,
    amount_total   = agg.total
FROM (
    SELECT order_id, sum(price_subtotal) AS subtotal, sum(price_total) AS total
    FROM purchase_order_line GROUP BY order_id
) agg
WHERE agg.order_id = po.id;
ALTER TABLE purchase_order ENABLE TRIGGER trg_purchase_order_write_date;

-- =============================================================================
-- 13. stock_quant  (1..quants_per_product rows per variant; on-hand + reserved)
-- =============================================================================
-- No UNIQUE(product, location): a variant can have multiple quant rows in the
-- same location (Odoo behaviour = separate lots), so duplicates here are
-- expected, not a bug. Bump `quants_per_product` for more rows.
\echo '>> [13/13] stock_quant ...'
INSERT INTO stock_quant
    (product_id, location_id, quantity, reserved_quantity, create_date, write_date)
SELECT
    pp.id,
    1 + floor(random() * :n_locations)::int,
    qh.q,
    round((qh.q * random() * 0.3)::numeric, 3),        -- up to 30% of on-hand reserved
    now() - (floor(random() * :history_days) || ' days')::interval,
    now() - (floor(random() * 30) || ' days')::interval
FROM product_product pp
CROSS JOIN LATERAL (SELECT 1 + floor(random() * :quants_per_product)::int AS n_loc, pp.id AS _p) c
CROSS JOIN LATERAL generate_series(1, c.n_loc) AS g(k)
CROSS JOIN LATERAL (SELECT floor(random() * 500)::numeric AS q, g.k AS _k) qh;

-- =============================================================================
-- Refresh planner statistics after bulk load.
-- =============================================================================
\echo '>> ANALYZE ...'
ANALYZE muhafazat, cities, res_partner, product_template, product_product,
        product_supplierinfo, sale_order, sale_order_line, account_payment,
        purchase_order, purchase_order_line, stock_quant;

\echo '>> Data generation complete.'
