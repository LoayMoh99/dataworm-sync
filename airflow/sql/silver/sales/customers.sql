CREATE TABLE IF NOT EXISTS nour_silver.customers
(
    customer_id UInt64,
    customer_name String,
    email String,
    phone String,
    street String,
    city_name String,
    muhafaza_name String,
    is_company Bool,
    partner_type String,
    segment String,
    active Bool
)
ENGINE = MergeTree
ORDER BY customer_id;