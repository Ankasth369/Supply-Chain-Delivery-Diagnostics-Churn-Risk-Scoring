// =========================================================================================
// Bulk-create all 30 DAX measures on the _Measures table in one shot.
// Usage: Power BI Desktop -> External Tools -> Tabular Editor 2 -> paste this into the
// "C# Script" / Advanced Scripting panel -> click Run script (green play button).
// Requires the _Measures table to already exist (Modeling -> New Table -> `_Measures = {1}`).
// =========================================================================================

var measures = new (string Name, string Expr)[]
{
    ("Total Orders", "COUNTROWS(fact_orders_aggregate)"),
    ("Total Order Lines", "COUNTROWS(fact_order_lines)"),
    ("Total Customers", "DISTINCTCOUNT(dim_customers[customer_id])"),
    ("Total Products", "DISTINCTCOUNT(dim_products[product_id])"),

    ("On Time Orders", "SUM(fact_orders_aggregate[on_time])"),
    ("On Time %", "DIVIDE([On Time Orders], [Total Orders])"),
    ("Late Orders", "[Total Orders] - [On Time Orders]"),
    ("Late %", "1 - [On Time %]"),
    ("In Full Orders", "SUM(fact_orders_aggregate[in_full])"),
    ("In Full %", "DIVIDE([In Full Orders], [Total Orders])"),
    ("OTIF Orders", "SUM(fact_orders_aggregate[otif])"),
    ("OTIF %", "DIVIDE([OTIF Orders], [Total Orders])"),

    ("Total Qty Ordered", "SUM(fact_order_lines[order_qty])"),
    ("Total Qty Delivered", "SUM(fact_order_lines[delivery_qty])"),
    ("Qty Shortfall", "[Total Qty Ordered] - [Total Qty Delivered]"),
    ("Volume Fill Rate % (VOFR)", "DIVIDE([Total Qty Delivered], [Total Qty Ordered])"),
    ("Line Fill Rate % (LIFR)", "DIVIDE(SUM(fact_order_lines[in_full]), COUNTROWS(fact_order_lines))"),

    ("Target OnTime %", "AVERAGE(dim_targets_orders[ontime_target_pct]) / 100"),
    ("Target InFull %", "AVERAGE(dim_targets_orders[infull_target_pct]) / 100"),
    ("Target OTIF %", "AVERAGE(dim_targets_orders[otif_target_pct]) / 100"),
    ("OTIF Gap (pts)", "([OTIF %] - [Target OTIF %]) * 100"),
    ("OTIF Status", @"
VAR Gap = [OTIF Gap (pts)]
RETURN
    IF(ISBLANK(Gap), BLANK(), IF(Gap >= 0, ""Meets Target"", ""Below Target""))"),

    ("Orders Prior Month", "CALCULATE([Total Orders], DATEADD(dim_date[calendar_date], -1, MONTH))"),
    ("MoM Orders Change %", "DIVIDE([Total Orders] - [Orders Prior Month], [Orders Prior Month])"),
    ("OTIF % Prior Week", "CALCULATE([OTIF %], DATEADD(dim_date[calendar_date], -7, DAY))"),
    ("WoW OTIF Change (pts)", "([OTIF %] - [OTIF % Prior Week]) * 100"),

    ("At-Risk Customers (OTIF<10%)", @"
CALCULATE(
    DISTINCTCOUNT(dim_customers[customer_id]),
    FILTER(VALUES(dim_customers[customer_id]), [OTIF %] < 0.10)
)"),
    ("Customer Performance Tier", @"
VAR CustomerOtif = [OTIF %]
RETURN
    SWITCH(
        TRUE(),
        ISBLANK(CustomerOtif), BLANK(),
        CustomerOtif >= 0.85, ""Excellent"",
        CustomerOtif >= 0.70, ""Good"",
        CustomerOtif >= 0.50, ""Poor"",
        ""Critical""
    )"),

    ("OTIF % (label)", @"FORMAT([OTIF %], ""0.0%"") & "" OTIF"""),
    ("OTIF vs Target (label)", @"
VAR Gap = [OTIF Gap (pts)]
RETURN FORMAT([OTIF %], ""0.0%"") & "" (target "" & FORMAT([Target OTIF %], ""0.0%"") &
    "", "" & IF(Gap >= 0, ""+"", """") & FORMAT(Gap, ""0.0"") & "" pts)"""),
};

var table = Model.Tables["_Measures"];
int created = 0, skipped = 0;
foreach (var m in measures)
{
    if (table.Measures.Contains(m.Name))
    {
        skipped++;
        continue;
    }
    table.AddMeasure(m.Name, m.Expr);
    created++;
}

Info($"Created {created} measures, skipped {skipped} that already existed.");
