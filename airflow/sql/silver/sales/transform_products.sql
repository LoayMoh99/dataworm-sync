INSERT INTO nour_silver.products
SELECT
    pp.id AS product_id,
    pt.name AS product_name,
    pp.default_code,
    pp.barcode,
    pp.color,
    pp.size,
    pc.name AS category_name,
    pt.list_price,
    pt.standard_price,
    pt.type AS product_type,
    pp.active
FROM nour_bronze.product_product AS pp
LEFT JOIN nour_bronze.product_template AS pt ON pp.product_tmpl_id = pt.id
LEFT JOIN nour_bronze.product_category AS pc ON pt.categ_id = pc.id
WHERE pp.active = true;