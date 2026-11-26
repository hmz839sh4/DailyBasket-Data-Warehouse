-- fills the 3 fact tables
-- every business key (like customer_id) gets swapped for the surrogate key of its dimension
SET search_path = project_dw;

-- sales: one row per order line
INSERT INTO fact_sales
    (date_key, customer_key, product_key, region_key, channel_key, promotion_key,
     order_id, order_line_number, quantity, unit_price,
     discount_amount, gross_amount, net_revenue, cost_amount, profit_amount)
SELECT d.date_key,
       c.customer_key,
       p.product_key,
       r.region_key,
       ch.channel_key,
       COALESCE(pr.promotion_key, 0),                         -- no promo -> key 0
       l.order_id,
       l.line_number,
       l.quantity,
       l.unit_price,
       ROUND(l.quantity * l.unit_price * COALESCE(pr.discount_percent, 0) / 100, 2),
       ROUND(l.quantity * l.unit_price, 2),
       ROUND(l.quantity * l.unit_price, 2)
         - ROUND(l.quantity * l.unit_price * COALESCE(pr.discount_percent, 0) / 100, 2),
       ROUND(l.quantity * p.unit_cost, 2),
       ROUND(l.quantity * l.unit_price, 2)
         - ROUND(l.quantity * l.unit_price * COALESCE(pr.discount_percent, 0) / 100, 2)
         - ROUND(l.quantity * p.unit_cost, 2)
FROM project_staging.stg_sales_clean  l
JOIN project_staging.stg_orders_clean o  ON o.order_id   = l.order_id
JOIN dim_date      d  ON d.full_date   = o.order_date
JOIN dim_customer  c  ON c.customer_id = o.customer_id
JOIN dim_product   p  ON p.product_id  = l.product_id
JOIN dim_region    r  ON r.region_id   = o.region_id
JOIN dim_channel   ch ON ch.channel_id = o.channel_id
LEFT JOIN dim_promotion pr ON pr.promotion_id = l.promotion_id
ON CONFLICT (order_id, order_line_number) DO NOTHING;

-- inventory: one row per product, region and day
INSERT INTO fact_inventory_snapshot
    (date_key, product_key, region_key, quantity_on_hand, quantity_received,
     quantity_sold, reorder_level, stock_value)
SELECT d.date_key,
       p.product_key,
       r.region_key,
       i.quantity_on_hand,
       i.quantity_received,
       i.quantity_sold,
       i.reorder_level,
       ROUND(i.quantity_on_hand * p.unit_cost, 2)
FROM project_staging.stg_inventory_clean i
JOIN dim_date    d ON d.full_date  = i.snapshot_date
JOIN dim_product p ON p.product_id = i.product_id
JOIN dim_region  r ON r.region_id  = i.region_id
ON CONFLICT (date_key, product_key, region_key) DO NOTHING;

-- promotion events: one row per product, promotion and active day
-- (no measures here, the row itself is the fact)
INSERT INTO fact_promotion_event (date_key, product_key, promotion_key)
SELECT d.date_key,
       p.product_key,
       dp.promotion_key
FROM project_staging.stg_promotion_product_clean pp
JOIN dim_promotion dp ON dp.promotion_id = pp.promotion_id
JOIN dim_product   p  ON p.product_id    = pp.product_id
JOIN dim_date      d  ON d.full_date BETWEEN dp.start_date AND dp.end_date
ON CONFLICT (date_key, product_key, promotion_key) DO NOTHING;

-- save the fact row counts for the re-run check
INSERT INTO project_staging.etl_row_counts (batch_id, step, object_name, row_count)
SELECT (SELECT MAX(batch_id) FROM project_staging.etl_batch), 'dw_load', t.name, t.n
FROM (
    SELECT 'fact_sales' AS name, COUNT(*) AS n FROM fact_sales UNION ALL
    SELECT 'fact_inventory_snapshot', COUNT(*) FROM fact_inventory_snapshot UNION ALL
    SELECT 'fact_promotion_event', COUNT(*) FROM fact_promotion_event
) t;

-- row counts and totals
SELECT 'fact_sales' AS fact_table, COUNT(*) AS rows, SUM(net_revenue) AS net_revenue FROM fact_sales UNION ALL
SELECT 'fact_inventory_snapshot', COUNT(*), SUM(stock_value) FROM fact_inventory_snapshot UNION ALL
SELECT 'fact_promotion_event', COUNT(*), NULL FROM fact_promotion_event;

-- sanity check: first 3 sales lines, business key next to surrogate key
SELECT f.order_id,
       f.order_line_number,
       c.customer_id AS business_key_customer,
       f.customer_key AS surrogate_customer_key,
       p.product_id  AS business_key_product,
       f.product_key  AS surrogate_product_key,
       f.net_revenue
FROM fact_sales f
JOIN dim_customer c ON c.customer_key = f.customer_key
JOIN dim_product  p ON p.product_key  = f.product_key
ORDER BY f.sales_key
LIMIT 3;