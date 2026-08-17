# Resume & LinkedIn Draft Bullets

Pick 3-4 for a resume (space is tight); use more freely on LinkedIn/portfolio pages.
Numbers are drawn directly from `sql/` and `python/` outputs — verify them against your own
run before publishing (`sql/02_eda_data_quality.sql` section 7 has the headline figures).

## Final resume entry (LaTeX)

The version actually chosen for the resume — title picked to name the two things the four
bullets back up (delivery diagnostics + churn risk scoring), not a generic project label.

```latex
\subhead{\textbf{Supply Chain Delivery Diagnostics \& Churn Risk Scoring} $\vert$ \emph{Self Project} \hfill \emph{(2026)}}
\begin{itemize}
    \item Built a \textbf{MySQL} schema \& \textbf{Python ETL} pipeline to clean \& load \textbf{88,825 orders}, fixing date \& category errors
    \item Wrote \textbf{31 SQL queries} using \textbf{CTEs \& window functions} to uncover a \textbf{29\% OTIF rate} \& a \textbf{360K-unit} shortfall
    \item Modeled customer churn risk with an \textbf{RFM-style SQL} scoring system across \textbf{35 customers}, flagging \textbf{5} for retention
    \item Shipped a \textbf{4-page Power BI} dashboard with \textbf{30 DAX measures} for live, self-serve OTIF tracking
\end{itemize}
```

**Reminder:** bullet 4 describes a dashboard that doesn't exist yet as of this writing — build
it (`powerbi/BUILD_GUIDE.md`) before this resume version actually goes out to anyone.

## Resume bullets (achievement-first, quantified)

- Designed and built a MySQL star schema (6 tables, FK/index design) and a Python ETL
  pipeline to clean and load 88K+ raw order records, resolving multi-format date fields and
  inconsistent categorical data.
- Wrote 31 SQL queries (CTEs, window functions, cross-dialect median calculation) to
  diagnose a 71%-order-failure delivery problem, isolating OTIF at 29% against a 66% average
  target and identifying a 360K-unit Dairy category shortfall as the single largest fix target.
- Built an RFM-style composite risk-scoring model in SQL to rank all customers (not just a
  top-N list) by churn risk, combining order frequency, service reliability, and recency into
  a single actionable segmentation.
- Tested whether OTIF failure was predictable from order-intake data using scikit-learn
  (Logistic Regression, Random Forest); a near-random ROC-AUC (~0.53) demonstrated the
  problem was systemic fulfillment capacity rather than order-specific risk — redirecting
  recommended fixes toward inventory/warehouse operations instead of order screening.
- Forecasted OTIF trend with Holt-Winters exponential smoothing (statsmodels), projecting
  continued stagnation absent intervention — used to justify immediate vs. long-term
  recommendation prioritization.
- Designed a 4-page Power BI dashboard from a live MySQL connection with 30 custom DAX
  measures (time intelligence, target-gap tracking, dynamic risk tiering), replacing static
  reporting with self-serve drill-down by customer, product, and city.

## LinkedIn / portfolio blurb (short paragraph form)

> Rebuilt an end-to-end supply-chain analytics project from raw CSVs to a live dashboard:
> designed a MySQL schema and ETL pipeline, wrote 31 SQL queries including an original
> RFM-style customer risk model, tested (and ruled out) order-level predictability of
> delivery failure with scikit-learn, forecasted the delivery-performance trend with
> statsmodels, and built a 4-page Power BI dashboard with 30 DAX measures on top of it all.
> Full write-up: [link to case_study.md or hosted dashboard]

## Interview talking points (things you should be ready to explain cold)

- Why MySQL has no `PERCENTILE_CONT` and how you computed a median manually.
- Why the classifier's ROC-AUC being close to 0.5 is a *good* finding, not a failed model.
- Why you used a chronological train/test split instead of a random one for the risk model.
- Why Volume Fill Rate (~96%) and Line Fill Rate (<68%) can diverge this much on the same data.
- What "illustrative revenue-at-risk" means and why you labeled the unit price as assumed
  rather than presenting it as a real AtliQ Mart figure.
