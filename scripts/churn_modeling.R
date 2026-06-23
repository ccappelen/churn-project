


# Packages ----------------------------------------------------------------
pacman::p_load("bigrquery", 
               "tidyverse", 
               "tidymodels", 
               "xgboost", 
               "vip", # Variable importance plots
               "probably", # Threshold tuning
               "shapviz", # SHAP values
               "patchwork"
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
ggsave("../images/roc_curves.png",
       width = 8, height = 5, dpi = 150)


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
ggsave("../images/xgb_importance.png",
       width = 8, height = 6, dpi = 150)

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
ggsave("../images/logistic_coefficients.png",
       width = 8, height = 6, dpi = 150)



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
  mutate(.metric = recode(.metric, "f_meas" = "F1")) |> 
  ggplot(aes(x = threshold, y = .estimate, color = .metric)) +
  geom_line(linewidth = 1) +
  scale_color_manual(values = c(
    "F1" = "black",
    "precision" = "steelblue",
    "recall" = "tomato"
  )) +
  geom_vline(xintercept = 0.5, linetype = "dashed", color = "gray") +
  labs(title = "Precision, Recall and F1 by Threshold — XGBoost",
       x = "Classification Threshold", y = "Score", color = "Metric")

ggsave("../images/threshold_tuning.png",
       width = 8, height = 5, dpi = 150)


# Find optimal threshold (maximizes F1) -----------------------------------

optimal_threshold <- threshold_df |>
  filter(.metric == "f_meas") |>
  slice_max(.estimate, n = 1) |>
  slice(1) |> 
  pull(threshold)

cat("Optimal threshold:", optimal_threshold, "\n")


# Apply optimal threshold to XGBoost predictions --------------------------

xgb_tuned_preds <- xgb_preds |>
  mutate(.pred_class_tuned = factor(
    if_else(.pred_yes >= optimal_threshold, "yes", "no"),
    levels = c("yes", "no")
  ))


# Compare default versus tuned threshold metrics --------------------------

default_metrics <- xgb_preds |>
  metric_set(f_meas, precision, recall)(
    truth = churned,
    estimate = .pred_class
  ) |>
  mutate(threshold = "Default (0.50)")

tuned_metrics <- xgb_tuned_preds |>
  metric_set(f_meas, precision, recall)(
    truth = churned,
    estimate = .pred_class_tuned
  ) |>
  mutate(threshold = paste0("Tuned (", optimal_threshold, ")"))

bind_rows(default_metrics, tuned_metrics) |>
  select(threshold, .metric, .estimate) |>
  pivot_wider(names_from = threshold, values_from = .estimate)

# ── Confusion matrix with tuned threshold ─────────────────────────────────────
xgb_tuned_preds |>
  conf_mat(truth = churned, estimate = .pred_class_tuned) |>
  autoplot(type = "heatmap") +
  labs(title = paste0("Confusion Matrix — XGBoost (Threshold = ", optimal_threshold, ")"))



# Lift and gains analysis -------------------------------------------------

base_rate <- mean(xgb_preds$churned == "yes")

lift_gains <- xgb_preds |>
  arrange(desc(.pred_yes)) |>
  mutate(
    row_n          = row_number(),
    pct_population = row_n / n(),
    churner        = if_else(churned == "yes", 1, 0),
    cum_churners   = cumsum(churner),
    cum_gains      = cum_churners / sum(churner),
    cum_lift       = cum_gains / pct_population
  )


# Cumulative gains curve --------------------------------------------------

lift_gains |>
  ggplot(aes(x = pct_population, y = cum_gains)) +
  geom_line(color = "tomato", linewidth = 1) +
  geom_abline(linetype = "dashed", color = "gray") +
  scale_x_continuous(labels = scales::percent) +
  scale_y_continuous(labels = scales::percent) +
  labs(title = "Cumulative Gains Curve — XGBoost",
       x = "% of Customers Contacted (ranked by churn probability)",
       y = "% of Churners Captured") 
ggsave("../images/gains_curve.png",
       width = 8, height = 5, dpi = 150)


# Lift curve --------------------------------------------------------------

lift_gains |>
  ggplot(aes(x = pct_population, y = cum_lift)) +
  geom_line(color = "steelblue", linewidth = 1) +
  geom_hline(yintercept = 1, linetype = "dashed", color = "gray") +
  scale_x_continuous(labels = scales::percent) +
  labs(title = "Lift Curve — XGBoost",
       x = "% of Customers Contacted (ranked by churn probability)",
       y = "Lift vs Random") 


# Decile table ------------------------------------------------------------

decile_table <- xgb_preds |>
  arrange(desc(.pred_yes)) |>
  mutate(
    decile = ntile(desc(.pred_yes), 10),
    churner = if_else(churned == "yes", 1, 0)
  ) |>
  group_by(decile) |>
  summarise(
    n_customers   = n(),
    n_churners    = sum(churner),
    churn_rate    = mean(churner),
    cumulative_churners = NA_real_,
    .groups = "drop"
  ) |>
  mutate(
    cumulative_churners  = cumsum(n_churners),
    pct_churners_captured = cumulative_churners / sum(n_churners),
    lift = churn_rate / base_rate
  )

print(decile_table)


# SHAP values -------------------------------------------------------------

# Extract the fitted XGBoost model
xgb_fit <- xgb_last_fit |> extract_fit_parsnip()

xgb_fit_raw <- xgb_last_fit |> 
  extract_fit_parsnip() |>
  extract_fit_engine()  # gets the underlying xgboost object

# Extract and prep the training data through the recipe
# (SHAP needs the preprocessed feature matrix, not raw data)
xgb_prep <- final_xgb_wf |>
  extract_preprocessor() |>
  prep()

train_baked <- xgb_prep |>
  bake(new_data = churn_train) |>
  select(-churned)

# Convert to matrix for shapviz
train_matrix <- as.matrix(train_baked)

# Create shapviz object
shp <- shapviz(xgb_fit_raw, X_pred = train_matrix, X = train_baked)



# 1. Beeswarm plot (global feature importance) ----------------------------

sv_importance(shp, kind = "beeswarm", max_display = 15) +
  labs(title = "SHAP Values — Feature Impact on Churn Prediction",
       x = "SHAP Value (impact on model output)",
       caption = "Red = high feature value, Blue = low feature value")

ggsave("../images/shap_beeswarm.png", 
       width = 10, height = 7, 
       dpi = 150)


# 2. Waterfall plot (single customer explanation) -------------------------

# Find an interesting churner to explain - highest predicted probability
ranked_idx <- order(xgb_preds$.pred_yes, decreasing = TRUE)
# top_churner_idx <- ranked_idx[1]   # highest
top_churner_idx <- ranked_idx[2]   # second highest
# top_churner_idx <- ranked_idx[3]   # third highest


sv_waterfall(shp, row_id = top_churner_idx) +
  labs(title = "SHAP Waterfall — Top Predicted Churner") +
  cappelenR::my_theme() +
  theme(panel.grid.major.x = element_blank(),
        panel.grid.minor.x = element_blank(),
        axis.line.x = element_line())

ggsave("../images/shap_waterfall.png", 
       width = 10, height = 7,
       dpi = 150)



# 3. Dependence plot (balance_trend vs. SHAP value) -----------------------

sv_dependence(shp, v = "balance_trend", color_var = "logins_last_1m") +
  labs(title = "SHAP Dependence — Balance Trend",
       x = "Balance Trend (3m avg - 6m avg)",
       y = "SHAP Value")

ggsave("../images/shap_dependence.png", 
       width = 8, height = 5,
       dpi = 150)
