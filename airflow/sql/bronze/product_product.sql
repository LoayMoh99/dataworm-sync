CREATE TABLE IF NOT EXISTS nour_bronze.product_product
(
    id UInt64,
    product_tmpl_id UInt64,
    default_code String null,
    barcode String null,
    name String null,
    color String null,
    size String null,
    price_extra Decimal(12,2) null,
    active Bool null,
    create_date DateTime64(3) null,
    write_date DateTime64(3) null
)
ENGINE = MergeTree
ORDER BY id;