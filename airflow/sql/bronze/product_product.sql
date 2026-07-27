CREATE TABLE IF NOT EXISTS nour_bronze.product_product
(
    id UInt64,
    product_tmpl_id UInt64,
    default_code String,
    barcode String,
    name String,
    color String,
    size String,
    price_extra Decimal(12,2),
    active Bool,
    create_date DateTime64(3),
    write_date DateTime64(3)
)
ENGINE = MergeTree
ORDER BY id;