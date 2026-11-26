-- makes a clean copy of each raw staging table (stg_*_clean)
-- the raw tables are never touched
-- when a key shows up more than once, the row that arrived last wins (highest src_row_id)
-- anything we drop or fix gets written to etl_rejected_rows so nothing disappears quietly
SET search_path = project_staging;

TRUNCATE etl_rejected_rows RESTART IDENTITY;

-- region
DROP TABLE IF EXISTS stg_region_clean;
CREATE TABLE stg_region_clean (
    region_id    TEXT PRIMARY KEY,
    city         TEXT NOT NULL,
    province     TEXT,
    country      TEXT,
    region_zone  TEXT,
    src_row_id   BIGINT
);

CREATE TEMP TABLE t_region AS
SELECT n.*,
       CASE WHEN n.region_id IS NULL THEN 'Missing region_id'
            WHEN n.city IS NULL THEN 'Missing city' END AS reject_reason
FROM (
    SELECT src_row_id,
           NULLIF(UPPER(TRIM(region_id)), '')                         AS region_id,
           NULLIF(INITCAP(regexp_replace(TRIM(city), '\s+', ' ', 'g')), '') AS city,
           INITCAP(TRIM(province))     AS province,
           INITCAP(TRIM(country))      AS country,
           INITCAP(TRIM(region_zone))  AS region_zone,
           ROW_NUMBER() OVER (PARTITION BY UPPER(TRIM(region_id)) ORDER BY src_row_id DESC) AS rn
    FROM stg_region
) n;

INSERT INTO etl_rejected_rows (source_table, src_row_id, business_key, kind, reason)
SELECT 'stg_region', src_row_id, region_id, 'DUPLICATE', 'Older copy of the same region_id removed'
FROM t_region WHERE rn > 1 AND region_id IS NOT NULL;
INSERT INTO etl_rejected_rows (source_table, src_row_id, business_key, kind, reason)
SELECT 'stg_region', src_row_id, region_id, 'REJECTED', reject_reason
FROM t_region WHERE (rn = 1 OR region_id IS NULL) AND reject_reason IS NOT NULL;

INSERT INTO stg_region_clean
SELECT region_id, city, province, country, region_zone, src_row_id
FROM t_region WHERE rn = 1 AND reject_reason IS NULL;

-- channel
DROP TABLE IF EXISTS stg_channel_clean;
CREATE TABLE stg_channel_clean (
    channel_id    TEXT PRIMARY KEY,
    channel_name  TEXT NOT NULL,
    channel_type  TEXT,
    src_row_id    BIGINT
);

CREATE TEMP TABLE t_channel AS
SELECT n.*,
       CASE WHEN n.channel_id IS NULL THEN 'Missing channel_id'
            WHEN n.channel_name IS NULL THEN 'Missing channel_name' END AS reject_reason
FROM (
    SELECT src_row_id,
           NULLIF(UPPER(TRIM(channel_id)), '')   AS channel_id,
           NULLIF(INITCAP(TRIM(channel_name)), '') AS channel_name,
           INITCAP(TRIM(channel_type))           AS channel_type,
           ROW_NUMBER() OVER (PARTITION BY UPPER(TRIM(channel_id)) ORDER BY src_row_id DESC) AS rn
    FROM stg_channel
) n;

INSERT INTO etl_rejected_rows (source_table, src_row_id, business_key, kind, reason)
SELECT 'stg_channel', src_row_id, channel_id, 'DUPLICATE', 'Older copy of the same channel_id removed'
FROM t_channel WHERE rn > 1 AND channel_id IS NOT NULL;
INSERT INTO etl_rejected_rows (source_table, src_row_id, business_key, kind, reason)
SELECT 'stg_channel', src_row_id, channel_id, 'REJECTED', reject_reason
FROM t_channel WHERE (rn = 1 OR channel_id IS NULL) AND reject_reason IS NOT NULL;

INSERT INTO stg_channel_clean
SELECT channel_id, channel_name, channel_type, src_row_id
FROM t_channel WHERE rn = 1 AND reject_reason IS NULL;

-- customer
DROP TABLE IF EXISTS stg_customer_clean;
CREATE TABLE stg_customer_clean (
    customer_id       TEXT PRIMARY KEY,
    customer_name     TEXT,
    email             TEXT,
    gender            TEXT,
    age_group         TEXT,
    customer_segment  TEXT,
    signup_date       DATE,
    src_row_id        BIGINT
);

CREATE TEMP TABLE t_customer AS
SELECT n.*,
       CASE WHEN n.customer_id IS NULL THEN 'Missing customer_id' END AS reject_reason
FROM (
    SELECT src_row_id,
           NULLIF(UPPER(TRIM(customer_id)), '') AS customer_id,
           INITCAP(regexp_replace(TRIM(customer_name), '\s+', ' ', 'g')) AS customer_name,
           COALESCE(NULLIF(LOWER(TRIM(email)), ''), 'not provided')       AS email,
           CASE UPPER(TRIM(gender))
                WHEN 'M' THEN 'Male'   WHEN 'MALE' THEN 'Male'
                WHEN 'F' THEN 'Female' WHEN 'FEMALE' THEN 'Female'
                ELSE 'Other' END                                           AS gender,
           COALESCE(NULLIF(TRIM(age_group), ''), 'Unknown')                AS age_group,
           COALESCE(NULLIF(INITCAP(TRIM(customer_segment)), ''), 'Regular') AS customer_segment,
           CASE WHEN TRIM(signup_date) ~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$'
                THEN TRIM(signup_date)::date END                           AS signup_date,
           ROW_NUMBER() OVER (PARTITION BY UPPER(TRIM(customer_id)) ORDER BY src_row_id DESC) AS rn
    FROM stg_customer
) n;

INSERT INTO etl_rejected_rows (source_table, src_row_id, business_key, kind, reason)
SELECT 'stg_customer', src_row_id, customer_id, 'DUPLICATE', 'Older copy of the same customer_id removed'
FROM t_customer WHERE rn > 1 AND customer_id IS NOT NULL;
INSERT INTO etl_rejected_rows (source_table, src_row_id, business_key, kind, reason)
SELECT 'stg_customer', src_row_id, customer_id, 'REJECTED', reject_reason
FROM t_customer WHERE (rn = 1 OR customer_id IS NULL) AND reject_reason IS NOT NULL;

INSERT INTO stg_customer_clean
SELECT customer_id, customer_name, email, gender, age_group, customer_segment, signup_date, src_row_id
FROM t_customer WHERE rn = 1 AND reject_reason IS NULL;

-- product
DROP TABLE IF EXISTS stg_product_clean;
CREATE TABLE stg_product_clean (
    product_id   TEXT PRIMARY KEY,
    product_name TEXT NOT NULL,
    brand        TEXT,
    subcategory  TEXT,
    category     TEXT,
    unit_cost    NUMERIC(10,2),
    list_price   NUMERIC(10,2) NOT NULL,
    is_active    BOOLEAN,
    src_row_id   BIGINT
);

CREATE TEMP TABLE t_product AS
SELECT n.*,
       CASE WHEN n.product_id IS NULL THEN 'Missing product_id'
            WHEN n.product_name IS NULL THEN 'Missing product_name'
            WHEN n.list_price IS NULL THEN 'Missing or invalid list_price' END AS reject_reason
FROM (
    SELECT src_row_id,
           NULLIF(UPPER(TRIM(product_id)), '') AS product_id,
           NULLIF(regexp_replace(TRIM(product_name), '\s+', ' ', 'g'), '') AS product_name,
           INITCAP(TRIM(brand))        AS brand,
           INITCAP(TRIM(subcategory))  AS subcategory,
           INITCAP(TRIM(category))     AS category,
           CASE WHEN TRIM(unit_cost)  ~ '^[0-9]+(\.[0-9]+)?$' THEN TRIM(unit_cost)::numeric(10,2) END  AS unit_cost_raw,
           CASE WHEN TRIM(list_price) ~ '^[0-9]+(\.[0-9]+)?$' THEN TRIM(list_price)::numeric(10,2) END AS list_price,
           CASE WHEN UPPER(TRIM(is_active)) IN ('N', 'NO', 'FALSE', '0') THEN FALSE ELSE TRUE END      AS is_active,
           ROW_NUMBER() OVER (PARTITION BY UPPER(TRIM(product_id)) ORDER BY src_row_id DESC) AS rn
    FROM stg_product
) n;

INSERT INTO etl_rejected_rows (source_table, src_row_id, business_key, kind, reason)
SELECT 'stg_product', src_row_id, product_id, 'DUPLICATE', 'Older copy of the same product_id removed'
FROM t_product WHERE rn > 1 AND product_id IS NOT NULL;
INSERT INTO etl_rejected_rows (source_table, src_row_id, business_key, kind, reason)
SELECT 'stg_product', src_row_id, product_id, 'REJECTED', reject_reason
FROM t_product WHERE (rn = 1 OR product_id IS NULL) AND reject_reason IS NOT NULL;

-- a missing unit_cost doesn't get the row rejected
-- we guess it as 75% of list price and log it as FIXED
INSERT INTO etl_rejected_rows (source_table, src_row_id, business_key, kind, reason)
SELECT 'stg_product', src_row_id, product_id, 'FIXED', 'Missing unit_cost filled with 75% of list_price'
FROM t_product WHERE rn = 1 AND reject_reason IS NULL AND unit_cost_raw IS NULL;

INSERT INTO stg_product_clean
SELECT product_id, product_name, brand, subcategory, category,
       COALESCE(unit_cost_raw, ROUND(list_price * 0.75, 2)), list_price, is_active, src_row_id
FROM t_product WHERE rn = 1 AND reject_reason IS NULL;

-- promotion
DROP TABLE IF EXISTS stg_promotion_clean;
CREATE TABLE stg_promotion_clean (
    promotion_id      TEXT PRIMARY KEY,
    promotion_name    TEXT,
    promotion_type    TEXT,
    discount_percent  NUMERIC(5,2),
    start_date        DATE NOT NULL,
    end_date          DATE NOT NULL,
    src_row_id        BIGINT
);

CREATE TEMP TABLE t_promotion AS
SELECT n.*,
       CASE WHEN n.promotion_id IS NULL THEN 'Missing promotion_id'
            WHEN n.start_date IS NULL OR n.end_date IS NULL THEN 'Missing or invalid start/end date'
            WHEN n.end_date < n.start_date THEN 'End date before start date' END AS reject_reason
FROM (
    SELECT src_row_id,
           NULLIF(UPPER(TRIM(promotion_id)), '') AS promotion_id,
           regexp_replace(TRIM(promotion_name), '\s+', ' ', 'g') AS promotion_name,
           INITCAP(TRIM(promotion_type)) AS promotion_type,
           COALESCE(CASE WHEN TRIM(discount_percent) ~ '^[0-9]+(\.[0-9]+)?$'
                         THEN TRIM(discount_percent)::numeric(5,2) END, 0) AS discount_percent,
           CASE WHEN TRIM(start_date) ~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' THEN TRIM(start_date)::date END AS start_date,
           CASE WHEN TRIM(end_date)   ~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' THEN TRIM(end_date)::date END   AS end_date,
           ROW_NUMBER() OVER (PARTITION BY UPPER(TRIM(promotion_id)) ORDER BY src_row_id DESC) AS rn
    FROM stg_promotion
) n;

INSERT INTO etl_rejected_rows (source_table, src_row_id, business_key, kind, reason)
SELECT 'stg_promotion', src_row_id, promotion_id, 'DUPLICATE', 'Older copy of the same promotion_id removed'
FROM t_promotion WHERE rn > 1 AND promotion_id IS NOT NULL;
INSERT INTO etl_rejected_rows (source_table, src_row_id, business_key, kind, reason)
SELECT 'stg_promotion', src_row_id, promotion_id, 'REJECTED', reject_reason
FROM t_promotion WHERE (rn = 1 OR promotion_id IS NULL) AND reject_reason IS NOT NULL;

INSERT INTO stg_promotion_clean
SELECT promotion_id, promotion_name, promotion_type, discount_percent, start_date, end_date, src_row_id
FROM t_promotion WHERE rn = 1 AND reject_reason IS NULL;

-- promotion <-> product pairs
DROP TABLE IF EXISTS stg_promotion_product_clean;
CREATE TABLE stg_promotion_product_clean (
    promotion_id  TEXT,
    product_id    TEXT,
    src_row_id    BIGINT,
    PRIMARY KEY (promotion_id, product_id)
);

CREATE TEMP TABLE t_pp AS
SELECT n.*,
       CASE WHEN n.promotion_id IS NULL OR n.product_id IS NULL THEN 'Missing promotion_id or product_id'
            WHEN NOT EXISTS (SELECT 1 FROM stg_promotion_clean p WHERE p.promotion_id = n.promotion_id) THEN 'Promotion not found'
            WHEN NOT EXISTS (SELECT 1 FROM stg_product_clean p WHERE p.product_id = n.product_id) THEN 'Product not found'
       END AS reject_reason
FROM (
    SELECT src_row_id,
           NULLIF(UPPER(TRIM(promotion_id)), '') AS promotion_id,
           NULLIF(UPPER(TRIM(product_id)), '')   AS product_id,
           ROW_NUMBER() OVER (PARTITION BY UPPER(TRIM(promotion_id)), UPPER(TRIM(product_id)) ORDER BY src_row_id DESC) AS rn
    FROM stg_promotion_product
) n;

INSERT INTO etl_rejected_rows (source_table, src_row_id, business_key, kind, reason)
SELECT 'stg_promotion_product', src_row_id, promotion_id || '/' || product_id, 'DUPLICATE', 'Duplicate promotion/product pair removed'
FROM t_pp WHERE rn > 1 AND promotion_id IS NOT NULL AND product_id IS NOT NULL;
INSERT INTO etl_rejected_rows (source_table, src_row_id, business_key, kind, reason)
SELECT 'stg_promotion_product', src_row_id, COALESCE(promotion_id, '?') || '/' || COALESCE(product_id, '?'), 'REJECTED', reject_reason
FROM t_pp WHERE (rn = 1 OR promotion_id IS NULL OR product_id IS NULL) AND reject_reason IS NOT NULL;

INSERT INTO stg_promotion_product_clean
SELECT promotion_id, product_id, src_row_id FROM t_pp WHERE rn = 1 AND reject_reason IS NULL;

-- orders (headers)
DROP TABLE IF EXISTS stg_orders_clean;
CREATE TABLE stg_orders_clean (
    order_id     TEXT PRIMARY KEY,
    order_date   DATE NOT NULL,
    customer_id  TEXT NOT NULL,
    region_id    TEXT NOT NULL,
    channel_id   TEXT NOT NULL,
    src_row_id   BIGINT
);

CREATE TEMP TABLE t_orders AS
SELECT n.*,
       CASE WHEN n.order_id IS NULL THEN 'Missing order_id'
            WHEN n.order_date IS NULL THEN 'Missing or invalid order_date'
            WHEN NOT EXISTS (SELECT 1 FROM stg_customer_clean c WHERE c.customer_id = n.customer_id) THEN 'Customer not found'
            WHEN NOT EXISTS (SELECT 1 FROM stg_region_clean r WHERE r.region_id = n.region_id) THEN 'Region not found'
            WHEN NOT EXISTS (SELECT 1 FROM stg_channel_clean c WHERE c.channel_id = n.channel_id) THEN 'Channel not found'
       END AS reject_reason
FROM (
    SELECT src_row_id,
           NULLIF(UPPER(TRIM(order_id)), '') AS order_id,
           CASE WHEN TRIM(order_date) ~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' THEN TRIM(order_date)::date END AS order_date,
           UPPER(TRIM(customer_id)) AS customer_id,
           UPPER(TRIM(region_id))   AS region_id,
           UPPER(TRIM(channel_id))  AS channel_id,
           ROW_NUMBER() OVER (PARTITION BY UPPER(TRIM(order_id)) ORDER BY src_row_id DESC) AS rn
    FROM stg_orders
) n;

INSERT INTO etl_rejected_rows (source_table, src_row_id, business_key, kind, reason)
SELECT 'stg_orders', src_row_id, order_id, 'DUPLICATE', 'Older copy of the same order_id removed'
FROM t_orders WHERE rn > 1 AND order_id IS NOT NULL;
INSERT INTO etl_rejected_rows (source_table, src_row_id, business_key, kind, reason)
SELECT 'stg_orders', src_row_id, order_id, 'REJECTED', reject_reason
FROM t_orders WHERE (rn = 1 OR order_id IS NULL) AND reject_reason IS NOT NULL;

INSERT INTO stg_orders_clean
SELECT order_id, order_date, customer_id, region_id, channel_id, src_row_id
FROM t_orders WHERE rn = 1 AND reject_reason IS NULL;

-- sales: one row per order line
DROP TABLE IF EXISTS stg_sales_clean;
CREATE TABLE stg_sales_clean (
    order_id      TEXT,
    line_number   INT,
    product_id    TEXT,
    quantity      INT NOT NULL,
    unit_price    NUMERIC(12,2) NOT NULL,
    promotion_id  TEXT,
    src_row_id    BIGINT,
    PRIMARY KEY (order_id, line_number)
);

CREATE TEMP TABLE t_sales AS
SELECT n.*,
       CASE WHEN n.order_id IS NULL OR n.line_number IS NULL THEN 'Missing order_id or line_number'
            WHEN n.quantity IS NULL OR n.quantity <= 0 THEN 'Invalid quantity (zero, negative or missing)'
            WHEN n.unit_price IS NULL THEN 'Missing or invalid unit_price'
            WHEN NOT EXISTS (SELECT 1 FROM stg_product_clean p WHERE p.product_id = n.product_id) THEN 'Product not found'
            WHEN NOT EXISTS (SELECT 1 FROM stg_orders_clean o WHERE o.order_id = n.order_id) THEN 'Order header rejected or missing'
       END AS reject_reason
FROM (
    SELECT src_row_id,
           NULLIF(UPPER(TRIM(order_id)), '') AS order_id,
           CASE WHEN TRIM(line_number) ~ '^[0-9]+$' THEN TRIM(line_number)::int END AS line_number,
           UPPER(TRIM(product_id)) AS product_id,
           CASE WHEN TRIM(quantity) ~ '^-?[0-9]+$' THEN TRIM(quantity)::int END AS quantity,
           CASE WHEN TRIM(unit_price) ~ '^[0-9]+(\.[0-9]+)?$' THEN TRIM(unit_price)::numeric(12,2) END AS unit_price,
           NULLIF(UPPER(TRIM(promotion_id)), '') AS promotion_id,
           ROW_NUMBER() OVER (PARTITION BY UPPER(TRIM(order_id)), TRIM(line_number) ORDER BY src_row_id DESC) AS rn
    FROM stg_sales
) n;

INSERT INTO etl_rejected_rows (source_table, src_row_id, business_key, kind, reason)
SELECT 'stg_sales', src_row_id, order_id || '-' || line_number, 'DUPLICATE', 'Order line loaded twice, extra copy removed'
FROM t_sales WHERE rn > 1 AND order_id IS NOT NULL AND line_number IS NOT NULL;
INSERT INTO etl_rejected_rows (source_table, src_row_id, business_key, kind, reason)
SELECT 'stg_sales', src_row_id, COALESCE(order_id, '?') || '-' || COALESCE(line_number::text, '?'), 'REJECTED', reject_reason
FROM t_sales WHERE (rn = 1 OR order_id IS NULL OR line_number IS NULL) AND reject_reason IS NOT NULL;

-- if the promotion_id doesn't exist we still keep the sale
-- and just treat it as having no promotion
INSERT INTO stg_sales_clean
SELECT s.order_id,
       s.line_number,
       s.product_id,
       s.quantity,
       s.unit_price,
       CASE WHEN EXISTS (SELECT 1 FROM stg_promotion_clean p WHERE p.promotion_id = s.promotion_id)
            THEN s.promotion_id END,
       s.src_row_id
FROM t_sales s WHERE s.rn = 1 AND s.reject_reason IS NULL;

-- inventory
DROP TABLE IF EXISTS stg_inventory_clean;
CREATE TABLE stg_inventory_clean (
    snapshot_date      DATE,
    product_id         TEXT,
    region_id          TEXT,
    quantity_on_hand   INT NOT NULL,
    quantity_received  INT,
    quantity_sold      INT,
    reorder_level      INT,
    src_row_id         BIGINT,
    PRIMARY KEY (snapshot_date, product_id, region_id)
);

CREATE TEMP TABLE t_inv AS
SELECT n.*,
       CASE WHEN n.snapshot_date IS NULL THEN 'Missing or invalid snapshot_date'
            WHEN n.quantity_on_hand IS NULL THEN 'Missing quantity_on_hand'
            WHEN n.quantity_on_hand < 0 THEN 'Negative quantity_on_hand'
            WHEN NOT EXISTS (SELECT 1 FROM stg_product_clean p WHERE p.product_id = n.product_id) THEN 'Product not found'
            WHEN NOT EXISTS (SELECT 1 FROM stg_region_clean r WHERE r.region_id = n.region_id) THEN 'Region not found'
       END AS reject_reason
FROM (
    SELECT src_row_id,
           CASE WHEN TRIM(snapshot_date) ~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' THEN TRIM(snapshot_date)::date END AS snapshot_date,
           UPPER(TRIM(product_id)) AS product_id,
           UPPER(TRIM(region_id))  AS region_id,
           CASE WHEN TRIM(quantity_on_hand) ~ '^-?[0-9]+$' THEN TRIM(quantity_on_hand)::int END AS quantity_on_hand,
           COALESCE(CASE WHEN TRIM(quantity_received) ~ '^[0-9]+$' THEN TRIM(quantity_received)::int END, 0) AS quantity_received,
           COALESCE(CASE WHEN TRIM(quantity_sold) ~ '^[0-9]+$' THEN TRIM(quantity_sold)::int END, 0)         AS quantity_sold,
           COALESCE(CASE WHEN TRIM(reorder_level) ~ '^[0-9]+$' THEN TRIM(reorder_level)::int END, 0)         AS reorder_level,
           ROW_NUMBER() OVER (PARTITION BY TRIM(snapshot_date), UPPER(TRIM(product_id)), UPPER(TRIM(region_id))
                              ORDER BY src_row_id DESC) AS rn
    FROM stg_inventory
) n;

INSERT INTO etl_rejected_rows (source_table, src_row_id, business_key, kind, reason)
SELECT 'stg_inventory', src_row_id, product_id || '/' || region_id || '/' || snapshot_date, 'DUPLICATE', 'Duplicate snapshot row removed'
FROM t_inv WHERE rn > 1 AND snapshot_date IS NOT NULL;
INSERT INTO etl_rejected_rows (source_table, src_row_id, business_key, kind, reason)
SELECT 'stg_inventory', src_row_id, COALESCE(product_id, '?') || '/' || COALESCE(region_id, '?'), 'REJECTED', reject_reason
FROM t_inv WHERE (rn = 1 OR snapshot_date IS NULL) AND reject_reason IS NOT NULL;

INSERT INTO stg_inventory_clean
SELECT snapshot_date, product_id, region_id, quantity_on_hand, quantity_received, quantity_sold, reorder_level, src_row_id
FROM t_inv WHERE rn = 1 AND reject_reason IS NULL;

-- remember how many rows each clean table ended up with
INSERT INTO etl_row_counts (batch_id, step, object_name, row_count)
SELECT (SELECT MAX(batch_id) FROM etl_batch), 'clean', t.name, t.n
FROM (
    SELECT 'stg_region_clean' AS name, COUNT(*) AS n FROM stg_region_clean UNION ALL
    SELECT 'stg_channel_clean', COUNT(*) FROM stg_channel_clean UNION ALL
    SELECT 'stg_customer_clean', COUNT(*) FROM stg_customer_clean UNION ALL
    SELECT 'stg_product_clean', COUNT(*) FROM stg_product_clean UNION ALL
    SELECT 'stg_promotion_clean', COUNT(*) FROM stg_promotion_clean UNION ALL
    SELECT 'stg_promotion_product_clean', COUNT(*) FROM stg_promotion_product_clean UNION ALL
    SELECT 'stg_orders_clean', COUNT(*) FROM stg_orders_clean UNION ALL
    SELECT 'stg_sales_clean', COUNT(*) FROM stg_sales_clean UNION ALL
    SELECT 'stg_inventory_clean', COUNT(*) FROM stg_inventory_clean
) t;

-- what got removed or fixed, grouped by table and reason
SELECT source_table, kind, reason, COUNT(*) AS rows
FROM etl_rejected_rows
GROUP BY source_table, kind, reason
ORDER BY source_table, kind, reason;