r"""Silver table specs: one entry per source table in ``public``.

Each column is ``(clickhouse_name, clickhouse_type, postgres_select_expr)``.
The Postgres expression is where cleaning happens (pushed down to the source),
so the Silver mirror stores already-typed, already-cleaned values. For most
tables the expr is just the column name; ``res_partner`` — the intentionally
"dirty" table — gets real cleaning (trim/case names, normalise emails/phones,
tidy free-text city).

``order_by`` is the ReplacingMergeTree sort key (the natural PK). Every table
carries ``write_date`` — the incremental cursor.
"""

# Money -> Decimal(18,4); ids -> Int32/Int64 by source width; text -> String or
# Nullable(String); timestamps -> DateTime64(3,'UTC'); flags -> Bool.
_DT = "DateTime64(3, 'UTC')"
_MONEY = "Decimal(18, 4)"

# Reusable cleaning fragments for res_partner (Postgres ARE regex).
_CLEAN_NAME = r"initcap(btrim(regexp_replace(name, '\s+', ' ', 'g')))"
_CLEAN_EMAIL = r"NULLIF(lower(btrim(email)), '')"
_CLEAN_CITY = r"NULLIF(lower(btrim(city)), '')"
# Normalise phones to canonical +20XXXXXXXXXX; NULL if unrecognisable.
_CLEAN_PHONE = r"""
CASE
    WHEN regexp_replace(coalesce(phone, ''), '\D', '', 'g') = '' THEN NULL
    WHEN regexp_replace(phone, '\D', '', 'g') ~ '^20' AND length(regexp_replace(phone, '\D', '', 'g')) = 12
        THEN '+' || regexp_replace(phone, '\D', '', 'g')
    WHEN regexp_replace(phone, '\D', '', 'g') ~ '^0'  AND length(regexp_replace(phone, '\D', '', 'g')) = 11
        THEN '+20' || substr(regexp_replace(phone, '\D', '', 'g'), 2)
    WHEN regexp_replace(phone, '\D', '', 'g') ~ '^1'  AND length(regexp_replace(phone, '\D', '', 'g')) = 10
        THEN '+20' || regexp_replace(phone, '\D', '', 'g')
    ELSE NULL
END
""".strip()


SILVER_TABLES = [
    {
        "name": "muhafazat",
        "order_by": "id",
        "columns": [
            ("id", "Int32", "id"),
            ("name", "String", "name"),
            ("name_ar", "String", "name_ar"),
            ("code", "String", "code"),
            ("create_date", _DT, "create_date"),
            ("write_date", _DT, "write_date"),
        ],
    },
    {
        "name": "cities",
        "order_by": "id",
        "columns": [
            ("id", "Int32", "id"),
            ("muhafaza_id", "Int32", "muhafaza_id"),
            ("name", "String", "name"),
            ("name_ar", "Nullable(String)", "name_ar"),
            ("create_date", _DT, "create_date"),
            ("write_date", _DT, "write_date"),
        ],
    },
    {
        "name": "res_partner",
        "order_by": "id",
        "columns": [
            ("id", "Int64", "id"),
            ("name", "String", _CLEAN_NAME),
            ("email", "Nullable(String)", _CLEAN_EMAIL),
            ("phone", "Nullable(String)", _CLEAN_PHONE),
            ("street", "Nullable(String)", "NULLIF(btrim(street), '')"),
            ("city", "Nullable(String)", _CLEAN_CITY),
            ("city_id", "Nullable(Int32)", "city_id"),
            ("muhafaza_id", "Int32", "muhafaza_id"),
            ("is_company", "Bool", "is_company"),
            ("partner_type", "String", "partner_type"),
            ("segment", "Nullable(String)", "segment"),
            ("active", "Bool", "active"),
            ("create_date", _DT, "create_date"),
            ("write_date", _DT, "write_date"),
        ],
    },
    {
        "name": "product_category",
        "order_by": "id",
        "columns": [
            ("id", "Int32", "id"),
            ("name", "String", "name"),
            ("parent_id", "Nullable(Int32)", "parent_id"),
            ("complete_name", "String", "complete_name"),
            ("create_date", _DT, "create_date"),
            ("write_date", _DT, "write_date"),
        ],
    },
    {
        "name": "product_template",
        "order_by": "id",
        "columns": [
            ("id", "Int64", "id"),
            ("name", "String", "name"),
            ("categ_id", "Int32", "categ_id"),
            ("default_code", "String", "default_code"),
            ("list_price", _MONEY, "list_price"),
            ("standard_price", _MONEY, "standard_price"),
            ("type", "String", "type"),
            ("active", "Bool", "active"),
            ("create_date", _DT, "create_date"),
            ("write_date", _DT, "write_date"),
        ],
    },
    {
        "name": "product_product",
        "order_by": "id",
        "columns": [
            ("id", "Int64", "id"),
            ("product_tmpl_id", "Int64", "product_tmpl_id"),
            ("default_code", "String", "default_code"),
            ("barcode", "Nullable(String)", "barcode"),
            ("name", "String", "name"),
            ("color", "Nullable(String)", "color"),
            ("size", "Nullable(String)", "size"),
            ("price_extra", _MONEY, "price_extra"),
            ("active", "Bool", "active"),
            ("create_date", _DT, "create_date"),
            ("write_date", _DT, "write_date"),
        ],
    },
    {
        "name": "product_supplierinfo",
        "order_by": "id",
        "columns": [
            ("id", "Int64", "id"),
            ("product_id", "Int64", "product_id"),
            ("partner_id", "Int64", "partner_id"),
            ("price", _MONEY, "price"),
            ("min_qty", _MONEY, "min_qty"),
            ("delay", "Int32", "delay"),
            ("create_date", _DT, "create_date"),
            ("write_date", _DT, "write_date"),
        ],
    },
    {
        "name": "stock_location",
        "order_by": "id",
        "columns": [
            ("id", "Int32", "id"),
            ("name", "String", "name"),
            ("code", "String", "code"),
            ("location_type", "String", "location_type"),
            ("muhafaza_id", "Nullable(Int32)", "muhafaza_id"),
            ("city_id", "Nullable(Int32)", "city_id"),
            ("create_date", _DT, "create_date"),
            ("write_date", _DT, "write_date"),
        ],
    },
    {
        "name": "stock_quant",
        "order_by": "id",
        "columns": [
            ("id", "Int64", "id"),
            ("product_id", "Int64", "product_id"),
            ("location_id", "Int32", "location_id"),
            ("quantity", _MONEY, "quantity"),
            ("reserved_quantity", _MONEY, "reserved_quantity"),
            ("create_date", _DT, "create_date"),
            ("write_date", _DT, "write_date"),
        ],
    },
    {
        "name": "sale_order",
        "order_by": "id",
        "columns": [
            ("id", "Int64", "id"),
            ("name", "String", "name"),
            ("partner_id", "Int64", "partner_id"),
            ("location_id", "Int32", "location_id"),
            ("date_order", _DT, "date_order"),
            ("state", "String", "state"),
            ("amount_untaxed", _MONEY, "amount_untaxed"),
            ("amount_tax", _MONEY, "amount_tax"),
            ("amount_total", _MONEY, "amount_total"),
            ("create_date", _DT, "create_date"),
            ("write_date", _DT, "write_date"),
        ],
    },
    {
        "name": "sale_order_line",
        "order_by": "id",
        "columns": [
            ("id", "Int64", "id"),
            ("order_id", "Int64", "order_id"),
            ("product_id", "Int64", "product_id"),
            ("product_uom_qty", _MONEY, "product_uom_qty"),
            ("price_unit", _MONEY, "price_unit"),
            ("discount", "Decimal(9, 4)", "discount"),
            ("price_subtotal", _MONEY, "price_subtotal"),
            ("price_total", _MONEY, "price_total"),
            ("create_date", _DT, "create_date"),
            ("write_date", _DT, "write_date"),
        ],
    },
    {
        "name": "account_payment",
        "order_by": "id",
        "columns": [
            ("id", "Int64", "id"),
            ("name", "String", "name"),
            ("partner_id", "Int64", "partner_id"),
            ("sale_order_id", "Int64", "sale_order_id"),
            ("amount", _MONEY, "amount"),
            ("payment_type", "String", "payment_type"),
            ("partner_type", "String", "partner_type"),
            ("journal", "String", "journal"),
            ("payment_method", "String", "payment_method"),
            ("state", "String", "state"),
            ("payment_date", "Nullable(DateTime64(3, 'UTC'))", "payment_date"),
            ("create_date", _DT, "create_date"),
            ("write_date", _DT, "write_date"),
        ],
    },
    {
        "name": "purchase_order",
        "order_by": "id",
        "columns": [
            ("id", "Int64", "id"),
            ("name", "String", "name"),
            ("partner_id", "Int64", "partner_id"),
            ("location_id", "Nullable(Int32)", "location_id"),
            ("date_order", _DT, "date_order"),
            ("state", "String", "state"),
            ("amount_untaxed", _MONEY, "amount_untaxed"),
            ("amount_tax", _MONEY, "amount_tax"),
            ("amount_total", _MONEY, "amount_total"),
            ("create_date", _DT, "create_date"),
            ("write_date", _DT, "write_date"),
        ],
    },
    {
        "name": "purchase_order_line",
        "order_by": "id",
        "columns": [
            ("id", "Int64", "id"),
            ("order_id", "Int64", "order_id"),
            ("product_id", "Int64", "product_id"),
            ("product_qty", _MONEY, "product_qty"),
            ("price_unit", _MONEY, "price_unit"),
            ("price_subtotal", _MONEY, "price_subtotal"),
            ("price_total", _MONEY, "price_total"),
            ("create_date", _DT, "create_date"),
            ("write_date", _DT, "write_date"),
        ],
    },
]

SILVER_TABLES_BY_NAME = {t["name"]: t for t in SILVER_TABLES}
