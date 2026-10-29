-- ============================================================
-- View 1: reporting.v_unusual_orders
-- Report:  Weekly unusual order activity (Risk & Compliance)
-- Grain:   one row per unusual order per seller
--          (= one row per order in the reporting window, because
--           no unusual order there has more than one seller;
--           check 2 below must stay 0 at every refresh)
-- Source:  raw.orders, raw.order_items, raw.sellers,
--          raw.customers, raw.order_payments
-- Defs:    docs/metric_definitions.md
-- ============================================================

CREATE SCHEMA IF NOT EXISTS reporting;

CREATE OR REPLACE VIEW reporting.v_unusual_orders AS

WITH unusual_orders AS (
    -- Canceled or unavailable orders purchased in the reporting window
    -- (Mon 2 Jan 2017 to Sun 26 Aug 2018: 86 full weeks)
    SELECT
        order_id,
        customer_id,
        order_status,
        order_purchase_timestamp
    FROM raw.orders
    WHERE order_status IN ('canceled', 'unavailable')
      AND order_purchase_timestamp >= DATE '2017-01-02'
      AND order_purchase_timestamp <  DATE '2018-08-27'
),

order_sellers AS (
    -- One row per order and seller.
    -- An order can have several items from the same seller, so DISTINCT
    -- stops the item rows from duplicating the order.
    SELECT DISTINCT
        order_id,
        seller_id
    FROM raw.order_items
),

order_payments AS (
    -- Payments summed to one row per order BEFORE joining,
    -- because one order can have several payment rows (card + vouchers)
    SELECT
        order_id,
        SUM(payment_value) AS amount_paid
    FROM raw.order_payments
    GROUP BY order_id
)

SELECT
    u.order_id,
    u.order_status,
    u.order_purchase_timestamp,
    DATE_TRUNC('week', u.order_purchase_timestamp)::date AS purchase_week,  -- Monday
    os.seller_id,                                       -- NULL = no items
    COALESCE(s.seller_state, 'Unattributed') AS seller_state,
    c.customer_state,
    COALESCE(p.amount_paid, 0) AS amount_paid

FROM unusual_orders u

-- LEFT JOIN: 720 unusual orders have no items. An INNER JOIN would drop them.
LEFT JOIN order_sellers  os ON os.order_id   = u.order_id
LEFT JOIN raw.sellers     s ON s.seller_id   = os.seller_id
LEFT JOIN raw.customers   c ON c.customer_id = u.customer_id
LEFT JOIN order_payments  p ON p.order_id    = u.order_id;


-- ============================================================
-- Reconciliation checks: run after every change or refresh.
-- Expected values are the baseline in docs/metric_definitions.md.
-- ============================================================

-- 1. Totals match the baseline
--    Expected: 1168 rows | 1168 orders | 566 canceled | 602 unavailable
--              720 unattributed | 254721.50 paid
SELECT
    COUNT(*)                                             AS view_rows,
    COUNT(DISTINCT order_id)                             AS orders,
    COUNT(*) FILTER (WHERE order_status = 'canceled')    AS canceled,
    COUNT(*) FILTER (WHERE order_status = 'unavailable') AS unavailable,
    COUNT(*) FILTER (WHERE seller_id IS NULL)            AS unattributed,
    SUM(amount_paid)                                     AS total_paid
FROM reporting.v_unusual_orders;

-- 2. No order appears twice (multi-seller orders). Expected: 0
SELECT COUNT(*) AS duplicated_orders
FROM (
    SELECT order_id
    FROM reporting.v_unusual_orders
    GROUP BY order_id
    HAVING COUNT(*) > 1
) d;

-- 3. Same total by a second method: straight from raw.orders. Expected: 1168
SELECT COUNT(*) AS unusual_orders_raw
FROM raw.orders
WHERE order_status IN ('canceled', 'unavailable')
  AND order_purchase_timestamp >= DATE '2017-01-02'
  AND order_purchase_timestamp <  DATE '2018-08-27';

-- 4. Every order has a customer region. Expected: 0
SELECT COUNT(*) AS missing_customer_state
FROM reporting.v_unusual_orders
WHERE customer_state IS NULL;
