CREATE TABLE IF NOT EXISTS nour_bronze.stock_location
(
    id UInt32,
    name String,
    code String,
    location_type String,
    muhafaza_id UInt32,
    city_id UInt32,
    create_date DateTime64(3),
    write_date DateTime64(3)
)
ENGINE = MergeTree
ORDER BY id;