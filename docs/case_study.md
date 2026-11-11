# Case Study: AtliQ Mart Supply Chain — Delivery Performance Analysis

## The problem

AtliQ Mart, a fast-growing FMCG distributor operating across Gujarat, India, was losing
customer contracts. Leadership suspected poor delivery performance but had no daily
visibility into where or why orders were failing. I was given six months of raw order data
(31,729 orders, 57,096 order lines, 35 customers, 18 products) and asked to find out.

## Approach

I treated this as an end-to-end analytics engagement rather than a single dashboard:

1. **Data engineering** — designed a MySQL star schema from scratch (`sql/00_schema_mysql.sql`):
   2 fact tables at different grains (order-line and order-level), 4 dimension tables, proper
   foreign keys and indexes on every join column. Built a Python ETL (`python/etl_load_mysql.py`)
   to clean and load the source CSVs, which had two different date formats and inconsistent
   category casing — both caught during data-quality checks and fixed at load time.
2. **SQL analysis** — 14 business questions (`sql/03_business_questions.sql`) covering
   headline OT/IF/OTIF rates, per-customer and per-city performance, product fill rates, and
   trend analysis, all using CTEs and window functions (`NTILE`, `LAG`, `DENSE_RANK`). MySQL
   has no `PERCENTILE_CONT`, so I implemented the median delivery-delay calculation manually
   with a `ROW_NUMBER`/midpoint trick — a good example of adapting a technique across SQL
   dialects rather than only knowing one.
3. **Original analysis beyond the brief** (`sql/04_original_analysis.sql`) — four questions
   nobody asked me to answer:
   - Does day-of-week affect delivery reliability? *(No — under 1.5 points of variation.)*
   - Does order size predict OTIF failure? *(No net effect — on-time% rises with size while
     in-full% falls, roughly cancelling out.)*
   - An RFM-style composite risk score (Frequency + Reliability + Recency) extending the
     "top 5 at-risk customers" finding into a full ranked segmentation of all 35 customers.
   - An illustrative revenue-at-risk estimate from the volume shortfall, using clearly-labeled
     assumed unit prices since the dataset has no price column — a transparent way to
     demonstrate business-impact quantification without fabricating a real financial figure.
4. **Python layer** (`python/`) — three notebooks going past what SQL comfortably expresses:
   a city×category heatmap and correlation check, a machine-learning model testing whether
   OTIF failure is predictable at order-intake time (it isn't — ROC-AUC ~0.53 even after
   balancing classes, which is itself the finding), and a Holt-Winters forecast projecting
   the 29% OTIF rate stays flat for the next month absent intervention.
5. **Power BI dashboard** (`powerbi/`) — rebuilt the data model and 30 DAX measures from
   scratch, connected live to MySQL, across 4 report pages (one more than the original: a
   dedicated diagnostics page for the day-of-week/order-size/forecast findings).

## Key findings

- **OTIF is 29.0%** against a 65.9% average target (individually set per customer, ranging
  49-75%) — a 36.9-point gap on average, and the primary driver of contract losses.
- **On-Time is 59.0%, In-Full is 52.8%** — both are broken, not just one.
- **Volume Fill Rate is strong (~96%) but Line Fill Rate is weak (<68%)** — the company
  delivers *most units* correctly but rarely delivers a full order complete, meaning the
  shortfall is spread thin across many orders rather than concentrated.
- **Dairy accounts for a 360,470-unit shortfall**, the largest of any category.
- **5 high-volume customers sit under 10% OTIF** and are named specifically for retention
  outreach; the composite risk score extends this to a full-book prioritization.
- **The problem is structural, not situational** — it doesn't vary meaningfully by day of
  week or order size, and a predictive model finds no learnable pattern in which orders fail.
  That rules out "smarter order intake" as a fix and points squarely at fulfillment capacity
  and inventory management.

## Takeaways

**Methods used:** SQL (schema design, CTEs, window functions, adapting a technique across
dialects), Python (pandas ETL, scikit-learn, statsmodels), and Power BI (data modeling, DAX,
dashboard design).

**The negative results matter as much as the positive ones.** Day-of-week and order size turn
out not to matter, and a classifier cannot predict which orders will fail. Both are actionable:
they show where *not* to spend effort (a smarter order-screening system) and where to spend it
(warehouse and inventory operations).
