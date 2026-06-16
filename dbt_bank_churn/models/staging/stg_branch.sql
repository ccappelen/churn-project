-- Source data quality check: branch_dim arrived clean with no leading or trailing whitespace,
-- correct capitalisation, and no missing values. Transformations are 
-- defensive only (TRIM, UPPER/INITCAP) with no observed impact on data.

WITH source AS (

	SELECT *
	FROM {{ source('raw', 'branch_dim') }}

)

SELECT 
	
	INITCAP(TRIM(city)) as city,
	INITCAP(TRIM(branch_name)) as branch_name,
	INITCAP(TRIM(region)) as region,
	UPPER(TRIM(branch_id)) as branch_id 

FROM source