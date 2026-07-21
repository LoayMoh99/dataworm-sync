-- =============================================================================
-- REFERENCE / LOOKUP SEED DATA (Odoo-inspired, Egypt edition)
-- =============================================================================
-- Small, mostly-static dimensions seeded deterministically:
--   muhafazat        Egypt's 27 governorates (English + Arabic + ISO code)
--   cities           cities per governorate (one governorate -> many cities)
--   product_category 2-level tree with complete_name
--   stock_location   flat physical locations (warehouse / store / transit)
-- Idempotent (safe to re-run) via ON CONFLICT.
--
-- Run:  psql -v ON_ERROR_STOP=1 -f 02_seed_reference.sql
-- =============================================================================

BEGIN;

-- -----------------------------------------------------------------------------
-- Governorates (muhafazat) — all 27, with ISO 3166-2 codes
-- -----------------------------------------------------------------------------
INSERT INTO muhafazat (name, name_ar, code) VALUES
    ('Cairo',          'القاهرة',        'EG-C'),
    ('Giza',           'الجيزة',         'EG-GZ'),
    ('Alexandria',     'الإسكندرية',     'EG-ALX'),
    ('Dakahlia',       'الدقهلية',       'EG-DK'),
    ('Red Sea',        'البحر الأحمر',   'EG-BA'),
    ('Beheira',        'البحيرة',        'EG-BH'),
    ('Fayoum',         'الفيوم',         'EG-FYM'),
    ('Gharbia',        'الغربية',        'EG-GH'),
    ('Ismailia',       'الإسماعيلية',    'EG-IS'),
    ('Menofia',        'المنوفية',       'EG-MNF'),
    ('Minya',          'المنيا',         'EG-MN'),
    ('Qaliubiya',      'القليوبية',      'EG-KB'),
    ('New Valley',     'الوادي الجديد',  'EG-WAD'),
    ('Suez',           'السويس',         'EG-SUZ'),
    ('Aswan',          'أسوان',          'EG-ASN'),
    ('Assiut',         'أسيوط',          'EG-AST'),
    ('Beni Suef',      'بني سويف',       'EG-BNS'),
    ('Port Said',      'بورسعيد',        'EG-PTS'),
    ('Damietta',       'دمياط',          'EG-DT'),
    ('Sharkia',        'الشرقية',        'EG-SHR'),
    ('South Sinai',    'جنوب سيناء',     'EG-JS'),
    ('Kafr El Sheikh', 'كفر الشيخ',      'EG-KFS'),
    ('Matrouh',        'مطروح',          'EG-MT'),
    ('Luxor',          'الأقصر',         'EG-LX'),
    ('Qena',           'قنا',            'EG-KN'),
    ('North Sinai',    'شمال سيناء',     'EG-SIN'),
    ('Sohag',          'سوهاج',          'EG-SHG')
ON CONFLICT (code) DO NOTHING;

-- -----------------------------------------------------------------------------
-- Cities (child of governorate). Joined to muhafazat by governorate code.
-- -----------------------------------------------------------------------------
INSERT INTO cities (muhafaza_id, name, name_ar)
SELECT m.id, c.name, c.name_ar
FROM (VALUES
    -- Cairo
    ('EG-C','Nasr City','مدينة نصر'), ('EG-C','Maadi','المعادي'),
    ('EG-C','Heliopolis','مصر الجديدة'), ('EG-C','New Cairo','القاهرة الجديدة'),
    ('EG-C','Shubra','شبرا'), ('EG-C','Helwan','حلوان'), ('EG-C','Zamalek','الزمالك'),
    -- Giza
    ('EG-GZ','Giza','الجيزة'), ('EG-GZ','6th of October','السادس من أكتوبر'),
    ('EG-GZ','Sheikh Zayed','الشيخ زايد'), ('EG-GZ','Dokki','الدقي'),
    ('EG-GZ','Haram','الهرم'), ('EG-GZ','Imbaba','إمبابة'),
    -- Alexandria
    ('EG-ALX','Montaza','المنتزه'), ('EG-ALX','Sidi Gaber','سيدي جابر'),
    ('EG-ALX','Borg El Arab','برج العرب'), ('EG-ALX','Miami','ميامي'),
    ('EG-ALX','Smouha','سموحة'), ('EG-ALX','Agami','العجمي'),
    -- Dakahlia
    ('EG-DK','Mansoura','المنصورة'), ('EG-DK','Talkha','طلخا'),
    ('EG-DK','Mit Ghamr','ميت غمر'), ('EG-DK','Belqas','بلقاس'), ('EG-DK','Aga','أجا'),
    -- Red Sea
    ('EG-BA','Hurghada','الغردقة'), ('EG-BA','Safaga','سفاجا'),
    ('EG-BA','El Gouna','الجونة'), ('EG-BA','Marsa Alam','مرسى علم'),
    ('EG-BA','Ras Ghareb','رأس غارب'),
    -- Beheira
    ('EG-BH','Damanhour','دمنهور'), ('EG-BH','Kafr El Dawwar','كفر الدوار'),
    ('EG-BH','Rashid','رشيد'), ('EG-BH','Edku','إدكو'),
    -- Fayoum
    ('EG-FYM','Fayoum','الفيوم'), ('EG-FYM','Sinnuris','سنورس'),
    ('EG-FYM','Ibsheway','إبشواي'), ('EG-FYM','Tamiya','طامية'),
    -- Gharbia
    ('EG-GH','Tanta','طنطا'), ('EG-GH','El Mahalla El Kubra','المحلة الكبرى'),
    ('EG-GH','Kafr El Zayat','كفر الزيات'), ('EG-GH','Zefta','زفتى'),
    ('EG-GH','Samannoud','سمنود'),
    -- Ismailia
    ('EG-IS','Ismailia','الإسماعيلية'), ('EG-IS','Fayed','فايد'),
    ('EG-IS','Qantara','القنطرة'), ('EG-IS','Abu Suwir','أبو صوير'),
    -- Menofia
    ('EG-MNF','Shibin El Kom','شبين الكوم'), ('EG-MNF','Menouf','منوف'),
    ('EG-MNF','Sadat City','مدينة السادات'), ('EG-MNF','Ashmoun','أشمون'),
    ('EG-MNF','Quesna','قويسنا'),
    -- Minya
    ('EG-MN','Minya','المنيا'), ('EG-MN','Mallawi','ملوي'),
    ('EG-MN','Beni Mazar','بني مزار'), ('EG-MN','Samalut','سمالوط'),
    ('EG-MN','Maghagha','مغاغة'),
    -- Qaliubiya
    ('EG-KB','Banha','بنها'), ('EG-KB','Qalyub','قليوب'),
    ('EG-KB','Shubra El Kheima','شبرا الخيمة'), ('EG-KB','Khanka','الخانكة'),
    ('EG-KB','Toukh','طوخ'), ('EG-KB','Obour','العبور'),
    -- New Valley
    ('EG-WAD','Kharga','الخارجة'), ('EG-WAD','Dakhla','الداخلة'),
    ('EG-WAD','Farafra','الفرافرة'), ('EG-WAD','Paris','باريس'),
    -- Suez
    ('EG-SUZ','Suez','السويس'), ('EG-SUZ','Ain Sokhna','العين السخنة'),
    ('EG-SUZ','Ataqa','عتاقة'),
    -- Aswan
    ('EG-ASN','Aswan','أسوان'), ('EG-ASN','Kom Ombo','كوم أمبو'),
    ('EG-ASN','Edfu','إدفو'), ('EG-ASN','Daraw','دراو'),
    ('EG-ASN','Abu Simbel','أبو سمبل'),
    -- Assiut
    ('EG-AST','Assiut','أسيوط'), ('EG-AST','Dairut','ديروط'),
    ('EG-AST','Manfalut','منفلوط'), ('EG-AST','Abnub','أبنوب'),
    ('EG-AST','El Qusiya','القوصية'),
    -- Beni Suef
    ('EG-BNS','Beni Suef','بني سويف'), ('EG-BNS','El Wasta','الواسطى'),
    ('EG-BNS','Nasser','ناصر'), ('EG-BNS','Beba','ببا'), ('EG-BNS','Ihnasia','إهناسيا'),
    -- Port Said
    ('EG-PTS','Port Said','بورسعيد'), ('EG-PTS','Port Fouad','بورفؤاد'),
    -- Damietta
    ('EG-DT','Damietta','دمياط'), ('EG-DT','New Damietta','دمياط الجديدة'),
    ('EG-DT','Ras El Bar','رأس البر'), ('EG-DT','Faraskur','فارسكور'),
    ('EG-DT','Kafr Saad','كفر سعد'),
    -- Sharkia
    ('EG-SHR','Zagazig','الزقازيق'), ('EG-SHR','10th of Ramadan','العاشر من رمضان'),
    ('EG-SHR','Belbeis','بلبيس'), ('EG-SHR','Minya El Qamh','منيا القمح'),
    ('EG-SHR','Abu Hammad','أبو حماد'), ('EG-SHR','Faqous','فاقوس'),
    -- South Sinai
    ('EG-JS','Sharm El Sheikh','شرم الشيخ'), ('EG-JS','Dahab','دهب'),
    ('EG-JS','Nuweiba','نويبع'), ('EG-JS','Saint Catherine','سانت كاترين'),
    ('EG-JS','El Tor','الطور'),
    -- Kafr El Sheikh
    ('EG-KFS','Kafr El Sheikh','كفر الشيخ'), ('EG-KFS','Desouk','دسوق'),
    ('EG-KFS','Baltim','بلطيم'), ('EG-KFS','Fuwwah','فوه'),
    ('EG-KFS','Sidi Salem','سيدي سالم'),
    -- Matrouh
    ('EG-MT','Marsa Matrouh','مرسى مطروح'), ('EG-MT','El Alamein','العلمين'),
    ('EG-MT','Siwa','سيوة'), ('EG-MT','El Dabaa','الضبعة'),
    -- Luxor
    ('EG-LX','Luxor','الأقصر'), ('EG-LX','Esna','إسنا'),
    ('EG-LX','Armant','أرمنت'), ('EG-LX','El Bayadiya','البياضية'),
    -- Qena
    ('EG-KN','Qena','قنا'), ('EG-KN','Nag Hammadi','نجع حمادي'),
    ('EG-KN','Qus','قوص'), ('EG-KN','Dishna','دشنا'), ('EG-KN','Farshut','فرشوط'),
    -- North Sinai
    ('EG-SIN','Arish','العريش'), ('EG-SIN','Sheikh Zuwaid','الشيخ زويد'),
    ('EG-SIN','Bir al-Abd','بئر العبد'), ('EG-SIN','Rafah','رفح'),
    -- Sohag
    ('EG-SHG','Sohag','سوهاج'), ('EG-SHG','Akhmim','أخميم'),
    ('EG-SHG','Girga','جرجا'), ('EG-SHG','Tahta','طهطا'), ('EG-SHG','El Balyana','البلينا')
) AS c(mcode, name, name_ar)
JOIN muhafazat m ON m.code = c.mcode
ON CONFLICT (muhafaza_id, name) DO NOTHING;

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
-- Stock locations — a flat set across several governorates. city_id is resolved
-- from the seeded cities (NULL for the transit hub).
-- -----------------------------------------------------------------------------
INSERT INTO stock_location (name, code, location_type, muhafaza_id, city_id)
SELECT
    l.name, l.code, l.ltype, m.id,
    (SELECT c.id FROM cities c WHERE c.muhafaza_id = m.id AND c.name = l.city_name)
FROM (VALUES
    ('Cairo Central Warehouse','WH-CAI-01','warehouse','EG-C','Nasr City'),
    ('Cairo Downtown Store',    'ST-CAI-01','store',    'EG-C','Heliopolis'),
    ('New Cairo Store',         'ST-CAI-02','store',    'EG-C','New Cairo'),
    ('Central Transit Hub',     'TR-CAI-01','transit',  'EG-C', NULL),
    ('Giza Distribution Center','WH-GZ-01', 'warehouse','EG-GZ','6th of October'),
    ('October Store',           'ST-GZ-01', 'store',    'EG-GZ','Sheikh Zayed'),
    ('Alexandria Warehouse',    'WH-ALX-01','warehouse','EG-ALX','Smouha'),
    ('Alexandria Store',        'ST-ALX-01','store',    'EG-ALX','Miami'),
    ('Mansoura Store',          'ST-DK-01', 'store',    'EG-DK','Mansoura'),
    ('Tanta Store',             'ST-GH-01', 'store',    'EG-GH','Tanta'),
    ('Zagazig Warehouse',       'WH-SHR-01','warehouse','EG-SHR','Zagazig'),
    ('Assiut Store',            'ST-AST-01','store',    'EG-AST','Assiut'),
    ('Luxor Store',             'ST-LX-01', 'store',    'EG-LX','Luxor'),
    ('Hurghada Store',          'ST-BA-01', 'store',    'EG-BA','Hurghada')
) AS l(name, code, ltype, mcode, city_name)
JOIN muhafazat m ON m.code = l.mcode
ON CONFLICT (code) DO NOTHING;

COMMIT;

\echo 'Reference data seeded (27 governorates, cities, categories, stock locations).'
