-- =============================================================
-- VENDRA CO. | SKU Churn & Catalog Health Analysis
-- File 04: At-Risk SKU Watchlist
-- Flags SKUs showing declining order frequency in Q4 2010
-- =============================================================


-- =============================================================
-- STEP 1: Create at-risk SKU table
-- Looks at Oct / Nov / Dec order trajectory per SKU
--
-- high_risk → orders in Oct, then complete silence in Nov + Dec
-- declining  → consecutive month-over-month drop all 3 months
-- =============================================================

DROP TABLE IF EXISTS vendra_at_risk_skus;

CREATE TABLE vendra_at_risk_skus AS
SELECT
    sku,
    oct_orders,
    nov_orders,
    dec_orders,
    CASE
        WHEN dec_orders = 0 AND nov_orders = 0 AND oct_orders > 0 THEN 'high_risk'
        WHEN dec_orders < nov_orders AND nov_orders < oct_orders  THEN 'declining'
        ELSE 'stable'
    END AS risk_flag
FROM (
    SELECT
        sku,
        SUM(CASE WHEN month = '2010-10' THEN orders ELSE 0 END) AS oct_orders,
        SUM(CASE WHEN month = '2010-11' THEN orders ELSE 0 END) AS nov_orders,
        SUM(CASE WHEN month = '2010-12' THEN orders ELSE 0 END) AS dec_orders
    FROM vendra_sku_activity
    GROUP BY sku
) sub;


-- =============================================================
-- STEP 2: Summary — how many SKUs in each risk category
-- =============================================================

SELECT
    risk_flag,
    COUNT(*) AS sku_count,
    ROUND(100.0 * COUNT(*) / (SELECT COUNT(*) FROM vendra_at_risk_skus), 1) AS pct_of_catalog
FROM vendra_at_risk_skus
GROUP BY risk_flag
ORDER BY sku_count DESC;


-- =============================================================
-- STEP 3: At-risk only — with product names and price tier
-- This is the actionable watchlist for merchandising
-- =============================================================

SELECT
    a.risk_flag,
    a.sku,
    c.product_name,
    c.price_tier,
    a.oct_orders,
    a.nov_orders,
    a.dec_orders,
    ROUND(c.total_revenue, 2)   AS lifetime_revenue
FROM vendra_at_risk_skus a
JOIN vendra_sku_catalog c ON a.sku = c.sku
WHERE a.risk_flag IN ('high_risk', 'declining')
ORDER BY a.risk_flag, lifetime_revenue DESC;


-- =============================================================
-- STEP 4: At-risk breakdown by price tier
-- Which tier is most exposed heading into 2011?
-- =============================================================

SELECT
    c.price_tier,
    COUNT(CASE WHEN a.risk_flag = 'high_risk' THEN 1 END)  AS high_risk_skus,
    COUNT(CASE WHEN a.risk_flag = 'declining' THEN 1 END)  AS declining_skus,
    COUNT(CASE WHEN a.risk_flag IN ('high_risk','declining') THEN 1 END) AS total_at_risk
FROM vendra_at_risk_skus a
JOIN vendra_sku_catalog c ON a.sku = c.sku
GROUP BY c.price_tier
ORDER BY c.price_tier;
