-- ============================================================
-- View 2: reporting.v_weekly_totals
-- Report:  Weekly unusual order activity (Risk & Compliance)
-- Grain:   one row per purchase week (Monday start), 86 weeks
-- Source:  raw.orders (all orders), reporting.v_unusual_orders (view 1)
-- Defs:    docs/metric_definitions.md
-- ============================================================

CREATE OR REPLACE VIEW reporting.v_weekly_totals AS

WITH weekly_all_orders AS (
    -- Every order purchased in the window, any status (the denominator)
    SELECT
        DATE_TRUNC('week', order_purchase_timestamp)::date AS purchase_week,
        COUNT(*) AS all_orders
    FROM raw.orders
    WHERE order_purchase_timestamp >= DATE '2017-01-02'
      AND order_purchase_timestamp <  DATE '2018-08-27'
    GROUP BY purchase_week
),

weekly_unusual AS (
    -- Unusual orders per week. DISTINCT so a multi-seller order
    -- (2 rows in view 1) is still counted once.
    SELECT
        purchase_week,
        COUNT(DISTINCT order_id) AS unusual_orders
    FROM reporting.v_unusual_orders
    GROUP BY purchase_week
),

weekly AS (
    -- One row per week. LEFT JOIN keeps weeks with 0 unusual orders.
    -- 100.0 (not 100) avoids integer division, which cuts off decimals.
    SELECT
        a.purchase_week,
        a.all_orders,
        COALESCE(u.unusual_orders, 0) AS unusual_orders,
        100.0 * COALESCE(u.unusual_orders, 0) / a.all_orders AS unusual_rate_pct
    FROM weekly_all_orders a
    LEFT JOIN weekly_unusual u ON u.purchase_week = a.purchase_week
)

SELECT
    purchase_week,
    all_orders,
    unusual_orders,
    ROUND(unusual_rate_pct, 2) AS unusual_rate_pct,

    -- Week-on-week change. The first week is NULL: nothing to compare with.
    unusual_orders
      - LAG(unusual_orders) OVER (ORDER BY purchase_week) AS wow_change,

    -- Change in the rate, in percentage points
    ROUND(unusual_rate_pct
      - LAG(unusual_rate_pct) OVER (ORDER BY purchase_week), 2) AS rate_change_pp,

    -- % change, only when last week had 10+ unusual orders.
    -- On smaller bases (e.g. 2 -> 4 = +100%) a % misleads, so NULL.
    CASE
        WHEN LAG(unusual_orders) OVER (ORDER BY purchase_week) >= 10
        THEN ROUND(100.0 * (unusual_orders - LAG(unusual_orders) OVER (ORDER BY purchase_week))
                   / LAG(unusual_orders) OVER (ORDER BY purchase_week), 1)
    END AS wow_change_pct

FROM weekly;


-- ============================================================
-- Reconciliation checks
-- ============================================================

-- 1. Totals match the baseline. Expected: 86 | 98962 | 1168
SELECT
    COUNT(*)            AS weeks,
    SUM(all_orders)     AS all_orders,
    SUM(unusual_orders) AS unusual_orders
FROM reporting.v_weekly_totals;

-- 2. No gaps: every Monday from 2017-01-02 to 2018-08-20 is present.
--    Expected: 0 missing weeks
SELECT COUNT(*) AS missing_weeks
FROM generate_series(DATE '2017-01-02', DATE '2018-08-20', INTERVAL '7 days') AS w(week)
WHERE w.week::date NOT IN (SELECT purchase_week FROM reporting.v_weekly_totals);

-- 3. The week-on-week changes add up: sum of all changes = last week - first week.
--    Expected: diff_check = 0
SELECT
    SUM(wow_change)
      - (MAX(unusual_orders) FILTER (WHERE purchase_week = DATE '2018-08-20')
       - MAX(unusual_orders) FILTER (WHERE purchase_week = DATE '2017-01-02')) AS diff_check
FROM reporting.v_weekly_totals;

-- 4. Eyeball the first weeks. Expected wow_change: NULL, 2, 0
SELECT *
FROM reporting.v_weekly_totals
ORDER BY purchase_week
LIMIT 5;
