CREATE TABLE IF NOT EXISTS nour_silver.sales
(
    sale_line_id UInt64,
    order_id UInt64,
    customer_id UInt64,
    location_id UInt32,
    date_order DateTime64(3),
    order_state String,
    product_id UInt64,
    product_uom_qty Decimal(12,3),
    price_unit Decimal(12,2),
    discount Decimal(5,2),
    price_subtotal Decimal(14,2),
    price_total Decimal(14,2)
)
ENGINE = MergeTree
ORDER BY sale_line_id;