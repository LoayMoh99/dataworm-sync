CREATE TABLE IF NOT EXISTS nour_bronze.sale_order_line
(
    id UInt64,
    order_id UInt64,
    product_id UInt64,
    product_uom_qty Decimal(12,3),
    price_unit Decimal(12,2),
    discount Decimal(5,2),
    price_subtotal Decimal(14,2),
    price_total Decimal(14,2),
    create_date DateTime64(3),
    write_date DateTime64(3)
)
ENGINE = MergeTree
ORDER BY id;