-- Source data quality check: 
-- No duplicates
-- Defensive transformations (UPPER, INITCAP, TRIM)

WITH source AS (

	SELECT *
	FROM {{ source('raw', 'transactions_sample')}}

)

SELECT
	UPPER(TRIM(customer_id)) as customer_id,
	UPPER(TRIM(transaction_id)) as transaction_id,
	UPPER(TRIM(account_id)) as account_id,
	INITCAP(TRIM(category)) as transaction_category,
	INITCAP(TRIM(transaction_type)) as transaction_type,
	amount,
	transaction_date
FROM source


	
	
	