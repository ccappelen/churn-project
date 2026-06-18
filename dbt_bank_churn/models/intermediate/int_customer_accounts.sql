-- Number of accounts
-- Number of unique account types
-- Has a loan
-- Has credit card (already in customers but check quality)
-- Total balance
-- Indicator for any account with negative balance (i.e. any debts)
-- Total positive balance
-- Total debt
-- Debt-to-asset ratio (total debt/total positive balance)
-- (Gearing will be calculated in fact table, using income data)

-- 
-- NB: current_balance assumption for churned customers

WITH ac AS (

	SELECT *
	FROM {{ ref('stg_accounts') }}

)

SELECT 
	customer_id, 
	COUNT(*) AS number_accounts,
	COUNT(DISTINCT account_type) AS distinct_accounts,
	MAX(IF(account_type = 'Loan', 1, 0)) AS has_loan,
	MAX(IF(account_type = 'Credit Card', 1, 0)) AS has_credit_card,
	SUM(current_balance) AS total_balance,
	MAX(IF(current_balance < 0, 1, 0)) AS has_debt,
	SUM(IF(account_type IN ('Loan', 'Credit Card'), ABS(current_balance), 0)) AS negative_balance,
	SUM(IF(account_type IN ('Checking', 'Savings'), ABS(current_balance), 0)) AS positive_balance,
	SUM(IF(account_type IN ('Loan', 'Credit Card'), ABS(current_balance), 0)) / 
		NULLIF(SUM(IF(account_type IN ('Checking', 'Savings'), ABS(current_balance), 0)), 0)
		AS debt_to_asset_ratio
FROM ac
GROUP BY customer_id