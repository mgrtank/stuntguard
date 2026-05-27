args <- commandArgs(trailingOnly = TRUE)

get_arg <- function(name, default = NA_character_) {
  prefix <- paste0("--", name, "=")
  hit <- args[startsWith(args, prefix)]
  if (length(hit) == 0) {
    return(default)
  }
  sub(prefix, "", hit[1], fixed = TRUE)
}

script_file <- normalizePath(sub("^--file=", "", commandArgs(trailingOnly = FALSE)[grepl("^--file=", commandArgs(trailingOnly = FALSE))][1]))
script_dir <- dirname(script_file)
package_root <- normalizePath(file.path(script_dir, "..", ".."))

source(file.path(package_root, "R", "data_prep.R"), local = TRUE)
source(file.path(package_root, "R", "model.R"), local = TRUE)
source(file.path(package_root, "R", "evaluation.R"), local = TRUE)

input_path <- normalizePath(get_arg("data", file.path(package_root, "..", "..", "..", "data", "Stunting_Dataset.csv")))
output_bundle <- get_arg("output", file.path(package_root, "inst", "models", "stunting_model.json"))
output_metrics <- get_arg("metrics", file.path(package_root, "inst", "models", "training_metrics.json"))
seed <- as.integer(get_arg("seed", "42"))

if (!file.exists(input_path)) {
  stop(sprintf("Dataset not found: %s", input_path))
}

data <- stg_load_dataset(input_path)
prepared <- stg_prepare_data(data, select_features = TRUE, include_target = TRUE, dedupe = TRUE)
split <- stg_split_data(prepared, p = 0.8, seed = seed)
train_data <- stg_upsample_minority(split$train, target = "Stunting", seed = seed)
model_bundle <- stg_train_portable_model(train_data, seed = seed)

train_predictions <- stg_predict_portable(model_bundle, split$train)
test_predictions <- stg_predict_portable(model_bundle, split$test)

train_metrics <- stg_evaluate_predictions(split$train$Stunting, train_predictions$probability)
test_metrics <- stg_evaluate_predictions(split$test$Stunting, test_predictions$probability)

model_bundle$metrics <- list(train = train_metrics, test = test_metrics)
model_bundle$source_data <- basename(input_path)
model_bundle$created_at <- as.character(Sys.time())

stg_export_model_bundle(model_bundle, output_bundle)
jsonlite::write_json(
  model_bundle$metrics,
  output_metrics,
  auto_unbox = TRUE,
  pretty = TRUE,
  na = "null"
)

cat(sprintf("Saved model bundle to %s\n", output_bundle))
cat(sprintf("Saved metrics to %s\n", output_metrics))
