-- Fact table
-- Grain: One customer per row
-- Adding intermediate models and recalculating tenure 
-- (based on cutoff_date) and calculating gearing


WITH base_with_cutoff AS (

	SELECT 
		customer.*,
		churn.churned,
		churn.churn_date,
		CASE WHEN churn.churned = 1
			THEN DATE_SUB(churn.churn_date, INTERVAL 1 MONTH)
			ELSE DATE '2024-12-31'
		END AS cutoff_date
	FROM {{ ref('stg_customers') }} customer
	LEFT JOIN {{ ref('stg_churn_labels') }} churn
		USING (customer_id)

),


base_joined AS (

SELECT 
	base.* EXCEPT (has_credit_card), -- has_credit_card was recalculated from accounts table
	acc.* EXCEPT (customer_id),
	comp.* EXCEPT (customer_id),
	act.* EXCEPT (customer_id),
	bra.* EXCEPT (branch_id)
FROM base_with_cutoff base
LEFT JOIN {{ ref('int_customer_accounts') }} acc USING (customer_id)
LEFT JOIN {{ ref('int_customer_complaints') }} comp USING (customer_id)
LEFT JOIN {{ ref('int_customer_activity') }} act USING (customer_id)
LEFT JOIN {{ ref('stg_branch') }} bra USING (branch_id)

)

SELECT 
	* EXCEPT (tenure_months),
	DATE_DIFF(cutoff_date, signup_date, MONTH) AS tenure,
	negative_balance / NULLIF(income_usd, 0) AS gearing
FROM base_joined

