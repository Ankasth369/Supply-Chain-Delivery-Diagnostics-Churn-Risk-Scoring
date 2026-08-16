-- =========================================================================================
-- ATLIQ MART SUPPLY CHAIN — BUSINESS QUESTIONS (MySQL 8.0)
-- Rebuilt independently in MySQL syntax: LIMIT instead of TOP, DATEDIFF(end, start) argument
-- order, CTEs + window functions throughout, and a manual median (MySQL has no
-- PERCENTILE_CONT) using the ROW_NUMBER/COUNT split-point trick.
-- =========================================================================================
USE atliq_mart_supplychain;

-- -----------------------------------------------------------------------------------------
-- Q1. Which products get ordered most often, and what share of all order lines is that?
-- -----------------------------------------------------------------------------------------
SELECT
    p.product_name,
    p.category,
    COUNT(*)                                                       AS order_lines,
    ROUND(100 * COUNT(*) / SUM(COUNT(*)) OVER (), 2)               AS pct_of_all_lines
FROM fact_order_lines fol
JOIN dim_products p ON p.product_id = fol.product_id
GROUP BY p.product_id, p.product_name, p.category
ORDER BY order_lines DESC;

-- -----------------------------------------------------------------------------------------
-- Q2. Which customers place the most orders?
-- -----------------------------------------------------------------------------------------
SELECT
    c.customer_name,
    c.city,
    COUNT(*)                                                       AS total_orders,
    ROUND(100 * COUNT(*) / SUM(COUNT(*)) OVER (), 2)               AS pct_of_all_orders
FROM fact_orders_aggregate foa
JOIN dim_customers c ON c.customer_id = foa.customer_id
GROUP BY c.customer_id, c.customer_name, c.city
ORDER BY total_orders DESC;

-- -----------------------------------------------------------------------------------------
-- Q3. Category performance — volume ordered vs delivered, and the Volume Fill Rate (VOFR%)
-- -----------------------------------------------------------------------------------------
SELECT
    p.category,
    COUNT(*)                                                       AS order_lines,
    SUM(fol.order_qty)                                             AS qty_ordered,
    SUM(fol.delivery_qty)                                          AS qty_delivered,
    SUM(fol.order_qty) - SUM(fol.delivery_qty)                     AS qty_shortfall,
    ROUND(100 * SUM(fol.delivery_qty) / SUM(fol.order_qty), 2)     AS volume_fill_rate_pct
FROM fact_order_lines fol
JOIN dim_products p ON p.product_id = fol.product_id
GROUP BY p.category
ORDER BY qty_shortfall DESC;

-- -----------------------------------------------------------------------------------------
-- Q4. Headline OT / IF / OTIF performance
-- -----------------------------------------------------------------------------------------
SELECT
    COUNT(*)                                                       AS total_orders,
    SUM(on_time)                                                   AS on_time_orders,
    ROUND(100 * AVG(on_time), 2)                                   AS on_time_pct,
    SUM(in_full)                                                   AS in_full_orders,
    ROUND(100 * AVG(in_full), 2)                                   AS in_full_pct,
    SUM(otif)                                                      AS otif_orders,
    ROUND(100 * AVG(otif), 2)                                      AS otif_pct
FROM fact_orders_aggregate;

-- -----------------------------------------------------------------------------------------
-- Q5. Monthly order volume and month-over-month growth
-- -----------------------------------------------------------------------------------------
WITH monthly AS (
    SELECT
        DATE_SUB(order_placement_date, INTERVAL DAY(order_placement_date) - 1 DAY) AS month_start,
        COUNT(*) AS total_orders
    FROM fact_orders_aggregate
    GROUP BY month_start
)
SELECT
    DATE_FORMAT(month_start, '%b %Y')                              AS order_month,
    total_orders,
    ROUND(100 * (total_orders - LAG(total_orders) OVER (ORDER BY month_start))
        / LAG(total_orders) OVER (ORDER BY month_start), 2)        AS mom_change_pct
FROM monthly
ORDER BY month_start;

-- -----------------------------------------------------------------------------------------
-- Q6. How late are the late deliveries? (avg / min / max / median delay in days)
-- MySQL has no PERCENTILE_CONT, so the median is computed manually: rank the delays and
-- average the one or two values sitting at the midpoint.
-- -----------------------------------------------------------------------------------------
WITH order_delay AS (
    SELECT
        order_id,
        MAX(DATEDIFF(actual_delivery_date, agreed_delivery_date)) AS delay_days
    FROM fact_order_lines
    WHERE actual_delivery_date > agreed_delivery_date
    GROUP BY order_id
),
ranked AS (
    SELECT
        delay_days,
        ROW_NUMBER() OVER (ORDER BY delay_days) AS rn,
        COUNT(*)     OVER ()                    AS n
    FROM order_delay
)
SELECT
    (SELECT ROUND(AVG(delay_days), 2) FROM order_delay)            AS avg_delay_days,
    (SELECT MIN(delay_days) FROM order_delay)                      AS min_delay_days,
    (SELECT MAX(delay_days) FROM order_delay)                      AS max_delay_days,
    (SELECT AVG(delay_days) FROM ranked
        WHERE rn IN (FLOOR((n + 1) / 2), CEIL((n + 1) / 2)))       AS median_delay_days;

-- -----------------------------------------------------------------------------------------
-- Q7. Per-customer OT / IF / OTIF% with a performance tier
-- -----------------------------------------------------------------------------------------
SELECT
    c.customer_name,
    c.city,
    COUNT(*)                                                       AS total_orders,
    ROUND(100 * AVG(foa.on_time), 2)                               AS on_time_pct,
    ROUND(100 * AVG(foa.in_full), 2)                                AS in_full_pct,
    ROUND(100 * AVG(foa.otif), 2)                                   AS otif_pct,
    CASE
        WHEN 100 * AVG(foa.otif) >= 85 THEN 'Excellent'
        WHEN 100 * AVG(foa.otif) >= 70 THEN 'Good'
        WHEN 100 * AVG(foa.otif) >= 50 THEN 'Poor'
        ELSE 'Critical'
    END                                                             AS performance_tier
FROM fact_orders_aggregate foa
JOIN dim_customers c ON c.customer_id = foa.customer_id
GROUP BY c.customer_id, c.customer_name, c.city
ORDER BY total_orders DESC;

-- -----------------------------------------------------------------------------------------
-- Q8. Which products have the highest rate of incomplete deliveries?
-- -----------------------------------------------------------------------------------------
SELECT
    p.product_name,
    p.category,
    COUNT(*)                                                       AS order_lines,
    ROUND(100 * (1 - AVG(fol.in_full)), 2)                         AS incomplete_delivery_pct
FROM fact_order_lines fol
JOIN dim_products p ON p.product_id = fol.product_id
GROUP BY p.product_id, p.product_name, p.category
ORDER BY incomplete_delivery_pct DESC;

-- -----------------------------------------------------------------------------------------
-- Q9. City-level delivery performance ranking
-- -----------------------------------------------------------------------------------------
SELECT
    c.city,
    ROUND(100 * AVG(foa.on_time), 2)                               AS on_time_pct,
    ROUND(100 * AVG(foa.in_full), 2)                                AS in_full_pct,
    ROUND(100 * AVG(foa.otif), 2)                                   AS otif_pct,
    DENSE_RANK() OVER (ORDER BY AVG(foa.otif) DESC)                AS city_rank
FROM fact_orders_aggregate foa
JOIN dim_customers c ON c.customer_id = foa.customer_id
GROUP BY c.city
ORDER BY otif_pct DESC;

-- -----------------------------------------------------------------------------------------
-- Q10. Weekly OTIF% trend, with week-over-week change
-- -----------------------------------------------------------------------------------------
WITH weekly AS (
    SELECT
        d.week_no,
        MIN(d.calendar_date)                                       AS week_start,
        ROUND(100 * AVG(foa.otif), 2)                              AS otif_pct
    FROM dim_date d
    JOIN fact_orders_aggregate foa ON foa.order_placement_date = d.calendar_date
    GROUP BY d.week_no
)
SELECT
    week_no,
    otif_pct,
    ROUND(otif_pct - LAG(otif_pct) OVER (ORDER BY week_start), 2)  AS wow_change_pct_points
FROM weekly
ORDER BY week_start;

-- -----------------------------------------------------------------------------------------
-- Q11. Top 5 churn-risk customers: high order volume, lowest OTIF%
-- -----------------------------------------------------------------------------------------
SELECT
    c.customer_name,
    c.city,
    COUNT(*)                                                       AS total_orders,
    ROUND(100 * AVG(foa.otif), 2)                                  AS otif_pct
FROM fact_orders_aggregate foa
JOIN dim_customers c ON c.customer_id = foa.customer_id
GROUP BY c.customer_id, c.customer_name, c.city
ORDER BY otif_pct ASC, total_orders DESC
LIMIT 5;

-- -----------------------------------------------------------------------------------------
-- Q12. Top 5 high-volume products with the lowest line fill rate (IF%)
-- -----------------------------------------------------------------------------------------
SELECT
    p.product_name,
    SUM(fol.order_qty)                                             AS qty_ordered,
    COUNT(*)                                                       AS order_lines,
    ROUND(100 * AVG(fol.in_full), 2)                                AS line_fill_rate_pct
FROM fact_order_lines fol
JOIN dim_products p ON p.product_id = fol.product_id
GROUP BY p.product_id, p.product_name
ORDER BY line_fill_rate_pct ASC, qty_ordered DESC
LIMIT 5;

-- -----------------------------------------------------------------------------------------
-- Q13. For each city, which product category has the worst on-time rate?
-- -----------------------------------------------------------------------------------------
WITH city_category AS (
    SELECT
        c.city,
        p.category,
        COUNT(*)                                                   AS order_lines,
        ROUND(100 * (1 - AVG(fol.on_time)), 2)                     AS delay_pct,
        DENSE_RANK() OVER (
            PARTITION BY c.city ORDER BY (1 - AVG(fol.on_time)) DESC
        )                                                           AS delay_rank
    FROM fact_order_lines fol
    JOIN dim_customers c ON c.customer_id = fol.customer_id
    JOIN dim_products p ON p.product_id = fol.product_id
    GROUP BY c.city, p.category
)
SELECT city, category AS worst_category, order_lines, delay_pct
FROM city_category
WHERE delay_rank = 1
ORDER BY delay_pct DESC;

-- -----------------------------------------------------------------------------------------
-- Q14. Actual vs target OT / IF / OTIF per customer, with a gap and pass/fail flag
-- -----------------------------------------------------------------------------------------
WITH customer_actuals AS (
    SELECT
        customer_id,
        ROUND(100 * AVG(on_time), 2)   AS actual_ontime_pct,
        ROUND(100 * AVG(in_full), 2)    AS actual_infull_pct,
        ROUND(100 * AVG(otif), 2)       AS actual_otif_pct,
        COUNT(*)                        AS total_orders
    FROM fact_orders_aggregate
    GROUP BY customer_id
)
SELECT
    c.customer_name,
    c.city,
    a.total_orders,
    a.actual_otif_pct,
    t.otif_target_pct,
    ROUND(a.actual_otif_pct - t.otif_target_pct, 2)                AS otif_gap_points,
    CASE WHEN a.actual_otif_pct >= t.otif_target_pct
         THEN 'Meets Target' ELSE 'Below Target' END               AS otif_status
FROM customer_actuals a
JOIN dim_customers c ON c.customer_id = a.customer_id
JOIN dim_targets_orders t ON t.customer_id = a.customer_id
ORDER BY otif_gap_points ASC;
