CREATE TABLE IF NOT EXISTS nour_bronze.product_category
(
    id UInt32,
    name String,
    parent_id UInt32,
    complete_name String null,
    create_date DateTime64(3) null,
    write_date DateTime64(3) null
)
ENGINE = MergeTree
ORDER BY id;