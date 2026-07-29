Truncate table nour_silver.customers;

INSERT INTO nour_silver.customers
SELECT
    p.id AS customer_id,
    p.name AS customer_name,
    p.email,
    p.phone,
    p.street,
    c.name AS city_name,
    m.name AS muhafaza_name,
    p.is_company,
    p.partner_type,
    p.segment,
    p.active
FROM nour_bronze.res_partner AS p
LEFT JOIN nour_bronze.cities AS c ON p.city_id = c.id
LEFT JOIN nour_bronze.muhafazat AS m ON p.muhafaza_id = m.id
WHERE p.active = true;