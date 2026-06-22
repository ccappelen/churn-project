-- Singular test: pct_resolved should be between 0 and 1

SELECT *
FROM {{ ref('int_customer_complaints') }}
WHERE pct_resolved < 0 OR pct_resolved > 1