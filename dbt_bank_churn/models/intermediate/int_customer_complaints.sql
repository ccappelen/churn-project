-- Number of complaints (0 if NULL, i.e. customers with no complaints)
-- Number of unresolved complaints (Escalated or Pending)
-- Average satisfaction score (median imputation for NULL)
-- Flag if customer has any complaints
-- Days since last complaint
-- Whether customer has fraud report complaint
-- Percent complaints resolved (relative to all complaints) - 0 for customers with no complaints (distinguished by complaints flag)

-- Left join stg_churn_labels and stg_complaints to get full set of customers
-- and churn_date to define feature_cutoff_date



-- 1. Add churn_date to stg_complaints and remove complaints after churn
WITH comp_churn AS (

	SELECT 
		comp.*,
		churn.churn_date
	FROM {{ ref('stg_complaints') }} comp
	LEFT JOIN {{ ref('stg_churn_labels') }} churn
		ON comp.customer_id = churn.customer_id
	WHERE comp.complaint_date < churn.churn_date OR churn.churn_date IS NULL
),

-- 2. Calculate median satisfcation score
median_satisfaction AS (

	SELECT 
		PERCENTILE_CONT(satisfaction_score, 0.5)
			OVER () AS median_satisfaction
	FROM {{ ref('stg_complaints') }}
	WHERE satisfaction_score IS NOT NULL
	LIMIT 1
),

-- 3. Add comp_churn to stg_churn_labels to include all customers
churn_comp AS (

	SELECT
		churn.customer_id,
		churn.churn_date,
		churn.churned,
		comp_churn.complaint_date, 
		comp_churn.complaint_id, 
		comp_churn.satisfaction_score, 
		comp_churn.complaint_type, 
		comp_churn.resolution_status
	FROM {{ ref('stg_churn_labels') }} churn
	LEFT JOIN comp_churn
		ON churn.customer_id = comp_churn.customer_id

),

-- 4. Add median satisfaction_score
churn_comp_median AS (

	SELECT *
	FROM churn_comp
	CROSS JOIN median_satisfaction

)

-- 5. Aggregate over customer id
SELECT 
	customer_id, 
	COUNT(complaint_id) AS total_complaints,
	COUNTIF(resolution_status IN ('Escalated', 'Pending', 'Closed - No Action')) AS total_unresolved,
	COALESCE(AVG(satisfaction_score), MAX(median_satisfaction)) AS avg_satisfaction,
	IF(COUNT(complaint_id) > 0, 1, 0) AS has_complaint,
	DATE_DIFF(
    	CASE WHEN MAX(churned) = 1 
        	THEN DATE_SUB(MAX(churn_date), INTERVAL 1 MONTH)
        ELSE DATE '2024-12-31'
    	END,
    	MAX(complaint_date),
    	DAY) AS days_since_last_complaint,
	MAX(IF(complaint_type = 'Fraud Report', 1, 0)) AS has_fraud_report,
	COUNTIF(resolution_status = 'Resolved') / COUNT(*) AS pct_resolved
FROM churn_comp_median
GROUP BY customer_id




