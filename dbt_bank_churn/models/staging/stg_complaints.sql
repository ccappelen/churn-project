-- Source data quality check: 
-- No duplicates
-- Defensive transformations (TRIM, UPPER, INITCAP)

WITH source AS (

	SELECT *
	
	FROM {{ source('raw', 'complaints_log') }}

)

SELECT 
	UPPER(TRIM(customer_id)) AS customer_id,
	complaint_date,
	UPPER(TRIM(complaint_id)) AS complaint_id,
	satisfaction_score,
	INITCAP(TRIM(complaint_type)) AS complaint_type,
	INITCAP(TRIM(resolution_status)) AS resolution_status	
FROM source