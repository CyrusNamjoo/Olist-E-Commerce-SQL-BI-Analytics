-- ============================================================
-- Olist E-Commerce SQL & Business Intelligence Analytics
-- Business Analysis
-- PostgreSQL 18
--
-- Purpose:
-- Answer business questions using the validated analytics layer.
-- ============================================================


-- ============================================================
-- Q1. What is the overall scale and commercial performance
--     of the marketplace during the observed period?
-- ============================================================

WITH order_metrics AS (
    SELECT
        COUNT(*) AS total_orders,

        COUNT(*) FILTER (
            WHERE order_status = 'delivered'
        ) AS delivered_orders,

        COUNT(*) FILTER (
            WHERE order_status = 'canceled'
        ) AS canceled_orders,

        MIN(purchase_date) AS first_purchase_date,
        MAX(purchase_date) AS last_purchase_date

    FROM analytics.fact_orders
),

customer_metrics AS (
    SELECT
        COUNT(DISTINCT customer_unique_id)
            AS unique_shoppers
    FROM analytics.dim_customers
),

item_metrics AS (
    SELECT
        COUNT(*) AS items_sold,
        COUNT(DISTINCT product_id) AS products_sold,
        COUNT(DISTINCT seller_id) AS active_sellers,

        ROUND(SUM(price), 2)
            AS gross_product_value,

        ROUND(SUM(freight_value), 2)
            AS total_freight_value,

        ROUND(SUM(item_total_value), 2)
            AS total_item_value

    FROM analytics.fact_order_items
),

payment_metrics AS (
    SELECT
        ROUND(SUM(payment_value), 2)
            AS total_payment_value
    FROM analytics.fact_payments
)

SELECT
    o.total_orders,
    o.delivered_orders,
    o.canceled_orders,

    ROUND(
        100.0 * o.delivered_orders / o.total_orders,
        2
    ) AS delivered_order_pct,

    c.unique_shoppers,

    i.items_sold,
    i.products_sold,
    i.active_sellers,

    i.gross_product_value,
    i.total_freight_value,
    i.total_item_value,
    p.total_payment_value,

    o.first_purchase_date,
    o.last_purchase_date

FROM order_metrics o
CROSS JOIN customer_metrics c
CROSS JOIN item_metrics i
CROSS JOIN payment_metrics p;

-- ============================================================
-- Q2. How did marketplace sales performance change over time?
-- ============================================================
--
-- Monthly trend analysis uses January 2017 through August 2018.
-- Earlier months contain sparse/incomplete transaction coverage,
-- while September–October 2018 are also incomplete.
-- These periods are excluded from month-over-month analysis to
-- avoid interpreting data-coverage artifacts as business trends.
--
-- Demonstrates:
-- - CTEs
-- - DATE_TRUNC
-- - aggregation
-- - LAG window function
-- - month-over-month growth
-- ============================================================

WITH monthly_sales AS (
    SELECT
        DATE_TRUNC('month', purchase_date)::DATE AS month,

        COUNT(DISTINCT order_id) AS orders,

        COUNT(*) AS items_sold,

        ROUND(SUM(price), 2) AS product_value,

        ROUND(SUM(freight_value), 2) AS freight_value,

        ROUND(SUM(item_total_value), 2) AS item_total_value

    FROM analytics.fact_order_items

    WHERE purchase_date >= DATE '2017-01-01'
      AND purchase_date <  DATE '2018-09-01'

    GROUP BY 1
),

with_previous_month AS (
    SELECT
        *,

        LAG(product_value)
            OVER (ORDER BY month)
            AS previous_month_product_value

    FROM monthly_sales
)

SELECT
    month,
    orders,
    items_sold,
    product_value,
    freight_value,
    item_total_value,

    ROUND(
        product_value / NULLIF(orders, 0),
        2
    ) AS product_value_per_order,

    ROUND(
        100.0 *
        (
            product_value - previous_month_product_value
        )
        / NULLIF(previous_month_product_value, 0),
        2
    ) AS product_value_mom_pct

FROM with_previous_month

ORDER BY month;

-- ============================================================
-- Q3. Which product categories drive marketplace value?
-- ============================================================
--
-- Purpose:
-- Identify leading categories by product value and quantify
-- their contribution to total marketplace product value.
--
-- Demonstrates:
-- - aggregation
-- - window functions
-- - RANK
-- - percentage contribution
-- ============================================================

WITH category_performance AS (
    SELECT
        category_name_english AS category,

        COUNT(DISTINCT order_id) AS orders,
        COUNT(*) AS items_sold,

        ROUND(SUM(price), 2) AS product_value,

        ROUND(AVG(price), 2) AS avg_item_price

    FROM analytics.fact_order_items

    GROUP BY category_name_english
),

ranked_categories AS (
    SELECT
        *,

        RANK() OVER (
            ORDER BY product_value DESC
        ) AS value_rank,

        ROUND(
            100.0 * product_value
            / SUM(product_value) OVER (),
            2
        ) AS product_value_share_pct

    FROM category_performance
)

SELECT
    value_rank,
    category,
    orders,
    items_sold,
    product_value,
    product_value_share_pct,
    avg_item_price

FROM ranked_categories

ORDER BY value_rank
LIMIT 15;

-- ============================================================
-- Q4. How much repeat purchasing exists in the marketplace?
-- ============================================================
--
-- customer_unique_id is used because customer_id represents
-- an order-level customer record rather than persistent shopper
-- identity.
--
-- Demonstrates:
-- - customer-level aggregation
-- - conditional aggregation
-- - segmentation
-- - CTEs
-- ============================================================

WITH customer_orders AS (
    SELECT
        c.customer_unique_id,
        COUNT(DISTINCT o.order_id) AS order_count,

        MIN(o.purchase_date) AS first_purchase_date,
        MAX(o.purchase_date) AS last_purchase_date

    FROM analytics.fact_orders o

    INNER JOIN analytics.dim_customers c
        ON o.customer_id = c.customer_id

    GROUP BY c.customer_unique_id
),

customer_segments AS (
    SELECT
        *,

        CASE
            WHEN order_count = 1 THEN 'One-time'
            WHEN order_count BETWEEN 2 AND 3 THEN 'Repeat (2-3)'
            ELSE 'Repeat (4+)'
        END AS customer_segment

    FROM customer_orders
)

SELECT
    customer_segment,

    COUNT(*) AS customers,

    ROUND(
        100.0 * COUNT(*) / SUM(COUNT(*)) OVER (),
        2
    ) AS customer_share_pct,

    SUM(order_count) AS orders,

    ROUND(
        AVG(order_count),
        2
    ) AS avg_orders_per_customer

FROM customer_segments

GROUP BY customer_segment

ORDER BY
    MIN(order_count);

-- ============================================================
-- Q5. Which customer states drive marketplace activity?
-- ============================================================
--
-- Purpose:
-- Compare geographic markets using customer location,
-- order activity and product value.
--
-- Product value is aggregated from the item-level fact.
-- ============================================================

WITH state_performance AS (
    SELECT
        customer_state AS state,

        COUNT(DISTINCT order_id) AS orders,
        COUNT(DISTINCT customer_unique_id) AS unique_shoppers,
        COUNT(*) AS items_sold,

        ROUND(SUM(price), 2) AS product_value

    FROM analytics.fact_order_items

    GROUP BY customer_state
),

ranked_states AS (
    SELECT
        *,

        RANK() OVER (
            ORDER BY product_value DESC
        ) AS value_rank,

        ROUND(
            100.0 * product_value
            / SUM(product_value) OVER (),
            2
        ) AS product_value_share_pct

    FROM state_performance
)

SELECT
    value_rank,
    state,
    orders,
    unique_shoppers,
    items_sold,
    product_value,
    product_value_share_pct,

    ROUND(
        product_value / NULLIF(orders, 0),
        2
    ) AS product_value_per_order

FROM ranked_states

ORDER BY value_rank;

-- ============================================================
-- Q6. How concentrated is marketplace product value among
--     sellers?
-- ============================================================
--
-- Purpose:
-- Rank sellers by product value and measure how much marketplace
-- value is generated by the highest-performing sellers.
--
-- Demonstrates:
-- - seller-level aggregation
-- - ranking
-- - cumulative window functions
-- - contribution analysis
-- ============================================================

WITH seller_performance AS (
    SELECT
        seller_id,
        seller_state,

        COUNT(DISTINCT order_id) AS orders,
        COUNT(*) AS items_sold,

        ROUND(SUM(price), 2) AS product_value,

        ROUND(AVG(price), 2) AS avg_item_price

    FROM analytics.fact_order_items

    GROUP BY
        seller_id,
        seller_state
),

ranked_sellers AS (
    SELECT
        *,

        ROW_NUMBER() OVER (
            ORDER BY product_value DESC
        ) AS seller_rank,

        ROUND(
            100.0 * product_value
            / SUM(product_value) OVER (),
            2
        ) AS product_value_share_pct,

        ROUND(
            100.0 * SUM(product_value) OVER (
                ORDER BY product_value DESC
                ROWS BETWEEN UNBOUNDED PRECEDING
                         AND CURRENT ROW
            )
            / SUM(product_value) OVER (),
            2
        ) AS cumulative_value_share_pct

    FROM seller_performance
)

SELECT
    seller_rank,
    seller_id,
    seller_state,
    orders,
    items_sold,
    product_value,
    product_value_share_pct,
    cumulative_value_share_pct,
    avg_item_price

FROM ranked_sellers

ORDER BY seller_rank

LIMIT 20;

-- ============================================================
-- Q7. How does delivery performance relate to customer
--     satisfaction?
-- ============================================================
--
-- Purpose:
-- Compare review outcomes between on-time/early and late
-- deliveries.
--
-- Only reviews linked to orders with an actual delivery date
-- and estimated delivery date are included.
--
-- Demonstrates:
-- - operational/customer-experience linkage
-- - conditional segmentation
-- - aggregation
-- - percentage calculations
-- ============================================================

WITH delivery_reviews AS (
    SELECT
        r.review_id,
        r.order_id,
        r.review_score,
        r.days_vs_estimate,

        CASE
            WHEN r.days_vs_estimate > 0
                THEN 'Late'
            ELSE 'On-time / Early'
        END AS delivery_status

    FROM analytics.fact_reviews r

    WHERE r.days_vs_estimate IS NOT NULL
)

SELECT
    delivery_status,

    COUNT(*) AS reviews,

    ROUND(
        AVG(review_score),
        2
    ) AS avg_review_score,

    COUNT(*) FILTER (
        WHERE review_score = 1
    ) AS one_star_reviews,

    ROUND(
        100.0 * COUNT(*) FILTER (
            WHERE review_score = 1
        ) / COUNT(*),
        2
    ) AS one_star_pct,

    COUNT(*) FILTER (
        WHERE review_score = 5
    ) AS five_star_reviews,

    ROUND(
        100.0 * COUNT(*) FILTER (
            WHERE review_score = 5
        ) / COUNT(*),
        2
    ) AS five_star_pct,

    ROUND(
        AVG(days_vs_estimate),
        2
    ) AS avg_days_vs_estimate

FROM delivery_reviews

GROUP BY delivery_status

ORDER BY
    CASE
        WHEN delivery_status = 'On-time / Early' THEN 1
        ELSE 2
    END;

-- ============================================================
-- Q8. Which customer states experience the highest late-
--     delivery rates?
-- ============================================================
--
-- Purpose:
-- Identify geographic differences in delivery performance.
--
-- Only orders with an actual customer delivery date are used.
-- States with fewer than 100 delivered orders are excluded from
-- ranking to reduce instability from very small samples.
--
-- Demonstrates:
-- - conditional aggregation
-- - operational segmentation
-- - minimum sample-size filtering
-- - ranking
-- ============================================================

WITH state_delivery AS (
    SELECT
        c.customer_state AS state,

        COUNT(*) AS delivered_orders,

        COUNT(*) FILTER (
            WHERE o.late_delivery_flag = TRUE
        ) AS late_orders,

        ROUND(
            AVG(o.delivery_days),
            2
        ) AS avg_delivery_days,

        ROUND(
            AVG(o.days_vs_estimate),
            2
        ) AS avg_days_vs_estimate

    FROM analytics.fact_orders o

    INNER JOIN analytics.dim_customers c
        ON o.customer_id = c.customer_id

    WHERE o.order_delivered_customer_date IS NOT NULL

    GROUP BY c.customer_state
),

ranked_states AS (
    SELECT
        *,

        ROUND(
            100.0 * late_orders
            / NULLIF(delivered_orders, 0),
            2
        ) AS late_delivery_pct

    FROM state_delivery

    WHERE delivered_orders >= 100
)

SELECT
    state,
    delivered_orders,
    late_orders,
    late_delivery_pct,
    avg_delivery_days,
    avg_days_vs_estimate

FROM ranked_states

ORDER BY late_delivery_pct DESC;

-- ============================================================
-- Q9. How do customers pay for marketplace orders?
-- ============================================================
--
-- Purpose:
-- Understand payment-method adoption, monetary contribution,
-- and installment behavior.
--
-- IMPORTANT:
-- Grain is payment record, not order. An order can contain
-- multiple payment records/payment methods.
-- ============================================================

WITH payment_method_performance AS (
    SELECT
        payment_type,

        COUNT(*) AS payment_records,
        COUNT(DISTINCT order_id) AS orders_using_method,

        ROUND(
            SUM(payment_value),
            2
        ) AS payment_value,

        ROUND(
            AVG(payment_value),
            2
        ) AS avg_payment_value,

        ROUND(
            AVG(payment_installments),
            2
        ) AS avg_installments

    FROM analytics.fact_payments

    GROUP BY payment_type
)

SELECT
    payment_type,
    payment_records,
    orders_using_method,
    payment_value,

    ROUND(
        100.0 * payment_value
        / SUM(payment_value) OVER (),
        2
    ) AS payment_value_share_pct,

    avg_payment_value,
    avg_installments

FROM payment_method_performance

ORDER BY payment_value DESC;

-- ============================================================
-- Q10. How does customer value differ between one-time and
--      repeat shoppers?
-- ============================================================
--
-- Purpose:
-- Compare purchasing behavior and product value at the persistent
-- shopper level using customer_unique_id.
--
-- Product value is used rather than payment value to avoid
-- mixing payment-record grain with item-level purchasing.
--
-- Demonstrates:
-- - multi-level aggregation
-- - customer-level metrics
-- - segmentation
-- - conditional business logic
-- ============================================================

WITH customer_value AS (
    SELECT
        i.customer_unique_id,

        COUNT(DISTINCT i.order_id) AS orders,
        COUNT(*) AS items_purchased,

        SUM(i.price) AS product_value

    FROM analytics.fact_order_items i

    GROUP BY i.customer_unique_id
),

segmented_customers AS (
    SELECT
        *,

        CASE
            WHEN orders = 1 THEN 'One-time'
            ELSE 'Repeat'
        END AS customer_segment

    FROM customer_value
)

SELECT
    customer_segment,

    COUNT(*) AS customers,

    SUM(orders) AS orders,
    SUM(items_purchased) AS items_purchased,

    ROUND(
        SUM(product_value),
        2
    ) AS product_value,

    ROUND(
        AVG(product_value),
        2
    ) AS avg_product_value_per_customer,

    ROUND(
        AVG(orders),
        2
    ) AS avg_orders_per_customer,

    ROUND(
        AVG(items_purchased),
        2
    ) AS avg_items_per_customer

FROM segmented_customers

GROUP BY customer_segment

ORDER BY
    CASE
        WHEN customer_segment = 'One-time' THEN 1
        ELSE 2
    END;