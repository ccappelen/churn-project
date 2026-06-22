


# Packages ----------------------------------------------------------------
pacman::p_load("bigrquery", 
               "tidyverse", 
               "tidymodels", 
               "xgboost", 
               "vip", # Variable importance plots
               "probably" # Threshold tuning
               )

set_theme(cappelenR::my_theme())

# Authentication ----------------------------------------------------------
bigrquery::bq_auth(path = Sys.getenv("GCP_KEY_PATH"))


# Load data from BigQuery -------------------------------------------------
project_id <- "churn-project-banking"

sql <- "
  SELECT *
  FROM `churn-project-banking.dbt_dev_marts.fact_churn`
"

churn_raw <- bq_project_query(project_id, sql) |>
  bq_table_download()



# Exploratory data analysis -----------------------------------------------

# 1. Class balance
churn_raw |>
  count(churned) |>
  mutate(pct = n / sum(n))

# 2. Missing values summary
churn_raw |>
  summarise(across(everything(), ~ sum(is.na(.)))) |>
  pivot_longer(everything(), names_to = "column", values_to = "n_missing") |>
  filter(n_missing > 0) |>
  mutate(pct_missing = n_missing / nrow(churn_raw)) |>
  arrange(desc(n_missing))

# 3. Numeric feature distributions by churn status
churn_raw |>
  select(churned, tenure, age, income_usd, avg_balance_last_3m,
         transactions_last_1m, logins_last_1m, total_complaints) |>
  pivot_longer(-churned, names_to = "feature", values_to = "value") |>
  ggplot(aes(x = value, fill = factor(churned))) +
  geom_histogram(alpha = 0.6, bins = 30, position = "identity") +
  facet_wrap(~ feature, scales = "free") +
  scale_fill_manual(values = c("0" = "steelblue", "1" = "tomato"),
                    labels = c("Retained", "Churned")) +
  labs(title = "Feature distributions by churn status",
       fill = "Status", x = NULL, y = "Count")



# Feature selection -------------------------------------------------------

churn_model <- churn_raw |>
  select(-customer_id, -first_name, -last_name,
         -churn_date, -cutoff_date, -signup_date,
         -country, -branch_name, -days_since_last_complaint,
         -branch_id, -debt_to_asset_ratio,
         -pct_change_balance_3m,
         -logins_last_3m,
         -transactions_last_3m,
         -pct_months_active_6m) |>
  mutate(churned = factor(churned, levels = c(1, 0),
                          labels = c("yes", "no")),
         balance_trend = avg_balance_last_3m - avg_balance_last_6m) |>
  select(-avg_balance_last_3m)



# Train/test split --------------------------------------------------------
set.seed(42)
churn_split <- initial_split(churn_model, prop = 0.8, strata = churned)
churn_train <- training(churn_split)
churn_test  <- testing(churn_split)



# Recipe ------------------------------------------------------------------
churn_recipe <- recipe(churned ~ ., data = churn_train) |>
  # impute numeric columns with median
  step_impute_median(all_numeric_predictors()) |>
  # impute categorical columns with mode
  step_impute_mode(all_nominal_predictors()) |>
  # dummy encode categorical variables
  step_dummy(all_nominal_predictors()) |>
  # remove zero variance predictors
  step_zv(all_predictors()) |>
  # normalize for logistic regression
  step_normalize(all_numeric_predictors())



# Model specifications ----------------------------------------------------

logistic_spec <- logistic_reg(penalty = tune(), mixture = 1) |>
  set_engine("glmnet") |>
  set_mode("classification")

xgb_spec <- boost_tree(
  trees = tune(),
  tree_depth = tune(),
  learn_rate = tune(),
  min_n = tune()
) |>
  set_engine("xgboost") |>
  set_mode("classification")



# Workflows ---------------------------------------------------------------

logistic_wf <- workflow() |>
  add_recipe(churn_recipe) |>
  add_model(logistic_spec)

xgb_wf <- workflow() |>
  add_recipe(churn_recipe) |>
  add_model(xgb_spec)


# Cross-validation --------------------------------------------------------

set.seed(42)
churn_folds <- vfold_cv(churn_train, v = 5, strata = churned)




# Tuning setup ------------------------------------------------------------

logistic_grid <- grid_regular(
  penalty(range = c(-4, 0)),
  levels = 20
)

xgb_grid <- grid_space_filling(
  trees(range = c(100, 500)),
  tree_depth(range = c(3, 8)),
  learn_rate(range = c(-3, -1)),
  min_n(range = c(5, 25)),
  size = 20
)



# Tuning logistic ---------------------------------------------------------

set.seed(42)
logistic_tune <- tune_grid(
  logistic_wf,
  resamples = churn_folds,
  grid = logistic_grid,
  metrics = metric_set(roc_auc, pr_auc, f_meas),
  control = control_grid(save_pred = TRUE)
)



# Tuning XGBoost ----------------------------------------------------------

set.seed(42)
xgb_tune <- tune_grid(
  xgb_wf,
  resamples = churn_folds,
  grid = xgb_grid,
  metrics = metric_set(roc_auc, pr_auc, f_meas),
  control = control_grid(save_pred = TRUE)
)



# Evaluate models
show_best(logistic_tune, metric = "roc_auc", n = 3)
show_best(xgb_tune, metric = "roc_auc", n = 3)


# Select best parameters -------------------------------------------------

# Best logistic parameters
best_logistic <- select_best(logistic_tune, metric = "roc_auc")

# Best XGBoost parameters
best_xgb <- select_best(xgb_tune, metric = "roc_auc")



# Final workflow ----------------------------------------------------------
final_logistic_wf <- logistic_wf |> finalize_workflow(best_logistic)
final_xgb_wf      <- xgb_wf |> finalize_workflow(best_xgb)



# Fit on full training set and evaluate test set --------------------------
set.seed(42)
logistic_last_fit <- last_fit(final_logistic_wf, churn_split,
                              metrics = metric_set(roc_auc, pr_auc, 
                                                   f_meas, accuracy,
                                                   precision, recall))
xgb_last_fit <- last_fit(final_xgb_wf, churn_split,
                         metrics = metric_set(roc_auc, pr_auc,
                                              f_meas, accuracy,
                                              precision, recall))



# Compared performance ----------------------------------------------------
collect_metrics(logistic_last_fit) |> mutate(model = "Logistic Regression") |>
  bind_rows(
    collect_metrics(xgb_last_fit) |> mutate(model = "XGBoost")
  ) |>
  select(model, .metric, .estimate) |>
  pivot_wider(names_from = model, values_from = .estimate) |>
  arrange(.metric)


# ROC curves --------------------------------------------------------------

logistic_roc <- logistic_last_fit |>
  collect_predictions() |>
  roc_curve(truth = churned, .pred_yes) |>
  mutate(model = "Logistic Regression")

xgb_roc <- xgb_last_fit |>
  collect_predictions() |>
  roc_curve(truth = churned, .pred_yes) |>
  mutate(model = "XGBoost")

bind_rows(logistic_roc, xgb_roc) |>
  ggplot(aes(x = 1 - specificity, y = sensitivity, color = model)) +
  geom_line(linewidth = 1) +
  geom_abline(linetype = "dashed", color = "gray") +
  scale_color_manual(values = c("Logistic Regression" = "steelblue", 
                                "XGBoost" = "tomato")) +
  labs(title = "ROC Curves — Test Set",
       x = "False Positive Rate (1 - Specificity)",
       y = "True Positive Rate (Sensitivity)",
       color = "Model") 



# Confusion matrices ------------------------------------------------------

logistic_last_fit |>
  collect_predictions() |>
  conf_mat(truth = churned, estimate = .pred_class) |>
  autoplot(type = "heatmap") +
  labs(title = "Confusion Matrix — Logistic Regression")

xgb_last_fit |>
  collect_predictions() |>
  conf_mat(truth = churned, estimate = .pred_class) |>
  autoplot(type = "heatmap") +
  labs(title = "Confusion Matrix — XGBoost")



# Feature importance ------------------------------------------------------

xgb_last_fit |>
  extract_fit_parsnip() |>
  vip(num_features = 15) +
  labs(title = "XGBoost Feature Importance")

# Logistic regression coefficients
logistic_last_fit |>
  extract_fit_parsnip() |>
  tidy() |>
  filter(term != "(Intercept)") |>
  arrange(desc(abs(estimate))) |>
  slice_head(n = 15) |>
  ggplot(aes(x = estimate, 
             y = reorder(term, abs(estimate)),
             fill = estimate > 0)) +
  geom_col() +
  scale_fill_manual(values = c("TRUE" = "tomato", "FALSE" = "steelblue"),
                    labels = c("TRUE" = "Increases churn risk",
                               "FALSE" = "Decreases churn risk")) +
  labs(title = "Logistic Regression — Top 15 Coefficients",
       x = "Coefficient", y = NULL, fill = NULL) 



# Threshold tuning --------------------------------------------------------

# Get predicted probabilities for both models on test set
xgb_preds <- xgb_last_fit |>
  collect_predictions()

logistic_preds <- logistic_last_fit |>
  collect_predictions()

# Plot precision-recall curve across thresholds for XGBoost
xgb_preds |>
  pr_curve(truth = churned, .pred_yes) |>
  ggplot(aes(x = recall, y = precision)) +
  geom_line(color = "tomato", linewidth = 1) +
  geom_point(aes(x = recall, y = precision), size = 0.5) +
  labs(title = "Precision-Recall Curve — XGBoost",
       x = "Recall", y = "Precision") 

# Find optimal threshold using F1 score across thresholds
threshold_df <- tibble(threshold = seq(0.1, 0.9, by = 0.01)) |>
  mutate(
    metrics = map(threshold, function(t) {
      xgb_preds |>
        mutate(.pred_class = factor(
          if_else(.pred_yes >= t, "yes", "no"),
          levels = c("yes", "no")
        )) |>
        metric_set(f_meas, precision, recall)(
          truth = churned,
          estimate = .pred_class
        )
    })
  ) |>
  unnest(metrics)

# Plot F1, precision, recall across thresholds
threshold_df |>
  ggplot(aes(x = threshold, y = .estimate, color = .metric)) +
  geom_line(linewidth = 1) +
  scale_color_manual(values = c(
    "f_meas" = "black",
    "precision" = "steelblue",
    "recall" = "tomato"
  )) +
  geom_vline(xintercept = 0.5, linetype = "dashed", color = "gray") +
  labs(title = "Precision, Recall and F1 by Threshold — XGBoost",
       x = "Classification Threshold", y = "Score", color = "Metric")
