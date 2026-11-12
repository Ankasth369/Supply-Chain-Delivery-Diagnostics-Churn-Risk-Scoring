# Power BI Rebuild Guide

Everything here is meant to be built by hand in Power BI Desktop, connected to the MySQL
database this project already set up (`atliq_mart_supplychain`). Budget ~60-90 minutes if
you're new to Power BI's UI. This rebuild connects to MySQL in Import mode (the data is loaded into the `.pbix`, so click
Refresh after the database changes) instead of reusing the
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
   - Password: the password you set for the `atliq_analyst` MySQL user (never commit it)
   - Click **Connect**.
6. A **Navigator** window lists your tables on the left with checkboxes. Check all 6:
   `dim_customers`, `dim_products`, `dim_date`, `dim_targets_orders`, `fact_order_lines`,
   `fact_orders_aggregate`.
7. Click **Load** (bottom-right) — not "Transform Data". The Python ETL already cleaned
   everything, so no Power Query edits are needed. Loading ~89K rows takes a few seconds.

**You'll know this worked** when the **Fields pane** on the right side of the screen lists
all 6 tables, each with an arrow you can expand to see its columns.

### 1b. Fix Boolean-typed flag columns (do this now, before writing any measures)

MySQL's `TINYINT(1)` type (used for `on_time`, `in_full`, `otif`, `on_time_in_full` in the
schema) is auto-interpreted as **True/False (Boolean)** by the MySQL Connector/NET driver
instead of as a 0/1 whole number — `TINYINT(1)` is literally MySQL's alias for `BOOLEAN`, so
this is a well-known cross-driver gotcha, not a mistake in the schema. Left as-is, any DAX
measure using `SUM()` on these columns fails with an error like:
`The function SUM cannot work with values of type Boolean.`

Fix it once, right after loading, so it never comes up while writing measures:

1. **Home** ribbon → **Transform Data** (opens the Power Query Editor in a new window).
2. In the **Queries** pane on the left, click `fact_orders_aggregate`.
3. In the data preview grid, click the `on_time` column header, then **Ctrl+click** `in_full`
   and `otif` to select all three at once.
4. Right-click any of the selected headers → **Change Type** → **Whole Number**.
5. Click `fact_order_lines` in the Queries pane and repeat for its `on_time`, `in_full`, and
   `on_time_in_full` columns.
6. Click **Close & Apply** (top-left) to reload the data with the corrected types.

### 1c. Fix database-prefixed table names (check this too, right after loading)

Power BI's MySQL connector sometimes auto-prefixes table names with the database name when
it loads them — e.g. a table shows up in the Fields pane as
`atliq_mart_supplychain fact_orders_aggregate` instead of plain `fact_orders_aggregate`. If
you don't catch this, every DAX measure that references `fact_orders_aggregate` by its plain
name will fail with an error like:
`Failed to resolve name 'fact_orders_aggregate'. It is not a valid table, variable, or function name.`

Check the Fields pane now, before writing any measures:

1. Look at each of the 6 tables listed in the **Fields pane**. If any name has a prefix
   before the table name (anything before `dim_` or `fact_`), it needs renaming.
2. Right-click the prefixed table name → **Rename**.
3. Type the plain name back in exactly: `dim_customers`, `dim_products`, `dim_date`,
   `dim_targets_orders`, `fact_order_lines`, or `fact_orders_aggregate` (matching whichever
   table you're renaming) → **Enter**.
4. Repeat for any other table that came in prefixed.

This must match exactly, since every formula in `dax_measures.txt` references these 6 tables
by their plain names.

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

## 4. Design system — apply this before building pages

Rather than manually color-formatting 20+ visuals one at a time, import one theme file that
sets the whole report's palette, fonts, and card styling in a single click. Do this now,
before adding visuals, so everything you build from here inherits it automatically.

**What the theme defines** (this project's [`theme.json`](theme.json)):
- **Primary accent** `#0F6FC6` (blue) — used for neutral charts/axes, e.g. the OTIF trend line
- **Good** `#2E7D32` (green) — on-target performance, "Excellent" tier, positive gaps
- **Bad** `#C62828` (red) — below-target performance, "Critical" tier, negative gaps
- **Neutral/warning** `#F9A825` (amber) — "Good"/"Poor" middle tiers
- White background, dark gray (`#252423`) text, Segoe UI throughout (Power BI's default —
  don't introduce a second font, it reads as inconsistent)

**To import it:**
1. **View** ribbon (top) → find the **Themes** group → click the small **∨** under the
   theme gallery thumbnails → **Browse for themes...**
2. Navigate to and select `powerbi/theme.json` from this project folder → **Open**
3. Every card, chart, and table on every page now uses this palette by default

**Design rules to follow while building the pages below** (this is what actually makes a
dashboard look "presentable" — consistency, not decoration):
- **One meaning per color, everywhere.** Green always means "meeting target," red always
  means "below target" — never repurpose red for something unrelated on another page.
- **Align things to an invisible grid.** Power BI snaps visuals to nearby edges as you drag —
  watch for the pink/red alignment guides and use them. Uneven visual edges are the single
  biggest thing that makes a dashboard look unpolished.
- **Biggest number, biggest font.** The KPI cards (Section 5, Page 1) should be the largest
  text on the page — that's the headline. Everything else is supporting detail.
- **Leave whitespace.** Don't stretch visuals to fill every pixel — a small margin between
  visuals (Power BI's default snap spacing is fine) reads as intentional, not empty.
- **Turn off visual clutter by default**: for every chart, open the **Format** pane
  (paint-roller icon in Visualizations) → under **General** or the visual-specific
  formatting card, turn off drop shadows if any are on; keep gridlines minimal (light gray,
  not black).

## 5. Report pages

Four pages — one more than the original's three, adding a diagnostics page for the
day-of-week / order-size / forecast findings from the Python notebooks. Click the **+** tab
at the bottom of the canvas to add each new page, then double-click its tab name to rename it.

### Page 1 — Overview

1. Add the page, rename it `Overview`.
2. **5 KPI cards** across the top: click empty canvas → **Card** icon in Visualizations →
   drag one measure into the "Data values"/"Fields" well. Repeat 5× (empty canvas → Card →
   drag) for: `[Total Orders]`, `[OTIF %]`, `[On Time %]`, `[In Full %]`, `[OTIF Gap (pts)]`.
   Line these 5 up in a row along the top, same height, evenly spaced (watch for the snap
   guides).
   - On the `[OTIF Gap (pts)]` card specifically: select it → Format pane → **Callout value**
     → turn on **Conditional formatting** on the font color → set rule: value ≥ 0 → green
     (`#2E7D32`), value < 0 → red (`#C62828`). This is the one number on the page that should
     visually shout "we're behind."
3. **Line chart**: empty canvas → **Line chart** icon → drag `dim_date[week_no]` to X-axis,
   `[OTIF %]` to Y-axis. Select it → Format pane → **Analytics** tab → **Constant line** →
   Add → set value to `0.66` (the ~66% average target) → label it "Target". This gives every
   viewer an instant visual gap reference without reading numbers.
4. **4 slicers** below or beside the chart: empty canvas → **Slicer** icon → drag
   `dim_customers[city]`. Repeat for `dim_customers[customer_name]`, `dim_products[category]`,
   and one more slicer with `dim_date[calendar_date]` — for that last one, select it → Format
   pane → **Slicer settings** → **Style** → change from "List" to **"Between"** for a proper
   date-range picker.
5. Set these 4 slicers to filter every page, not just this one: select each slicer → **Format**
   ribbon tab (not Format pane) → **Edit interactions** is per-visual, but for cross-page
   filtering use **Sync slicers**: **View** ribbon → **Sync slicers** → check the box for
   every other page next to each slicer.

### Page 2 — Customer Risk

1. Add the page, rename it `Customer Risk`.
2. **Table**: empty canvas → **Table** icon → drag in `dim_customers[customer_name]`,
   `dim_customers[city]`, `[Total Orders]`, `[On Time %]`, `[In Full %]`, `[OTIF %]`,
   `[Customer Performance Tier]`.
   - Select the table → Format pane → find the `Customer Performance Tier` column →
     **Conditional formatting** → **Background color** → set rules by category: "Excellent"
     → green, "Good" → light green/amber, "Poor" → amber, "Critical" → red.
3. **Bar chart**: empty canvas → **Bar chart** (horizontal) icon → drag
   `dim_customers[customer_name]` to Y-axis, `[OTIF %]` to X-axis. Select it → Format pane →
   under the general visual settings find **Top N** filtering (or use the Filters pane on the
   right: drag `[OTIF %]` into Filters, set filter type to "Top N", value 10, and set "By
   value" ascending) so it shows only the 10 worst performers.
4. **Card**: empty canvas → **Card** → drag `[At-Risk Customers (OTIF<10%)]` in.
5. *(Optional, more advanced)* Import the RFM risk-scoring query as its own table: **Home** →
   **Get Data** → **MySQL database** → same server/database → but instead of the Navigator,
   click **Advanced options** before connecting and paste the full query text from
   `sql/04_original_analysis.sql` section C into the SQL statement box → Load. Add a second
   table visual on this page using its `composite_risk_score` and `risk_segment` columns
   (also drag in `customer_name` — without it, the table collapses into 4 grouped rows
   summed by `risk_segment` instead of one row per customer; if that happens, add
   `customer_name` and change `composite_risk_score`'s aggregation to **"Don't summarize"**).
   Power BI names this query `Query1`/`Query2` by default — rename it now (right-click it in
   the Fields pane → **Rename**) to something like `customer_risk_scores`, matching the
   plain-snake-case style of the other 6 tables.

### Page 3 — Product & Category

1. Add the page, rename it `Product & Category`.
2. **Table**: empty canvas → **Table** → drag `dim_products[category]`,
   `[Total Qty Ordered]`, `[Total Qty Delivered]`, `[Qty Shortfall]`,
   `[Volume Fill Rate % (VOFR)]`.
3. **Bar chart**: empty canvas → **Bar chart** → `dim_products[product_name]` on Y-axis,
   `[Line Fill Rate % (LIFR)]` on X-axis → select it → in the Visualizations pane's
   field well or the "..." menu on the visual, set **Sort** to ascending by that measure
   (worst-performing products first).
4. **Callout card**: empty canvas → **Card** → drag `[Qty Shortfall]` in, but first add a
   filter (drag `dim_products[category]` into the Filters pane, set it to only show "Dairy")
   so this one card highlights the single biggest number from the whole project.
5. **Matrix (heatmap)**: empty canvas → **Matrix** icon → drag `dim_customers[city]` into
   Rows, `dim_products[category]` into Columns, `[On Time %]` into Values → select it →
   Format pane → **Cell elements** → turn on **Conditional formatting** → **Background
   color** → set a 3-color scale (red low, amber mid, green high) using the same
   `#C62828`/`#F9A825`/`#2E7D32` values as the theme.

### Page 4 — Trends & Diagnostics *(new page, not in the original)*

1. Add the page, rename it `Trends & Diagnostics`.
2. Import the day-of-week and order-size findings as query tables, the same way as the
   optional risk-score table on Page 2: **Get Data** → **MySQL database** → **Advanced
   options** → paste the query text from `sql/04_original_analysis.sql` sections A and B
   respectively (two separate Get Data steps, two separate tables) → Load. Rename each one
   right after loading (right-click it in the Fields pane → **Rename**) — `day_of_week_otif`
   for section A's query, `order_size_otif` for section B's — instead of leaving them as the
   default `Query2`/`Query3`.
3. **Column chart**: empty canvas → **Column chart** → drag the day-of-week table's
   `day_name` to X-axis, `otif_pct` to Y-axis.
4. **Column chart**: empty canvas → **Column chart** → drag the order-size table's
   `order_size_bucket` to X-axis, `otif_pct` to Y-axis.
5. **Text box**: **Insert** ribbon → **Text box** → type the forecast finding directly:
   *"At the current trend, OTIF stays flat around 29% for the next month, with no sign of
   self-correction."* This is deliberately static text, not a live measure — the point is
   showing you can tie a Python finding back into the BI narrative, not making Power BI run
   the forecast itself.

## 6. Polish checklist

- Re-check every page against the design rules in Section 4 — same colors mean the same
  thing everywhere, everything's grid-aligned, KPI numbers are the biggest text on the page.
- **Page navigation buttons**: on Page 1, **Insert** ribbon → **Buttons** → **Blank** → draw
  a small button → Format pane → **Action** → turn on → Type: **Page navigation** → pick the
  target page. Make 3 of these (one per other page), then copy/paste them onto every other
  page so navigation is consistent throughout — beats relying on the small page tabs at the
  very bottom, which are easy to miss.
- **Tooltips**: select your main charts → Format pane → **Tooltip** → drag 1-2 extra relevant
  fields into the tooltip fields well (e.g. add `[Total Orders]` to the OTIF trend line's
  tooltip) so hovering shows more context than just the axis values.
- Publish to the Power BI Service (**Home** ribbon → **Publish** button, needs a free Power
  BI account) if you want a live shareable link like the original repo had — otherwise the
  `.pbix` file itself is enough for a portfolio; note in your README that a Pro/service
  account is optional.

## 7. Verification

Before calling it done, confirm the rebuilt dashboard's headline numbers match the SQL:
**OTIF ≈ 29.0%, On-Time ≈ 59.0%, In-Full ≈ 52.8%** (see `sql/02_eda_data_quality.sql`
section 7). If your Power BI card shows something different, the model relationships or a
measure's filter context is off — check for an unintended cross-filter direction first.
