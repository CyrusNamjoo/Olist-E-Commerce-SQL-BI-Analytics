-- ============================================================
-- View 4: reporting.v_seller_trailing_4w
-- Report:   Weekly unusual order activity (Risk & Compliance)
-- Question: Which sellers have had the most unusual orders recently?
-- Grain:    one row per report week x seller, for sellers with at least
--           1 unusual order in the 4 weeks up to and including that week
-- Source:   reporting.v_unusual_orders (view 1),
--           reporting.v_weekly_totals (view 2, for the list of weeks)
-- Why 4 weeks: most sellers have only 1 unusual order in the whole
--           window, so a per-seller week-on-week change would be noise.
-- WARNING:  orders_last_4w is a ROLLING count. Each order is counted in
--           up to 4 report weeks, so never SUM it across weeks.
-- Defs:     docs/metric_definitions.md
-- ============================================================

CREATE OR REPLACE VIEW reporting.v_seller_trailing_4w AS

WITH seller_orders AS (
    -- a. Unusual orders that have a seller.
    --    Unattributed orders (no items) can't be ranked by seller.
    SELECT
        order_id,
        seller_id,
        seller_state,
        purchase_week
    FROM reporting.v_unusual_orders
    WHERE seller_id IS NOT NULL
),

seller_last_4w AS (
    -- b. For each report week: orders from that week and the 3 weeks
    --    before it (report_week - 21 days), counted per seller
    SELECT
        w.purchase_week            AS report_week,
        s.seller_id,
        s.seller_state,
        COUNT(DISTINCT s.order_id) AS orders_last_4w
    FROM reporting.v_weekly_totals w
    JOIN seller_orders s
        ON s.purchase_week BETWEEN w.purchase_week - 21 AND w.purchase_week
    GROUP BY w.purchase_week, s.seller_id, s.seller_state
)

-- c. Rank sellers within each report week.
--    RANK(): ties share a rank (two sellers with 3 orders are both rank 1).
SELECT
    report_week,
    seller_id,
    seller_state,
    orders_last_4w,
    RANK() OVER (PARTITION BY report_week ORDER BY orders_last_4w DESC) AS seller_rank
FROM seller_last_4w;


-- ============================================================
-- Reconciliation checks
-- ============================================================

-- 1. Size. Expected: 1569 rows | max 5 orders for one seller in 4 weeks
SELECT
    COUNT(*)            AS view_rows,
    MAX(orders_last_4w) AS max_orders_last_4w
FROM reporting.v_seller_trailing_4w;

-- 2. Second method: for every report week, the sellers' 4-week counts must
--    equal a direct count of attributed orders in the same 4 weeks.
--    Expected: 0 weeks not matching
SELECT COUNT(*) AS weeks_not_matching
FROM (
    SELECT report_week, SUM(orders_last_4w) AS seller_sum
    FROM reporting.v_seller_trailing_4w
    GROUP BY report_week
) v
JOIN (
    SELECT w.purchase_week AS report_week, COUNT(DISTINCT u.order_id) AS direct_count
    FROM reporting.v_weekly_totals w
    JOIN reporting.v_unusual_orders u
        ON  u.purchase_week BETWEEN w.purchase_week - 21 AND w.purchase_week
        AND u.seller_id IS NOT NULL
    GROUP BY w.purchase_week
) d USING (report_week)
WHERE v.seller_sum <> d.direct_count;

-- 3. Every report week's ranking starts at 1. Expected: 0
SELECT COUNT(*) AS weeks_without_rank_1
FROM (
    SELECT report_week, MIN(seller_rank) AS top_rank
    FROM reporting.v_seller_trailing_4w
    GROUP BY report_week
) r
WHERE top_rank <> 1;

-- 4. Example: top sellers for one week
SELECT *
FROM reporting.v_seller_trailing_4w
WHERE report_week = DATE '2018-08-20'
ORDER BY seller_rank
LIMIT 10;
