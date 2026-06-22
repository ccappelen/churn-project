-- Singular test: pct_months_active_6m should be between 0 and 1

SELECT *
FROM {{ ref('int_customer_activity') }}
WHERE pct_months_active_6m < 0 OR pct_months_active_6m > 1