Truncate table nour_silver.locations;

INSERT INTO nour_silver.locations
SELECT
    l.id AS location_id,
    l.name AS location_name,
    l.code AS location_code,
    l.location_type,
    c.name AS city_name,
    m.name AS muhafaza_name
FROM nour_bronze.stock_location AS l
LEFT JOIN nour_bronze.cities AS c ON l.city_id = c.id
LEFT JOIN nour_bronze.muhafazat AS m ON l.muhafaza_id = m.id;