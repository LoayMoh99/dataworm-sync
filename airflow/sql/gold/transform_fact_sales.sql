INSERT INTO nour_gold.FactSales
SELECT
    sale_line_id,
    order_id,
    customer_id,
    product_id,
    location_id,
    toYYYYMMDD(date_order) AS date_key,
    order_state,
    product_uom_qty,
    price_unit,
    discount,
    price_subtotal,
    price_total
FROM nour_silver.sales;