CREATE TABLE IF NOT EXISTS nour_bronze.muhafazat
(
    id UInt32,
    name String,
    name_ar String null,
    code String null,
    create_date DateTime64(3) null,
    write_date DateTime64(3) null
)
ENGINE = MergeTree
ORDER BY id;