CREATE TABLE IF NOT EXISTS nour_bronze.stock_location
(
    id UInt32,
    name String,
    code String null,
    location_type String null,
    muhafaza_id UInt32 null,
    city_id UInt32 null,
    create_date DateTime64(3) null,
    write_date DateTime64(3) null
)
ENGINE = MergeTree
ORDER BY id;