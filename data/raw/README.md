# Simulated Bank Customer Churn Dataset

A multi-table, intentionally messy dataset designed for practicing data
cleaning, relational data modeling (star schema), feature engineering from
panel data, and churn classification.

## Files

| File | Grain | Rows | Description |
|---|---|---|---|
| `customers_raw.csv` | 1 row per customer (with some duplicates) | ~5,060 | Demographics, account-level summary fields (income, tenure, products) |
| `accounts_raw.csv` | 1 row per account | ~9,400 | Account type, balance, open date, currency. Customers can have multiple accounts |
| `monthly_activity_raw.csv` | 1 row per account per month (12 months) | ~59,000 | **PANEL DATA** — balances, transactions, logins, overdraft flags per month |
| `transactions_sample.csv` | 1 row per transaction | ~25,000 | Individual transactions for a sample of ~1,200 customers, last 90 days |
| `complaints_log.csv` | 1 row per complaint | ~740 | Customer service interactions |
| `branch_dim.csv` | 1 row per branch | 20 | Branch reference/dimension table — 20 branches across 16 US cities, each city consistently mapped to one region (Northeast/Midwest/South/West) |
| `churn_labels.csv` | 1 row per customer | 5,000 | **Target variable** — churned (0/1) and churn date. Deliberately kept separate, as in real organizations where the "target" often lives in a different system (e.g. CRM) than the feature data |

## Known data quality issues (by design)

**customers_raw.csv**
- Inconsistent `gender` encodings: `M`, `Male`, `male`, `MALE`, `m`, etc.
- `signup_date` stored in 5 different date formats
- Missing values in `income_usd` (~8%), `education_level` (~5%), `marital_status` (~3%)
- Age outliers/data entry errors (e.g., -1, 0, 150, 199, 250)
- ~60 duplicate/near-duplicate customer rows (some with slightly different income due to re-extraction)
- Some `customer_id` values have leading/trailing whitespace and inconsistent casing

**accounts_raw.csv**
- `current_balance` is mixed-type: numeric, `"USD 234,953.96"`, `"234 953.96"` (space thousands separator), and `"N/A"`
- `open_date` inherits the messy formats from `customers_raw`
- Negative balances for Credit Card / Loan accounts (amounts owed) — needs business-logic handling

**monthly_activity_raw.csv**
- ~1.5% of rows randomly missing (simulated dropped data feed)
- ~30 duplicate rows (simulated pipeline re-runs)
- After a customer's churn month, balances/activity drop to zero — reflects real "ghost account" behavior

**churn_labels.csv**
- `churn_date` is `NaN` for non-churned customers (expected — not a data quality bug)

## Suggested Workflow

### 1. Data Cleaning
- Standardize `customer_id` (strip whitespace, uppercase)
- Deduplicate `customers_raw` (decide on a rule — keep latest? average income for near-duplicates?)
- Standardize `gender` to a single encoding
- Parse all date formats into a single `datetime` type
- Clean `current_balance` in `accounts_raw` (strip currency codes, handle space/comma separators, decide how to treat `"N/A"`)
- Handle age outliers (cap, remove, or impute)
- Handle missing income/education/marital status (imputation strategy + document assumptions)

### 2. Data Modeling (Star Schema)
A reasonable target model:

- **Fact table**: `fact_customer_monthly` — grain = customer-month, built from `monthly_activity_raw` (aggregated from account-level to customer-level if a customer has multiple accounts)
- **Dimension tables**:
  - `dim_customer` (from cleaned `customers_raw`)
  - `dim_account` (from cleaned `accounts_raw`)
  - `dim_branch` (`branch_dim.csv`)
  - `dim_date` (generated from the 12 months)
- **Target table**: `churn_labels` joins to `dim_customer` on `customer_id`

### 3. Feature Engineering (from panel data)
From `monthly_activity_raw`, construct features such as:
- `avg_balance_last_3m`, `avg_balance_last_6m`
- `balance_trend` (e.g., slope of balance over last 3-6 months, or % change)
- `total_transactions_last_3m`, `transaction_trend`
- `avg_logins_last_3m`
- `months_since_last_overdraft`
- `pct_months_active` (logins > 0)

Be careful about **time-window construction relative to churn date** to avoid
data leakage — features should only use information available *before* the
observation/cutoff point for each customer.

### 4. Joining everything together
Final modeling table = `dim_customer` (cleaned) + engineered features from
`monthly_activity_raw` + complaint counts/recency from `complaints_log` +
transaction-level aggregates from `transactions_sample` (for the subset of
customers where available — note this introduces a missing-data pattern to
handle) + `churn_labels` (target).

### 5. Modeling
- Baseline: Logistic Regression
- Tree-based: Random Forest / XGBoost / LightGBM
- Handle class imbalance (~18% churn rate)
- Evaluate with precision/recall/F1/ROC-AUC/PR-AUC (accuracy alone is misleading given imbalance)

## Reproducibility

Generated with `numpy` random seed `42`. Re-running `generate_data.py` will
produce the same dataset.
