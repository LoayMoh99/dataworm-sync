CREATE TABLE IF NOT EXISTS nour_gold.FactSales
(
    sale_line_id UInt64,
    order_id UInt64,
    customer_id UInt64,
    product_id UInt64,
    location_id UInt32,
    date_key UInt32,
    order_state String,
    product_uom_qty Decimal(12,3),
    price_unit Decimal(12,2),
    discount Decimal(5,2),
    price_subtotal Decimal(14,2),
    price_total Decimal(14,2)
)
ENGINE = MergeTree
ORDER BY (date_key, sale_line_id);