-- Source data quality check: 
-- Duplicate account/month combinations - exact copies so keeping first row
-- Defensive transformations (UPPER, TRIM)
-- Cast month string to first day of month date

WITH source AS (

	SELECT *
	
	FROM {{ source('raw', 'monthly_activity_raw') }}

),

no_duplicates AS (

	SELECT *,
	ROW_NUMBER() OVER (
		PARTITION BY UPPER(TRIM(account_id)), month
		ORDER BY end_of_month_balance
	) AS row_num
	
	FROM source

)

SELECT 
	* EXCEPT(row_num)
	REPLACE(
		UPPER(TRIM(customer_id)) AS customer_id,
		UPPER(TRIM(account_id)) AS account_id,
		PARSE_DATE('%Y-%m-%d', CONCAT(month, '-01')) AS month
	)
FROM no_duplicates
WHERE row_num = 1



