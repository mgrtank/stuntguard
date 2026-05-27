args <- commandArgs(trailingOnly = TRUE)

if (length(args) < 3) {
  stop("Usage: calculate_hfa_z.R <age_months> <length_cm> <gender>")
}

age_months <- as.numeric(args[[1]])
length_cm <- as.numeric(args[[2]])
gender <- tolower(args[[3]])

if (is.na(age_months) || is.na(length_cm)) {
  stop("age_months and length_cm must be numeric")
}

# Lightweight WHO-inspired approximation (placeholder) for app workflow prototyping.
# For production, replace with full WHO LMS tables.
if (gender == "male") {
  median <- 49.9 + 1.18 * age_months + 0.002 * age_months^2
  sd <- 2.2 + 0.015 * age_months
} else {
  median <- 49.1 + 1.14 * age_months + 0.002 * age_months^2
  sd <- 2.1 + 0.014 * age_months
}

z <- (length_cm - median) / sd
category <- if (z < -3) {
  "Severe Stunting"
} else if (z < -2) {
  "Stunting"
} else {
  "Normal"
}

out <- list(
  z_score = as.numeric(round(z, 3)),
  category = category,
  reference = "WHO-inspired approximation"
)

cat(jsonlite::toJSON(out, auto_unbox = TRUE, pretty = TRUE))
