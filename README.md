# Olist Brazil Marketplace Analysis

SQL + Tableau analysis of the Olist Brazilian e-commerce dataset, looking at whether late delivery hurts customer reviews, and which product categories and sellers are driving the delays.

## Business Question

Does late delivery hurt review scores? If so, which categories and sellers are contributing most to it?

## Dataset

[Olist Brazilian E-Commerce Public Dataset](https://www.kaggle.com/datasets/olistbr/brazilian-ecommerce) (Kaggle) — ~100K orders placed between 2016-2018, spread across 9 relational tables (orders, order items, products, sellers, customers, payments, reviews, geolocation, category translation). Raw CSVs aren't included in this repo; download them from Kaggle if you want to run the queries yourself.

## Tools

SQLite (via DB Browser for SQLite) for the analysis, Tableau Public for the dashboard.

## Methodology

- Calculated per-order delivery delay: actual delivery date minus estimated delivery date.
- Joined delay to review score. Orders can have more than one review row, so review scores are averaged per order before joining.
- Bucketed each order into Early/On Time, 1-3 Days Late, 4-7 Days Late, 8+ Days Late, or Not Delivered (no delivery date logged).
- For category- and seller-level breakdowns, used **late rate** (% of items late) instead of average delay days. About 92% of orders are on time or early, so averaging delay buries the late-minority signal; late rate surfaces it directly.
- Checked item count alongside every late rate — a rate computed on a handful of items isn't a reliable signal and is called out as such below.

Full query log: [`olist_queries.sql`](./olist_queries.sql)

## Key Findings

**1. Review scores drop in a clean, monotonic pattern as delivery delay increases.**

| Delivery Status | Orders | Avg. Review Score |
|---|---|---|
| Early / On Time | 88,174 | 4.29 |
| 1-3 Days Late | 1,363 | 3.51 |
| 4-7 Days Late | 1,284 | 2.18 |
| 8+ Days Late | 2,786 | 1.70 |
| Not Delivered | 2,224 | 3.29 |

Every additional bucket of delay corresponds to a lower average review score, from 4.29 down to 1.70. "Not Delivered" sits outside this trend since these orders never logged a delivery date at all (confirmed via order status — canceled, unavailable, still processing, etc. — not an in-store pickup scenario, since Olist has no physical stores).

**2. Late rate varies meaningfully by category**, topped by `casa_conforto_2`, `moveis_colchao_e_estofado`, and `audio` in the ~15-17% range. See the dashboard for the full ranking. Some very high or very low rates in the long tail come from categories with only a handful of items and shouldn't be read as real signal without checking item count.

**3. Seller late rate shows a classic sample-size pattern.** Plotted against item count, low-volume sellers scatter widely — including a few sitting at 0% or 100% on a single-digit number of items — while high-volume sellers converge into a tight ~5-15% late-rate band. This means a seller's late rate is only a trustworthy performance signal once their item count is reasonably large.

## Data Quality Notes

- `casa_conforto_2` (5 products) appears to be a data-entry duplicate/mislabel of `casa_conforto` (111 products), not a genuinely distinct category. Left separate in the analysis rather than merged, but worth knowing when reading the category ranking.
- ~1.5% of order items (1,603 of 110,197) have no matching product category and were excluded from the category-level breakdown. Small enough not to change the conclusions.
- 8 orders are logged with status `delivered` but have no delivery date recorded — a minor data-logging gap, not material to the analysis.

## Dashboard

(https://public.tableau.com/app/profile/carlos.cortez7133/viz/OlistBrazilE-CommerceAnalysis_17906241327840/Dashboard1?publish=yes)

## Repo Contents

- `olist_queries.sql` — full SQL analysis, step by step, with comments
- `data/` — the three result CSVs used as Tableau data sources (`delay_vs_reviews.csv`, `category_late_rate.csv`, `seller_late_rate.csv`)
