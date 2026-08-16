# Power BI Rebuild Guide

Everything here is meant to be built by hand in Power BI Desktop, connected to the MySQL
database this project already set up (`atliq_mart_supplychain`). Budget ~45-60 minutes.
This rebuild connects live to MySQL instead of reusing the original repo's `.pbix`, so the
model, DAX, and layout are all your own work.

## 1. Connect to MySQL

1. Power BI Desktop → **Get Data** → search **MySQL database** (install the free "MySQL
   Connector/NET" if Power BI prompts you — it's a one-time driver install).
2. Server: `localhost:3306`. Database: `atliq_mart_supplychain`.
3. Credentials: **Database** auth, username `atliq_analyst`, password = whatever you set
   when you created that MySQL user (see `sql/00_schema_mysql.sql` setup notes — don't reuse
   the same password anywhere this gets committed to git).
4. Import all 6 tables: `dim_customers`, `dim_products`, `dim_date`, `dim_targets_orders`,
   `fact_order_lines`, `fact_orders_aggregate`. Use **Import** mode, not DirectQuery — the
   dataset is small (~57K rows) and Import gives you full DAX time-intelligence support.

## 2. Data model (Model view)

Relationships to create (drag from the "one" side to the "many" side):

| From (one) | To (many) | Notes |
|---|---|---|
| `dim_customers[customer_id]` | `fact_order_lines[customer_id]` | |
| `dim_customers[customer_id]` | `fact_orders_aggregate[customer_id]` | |
| `dim_customers[customer_id]` | `dim_targets_orders[customer_id]` | 1:1 |
| `dim_products[product_id]` | `fact_order_lines[product_id]` | |
| `dim_date[calendar_date]` | `fact_orders_aggregate[order_placement_date]` | mark active |
| `dim_date[calendar_date]` | `fact_order_lines[order_placement_date]` | mark active |

`fact_order_lines` also has `agreed_delivery_date` and `actual_delivery_date`. Don't create
active relationships for those (Power BI only allows one active path between two tables) —
leave them unrelated, or add them as **inactive** relationships and reference with
`USERELATIONSHIP()` only if you build a delay-specific measure later.

**Mark `dim_date` as the official date table**: right-click it in Model view → *Mark as date
table* → pick `calendar_date`. This unlocks `DATEADD`/`SAMEPERIODLASTYEAR`-style time
intelligence in the DAX library.

## 3. DAX measures

Create a blank table (Modeling ribbon → **New Table** → formula `_Measures = { }`) to hold
every measure instead of scattering them across fact tables — standard practice, and it's
the first thing an interviewer looks for when they open your model.

Copy every measure from [`dax_measures.txt`](dax_measures.txt) into `_Measures`, one at a
time (New Measure, paste the name and formula). 30 measures total: core volume, headline
OT/IF/OTIF, VOFR/LIFR, target gaps, MoM/WoW time intelligence, and customer risk tiering.

## 4. Report pages

Four pages — one more than the original's three, adding a diagnostics page for the
day-of-week / order-size / forecast findings from the Python notebooks.

**Page 1 — Overview**
- KPI cards: `[Total Orders]`, `[OTIF %]`, `[On Time %]`, `[In Full %]`, `[OTIF Gap (pts)]`
  (conditional-format red/green on sign)
- Line chart: OTIF% by week (`dim_date[week_no]` on axis, `[OTIF %]` on values), with a
  constant-line at the average target OTIF (~70%) for visual gap reference
- Slicers: city, customer, product category, date range
- Card or button strip navigating to the other 3 pages (Bookmarks + Buttons)

**Page 2 — Customer Risk**
- Table: customer, city, total orders, On Time/In Full/OTIF %, `[Customer Performance Tier]`
  — conditional-format the tier column (green=Excellent, red=Critical)
- Bar chart: bottom 10 customers by OTIF%, sorted ascending
- Card: `[At-Risk Customers (OTIF<10%)]`
- Optional: import `sql/04_original_analysis.sql` section C (the RFM-style composite risk
  score) as a **custom SQL query table** (Get Data → MySQL → paste the query) for a table
  visual with `composite_risk_score` and `risk_segment` — that logic uses `NTILE()` window
  functions which DAX can't replicate cleanly, so pulling it in as a query result is the
  right call here rather than forcing it into a measure.

**Page 3 — Product & Category**
- Table: category, qty ordered, qty delivered, shortfall, `[Volume Fill Rate % (VOFR)]`
- Bar chart: `[Line Fill Rate % (LIFR)]` by product, ascending (worst first)
- Callout card: Dairy shortfall units (highlight the single biggest fix-target number)
- Matrix: city x category on-time%, conditional-formatted like a heatmap (this replicates
  the seaborn heatmap from `python/eda_deep_dive.ipynb` as a native Power BI visual)

**Page 4 — Trends & Diagnostics** *(new page, not in the original)*
- Column chart: OTIF% by day-of-week (import `sql/04_original_analysis.sql` section A, or
  rebuild with a calculated column `Weekday = FORMAT(dim_date[calendar_date], "dddd")`)
- Column chart: OTIF% by order-size bucket (import section B, since the bucket logic is
  easier to keep in SQL than to re-derive as a DAX calculated column)
- Text box: paste the forecast finding from `python/otif_trend_forecast.ipynb` — "at current
  trend, OTIF stays flat around 29% for the next month; this will not self-correct." Static
  text is fine here — the point is showing you can tie a Python finding back into the BI
  narrative, not making Power BI run the forecast itself.

## 5. Polish checklist

- One consistent color: red/amber/green mapped to the same three tiers everywhere (page 2's
  Excellent/Good/Poor/Critical, page 3's fill-rate bars, page 1's gap cards)
- Page navigation buttons (Insert → Buttons → Blank, add a Page Navigator action) instead of
  relying on the page tabs at the bottom
- Tooltips: add a tooltip page or at minimum enable the default tooltip with 2-3 extra
  fields for the main charts
- Publish to the Power BI Service (**Publish** button, needs a free Power BI account) if you
  want a live shareable link like the original repo had — otherwise the `.pbix` file itself
  is enough for a portfolio; note in your README that a Pro/service account is optional.

## 6. Verification

Before calling it done, confirm the rebuilt dashboard's headline numbers match the SQL:
**OTIF ≈ 29.0%, On-Time ≈ 59.0%, In-Full ≈ 52.8%** (see `sql/02_eda_data_quality.sql`
section 7). If your Power BI card shows something different, the model relationships or a
measure's filter context is off — check for an unintended cross-filter direction first.
