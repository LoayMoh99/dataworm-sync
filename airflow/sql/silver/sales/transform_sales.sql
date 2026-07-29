INSERT INTO nour_silver.sales
SELECT
    sol.id AS sale_line_id,
    so.id AS order_id,
    so.partner_id AS customer_id,
    so.location_id,
    so.date_order,
    so.state AS order_state,
    sol.product_id,
    sol.product_uom_qty,
    sol.price_unit,
    sol.discount,
    sol.price_subtotal,
    sol.price_total
FROM nour_bronze.sale_order_line AS sol
INNER JOIN nour_bronze.sale_order AS so ON sol.order_id = so.id;