-- ============================================================
-- Olist E-Commerce SQL & Business Intelligence Analytics
-- Raw-layer validation
-- PostgreSQL 18
--
-- Purpose:
-- Verify that the imported PostgreSQL tables match the
-- audited source CSV row counts and key structural facts.
-- ============================================================


-- ------------------------------------------------------------
-- 1. Row counts
-- ------------------------------------------------------------

SELECT 'product_category_name_translation' AS table_name, COUNT(*) AS row_count
FROM raw.product_category_name_translation

UNION ALL

SELECT 'customers', COUNT(*)
FROM raw.customers

UNION ALL

SELECT 'products', COUNT(*)
FROM raw.products

UNION ALL

SELECT 'sellers', COUNT(*)
FROM raw.sellers

UNION ALL

SELECT 'orders', COUNT(*)
FROM raw.orders

UNION ALL

SELECT 'order_items', COUNT(*)
FROM raw.order_items

UNION ALL

SELECT 'order_payments', COUNT(*)
FROM raw.order_payments

UNION ALL

SELECT 'order_reviews', COUNT(*)
FROM raw.order_reviews

UNION ALL

SELECT 'geolocation', COUNT(*)
FROM raw.geolocation

ORDER BY table_name;


-- ------------------------------------------------------------
-- 2. Distinct key counts
-- ------------------------------------------------------------

SELECT
    COUNT(*) AS customer_rows,
    COUNT(DISTINCT customer_id) AS distinct_customer_ids,
    COUNT(DISTINCT customer_unique_id) AS distinct_unique_customers
FROM raw.customers;


SELECT
    COUNT(*) AS order_rows,
    COUNT(DISTINCT order_id) AS distinct_order_ids
FROM raw.orders;


SELECT
    COUNT(*) AS product_rows,
    COUNT(DISTINCT product_id) AS distinct_product_ids
FROM raw.products;


SELECT
    COUNT(*) AS seller_rows,
    COUNT(DISTINCT seller_id) AS distinct_seller_ids
FROM raw.sellers;


-- ------------------------------------------------------------
-- 3. Order status distribution
-- ------------------------------------------------------------

SELECT
    order_status,
    COUNT(*) AS order_count
FROM raw.orders
GROUP BY order_status
ORDER BY order_count DESC;


-- ------------------------------------------------------------
-- 4. Purchase date range
-- ------------------------------------------------------------

SELECT
    MIN(order_purchase_timestamp) AS first_purchase,
    MAX(order_purchase_timestamp) AS last_purchase
FROM raw.orders;


-- ------------------------------------------------------------
-- 5. Multi-row relationship checks
-- ------------------------------------------------------------

SELECT COUNT(*) AS orders_with_multiple_items
FROM (
    SELECT order_id
    FROM raw.order_items
    GROUP BY order_id
    HAVING COUNT(*) > 1
) x;


SELECT COUNT(*) AS orders_with_multiple_payment_records
FROM (
    SELECT order_id
    FROM raw.order_payments
    GROUP BY order_id
    HAVING COUNT(*) > 1
) x;


SELECT COUNT(*) AS orders_with_multiple_review_records
FROM (
    SELECT order_id
    FROM raw.order_reviews
    GROUP BY order_id
    HAVING COUNT(*) > 1
) x;


-- ------------------------------------------------------------
-- 6. Orders without related records
-- ------------------------------------------------------------

SELECT COUNT(*) AS orders_without_items
FROM raw.orders o
LEFT JOIN raw.order_items oi
    ON o.order_id = oi.order_id
WHERE oi.order_id IS NULL;


SELECT COUNT(*) AS orders_without_payments
FROM raw.orders o
LEFT JOIN raw.order_payments p
    ON o.order_id = p.order_id
WHERE p.order_id IS NULL;


SELECT COUNT(*) AS orders_without_reviews
FROM raw.orders o
LEFT JOIN raw.order_reviews r
    ON o.order_id = r.order_id
WHERE r.order_id IS NULL;


-- ------------------------------------------------------------
-- 7. Product category translation coverage
-- ------------------------------------------------------------

SELECT
    COUNT(*) AS unmatched_product_rows,
    COUNT(DISTINCT p.product_category_name) AS distinct_unmatched_categories
FROM raw.products p
LEFT JOIN raw.product_category_name_translation t
    ON p.product_category_name = t.product_category_name
WHERE p.product_category_name IS NOT NULL
  AND t.product_category_name IS NULL;


-- ------------------------------------------------------------
-- 8. Known raw-data anomalies
-- ------------------------------------------------------------

SELECT COUNT(*) AS delivered_without_delivery_date
FROM raw.orders
WHERE order_status = 'delivered'
  AND order_delivered_customer_date IS NULL;


SELECT COUNT(*) AS nondelivered_with_delivery_date
FROM raw.orders
WHERE order_status <> 'delivered'
  AND order_delivered_customer_date IS NOT NULL;


SELECT
    MIN(shipping_limit_date) AS min_shipping_limit_date,
    MAX(shipping_limit_date) AS max_shipping_limit_date
FROM raw.order_items;


SELECT COUNT(*) AS zero_weight_products
FROM raw.products
WHERE product_weight_g = 0;


SELECT COUNT(*) AS undefined_payment_type_rows
FROM raw.order_payments
WHERE payment_type = 'not_defined';


SELECT COUNT(*) AS zero_installment_rows
FROM raw.order_payments
WHERE payment_installments = 0;


SELECT COUNT(*) AS nonpositive_payment_rows
FROM raw.order_payments
WHERE payment_value <= 0;

SELECT 'customers_rows' AS check_name, COUNT(*)::TEXT AS actual_value
FROM raw.customers

UNION ALL
SELECT 'unique_shoppers', COUNT(DISTINCT customer_unique_id)::TEXT
FROM raw.customers

UNION ALL
SELECT 'orders_rows', COUNT(*)::TEXT
FROM raw.orders

UNION ALL
SELECT 'products_rows', COUNT(*)::TEXT
FROM raw.products

UNION ALL
SELECT 'sellers_rows', COUNT(*)::TEXT
FROM raw.sellers

UNION ALL
SELECT 'order_items_rows', COUNT(*)::TEXT
FROM raw.order_items

UNION ALL
SELECT 'payments_rows', COUNT(*)::TEXT
FROM raw.order_payments

UNION ALL
SELECT 'reviews_rows', COUNT(*)::TEXT
FROM raw.order_reviews

UNION ALL
SELECT 'geolocation_rows', COUNT(*)::TEXT
FROM raw.geolocation

UNION ALL
SELECT 'orders_multiple_items', COUNT(*)::TEXT
FROM (
    SELECT order_id
    FROM raw.order_items
    GROUP BY order_id
    HAVING COUNT(*) > 1
) x

UNION ALL
SELECT 'orders_multiple_payments', COUNT(*)::TEXT
FROM (
    SELECT order_id
    FROM raw.order_payments
    GROUP BY order_id
    HAVING COUNT(*) > 1
) x

UNION ALL
SELECT 'orders_multiple_reviews', COUNT(*)::TEXT
FROM (
    SELECT order_id
    FROM raw.order_reviews
    GROUP BY order_id
    HAVING COUNT(*) > 1
) x

UNION ALL
SELECT 'orders_without_items', COUNT(*)::TEXT
FROM raw.orders o
LEFT JOIN raw.order_items oi ON o.order_id = oi.order_id
WHERE oi.order_id IS NULL

UNION ALL
SELECT 'orders_without_payments', COUNT(*)::TEXT
FROM raw.orders o
LEFT JOIN raw.order_payments p ON o.order_id = p.order_id
WHERE p.order_id IS NULL

UNION ALL
SELECT 'orders_without_reviews', COUNT(*)::TEXT
FROM raw.orders o
LEFT JOIN raw.order_reviews r ON o.order_id = r.order_id
WHERE r.order_id IS NULL

UNION ALL
SELECT 'delivered_without_delivery_date', COUNT(*)::TEXT
FROM raw.orders
WHERE order_status = 'delivered'
AND order_delivered_customer_date IS NULL

UNION ALL
SELECT 'nondelivered_with_delivery_date', COUNT(*)::TEXT
FROM raw.orders
WHERE order_status <> 'delivered'
AND order_delivered_customer_date IS NOT NULL

UNION ALL
SELECT 'zero_weight_products', COUNT(*)::TEXT
FROM raw.products
WHERE product_weight_g = 0

UNION ALL
SELECT 'undefined_payment_type', COUNT(*)::TEXT
FROM raw.order_payments
WHERE payment_type = 'not_defined'

UNION ALL
SELECT 'zero_installments', COUNT(*)::TEXT
FROM raw.order_payments
WHERE payment_installments = 0

UNION ALL
SELECT 'nonpositive_payments', COUNT(*)::TEXT
FROM raw.order_payments
WHERE payment_value <= 0;