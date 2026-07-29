-- dim_product — one row per sellable variant, with template + category rolled in.
CREATE DATABASE IF NOT EXISTS cupcakeGold;

CREATE TABLE IF NOT EXISTS cupcakeGold.dim_product (
    product_key         Int64,
    variant_code        String,
    barcode             Nullable(String),
    variant_name        String,
    color               Nullable(String),
    size                Nullable(String),
    template_id         Int64,
    template_name       String,
    product_type        String,
    list_price          Decimal(18, 4),
    standard_price      Decimal(18, 4),
    variant_list_price  Decimal(18, 4),
    category_name       String,
    category_path       String,
    parent_category     String
) ENGINE = MergeTree
ORDER BY product_key;

TRUNCATE TABLE cupcakeGold.dim_product;

INSERT INTO cupcakeGold.dim_product
SELECT
    pp.id                            AS product_key,
    pp.default_code                  AS variant_code,
    pp.barcode                       AS barcode,
    pp.name                          AS variant_name,
    pp.color                         AS color,
    pp.size                          AS size,
    pt.id                            AS template_id,
    pt.name                          AS template_name,
    pt.type                          AS product_type,
    pt.list_price                    AS list_price,
    pt.standard_price                AS standard_price,
    pt.list_price + pp.price_extra   AS variant_list_price,
    cat.name                         AS category_name,
    cat.complete_name                AS category_path,
    parent.name                      AS parent_category
FROM (SELECT * FROM cupcakeSilver.product_product FINAL) AS pp
LEFT JOIN (SELECT * FROM cupcakeSilver.product_template FINAL) AS pt
    ON pp.product_tmpl_id = pt.id
LEFT JOIN (SELECT id, name, parent_id, complete_name FROM cupcakeSilver.product_category FINAL) AS cat
    ON pt.categ_id = cat.id
LEFT JOIN (SELECT id, name FROM cupcakeSilver.product_category FINAL) AS parent
    ON cat.parent_id = parent.id;
