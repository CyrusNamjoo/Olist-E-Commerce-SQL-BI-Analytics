-- ============================================================
-- View 3: reporting.v_weekly_by_region
-- Report:   Weekly unusual order activity (Risk & Compliance)
-- Question: Each week, where are unusual orders coming from,
--           and is any region getting worse?
-- Grain:    one row per purchase week x seller region (86 x 7 = 602)
-- Source:   reporting.v_unusual_orders (view 1),
--           reporting.v_weekly_totals (view 2, for the list of weeks)
-- Rule:     states with < 10 unusual orders in the window -> 'Other'
-- Defs:     docs/metric_definitions.md
-- ============================================================

CREATE OR REPLACE VIEW reporting.v_weekly_by_region AS

WITH state_totals AS (
    -- a. Unusual orders per seller state over the whole window,
    --    used to decide which states are too small to show alone
    SELECT
        seller_state,
        COUNT(DISTINCT order_id) AS unusual_orders
    FROM reporting.v_unusual_orders
    GROUP BY seller_state
),

orders_with_region AS (
    -- b. Each unusual order with its report region:
    --    small states become 'Other', the rest keep their state
    SELECT
        v.order_id,
        v.purchase_week,
        CASE
            WHEN t.unusual_orders < 10 THEN 'Other'
            ELSE v.seller_state
        END AS region
    FROM reporting.v_unusual_orders v
    JOIN state_totals t ON t.seller_state = v.seller_state
),

weekly_region AS (
    -- c. Unusual orders per week and region.
    --    Only has a row when a region had orders that week.
    SELECT
        purchase_week,
        region,
        COUNT(DISTINCT order_id) AS unusual_orders
    FROM orders_with_region
    GROUP BY purchase_week, region
),

week_region_grid AS (
    -- d. Every week x every region, so weeks with 0 orders exist as rows.
    --    Without this, LAG would compare with the last week that HAD orders.
    SELECT
        w.purchase_week,
        r.region
    FROM reporting.v_weekly_totals w
    CROSS JOIN (SELECT DISTINCT region FROM orders_with_region) r
)

SELECT
    g.purchase_week,
    g.region,
    COALESCE(w.unusual_orders, 0) AS unusual_orders,

    -- Week-on-week change within each region (PARTITION BY region).
    -- First week of each region is NULL: nothing to compare with.
    COALESCE(w.unusual_orders, 0)
      - LAG(COALESCE(w.unusual_orders, 0))
            OVER (PARTITION BY g.region ORDER BY g.purchase_week) AS wow_change

FROM week_region_grid g
LEFT JOIN weekly_region w
    ON  w.purchase_week = g.purchase_week
    AND w.region        = g.region;


-- ============================================================
-- Reconciliation checks
-- ============================================================

-- 1. Size and total. Expected: 602 rows | 86 weeks | 7 regions | 1168 orders
SELECT
    COUNT(*)                      AS view_rows,
    COUNT(DISTINCT purchase_week) AS weeks,
    COUNT(DISTINCT region)        AS regions,
    SUM(unusual_orders)           AS unusual_orders
FROM reporting.v_weekly_by_region;

-- 2. Region totals. Expected: Unattributed 720 | SP 327 | MG 48 |
--    PR 24 | RJ 18 | SC 17 | Other 14
SELECT region, SUM(unusual_orders) AS unusual_orders
FROM reporting.v_weekly_by_region
GROUP BY region
ORDER BY unusual_orders DESC;

-- 3. Every week's regions add up to view 2's weekly total. Expected: 0
SELECT COUNT(*) AS weeks_not_matching
FROM (
    SELECT purchase_week, SUM(unusual_orders) AS region_sum
    FROM reporting.v_weekly_by_region
    GROUP BY purchase_week
) r
JOIN reporting.v_weekly_totals t USING (purchase_week)
WHERE r.region_sum <> t.unusual_orders;

-- 4. Exactly one NULL wow_change per region (its first week). Expected: 7
SELECT COUNT(*) AS null_wow_rows
FROM reporting.v_weekly_by_region
WHERE wow_change IS NULL;
