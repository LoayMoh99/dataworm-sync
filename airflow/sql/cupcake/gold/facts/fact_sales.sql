-- fact_sales — grain: one sale_order_line. Additive measures; keys are natural
-- business ids that join to dim_customer/dim_product/dim_location/dim_date.
CREATE DATABASE IF NOT EXISTS cupcakeGold;

CREATE TABLE IF NOT EXISTS cupcakeGold.fact_sales (
    sale_line_key   Int64,
    order_id        Int64,
    order_name      String,
    date_key        Int32,
    customer_key    Int64,
    product_key     Int64,
    location_key    Int32,
    order_state     String,
    quantity        Decimal(18, 4),
    unit_price      Decimal(18, 4),
    discount_pct    Decimal(9, 4),
    amount_untaxed  Decimal(18, 4),
    tax_amount      Decimal(18, 4),
    amount_total    Decimal(18, 4)
) ENGINE = MergeTree
ORDER BY (date_key, customer_key, sale_line_key);

TRUNCATE TABLE cupcakeGold.fact_sales;

INSERT INTO cupcakeGold.fact_sales
SELECT
    sol.id                              AS sale_line_key,
    so.id                               AS order_id,
    so.name                             AS order_name,
    toInt32(toYYYYMMDD(so.date_order))  AS date_key,
    so.partner_id                       AS customer_key,
    sol.product_id                      AS product_key,
    so.location_id                      AS location_key,
    so.state                            AS order_state,
    sol.product_uom_qty                 AS quantity,
    sol.price_unit                      AS unit_price,
    sol.discount                        AS discount_pct,
    sol.price_subtotal                  AS amount_untaxed,
    sol.price_total - sol.price_subtotal AS tax_amount,
    sol.price_total                     AS amount_total
FROM (SELECT * FROM cupcakeSilver.sale_order_line FINAL) AS sol
INNER JOIN (SELECT * FROM cupcakeSilver.sale_order FINAL) AS so
    ON sol.order_id = so.id;
