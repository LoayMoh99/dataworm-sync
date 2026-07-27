CREATE TABLE IF NOT EXISTS nour_bronze.res_partner
(
    id UInt64,
    name String,
    email String null,
    phone String,
    street String,
    city String,
    city_id UInt32,
    muhafaza_id UInt32,
    is_company Bool,
    partner_type String,
    segment String,
    active Bool,
    create_date DateTime64(3),
    write_date DateTime64(3)
)
ENGINE = MergeTree
ORDER BY id;