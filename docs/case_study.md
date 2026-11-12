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
   - Does order size predict OTIF failure? *(No net effect on OTIF — but on-time% rises with
     size (44% to 87%) while in-full% falls (63% to 33%), so size changes the type of failure.)*
   - An RFM-style composite risk score (Frequency + Reliability + Recency) extending the
     "top 5 at-risk customers" finding into a full ranked segmentation of all 35 customers
     (11 land in the Critical segment). Recency adds little here, since 34 of 35 customers
     ordered on the last day of data, so the score is driven by frequency and reliability.
   - An illustrative revenue-at-risk estimate from the volume shortfall, using clearly-labeled
     assumed unit prices since the dataset has no price column — a transparent way to
     demonstrate business-impact quantification without fabricating a real financial figure.
4. **Python layer** (`python/`) — three notebooks going past what SQL comfortably expresses:
   a city×category heatmap, a correlation check and a customer breakdown; a machine-learning
   model testing whether OTIF failure is predictable at order time (from order attributes
   alone it is not: ROC-AUC ≈ 0.52–0.53; adding customer identity lifts it to ≈ 0.66–0.67);
   and a Holt linear-trend forecast projecting the 29% OTIF rate stays flat for the next
   month (a backtest shows the trend term adds nothing over the historical mean).
5. **Power BI dashboard** (`powerbi/`) — rebuilt the data model and 30 DAX measures from
   scratch, connected live to MySQL, across 4 report pages (one more than the original: a
   dedicated diagnostics page for the day-of-week/order-size/forecast findings).

## Key findings

- **OTIF is 29.0%** against a 65.9% average target (individually set per customer, ranging
  49-75%) — a 36.9-point gap on average, and the primary driver of contract losses.
- **On-Time is 59.0%, In-Full is 52.8%** — both are broken, not just one.
- **Volume Fill Rate is strong (96.6%) but Line Fill Rate is weak (66.0%)** — the company
  delivers *most units* correctly but rarely delivers a full order complete. A short line is
  about 10% short on average, so the shortfall is many small misses rather than a few large ones.
- **Dairy has the largest shortfall in absolute terms** (360,470 of 457,779 missing units,
  about 79%) because it is two-thirds of all order lines. Its fill rate (96.6%) matches Food
  and Beverages, so Dairy is where the volume is, not a worse performer.
- **5 customers sit under 10% OTIF** (three of them among the largest accounts) and are named
  for retention outreach; the composite risk score extends this to a full-book prioritization.
- **The customer matters more than the order.** Product, city, week and day of week each vary
  by only a few points, and order size shifts the type of failure without changing OTIF. By
  customer, OTIF ranges from 7% to 42%. The 8 largest customers (30% of orders) are at 15%
  versus 35% for the other 27, with two distinct patterns: late deliveries at the large
  accounts, and incomplete deliveries at seven customers. A classifier using only order
  attributes is close to chance (ROC-AUC ≈ 0.52–0.53); adding the customer lifts it to
  ≈ 0.66–0.67. The dataset has no inventory, warehouse or transport fields, so the root cause
  inside operations is a hypothesis, not a finding.

## Recommendations and next steps

**Supported by the data:**

1. **Work customer by customer.** OTIF varies far more across customers (7% to 42%) than
   across products, cities, weekdays or order sizes. Review fulfillment for the large accounts
   (late deliveries) and the seven customers with very low in-full rates first.
2. **Prioritize retention outreach.** Contact the 5 customers below 10% OTIF first, then work
   down the composite risk ranking of all 35 customers.
3. **Dairy recovers the most units.** It holds about 79% of the missing units, so fixes there
   recover the most volume, even though its fill rate is the same as the other categories.
4. **Don't expect order-screening rules to help.** City, order size, line count and weekday
   carry almost no signal about which orders fail (ROC-AUC ≈ 0.52–0.53).
5. **Do not expect self-correction.** The forecast holds OTIF flat near 29% without
   intervention.

**Needs more data before acting:**

- *Root cause inside operations:* the dataset has no inventory, warehouse, dispatch or transport
  fields, so it cannot say whether failures come from stock-outs, picking, or logistics.
  Inventory levels, supplier lead times and dispatch timestamps would be the first additions.
- *Financial impact:* the revenue-at-risk figure uses assumed unit prices and is illustrative.
  Real prices and contract values are needed for a decision-grade estimate.
- *Validation:* pilot fixes on Dairy and the highest-risk customers, and track weekly OTIF in
  the dashboard to confirm whether the gap closes.

## Takeaways

**Methods used:** SQL (schema design, CTEs, window functions, adapting a technique across
dialects), Python (pandas ETL, scikit-learn, statsmodels), and Power BI (data modeling, DAX,
dashboard design).

**The negative results matter as much as the positive ones.** Day of week does not matter,
order size shifts the type of failure but not OTIF, and order attributes alone cannot predict
which orders fail. These show where *not* to spend effort (order-screening rules) and point to
customer-specific fulfillment problems. The data cannot say whether the cause is inventory,
warehouse capacity or transport, which is the first thing to find out.
