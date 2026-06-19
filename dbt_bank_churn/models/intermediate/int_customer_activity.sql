-- Number of transactions last month before cutoff/churn
-- Number of transactions last 3 months before cutoff/churn
-- Number of overdraft flags within last three months before cutoff/churn
-- Number of logins in last month before cutoff/churn
-- Pct. Change in number of transactions over last three months before cutoff/churn
-- Pct. Change in number of logins over last three months before cutoff
-- Average balance last 3 months
-- Average balance last 6 months
-- Percent change in balance over last 3 months before cutoff/churn 
-- Number of months active (at least one login) over last 6 months
-- Percent months active (at least one login) over last 6 months

-- Cutoff date for churned customers are set to one month before churn_date
-- Customers with early churn (first couple of months) will have NULL values for look-back features (e.g. last 3 months). 
-- However, since activity is only recorded for one year (while they may have been customers for much longer), early churn 
-- (within that year) does not necessarily indicate NEW customers that churned quickly. Therefore we keep the NULL values
-- and leave the appropriate handling of NULL values to the modeling stage. 


-- 1. Add churn date and remove rows after cutoff_date

WITH activity_churn_cutoff AS (

	SELECT 
		act.*,
		churn.churn_date,
		CASE WHEN churn.churn_date IS NOT NULL 
			THEN DATE_SUB(churn.churn_date, INTERVAL 1 MONTH)
		ELSE DATE '2024-12-31'
		END AS cutoff_date 
	FROM {{ ref('stg_monthly_activity') }}  act
	LEFT JOIN {{ ref('stg_churn_labels') }} churn
		ON act.customer_id = churn.customer_id

),

activity_churn AS (

	SELECT * 
	FROM activity_churn_cutoff
	WHERE month <= cutoff_date

),

-- 2. Aggregate to one row per customer (change features calculated in next CTE)
activity_agg AS (

	SELECT	
		customer_id,
		SUM(IF(DATE_DIFF(cutoff_date, month, MONTH) = 0, num_transactions, 0)) AS transactions_last_1m,
		SUM(IF(DATE_DIFF(cutoff_date, month, MONTH) = 2, num_transactions, 0)) AS transactions_3m,
		SUM(IF(DATE_DIFF(cutoff_date, month, MONTH) BETWEEN 0 AND 2, num_transactions, 0)) AS transactions_last_3m,
		SUM(IF(DATE_DIFF(cutoff_date, month, MONTH) BETWEEN 0 AND 2, overdraft_flag, 0)) AS overdraft_last_3m,
		SUM(IF(DATE_DIFF(cutoff_date, month, MONTH) = 0, num_logins, 0)) AS logins_last_1m,
		SUM(IF(DATE_DIFF(cutoff_date, month, MONTH) = 2, num_logins, 0)) AS logins_3m,
		SUM(IF(DATE_DIFF(cutoff_date, month, MONTH) BETWEEN 0 AND 2, num_logins, 0)) AS logins_last_3m,
		AVG(IF(DATE_DIFF(cutoff_date, month, MONTH) BETWEEN 0 and 2, end_of_month_balance, NULL)) AS avg_balance_last_3m,
		AVG(IF(DATE_DIFF(cutoff_date, month, MONTH) BETWEEN 0 and 5, end_of_month_balance, NULL)) AS avg_balance_last_6m,
		SUM(IF(DATE_DIFF(cutoff_date, month, MONTH) = 0, end_of_month_balance, 0)) AS balance_1m,
		SUM(IF(DATE_DIFF(cutoff_date, month, MONTH) = 2, end_of_month_balance, 0)) AS balance_3m,
		COUNTIF(DATE_DIFF(cutoff_date, month, MONTH) BETWEEN 0 AND 5 AND num_logins > 0) AS months_active_6m,
		COUNTIF(DATE_DIFF(cutoff_date, month, MONTH) BETWEEN 0 AND 5 AND num_logins > 0) / 6.0 AS pct_months_active_6m
		
	FROM activity_churn 
	GROUP BY customer_id

)

-- 3. Calculate derived feature (change over time)
SELECT
	customer_id,
	transactions_last_1m,
	transactions_last_3m,
	overdraft_last_3m,
	logins_last_1m,
	logins_last_3m,
	(transactions_last_1m - transactions_last_3m) / NULLIF(transactions_3m, 0) AS pct_change_transactions_3m,
	(logins_last_1m - logins_last_3m) / NULLIF(logins_3m, 0) AS pct_change_logins_3m,
	avg_balance_last_3m,
	avg_balance_last_6m,
	(balance_1m - balance_3m) / NULLIF(balance_3m, 0) AS pct_change_balance_3m,
	months_active_6m,
	pct_months_active_6m
FROM activity_agg
