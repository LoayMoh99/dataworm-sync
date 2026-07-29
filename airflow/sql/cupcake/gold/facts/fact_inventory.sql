-- fact_inventory — grain: one stock_quant (current on-hand snapshot per variant
-- and location). available = on_hand - reserved; value at standard cost.
CREATE DATABASE IF NOT EXISTS cupcakeGold;

CREATE TABLE IF NOT EXISTS cupcakeGold.fact_inventory (
    quant_key        Int64,
    product_key      Int64,
    location_key     Int32,
    on_hand_qty      Decimal(18, 4),
    reserved_qty     Decimal(18, 4),
    available_qty    Decimal(18, 4),
    inventory_value  Decimal(18, 4)
) ENGINE = MergeTree
ORDER BY (location_key, product_key, quant_key);

TRUNCATE TABLE cupcakeGold.fact_inventory;

INSERT INTO cupcakeGold.fact_inventory
SELECT
    sq.id                                AS quant_key,
    sq.product_id                        AS product_key,
    sq.location_id                       AS location_key,
    sq.quantity                          AS on_hand_qty,
    sq.reserved_quantity                 AS reserved_qty,
    sq.quantity - sq.reserved_quantity   AS available_qty,
    sq.quantity * pt.standard_price      AS inventory_value
FROM (SELECT * FROM cupcakeSilver.stock_quant FINAL) AS sq
LEFT JOIN (SELECT id, product_tmpl_id FROM cupcakeSilver.product_product FINAL) AS pp
    ON sq.product_id = pp.id
LEFT JOIN (SELECT id, standard_price FROM cupcakeSilver.product_template FINAL) AS pt
    ON pp.product_tmpl_id = pt.id;
