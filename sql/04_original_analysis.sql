-- =========================================================================================
-- ATLIQ MART SUPPLY CHAIN — ORIGINAL ANALYSIS (not part of the original brief)
-- =========================================================================================
-- Four questions the original challenge didn't ask:
--   A. Does the day of the week an order is placed affect delivery reliability?
--   B. Does order size correlate with fulfillment performance?
--   C. An RFM-style composite risk score for churn prioritization (extends the
--      original "top 5 at-risk customers" question into a full ranked segmentation)
--   D. An illustrative revenue-at-risk estimate from the volume shortfall
-- =========================================================================================
USE atliq_mart_supplychain;

-- -----------------------------------------------------------------------------------------
-- A. Delivery reliability by day of week the order was PLACED
--    Uses the generated day_name column added to dim_date in 00_schema_mysql.sql.
-- -----------------------------------------------------------------------------------------
SELECT
    d.day_name,
    COUNT(*)                                                       AS orders,
    ROUND(100 * AVG(foa.on_time), 2)                               AS on_time_pct,
    ROUND(100 * AVG(foa.otif), 2)                                  AS otif_pct
FROM fact_orders_aggregate foa
JOIN dim_date d ON d.calendar_date = foa.order_placement_date
GROUP BY d.day_name
ORDER BY FIELD(d.day_name,
    'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday');

-- -----------------------------------------------------------------------------------------
-- B. Order-size bucket vs OTIF% — is a large order more likely to be short-shipped or late?
--    Buckets are set from the actual quartiles of order size (25th=177, median=360,
--    75th=558 units per order).
-- -----------------------------------------------------------------------------------------
WITH order_size AS (
    SELECT order_id, SUM(order_qty) AS total_qty
    FROM fact_order_lines
    GROUP BY order_id
)
SELECT
    CASE
        WHEN os.total_qty < 200 THEN '1. Small (<200 units)'
        WHEN os.total_qty < 400 THEN '2. Medium (200-399)'
        WHEN os.total_qty < 600 THEN '3. Large (400-599)'
        ELSE '4. X-Large (600+)'
    END                                                             AS order_size_bucket,
    COUNT(*)                                                        AS orders,
    ROUND(AVG(os.total_qty), 0)                                     AS avg_qty_in_bucket,
    ROUND(100 * AVG(foa.on_time), 2)                                AS on_time_pct,
    ROUND(100 * AVG(foa.in_full), 2)                                 AS in_full_pct,
    ROUND(100 * AVG(foa.otif), 2)                                    AS otif_pct
FROM order_size os
JOIN fact_orders_aggregate foa ON foa.order_id = os.order_id
GROUP BY order_size_bucket
ORDER BY order_size_bucket;

-- -----------------------------------------------------------------------------------------
-- C. RFM-style customer risk score — Frequency, Reliability (in place of Monetary, since
--    no price data exists), and Recency, combined into one composite risk tier.
--    This extends Task 11 (top-5 at-risk list) into a scored segmentation of ALL customers.
-- -----------------------------------------------------------------------------------------
WITH customer_stats AS (
    SELECT
        customer_id,
        COUNT(*)                                                    AS frequency,
        AVG(otif)                                                   AS otif_rate,
        DATEDIFF(
            (SELECT MAX(order_placement_date) FROM fact_orders_aggregate),
            MAX(order_placement_date)
        )                                                            AS days_since_last_order
    FROM fact_orders_aggregate
    GROUP BY customer_id
),
scored AS (
    SELECT
        cs.*,
        NTILE(4) OVER (ORDER BY frequency ASC)             AS value_tier,          -- 4 = highest order volume = most revenue exposure
        NTILE(4) OVER (ORDER BY otif_rate DESC)            AS reliability_risk,    -- 4 = lowest OTIF = highest service-failure risk
        NTILE(4) OVER (ORDER BY days_since_last_order ASC) AS recency_risk         -- 4 = longest gap since last order = early churn signal
    FROM customer_stats cs
)
SELECT
    c.customer_name,
    c.city,
    s.frequency                                                     AS total_orders,
    ROUND(100 * s.otif_rate, 2)                                     AS otif_pct,
    s.days_since_last_order,
    (s.value_tier + s.reliability_risk + s.recency_risk)            AS composite_risk_score,
    CASE
        WHEN (s.value_tier + s.reliability_risk + s.recency_risk) >= 10 THEN 'Critical — act this week'
        WHEN (s.value_tier + s.reliability_risk + s.recency_risk) >= 7  THEN 'High risk'
        WHEN (s.value_tier + s.reliability_risk + s.recency_risk) >= 4  THEN 'Monitor'
        ELSE 'Healthy'
    END                                                              AS risk_segment
FROM scored s
JOIN dim_customers c ON c.customer_id = s.customer_id
ORDER BY composite_risk_score DESC, total_orders DESC;

-- -----------------------------------------------------------------------------------------
-- D. Illustrative revenue-at-risk from the volume shortfall
--    The dataset has NO price/revenue column, so this uses a small, clearly-labeled
--    assumed price per category purely to demonstrate the technique — NOT a real AtliQ
--    Mart figure. Swap unit_price_assumed for actual price-list data in a real engagement.
-- -----------------------------------------------------------------------------------------
WITH assumed_unit_price AS (
    SELECT 'Dairy' AS category, 40 AS unit_price_assumed
    UNION ALL SELECT 'Food', 30
    UNION ALL SELECT 'Beverages', 50
),
category_shortfall AS (
    SELECT
        p.category,
        SUM(fol.order_qty) - SUM(fol.delivery_qty)                  AS qty_shortfall
    FROM fact_order_lines fol
    JOIN dim_products p ON p.product_id = fol.product_id
    GROUP BY p.category
)
SELECT
    cs.category,
    cs.qty_shortfall,
    aup.unit_price_assumed,
    cs.qty_shortfall * aup.unit_price_assumed                       AS illustrative_revenue_at_risk
FROM category_shortfall cs
JOIN assumed_unit_price aup ON aup.category = cs.category
ORDER BY illustrative_revenue_at_risk DESC;
