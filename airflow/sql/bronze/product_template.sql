CREATE TABLE IF NOT EXISTS nour_bronze.product_template
(
    id UInt64,
    name String,
    categ_id UInt32 null,
    default_code String null,
    list_price Decimal(12,2) null,
    standard_price Decimal(12,2) null,
    type String null,
    active Bool null,
    create_date DateTime64(3) null,
    write_date DateTime64(3) null
)
ENGINE = MergeTree
ORDER BY id;