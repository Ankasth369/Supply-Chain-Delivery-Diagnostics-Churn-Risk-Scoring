-- =========================================================================================
-- ATLIQ MART SUPPLY CHAIN ANALYSIS — MySQL Schema
-- =========================================================================================
-- Engine   : MySQL 8.0
-- Purpose  : Star schema for delivery-performance analysis (OT / IF / OTIF / VOFR / LIFR)
-- Notes    : Rebuilt from the original SQL Server design as a proper MySQL star schema —
--            explicit keys, foreign keys, and indexes on every join/filter column.
-- =========================================================================================

DROP DATABASE IF EXISTS atliq_mart_supplychain;
CREATE DATABASE atliq_mart_supplychain CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;
USE atliq_mart_supplychain;

-- -----------------------------------------------------------------------------------------
-- DIMENSION: customers
-- -----------------------------------------------------------------------------------------
CREATE TABLE dim_customers (
    customer_id     INT             NOT NULL,
    customer_name   VARCHAR(100)    NOT NULL,
    city            VARCHAR(50)     NOT NULL,
    PRIMARY KEY (customer_id)
) ENGINE = InnoDB;

-- -----------------------------------------------------------------------------------------
-- DIMENSION: products
-- -----------------------------------------------------------------------------------------
CREATE TABLE dim_products (
    product_id      BIGINT          NOT NULL,
    product_name    VARCHAR(100)    NOT NULL,
    category        VARCHAR(50)     NOT NULL,
    PRIMARY KEY (product_id)
) ENGINE = InnoDB;

-- -----------------------------------------------------------------------------------------
-- DIMENSION: date
-- day_name / is_weekend are generated columns — not in the source CSV, added so the
-- day-of-week delay analysis (sql/04_original_analysis.sql) doesn't need to compute
-- them ad hoc on every query.
-- -----------------------------------------------------------------------------------------
CREATE TABLE dim_date (
    calendar_date   DATE            NOT NULL,
    mmm_yy          VARCHAR(10)     NOT NULL,
    week_no         VARCHAR(10)     NOT NULL,
    day_name        VARCHAR(10)     GENERATED ALWAYS AS (DAYNAME(calendar_date)) STORED,
    is_weekend      TINYINT(1)      GENERATED ALWAYS AS (DAYOFWEEK(calendar_date) IN (1, 7)) STORED,
    PRIMARY KEY (calendar_date)
) ENGINE = InnoDB;

-- -----------------------------------------------------------------------------------------
-- DIMENSION: per-customer service-level targets
-- -----------------------------------------------------------------------------------------
CREATE TABLE dim_targets_orders (
    customer_id             INT             NOT NULL,
    ontime_target_pct       DECIMAL(5,2)    NOT NULL,
    infull_target_pct       DECIMAL(5,2)    NOT NULL,
    otif_target_pct         DECIMAL(5,2)    NOT NULL,
    PRIMARY KEY (customer_id),
    CONSTRAINT fk_targets_customer
        FOREIGN KEY (customer_id) REFERENCES dim_customers (customer_id)
) ENGINE = InnoDB;

-- -----------------------------------------------------------------------------------------
-- FACT: order line items (grain = one row per order + product)
-- -----------------------------------------------------------------------------------------
CREATE TABLE fact_order_lines (
    order_id                VARCHAR(20)     NOT NULL,
    product_id              BIGINT          NOT NULL,
    customer_id             INT             NOT NULL,
    order_placement_date    DATE            NOT NULL,
    agreed_delivery_date    DATE            NOT NULL,
    actual_delivery_date    DATE            NOT NULL,
    order_qty               INT             NOT NULL,
    delivery_qty             INT             NOT NULL,
    in_full                 TINYINT(1)      NOT NULL,
    on_time                 TINYINT(1)      NOT NULL,
    on_time_in_full         TINYINT(1)      NOT NULL,
    PRIMARY KEY (order_id, product_id),
    CONSTRAINT fk_lines_customer
        FOREIGN KEY (customer_id) REFERENCES dim_customers (customer_id),
    CONSTRAINT fk_lines_product
        FOREIGN KEY (product_id) REFERENCES dim_products (product_id),
    INDEX idx_lines_customer (customer_id),
    INDEX idx_lines_product (product_id),
    INDEX idx_lines_order_date (order_placement_date)
) ENGINE = InnoDB;

-- -----------------------------------------------------------------------------------------
-- FACT: order-level aggregate (grain = one row per order)
-- -----------------------------------------------------------------------------------------
CREATE TABLE fact_orders_aggregate (
    order_id                VARCHAR(20)     NOT NULL,
    customer_id             INT             NOT NULL,
    order_placement_date    DATE            NOT NULL,
    on_time                 TINYINT(1)      NOT NULL,
    in_full                 TINYINT(1)      NOT NULL,
    otif                    TINYINT(1)      NOT NULL,
    PRIMARY KEY (order_id),
    CONSTRAINT fk_agg_customer
        FOREIGN KEY (customer_id) REFERENCES dim_customers (customer_id),
    INDEX idx_agg_customer (customer_id),
    INDEX idx_agg_order_date (order_placement_date)
) ENGINE = InnoDB;
