-- Exports the clean staging tables to CSV files in 02_Data/cleaned_data (run from the repository root).
\copy (SELECT * FROM project_staging.stg_region_clean ORDER BY region_id) TO '02_Data/cleaned_data/regions_clean.csv' WITH (FORMAT csv, HEADER true)
\copy (SELECT * FROM project_staging.stg_channel_clean ORDER BY channel_id) TO '02_Data/cleaned_data/channels_clean.csv' WITH (FORMAT csv, HEADER true)
\copy (SELECT * FROM project_staging.stg_customer_clean ORDER BY customer_id) TO '02_Data/cleaned_data/customers_clean.csv' WITH (FORMAT csv, HEADER true)
\copy (SELECT * FROM project_staging.stg_product_clean ORDER BY product_id) TO '02_Data/cleaned_data/products_clean.csv' WITH (FORMAT csv, HEADER true)
\copy (SELECT * FROM project_staging.stg_promotion_clean ORDER BY promotion_id) TO '02_Data/cleaned_data/promotions_clean.csv' WITH (FORMAT csv, HEADER true)
\copy (SELECT * FROM project_staging.stg_promotion_product_clean ORDER BY promotion_id, product_id) TO '02_Data/cleaned_data/promotion_products_clean.csv' WITH (FORMAT csv, HEADER true)
\copy (SELECT * FROM project_staging.stg_orders_clean ORDER BY order_id) TO '02_Data/cleaned_data/orders_clean.csv' WITH (FORMAT csv, HEADER true)
\copy (SELECT * FROM project_staging.stg_sales_clean ORDER BY order_id, line_number) TO '02_Data/cleaned_data/order_lines_clean.csv' WITH (FORMAT csv, HEADER true)
\copy (SELECT * FROM project_staging.stg_inventory_clean ORDER BY snapshot_date, product_id, region_id) TO '02_Data/cleaned_data/inventory_clean.csv' WITH (FORMAT csv, HEADER true)

SELECT 'cleaned CSV files written' AS result;
