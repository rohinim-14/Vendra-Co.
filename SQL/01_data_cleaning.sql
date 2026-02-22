-- =============================================================
-- VENDRA CO. | SKU Churn & Catalog Health Analysis
-- File 01: Data Cleaning
-- Tool: SQLite via DBeaver
-- Source: online_retail_II_xlsx
-- =============================================================


-- =============================================================
-- STEP 1: Inspect raw data
-- =============================================================

SELECT * FROM online_retail_II_xlsx LIMIT 20;

SELECT COUNT(*) AS total_rows FROM online_retail_II_xlsx;

SELECT COUNT(*) AS missing_customer_id
FROM online_retail_II_xlsx
WHERE "Customer ID" IS NULL;

SELECT COUNT(*) AS return_rows
FROM online_retail_II_xlsx
WHERE Quantity < 0;

SELECT COUNT(*) AS bad_price_rows
FROM online_retail_II_xlsx
WHERE Price <= 0;

-- Spot junk StockCodes
SELECT
    StockCode,
    Description,
    COUNT(*) AS row_count
FROM online_retail_II_xlsx
WHERE
    LENGTH(TRIM(StockCode)) < 4
    OR UPPER(TRIM(StockCode)) IN ('POST','D','M','DOT','PADS','BANK CHARGES','CRUK','C2')
GROUP BY StockCode, Description
ORDER BY row_count DESC
LIMIT 30;

-- Test date parsing before running Step 2
-- Raw format is M/D/YY H:MM → target YYYY-MM-DD
SELECT
    InvoiceDate,
    '20' || SUBSTR(SUBSTR(InvoiceDate, INSTR(InvoiceDate, '/') + 1),
                   INSTR(SUBSTR(InvoiceDate, INSTR(InvoiceDate, '/') + 1), '/') + 1, 2)
    || '-'
    || PRINTF('%02d', CAST(SUBSTR(InvoiceDate, 1, INSTR(InvoiceDate, '/') - 1) AS INTEGER))
    || '-'
    || PRINTF('%02d', CAST(SUBSTR(SUBSTR(InvoiceDate, INSTR(InvoiceDate, '/') + 1), 1,
              INSTR(SUBSTR(InvoiceDate, INSTR(InvoiceDate, '/') + 1), '/') - 1) AS INTEGER))
                                                    AS order_date
FROM online_retail_II_xlsx
LIMIT 10;


-- =============================================================
-- STEP 2: Create cleaned transactions table
-- =============================================================

DROP TABLE IF EXISTS vendra_transactions;

CREATE TABLE vendra_transactions AS
SELECT
    CAST(Invoice AS TEXT)                               AS order_id,
    UPPER(TRIM(StockCode))                              AS sku,
    TRIM(Description)                                   AS product_name,
    Quantity                                            AS quantity,

    -- Parse M/D/YY H:MM → YYYY-MM-DD
    '20' || SUBSTR(SUBSTR(InvoiceDate, INSTR(InvoiceDate, '/') + 1),
                   INSTR(SUBSTR(InvoiceDate, INSTR(InvoiceDate, '/') + 1), '/') + 1, 2)
    || '-'
    || PRINTF('%02d', CAST(SUBSTR(InvoiceDate, 1, INSTR(InvoiceDate, '/') - 1) AS INTEGER))
    || '-'
    || PRINTF('%02d', CAST(SUBSTR(SUBSTR(InvoiceDate, INSTR(InvoiceDate, '/') + 1), 1,
              INSTR(SUBSTR(InvoiceDate, INSTR(InvoiceDate, '/') + 1), '/') - 1) AS INTEGER))
                                                        AS order_date,

    Price                                               AS unit_price,
    ROUND(Quantity * Price, 2)                          AS line_revenue,
    CAST("Customer ID" AS TEXT)                         AS customer_id,
    Country                                             AS country

FROM online_retail_II_xlsx
WHERE
    "Customer ID" IS NOT NULL
    AND Quantity > 0
    AND Price > 0
    AND UPPER(TRIM(StockCode)) NOT IN ('POST','D','M','DOT','PADS','BANK CHARGES','CRUK','C2')
    AND LENGTH(TRIM(StockCode)) >= 4
    AND Description IS NOT NULL
    AND TRIM(Description) != '';


-- =============================================================
-- STEP 3: Verify
-- =============================================================

-- Row count
SELECT COUNT(*) AS clean_rows FROM vendra_transactions;

-- % removed
SELECT
    raw.total                                                   AS raw_rows,
    clean.total                                                 AS clean_rows,
    ROUND(100.0 * (raw.total - clean.total) / raw.total, 1)    AS pct_removed
FROM
    (SELECT COUNT(*) AS total FROM online_retail_II_xlsx) raw,
    (SELECT COUNT(*) AS total FROM vendra_transactions) clean;

-- Unique SKUs and customers
SELECT
    COUNT(DISTINCT sku)         AS total_skus,
    COUNT(DISTINCT customer_id) AS total_customers
FROM vendra_transactions;

-- Revenue by year
SELECT
    SUBSTR(order_date, 1, 4)        AS year,
    COUNT(*)                        AS transactions,
    COUNT(DISTINCT sku)             AS active_skus,
    COUNT(DISTINCT customer_id)     AS customers,
    ROUND(SUM(line_revenue), 2)     AS total_revenue
FROM vendra_transactions
GROUP BY year
ORDER BY year;

-- Date spot check
SELECT order_id, order_date FROM vendra_transactions LIMIT 10;


-- =============================================================
-- STEP 4: Create SKU catalog
-- =============================================================

DROP TABLE IF EXISTS vendra_sku_catalog;

CREATE TABLE vendra_sku_catalog AS
SELECT
    sku,
    (
        SELECT product_name FROM vendra_transactions t2
        WHERE t2.sku = t1.sku
        GROUP BY product_name
        ORDER BY COUNT(*) DESC
        LIMIT 1
    )                                               AS product_name,
    ROUND(AVG(unit_price), 2)                       AS avg_unit_price,
    CASE
        WHEN AVG(unit_price) < 2    THEN '1_Budget'
        WHEN AVG(unit_price) < 5    THEN '2_Value'
        WHEN AVG(unit_price) < 15   THEN '3_Mid'
        WHEN AVG(unit_price) < 50   THEN '4_Premium'
        ELSE                             '5_Luxury'
    END                                             AS price_tier,
    MIN(order_date)                                 AS first_seen_date,
    MAX(order_date)                                 AS last_seen_date,
    CAST(JULIANDAY(MAX(order_date)) - JULIANDAY(MIN(order_date)) AS INTEGER)
                                                    AS active_lifespan_days,
    COUNT(*)                                        AS total_orders,
    SUM(quantity)                                   AS total_units_sold,
    ROUND(SUM(line_revenue), 2)                     AS total_revenue
FROM vendra_transactions t1
GROUP BY sku;

-- Preview top SKUs
SELECT * FROM vendra_sku_catalog ORDER BY total_revenue DESC LIMIT 20;
