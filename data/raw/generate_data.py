"""
Simulated Bank Customer Churn Dataset Generator
================================================
Produces a multi-table relational dataset (star-schema friendly) with
realistic messiness for data cleaning, feature engineering, and ML practice.

Tables produced (raw, "as received from systems"):
1. customers_raw.csv         - customer demographics & account info (dim_customer source)
2. accounts_raw.csv           - one row per account, customer can have multiple (dim_account source)
3. monthly_activity_raw.csv   - PANEL DATA: one row per account per month (12 months)
                                 -> needs aggregation into features (avg balance last 3m, etc.)
4. transactions_sample.csv    - sample of individual transactions (last 90 days)
5. complaints_log.csv         - customer service complaints/tickets
6. branch_dim.csv              - branch reference table (dimension)
7. churn_labels.csv            - target variable (churned yes/no + churn date), separate file
                                 on purpose (common in real projects: target lives in a
                                 different system than features)

Messiness deliberately introduced:
- Missing values (MCAR/MAR patterns)
- Inconsistent categorical encodings (e.g., "M"/"Male"/"male")
- Duplicate customer rows
- Inconsistent date formats
- Outliers in balances/ages
- Mixed data types in numeric columns (stored as strings with currency symbols)
- Whitespace / casing issues in IDs and text fields
"""

import numpy as np
import pandas as pd
from datetime import datetime, timedelta
import random

SEED = 42
rng = np.random.default_rng(SEED)
random.seed(SEED)

N_CUSTOMERS = 5000
N_MONTHS = 12
SNAPSHOT_DATE = datetime(2024, 12, 31)

# ----------------------------------------------------------------------------
# 1. BRANCH DIMENSION
# ----------------------------------------------------------------------------
city_region_map = {
    "New York": "Northeast",
    "Boston": "Northeast",
    "Philadelphia": "Northeast",
    "Chicago": "Midwest",
    "Detroit": "Midwest",
    "Minneapolis": "Midwest",
    "Atlanta": "South",
    "Dallas": "South",
    "Houston": "South",
    "Miami": "South",
    "Charlotte": "South",
    "Los Angeles": "West",
    "San Francisco": "West",
    "Seattle": "West",
    "Denver": "West",
    "Phoenix": "West",
}

branch_cities = rng.choice(list(city_region_map.keys()), size=20)
branches = pd.DataFrame({
    "branch_id": [f"BR{str(i).zfill(3)}" for i in range(1, 21)],
    "branch_name": [f"Branch {i}" for i in range(1, 21)],
    "city": branch_cities,
    "region": [city_region_map[c] for c in branch_cities],
})
branches.to_csv("branch_dim.csv", index=False)

# ----------------------------------------------------------------------------
# 2. CUSTOMERS RAW
# ----------------------------------------------------------------------------
first_names = ["James", "Mary", "Robert", "Patricia", "Michael", "Jennifer", "William", "Linda",
                "David", "Elizabeth", "Richard", "Barbara", "Joseph", "Susan", "Thomas",
                "Jessica", "Christopher", "Sarah", "Daniel", "Karen", "Matthew", "Nancy",
                "Anthony", "Lisa", "Mark", "Betty", "Donald", "Margaret", "Steven", "Sandra"]
last_names = ["Smith", "Johnson", "Williams", "Brown", "Jones", "Garcia", "Miller", "Davis",
               "Rodriguez", "Martinez", "Hernandez", "Lopez", "Gonzalez", "Wilson", "Anderson",
               "Thomas", "Taylor", "Moore", "Jackson", "Martin", "Lee", "Perez", "Thompson",
               "White", "Harris", "Sanchez", "Clark", "Ramirez", "Lewis", "Robinson"]

customer_ids = [f"CUST{str(i).zfill(6)}" for i in range(1, N_CUSTOMERS + 1)]

# Latent "true" churn risk factors used to seed correlations later
age = rng.normal(45, 15, N_CUSTOMERS).clip(18, 92).round().astype(int)
tenure_months = rng.integers(1, 121, N_CUSTOMERS)  # up to 10 years

# Income (gross annual, USD)
income = rng.lognormal(mean=10.9, sigma=0.45, size=N_CUSTOMERS).round(-2)

genders_clean = rng.choice(["Male", "Female", "Other"], size=N_CUSTOMERS, p=[0.485, 0.485, 0.03])

# inconsistent encodings to simulate messy source systems
def messify_gender(g):
    r = random.random()
    if g == "Male":
        return random.choice(["M", "Male", "male", "MALE", "m"])
    elif g == "Female":
        return random.choice(["F", "Female", "female", "FEMALE", "f"])
    else:
        return random.choice(["Other", "other", "OTHER", "O"])

gender_messy = [messify_gender(g) for g in genders_clean]

countries = np.full(N_CUSTOMERS, "USA")

education = rng.choice(
    ["High School", "Bachelor", "Master", "PhD", "Vocational"],
    size=N_CUSTOMERS, p=[0.30, 0.35, 0.22, 0.03, 0.10]
)

marital = rng.choice(["Single", "Married", "Divorced", "Widowed"], size=N_CUSTOMERS, p=[0.35, 0.45, 0.15, 0.05])

has_credit_card = rng.choice([0, 1], size=N_CUSTOMERS, p=[0.3, 0.7])
is_active_member = rng.choice([0, 1], size=N_CUSTOMERS, p=[0.45, 0.55])
num_products = rng.choice([1, 2, 3, 4], size=N_CUSTOMERS, p=[0.4, 0.35, 0.2, 0.05])

branch_assignment = rng.choice(branches["branch_id"], size=N_CUSTOMERS)

# Signup date based on tenure
signup_dates = [SNAPSHOT_DATE - pd.DateOffset(months=int(t)) - timedelta(days=random.randint(0, 27))
                 for t in tenure_months]

# Different date formats to simulate messy source systems
def messy_date(d):
    fmt = random.choice(["%Y-%m-%d", "%d/%m/%Y", "%m/%d/%Y", "%d-%b-%Y", "%Y/%m/%d"])
    return d.strftime(fmt)

signup_date_messy = [messy_date(d) for d in signup_dates]

customers = pd.DataFrame({
    "customer_id": customer_ids,
    "first_name": [random.choice(first_names) for _ in range(N_CUSTOMERS)],
    "last_name": [random.choice(last_names) for _ in range(N_CUSTOMERS)],
    "age": age,
    "gender": gender_messy,
    "country": countries,
    "education_level": education,
    "marital_status": marital,
    "income_usd": income,
    "signup_date": signup_date_messy,
    "tenure_months": tenure_months,
    "has_credit_card": has_credit_card,
    "is_active_member": is_active_member,
    "num_products": num_products,
    "branch_id": branch_assignment,
})

# Introduce missingness (MAR-ish: more missing income for older customers, random for others)
missing_income_idx = rng.choice(N_CUSTOMERS, size=int(N_CUSTOMERS * 0.08), replace=False)
customers.loc[missing_income_idx, "income_usd"] = np.nan

missing_education_idx = rng.choice(N_CUSTOMERS, size=int(N_CUSTOMERS * 0.05), replace=False)
customers.loc[missing_education_idx, "education_level"] = np.nan

missing_marital_idx = rng.choice(N_CUSTOMERS, size=int(N_CUSTOMERS * 0.03), replace=False)
customers.loc[missing_marital_idx, "marital_status"] = np.nan

# A few age outliers / data entry errors
outlier_idx = rng.choice(N_CUSTOMERS, size=8, replace=False)
customers.loc[outlier_idx, "age"] = rng.choice([150, 199, -1, 0, 250], size=8)

# Inject some whitespace/casing issues into customer_id and names
ws_idx = rng.choice(N_CUSTOMERS, size=int(N_CUSTOMERS * 0.04), replace=False)
for i in ws_idx:
    customers.loc[i, "customer_id"] = f" {customers.loc[i, 'customer_id'].lower()} "

# Inject duplicate rows (exact and near-duplicates with slightly different income)
dup_idx = rng.choice(N_CUSTOMERS, size=60, replace=False)
dup_rows = customers.loc[dup_idx].copy()
# make some near-duplicates (slightly different income due to re-extraction at different time)
near_dup_mask = rng.choice([True, False], size=len(dup_rows), p=[0.5, 0.5])
dup_rows.loc[near_dup_mask, "income_usd"] = dup_rows.loc[near_dup_mask, "income_usd"] * rng.uniform(0.98, 1.02, near_dup_mask.sum())
customers = pd.concat([customers, dup_rows], ignore_index=True)

customers = customers.sample(frac=1, random_state=SEED).reset_index(drop=True)
customers.to_csv("customers_raw.csv", index=False)

# ----------------------------------------------------------------------------
# 3. ACCOUNTS RAW (one-to-many: customer -> accounts)
# ----------------------------------------------------------------------------
# Use the de-duplicated, clean ID list for relational integrity in downstream tables
unique_customers = customers.drop_duplicates(subset="customer_id").copy()
unique_customers["customer_id_clean"] = unique_customers["customer_id"].str.strip().str.upper()

account_rows = []
account_id_counter = 1
account_types_pool = ["Checking", "Savings", "Credit Card", "Loan"]

for _, row in unique_customers.iterrows():
    n_acc = row["num_products"]
    chosen_types = rng.choice(account_types_pool, size=n_acc, replace=False) if n_acc <= 4 else ["Checking"]
    for atype in chosen_types:
        # Base balance depends on account type and income
        base_income = row["income_usd"] if not pd.isna(row["income_usd"]) else 60000
        if atype == "Checking":
            bal = rng.normal(base_income * 0.05, base_income * 0.03)
        elif atype == "Savings":
            bal = rng.normal(base_income * 0.4, base_income * 0.25)
        elif atype == "Credit Card":
            bal = -abs(rng.normal(2200, 1800))  # owed amount, negative balance
        else:  # Loan
            bal = -abs(rng.normal(28000, 21000))

        account_rows.append({
            "account_id": f"ACC{str(account_id_counter).zfill(7)}",
            "customer_id": row["customer_id_clean"],
            "account_type": atype,
            "open_date": row["signup_date"],  # keep messy format, will need parsing
            "current_balance": round(bal, 2),
            "currency": "USD",
        })
        account_id_counter += 1

accounts = pd.DataFrame(account_rows)

# Messify current_balance into strings with currency symbols / thousands separators for some rows
def messify_balance(val, currency):
    r = random.random()
    if r < 0.15:
        return f"{currency} {val:,.2f}"
    elif r < 0.25:
        return f"{val:,.2f}".replace(",", " ")  # space as thousands sep
    elif r < 0.30:
        return "N/A"
    else:
        return val

accounts["current_balance"] = [messify_balance(v, c) for v, c in zip(accounts["current_balance"], accounts["currency"])]
accounts.to_csv("accounts_raw.csv", index=False)

# ----------------------------------------------------------------------------
# 4. MONTHLY ACTIVITY PANEL (the panel data table requiring aggregation)
# ----------------------------------------------------------------------------
months = pd.date_range(end=SNAPSHOT_DATE, periods=N_MONTHS, freq="ME")

# We'll generate churn behavior here too, then build churn_labels from it
panel_rows = []
churn_info = {}

checking_accounts = accounts[accounts["account_type"] == "Checking"][["account_id", "customer_id"]]
# fall back: if a customer has no checking account, use their first account
cust_to_acc = {}
for cust_id in unique_customers["customer_id_clean"]:
    acc_for_cust = accounts[accounts["customer_id"] == cust_id]
    if len(acc_for_cust) == 0:
        continue
    checking = acc_for_cust[acc_for_cust["account_type"] == "Checking"]
    chosen_acc = checking.iloc[0]["account_id"] if len(checking) > 0 else acc_for_cust.iloc[0]["account_id"]
    cust_to_acc[cust_id] = chosen_acc

# Determine latent churn probability per customer based on realistic drivers
cust_lookup = unique_customers.set_index("customer_id_clean")

for cust_id, acc_id in cust_to_acc.items():
    crow = cust_lookup.loc[cust_id]
    base_balance = rng.normal(6000, 3500)
    base_balance = max(base_balance, 500)

    # churn risk score (latent, used to decide churn month)
    risk = 0.0
    risk += 0.35 if crow["is_active_member"] == 0 else -0.1
    risk += 0.25 if crow["num_products"] == 1 else (0.0 if crow["num_products"] == 2 else -0.15)
    risk += 0.15 if crow["tenure_months"] < 12 else -0.05
    risk += 0.10 if crow["age"] < 30 else 0.0
    risk += rng.normal(0, 0.15)
    risk = np.clip(risk, -0.3, 0.9)

    will_churn = rng.random() < (0.08 + 0.45 * max(risk, 0))  # baseline ~8% churn, up to high risk
    churn_month_idx = rng.integers(1, N_MONTHS) if will_churn else None

    balance = base_balance
    declining = will_churn and churn_month_idx is not None

    for m_idx, month_end in enumerate(months):
        # Simulate balance trajectory
        if declining and m_idx >= max(churn_month_idx - 3, 0):
            # gradual drawdown before churn
            balance *= rng.uniform(0.75, 0.92)
        else:
            balance *= rng.uniform(0.97, 1.05)
        balance = max(balance, 0)

        # transactions count - drops before churn
        base_tx = rng.poisson(12)
        if declining and m_idx >= max(churn_month_idx - 2, 0):
            base_tx = rng.poisson(4)

        # logins
        base_logins = rng.poisson(8)
        if declining and m_idx >= max(churn_month_idx - 2, 0):
            base_logins = rng.poisson(2)

        # customer becomes inactive after churn month
        is_churn_month_or_after = will_churn and (m_idx >= churn_month_idx)

        panel_rows.append({
            "account_id": acc_id,
            "customer_id": cust_id,
            "month": month_end.strftime("%Y-%m"),
            "end_of_month_balance": round(balance, 2) if not is_churn_month_or_after else 0.0,
            "num_transactions": int(base_tx) if not is_churn_month_or_after else 0,
            "num_logins": int(base_logins) if not is_churn_month_or_after else 0,
            "overdraft_flag": int(rng.random() < 0.05 and not is_churn_month_or_after),
        })

    churn_info[cust_id] = {
        "will_churn": int(will_churn),
        "churn_month_idx": churn_month_idx,
    }

panel = pd.DataFrame(panel_rows)

# Introduce some missing months (simulate missing data feeds) - randomly drop ~1.5% of rows
drop_idx = rng.choice(panel.index, size=int(len(panel) * 0.015), replace=False)
panel = panel.drop(index=drop_idx).reset_index(drop=True)

# Introduce a few duplicate rows (system re-runs)
dup_panel_idx = rng.choice(panel.index, size=30, replace=False)
panel = pd.concat([panel, panel.loc[dup_panel_idx]], ignore_index=True)

panel.to_csv("monthly_activity_raw.csv", index=False)

# ----------------------------------------------------------------------------
# 5. CHURN LABELS (separate file, as is common: target from a different system)
# ----------------------------------------------------------------------------
churn_label_rows = []
for cust_id, info in churn_info.items():
    if info["will_churn"]:
        churn_month = months[info["churn_month_idx"]]
        churn_date = churn_month + pd.DateOffset(days=int(rng.integers(0, 27)))
        churn_label_rows.append({
            "customer_id": cust_id,
            "churned": 1,
            "churn_date": churn_date.strftime("%Y-%m-%d"),
        })
    else:
        churn_label_rows.append({
            "customer_id": cust_id,
            "churned": 0,
            "churn_date": np.nan,
        })

churn_labels = pd.DataFrame(churn_label_rows)
churn_labels.to_csv("churn_labels.csv", index=False)

# ----------------------------------------------------------------------------
# 6. TRANSACTIONS SAMPLE (last 90 days, individual transaction-level detail)
# ----------------------------------------------------------------------------
tx_types = ["POS Purchase", "ATM Withdrawal", "Online Transfer", "Direct Debit",
             "Salary Deposit", "International Transfer", "Mobile Payment"]
tx_categories = ["Groceries", "Utilities", "Entertainment", "Travel", "Salary",
                  "Rent", "Shopping", "Dining", "Healthcare", "Other"]

# Sample a subset of active customers for transaction-level detail
sample_customers = rng.choice(list(cust_to_acc.keys()), size=1200, replace=False)

tx_rows = []
tx_id = 1
for cust_id in sample_customers:
    acc_id = cust_to_acc[cust_id]
    n_tx = rng.integers(3, 40)
    for _ in range(n_tx):
        days_ago = rng.integers(0, 90)
        tx_date = SNAPSHOT_DATE - timedelta(days=int(days_ago))
        ttype = rng.choice(tx_types)
        if ttype == "Salary Deposit":
            amount = round(rng.normal(4500, 1000), 2)
        elif ttype == "International Transfer":
            amount = -round(abs(rng.normal(400, 300)), 2)
        else:
            amount = -round(abs(rng.normal(60, 80)), 2)

        tx_rows.append({
            "transaction_id": f"TXN{str(tx_id).zfill(8)}",
            "account_id": acc_id,
            "customer_id": cust_id,
            "transaction_date": tx_date.strftime("%Y-%m-%d %H:%M:%S"),
            "transaction_type": ttype,
            "category": rng.choice(tx_categories) if ttype != "Salary Deposit" else "Salary",
            "amount": amount,
        })
        tx_id += 1

transactions = pd.DataFrame(tx_rows)
transactions.to_csv("transactions_sample.csv", index=False)

# ----------------------------------------------------------------------------
# 7. COMPLAINTS LOG
# ----------------------------------------------------------------------------
complaint_types = ["Fee Dispute", "App/Online Banking Issue", "Card Issue",
                     "Service Quality", "Loan/Mortgage Query", "Fraud Report", "Other"]
resolution_status = ["Resolved", "Pending", "Escalated", "Closed - No Action"]

# Customers with higher churn risk more likely to have complaints
complaint_rows = []
complaint_id = 1
for cust_id, info in churn_info.items():
    p_complaint = 0.35 if info["will_churn"] else 0.12
    n_complaints = rng.poisson(0.7) if rng.random() < p_complaint else (1 if rng.random() < 0.05 else 0)
    for _ in range(n_complaints):
        days_ago = rng.integers(0, 365)
        c_date = SNAPSHOT_DATE - timedelta(days=int(days_ago))
        complaint_rows.append({
            "complaint_id": f"CMP{str(complaint_id).zfill(6)}",
            "customer_id": cust_id,
            "complaint_date": c_date.strftime("%Y-%m-%d"),
            "complaint_type": rng.choice(complaint_types),
            "resolution_status": rng.choice(resolution_status),
            "satisfaction_score": rng.choice([1, 2, 3, 4, 5, np.nan], p=[0.15, 0.15, 0.2, 0.2, 0.2, 0.1]),
        })
        complaint_id += 1

complaints = pd.DataFrame(complaint_rows)
complaints.to_csv("complaints_log.csv", index=False)

# ----------------------------------------------------------------------------
# Summary
# ----------------------------------------------------------------------------
print("Files generated:")
for f in ["customers_raw.csv", "accounts_raw.csv", "monthly_activity_raw.csv",
          "transactions_sample.csv", "complaints_log.csv", "branch_dim.csv", "churn_labels.csv"]:
    df = pd.read_csv(f)
    print(f"  {f:28s} shape={df.shape}")

print(f"\nChurn rate: {churn_labels['churned'].mean():.2%}")
