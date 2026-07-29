CREATE TABLE IF NOT EXISTS nour_silver.locations
(
    location_id UInt32,
    location_name String,
    location_code String,
    location_type String,
    city_name String,
    muhafaza_name String
)
ENGINE = MergeTree
ORDER BY location_id;