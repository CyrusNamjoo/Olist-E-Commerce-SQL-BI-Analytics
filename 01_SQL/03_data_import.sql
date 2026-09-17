-- ============================================================
-- Olist E-Commerce SQL & Business Intelligence Analytics
-- Raw CSV data import
-- Run using psql, NOT pgAdmin Query Tool
-- ============================================================

\set ON_ERROR_STOP on

\echo 'Starting Olist raw-data import...'

\copy raw.product_category_name_translation FROM 'data/product_category_name_translation.csv' WITH (FORMAT CSV, HEADER TRUE, ENCODING 'UTF8');

\copy raw.customers FROM 'data/olist_customers_dataset.csv' WITH (FORMAT CSV, HEADER TRUE, ENCODING 'UTF8');

\copy raw.products FROM 'data/olist_products_dataset.csv' WITH (FORMAT CSV, HEADER TRUE, ENCODING 'UTF8');

\copy raw.sellers FROM 'data/olist_sellers_dataset.csv' WITH (FORMAT CSV, HEADER TRUE, ENCODING 'UTF8');

\copy raw.orders FROM 'data/olist_orders_dataset.csv' WITH (FORMAT CSV, HEADER TRUE, ENCODING 'UTF8');

\copy raw.order_items FROM 'data/olist_order_items_dataset.csv' WITH (FORMAT CSV, HEADER TRUE, ENCODING 'UTF8');

\copy raw.order_payments FROM 'data/olist_order_payments_dataset.csv' WITH (FORMAT CSV, HEADER TRUE, ENCODING 'UTF8');

\copy raw.order_reviews FROM 'data/olist_order_reviews_dataset.csv' WITH (FORMAT CSV, HEADER TRUE, ENCODING 'UTF8');

\copy raw.geolocation FROM 'data/olist_geolocation_dataset.csv' WITH (FORMAT CSV, HEADER TRUE, ENCODING 'UTF8');

\echo 'Olist raw-data import completed.'