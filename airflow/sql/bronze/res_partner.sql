CREATE TABLE IF NOT EXISTS nour_bronze.res_partner
(
    id UInt64,
    name String,
    email String null,
    phone String null,
    street String null,
    city String null,
    city_id UInt32 null,
    muhafaza_id UInt32 null,
    is_company Bool ,
    partner_type String null,
    segment String null,
    active Bool,
    create_date DateTime64(3) null,
    write_date DateTime64(3) null
)
ENGINE = MergeTree
ORDER BY id