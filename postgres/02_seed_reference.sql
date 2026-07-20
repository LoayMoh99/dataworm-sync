-- =============================================================================
-- REFERENCE / LOOKUP SEED DATA (Odoo-inspired)
-- =============================================================================
-- Small, mostly-static dimensions seeded deterministically:
--   res_country, res_country_state, product_category (2-level tree with
--   complete_name), stock_warehouse (physical + online per country).
-- Idempotent (safe to re-run) via ON CONFLICT.
--
-- Run:  psql -v ON_ERROR_STOP=1 -f 02_seed_reference.sql
-- =============================================================================

BEGIN;

-- -----------------------------------------------------------------------------
-- Countries
-- -----------------------------------------------------------------------------
INSERT INTO res_country (name, code) VALUES
    ('United States', 'US'), ('Canada', 'CA'), ('United Kingdom', 'GB'),
    ('Germany', 'DE'), ('Spain', 'ES'), ('Sweden', 'SE'),
    ('United Arab Emirates', 'AE'), ('Egypt', 'EG'), ('Japan', 'JP'),
    ('India', 'IN'), ('Australia', 'AU'), ('Brazil', 'BR')
ON CONFLICT (code) DO NOTHING;

-- -----------------------------------------------------------------------------
-- States / regions (child of country)
-- -----------------------------------------------------------------------------
INSERT INTO res_country_state (country_id, name, code)
SELECT c.id, s.name, s.code
FROM (VALUES
    ('US','California','CA'), ('US','Texas','TX'), ('US','New York','NY'), ('US','Illinois','IL'),
    ('CA','Ontario','ON'), ('CA','Quebec','QC'),
    ('GB','England','ENG'), ('GB','Scotland','SCT'),
    ('DE','Bavaria','BY'), ('DE','Berlin','BE'),
    ('ES','Madrid','MD'), ('ES','Catalonia','CT'),
    ('SE','Stockholm','ST'),
    ('AE','Dubai','DXB'),
    ('EG','Cairo','C'),
    ('JP','Tokyo','13'), ('JP','Osaka','27'),
    ('IN','Maharashtra','MH'), ('IN','Karnataka','KA'),
    ('AU','New South Wales','NSW'), ('AU','Victoria','VIC'),
    ('BR','Sao Paulo','SP'), ('BR','Rio de Janeiro','RJ')
) AS s(ccode, name, code)
JOIN res_country c ON c.code = s.ccode
ON CONFLICT (country_id, name) DO NOTHING;

-- -----------------------------------------------------------------------------
-- Product category tree (parents, then children with complete_name)
-- -----------------------------------------------------------------------------
INSERT INTO product_category (name, complete_name) VALUES
    ('Electronics','Electronics'), ('Home & Kitchen','Home & Kitchen'),
    ('Apparel','Apparel'), ('Sports & Outdoors','Sports & Outdoors'),
    ('Beauty & Health','Beauty & Health'), ('Toys & Games','Toys & Games'),
    ('Grocery','Grocery'), ('Office','Office')
ON CONFLICT (complete_name) DO NOTHING;

INSERT INTO product_category (name, parent_id, complete_name)
SELECT child, p.id, p.name || ' / ' || child
FROM (VALUES
    ('Smartphones','Electronics'),      ('Laptops','Electronics'),
    ('Audio','Electronics'),            ('Cameras','Electronics'),
    ('Cookware','Home & Kitchen'),      ('Furniture','Home & Kitchen'),
    ('Small Appliances','Home & Kitchen'),
    ('Menswear','Apparel'),             ('Womenswear','Apparel'),
    ('Footwear','Apparel'),
    ('Fitness Equipment','Sports & Outdoors'), ('Camping','Sports & Outdoors'),
    ('Skincare','Beauty & Health'),     ('Supplements','Beauty & Health'),
    ('Board Games','Toys & Games'),     ('Action Figures','Toys & Games'),
    ('Snacks','Grocery'),               ('Beverages','Grocery'),
    ('Stationery','Office'),            ('Printers','Office')
) AS t(child, parent)
JOIN product_category p ON p.complete_name = parent   -- parents have no '/'
ON CONFLICT (complete_name) DO NOTHING;

-- -----------------------------------------------------------------------------
-- Warehouses: 3 physical + 1 online per country, anchored to the country's
-- first state.
-- -----------------------------------------------------------------------------
INSERT INTO stock_warehouse (name, code, state_id, warehouse_type)
SELECT
    c.name || ' ' || w.label,
    c.code || '-' || w.suffix,
    (SELECT id FROM res_country_state s WHERE s.country_id = c.id ORDER BY id LIMIT 1),
    w.wtype
FROM res_country c
CROSS JOIN (VALUES
    ('Flagship WH','FLG','flagship'),
    ('Standard WH','STD','standard'),
    ('Outlet WH','OUT','outlet'),
    ('Online WH','ONL','online')
) AS w(label, suffix, wtype)
ON CONFLICT (code) DO NOTHING;

COMMIT;

\echo 'Reference data seeded (countries, states, categories, warehouses).'
