CREATE TABLE IF NOT EXISTS nour_bronze.muhafazat
(
    id UInt32,
    name String,
    name_ar String,
    code String,
    create_date DateTime64(3),
    write_date DateTime64(3)
)
ENGINE = MergeTree
ORDER BY id;