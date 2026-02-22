-- =============================================================
-- VENDRA CO. | SKU Churn & Catalog Health Analysis
-- File 02: SKU Activity Flags
-- Builds monthly activity matrix — every SKU x every month of 2010
-- =============================================================


-- =============================================================
-- STEP 1: Preview monthly activity per SKU (sense check)
-- =============================================================

SELECT
    sku,
    SUBSTR(order_date, 1, 7)        AS order_month,
    COUNT(*)                        AS orders_that_month,
    SUM(quantity)                   AS units_that_month,
    ROUND(SUM(line_revenue), 2)     AS revenue_that_month
FROM vendra_transactions
WHERE SUBSTR(order_date, 1, 4) = '2010'
GROUP BY sku, order_month
ORDER BY sku, order_month
LIMIT 30;


-- =============================================================
-- STEP 2: Create the activity matrix
-- Every SKU gets a row for every month — missing months = 0
-- This is the foundation for all churn logic
-- =============================================================

DROP TABLE IF EXISTS vendra_sku_activity;

CREATE TABLE vendra_sku_activity AS
SELECT
    s.sku,
    m.month,
    COALESCE(sm.orders, 0)                      AS orders,
    COALESCE(sm.revenue, 0.0)                   AS revenue,
    CASE WHEN sm.orders > 0 THEN 1 ELSE 0 END   AS is_active
FROM
    -- All SKUs active in 2010
    (SELECT DISTINCT sku FROM vendra_transactions
     WHERE SUBSTR(order_date, 1, 4) = '2010') s

CROSS JOIN
    -- All 12 months of 2010
    (SELECT '2010-01' AS month UNION ALL SELECT '2010-02' UNION ALL
     SELECT '2010-03' UNION ALL SELECT '2010-04' UNION ALL
     SELECT '2010-05' UNION ALL SELECT '2010-06' UNION ALL
     SELECT '2010-07' UNION ALL SELECT '2010-08' UNION ALL
     SELECT '2010-09' UNION ALL SELECT '2010-10' UNION ALL
     SELECT '2010-11' UNION ALL SELECT '2010-12') m

LEFT JOIN
    -- Actual monthly orders per SKU
    (SELECT
         sku,
         SUBSTR(order_date, 1, 7)        AS month,
         COUNT(*)                        AS orders,
         ROUND(SUM(line_revenue), 2)     AS revenue
     FROM vendra_transactions
     WHERE SUBSTR(order_date, 1, 4) = '2010'
     GROUP BY sku, month) sm
    ON s.sku = sm.sku AND m.month = sm.month

ORDER BY s.sku, m.month;


-- =============================================================
-- STEP 3: Verify
-- =============================================================

-- Should be exactly: unique 2010 SKUs × 12 months
SELECT COUNT(*) AS total_rows FROM vendra_sku_activity;

-- Preview — SKU 10002 should show is_active=1 all 12 months
-- SKU 10080 should show gaps
SELECT * FROM vendra_sku_activity
WHERE sku IN ('10002', '10002R', '10080')
ORDER BY sku, month;

-- Active vs inactive split
SELECT
    is_active,
    COUNT(*) AS row_count,
    ROUND(100.0 * COUNT(*) / (SELECT COUNT(*) FROM vendra_sku_activity), 1) AS pct
FROM vendra_sku_activity
GROUP BY is_active;
