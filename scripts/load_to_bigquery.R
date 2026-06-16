
# Load packages
if (!require("pacman")) install.packages("pacman")
pacman::p_load("bigrquery", "readr", "readxl", "dplyr", "here", "DBI")


# Configuration -----------------------------------------------------------
project_id  <- "churn-project-banking"
dataset_id  <- "raw"
location    <- "EU"
data_dir    <- here("data/raw")
key_path    <- "/Users/christoffercappelen/Documents/keys/churn-project-banking-fd63b0da09ff.json"


# Authentication ----------------------------------------------------------
bigrquery::bq_auth(path = key_path)


# Create dataset if it doesn't exist --------------------------------------
ds <- bq_dataset(project_id, dataset_id)
if (!bq_dataset_exists(ds)) {
  bq_dataset_create(ds, location = location)
  message("Created dataset: ", dataset_id)
} else {
  message("Dataset already exists: ", dataset_id)
}


# Upload data -------------------------------------------------------------
csv_files <- list.files(data_dir, pattern = "\\.csv$", full.names = TRUE)

for(x in csv_files) {
  table_name <- tools::file_path_sans_ext(basename(x))
  message("Uploading: ", table_name, " ...")
  
  df <- read_csv(x, col_types = cols(.default = "c"))  # all columns as character, will convert types in staging
  
  table_ref <- bq_table(project_id, dataset_id, table_name)
  
  bq_table_upload(
    x = table_ref,
    values = df,
    create_disposition = "CREATE_IF_NEEDED",
    write_disposition  = "WRITE_TRUNCATE"   # overwrite if re-running
  )
  
  message("  -> Done: ", nrow(df), " rows loaded")
}

message("All files uploaded to ", project_id, ".", dataset_id)



