-- =============================================================
-- VENDRA CO. | SKU Churn & Catalog Health Analysis
-- File 03: SKU Churn Status & North Star Metrics
-- Uses LAG() window function to classify each SKU per month
-- =============================================================


-- =============================================================
-- STEP 1: Create churn status table
-- Each SKU gets a status for each month:
--   new        → first time appearing active
--   retained   → active last month AND this month
--   churned    → was active, now gone
--   reactivated→ back after being inactive
--   dormant    → inactive this month and last month
-- =============================================================

DROP TABLE IF EXISTS vendra_sku_churn;

CREATE TABLE vendra_sku_churn AS
SELECT
    sku,
    month,
    orders,
    revenue,
    is_active,
    LAG(is_active, 1, 0) OVER (PARTITION BY sku ORDER BY month) AS was_active_last_month,
    LAG(is_active, 2, 0) OVER (PARTITION BY sku ORDER BY month) AS was_active_2mo_ago,

    CASE
        -- NEW: active now, no activity in prior 3 months
        WHEN is_active = 1
             AND LAG(is_active, 1, 0) OVER (PARTITION BY sku ORDER BY month) = 0
             AND LAG(is_active, 2, 0) OVER (PARTITION BY sku ORDER BY month) = 0
             AND LAG(is_active, 3, 0) OVER (PARTITION BY sku ORDER BY month) = 0
             THEN 'new'

        -- RETAINED: active this month and last month
        WHEN is_active = 1
             AND LAG(is_active, 1, 0) OVER (PARTITION BY sku ORDER BY month) = 1
             THEN 'retained'

        -- CHURNED: was active, now gone
        WHEN is_active = 0
             AND LAG(is_active, 1, 0) OVER (PARTITION BY sku ORDER BY month) = 1
             THEN 'churned'

        -- REACTIVATED: back after a gap
        WHEN is_active = 1
             AND LAG(is_active, 1, 0) OVER (PARTITION BY sku ORDER BY month) = 0
             AND (LAG(is_active, 2, 0) OVER (PARTITION BY sku ORDER BY month) = 1
              OR  LAG(is_active, 3, 0) OVER (PARTITION BY sku ORDER BY month) = 1)
             THEN 'reactivated'

        -- DORMANT: inactive this month and last month
        WHEN is_active = 0
             AND LAG(is_active, 1, 0) OVER (PARTITION BY sku ORDER BY month) = 0
             THEN 'dormant'

        ELSE 'other'
    END AS sku_status

FROM vendra_sku_activity
ORDER BY sku, month;


-- =============================================================
-- STEP 2: Verify — status distribution
-- =============================================================

SELECT
    sku_status,
    COUNT(*)                                                        AS count,
    ROUND(100.0 * COUNT(*) / (SELECT COUNT(*) FROM vendra_sku_churn), 1) AS pct
FROM vendra_sku_churn
GROUP BY sku_status
ORDER BY count DESC;


-- =============================================================
-- STEP 3: North Star — SKU Retention Rate by month
-- This is the headline metric for the Tableau dashboard
-- =============================================================

SELECT
    month,
    SUM(CASE WHEN sku_status = 'retained'    THEN 1 ELSE 0 END)    AS retained,
    SUM(CASE WHEN sku_status = 'churned'     THEN 1 ELSE 0 END)    AS churned,
    SUM(CASE WHEN sku_status = 'new'         THEN 1 ELSE 0 END)    AS new_skus,
    SUM(CASE WHEN sku_status = 'reactivated' THEN 1 ELSE 0 END)    AS reactivated,
    SUM(CASE WHEN sku_status = 'dormant'     THEN 1 ELSE 0 END)    AS dormant,
    ROUND(100.0 *
        SUM(CASE WHEN sku_status = 'retained' THEN 1 ELSE 0 END) /
        NULLIF(SUM(CASE WHEN sku_status IN ('retained','churned') THEN 1 ELSE 0 END), 0), 1)
                                                                    AS retention_rate_pct
FROM vendra_sku_churn
GROUP BY month
ORDER BY month;


-- =============================================================
-- STEP 4: Supporting metric — Churn by Price Tier
-- Join vendra_sku_catalog for price_tier segmentation
-- =============================================================

SELECT
    c.price_tier,
    COUNT(DISTINCT ch.sku)                                              AS total_skus,
    SUM(CASE WHEN ch.sku_status = 'churned'  THEN 1 ELSE 0 END)        AS churn_events,
    SUM(CASE WHEN ch.sku_status = 'retained' THEN 1 ELSE 0 END)        AS retained_events,
    ROUND(100.0 *
        SUM(CASE WHEN ch.sku_status = 'churned' THEN 1 ELSE 0 END) /
        NULLIF(SUM(CASE WHEN ch.sku_status IN ('retained','churned') THEN 1 ELSE 0 END), 0), 1)
                                                                        AS churn_rate_pct,
    ROUND(AVG(c.active_lifespan_days), 0)                               AS avg_lifespan_days
FROM vendra_sku_churn ch
JOIN vendra_sku_catalog c ON ch.sku = c.sku
GROUP BY c.price_tier
ORDER BY c.price_tier;
