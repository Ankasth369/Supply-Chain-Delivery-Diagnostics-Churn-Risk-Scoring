# Power BI Rebuild Guide

Everything here is meant to be built by hand in Power BI Desktop, connected to the MySQL
database this project already set up (`atliq_mart_supplychain`). Budget ~60-90 minutes if
you're new to Power BI's UI. This rebuild connects live to MySQL instead of reusing the
original repo's `.pbix`, so the model, DAX, and layout are all your own work.

Written click-by-click on purpose — if a step doesn't match what you see on screen, that's
the signal something's off (wrong window, wrong view), not that you did it wrong.

## Prerequisites (should already be done)

- MySQL Server running locally with database `atliq_mart_supplychain` (see `sql/00_schema_mysql.sql`)
- MySQL Connector/NET installed (from `https://dev.mysql.com/downloads/connector/net/` — the
  "Windows (x86, 32-bit), MSI Installer" package works fine on 64-bit Windows too)
- Power BI Desktop installed and open to a **blank report** — if you only see three tabs
  (File, Home, Help) at the top, you're on the start/welcome screen, not an actual report.
  Click "Blank report" on that screen first.

## 1. Connect to MySQL

1. In Power BI Desktop, click the **Home** tab (top-left) if it isn't already selected.
2. Click **Get Data** → in the search box that opens, type `mysql`.
3. Select **MySQL database** from the results → click **Connect**.
4. A dialog asks for Server and Database:
   - Server: `localhost:3306`
   - Database: `atliq_mart_supplychain`
   - Click **OK**.
5. A credentials dialog appears with tabs on the left (Windows, Database, Microsoft account).
   Click the **Database** tab → enter:
   - Username: `atliq_analyst`
   - Password: `AtliqMart_2026!`
   - Click **Connect**.
6. A **Navigator** window lists your tables on the left with checkboxes. Check all 6:
   `dim_customers`, `dim_products`, `dim_date`, `dim_targets_orders`, `fact_order_lines`,
   `fact_orders_aggregate`.
7. Click **Load** (bottom-right) — not "Transform Data". The Python ETL already cleaned
   everything, so no Power Query edits are needed. Loading ~89K rows takes a few seconds.

**You'll know this worked** when the **Fields pane** on the right side of the screen lists
all 6 tables, each with an arrow you can expand to see its columns.

## 2. Data model (Model view)

1. Look at the far-left edge of the Power BI window — there are 3 icons stacked vertically:
   **Report**, **Data**, **Model** (they look like a bar chart, a grid/table, and a small
   schema diagram respectively). Click **Model**.
2. You'll see all 6 tables as boxes you can drag around. No lines connect them yet.
3. To create a relationship: click a field name inside one table's box and **drag it onto**
   the matching field name in another table's box, then release. A dialog confirms the
   relationship — it should auto-detect "Many to one" with the dim table on the "one" side.
   Click **OK** without changing anything else.

Create these 6 relationships (drag from the left column onto the right column):

| Drag from | Drop onto |
|---|---|
| `dim_customers[customer_id]` | `fact_order_lines[customer_id]` |
| `dim_customers[customer_id]` | `fact_orders_aggregate[customer_id]` |
| `dim_customers[customer_id]` | `dim_targets_orders[customer_id]` |
| `dim_products[product_id]` | `fact_order_lines[product_id]` |
| `dim_date[calendar_date]` | `fact_orders_aggregate[order_placement_date]` |
| `dim_date[calendar_date]` | `fact_order_lines[order_placement_date]` |

**Skip** `agreed_delivery_date` and `actual_delivery_date` in `fact_order_lines` — don't
connect those to `dim_date` (Power BI only allows one active relationship per table pair,
and `order_placement_date` already uses that slot).

4. **Mark `dim_date` as the official date table**: right-click the `dim_date` table's title
   bar in Model view → **Mark as date table** → in the dropdown pick `calendar_date` → **OK**.
   This unlocks `DATEADD`/time-intelligence functions used in section 3 below.

**You'll know this worked** when you see 6 lines connecting the table boxes, each showing a
"1" near the dim table and a "*" (many) near the fact table.

## 3. DAX measures

### 3a. Create a home for your measures

1. Still anywhere in Power BI Desktop, click the **Modeling** tab at the top (next to Home,
   Insert, View). If you don't see a **Modeling** tab at all, you're likely still on the
   welcome screen — go back to Prerequisites above.
2. In the Modeling ribbon, find the **Calculations** group of buttons: **New Measure**,
   **New Column**, **New Table**. Click **New Table**.
3. A formula bar opens at the top with a blinking cursor. Type exactly:
   ```
   _Measures = {1}
   ```
4. Press **Enter**.
5. Check the **Fields** pane on the right — a new table `_Measures` should now be listed,
   containing one column called `Value`. (Optional tidy-up: right-click that `Value` column
   → **Hide in report view**, since you'll never actually use it.)

### 3b. Add the measures, one at a time, in order

**Order matters**: many measures reference earlier ones (e.g. `On Time %` uses
`[On Time Orders]` and `[Total Orders]`, which must exist first). Go through
[`dax_measures.txt`](dax_measures.txt) **top to bottom**. Skip lines starting with `//` —
those are section headers, not measures.

For each measure:
1. Click `_Measures` in the Fields pane to select it.
2. **Modeling** tab → **New Measure**. A formula bar opens.
3. Click the small **∨ chevron** at the right end of the formula bar to expand it into a
   multi-line editor — makes pasting the multi-line measures much easier.
4. Copy one full measure block from `dax_measures.txt` (from its name through the end of its
   formula) and paste it into the formula bar.
5. Click the **✓ checkmark** button next to the formula bar (or press Ctrl+Enter) to commit.
6. Repeat from step 2 for the next measure.

There are 30 measures total, covering: core volume, headline OT/IF/OTIF, VOFR/LIFR, target
gaps, MoM/WoW time intelligence, and customer risk tiering.

**If a measure shows a red squiggly underline or an error on commit**: the most common cause
is a typo from copy-paste (a stray character) or trying to reference a measure you haven't
created yet — check it's not skipped and matches the file exactly.

**You'll know this worked** when `_Measures` in the Fields pane expands to show all 30
measure names (look for the calculator-icon next to each, distinguishing them from columns).

## 4. Report pages

Four pages — one more than the original's three, adding a diagnostics page for the
day-of-week / order-size / forecast findings from the Python notebooks. Click the **+** tab
at the bottom of the canvas to add each new page.

**Page 1 — Overview**
- KPI cards: `[Total Orders]`, `[OTIF %]`, `[On Time %]`, `[In Full %]`, `[OTIF Gap (pts)]`
  (conditional-format red/green on sign)
- Line chart: OTIF% by week (`dim_date[week_no]` on axis, `[OTIF %]` on values), with a
  constant-line at the average target OTIF (~66%) for visual gap reference
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
