-- ============================================================
-- Olist E-Commerce SQL & Business Intelligence Analytics
-- Analytics layer
-- PostgreSQL 18
--
-- Purpose:
-- Create analysis-ready views from the source-faithful raw layer.
-- Raw data is never overwritten.
-- ============================================================


-- ============================================================
-- 1. Clean ZIP-level geolocation dimension
-- ============================================================
--
-- Problem:
-- raw.geolocation contains multiple observations per ZIP prefix
-- and cannot safely be joined directly to customers or sellers.
--
-- Strategy:
-- - One row per ZIP prefix
-- - Median latitude and longitude to reduce sensitivity to outliers
-- - Most frequent city/state as representative labels
-- - Preserve source counts for transparency
-- ============================================================

CREATE OR REPLACE VIEW analytics.dim_geolocation AS

SELECT
    geolocation_zip_code_prefix,

    PERCENTILE_CONT(0.5)
        WITHIN GROUP (ORDER BY geolocation_lat)
        AS latitude,

    PERCENTILE_CONT(0.5)
        WITHIN GROUP (ORDER BY geolocation_lng)
        AS longitude,

    MODE()
        WITHIN GROUP (ORDER BY geolocation_city)
        AS city,

    MODE()
        WITHIN GROUP (ORDER BY geolocation_state)
        AS state,

    COUNT(*) AS source_row_count,

    COUNT(
        DISTINCT (
            geolocation_lat,
            geolocation_lng
        )
    ) AS distinct_coordinate_count

FROM raw.geolocation

GROUP BY geolocation_zip_code_prefix;

SELECT
    COUNT(*) AS zip_rows,
    COUNT(DISTINCT geolocation_zip_code_prefix) AS distinct_zip_prefixes,
    MIN(source_row_count) AS min_source_rows_per_zip,
    MAX(source_row_count) AS max_source_rows_per_zip
FROM analytics.dim_geolocation;

SELECT *
FROM analytics.dim_geolocation
ORDER BY source_row_count DESC
LIMIT 10;

-- ============================================================
-- 2. Product dimension with category enrichment
-- ============================================================
--
-- Strategy:
-- - Preserve the original Portuguese category
-- - Add the available English translation
-- - Label missing categories explicitly
-- - Preserve untranslated categories rather than discarding them
-- - Flag physically invalid zero-weight products
-- ============================================================

CREATE OR REPLACE VIEW analytics.dim_products AS

SELECT
    p.product_id,

    p.product_category_name AS category_name_original,

    CASE
        WHEN p.product_category_name IS NULL
            THEN 'Unknown'

        WHEN t.product_category_name_english IS NULL
            THEN 'Untranslated: ' || p.product_category_name

        ELSE t.product_category_name_english
    END AS category_name_english,

    p.product_name_lenght,
    p.product_description_lenght,
    p.product_photos_qty,
    p.product_weight_g,
    p.product_length_cm,
    p.product_height_cm,
    p.product_width_cm,

    CASE
        WHEN p.product_weight_g = 0 THEN TRUE
        ELSE FALSE
    END AS invalid_weight_flag

FROM raw.products p

LEFT JOIN raw.product_category_name_translation t
    ON p.product_category_name = t.product_category_name;

SELECT
    COUNT(*) AS product_rows,

    COUNT(DISTINCT product_id) AS distinct_products,

    COUNT(*) FILTER (
        WHERE category_name_original IS NULL
    ) AS unknown_category_products,

    COUNT(*) FILTER (
        WHERE category_name_english LIKE 'Untranslated:%'
    ) AS untranslated_product_rows,

    COUNT(DISTINCT category_name_original) FILTER (
        WHERE category_name_english LIKE 'Untranslated:%'
    ) AS untranslated_categories,

    COUNT(*) FILTER (
        WHERE invalid_weight_flag = TRUE
    ) AS invalid_weight_products

FROM analytics.dim_products;

-- ============================================================
-- 3. Customer dimension with geographic enrichment
-- ============================================================
--
-- customer_id:
-- Order-level customer identifier used by the source system.
--
-- customer_unique_id:
-- Persistent shopper identifier used for customer-level analysis.
--
-- Geography is enriched from the cleaned ZIP-level dimension.
-- Missing geolocation matches are preserved through LEFT JOIN.
-- ============================================================

CREATE OR REPLACE VIEW analytics.dim_customers AS

SELECT
    c.customer_id,
    c.customer_unique_id,
    c.customer_zip_code_prefix,
    c.customer_city,
    c.customer_state,

    g.latitude,
    g.longitude,

    CASE
        WHEN g.geolocation_zip_code_prefix IS NULL THEN FALSE
        ELSE TRUE
    END AS geolocation_match_flag

FROM raw.customers c

LEFT JOIN analytics.dim_geolocation g
    ON c.customer_zip_code_prefix =
       g.geolocation_zip_code_prefix;

SELECT
    COUNT(*) AS customer_rows,

    COUNT(DISTINCT customer_id)
        AS distinct_customer_ids,

    COUNT(DISTINCT customer_unique_id)
        AS distinct_unique_shoppers,

    COUNT(*) FILTER (
        WHERE geolocation_match_flag = FALSE
    ) AS customers_without_geolocation,

    COUNT(DISTINCT customer_zip_code_prefix) FILTER (
        WHERE geolocation_match_flag = FALSE
    ) AS unmatched_zip_prefixes

FROM analytics.dim_customers;

-- ============================================================
-- 4. Seller dimension with geographic enrichment
-- ============================================================
--
-- Geography is enriched from the cleaned ZIP-level dimension.
-- Sellers without a geolocation match are preserved.
-- ============================================================

CREATE OR REPLACE VIEW analytics.dim_sellers AS

SELECT
    s.seller_id,
    s.seller_zip_code_prefix,
    s.seller_city,
    s.seller_state,

    g.latitude,
    g.longitude,

    CASE
        WHEN g.geolocation_zip_code_prefix IS NULL THEN FALSE
        ELSE TRUE
    END AS geolocation_match_flag

FROM raw.sellers s

LEFT JOIN analytics.dim_geolocation g
    ON s.seller_zip_code_prefix =
       g.geolocation_zip_code_prefix;

SELECT
    COUNT(*) AS seller_rows,

    COUNT(DISTINCT seller_id)
        AS distinct_sellers,

    COUNT(*) FILTER (
        WHERE geolocation_match_flag = FALSE
    ) AS sellers_without_geolocation,

    COUNT(DISTINCT seller_zip_code_prefix) FILTER (
        WHERE geolocation_match_flag = FALSE
    ) AS unmatched_zip_prefixes

FROM analytics.dim_sellers;

-- ============================================================
-- 5. Order analytics
-- ============================================================
--
-- Purpose:
-- Create one analysis-ready row per order with:
-- - lifecycle timestamps
-- - approval and delivery durations
-- - delivery performance against estimate
-- - useful data-quality flags
--
-- Raw timestamps/status values are preserved.
-- ============================================================

CREATE OR REPLACE VIEW analytics.fact_orders AS

SELECT
    o.order_id,
    o.customer_id,
    o.order_status,

    o.order_purchase_timestamp,
    o.order_approved_at,
    o.order_delivered_carrier_date,
    o.order_delivered_customer_date,
    o.order_estimated_delivery_date,

    -- Calendar attributes for BI/time analysis
    o.order_purchase_timestamp::DATE AS purchase_date,

    EXTRACT(YEAR FROM o.order_purchase_timestamp)::INTEGER
        AS purchase_year,

    EXTRACT(MONTH FROM o.order_purchase_timestamp)::INTEGER
        AS purchase_month,

    TO_CHAR(o.order_purchase_timestamp, 'YYYY-MM')
        AS purchase_year_month,

    -- Time from purchase to approval
    ROUND(
        (
            EXTRACT(
                EPOCH FROM (
                    o.order_approved_at
                    - o.order_purchase_timestamp
                )
            ) / 3600.0
        )::NUMERIC,
        2
    ) AS approval_hours,

    -- Time from purchase to actual customer delivery
    ROUND(
        (
            EXTRACT(
                EPOCH FROM (
                    o.order_delivered_customer_date
                    - o.order_purchase_timestamp
                )
            ) / 86400.0
        )::NUMERIC,
        2
    ) AS delivery_days,

    -- Difference between actual and estimated delivery.
    -- Positive = delivered late
    -- Negative = delivered early
    ROUND(
        (
            EXTRACT(
                EPOCH FROM (
                    o.order_delivered_customer_date
                    - o.order_estimated_delivery_date
                )
            ) / 86400.0
        )::NUMERIC,
        2
    ) AS days_vs_estimate,

    CASE
        WHEN o.order_delivered_customer_date IS NULL
            THEN NULL

        WHEN o.order_delivered_customer_date
             > o.order_estimated_delivery_date
            THEN TRUE

        ELSE FALSE
    END AS late_delivery_flag,

    -- Known source inconsistency flags
    CASE
        WHEN o.order_status = 'delivered'
             AND o.order_delivered_customer_date IS NULL
            THEN TRUE
        ELSE FALSE
    END AS delivered_missing_date_flag,

    CASE
        WHEN o.order_status <> 'delivered'
             AND o.order_delivered_customer_date IS NOT NULL
            THEN TRUE
        ELSE FALSE
    END AS nondelivered_with_date_flag

FROM raw.orders o;

SELECT
    COUNT(*) AS order_rows,

    COUNT(DISTINCT order_id)
        AS distinct_orders,

    COUNT(*) FILTER (
        WHERE delivered_missing_date_flag = TRUE
    ) AS delivered_missing_date,

    COUNT(*) FILTER (
        WHERE nondelivered_with_date_flag = TRUE
    ) AS nondelivered_with_date,

    COUNT(*) FILTER (
        WHERE late_delivery_flag = TRUE
    ) AS late_deliveries,

    ROUND(AVG(delivery_days), 2)
        AS avg_delivery_days,

    ROUND(AVG(days_vs_estimate), 2)
        AS avg_days_vs_estimate

FROM analytics.fact_orders;

-- ============================================================
-- 6. Order-item sales fact
-- ============================================================
--
-- Grain:
-- One row per order item.
--
-- Purpose:
-- Provide the primary fact view for product, seller, category,
-- geography and sales analysis.
--
-- item_value = product price + freight charged for that item.
-- ============================================================

CREATE OR REPLACE VIEW analytics.fact_order_items AS

SELECT
    oi.order_id,
    oi.order_item_id,
    oi.product_id,
    oi.seller_id,

    oi.shipping_limit_date,

    oi.price,
    oi.freight_value,

    oi.price + oi.freight_value
        AS item_total_value,

    -- Order attributes
    o.customer_id,
    o.order_status,
    o.purchase_date,
    o.purchase_year,
    o.purchase_month,
    o.purchase_year_month,
    o.delivery_days,
    o.days_vs_estimate,
    o.late_delivery_flag,

    -- Product attributes
    p.category_name_original,
    p.category_name_english,

    -- Customer identity/location
    c.customer_unique_id,
    c.customer_city,
    c.customer_state,

    -- Seller location
    s.seller_city,
    s.seller_state

FROM raw.order_items oi

INNER JOIN analytics.fact_orders o
    ON oi.order_id = o.order_id

INNER JOIN analytics.dim_products p
    ON oi.product_id = p.product_id

INNER JOIN analytics.dim_customers c
    ON o.customer_id = c.customer_id

INNER JOIN analytics.dim_sellers s
    ON oi.seller_id = s.seller_id;

SELECT
    COUNT(*) AS item_rows,

    COUNT(DISTINCT order_id)
        AS orders_with_items,

    COUNT(DISTINCT product_id)
        AS products_sold,

    COUNT(DISTINCT seller_id)
        AS active_sellers,

    ROUND(SUM(price), 2)
        AS gross_product_value,

    ROUND(SUM(freight_value), 2)
        AS total_freight_value,

    ROUND(SUM(item_total_value), 2)
        AS total_item_value,

    ROUND(AVG(price), 2)
        AS avg_item_price

FROM analytics.fact_order_items;

-- ============================================================
-- 7. Payment fact
-- ============================================================
--
-- Grain:
-- One row per payment record.
--
-- An order may contain multiple payment records because Olist
-- supports sequential/split payments.
--
-- Raw edge cases are preserved and explicitly flagged.
-- ============================================================

CREATE OR REPLACE VIEW analytics.fact_payments AS

SELECT
    p.order_id,
    p.payment_sequential,
    p.payment_type,
    p.payment_installments,
    p.payment_value,

    CASE
        WHEN p.payment_type = 'not_defined'
            THEN TRUE
        ELSE FALSE
    END AS undefined_payment_type_flag,

    CASE
        WHEN p.payment_installments = 0
            THEN TRUE
        ELSE FALSE
    END AS zero_installment_flag,

    CASE
        WHEN p.payment_value <= 0
            THEN TRUE
        ELSE FALSE
    END AS nonpositive_payment_flag,

    o.customer_id,
    o.order_status,
    o.purchase_date,
    o.purchase_year,
    o.purchase_month,
    o.purchase_year_month,

    c.customer_unique_id,
    c.customer_state

FROM raw.order_payments p

INNER JOIN analytics.fact_orders o
    ON p.order_id = o.order_id

INNER JOIN analytics.dim_customers c
    ON o.customer_id = c.customer_id;

SELECT
    COUNT(*) AS payment_rows,

    COUNT(DISTINCT order_id)
        AS orders_with_payments,

    ROUND(SUM(payment_value), 2)
        AS total_payment_value,

    ROUND(AVG(payment_value), 2)
        AS avg_payment_record_value,

    COUNT(*) FILTER (
        WHERE undefined_payment_type_flag = TRUE
    ) AS undefined_payment_rows,

    COUNT(*) FILTER (
        WHERE zero_installment_flag = TRUE
    ) AS zero_installment_rows,

    COUNT(*) FILTER (
        WHERE nonpositive_payment_flag = TRUE
    ) AS nonpositive_payment_rows

FROM analytics.fact_payments;

-- ============================================================
-- 8. Order-level financial reconciliation
-- ============================================================
--
-- Purpose:
-- Reconcile item-level order value with recorded payments.
--
-- IMPORTANT:
-- Items and payments are aggregated independently BEFORE joining
-- because both tables may contain multiple rows per order.
-- Directly joining the raw fact tables would create fan-out and
-- inflate financial totals.
-- ============================================================

CREATE OR REPLACE VIEW analytics.fact_order_financials AS

WITH item_totals AS (
    SELECT
        order_id,
        COUNT(*) AS item_count,
        SUM(price) AS product_value,
        SUM(freight_value) AS freight_value,
        SUM(item_total_value) AS item_total_value
    FROM analytics.fact_order_items
    GROUP BY order_id
),

payment_totals AS (
    SELECT
        order_id,
        COUNT(*) AS payment_record_count,
        SUM(payment_value) AS payment_value
    FROM analytics.fact_payments
    GROUP BY order_id
)

SELECT
    o.order_id,
    o.customer_id,
    o.order_status,
    o.purchase_date,

    COALESCE(i.item_count, 0) AS item_count,
    COALESCE(p.payment_record_count, 0) AS payment_record_count,

    i.product_value,
    i.freight_value,
    i.item_total_value,
    p.payment_value,

    CASE
        WHEN i.item_total_value IS NOT NULL
         AND p.payment_value IS NOT NULL
        THEN p.payment_value - i.item_total_value
        ELSE NULL
    END AS payment_item_difference,

    CASE
        WHEN i.item_total_value IS NOT NULL
         AND p.payment_value IS NOT NULL
         AND ABS(p.payment_value - i.item_total_value) <= 0.01
        THEN TRUE
        ELSE FALSE
    END AS values_match_flag

FROM analytics.fact_orders o

LEFT JOIN item_totals i
    ON o.order_id = i.order_id

LEFT JOIN payment_totals p
    ON o.order_id = p.order_id;

SELECT
    COUNT(*) AS order_rows,

    COUNT(*) FILTER (
        WHERE item_total_value IS NOT NULL
          AND payment_value IS NOT NULL
    ) AS comparable_orders,

    COUNT(*) FILTER (
        WHERE values_match_flag = TRUE
    ) AS matching_orders,

    COUNT(*) FILTER (
        WHERE item_total_value IS NOT NULL
          AND payment_value IS NOT NULL
          AND values_match_flag = FALSE
    ) AS nonmatching_orders,

    ROUND(SUM(item_total_value), 2)
        AS total_item_value,

    ROUND(SUM(payment_value), 2)
        AS total_payment_value,

    ROUND(
        SUM(payment_value) - SUM(item_total_value),
        2
    ) AS overall_difference,

    ROUND(
        AVG(payment_item_difference)
        FILTER (
            WHERE payment_item_difference IS NOT NULL
        ),
        2
    ) AS avg_difference

FROM analytics.fact_order_financials;

-- ============================================================
-- 9. Review / customer satisfaction fact
-- ============================================================
--
-- Grain:
-- One row per (review_id, order_id).
--
-- review_id alone is not unique in the source data, therefore
-- the verified composite key grain is preserved.
--
-- Review text is optional and heavily missing in the source.
-- ============================================================

CREATE OR REPLACE VIEW analytics.fact_reviews AS

SELECT
    r.review_id,
    r.order_id,
    r.review_score,
    r.review_comment_title,
    r.review_comment_message,
    r.review_creation_date,
    r.review_answer_timestamp,

    CASE
        WHEN r.review_comment_title IS NOT NULL
            THEN TRUE
        ELSE FALSE
    END AS has_review_title,

    CASE
        WHEN r.review_comment_message IS NOT NULL
            THEN TRUE
        ELSE FALSE
    END AS has_review_comment,

    o.customer_id,
    o.order_status,
    o.purchase_date,
    o.purchase_year,
    o.purchase_month,
    o.purchase_year_month,
    o.delivery_days,
    o.days_vs_estimate,
    o.late_delivery_flag,

    c.customer_unique_id,
    c.customer_state

FROM raw.order_reviews r

INNER JOIN analytics.fact_orders o
    ON r.order_id = o.order_id

INNER JOIN analytics.dim_customers c
    ON o.customer_id = c.customer_id;

SELECT
    COUNT(*) AS review_rows,

    COUNT(DISTINCT order_id)
        AS orders_with_reviews,

    COUNT(DISTINCT review_id)
        AS distinct_review_ids,

    ROUND(AVG(review_score), 2)
        AS avg_review_score,

    COUNT(*) FILTER (
        WHERE has_review_title = TRUE
    ) AS reviews_with_title,

    COUNT(*) FILTER (
        WHERE has_review_comment = TRUE
    ) AS reviews_with_comment,

    COUNT(*) FILTER (
        WHERE review_score = 1
    ) AS one_star_reviews,

    COUNT(*) FILTER (
        WHERE review_score = 5
    ) AS five_star_reviews

FROM analytics.fact_reviews;

-- ============================================================
-- Diagnostic: Financial reconciliation discrepancies
-- ============================================================
--
-- 303 comparable orders have payment totals that differ from
-- item price + freight by more than R$0.01.
--
-- This diagnostic surfaces the largest discrepancies.
-- The source data does not provide enough accounting detail
-- to determine their cause.
-- ============================================================

SELECT
    order_id,
    order_status,
    item_count,
    payment_record_count,
    item_total_value,
    payment_value,
    ROUND(payment_item_difference, 2) AS difference
FROM analytics.fact_order_financials
WHERE item_total_value IS NOT NULL
  AND payment_value IS NOT NULL
  AND values_match_flag = FALSE
ORDER BY ABS(payment_item_difference) DESC
LIMIT 20;