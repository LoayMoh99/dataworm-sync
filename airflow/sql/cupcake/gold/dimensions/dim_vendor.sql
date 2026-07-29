-- dim_vendor — one row per vendor partner (SCD-1 overwrite).
CREATE DATABASE IF NOT EXISTS cupcakeGold;

CREATE TABLE IF NOT EXISTS cupcakeGold.dim_vendor (
    vendor_key        Int64,
    vendor_name       String,
    email             Nullable(String),
    phone             Nullable(String),
    is_company        Bool,
    city              String,
    governorate       String,
    governorate_ar    String,
    governorate_code  String
) ENGINE = MergeTree
ORDER BY vendor_key;

TRUNCATE TABLE cupcakeGold.dim_vendor;

INSERT INTO cupcakeGold.dim_vendor
SELECT
    p.id                                     AS vendor_key,
    p.name                                   AS vendor_name,
    p.email                                  AS email,
    p.phone                                  AS phone,
    p.is_company                             AS is_company,
    coalesce(nullIf(c.name, ''), p.city, '') AS city,
    m.name                                   AS governorate,
    m.name_ar                                AS governorate_ar,
    m.code                                   AS governorate_code
FROM (SELECT * FROM cupcakeSilver.res_partner FINAL WHERE partner_type = 'vendor') AS p
LEFT JOIN (SELECT id, name FROM cupcakeSilver.cities FINAL) AS c
    ON p.city_id = c.id
LEFT JOIN (SELECT id, name, name_ar, code FROM cupcakeSilver.muhafazat FINAL) AS m
    ON p.muhafaza_id = m.id;
