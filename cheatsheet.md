# StuntGuard R Cheatsheet

## What the R code in this project does

StuntGuard is split into a small R package and a Tauri/Vue desktop shell.
The R package owns the data logic, model logic, and dashboard state. The desktop app calls into R for calculations and snapshots.

### Main R files

- [R/data_prep.R](src-tauri/r/stuntguardr/R/data_prep.R) prepares raw patient data, standardizes column names, imputes missing values, and scales numeric fields.
- [R/model.R](src-tauri/r/stuntguardr/R/model.R) trains the logistic model, predicts stunting risk, and stores or loads model bundles.
- [R/evaluation.R](src-tauri/r/stuntguardr/R/evaluation.R) computes accuracy, precision, recall, F1, and the confusion matrix.
- [R/dashboard.R](src-tauri/r/stuntguardr/R/dashboard.R) defines the dashboard state object, default patients, filtering, selection, alerts, and growth-chart points.
- [inst/scripts/calculate_hfa_z.R](src-tauri/r/stuntguardr/inst/scripts/calculate_hfa_z.R) calculates the height-for-age Z-score from the command line.
- [inst/scripts/predict_patient.R](src-tauri/r/stuntguardr/inst/scripts/predict_patient.R) loads the saved model bundle and returns prediction JSON.
- [inst/scripts/dashboard_state.R](src-tauri/r/stuntguardr/inst/scripts/dashboard_state.R) receives dashboard input and returns the current snapshot JSON for the app.

### Conceptual flow

1. Raw patient or training data comes in from CSV or JSON.
2. `stg_prepare_data()` cleans and standardizes the columns.
3. `stg_train_portable_model()` builds the model bundle.
4. `stg_predict_portable()` uses that bundle for prediction.
5. `stg_dashboard()` creates the dashboard state object.
6. `stg_dashboard_snapshot()` converts the object into a UI-friendly list.
7. Tauri runs the R scripts and Vue displays the returned JSON.

## Requirement 1: Writing advanced functions in R

### Best existing examples

- [R/data_prep.R](src-tauri/r/stuntguardr/R/data_prep.R) is the strongest example of advanced function design.
- [R/dashboard.R](src-tauri/r/stuntguardr/R/dashboard.R) adds defensive helpers for patient normalization and dashboard state handling.
- [R/model.R](src-tauri/r/stuntguardr/R/model.R) shows reusable prediction and export helpers.

### Why these count

- `stg_prepare_data()` does input validation, canonicalization, conditional feature selection, and error handling.
- `stg_split_data()` and `stg_scale_numeric()` encapsulate repeated logic into reusable helpers.
- `stg_normalize_patient()` and `stg_patient_field()` protect the dashboard from malformed JSON, empty values, and mixed data shapes.
- `stg_predict_portable()` and `stg_train_portable_model()` separate model training from inference and bundle the full model state.

### Defensive-programming patterns already present

- Check for missing required columns before modeling.
- Guard against `NULL`, empty lists, and malformed dashboard records.
- Convert text to canonical names before matching fields.
- Use fallback values for missing patient data.
- Keep model bundle loading and prediction separate from the UI.

### What could be added to make this requirement stronger

- Add explicit `stopifnot()` or custom validator functions for age, length, and gender inputs.
- Add a dedicated `stg_validate_patient()` helper that returns clear messages instead of failing later.
- Add unit tests for bad inputs, missing columns, and malformed patient JSON.
- Add roxygen comments and exported help pages for the public helpers.

### Example you could add

```r
stg_validate_patient <- function(patient) {
  if (is.null(patient$id) || !nzchar(patient$id)) {
    stop("Patient id is required")
  }
  if (is.null(patient$name) || !nzchar(patient$name)) {
    stop("Patient name is required")
  }
  invisible(TRUE)
}
```

## Requirement 2: Object-oriented programming in R

### Best existing examples

- [R/dashboard.R](src-tauri/r/stuntguardr/R/dashboard.R) uses S3.
- `stg_dashboard()` creates an object with class `stg_dashboard`.
- `stg_dashboard_snapshot()`, `stg_dashboard_select_patient()`, `stg_dashboard_set_filter()`, `stg_dashboard_upsert_patient()`, and `stg_dashboard_delete_patient()` are S3 generics with methods.

### Why this counts

- The object stores dashboard state in one place.
- Methods operate on that object instead of using loose global variables.
- The code already uses `UseMethod()` and method dispatch, which is classic S3.

### What is missing

- There is no S4 example.

### What to add for S4

Add a formal patient or model class when you want strict slot validation.

Example idea:

```r
setClass(
  "PatientRecord",
  slots = c(
    id = "character",
    name = "character",
    ageMonths = "numeric",
    risk = "character"
  )
)
```

Then add `setGeneric()` and `setMethod()` for summary, validation, or conversion.

### Current R6 example

The package now includes an R6 dashboard session class, `StgDashboardSession`, built around [R/dashboard.R](src-tauri/r/stuntguardr/R/dashboard.R). It owns mutable dashboard state and exposes methods such as `select_patient()`, `set_filter()`, `upsert_patient()`, `delete_patient()`, and `snapshot()`.

This is the strongest OO example in the project because it shows a real class with encapsulated state and methods instead of only S3 dispatch.

### What to add for S4

Add a formal patient or model class when you want strict slot validation.

Example idea:

```r
setClass(
  "PatientRecord",
  slots = c(
    id = "character",
    name = "character",
    ageMonths = "numeric",
    risk = "character"
  )
)
```

Then add `setGeneric()` and `setMethod()` for summary, validation, or conversion.

### Best way to phrase this in an assignment

- "The project currently demonstrates S3 through a dashboard state object and generic methods."
- "To fully cover OO in R, the next step would be to add either an S4 patient class or an R6 session manager."

## Requirement 3: Code vectorisation and performance optimization

### Best existing examples

- [R/model.R](src-tauri/r/stuntguardr/R/model.R) is the best performance-oriented file.
- [R/evaluation.R](src-tauri/r/stuntguardr/R/evaluation.R) is also mostly vectorized.
- [R/data_prep.R](src-tauri/r/stuntguardr/R/data_prep.R) uses vectorized recoding and scaling in several places.

### Good vectorized examples already in the code

- `stg_scale_numeric()` subtracts means and divides by standard deviations column-wise.
- `stg_evaluate_predictions()` computes confusion-matrix values with vectorized comparisons.
- `stg_prepare_data()` uses vectorized `ifelse()`, `vapply()`, and column operations.
- `stg_predict_portable()` uses `model.matrix()` and matrix multiplication instead of row-by-row prediction.

### Places where performance could be improved further

- [R/dashboard.R](src-tauri/r/stuntguardr/R/dashboard.R) still uses loops for alerts, filtering, and growth points.
- These loops are fine for a small prototype, but they are not the most vectorized version.

### What to add to strengthen this requirement

- Rewrite dashboard filtering with `vapply()` or `dplyr::filter()`.
- Replace manual alert construction with a vectorized patient table.
- Add cached dashboard snapshots if the data becomes larger.
- Measure performance with `bench` or `microbenchmark` and compare the current and optimized versions.

### Example you could add

```r
stg_patient_metrics <- function(patients) {
  risk <- vapply(patients, function(x) x$risk, character(1))
  follow_up <- vapply(patients, function(x) x$followUp, character(1))
  hfa_z <- vapply(patients, function(x) as.numeric(x$hfaZ), numeric(1))

  data.frame(
    total = length(patients),
    red = sum(risk == "Red"),
    overdue = sum(follow_up == "Overdue" | follow_up == "Due this week"),
    severe = sum(hfa_z <= -3, na.rm = TRUE)
  )
}
```

## Requirement 4: Shiny applications and analytical dashboards

### What exists now

- There is no Shiny app in the repository yet.
- The closest thing is the R dashboard state object and the Tauri/Vue UI that consumes it.

### What this means

- The current project demonstrates dashboard logic, but not a Shiny implementation.
- If the course requires explicit Shiny code, this requirement is not yet fully met.

### What to add

Create a small Shiny app that reuses the same R package functions.

Suggested structure:

- [src-tauri/r/stuntguardr/app.R](src-tauri/r/stuntguardr/app.R)
- `ui <- fluidPage(...)`
- `server <- function(input, output, session) { ... }`
- `renderPlot()` for the growth chart
- `renderTable()` or `DT::renderDT()` for patient lists
- `reactiveVal()` for selected patient state
- `observeEvent()` for assessment and save actions

### Best way to connect it to the existing code

- Reuse `stg_dashboard()` and `stg_dashboard_snapshot()`.
- Reuse `stg_predict_portable()` and `stg_dashboard_growth_points()`.
- Store dashboard state in a reactive object and render cards, tables, and charts.

### Example Shiny feature set

- Patient filter sidebar
- Selected patient summary card
- Growth curve chart
- Risk prediction panel
- Save/load button for local encrypted storage

## Requirement 5: Creating and structuring your own R packages

### Best existing examples

- [src-tauri/r/stuntguardr/DESCRIPTION](src-tauri/r/stuntguardr/DESCRIPTION) defines the package metadata.
- [src-tauri/r/stuntguardr/NAMESPACE](src-tauri/r/stuntguardr/NAMESPACE) exports public functions.
- [src-tauri/r/stuntguardr/R/](src-tauri/r/stuntguardr/R) contains package functions by topic.
- [src-tauri/r/stuntguardr/inst/scripts](src-tauri/r/stuntguardr/inst/scripts) contains runtime scripts used by the desktop app.

### Why this is a good package structure

- Data prep, model training, evaluation, and dashboard logic are separated into different files.
- Runtime scripts are stored under `inst/`, which is the right place for non-exported helper scripts.
- The package exposes only the functions the app actually needs.

### What is already good

- Clear function grouping by responsibility.
- A documented package boundary between UI and R logic.
- Model bundle export/load support.
- CLI scripts for Rscript-based integration.

### What could be added to make the package more complete

- Add `README.md` or a vignette explaining usage.
- Add `tests/testthat/` with validation tests.
- Add `R/zzz.R` for startup hooks if needed.
- Add roxygen2 comments and generated man pages.
- Add a `pkgdown` site or vignettes for coursework presentation.

### Suggested package flow for the assignment

1. `DESCRIPTION` declares dependencies.
2. `R/` holds reusable functions.
3. `inst/scripts/` holds command-line helpers used by Tauri.
4. `NAMESPACE` exports only the public API.
5. Tests and docs show that the package is maintained like a real package.

## Quick assignment mapping

| Requirement | Current status | Best example in this project | Gap |
|---|---|---|---|
| Advanced functions in R | Good | `stg_prepare_data()`, `stg_normalize_patient()` | Add stronger validators and tests |
| OO in R | Good | `StgDashboardSession` R6 class and S3 dashboard object | Add S4 |
| Vectorization | Good, but uneven | `stg_scale_numeric()`, `stg_evaluate_predictions()` | Vectorize dashboard loops further |
| Shiny dashboards | Missing | None yet | Add a small `app.R` Shiny dashboard |
| Package structure | Good | `DESCRIPTION`, `NAMESPACE`, `R/`, `inst/` | Add tests and documentation |

## Short conclusion you can use in class

The project already demonstrates advanced R function design, defensive programming, vectorized modeling code, and package structuring. It also demonstrates S3 object-oriented programming through the dashboard state object. To fully satisfy all course requirements, the main missing pieces are an S4 or R6 example and a real Shiny app.