-- Reporting views over the star schema (read by Power BI); each answers one or more business questions.
SET search_path = project_reporting;

-- Q1  Monthly net revenue and profit trend
CREATE OR REPLACE VIEW vw_monthly_sales AS
SELECT d.year, d.month_number, d.month_name,
       SUM(f.net_revenue)  AS net_revenue,
       SUM(f.profit_amount) AS profit,
       SUM(f.quantity)     AS units_sold,
       COUNT(DISTINCT f.order_id) AS orders
FROM project_dw.fact_sales f
JOIN project_dw.dim_date d ON d.date_key = f.date_key
GROUP BY d.year, d.month_number, d.month_name;

-- Q2  Products and categories with the highest revenue
CREATE OR REPLACE VIEW vw_product_sales AS
SELECT p.product_id, p.product_name, p.category, p.subcategory, p.brand,
       SUM(f.net_revenue) AS net_revenue,
       SUM(f.quantity)    AS units_sold,
       SUM(f.profit_amount) AS profit
FROM project_dw.fact_sales f
JOIN project_dw.dim_product p ON p.product_key = f.product_key
GROUP BY p.product_id, p.product_name, p.category, p.subcategory, p.brand;

-- Q3  Regions that perform well or badly (by year)
CREATE OR REPLACE VIEW vw_region_sales AS
SELECT r.city, r.province, r.region_zone, d.year,
       SUM(f.net_revenue) AS net_revenue,
       SUM(f.quantity)    AS units_sold,
       COUNT(DISTINCT f.order_id) AS orders
FROM project_dw.fact_sales f
JOIN project_dw.dim_region r ON r.region_key = f.region_key
JOIN project_dw.dim_date   d ON d.date_key   = f.date_key
GROUP BY r.city, r.province, r.region_zone, d.year;

-- Q4  Best sales channel
CREATE OR REPLACE VIEW vw_channel_sales AS
SELECT ch.channel_name, ch.channel_type, d.year,
       SUM(f.net_revenue)   AS net_revenue,
       SUM(f.profit_amount) AS profit,
       COUNT(DISTINCT f.order_id) AS orders
FROM project_dw.fact_sales f
JOIN project_dw.dim_channel ch ON ch.channel_key = f.channel_key
JOIN project_dw.dim_date    d  ON d.date_key     = f.date_key
GROUP BY ch.channel_name, ch.channel_type, d.year;

-- Q5  Customer lifetime value
CREATE OR REPLACE VIEW vw_customer_lifetime_value AS
SELECT c.customer_id, c.customer_name, c.customer_segment,
       COUNT(DISTINCT f.order_id) AS orders,
       SUM(f.net_revenue)   AS lifetime_revenue,
       SUM(f.profit_amount) AS lifetime_profit
FROM project_dw.fact_sales f
JOIN project_dw.dim_customer c ON c.customer_key = f.customer_key
GROUP BY c.customer_id, c.customer_name, c.customer_segment;

-- Q6, Q7  How often each segment buys and average order value
CREATE OR REPLACE VIEW vw_segment_summary AS
SELECT c.customer_segment,
       COUNT(DISTINCT c.customer_key)  AS customers,
       COUNT(DISTINCT f.order_id)      AS orders,
       SUM(f.net_revenue)              AS net_revenue,
       ROUND(SUM(f.net_revenue) / COUNT(DISTINCT f.order_id), 2)           AS avg_order_value,
       ROUND(COUNT(DISTINCT f.order_id)::numeric / COUNT(DISTINCT c.customer_key), 2) AS orders_per_customer
FROM project_dw.fact_sales f
JOIN project_dw.dim_customer c ON c.customer_key = f.customer_key
GROUP BY c.customer_segment;

-- Q8  Products with declining demand (units per quarter)
CREATE OR REPLACE VIEW vw_product_demand_trend AS
SELECT p.product_id, p.product_name, d.year, d.quarter,
       SUM(f.quantity) AS units_sold
FROM project_dw.fact_sales f
JOIN project_dw.dim_product p ON p.product_key = f.product_key
JOIN project_dw.dim_date    d ON d.date_key    = f.date_key
GROUP BY p.product_id, p.product_name, d.year, d.quarter;

-- Q9  Products below reorder level (latest snapshot)
CREATE OR REPLACE VIEW vw_low_stock AS
SELECT p.product_id, p.product_name, r.city,
       i.quantity_on_hand, i.reorder_level
FROM project_dw.fact_inventory_snapshot i
JOIN project_dw.dim_product p ON p.product_key = i.product_key
JOIN project_dw.dim_region  r ON r.region_key  = i.region_key
WHERE i.date_key = (SELECT MAX(date_key) FROM project_dw.fact_inventory_snapshot)
  AND i.quantity_on_hand <= i.reorder_level;

-- Q10 Stock value by region (latest snapshot)
CREATE OR REPLACE VIEW vw_stock_value_by_region AS
SELECT r.city, r.province,
       SUM(i.quantity_on_hand) AS units_in_stock,
       SUM(i.stock_value)      AS stock_value
FROM project_dw.fact_inventory_snapshot i
JOIN project_dw.dim_region r ON r.region_key = i.region_key
WHERE i.date_key = (SELECT MAX(date_key) FROM project_dw.fact_inventory_snapshot)
GROUP BY r.city, r.province;

-- Q11 Which promotions raise sales
CREATE OR REPLACE VIEW vw_promotion_sales AS
SELECT pr.promotion_id, pr.promotion_name, pr.promotion_type, pr.discount_percent,
       COUNT(*)              AS order_lines,
       SUM(f.quantity)       AS units_sold,
       SUM(f.net_revenue)    AS net_revenue,
       SUM(f.discount_amount) AS discount_given
FROM project_dw.fact_sales f
JOIN project_dw.dim_promotion pr ON pr.promotion_key = f.promotion_key
GROUP BY pr.promotion_id, pr.promotion_name, pr.promotion_type, pr.discount_percent;

-- Q12 Products on promotion most often (factless fact: just count rows)
CREATE OR REPLACE VIEW vw_product_promotion_days AS
SELECT p.product_id, p.product_name,
       COUNT(*) AS promotion_days,
       COUNT(DISTINCT e.promotion_key) AS promotions
FROM project_dw.fact_promotion_event e
JOIN project_dw.dim_product p ON p.product_key = e.product_key
GROUP BY p.product_id, p.product_name;

SELECT table_name AS reporting_view FROM information_schema.views
WHERE table_schema = 'project_reporting' ORDER BY table_name;
