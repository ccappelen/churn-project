-- Source data quality check: churn_labels arrived clean, DATE and INT features already typed,
-- churn_date is NULL if churned is 0. 
-- Defensive transformations (TRIM)

WITH source AS (

	SELECT * 
	FROM {{ source('raw', 'churn_labels') }}
	
)

SELECT 
	
	UPPER(TRIM(customer_id)) AS customer_id,
	churned,
	churn_date
	
FROM source