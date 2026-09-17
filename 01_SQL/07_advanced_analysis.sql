-- ============================================================
-- Olist E-Commerce SQL & Business Intelligence Analytics
-- Advanced Analysis
-- PostgreSQL 18
--
-- Analysis:
-- Monthly Customer Cohort & Repeat-Purchase Retention
--
-- customer_unique_id is used as the persistent shopper identity.
-- ============================================================


-- ============================================================
-- 1. Customer monthly activity and cohort assignment
-- ============================================================

WITH customer_monthly_activity AS (
    SELECT DISTINCT
        c.customer_unique_id,

        DATE_TRUNC(
            'month',
            o.purchase_date
        )::DATE AS activity_month

    FROM analytics.fact_orders o

    INNER JOIN analytics.dim_customers c
        ON o.customer_id = c.customer_id

    -- Use the same continuous analytical period established
    -- during monthly trend analysis.
    WHERE o.purchase_date >= DATE '2017-01-01'
      AND o.purchase_date <  DATE '2018-09-01'
),

customer_cohorts AS (
    SELECT
        customer_unique_id,
        MIN(activity_month) AS cohort_month

    FROM customer_monthly_activity

    GROUP BY customer_unique_id
),

cohort_activity AS (
    SELECT
        a.customer_unique_id,
        c.cohort_month,
        a.activity_month,

        (
            (
                EXTRACT(YEAR FROM a.activity_month)
                - EXTRACT(YEAR FROM c.cohort_month)
            ) * 12
            +
            (
                EXTRACT(MONTH FROM a.activity_month)
                - EXTRACT(MONTH FROM c.cohort_month)
            )
        )::INTEGER AS months_since_first_purchase

    FROM customer_monthly_activity a

    INNER JOIN customer_cohorts c
        ON a.customer_unique_id = c.customer_unique_id
)

,
cohort_counts AS (
    SELECT
        cohort_month,
        months_since_first_purchase,

        COUNT(DISTINCT customer_unique_id)
            AS active_customers

    FROM cohort_activity

    GROUP BY
        cohort_month,
        months_since_first_purchase
),

cohort_sizes AS (
    SELECT
        cohort_month,
        active_customers AS cohort_size

    FROM cohort_counts

    WHERE months_since_first_purchase = 0
)

SELECT
    cc.cohort_month,
    cc.months_since_first_purchase,
    cs.cohort_size,
    cc.active_customers,

    ROUND(
        100.0 * cc.active_customers
        / cs.cohort_size,
        2
    ) AS retention_pct

FROM cohort_counts cc

INNER JOIN cohort_sizes cs
    ON cc.cohort_month = cs.cohort_month

ORDER BY
    cc.cohort_month,
    cc.months_since_first_purchase;

-- ============================================================
-- 2. Cohort retention matrix — Month 0 through Month 12
-- ============================================================
--
-- Purpose:
-- Present customer repeat-purchase retention in a matrix format.
--
-- Missing activity periods are displayed as 0%.
-- Later cohort months naturally have shorter observable horizons.
-- ============================================================

WITH customer_monthly_activity AS (
    SELECT DISTINCT
        c.customer_unique_id,
        DATE_TRUNC('month', o.purchase_date)::DATE AS activity_month

    FROM analytics.fact_orders o

    INNER JOIN analytics.dim_customers c
        ON o.customer_id = c.customer_id

    WHERE o.purchase_date >= DATE '2017-01-01'
      AND o.purchase_date <  DATE '2018-09-01'
),

customer_cohorts AS (
    SELECT
        customer_unique_id,
        MIN(activity_month) AS cohort_month

    FROM customer_monthly_activity

    GROUP BY customer_unique_id
),

cohort_activity AS (
    SELECT
        a.customer_unique_id,
        c.cohort_month,

        (
            (
                EXTRACT(YEAR FROM a.activity_month)
                - EXTRACT(YEAR FROM c.cohort_month)
            ) * 12
            +
            (
                EXTRACT(MONTH FROM a.activity_month)
                - EXTRACT(MONTH FROM c.cohort_month)
            )
        )::INTEGER AS months_since_first_purchase

    FROM customer_monthly_activity a

    INNER JOIN customer_cohorts c
        ON a.customer_unique_id = c.customer_unique_id
),

cohort_counts AS (
    SELECT
        cohort_month,
        months_since_first_purchase,
        COUNT(DISTINCT customer_unique_id) AS active_customers

    FROM cohort_activity

    GROUP BY
        cohort_month,
        months_since_first_purchase
),

cohort_sizes AS (
    SELECT
        cohort_month,
        active_customers AS cohort_size

    FROM cohort_counts

    WHERE months_since_first_purchase = 0
)

SELECT
    cs.cohort_month,
    cs.cohort_size,

    100.00 AS month_0,

    CASE
        WHEN cs.cohort_month + INTERVAL '1 month' > DATE '2018-08-01'
            THEN NULL
        ELSE ROUND(
            100.0 * COALESCE(
                MAX(cc.active_customers)
                    FILTER (WHERE cc.months_since_first_purchase = 1), 0
            ) / cs.cohort_size, 2
        )
    END AS month_1,

    CASE
        WHEN cs.cohort_month + INTERVAL '2 months' > DATE '2018-08-01'
            THEN NULL
        ELSE ROUND(
            100.0 * COALESCE(
                MAX(cc.active_customers)
                    FILTER (WHERE cc.months_since_first_purchase = 2), 0
            ) / cs.cohort_size, 2
        )
    END AS month_2,

    CASE
        WHEN cs.cohort_month + INTERVAL '3 months' > DATE '2018-08-01'
            THEN NULL
        ELSE ROUND(
            100.0 * COALESCE(
                MAX(cc.active_customers)
                    FILTER (WHERE cc.months_since_first_purchase = 3), 0
            ) / cs.cohort_size, 2
        )
    END AS month_3,

    CASE
        WHEN cs.cohort_month + INTERVAL '4 months' > DATE '2018-08-01'
            THEN NULL
        ELSE ROUND(
            100.0 * COALESCE(
                MAX(cc.active_customers)
                    FILTER (WHERE cc.months_since_first_purchase = 4), 0
            ) / cs.cohort_size, 2
        )
    END AS month_4,

    CASE
        WHEN cs.cohort_month + INTERVAL '5 months' > DATE '2018-08-01'
            THEN NULL
        ELSE ROUND(
            100.0 * COALESCE(
                MAX(cc.active_customers)
                    FILTER (WHERE cc.months_since_first_purchase = 5), 0
            ) / cs.cohort_size, 2
        )
    END AS month_5,

    CASE
        WHEN cs.cohort_month + INTERVAL '6 months' > DATE '2018-08-01'
            THEN NULL
        ELSE ROUND(
            100.0 * COALESCE(
                MAX(cc.active_customers)
                    FILTER (WHERE cc.months_since_first_purchase = 6), 0
            ) / cs.cohort_size, 2
        )
    END AS month_6,

    CASE
        WHEN cs.cohort_month + INTERVAL '7 months' > DATE '2018-08-01'
            THEN NULL
        ELSE ROUND(
            100.0 * COALESCE(
                MAX(cc.active_customers)
                    FILTER (WHERE cc.months_since_first_purchase = 7), 0
            ) / cs.cohort_size, 2
        )
    END AS month_7,

    CASE
        WHEN cs.cohort_month + INTERVAL '8 months' > DATE '2018-08-01'
            THEN NULL
        ELSE ROUND(
            100.0 * COALESCE(
                MAX(cc.active_customers)
                    FILTER (WHERE cc.months_since_first_purchase = 8), 0
            ) / cs.cohort_size, 2
        )
    END AS month_8,

    CASE
        WHEN cs.cohort_month + INTERVAL '9 months' > DATE '2018-08-01'
            THEN NULL
        ELSE ROUND(
            100.0 * COALESCE(
                MAX(cc.active_customers)
                    FILTER (WHERE cc.months_since_first_purchase = 9), 0
            ) / cs.cohort_size, 2
        )
    END AS month_9,

    CASE
        WHEN cs.cohort_month + INTERVAL '10 months' > DATE '2018-08-01'
            THEN NULL
        ELSE ROUND(
            100.0 * COALESCE(
                MAX(cc.active_customers)
                    FILTER (WHERE cc.months_since_first_purchase = 10), 0
            ) / cs.cohort_size, 2
        )
    END AS month_10,

    CASE
        WHEN cs.cohort_month + INTERVAL '11 months' > DATE '2018-08-01'
            THEN NULL
        ELSE ROUND(
            100.0 * COALESCE(
                MAX(cc.active_customers)
                    FILTER (WHERE cc.months_since_first_purchase = 11), 0
            ) / cs.cohort_size, 2
        )
    END AS month_11,

    CASE
        WHEN cs.cohort_month + INTERVAL '12 months' > DATE '2018-08-01'
            THEN NULL
        ELSE ROUND(
            100.0 * COALESCE(
                MAX(cc.active_customers)
                    FILTER (WHERE cc.months_since_first_purchase = 12), 0
            ) / cs.cohort_size, 2
        )
    END AS month_12

FROM cohort_sizes cs

LEFT JOIN cohort_counts cc
    ON cs.cohort_month = cc.cohort_month

GROUP BY
    cs.cohort_month,
    cs.cohort_size

ORDER BY cs.cohort_month;