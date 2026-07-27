CREATE TABLE IF NOT EXISTS nour_bronze.cities
(
    id UInt32,
    muhafaza_id UInt32,
    name String,
    name_ar String,
    create_date DateTime64(3),
    write_date DateTime64(3)
)
ENGINE = MergeTree
ORDER BY id;