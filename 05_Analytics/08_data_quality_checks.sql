-- Data quality checks: completeness, accuracy and integrity.
-- Every check writes one row into project_reporting.dq_results
-- with a status of PASS, FAIL or INFO.
CREATE TABLE IF NOT EXISTS project_reporting.dq_results (
    check_id    INT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    category    TEXT,
    check_name  TEXT,
    expected    TEXT,
    actual      TEXT,
    status      TEXT,
    checked_at  TIMESTAMPTZ DEFAULT now()
);

-- start fresh on every run
TRUNCATE project_reporting.dq_results RESTART IDENTITY;

SET search_path = project_dw, project_staging, project_reporting;

-- 1. COMPLETENESS  (we expect zero missing values)

INSERT INTO dq_results (category, check_name, expected, actual, status)
SELECT 'Completeness', t.name, '0', t.n::text, CASE WHEN t.n = 0 THEN 'PASS' ELSE 'FAIL' END
FROM (
    SELECT 'dim_customer: missing customer_id or customer_name' AS name,
           (SELECT COUNT(*) FROM dim_customer WHERE customer_id IS NULL OR customer_name IS NULL) AS n UNION ALL
    SELECT 'dim_product: missing product_id, name, category, cost or price',
           (SELECT COUNT(*) FROM dim_product WHERE product_id IS NULL OR product_name IS NULL OR category IS NULL OR unit_cost IS NULL OR list_price IS NULL) UNION ALL
    SELECT 'dim_region: missing region_id or city',
           (SELECT COUNT(*) FROM dim_region WHERE region_id IS NULL OR city IS NULL) UNION ALL
    SELECT 'dim_channel: missing channel_id or channel_name',
           (SELECT COUNT(*) FROM dim_channel WHERE channel_id IS NULL OR channel_name IS NULL) UNION ALL
    SELECT 'dim_promotion: missing promotion_id or name',
           (SELECT COUNT(*) FROM dim_promotion WHERE promotion_id IS NULL OR promotion_name IS NULL) UNION ALL
    SELECT 'fact_sales: missing foreign key',
           (SELECT COUNT(*) FROM fact_sales WHERE date_key IS NULL OR customer_key IS NULL OR product_key IS NULL
                   OR region_key IS NULL OR channel_key IS NULL OR promotion_key IS NULL) UNION ALL
    SELECT 'fact_sales: missing measure',
           (SELECT COUNT(*) FROM fact_sales WHERE quantity IS NULL OR unit_price IS NULL OR discount_amount IS NULL
                   OR gross_amount IS NULL OR net_revenue IS NULL OR cost_amount IS NULL OR profit_amount IS NULL) UNION ALL
    SELECT 'fact_inventory_snapshot: missing foreign key or measure',
           (SELECT COUNT(*) FROM fact_inventory_snapshot WHERE date_key IS NULL OR product_key IS NULL OR region_key IS NULL
                   OR quantity_on_hand IS NULL OR stock_value IS NULL) UNION ALL
    SELECT 'fact_promotion_event: missing foreign key',
           (SELECT COUNT(*) FROM fact_promotion_event WHERE date_key IS NULL OR product_key IS NULL OR promotion_key IS NULL)
) t;

-- Gaps we already patched while cleaning the data.
-- These are only for information, so they never fail.
INSERT INTO dq_results (category, check_name, expected, actual, status)
SELECT 'Completeness', 'Customers with no email (filled with "not provided")', 'info',
       COUNT(*)::text, 'INFO' FROM dim_customer WHERE email = 'not provided';
INSERT INTO dq_results (category, check_name, expected, actual, status)
SELECT 'Completeness', 'Customers with unknown age group (filled with "Unknown")', 'info',
       COUNT(*)::text, 'INFO' FROM dim_customer WHERE age_group = 'Unknown';
INSERT INTO dq_results (category, check_name, expected, actual, status)
SELECT 'Completeness', 'Customers with no valid signup date (kept as NULL)', 'info',
       COUNT(*)::text, 'INFO' FROM dim_customer WHERE signup_date IS NULL;

-- 2. ACCURACY: do staging and the warehouse agree
--    Staging totals are worked out on their own, without any dimensions.

-- 2a. No row went missing along the way: raw = clean + removed
INSERT INTO dq_results (category, check_name, expected, actual, status)
SELECT 'Accuracy', 'Raw = clean + removed rows: ' || t.src, t.raw::text, (t.clean + t.removed)::text,
       CASE WHEN t.raw = t.clean + t.removed THEN 'PASS' ELSE 'FAIL' END
FROM (
    SELECT 'stg_region' AS src, (SELECT COUNT(*) FROM stg_region) AS raw, (SELECT COUNT(*) FROM stg_region_clean) AS clean,
           (SELECT COUNT(*) FROM etl_rejected_rows WHERE source_table = 'stg_region' AND kind IN ('REJECTED','DUPLICATE')) AS removed UNION ALL
    SELECT 'stg_channel', (SELECT COUNT(*) FROM stg_channel), (SELECT COUNT(*) FROM stg_channel_clean),
           (SELECT COUNT(*) FROM etl_rejected_rows WHERE source_table = 'stg_channel' AND kind IN ('REJECTED','DUPLICATE')) UNION ALL
    SELECT 'stg_customer', (SELECT COUNT(*) FROM stg_customer), (SELECT COUNT(*) FROM stg_customer_clean),
           (SELECT COUNT(*) FROM etl_rejected_rows WHERE source_table = 'stg_customer' AND kind IN ('REJECTED','DUPLICATE')) UNION ALL
    SELECT 'stg_product', (SELECT COUNT(*) FROM stg_product), (SELECT COUNT(*) FROM stg_product_clean),
           (SELECT COUNT(*) FROM etl_rejected_rows WHERE source_table = 'stg_product' AND kind IN ('REJECTED','DUPLICATE')) UNION ALL
    SELECT 'stg_promotion', (SELECT COUNT(*) FROM stg_promotion), (SELECT COUNT(*) FROM stg_promotion_clean),
           (SELECT COUNT(*) FROM etl_rejected_rows WHERE source_table = 'stg_promotion' AND kind IN ('REJECTED','DUPLICATE')) UNION ALL
    SELECT 'stg_promotion_product', (SELECT COUNT(*) FROM stg_promotion_product), (SELECT COUNT(*) FROM stg_promotion_product_clean),
           (SELECT COUNT(*) FROM etl_rejected_rows WHERE source_table = 'stg_promotion_product' AND kind IN ('REJECTED','DUPLICATE')) UNION ALL
    SELECT 'stg_orders', (SELECT COUNT(*) FROM stg_orders), (SELECT COUNT(*) FROM stg_orders_clean),
           (SELECT COUNT(*) FROM etl_rejected_rows WHERE source_table = 'stg_orders' AND kind IN ('REJECTED','DUPLICATE')) UNION ALL
    SELECT 'stg_sales', (SELECT COUNT(*) FROM stg_sales), (SELECT COUNT(*) FROM stg_sales_clean),
           (SELECT COUNT(*) FROM etl_rejected_rows WHERE source_table = 'stg_sales' AND kind IN ('REJECTED','DUPLICATE')) UNION ALL
    SELECT 'stg_inventory', (SELECT COUNT(*) FROM stg_inventory), (SELECT COUNT(*) FROM stg_inventory_clean),
           (SELECT COUNT(*) FROM etl_rejected_rows WHERE source_table = 'stg_inventory' AND kind IN ('REJECTED','DUPLICATE'))
) t;

-- 2b. Clean staging data should match what landed in the warehouse
INSERT INTO dq_results (category, check_name, expected, actual, status)
SELECT 'Accuracy', t.name, t.expected::text, t.actual::text,
       CASE WHEN t.expected = t.actual THEN 'PASS' ELSE 'FAIL' END
FROM (
    SELECT 'Row count: clean order lines vs fact_sales' AS name,
           (SELECT COUNT(*) FROM stg_sales_clean) AS expected,
           (SELECT COUNT(*) FROM fact_sales) AS actual UNION ALL
    SELECT 'Sum of quantity: clean order lines vs fact_sales',
           (SELECT SUM(quantity) FROM stg_sales_clean),
           (SELECT SUM(quantity) FROM fact_sales) UNION ALL
    SELECT 'Gross revenue: clean order lines vs fact_sales',
           (SELECT SUM(ROUND(quantity * unit_price, 2)) FROM stg_sales_clean),
           (SELECT SUM(gross_amount) FROM fact_sales) UNION ALL
    SELECT 'Discount amount: clean order lines vs fact_sales',
           (SELECT SUM(ROUND(l.quantity * l.unit_price * COALESCE(p.discount_percent, 0) / 100, 2))
              FROM stg_sales_clean l LEFT JOIN stg_promotion_clean p ON p.promotion_id = l.promotion_id),
           (SELECT SUM(discount_amount) FROM fact_sales) UNION ALL
    SELECT 'Net revenue: clean order lines vs fact_sales',
           (SELECT SUM(ROUND(l.quantity * l.unit_price, 2)
                       - ROUND(l.quantity * l.unit_price * COALESCE(p.discount_percent, 0) / 100, 2))
              FROM stg_sales_clean l LEFT JOIN stg_promotion_clean p ON p.promotion_id = l.promotion_id),
           (SELECT SUM(net_revenue) FROM fact_sales) UNION ALL
    SELECT 'Row count: clean inventory vs fact_inventory_snapshot',
           (SELECT COUNT(*) FROM stg_inventory_clean),
           (SELECT COUNT(*) FROM fact_inventory_snapshot) UNION ALL
    SELECT 'Sum of quantity_on_hand: clean inventory vs fact_inventory_snapshot',
           (SELECT SUM(quantity_on_hand) FROM stg_inventory_clean),
           (SELECT SUM(quantity_on_hand) FROM fact_inventory_snapshot) UNION ALL
    SELECT 'Row count: promotion days (start to end date) vs fact_promotion_event',
           (SELECT SUM(p.end_date - p.start_date + 1) FROM stg_promotion_product_clean pp
              JOIN stg_promotion_clean p ON p.promotion_id = pp.promotion_id),
           (SELECT COUNT(*) FROM fact_promotion_event)
) t;

-- 2c. The maths inside each row should hold up (expected 0 bad rows)
INSERT INTO dq_results (category, check_name, expected, actual, status)
SELECT 'Accuracy', t.name, '0', t.n::text, CASE WHEN t.n = 0 THEN 'PASS' ELSE 'FAIL' END
FROM (
    SELECT 'fact_sales rows where gross - discount <> net_revenue' AS name,
           (SELECT COUNT(*) FROM fact_sales WHERE gross_amount - discount_amount <> net_revenue) AS n UNION ALL
    SELECT 'fact_sales rows where net_revenue - cost <> profit',
           (SELECT COUNT(*) FROM fact_sales WHERE net_revenue - cost_amount <> profit_amount) UNION ALL
    SELECT 'fact_sales rows where quantity x unit_price <> gross_amount',
           (SELECT COUNT(*) FROM fact_sales WHERE ROUND(quantity * unit_price, 2) <> gross_amount) UNION ALL
    SELECT 'fact_inventory_snapshot rows where on_hand x unit_cost <> stock_value',
           (SELECT COUNT(*) FROM fact_inventory_snapshot i JOIN dim_product p ON p.product_key = i.product_key
             WHERE ROUND(i.quantity_on_hand * p.unit_cost, 2) <> i.stock_value) UNION ALL
    SELECT 'fact_sales rows with quantity <= 0',
           (SELECT COUNT(*) FROM fact_sales WHERE quantity <= 0) UNION ALL
    SELECT 'fact_sales rows with negative net_revenue',
           (SELECT COUNT(*) FROM fact_sales WHERE net_revenue < 0) UNION ALL
    SELECT 'dim_product rows where unit_cost > list_price',
           (SELECT COUNT(*) FROM dim_product WHERE unit_cost > list_price) UNION ALL
    SELECT 'dim_promotion rows with discount outside 0 to 100',
           (SELECT COUNT(*) FROM dim_promotion WHERE discount_percent < 0 OR discount_percent > 100)
) t;

-- 3. INTEGRITY

-- 3a. Orphans: fact rows that point at a dimension row that doesn't exist (expected 0)
INSERT INTO dq_results (category, check_name, expected, actual, status)
SELECT 'Integrity', 'Orphans: ' || t.name, '0', t.n::text, CASE WHEN t.n = 0 THEN 'PASS' ELSE 'FAIL' END
FROM (
    SELECT 'fact_sales.date_key -> dim_date' AS name,
           (SELECT COUNT(*) FROM fact_sales f LEFT JOIN dim_date d ON d.date_key = f.date_key WHERE d.date_key IS NULL) AS n UNION ALL
    SELECT 'fact_sales.customer_key -> dim_customer',
           (SELECT COUNT(*) FROM fact_sales f LEFT JOIN dim_customer d ON d.customer_key = f.customer_key WHERE d.customer_key IS NULL) UNION ALL
    SELECT 'fact_sales.product_key -> dim_product',
           (SELECT COUNT(*) FROM fact_sales f LEFT JOIN dim_product d ON d.product_key = f.product_key WHERE d.product_key IS NULL) UNION ALL
    SELECT 'fact_sales.region_key -> dim_region',
           (SELECT COUNT(*) FROM fact_sales f LEFT JOIN dim_region d ON d.region_key = f.region_key WHERE d.region_key IS NULL) UNION ALL
    SELECT 'fact_sales.channel_key -> dim_channel',
           (SELECT COUNT(*) FROM fact_sales f LEFT JOIN dim_channel d ON d.channel_key = f.channel_key WHERE d.channel_key IS NULL) UNION ALL
    SELECT 'fact_sales.promotion_key -> dim_promotion',
           (SELECT COUNT(*) FROM fact_sales f LEFT JOIN dim_promotion d ON d.promotion_key = f.promotion_key WHERE d.promotion_key IS NULL) UNION ALL
    SELECT 'fact_inventory_snapshot.date_key -> dim_date',
           (SELECT COUNT(*) FROM fact_inventory_snapshot f LEFT JOIN dim_date d ON d.date_key = f.date_key WHERE d.date_key IS NULL) UNION ALL
    SELECT 'fact_inventory_snapshot.product_key -> dim_product',
           (SELECT COUNT(*) FROM fact_inventory_snapshot f LEFT JOIN dim_product d ON d.product_key = f.product_key WHERE d.product_key IS NULL) UNION ALL
    SELECT 'fact_inventory_snapshot.region_key -> dim_region',
           (SELECT COUNT(*) FROM fact_inventory_snapshot f LEFT JOIN dim_region d ON d.region_key = f.region_key WHERE d.region_key IS NULL) UNION ALL
    SELECT 'fact_promotion_event.date_key -> dim_date',
           (SELECT COUNT(*) FROM fact_promotion_event f LEFT JOIN dim_date d ON d.date_key = f.date_key WHERE d.date_key IS NULL) UNION ALL
    SELECT 'fact_promotion_event.product_key -> dim_product',
           (SELECT COUNT(*) FROM fact_promotion_event f LEFT JOIN dim_product d ON d.product_key = f.product_key WHERE d.product_key IS NULL) UNION ALL
    SELECT 'fact_promotion_event.promotion_key -> dim_promotion',
           (SELECT COUNT(*) FROM fact_promotion_event f LEFT JOIN dim_promotion d ON d.promotion_key = f.promotion_key WHERE d.promotion_key IS NULL)
) t;

-- 3b. Each dimension's business key should be unique (total rows = distinct keys)
INSERT INTO dq_results (category, check_name, expected, actual, status)
SELECT 'Integrity', 'Unique business key: ' || t.name, t.total::text, t.distinct_keys::text,
       CASE WHEN t.total = t.distinct_keys THEN 'PASS' ELSE 'FAIL' END
FROM (
    SELECT 'dim_date.full_date' AS name, COUNT(*) AS total, COUNT(DISTINCT full_date) AS distinct_keys FROM dim_date UNION ALL
    SELECT 'dim_customer.customer_id', COUNT(*), COUNT(DISTINCT customer_id) FROM dim_customer UNION ALL
    SELECT 'dim_product.product_id', COUNT(*), COUNT(DISTINCT product_id) FROM dim_product UNION ALL
    SELECT 'dim_region.region_id', COUNT(*), COUNT(DISTINCT region_id) FROM dim_region UNION ALL
    SELECT 'dim_channel.channel_id', COUNT(*), COUNT(DISTINCT channel_id) FROM dim_channel UNION ALL
    SELECT 'dim_promotion.promotion_id', COUNT(*), COUNT(DISTINCT promotion_id) FROM dim_promotion
) t;

-- 3c. The No Promotion placeholder (key 0) must exist exactly once
INSERT INTO dq_results (category, check_name, expected, actual, status)
SELECT 'Integrity', 'dim_promotion has exactly one "No Promotion" row with key 0', '1', COUNT(*)::text,
       CASE WHEN COUNT(*) = 1 THEN 'PASS' ELSE 'FAIL' END
FROM dim_promotion WHERE promotion_key = 0;

-- 3d. Grain check: the same key combination must never appear twice in a fact table
INSERT INTO dq_results (category, check_name, expected, actual, status)
SELECT 'Integrity', 'Duplicate grain rows: ' || t.name, '0', t.n::text, CASE WHEN t.n = 0 THEN 'PASS' ELSE 'FAIL' END
FROM (
    SELECT 'fact_sales (order_id + order_line_number)' AS name,
           (SELECT COUNT(*) - COUNT(DISTINCT (order_id, order_line_number)) FROM fact_sales) AS n UNION ALL
    SELECT 'fact_inventory_snapshot (date + product + region)',
           (SELECT COUNT(*) - COUNT(DISTINCT (date_key, product_key, region_key)) FROM fact_inventory_snapshot) UNION ALL
    SELECT 'fact_promotion_event (date + product + promotion)',
           (SELECT COUNT(*) - COUNT(DISTINCT (date_key, product_key, promotion_key)) FROM fact_promotion_event)
) t;

-- 3e. Constraint tests: each bad insert below MUST be rejected.
--     If the database lets it through, that check is marked FAIL.

-- unknown customer_key should hit the foreign key
DO $$
BEGIN
    INSERT INTO project_dw.fact_sales (date_key, customer_key, product_key, region_key, channel_key, promotion_key,
        order_id, order_line_number, quantity, unit_price, discount_amount, gross_amount, net_revenue, cost_amount, profit_amount)
    VALUES (20260101, -1, 1, 1, 1, 0, 'O-TEST', 1, 1, 1, 0, 1, 1, 1, 0);
    INSERT INTO project_reporting.dq_results (category, check_name, expected, actual, status)
    VALUES ('Integrity', 'Constraint test: fact row with unknown customer_key', 'rejected', 'ACCEPTED (bad)', 'FAIL');
EXCEPTION WHEN foreign_key_violation THEN
    INSERT INTO project_reporting.dq_results (category, check_name, expected, actual, status)
    VALUES ('Integrity', 'Constraint test: fact row with unknown customer_key', 'rejected', 'rejected by foreign key', 'PASS');
END $$;

-- a repeated customer_id should hit the unique constraint
DO $$
BEGIN
    INSERT INTO project_dw.dim_customer (customer_id)
    SELECT customer_id FROM project_dw.dim_customer LIMIT 1;
    INSERT INTO project_reporting.dq_results (category, check_name, expected, actual, status)
    VALUES ('Integrity', 'Constraint test: duplicate customer_id in dim_customer', 'rejected', 'ACCEPTED (bad)', 'FAIL');
EXCEPTION WHEN unique_violation THEN
    INSERT INTO project_reporting.dq_results (category, check_name, expected, actual, status)
    VALUES ('Integrity', 'Constraint test: duplicate customer_id in dim_customer', 'rejected', 'rejected by unique constraint', 'PASS');
END $$;

-- loading the same order line twice should hit the unique constraint
DO $$
BEGIN
    INSERT INTO project_dw.fact_sales (date_key, customer_key, product_key, region_key, channel_key, promotion_key,
        order_id, order_line_number, quantity, unit_price, discount_amount, gross_amount, net_revenue, cost_amount, profit_amount)
    SELECT date_key, customer_key, product_key, region_key, channel_key, promotion_key,
           order_id, order_line_number, quantity, unit_price, discount_amount, gross_amount, net_revenue, cost_amount, profit_amount
    FROM project_dw.fact_sales LIMIT 1;
    INSERT INTO project_reporting.dq_results (category, check_name, expected, actual, status)
    VALUES ('Integrity', 'Constraint test: same order line loaded twice', 'rejected', 'ACCEPTED (bad)', 'FAIL');
EXCEPTION WHEN unique_violation THEN
    INSERT INTO project_reporting.dq_results (category, check_name, expected, actual, status)
    VALUES ('Integrity', 'Constraint test: same order line loaded twice', 'rejected', 'rejected by unique constraint', 'PASS');
END $$;

-- quantity = 0 should hit the check constraint
DO $$
BEGIN
    INSERT INTO project_dw.fact_sales (date_key, customer_key, product_key, region_key, channel_key, promotion_key,
        order_id, order_line_number, quantity, unit_price, discount_amount, gross_amount, net_revenue, cost_amount, profit_amount)
    VALUES (20260101, 1, 1, 1, 1, 0, 'O-TEST', 2, 0, 1, 0, 1, 1, 1, 0);
    INSERT INTO project_reporting.dq_results (category, check_name, expected, actual, status)
    VALUES ('Integrity', 'Constraint test: fact row with quantity = 0', 'rejected', 'ACCEPTED (bad)', 'FAIL');
EXCEPTION WHEN check_violation THEN
    INSERT INTO project_reporting.dq_results (category, check_name, expected, actual, status)
    VALUES ('Integrity', 'Constraint test: fact row with quantity = 0', 'rejected', 'rejected by check constraint', 'PASS');
END $$;

-- 3f. Safe re-run: this batch's warehouse row counts should equal the previous batch.
--     Nothing is inserted here if there is no earlier run to compare with.
INSERT INTO dq_results (category, check_name, expected, actual, status)
SELECT 'Integrity', 'Re-run gives same row count: ' || cur.object_name,
       prev.row_count::text, cur.row_count::text,
       CASE WHEN prev.row_count = cur.row_count THEN 'PASS' ELSE 'FAIL' END
FROM project_staging.etl_row_counts cur
JOIN project_staging.etl_row_counts prev
  ON prev.object_name = cur.object_name AND prev.step = 'dw_load'
 AND prev.batch_id = (SELECT MAX(b.batch_id) FROM project_staging.etl_row_counts b
                      WHERE b.step = 'dw_load' AND b.batch_id < cur.batch_id)
WHERE cur.step = 'dw_load'
  AND cur.batch_id = (SELECT MAX(batch_id) FROM project_staging.etl_batch);

-- Results: a summary first, then anything that did not pass
SELECT category, status, COUNT(*) AS checks FROM dq_results GROUP BY category, status ORDER BY category, status;
SELECT check_id, category, status, check_name, expected, actual FROM dq_results WHERE status <> 'PASS' ORDER BY check_id;