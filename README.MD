# AtliQ Mart Supply Chain Analysis

![MySQL](https://img.shields.io/badge/MySQL-4479A1?style=for-the-badge&logo=mysql&logoColor=white)
![Power BI](https://img.shields.io/badge/Power%20BI-F2C811?style=for-the-badge&logo=powerbi&logoColor=black)
![Python](https://img.shields.io/badge/Python-3776AB?style=for-the-badge&logo=python&logoColor=white)

> End-to-end supply-chain delivery-performance analysis: MySQL schema + ETL → SQL diagnostics
> → Python (EDA, ML, forecasting) → Power BI dashboard.

## About this project

This project analyzes six months of synthetic order data for AtliQ Mart, a fictional FMCG distributor
(dataset and business brief originally provided by [Codebasics](https://codebasics.io/) as a
resume-project challenge). It's been rebuilt from the ground up as a MySQL + Python + Power BI
pipeline, going beyond the original brief with an RFM-style customer risk model, a machine
learning test of whether delivery failure is predictable, and a trend forecast — see
[`docs/case_study.md`](docs/case_study.md) for the full write-up.

## Problem statement

AtliQ Mart has been losing customer contracts due to poor delivery performance — orders
arriving late, incomplete, or both — with no daily visibility into where the problem was
concentrated. The goal: quantify it, find the root cause, and prioritize fixes.

**Key metrics tracked:**
- **OT%** — On-Time delivery rate
- **IF%** — In-Full delivery rate (complete quantity)
- **OTIF%** — On-Time AND In-Full (both criteria)
- **VOFR%** — Volume Fill Rate (units delivered ÷ units ordered)
- **LIFR%** — Line Fill Rate (% of order lines delivered complete)

## Headline findings

| Metric | Value | Target | Gap |
|---|---|---|---|
| OTIF% | 29.0% | 65.9% avg (49-75% by customer) | 36.9 points |
| On-Time% | 59.0% | 86.1% avg | 27.1 points |
| In-Full% | 52.8% | 76.5% avg | 23.7 points |
| Volume Fill Rate | 96.6% | — (no target set) | high |
| Line Fill Rate | 66.0% | — (no target set) | weak |

- **Most units ship, but few orders arrive complete**: 96.6% of ordered units are delivered
  (VOFR), yet only 66.0% of order lines are delivered in full (LIFR) — the shortfall is many
  small misses (a short line is about 10% short on average), not a few large ones.
- **Dairy has the largest shortfall in absolute terms** (360,470 of 457,779 missing units,
  about 79%) because it is two-thirds of all order lines. Its fill rate (96.6%) is the same
  as Food and Beverages, so Dairy is where the volume is, not a worse performer.
- **5 customers sit under 10% OTIF** (three of them among the largest accounts) and are
  priorities for retention outreach. An RFM-style risk score ranks all 35 customers
  (11 land in the Critical segment) — see `sql/04_original_analysis.sql`.
- **Failures are broad, and customer matters most.** Product (in-full rate), city, week
  and day of week each vary by only a few points. Order size changes the *type* of failure
  (larger orders are on time more often but complete less often) while OTIF stays flat at
  28–30%. By customer, OTIF ranges from 7% to 42%, and the 8 largest customers are at 15%
  versus 35% for the other 27.
- **Order attributes alone can't predict failure; the customer can, modestly.** A classifier
  using city, order size, line count and weekday scores ROC-AUC ≈ 0.52–0.53, close to chance.
  Adding customer identity lifts it to ≈ 0.66–0.67. The dataset has no inventory, warehouse
  or transport fields, so the root cause inside operations (fulfillment capacity, inventory)
  remains a hypothesis, not a finding.
- **Forecast**: a Holt linear-trend model projects OTIF staying flat around 29% for the next
  month (a backtest shows the trend term adds nothing over the historical mean) — there is
  no sign of self-correction in the data.

Full detail in [`docs/case_study.md`](docs/case_study.md).

## Tech stack

| Layer | Tools |
|---|---|
| Database | MySQL 8.0 — star schema, FKs, indexes, generated columns |
| ETL | Python (pandas, SQLAlchemy) — cleans mixed date formats & inconsistent casing |
| Analysis (SQL) | CTEs, window functions (`NTILE`, `LAG`, `DENSE_RANK`), manual median calc |
| Analysis (Python) | pandas, seaborn/matplotlib, scikit-learn, statsmodels |
| Visualization | Power BI — live MySQL connection, 30 DAX measures, 4-page dashboard |

## Project structure

```
sql/
  00_schema_mysql.sql          — star schema DDL (2 fact, 4 dim tables)
  02_eda_data_quality.sql      — data quality checks + a casing fix found during EDA
  03_business_questions.sql    — 14 core business questions
  04_original_analysis.sql     — 4 original questions beyond the brief (see below)
python/
  etl_load_mysql.py            — cleans CSVs and loads them into MySQL
  eda_deep_dive.ipynb          — trend chart, city×category heatmap, order-size and customer breakdowns
  delay_risk_model.ipynb       — ML test of whether OTIF failure is predictable at order time, with and without customer identity
  otif_trend_forecast.ipynb    — Holt linear-trend forecast of weekly OTIF% with a backtest
powerbi/
  BUILD_GUIDE.md               — page-by-page rebuild spec
  dax_measures.txt             — all 30 DAX measures, ready to paste into Power BI Desktop
docs/
  case_study.md                — full narrative write-up
dataset/                       — original 6 source CSVs (provided by Codebasics)
```

## How to run this project

**1. Set up MySQL:**
```bash
mysql -u root -p < sql/00_schema_mysql.sql
```

**2. Load the data:**
```bash
pip install -r python/requirements.txt
python python/etl_load_mysql.py
```

**3. Run the SQL analysis:**
```bash
mysql -u atliq_analyst -p atliq_mart_supplychain < sql/02_eda_data_quality.sql
mysql -u atliq_analyst -p atliq_mart_supplychain < sql/03_business_questions.sql
mysql -u atliq_analyst -p atliq_mart_supplychain < sql/04_original_analysis.sql
```

**4. Run the Python notebooks:**
```bash
jupyter nbconvert --to notebook --execute --inplace python/eda_deep_dive.ipynb
jupyter nbconvert --to notebook --execute --inplace python/delay_risk_model.ipynb
jupyter nbconvert --to notebook --execute --inplace python/otif_trend_forecast.ipynb
```

**5. Build the Power BI dashboard:** follow [`powerbi/BUILD_GUIDE.md`](powerbi/BUILD_GUIDE.md).

## Original contributions beyond the source challenge

The dataset and business brief are from Codebasics' resume project challenge series. Beyond
rebuilding the SQL/BI layer independently in MySQL, this project adds:
- A day-of-week delivery-reliability check
- An order-size analysis (OTIF is flat, but on-time and in-full move in opposite directions)
- An RFM-style composite customer risk score (ranks *all* customers, not just a top-5 list;
  the recency component adds little here since 34 of 35 customers ordered on the last data day)
- An illustrative revenue-at-risk estimate from the volume shortfall (assumed unit prices,
  not real revenue)
- A full Python layer: deeper EDA, an ML test of order-level predictability, and a trend forecast
- A 4th Power BI page dedicated to these findings

## Acknowledgements

Dataset and original business brief: [Codebasics](https://codebasics.io/) Resume Project
Challenge. This repository is an independent rebuild and extension of that challenge.

## License

MIT — see [LICENSE](LICENSE).
