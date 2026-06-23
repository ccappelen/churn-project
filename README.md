# Bank Customer Churn Prediction

An end-to-end data science project simulating a real-world bank churn 
prediction pipeline — from raw data ingestion to machine learning modeling.

## Tech Stack

| Layer | Tools |
|---|---|
| Data simulation | Python (numpy, pandas) |
| Data ingestion | R (bigrquery) |
| Data warehouse | Google BigQuery |
| Data modeling | dbt (staging → intermediate → marts) |
| Machine learning | R (tidymodels, XGBoost, glmnet) |
| Version control | Git / GitHub |

## Project Structure
```
bank-churn-project/

├── data/raw/               # Simulated raw CSV files (7 tables)

│   ├── generate_data.py    # Synthetic data generation

├── dbt_bank_churn/         # dbt project

│   └── models/

│       ├── staging/        # Cleaned source tables (7 models)

│       ├── intermediate/   # Aggregated features (3 models)

│       └── marts/          # Final feature table (fact_churn)

└── scripts/

    ├── load_to_bigquery.R  # Raw data ingestion to BigQuery

    └── churn_modeling.R    # ML modeling pipeline
```


## Data Lineage

The dbt pipeline builds 11 models across 3 layers — from raw BigQuery 
sources through to the final `fact_churn` feature table.

![dbt Lineage Graph](images/lineage_graph.png)

> Full interactive documentation: [dbt docs](https://ccappelen.github.io/churn-project/)


## Dataset

A synthetically generated dataset of 5,000 bank customers across 7 
relational tables, designed to reflect real-world data quality issues 
(mixed date formats, inconsistent encodings, duplicates, missing values). 
The panel table (`monthly_activity_raw`) contains 12 months of per-customer 
activity data requiring feature engineering before modeling.

## Pipeline

**1. Data Generation** — `generate_data.py` simulates 7 raw tables with 
realistic messiness and known churn-predictive relationships.

**2. Ingestion** — `load_to_bigquery.R` loads raw CSVs into BigQuery as 
STRING columns, preserving messiness for dbt to handle.

**3. dbt Modeling** — 11 models across 3 layers clean, aggregate, and 
join all data into `fact_churn` — a single feature table with one row 
per customer. Key steps include deduplication, multi-format date parsing, 
panel data aggregation with leakage-safe cutoff dates, and 43 data quality 
tests.

**4. ML Modeling** — `churn_modeling.R` builds two models using tidymodels:
- **LASSO Logistic Regression** — interpretable baseline
- **XGBoost** — gradient boosted trees with hyperparameter tuning

## Results

| Metric | Logistic Regression | XGBoost (tuned) |
|---|---|---|
| ROC-AUC | 0.979 | 0.984 |
| F1 | 0.835 | 0.899 |
| Precision | 0.950 | 0.924 |
| Recall | 0.745 | 0.876 |

**Top predictive features:** balance trend (3m vs 6m average), monthly 
login activity, transaction volume, and months active in last 6 months — 
confirming that behavioral disengagement precedes churn.

**Lift:** targeting the top 20% of customers by predicted churn probability 
captures 95% of all churners — a 4-6x improvement over random targeting.

## Reproduction

1. Clone the repo and create a Python virtual environment:
```bash
   pip install -r requirements.txt
```
2. Generate raw data: `python data/raw/generate_data.py`
3. Set up a GCP project and create a service account key
4. Create `.Renviron` with `GCP_KEY_PATH=/path/to/key.json`
5. Load data to BigQuery: run `scripts/load_to_bigquery.R`
6. Configure `~/.dbt/profiles.yml` (see `profiles_template.yml`)
7. Build dbt pipeline: `cd dbt_bank_churn && dbt build`
8. Run modeling: `scripts/churn_modeling.R`