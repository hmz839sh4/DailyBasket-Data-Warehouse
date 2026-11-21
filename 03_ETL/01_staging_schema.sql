-- Raw staging tables: every column is TEXT so bad data can still load; src_row_id is the arrival order, not a warehouse key.
SET search_path = project_staging;

CREATE TABLE IF NOT EXISTS etl_batch (
    batch_id    BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    started_at  TIMESTAMPTZ DEFAULT now(),
    note        TEXT
);

CREATE TABLE IF NOT EXISTS etl_row_counts (
    log_id       BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    batch_id     BIGINT,
    step         TEXT,
    object_name  TEXT,
    row_count    BIGINT,
    logged_at    TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE IF NOT EXISTS etl_rejected_rows (
    reject_id     BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    source_table  TEXT,
    src_row_id    BIGINT,
    business_key  TEXT,
    kind          TEXT,      -- REJECTED (bad row) or DUPLICATE (older copy removed)
    reason        TEXT
);

DROP TABLE IF EXISTS stg_region, stg_channel, stg_customer, stg_product, stg_promotion,
                     stg_promotion_product, stg_orders, stg_sales, stg_inventory CASCADE;

CREATE TABLE stg_region (
    src_row_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    region_id TEXT, city TEXT, province TEXT, country TEXT, region_zone TEXT,
    loaded_at TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE stg_channel (
    src_row_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    channel_id TEXT, channel_name TEXT, channel_type TEXT,
    loaded_at TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE stg_customer (
    src_row_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    customer_id TEXT, customer_name TEXT, email TEXT, gender TEXT,
    age_group TEXT, customer_segment TEXT, signup_date TEXT,
    loaded_at TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE stg_product (
    src_row_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    product_id TEXT, product_name TEXT, brand TEXT, subcategory TEXT, category TEXT,
    unit_cost TEXT, list_price TEXT, is_active TEXT,
    loaded_at TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE stg_promotion (
    src_row_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    promotion_id TEXT, promotion_name TEXT, promotion_type TEXT,
    discount_percent TEXT, start_date TEXT, end_date TEXT,
    loaded_at TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE stg_promotion_product (
    src_row_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    promotion_id TEXT, product_id TEXT,
    loaded_at TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE stg_orders (
    src_row_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    order_id TEXT, order_date TEXT, customer_id TEXT, region_id TEXT, channel_id TEXT,
    loaded_at TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE stg_sales (            -- one row per order line
    src_row_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    order_id TEXT, line_number TEXT, product_id TEXT, quantity TEXT,
    unit_price TEXT, promotion_id TEXT,
    loaded_at TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE stg_inventory (
    src_row_id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    snapshot_date TEXT, product_id TEXT, region_id TEXT, quantity_on_hand TEXT,
    quantity_received TEXT, quantity_sold TEXT, reorder_level TEXT,
    loaded_at TIMESTAMPTZ DEFAULT now()
);

SELECT table_name FROM information_schema.tables
WHERE table_schema = 'project_staging' ORDER BY table_name;
