-- Source data quality check: 
-- No duplicates
-- N/A values should be NULL
-- "USD " prefic in current_balance should be stripped
-- Space-separated thousands 
-- open_date mixed formats
-- Defensive transformations (TRIM, UPPER, INITCAP)

WITH source AS (

	SELECT *
	FROM {{ source('raw', 'accounts_raw') }}

)

SELECT 

	UPPER(TRIM(currency)) AS currency,
	COALESCE(
    	SAFE.PARSE_DATE('%Y-%m-%d', open_date),
    	SAFE.PARSE_DATE('%Y/%m/%d', open_date),
    	SAFE.PARSE_DATE('%d-%b-%Y', open_date),
    	SAFE.PARSE_DATE('%m/%d/%Y', open_date),
    	SAFE.PARSE_DATE('%d/%m/%Y', open_date)
	) AS open_date, 
	UPPER(TRIM(customer_id)) AS customer_id,
	INITCAP(TRIM(account_type)) AS account_type,
	SAFE_CAST(
    	REGEXP_REPLACE(
        	REGEXP_REPLACE(
            	REGEXP_REPLACE(
                	NULLIF(TRIM(current_balance), 'N/A'),
            	'USD ', ''),    -- strip USD prefix
        	r',', ''),          -- strip comma thousands separator
    	r'\s', '') 				-- strip space thousands separator
	AS FLOAT64) AS current_balance,
	UPPER(TRIM(account_id)) AS account_id
	
FROM source