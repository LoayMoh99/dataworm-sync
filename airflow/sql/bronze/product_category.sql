CREATE TABLE IF NOT EXISTS nour_bronze.product_category
(
    id UInt32,
    name String,
    parent_id UInt32,
    complete_name String,
    create_date DateTime64(3),
    write_date DateTime64(3)
)
ENGINE = MergeTree
ORDER BY id;