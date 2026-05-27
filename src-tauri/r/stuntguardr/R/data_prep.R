stg_feature_names <- c("Gender", "Age", "Birth Weight", "Birth Length", "Body Weight", "Stunting")
stg_selected_features <- c("gender", "age", "birth_weight", "birth_length", "body_weight")

stg_load_dataset <- function(path) {
  data <- utils::read.csv(path, check.names = FALSE, stringsAsFactors = FALSE)
  names(data) <- trimws(names(data))
  data
}

stg_mode <- function(values) {
  values <- values[!is.na(values)]
  if (length(values) == 0) {
    return(NA)
  }
  unique_values <- unique(values)
  unique_values[which.max(tabulate(match(values, unique_values)))]
}

stg_impute_missing <- function(data) {
  numeric_columns <- c("Age", "Birth Weight", "Birth Length", "Body Weight")
  categorical_columns <- c("Gender", "Breastfeeding")

  for (column in numeric_columns) {
    if (column %in% names(data)) {
      data[[column]][is.na(data[[column]])] <- mean(data[[column]], na.rm = TRUE)
    }
  }

  for (column in categorical_columns) {
    if (column %in% names(data)) {
      data[[column]][is.na(data[[column]])] <- stg_mode(data[[column]])
    }
  }

  data
}

stg_prepare_data <- function(data, select_features = TRUE, include_target = TRUE, dedupe = TRUE) {
  if (dedupe) {
    data <- dplyr::distinct(data)
  }
  data <- stg_impute_missing(data)

  if ("Gender" %in% names(data)) {
    if (is.character(data$Gender) || is.factor(data$Gender)) {
      data$Gender <- ifelse(tolower(as.character(data$Gender)) == "male", 1, 0)
    }
    data$Gender <- as.integer(data$Gender)
  }

  if (include_target && "Stunting" %in% names(data)) {
    if (is.character(data$Stunting) || is.factor(data$Stunting)) {
      data$Stunting <- ifelse(tolower(as.character(data$Stunting)) == "yes", 1, 0)
    }
    data$Stunting <- as.integer(data$Stunting)
  }

  canonicalize <- function(name) {
    lowered <- tolower(name)
    lowered <- gsub("[._-]", " ", lowered)
    lowered <- gsub("\\s+", " ", lowered)
    trimws(lowered)
  }

  alias_map <- c(
    "gender" = "Gender",
    "age" = "Age",
    "birth weight" = "Birth_Weight",
    "birth length" = "Birth_Length",
    "body weight" = "Body_Weight",
    "body length" = "Body_Length",
    "breastfeeding" = "Breastfeeding",
    "stunting" = "Stunting"
  )

  current_names <- names(data)
  canonical_names <- vapply(current_names, canonicalize, character(1))
  replacements <- alias_map[canonical_names]
  valid_idx <- !is.na(replacements)
  current_names[valid_idx] <- unname(replacements[valid_idx])
  names(data) <- current_names

  required_features <- c("Gender", "Age", "Birth_Weight", "Birth_Length", "Body_Weight")
  required_columns <- if (include_target) c(required_features, "Stunting") else required_features
  missing_columns <- setdiff(required_columns, names(data))
  if (length(missing_columns) > 0) {
    stop(sprintf("Missing required columns: %s", paste(missing_columns, collapse = ", ")))
  }

  if (select_features) {
    selected_columns <- c("Gender", "Age", "Birth_Weight", "Birth_Length", "Body_Weight")

    if (include_target && "Stunting" %in% names(data)) {
      selected_columns <- c(selected_columns, "Stunting")
    }

    data <- data[, selected_columns]
  } else {
    if ("Body_Length" %in% names(data)) {
      selected_columns <- c("Gender", "Age", "Birth_Weight", "Birth_Length", "Body_Weight", "Body_Length", "Breastfeeding")
      if (include_target && "Stunting" %in% names(data)) {
        selected_columns <- c(selected_columns, "Stunting")
      }
      data <- data[, selected_columns]
    }
  }

  data
}

stg_split_data <- function(data, p = 0.8, seed = 42) {
  set.seed(seed)
  y <- data$Stunting
  positive_idx <- which(y == 1)
  negative_idx <- which(y == 0)

  positive_train <- sample(positive_idx, size = ceiling(length(positive_idx) * p))
  negative_train <- sample(negative_idx, size = ceiling(length(negative_idx) * p))

  train_idx <- sort(unique(c(positive_train, negative_train)))
  train_data <- data[train_idx, , drop = FALSE]
  test_data <- data[-train_idx, , drop = FALSE]

  list(train = train_data, test = test_data)
}

stg_upsample_minority <- function(data, target = "Stunting", seed = 42) {
  set.seed(seed)
  target_values <- data[[target]]
  majority_class <- names(which.max(table(target_values)))
  minority_class <- names(which.min(table(target_values)))

  majority_rows <- data[target_values == majority_class, , drop = FALSE]
  minority_rows <- data[target_values == minority_class, , drop = FALSE]

  if (nrow(minority_rows) == 0 || nrow(majority_rows) == 0) {
    return(data)
  }

  sampled_minority <- minority_rows[sample(seq_len(nrow(minority_rows)), size = nrow(majority_rows), replace = TRUE), , drop = FALSE]
  balanced <- rbind(majority_rows, sampled_minority)
  balanced <- balanced[sample(seq_len(nrow(balanced))), , drop = FALSE]
  rownames(balanced) <- NULL
  balanced
}

stg_scale_numeric <- function(data, numeric_columns) {
  means <- vapply(data[numeric_columns], mean, numeric(1), na.rm = TRUE)
  sds <- vapply(data[numeric_columns], stats::sd, numeric(1), na.rm = TRUE)
  sds[sds == 0] <- 1

  scaled <- data
  for (column in numeric_columns) {
    scaled[[column]] <- (scaled[[column]] - means[[column]]) / sds[[column]]
  }

  list(data = scaled, means = means, sds = sds)
}
