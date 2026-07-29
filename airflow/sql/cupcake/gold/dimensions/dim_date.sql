-- dim_date — generated calendar (2015-2035). Egypt weekend = Friday/Saturday.
CREATE DATABASE IF NOT EXISTS cupcakeGold;

CREATE TABLE IF NOT EXISTS cupcakeGold.dim_date (
    date_key    Int32,
    date        Date,
    day         UInt8,
    month       UInt8,
    quarter     UInt8,
    year        UInt16,
    day_of_week UInt8,
    day_name    String,
    month_name  String,
    is_weekend  UInt8
) ENGINE = MergeTree
ORDER BY date_key;

TRUNCATE TABLE cupcakeGold.dim_date;

INSERT INTO cupcakeGold.dim_date
SELECT
    toInt32(toYYYYMMDD(d))        AS date_key,
    d                             AS date,
    toDayOfMonth(d)               AS day,
    toMonth(d)                    AS month,
    toQuarter(d)                  AS quarter,
    toYear(d)                     AS year,
    toDayOfWeek(d)                AS day_of_week,
    formatDateTime(d, '%A')       AS day_name,
    formatDateTime(d, '%B')       AS month_name,
    toDayOfWeek(d) IN (5, 6)      AS is_weekend
FROM (
    SELECT toDate('2015-01-01') + number AS d
    FROM numbers(toUInt32(toDate('2035-12-31') - toDate('2015-01-01') + 1))
);
