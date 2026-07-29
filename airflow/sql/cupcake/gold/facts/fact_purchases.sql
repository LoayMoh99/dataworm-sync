-- fact_purchases — grain: one purchase_order_line. vendor_key joins dim_vendor.
CREATE DATABASE IF NOT EXISTS cupcakeGold;

CREATE TABLE IF NOT EXISTS cupcakeGold.fact_purchases (
    purchase_line_key  Int64,
    order_id           Int64,
    order_name         String,
    date_key           Int32,
    vendor_key         Int64,
    product_key        Int64,
    location_key       Nullable(Int32),
    order_state        String,
    quantity           Decimal(18, 4),
    unit_cost          Decimal(18, 4),
    amount_untaxed     Decimal(18, 4),
    tax_amount         Decimal(18, 4),
    amount_total       Decimal(18, 4)
) ENGINE = MergeTree
ORDER BY (date_key, vendor_key, purchase_line_key);

TRUNCATE TABLE cupcakeGold.fact_purchases;

INSERT INTO cupcakeGold.fact_purchases
SELECT
    pol.id                              AS purchase_line_key,
    po.id                               AS order_id,
    po.name                             AS order_name,
    toInt32(toYYYYMMDD(po.date_order))  AS date_key,
    po.partner_id                       AS vendor_key,
    pol.product_id                      AS product_key,
    po.location_id                      AS location_key,
    po.state                            AS order_state,
    pol.product_qty                     AS quantity,
    pol.price_unit                      AS unit_cost,
    pol.price_subtotal                  AS amount_untaxed,
    pol.price_total - pol.price_subtotal AS tax_amount,
    pol.price_total                     AS amount_total
FROM (SELECT * FROM cupcakeSilver.purchase_order_line FINAL) AS pol
INNER JOIN (SELECT * FROM cupcakeSilver.purchase_order FINAL) AS po
    ON pol.order_id = po.id;
