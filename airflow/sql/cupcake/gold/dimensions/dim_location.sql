-- dim_location — one row per physical stock location.
CREATE DATABASE IF NOT EXISTS cupcakeGold;

CREATE TABLE IF NOT EXISTS cupcakeGold.dim_location (
    location_key    Int32,
    location_code   String,
    location_name   String,
    location_type   String,
    city            String,
    governorate     String,
    governorate_ar  String
) ENGINE = MergeTree
ORDER BY location_key;

TRUNCATE TABLE cupcakeGold.dim_location;

INSERT INTO cupcakeGold.dim_location
SELECT
    l.id             AS location_key,
    l.code           AS location_code,
    l.name           AS location_name,
    l.location_type  AS location_type,
    c.name           AS city,
    m.name           AS governorate,
    m.name_ar        AS governorate_ar
FROM (SELECT * FROM cupcakeSilver.stock_location FINAL) AS l
LEFT JOIN (SELECT id, name FROM cupcakeSilver.cities FINAL) AS c
    ON l.city_id = c.id
LEFT JOIN (SELECT id, name, name_ar FROM cupcakeSilver.muhafazat FINAL) AS m
    ON l.muhafaza_id = m.id;
