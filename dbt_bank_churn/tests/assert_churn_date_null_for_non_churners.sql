-- Singular test: churn_date should be NULL for all non-churned customers

SELECT *
FROM {{ ref('stg_churn_labels') }}
WHERE churned = 0 AND churn_date IS NOT NULL
