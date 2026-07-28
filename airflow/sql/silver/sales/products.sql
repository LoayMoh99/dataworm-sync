CREATE TABLE IF NOT EXISTS nour_silver.products
(
    product_id UInt64,
    product_name String,
    default_code String,
    barcode String,
    color String,
    size String,
    category_name String,
    list_price Decimal(12,2),
    standard_price Decimal(12,2),
    product_type String,
    active Bool
)
ENGINE = MergeTree
ORDER BY product_id;