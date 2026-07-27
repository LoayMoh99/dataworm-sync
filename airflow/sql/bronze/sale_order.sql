CREATE TABLE IF NOT EXISTS nour_bronze.sale_order
(
    id UInt64,
    name String,
    partner_id UInt64,
    location_id UInt32,
    date_order DateTime64(3),
    state String,
    amount_untaxed Decimal(14,2),
    amount_tax Decimal(14,2),
    amount_total Decimal(14,2),
    create_date DateTime64(3),
    write_date DateTime64(3)
)
ENGINE = MergeTree
ORDER BY id;