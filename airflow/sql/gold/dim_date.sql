CREATE TABLE IF NOT EXISTS nour_gold.dim_date
(
    date_key UInt32,
    full_date Date,
    year UInt16,
    quarter UInt8,
    month UInt8,
    month_name String,
    day UInt8,
    day_of_week UInt8,
    day_name String,
    is_weekend Bool
)
ENGINE = MergeTree
ORDER BY date_key;