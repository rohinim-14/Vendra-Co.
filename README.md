# Vendra-Co.
A product-level churn analysis framework built for a mock e-commerce brand, targeting executive-ready insights on catalog health, SKU retention, and at-risk product identification.


# How to re-create
Download the UCI Online Retail II dataset
Import the xlsx file into SQLite using DBeaver (File → Import Data)
Run the SQL files in order: 01 → 02 → 03 → 04
Connect the output tables to Tableau Public for visualization

# Dataset
The analysis uses the UCI Machine Learning Repository's Online Retail II dataset — a real transaction log from a UK-based gift and home goods retailer covering December 2009 through December 2010. The dataset contains approximately 1.07 million raw transaction rows across ~4,300 unique product codes.

Raw rows
1,067,371
Clean rows (post-filter)
509,343
Rows removed
~52% (returns, nulls, admin codes)
Unique SKUs (clean)
4,093
Unique customers
4,338
Date range
2009-12-01 to 2010-12-09
Countries
38 (UK = ~90% of volume)


# Data Cleaning Rules
The following rows were excluded from analysis to ensure analytical integrity:

- Rows with NULL Customer ID -> cannot be attributed to any buyer behaviour
- Negative quantity rows-> these are return transactions, treated separately
- Zero or negative price rows -> free samples or system errors
- Internal admin stock codes -> POST (postage), D (discount), M (manual), DOT, CRUK
- Stock codes under 4 characters — Vendra-specific junk codes
- Rows with blank descriptions — data integrity failures

## Churn Status Logic
Each SKU is assigned a status for each month based on the current and prior month's activity, using SQLite window functions (LAG):

- New
Active this month, no orders in any of the prior 3 months
- Retained
Active this month AND was active last month
- Churned
Was active last month, zero orders this month
- Reactivated
Active this month, was inactive last month but active 2–3 months ago
- Dormant
Inactive this month AND inactive last month

