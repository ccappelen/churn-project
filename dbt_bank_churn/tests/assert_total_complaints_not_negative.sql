-- Singular test: total_complaints never negative

SELECT *
FROM {{ ref('int_customer_complaints') }}
WHERE total_complaints < 0