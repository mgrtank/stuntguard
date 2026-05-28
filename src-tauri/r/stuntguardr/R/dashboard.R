stg_default_views <- function() {
  list(
    list(id = "overview", label = "Practitioner Overview"),
    list(id = "newpatient", label = "New Patient Entry"),
    list(id = "intake", label = "Patient Intake & Growth"),
    list(id = "prediction", label = "Prediction & Risk"),
    list(id = "profile", label = "360° Patient View"),
    list(id = "care", label = "Intervention & Care Plan")
  )
}

stg_default_patients <- function() {
  list(
    list(
      id = "P-1042",
      name = "Amina K.",
      ageMonths = 18,
      risk = "Red",
      hfaZ = -2.8,
      followUp = "Due this week",
      lastVisit = "2026-05-21",
      drivers = c("Frequent diarrheal episodes", "Low birth weight", "Food insecurity"),
      interventions = c("Micronutrient supplementation", "Caregiver counseling"),
      timeline = c(
        "2026-05-21 Growth plateau detected",
        "2026-05-13 Diarrheal episode",
        "2026-05-01 Nutrition follow-up"
      ),
      medicalHistory = c("Chronic diarrhea", "Mild respiratory infection"),
      caregiver = list(name = "Mariam K.", phone = "+48 500 222 111"),
      referralStatus = "Pending",
      educationTopics = c("Protein intake", "Handwashing"),
      growthSamples = c(66.2, 67.1, 67.3, 67.2),
      photos = list(),
      bodyWeight = 8.9,
      bodyLength = 67.2
    ),
    list(
      id = "P-1088",
      name = "Noah M.",
      ageMonths = 22,
      risk = "Yellow",
      hfaZ = -1.9,
      followUp = "Next month",
      lastVisit = "2026-05-12",
      drivers = c("Prematurity", "Limited dietary diversity", "Household sanitation"),
      interventions = c("Growth monitoring", "Feeding education"),
      timeline = c(
        "2026-05-12 Vaccination review",
        "2026-04-20 Follow-up consultation",
        "2026-04-01 Intake visit"
      ),
      medicalHistory = c("Prematurity"),
      caregiver = list(name = "Anna M.", phone = "+48 500 333 444"),
      referralStatus = "Not required",
      educationTopics = c("Diet diversity"),
      growthSamples = c(69.0, 69.5, 70.1, 70.2),
      photos = list(),
      bodyWeight = 10.3,
      bodyLength = 70.2
    ),
    list(
      id = "P-1105",
      name = "Lina S.",
      ageMonths = 14,
      risk = "Green",
      hfaZ = -0.7,
      followUp = "Routine",
      lastVisit = "2026-05-24",
      drivers = c("No active clinical red flags", "Stable growth", "Breastfeeding maintained"),
      interventions = c("Routine review"),
      timeline = c(
        "2026-05-24 Routine review",
        "2026-05-01 Immunization update",
        "2026-04-10 Intake visit"
      ),
      medicalHistory = c("No significant infections"),
      caregiver = list(name = "Olga S.", phone = "+48 500 111 222"),
      referralStatus = "Closed",
      educationTopics = c("Complementary feeding"),
      growthSamples = c(63.0, 63.8, 64.4, 65.0),
      photos = list(),
      bodyWeight = 9.6,
      bodyLength = 65.0
    )
  )
}

`%||%` <- function(left, right) {
  if (is.null(left) || length(left) == 0 || identical(left, "")) {
    right
  } else {
    left
  }
}

stg_patient_field <- function(patient, field, default = NULL) {
  if (is.null(patient) || length(patient) == 0) {
    return(default)
  }

  if (!is.list(patient)) {
    patient <- as.list(patient)
  }

  if (is.null(names(patient)) || !(field %in% names(patient))) {
    return(default)
  }

  value <- patient[[field]]
  if (is.null(value) || length(value) == 0) {
    default
  } else {
    value
  }
}

stg_patient_to_list <- function(patient) {
  if (is.null(patient) || length(patient) == 0) {
    return(NULL)
  }

  if (is.data.frame(patient)) {
    if (nrow(patient) == 0) {
      return(NULL)
    }

    return(as.list(patient[1, , drop = FALSE]))
  }

  if (is.atomic(patient) && !is.null(names(patient))) {
    return(as.list(patient))
  }

  if (is.list(patient)) {
    return(as.list(patient))
  }

  NULL
}

stg_normalize_patient <- function(patient) {
  patient <- stg_patient_to_list(patient)
  if (is.null(patient)) {
    return(NULL)
  }

  intake_profile <- stg_patient_field(patient, "intakeProfile", list())
  prediction_profile <- stg_patient_field(patient, "predictionProfile", list())

  list(
    id = as.character(stg_patient_field(patient, "id", "")),
    name = as.character(stg_patient_field(patient, "name", "")),
    ageMonths = suppressWarnings(as.numeric(stg_patient_field(patient, "ageMonths", 0))),
    risk = as.character(stg_patient_field(patient, "risk", "Pending assessment")),
    hfaZ = suppressWarnings(as.numeric(stg_patient_field(patient, "hfaZ", NA_real_))),
    followUp = as.character(stg_patient_field(patient, "followUp", "Pending assessment")),
    lastVisit = as.character(stg_patient_field(patient, "lastVisit", "")),
    drivers = as.list(stg_patient_field(patient, "drivers", list())),
    interventions = as.list(stg_patient_field(patient, "interventions", list())),
    timeline = as.list(stg_patient_field(patient, "timeline", list())),
    medicalHistory = as.list(stg_patient_field(patient, "medicalHistory", list())),
    caregiver = stg_patient_field(patient, "caregiver", list(name = "", phone = "")),
    referralStatus = as.character(stg_patient_field(patient, "referralStatus", "Pending")),
    educationTopics = as.list(stg_patient_field(patient, "educationTopics", list())),
    growthSamples = suppressWarnings(as.numeric(unlist(stg_patient_field(patient, "growthSamples", list()), use.names = FALSE))),
    photos = as.list(stg_patient_field(patient, "photos", list())),
    bodyWeight = suppressWarnings(as.numeric(stg_patient_field(patient, "bodyWeight", stg_patient_field(intake_profile, "bodyWeight", NA_real_)))),
    bodyLength = suppressWarnings(as.numeric(stg_patient_field(patient, "bodyLength", stg_patient_field(intake_profile, "bodyLength", NA_real_)))),
    headCircumference = suppressWarnings(as.numeric(stg_patient_field(patient, "headCircumference", stg_patient_field(intake_profile, "headCircumference", NA_real_)))),
    gender = as.character(stg_patient_field(patient, "gender", stg_patient_field(prediction_profile, "gender", "Male"))),
    intakeProfile = if (length(intake_profile) == 0) list() else as.list(intake_profile),
    predictionProfile = if (length(prediction_profile) == 0) list() else as.list(prediction_profile),
    intakeHistory = as.list(stg_patient_field(patient, "intakeHistory", list())),
    predictionHistory = as.list(stg_patient_field(patient, "predictionHistory", list()))
  )
}

stg_normalize_patient_list <- function(patients) {
  if (is.null(patients) || length(patients) == 0) {
    return(list())
  }

  if (is.data.frame(patients)) {
    return(lapply(seq_len(nrow(patients)), function(index) stg_normalize_patient(patients[index, , drop = FALSE])))
  }

  patient_fields <- c("id", "name", "ageMonths", "risk", "hfaZ", "followUp", "lastVisit")

  if (is.list(patients) && !is.null(names(patients)) && any(names(patients) %in% patient_fields)) {
    return(list(stg_normalize_patient(patients)))
  }

  if (!is.list(patients)) {
    return(list())
  }

  normalized <- lapply(patients, stg_normalize_patient)
  Filter(Negate(is.null), normalized)
}

stg_dashboard <- function(patients = stg_default_patients(), selected_patient_id = NULL, risk_filter = "All", search_text = "") {
  patients <- stg_normalize_patient_list(patients)

  if (is.null(selected_patient_id) && length(patients) > 0) {
    selected_patient_id <- patients[[1]]$id
  }

  structure(
    list(
      patients = patients,
      selectedPatientId = selected_patient_id %||% "",
      riskFilter = risk_filter %||% "All",
      searchText = search_text %||% ""
    ),
    class = "stg_dashboard"
  )
}

stg_dashboard_patient_by_id <- function(patients, patient_id) {
  patients <- stg_normalize_patient_list(patients)

  for (patient in patients) {
    if (identical(stg_patient_field(patient, "id", ""), patient_id)) {
      return(patient)
    }
  }
  NULL
}

stg_dashboard_metrics <- function(patients) {
  patients <- stg_normalize_patient_list(patients)

  total <- length(patients)
  high_risk <- sum(vapply(patients, function(patient) identical(stg_patient_field(patient, "risk", ""), "Red"), logical(1)))
  due <- sum(vapply(patients, function(patient) {
    follow_up <- stg_patient_field(patient, "followUp", "")
    identical(follow_up, "Due this week") || identical(follow_up, "Overdue")
  }, logical(1)))

  list(
    total = total,
    highRiskPct = if (total > 0) round((high_risk / total) * 100) else 0,
    due = due
  )
}

stg_dashboard_urgent_alerts <- function(patients) {
  patients <- stg_normalize_patient_list(patients)
  alerts <- list()

  for (patient in patients) {
    risk <- stg_patient_field(patient, "risk", "")
    follow_up <- stg_patient_field(patient, "followUp", "")
    hfa_z <- suppressWarnings(as.numeric(stg_patient_field(patient, "hfaZ", NA_real_)))

    if (identical(risk, "Red") || identical(follow_up, "Overdue") || isTRUE(hfa_z <= -2.8)) {
      reason <- if (identical(follow_up, "Overdue")) {
        "Follow-up overdue"
      } else if (isTRUE(hfa_z <= -2.8)) {
        "Growth curve decline"
      } else {
        "High risk status"
      }

      alerts[[length(alerts) + 1]] <- list(
        id = stg_patient_field(patient, "id", ""),
        name = stg_patient_field(patient, "name", ""),
        reason = reason
      )
    }
  }

  alerts
}

stg_dashboard_filtered_patients <- function(patients, risk_filter = "All", search_text = "") {
  patients <- stg_normalize_patient_list(patients)
  query <- trimws(tolower(search_text %||% ""))

  filtered <- list()
  for (patient in patients) {
    patient_id <- tolower(as.character(stg_patient_field(patient, "id", "")))
    patient_name <- tolower(as.character(stg_patient_field(patient, "name", "")))
    risk_match <- identical(risk_filter, "All") || identical(stg_patient_field(patient, "risk", ""), risk_filter)
    text_match <- !nzchar(query) || grepl(query, patient_id, fixed = TRUE) || grepl(query, patient_name, fixed = TRUE)

    if (risk_match && text_match) {
      filtered[[length(filtered) + 1]] <- patient
    }
  }

  filtered
}

stg_dashboard_growth_points <- function(patient) {
  patient <- stg_normalize_patient(patient)
  samples <- patient$growthSamples
  if (is.null(samples) || length(samples) == 0) {
    samples <- c(64, 65, 66, 67)
  }

  min_y <- min(samples)
  max_y <- max(samples)
  span <- max(max_y - min_y, 1)

  points <- character(length(samples))
  for (index in seq_along(samples)) {
    x <- 20 + (index - 1) * (240 / max(length(samples) - 1, 1))
    y <- 140 - ((samples[[index]] - min_y) / span) * 100
    points[[index]] <- paste0(round(x, 2), ",", round(y, 2))
  }

  paste(points, collapse = " ")
}

stg_dashboard_selected_patient <- function(object) {
  object$patients <- stg_normalize_patient_list(object$patients)
  selected <- stg_dashboard_patient_by_id(object$patients, object$selectedPatientId)
  if (!is.null(selected)) {
    return(selected)
  }

  if (length(object$patients) > 0) {
    return(object$patients[[1]])
  }

  NULL
}

stg_dashboard_snapshot <- function(object) {
  UseMethod("stg_dashboard_snapshot")
}

stg_dashboard_snapshot.stg_dashboard <- function(object) {
  object$patients <- stg_normalize_patient_list(object$patients)
  selected_patient <- stg_dashboard_selected_patient(object)
  filtered_patients <- stg_dashboard_filtered_patients(object$patients, object$riskFilter, object$searchText)

  list(
    views = stg_default_views(),
    patients = object$patients,
    currentView = "overview",
    selectedPatientId = if (!is.null(selected_patient)) selected_patient$id else "",
    selectedPatient = selected_patient,
    filteredPatients = filtered_patients,
    metrics = stg_dashboard_metrics(object$patients),
    urgentAlerts = stg_dashboard_urgent_alerts(object$patients),
    growthChartPoints = if (!is.null(selected_patient)) stg_dashboard_growth_points(selected_patient) else "20,140 100,100 180,80 260,60",
    riskFilter = object$riskFilter,
    searchText = object$searchText
  )
}

stg_dashboard_select_patient <- function(object, patient_id) {
  UseMethod("stg_dashboard_select_patient")
}

stg_dashboard_select_patient.stg_dashboard <- function(object, patient_id) {
  object$selectedPatientId <- patient_id %||% object$selectedPatientId
  object
}

stg_dashboard_set_filter <- function(object, risk_filter = "All", search_text = "") {
  UseMethod("stg_dashboard_set_filter")
}

stg_dashboard_set_filter.stg_dashboard <- function(object, risk_filter = "All", search_text = "") {
  object$riskFilter <- risk_filter %||% "All"
  object$searchText <- search_text %||% ""
  object
}

stg_dashboard_upsert_patient <- function(object, patient) {
  UseMethod("stg_dashboard_upsert_patient")
}

stg_dashboard_upsert_patient.stg_dashboard <- function(object, patient) {
  patient <- stg_normalize_patient(patient)
  if (is.null(patient) || is.null(patient$id) || !nzchar(patient$id)) {
    stop("Patient id is required")
  }

  object$patients <- stg_normalize_patient_list(object$patients)
  existing_index <- which(vapply(object$patients, function(item) identical(stg_patient_field(item, "id", ""), patient$id), logical(1)))
  if (length(existing_index) > 0) {
    object$patients[[existing_index[[1]]]] <- patient
  } else {
    object$patients <- c(list(patient), object$patients)
  }

  object$selectedPatientId <- patient$id
  object
}

stg_dashboard_delete_patient <- function(object, patient_id) {
  UseMethod("stg_dashboard_delete_patient")
}

stg_dashboard_delete_patient.stg_dashboard <- function(object, patient_id) {
  object$patients <- stg_normalize_patient_list(object$patients)
  keep <- vapply(object$patients, function(patient) !identical(stg_patient_field(patient, "id", ""), patient_id), logical(1))
  object$patients <- object$patients[keep]

  if (identical(object$selectedPatientId, patient_id)) {
    object$selectedPatientId <- if (length(object$patients) > 0) stg_patient_field(object$patients[[1]], "id", "") else ""
  }

  object
}

stg_dashboard_snapshot.StgDashboardSession <- function(object) {
  object$snapshot()
}

stg_dashboard_select_patient.StgDashboardSession <- function(object, patient_id) {
  object$select_patient(patient_id)
}

stg_dashboard_set_filter.StgDashboardSession <- function(object, risk_filter = "All", search_text = "") {
  object$set_filter(risk_filter = risk_filter, search_text = search_text)
}

stg_dashboard_upsert_patient.StgDashboardSession <- function(object, patient) {
  object$upsert_patient(patient)
}

stg_dashboard_delete_patient.StgDashboardSession <- function(object, patient_id) {
  object$delete_patient(patient_id)
}

StgDashboardSession <- R6::R6Class(
  "StgDashboardSession",
  public = list(
    patients = NULL,
    selected_patient_id = NULL,
    risk_filter = "All",
    search_text = "",
    initialize = function(patients = stg_default_patients(), selected_patient_id = NULL, risk_filter = "All", search_text = "") {
      self$patients <- stg_normalize_patient_list(patients)
      self$selected_patient_id <- selected_patient_id %||% if (length(self$patients) > 0) stg_patient_field(self$patients[[1]], "id", "") else ""
      self$risk_filter <- risk_filter %||% "All"
      self$search_text <- search_text %||% ""
    },
    as_dashboard = function() {
      stg_dashboard(
        patients = self$patients,
        selected_patient_id = self$selected_patient_id,
        risk_filter = self$risk_filter,
        search_text = self$search_text
      )
    },
    snapshot = function() {
      stg_dashboard_snapshot(self$as_dashboard())
    },
    select_patient = function(patient_id) {
      self$selected_patient_id <- patient_id %||% self$selected_patient_id
      invisible(self)
    },
    set_filter = function(risk_filter = "All", search_text = "") {
      self$risk_filter <- risk_filter %||% "All"
      self$search_text <- search_text %||% ""
      invisible(self)
    },
    replace_patients = function(patients) {
      self$patients <- stg_normalize_patient_list(patients)
      if (length(self$patients) > 0 && !nzchar(self$selected_patient_id)) {
        self$selected_patient_id <- stg_patient_field(self$patients[[1]], "id", "")
      }
      if (length(self$patients) == 0) {
        self$selected_patient_id <- ""
      }
      invisible(self)
    },
    upsert_patient = function(patient) {
      updated <- stg_dashboard_upsert_patient(self$as_dashboard(), patient)
      self$patients <- updated$patients
      self$selected_patient_id <- updated$selectedPatientId
      invisible(self)
    },
    delete_patient = function(patient_id) {
      updated <- stg_dashboard_delete_patient(self$as_dashboard(), patient_id)
      self$patients <- updated$patients
      self$selected_patient_id <- updated$selectedPatientId
      invisible(self)
    }
  )
)

stg_dashboard_session <- function(patients = stg_default_patients(), selected_patient_id = NULL, risk_filter = "All", search_text = "") {
  StgDashboardSession$new(
    patients = patients,
    selected_patient_id = selected_patient_id,
    risk_filter = risk_filter,
    search_text = search_text
  )
}