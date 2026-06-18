-- Source data quality check: 
-- No duplicates
-- Defensive transformations (UPPER, INITCAP, TRIM)

WITH source AS (

	SELECT *
	FROM {{ source('raw', 'transactions_sample')}}

)

SELECT
	UPPER(TRIM(customer_id)) AS customer_id,
	UPPER(TRIM(transaction_id)) AS transaction_id,
	UPPER(TRIM(account_id)) AS account_id,
	INITCAP(TRIM(category)) AS transaction_category,
	INITCAP(TRIM(transaction_type)) AS transaction_type,
	amount,
	transaction_date
FROM source


	
	
	