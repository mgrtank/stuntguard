stg_train_portable_model <- function(train_data, seed = 42) {
  numeric_columns <- c("Age", "Birth_Weight", "Birth_Length", "Body_Weight")
  scaled_train <- stg_scale_numeric(train_data, numeric_columns)
  train_scaled <- scaled_train$data

  formula <- stats::as.formula("Stunting ~ Gender + Age + Birth_Weight + Birth_Length + Body_Weight")
  model <- stats::glm(formula, data = train_scaled, family = stats::binomial())

  bundle <- list(
    model_type = "logistic_regression",
    selected_features = c("Gender", "Age", "Birth_Weight", "Birth_Length", "Body_Weight"),
    numeric_columns = numeric_columns,
    feature_means = as.list(scaled_train$means),
    feature_sds = as.list(scaled_train$sds),
    coefficients = as.list(stats::coef(model)),
    training_seed = seed
  )

  bundle
}

stg_predict_portable <- function(bundle, new_data) {
  cleaned <- stg_prepare_data(new_data, select_features = TRUE, include_target = FALSE, dedupe = FALSE)
  numeric_columns <- bundle$numeric_columns
  feature_means <- unlist(bundle$feature_means, use.names = TRUE)
  feature_sds <- unlist(bundle$feature_sds, use.names = TRUE)
  coefficients <- unlist(bundle$coefficients, use.names = TRUE)

  for (column in numeric_columns) {
    cleaned[[column]] <- (cleaned[[column]] - feature_means[[column]]) / feature_sds[[column]]
  }

  design <- model.matrix(~ Gender + Age + Birth_Weight + Birth_Length + Body_Weight, data = cleaned)
  linear_predictor <- drop(design %*% coefficients[colnames(design)])
  probability <- stats::plogis(linear_predictor)

  data.frame(
    probability = probability,
    predicted_class = ifelse(probability >= 0.5, "Stunted", "Not_Stunted"),
    stringsAsFactors = FALSE
  )
}

stg_export_model_bundle <- function(bundle, path) {
  jsonlite::write_json(bundle, path, auto_unbox = TRUE, pretty = TRUE)
  invisible(path)
}

stg_load_model_bundle <- function(path) {
  jsonlite::read_json(path, simplifyVector = TRUE)
}
