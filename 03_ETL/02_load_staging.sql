-- Loads the 9 source CSV files into the raw staging tables (run from the repository root).
SET search_path = project_staging;

INSERT INTO etl_batch (note) VALUES ('Staging load');

TRUNCATE stg_region, stg_channel, stg_customer, stg_product, stg_promotion,
         stg_promotion_product, stg_orders, stg_sales, stg_inventory
         RESTART IDENTITY;

\copy stg_region (region_id, city, province, country, region_zone) FROM '02_Data/raw_data/source_regions.csv' WITH (FORMAT csv, HEADER true)
\copy stg_channel (channel_id, channel_name, channel_type) FROM '02_Data/raw_data/source_channels.csv' WITH (FORMAT csv, HEADER true)
\copy stg_customer (customer_id, customer_name, email, gender, age_group, customer_segment, signup_date) FROM '02_Data/raw_data/source_customers.csv' WITH (FORMAT csv, HEADER true)
\copy stg_product (product_id, product_name, brand, subcategory, category, unit_cost, list_price, is_active) FROM '02_Data/raw_data/source_products.csv' WITH (FORMAT csv, HEADER true)
\copy stg_promotion (promotion_id, promotion_name, promotion_type, discount_percent, start_date, end_date) FROM '02_Data/raw_data/source_promotions.csv' WITH (FORMAT csv, HEADER true)
\copy stg_promotion_product (promotion_id, product_id) FROM '02_Data/raw_data/source_promotion_products.csv' WITH (FORMAT csv, HEADER true)
\copy stg_orders (order_id, order_date, customer_id, region_id, channel_id) FROM '02_Data/raw_data/source_orders.csv' WITH (FORMAT csv, HEADER true)
\copy stg_sales (order_id, line_number, product_id, quantity, unit_price, promotion_id) FROM '02_Data/raw_data/source_order_lines.csv' WITH (FORMAT csv, HEADER true)
\copy stg_inventory (snapshot_date, product_id, region_id, quantity_on_hand, quantity_received, quantity_sold, reorder_level) FROM '02_Data/raw_data/source_inventory.csv' WITH (FORMAT csv, HEADER true)

INSERT INTO etl_row_counts (batch_id, step, object_name, row_count)
SELECT (SELECT MAX(batch_id) FROM etl_batch), 'raw_load', t.name, t.n
FROM (
    SELECT 'stg_region' AS name, COUNT(*) AS n FROM stg_region UNION ALL
    SELECT 'stg_channel', COUNT(*) FROM stg_channel UNION ALL
    SELECT 'stg_customer', COUNT(*) FROM stg_customer UNION ALL
    SELECT 'stg_product', COUNT(*) FROM stg_product UNION ALL
    SELECT 'stg_promotion', COUNT(*) FROM stg_promotion UNION ALL
    SELECT 'stg_promotion_product', COUNT(*) FROM stg_promotion_product UNION ALL
    SELECT 'stg_orders', COUNT(*) FROM stg_orders UNION ALL
    SELECT 'stg_sales', COUNT(*) FROM stg_sales UNION ALL
    SELECT 'stg_inventory', COUNT(*) FROM stg_inventory
) t;

SELECT object_name, row_count FROM etl_row_counts
WHERE batch_id = (SELECT MAX(batch_id) FROM etl_batch) AND step = 'raw_load'
ORDER BY object_name;
