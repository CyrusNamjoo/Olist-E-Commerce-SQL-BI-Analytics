-- ============================================================
-- Olist E-Commerce SQL & Business Intelligence Analytics
-- Raw-layer table definitions
-- PostgreSQL 18
--
-- Purpose:
-- Create source-faithful relational tables for the nine
-- original Olist CSV files.
--
-- No cleaning or analytical transformations are performed here.
-- ============================================================


-- ------------------------------------------------------------
-- 1. Customers
-- ------------------------------------------------------------

CREATE TABLE IF NOT EXISTS raw.customers (
    customer_id                  VARCHAR(32) PRIMARY KEY,
    customer_unique_id           VARCHAR(32) NOT NULL,
    customer_zip_code_prefix     INTEGER NOT NULL,
    customer_city                TEXT NOT NULL,
    customer_state               VARCHAR(2) NOT NULL
);


-- ------------------------------------------------------------
-- 2. Orders
-- ------------------------------------------------------------

CREATE TABLE IF NOT EXISTS raw.orders (
    order_id                         VARCHAR(32) PRIMARY KEY,
    customer_id                      VARCHAR(32) NOT NULL,
    order_status                     TEXT NOT NULL,
    order_purchase_timestamp         TIMESTAMP NOT NULL,
    order_approved_at                TIMESTAMP,
    order_delivered_carrier_date     TIMESTAMP,
    order_delivered_customer_date    TIMESTAMP,
    order_estimated_delivery_date    TIMESTAMP NOT NULL,

    CONSTRAINT fk_orders_customer
        FOREIGN KEY (customer_id)
        REFERENCES raw.customers(customer_id)
);


-- ------------------------------------------------------------
-- 3. Products
-- ------------------------------------------------------------

CREATE TABLE IF NOT EXISTS raw.products (
    product_id                      VARCHAR(32) PRIMARY KEY,
    product_category_name           TEXT,
    product_name_lenght             NUMERIC,
    product_description_lenght      NUMERIC,
    product_photos_qty              NUMERIC,
    product_weight_g                NUMERIC,
    product_length_cm               NUMERIC,
    product_height_cm               NUMERIC,
    product_width_cm                NUMERIC
);


-- ------------------------------------------------------------
-- 4. Sellers
-- ------------------------------------------------------------

CREATE TABLE IF NOT EXISTS raw.sellers (
    seller_id                   VARCHAR(32) PRIMARY KEY,
    seller_zip_code_prefix      INTEGER NOT NULL,
    seller_city                 TEXT NOT NULL,
    seller_state                VARCHAR(2) NOT NULL
);


-- ------------------------------------------------------------
-- 5. Order Items
-- ------------------------------------------------------------

CREATE TABLE IF NOT EXISTS raw.order_items (
    order_id                VARCHAR(32) NOT NULL,
    order_item_id           INTEGER NOT NULL,
    product_id              VARCHAR(32) NOT NULL,
    seller_id               VARCHAR(32) NOT NULL,
    shipping_limit_date     TIMESTAMP NOT NULL,
    price                   NUMERIC(12,2) NOT NULL,
    freight_value           NUMERIC(12,2) NOT NULL,

    CONSTRAINT pk_order_items
        PRIMARY KEY (order_id, order_item_id),

    CONSTRAINT fk_order_items_order
        FOREIGN KEY (order_id)
        REFERENCES raw.orders(order_id),

    CONSTRAINT fk_order_items_product
        FOREIGN KEY (product_id)
        REFERENCES raw.products(product_id),

    CONSTRAINT fk_order_items_seller
        FOREIGN KEY (seller_id)
        REFERENCES raw.sellers(seller_id)
);


-- ------------------------------------------------------------
-- 6. Order Payments
-- ------------------------------------------------------------

CREATE TABLE IF NOT EXISTS raw.order_payments (
    order_id                VARCHAR(32) NOT NULL,
    payment_sequential      INTEGER NOT NULL,
    payment_type            TEXT NOT NULL,
    payment_installments    INTEGER NOT NULL,
    payment_value           NUMERIC(12,2) NOT NULL,

    CONSTRAINT pk_order_payments
        PRIMARY KEY (order_id, payment_sequential),

    CONSTRAINT fk_order_payments_order
        FOREIGN KEY (order_id)
        REFERENCES raw.orders(order_id)
);


-- ------------------------------------------------------------
-- 7. Order Reviews
-- ------------------------------------------------------------

CREATE TABLE IF NOT EXISTS raw.order_reviews (
    review_id                   VARCHAR(32) NOT NULL,
    order_id                    VARCHAR(32) NOT NULL,
    review_score                INTEGER NOT NULL,
    review_comment_title        TEXT,
    review_comment_message      TEXT,
    review_creation_date        TIMESTAMP NOT NULL,
    review_answer_timestamp     TIMESTAMP NOT NULL,

    CONSTRAINT pk_order_reviews
        PRIMARY KEY (review_id, order_id),

    CONSTRAINT fk_order_reviews_order
        FOREIGN KEY (order_id)
        REFERENCES raw.orders(order_id)
);


-- ------------------------------------------------------------
-- 8. Product Category Translation
-- ------------------------------------------------------------

CREATE TABLE IF NOT EXISTS raw.product_category_name_translation (
    product_category_name            TEXT PRIMARY KEY,
    product_category_name_english    TEXT NOT NULL
);


-- ------------------------------------------------------------
-- 9. Geolocation
--
-- Audit confirmed that this source has no valid primary key.
-- It is intentionally loaded without a PK or uniqueness
-- constraint in the raw layer.
-- ------------------------------------------------------------

CREATE TABLE IF NOT EXISTS raw.geolocation (
    geolocation_zip_code_prefix     INTEGER NOT NULL,
    geolocation_lat                 DOUBLE PRECISION NOT NULL,
    geolocation_lng                 DOUBLE PRECISION NOT NULL,
    geolocation_city                TEXT NOT NULL,
    geolocation_state               VARCHAR(2) NOT NULL
);