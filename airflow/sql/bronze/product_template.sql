CREATE TABLE IF NOT EXISTS nour_bronze.product_template
(
    id UInt64,
    name String,
    categ_id UInt32,
    default_code String,
    list_price Decimal(12,2),
    standard_price Decimal(12,2),
    type String,
    active Bool,
    create_date DateTime64(3),
    write_date DateTime64(3)
)
ENGINE = MergeTree
ORDER BY id;