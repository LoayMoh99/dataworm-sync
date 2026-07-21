-- =============================================================================
-- POST-SEED VERIFICATION / SUMMARY (Odoo-inspired, Egypt edition)
-- =============================================================================
-- Row counts, distributions, and integrity spot-checks. Run after
-- 03_generate_data.sql. NOTE: payments intentionally do NOT reconcile to order
-- totals here (open balances are part of the realistic data).
-- =============================================================================

\echo '=== Row counts ==='
SELECT 'muhafazat'            AS table_name, count(*) FROM muhafazat
UNION ALL SELECT 'cities',              count(*) FROM cities
UNION ALL SELECT 'product_category',    count(*) FROM product_category
UNION ALL SELECT 'stock_location',      count(*) FROM stock_location
UNION ALL SELECT 'res_partner',         count(*) FROM res_partner
UNION ALL SELECT 'product_template',    count(*) FROM product_template
UNION ALL SELECT 'product_product',     count(*) FROM product_product
UNION ALL SELECT 'product_supplierinfo',count(*) FROM product_supplierinfo
UNION ALL SELECT 'sale_order',          count(*) FROM sale_order
UNION ALL SELECT 'sale_order_line',     count(*) FROM sale_order_line
UNION ALL SELECT 'account_payment',     count(*) FROM account_payment
UNION ALL SELECT 'purchase_order',      count(*) FROM purchase_order
UNION ALL SELECT 'purchase_order_line', count(*) FROM purchase_order_line
UNION ALL SELECT 'stock_quant',         count(*) FROM stock_quant
ORDER BY table_name;

\echo '=== Partners: customers vs vendors ==='
SELECT
    count(*) FILTER (WHERE partner_type = 'customer') AS customers,
    count(*) FILTER (WHERE partner_type = 'vendor')   AS vendors,
    count(*) FILTER (WHERE active)                     AS active_partners
FROM res_partner;

\echo '=== Variants per template (product_product fan-out) ==='
SELECT min(v) AS min_variants, round(avg(v), 2) AS avg_variants, max(v) AS max_variants
FROM (SELECT product_tmpl_id, count(*) v FROM product_product GROUP BY product_tmpl_id) s;

\echo '=== Vendors per product (supplierinfo) ==='
SELECT min(v) AS min_vendors, round(avg(v), 2) AS avg_vendors, max(v) AS max_vendors
FROM (SELECT product_id, count(*) v FROM product_supplierinfo GROUP BY product_id) s;

\echo '=== Order time span (for incremental ETL demos) ==='
SELECT min(date_order) AS earliest_order,
       max(date_order) AS latest_order,
       max(date_order) - min(date_order) AS span
FROM sale_order;

\echo '=== Sale order state distribution ==='
SELECT state, count(*),
       round(100.0 * count(*) / sum(count(*)) OVER (), 1) AS pct
FROM sale_order GROUP BY state ORDER BY count(*) DESC;

\echo '=== Purchase order state distribution ==='
SELECT state, count(*),
       round(100.0 * count(*) / sum(count(*)) OVER (), 1) AS pct
FROM purchase_order GROUP BY state ORDER BY count(*) DESC;

\echo '=== Payment coverage of orders (paid / partial / unpaid) ==='
SELECT
    CASE
        WHEN p.paid IS NULL OR p.paid = 0        THEN 'unpaid'
        WHEN p.paid >= so.amount_total - 0.01     THEN 'paid_full'
        ELSE 'partial'
    END AS payment_status,
    count(*),
    round(100.0 * count(*) / sum(count(*)) OVER (), 1) AS pct
FROM sale_order so
LEFT JOIN (SELECT sale_order_id, sum(amount) AS paid FROM account_payment GROUP BY sale_order_id) p
       ON p.sale_order_id = so.id
GROUP BY 1 ORDER BY count(*) DESC;

\echo '=== Top 10 governorates by customer count ==='
SELECT m.name AS governorate, count(*) AS customers
FROM res_partner rp
JOIN muhafazat m ON m.id = rp.muhafaza_id
WHERE rp.partner_type = 'customer'
GROUP BY m.name ORDER BY customers DESC LIMIT 10;

\echo '=== Inventory position (stock_quant, standalone) ==='
SELECT
    count(*)                                             AS quant_rows,
    round(sum(quantity), 0)                              AS total_on_hand,
    round(sum(reserved_quantity), 0)                     AS total_reserved,
    round(sum(quantity - reserved_quantity), 0)          AS total_available
FROM stock_quant;

\echo '=== Top 5 governorates by inventory value (on-hand x cost) ==='
SELECT m.name AS governorate,
       round(sum(sq.quantity * pt.standard_price), 2) AS inventory_value
FROM stock_quant sq
JOIN stock_location sl ON sl.id = sq.location_id
JOIN muhafazat m       ON m.id = sl.muhafaza_id
JOIN product_product pp ON pp.id = sq.product_id
JOIN product_template pt ON pt.id = pp.product_tmpl_id
GROUP BY m.name ORDER BY inventory_value DESC LIMIT 5;

\echo '=== Line tax reconciliation: amount_total vs sum(line.price_total) (0 mismatches) ==='
SELECT count(*) AS mismatched_orders
FROM sale_order so
JOIN (SELECT order_id, sum(price_total) t FROM sale_order_line GROUP BY order_id) l
  ON l.order_id = so.id
WHERE so.amount_total <> round(l.t, 2);

\echo '=== Dirtiness sample (should be > 0 — this is intentional) ==='
SELECT
    (SELECT count(*) FROM res_partner WHERE email IS NULL)                       AS partners_null_email,
    (SELECT count(*) FROM res_partner WHERE phone IS NULL)                       AS partners_null_phone,
    (SELECT count(*) FROM res_partner WHERE city_id IS NULL)                     AS partners_null_city_id,
    (SELECT count(*) - count(DISTINCT lower(btrim(email))) FROM res_partner WHERE email IS NOT NULL) AS duplicate_emails,
    (SELECT count(*) FROM res_partner WHERE name <> btrim(name))                 AS names_with_padding;

\echo '=== Orphan check (should all be 0) ==='
SELECT
    (SELECT count(*) FROM sale_order o        LEFT JOIN res_partner c       ON c.id = o.partner_id   WHERE c.id IS NULL) AS sale_orders_without_partner,
    (SELECT count(*) FROM sale_order_line l    LEFT JOIN sale_order o        ON o.id = l.order_id     WHERE o.id IS NULL) AS sale_lines_without_order,
    (SELECT count(*) FROM sale_order_line l    LEFT JOIN product_product pp  ON pp.id = l.product_id  WHERE pp.id IS NULL) AS sale_lines_without_product,
    (SELECT count(*) FROM purchase_order o     LEFT JOIN res_partner v       ON v.id = o.partner_id   WHERE v.id IS NULL) AS purchase_orders_without_vendor,
    (SELECT count(*) FROM purchase_order_line l LEFT JOIN purchase_order o    ON o.id = l.order_id     WHERE o.id IS NULL) AS purchase_lines_without_order;
