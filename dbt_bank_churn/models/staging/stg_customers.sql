-- Source data quality check: 
-- Duplicates in customer_id - keep row with highest tenure_months and highest income_usd
-- Rows with NULL income, NULL education, NULL marital status (leave as is)
-- Age outliers (not between 18 and 100)
-- Multiple gender labels
-- Mixed date formats

WITH source AS (

	SELECT *
	FROM {{ source('raw', 'customers_raw') }}

),

typed AS (

	SELECT 
		*
		REPLACE(
			SAFE_CAST(age AS INT64) as age,
			SAFE_CAST(income_usd AS FLOAT64) AS income_usd
		)		
	
	FROM source
),

no_duplicates AS (

	SELECT 
		*,
		ROW_NUMBER() OVER (
			PARTITION BY UPPER(TRIM(customer_id))
			ORDER BY tenure_months DESC, income_USD DESC 	
		) AS row_num
	
	FROM typed
)

SELECT 
	UPPER(TRIM(customer_id)) AS customer_id,
	UPPER(TRIM(branch_id)) AS branch_id, 
	num_products,
	is_active_member,
	CASE 
		WHEN LOWER(TRIM(gender)) IN ('m', 'male') THEN 'Male'
		WHEN LOWER(TRIM(gender)) IN ('f', 'female') THEN 'Female'
		WHEN LOWER(TRIM(gender)) IN ('o', 'other') THEN 'Other'
		ELSE NULL
	END AS gender,
	UPPER(TRIM(country)) AS country,
	COALESCE(
    	SAFE.PARSE_DATE('%Y-%m-%d', signup_date),
    	SAFE.PARSE_DATE('%Y/%m/%d', signup_date),
    	SAFE.PARSE_DATE('%d-%b-%Y', signup_date),
    	SAFE.PARSE_DATE('%m/%d/%Y', signup_date),
    	SAFE.PARSE_DATE('%d/%m/%Y', signup_date)
	) AS signup_date,  
	INITCAP(TRIM(marital_status)) AS marital_status,
	CASE
    	WHEN age BETWEEN 18 AND 100 THEN age
    	ELSE NULL
	END AS age, 
	last_name, 
	INITCAP(TRIM(education_level)) AS education_level,
	first_name, 
	tenure_months,
	has_credit_card, 
	income_usd
	
FROM no_duplicates
WHERE row_num = 1