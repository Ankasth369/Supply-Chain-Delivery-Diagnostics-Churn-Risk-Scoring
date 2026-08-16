-- =========================================================================================
-- ATLIQ MART SUPPLY CHAIN — EXPLORATORY DATA ANALYSIS & DATA QUALITY (MySQL 8.0)
-- =========================================================================================
USE atliq_mart_supplychain;

-- -----------------------------------------------------------------------------------------
-- 1. Table sizes and coverage window
-- -----------------------------------------------------------------------------------------
SELECT 'dim_customers' AS table_name, COUNT(*) AS row_count FROM dim_customers
UNION ALL SELECT 'dim_products', COUNT(*) FROM dim_products
UNION ALL SELECT 'dim_date', COUNT(*) FROM dim_date
UNION ALL SELECT 'dim_targets_orders', COUNT(*) FROM dim_targets_orders
UNION ALL SELECT 'fact_order_lines', COUNT(*) FROM fact_order_lines
UNION ALL SELECT 'fact_orders_aggregate', COUNT(*) FROM fact_orders_aggregate;

SELECT
    MIN(order_placement_date)                                              AS first_order_date,
    MAX(order_placement_date)                                              AS last_order_date,
    DATEDIFF(MAX(order_placement_date), MIN(order_placement_date)) + 1     AS days_covered
FROM fact_orders_aggregate;

-- -----------------------------------------------------------------------------------------
-- 2. Null checks on every column that should never be null
-- -----------------------------------------------------------------------------------------
SELECT
    COUNT(*)                                           AS total_rows,
    SUM(customer_id   IS NULL)                         AS null_customer_id,
    SUM(customer_name IS NULL)                         AS null_customer_name,
    SUM(city          IS NULL)                         AS null_city
FROM dim_customers;

SELECT
    COUNT(*)                                           AS total_rows,
    SUM(order_id                IS NULL)                AS null_order_id,
    SUM(product_id               IS NULL)               AS null_product_id,
    SUM(order_qty                IS NULL)               AS null_order_qty,
    SUM(delivery_qty             IS NULL)               AS null_delivery_qty,
    SUM(agreed_delivery_date     IS NULL)               AS null_agreed_date,
    SUM(actual_delivery_date     IS NULL)               AS null_actual_date
FROM fact_order_lines;

-- -----------------------------------------------------------------------------------------
-- 3. Duplicate / uniqueness checks
-- -----------------------------------------------------------------------------------------
-- Same customer name+city under more than one customer_id
SELECT customer_name, city, COUNT(DISTINCT customer_id) AS id_variants
FROM dim_customers
GROUP BY customer_name, city
HAVING COUNT(DISTINCT customer_id) > 1;

-- Duplicate order+product lines (should be none — that's the fact grain)
SELECT order_id, product_id, COUNT(*) AS dup_count
FROM fact_order_lines
GROUP BY order_id, product_id
HAVING COUNT(*) > 1;

-- -----------------------------------------------------------------------------------------
-- 3b. Category casing is inconsistent in the source CSV ('Dairy', 'Food', 'beverages') —
--     found here, fixed below, and mirrored in python/etl_load_mysql.py so a fresh load
--     stays clean.
-- -----------------------------------------------------------------------------------------
SELECT DISTINCT category FROM dim_products;

UPDATE dim_products
SET category = CONCAT(UPPER(LEFT(category, 1)), LOWER(SUBSTRING(category, 2)))
WHERE category <> CONCAT(UPPER(LEFT(category, 1)), LOWER(SUBSTRING(category, 2)));

-- -----------------------------------------------------------------------------------------
-- 4. Referential integrity — orphan rows that reference a missing dimension key
-- -----------------------------------------------------------------------------------------
SELECT COUNT(*) AS orphan_products_in_lines
FROM fact_order_lines fol
LEFT JOIN dim_products p ON p.product_id = fol.product_id
WHERE p.product_id IS NULL;

SELECT COUNT(*) AS orphan_customers_in_orders
FROM fact_orders_aggregate foa
LEFT JOIN dim_customers c ON c.customer_id = foa.customer_id
WHERE c.customer_id IS NULL;

-- -----------------------------------------------------------------------------------------
-- 5. Date-logic sanity check — agreed delivery date can never precede the order date
-- -----------------------------------------------------------------------------------------
SELECT order_id, product_id, order_placement_date, agreed_delivery_date
FROM fact_order_lines
WHERE agreed_delivery_date < order_placement_date;

-- -----------------------------------------------------------------------------------------
-- 6. Cross-table consistency — order counts must match between the line-item and
--    order-level fact tables (they're two grains of the same source data)
-- -----------------------------------------------------------------------------------------
SELECT
    (SELECT COUNT(DISTINCT order_id) FROM fact_order_lines)      AS distinct_orders_in_lines,
    (SELECT COUNT(*)                 FROM fact_orders_aggregate) AS orders_in_aggregate,
    (SELECT COUNT(DISTINCT order_id) FROM fact_order_lines)
        - (SELECT COUNT(*) FROM fact_orders_aggregate)           AS difference;

-- -----------------------------------------------------------------------------------------
-- 7. Executive snapshot — one-query business overview
-- -----------------------------------------------------------------------------------------
SELECT
    (SELECT COUNT(*) FROM dim_customers)                                              AS total_customers,
    (SELECT COUNT(DISTINCT city) FROM dim_customers)                                  AS total_cities,
    (SELECT COUNT(*) FROM dim_products)                                               AS total_products,
    (SELECT COUNT(DISTINCT category) FROM dim_products)                               AS total_categories,
    (SELECT COUNT(*) FROM fact_orders_aggregate)                                      AS total_orders,
    ROUND(100 * (SELECT AVG(on_time) FROM fact_orders_aggregate), 2)                  AS ontime_pct,
    ROUND(100 * (SELECT AVG(in_full) FROM fact_orders_aggregate), 2)                  AS infull_pct,
    ROUND(100 * (SELECT AVG(otif)    FROM fact_orders_aggregate), 2)                  AS otif_pct;
