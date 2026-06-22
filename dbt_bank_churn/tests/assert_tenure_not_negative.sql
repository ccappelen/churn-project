-- Singular test: tenure should never be negative

SELECT *
FROM {{ ref('fact_churn') }}
WHERE tenure < 0