args <- commandArgs(trailingOnly = TRUE)

script_file <- normalizePath(sub("^--file=", "", commandArgs(trailingOnly = FALSE)[grepl("^--file=", commandArgs(trailingOnly = FALSE))][1]))
script_dir <- dirname(script_file)
package_root <- normalizePath(file.path(script_dir, "..", ".."))

source(file.path(package_root, "R", "dashboard.R"), local = TRUE)

request <- list()
if (length(args) >= 1 && nzchar(args[[1]]) && file.exists(args[[1]])) {
  request <- jsonlite::fromJSON(args[[1]], simplifyVector = TRUE)
}

patients <- if (!is.null(request$patients) && length(request$patients) > 0) request$patients else stg_default_patients()
dashboard <- stg_dashboard_session(
  patients = patients,
  selected_patient_id = request$selectedPatientId %||% NULL,
  risk_filter = request$riskFilter %||% "All",
  search_text = request$searchText %||% ""
)

snapshot <- stg_dashboard_snapshot(dashboard)
cat(jsonlite::toJSON(snapshot, auto_unbox = TRUE, pretty = TRUE))