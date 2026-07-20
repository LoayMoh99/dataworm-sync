-- =============================================================================
-- POST-SEED VERIFICATION / SUMMARY (Odoo-inspired)
-- =============================================================================
-- Row counts, integrity spot-checks, and the time span of the generated data.
-- Run after 03_generate_data.sql.
-- =============================================================================

\echo '=== Row counts ==='
SELECT 'res_country'        AS table_name, count(*) FROM res_country
UNION ALL SELECT 'res_country_state', count(*) FROM res_country_state
UNION ALL SELECT 'product_category',  count(*) FROM product_category
UNION ALL SELECT 'stock_warehouse',   count(*) FROM stock_warehouse
UNION ALL SELECT 'res_partner',       count(*) FROM res_partner
UNION ALL SELECT 'product_template',  count(*) FROM product_template
UNION ALL SELECT 'product_product',   count(*) FROM product_product
UNION ALL SELECT 'sale_order',        count(*) FROM sale_order
UNION ALL SELECT 'sale_order_line',   count(*) FROM sale_order_line
UNION ALL SELECT 'account_payment',   count(*) FROM account_payment
UNION ALL SELECT 'stock_quant',       count(*) FROM stock_quant
ORDER BY table_name;

\echo '=== Order time span (for incremental ETL demos) ==='
SELECT min(date_order) AS earliest_order,
       max(date_order) AS latest_order,
       max(date_order) - min(date_order) AS span
FROM sale_order;

\echo '=== Order state distribution ==='
SELECT state, count(*),
       round(100.0 * count(*) / sum(count(*)) OVER (), 1) AS pct
FROM sale_order GROUP BY state ORDER BY count(*) DESC;

\echo '=== amount_total vs sum(line.price_total) reconciliation (0 mismatches) ==='
SELECT count(*) AS mismatched_orders
FROM sale_order so
JOIN (SELECT order_id, sum(price_total) t FROM sale_order_line GROUP BY order_id) l
  ON l.order_id = so.id
WHERE so.amount_total <> round(l.t, 2);

\echo '=== payment.amount vs order.amount_total reconciliation (0 mismatches) ==='
SELECT count(*) AS mismatched_payments
FROM account_payment p
JOIN sale_order so ON so.id = p.sale_order_id
WHERE p.amount <> so.amount_total;

\echo '=== Orphan check (should all be 0) ==='
SELECT
    (SELECT count(*) FROM sale_order o      LEFT JOIN res_partner c      ON c.id = o.partner_id  WHERE c.id IS NULL) AS orders_without_partner,
    (SELECT count(*) FROM sale_order_line l LEFT JOIN sale_order o       ON o.id = l.order_id    WHERE o.id IS NULL) AS lines_without_order,
    (SELECT count(*) FROM sale_order_line l LEFT JOIN product_product pp ON pp.id = l.product_id WHERE pp.id IS NULL) AS lines_without_product;
