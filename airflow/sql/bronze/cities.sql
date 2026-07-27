CREATE TABLE IF NOT EXISTS nour_bronze.cities
(
    id UInt32,
    muhafaza_id UInt32,
    name String null,
    name_ar String null,
    create_date DateTime64(3) null,
    write_date DateTime64(3) null
)
ENGINE = MergeTree
ORDER BY id;