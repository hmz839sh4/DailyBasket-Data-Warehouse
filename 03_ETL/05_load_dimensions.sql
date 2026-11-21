-- Loads the 6 dimensions from the clean staging tables. Dimensions must be loaded before facts.
SET search_path = project_dw;

INSERT INTO dim_date
SELECT to_char(d, 'YYYYMMDD')::int,
       d::date,
       TRIM(to_char(d, 'Day')),
       EXTRACT(day FROM d)::int,
       EXTRACT(week FROM d)::int,
       EXTRACT(month FROM d)::int,
       TRIM(to_char(d, 'Month')),
       EXTRACT(quarter FROM d)::int,
       EXTRACT(year FROM d)::int,
       EXTRACT(isodow FROM d) IN (6, 7)
FROM generate_series('2024-01-01'::date, '2026-12-31'::date, interval '1 day') AS d
ON CONFLICT (date_key) DO NOTHING;

INSERT INTO dim_region (region_id, city, province, country, region_zone)
SELECT region_id, city, province, country, region_zone
FROM project_staging.stg_region_clean
ON CONFLICT (region_id) DO UPDATE
SET city = EXCLUDED.city, province = EXCLUDED.province,
    country = EXCLUDED.country, region_zone = EXCLUDED.region_zone;

INSERT INTO dim_channel (channel_id, channel_name, channel_type)
SELECT channel_id, channel_name, channel_type
FROM project_staging.stg_channel_clean
ON CONFLICT (channel_id) DO UPDATE
SET channel_name = EXCLUDED.channel_name, channel_type = EXCLUDED.channel_type;

INSERT INTO dim_customer (customer_id, customer_name, email, gender, age_group, customer_segment, signup_date)
SELECT customer_id, customer_name, email, gender, age_group, customer_segment, signup_date
FROM project_staging.stg_customer_clean
ON CONFLICT (customer_id) DO UPDATE
SET customer_name = EXCLUDED.customer_name, email = EXCLUDED.email, gender = EXCLUDED.gender,
    age_group = EXCLUDED.age_group, customer_segment = EXCLUDED.customer_segment,
    signup_date = EXCLUDED.signup_date;

INSERT INTO dim_product (product_id, product_name, brand, subcategory, category, unit_cost, list_price, is_active)
SELECT product_id, product_name, brand, subcategory, category, unit_cost, list_price, is_active
FROM project_staging.stg_product_clean
ON CONFLICT (product_id) DO UPDATE
SET product_name = EXCLUDED.product_name, brand = EXCLUDED.brand, subcategory = EXCLUDED.subcategory,
    category = EXCLUDED.category, unit_cost = EXCLUDED.unit_cost, list_price = EXCLUDED.list_price,
    is_active = EXCLUDED.is_active;

-- Row 0 = "No Promotion", so every sale can still have a valid promotion_key.
INSERT INTO dim_promotion (promotion_key, promotion_id, promotion_name, promotion_type, discount_percent)
VALUES (0, 'NONE', 'No Promotion', 'None', 0)
ON CONFLICT (promotion_id) DO NOTHING;

INSERT INTO dim_promotion (promotion_id, promotion_name, promotion_type, discount_percent, start_date, end_date)
SELECT promotion_id, promotion_name, promotion_type, discount_percent, start_date, end_date
FROM project_staging.stg_promotion_clean
ON CONFLICT (promotion_id) DO UPDATE
SET promotion_name = EXCLUDED.promotion_name, promotion_type = EXCLUDED.promotion_type,
    discount_percent = EXCLUDED.discount_percent, start_date = EXCLUDED.start_date,
    end_date = EXCLUDED.end_date;

INSERT INTO project_staging.etl_row_counts (batch_id, step, object_name, row_count)
SELECT (SELECT MAX(batch_id) FROM project_staging.etl_batch), 'dw_load', t.name, t.n
FROM (
    SELECT 'dim_date' AS name, COUNT(*) AS n FROM dim_date UNION ALL
    SELECT 'dim_customer', COUNT(*) FROM dim_customer UNION ALL
    SELECT 'dim_product', COUNT(*) FROM dim_product UNION ALL
    SELECT 'dim_region', COUNT(*) FROM dim_region UNION ALL
    SELECT 'dim_channel', COUNT(*) FROM dim_channel UNION ALL
    SELECT 'dim_promotion', COUNT(*) FROM dim_promotion
) t;

SELECT 'dim_date' AS dimension, COUNT(*) AS rows FROM dim_date UNION ALL
SELECT 'dim_customer', COUNT(*) FROM dim_customer UNION ALL
SELECT 'dim_product', COUNT(*) FROM dim_product UNION ALL
SELECT 'dim_region', COUNT(*) FROM dim_region UNION ALL
SELECT 'dim_channel', COUNT(*) FROM dim_channel UNION ALL
SELECT 'dim_promotion', COUNT(*) FROM dim_promotion;
