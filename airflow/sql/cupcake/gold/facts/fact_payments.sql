-- fact_payments — grain: one account_payment. Enables AR / collections analysis
-- (payments rarely sum to the order total). date_key uses payment_date, falling
-- back to create_date when the payment has not been dated.
CREATE DATABASE IF NOT EXISTS cupcakeGold;

CREATE TABLE IF NOT EXISTS cupcakeGold.fact_payments (
    payment_key     Int64,
    payment_name    String,
    order_id        Int64,
    customer_key    Int64,
    date_key        Int32,
    amount          Decimal(18, 4),
    payment_type    String,
    journal         String,
    payment_method  String,
    payment_state   String
) ENGINE = MergeTree
ORDER BY (date_key, customer_key, payment_key);

TRUNCATE TABLE cupcakeGold.fact_payments;

INSERT INTO cupcakeGold.fact_payments
SELECT
    ap.id                                                       AS payment_key,
    ap.name                                                     AS payment_name,
    ap.sale_order_id                                            AS order_id,
    ap.partner_id                                               AS customer_key,
    toInt32(toYYYYMMDD(coalesce(ap.payment_date, ap.create_date))) AS date_key,
    ap.amount                                                   AS amount,
    ap.payment_type                                             AS payment_type,
    ap.journal                                                  AS journal,
    ap.payment_method                                           AS payment_method,
    ap.state                                                    AS payment_state
FROM (SELECT * FROM cupcakeSilver.account_payment FINAL) AS ap;
