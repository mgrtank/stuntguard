<script setup>
import { computed, onMounted, reactive, ref } from "vue";
import { invoke } from "@tauri-apps/api/core";

const views = [
  { id: "overview", label: "Practitioner Overview" },
  { id: "newpatient", label: "New Patient Entry" },
  { id: "intake", label: "Patient Intake & Growth" },
  { id: "prediction", label: "Prediction & Risk" },
  { id: "profile", label: "360° Patient View" },
  { id: "care", label: "Intervention & Care Plan" },
];

const patients = ref([]);
const currentView = ref("overview");
const selectedPatientId = ref("");
const riskFilter = ref("All");
const searchText = ref("");
const dashboardSnapshot = ref(null);
const dashboardMessage = ref("Loading dashboard from R...");

const auth = reactive({
  storagePassphrase: "",
  mode: "unlock",
});

const authenticated = ref(false);
const authMessage = ref("Sign in to access the practitioner dashboard");

const storageUnlocked = ref(false);
const storageMessage = ref("Storage locked");

const selectedPatient = computed(() => {
  const patient = patients.value.find((entry) => entry.id === selectedPatientId.value);
  return patient ? normalizePatient(patient) : null;
});

const patientForm = reactive({
  id: "",
  name: "",
  ageMonths: "",
  risk: "Pending assessment",
  hfaZ: "",
  followUp: "Pending assessment",
  lastVisit: new Date().toISOString().slice(0, 10),
  driversText: "",
  interventionsText: "",
});

const intakeForm = reactive({
  gender: "Male",
  ageMonths: 17,
  bodyWeight: 10,
  bodyLength: 72,
  headCircumference: 46,
});

const zScoreResult = ref(null);
const growthMessage = ref("Run calculation to update HFA Z-score");
const assessmentBusy = ref(false);
const assessmentStatus = ref("Assessment runs on save");
let autosaveTimer = null;

const selectedIntakeHistory = computed(() => selectedPatient.value?.intakeHistory ?? []);
const selectedPredictionHistory = computed(() => selectedPatient.value?.predictionHistory ?? []);

const predictionForm = reactive({
  gender: "Male",
  age: 17,
  birthWeight: 3.0,
  birthLength: 49,
  bodyWeight: 10,
  maternalHeight: 160,
  maternalBmi: 23,
  pregnancyComplications: false,
  gestationalAge: 38,
  cleanWater: true,
  sanitation: true,
  householdIncome: "Medium",
  exclusiveBreastfeeding: false,
  dietaryDiversity: "Low",
});

const predictionResult = ref(null);
const predictionStatus = ref("Not run yet");
const predictionBusy = ref(false);

const intervention = reactive({
  supplementation: false,
  deworming: false,
  therapeuticFeeding: false,
  educationProtein: false,
  educationHandwash: false,
  referralStatus: "Pending",
});

const selectedPhotoPreview = ref("");

function asText(value, fallback = "") {
  return value === null || value === undefined ? fallback : String(value);
}

function asNumber(value, fallback = 0) {
  const parsed = Number(value);
  return Number.isFinite(parsed) ? parsed : fallback;
}

function cloneHistory(entries) {
  if (!Array.isArray(entries)) {
    return [];
  }

  return entries.map((entry) => {
    if (entry && typeof entry === "object") {
      return { ...entry };
    }

    return { label: String(entry) };
  });
}

function latestHistoryEntry(entries) {
  return Array.isArray(entries) && entries.length ? entries[entries.length - 1] : null;
}

function historyLabel(entry, fallbackLabel) {
  if (!entry || typeof entry !== "object") {
    return fallbackLabel;
  }

  const date = asText(entry.date);
  const parts = [];

  if (date) {
    parts.push(date);
  }

  if (entry.zScore !== undefined) {
    parts.push(`Z ${Number(entry.zScore).toFixed(2)}`);
  }

  if (entry.probability !== undefined) {
    parts.push(`${Math.round(Number(entry.probability) * 100)}%`);
  }

  if (entry.predictedClass) {
    parts.push(asText(entry.predictedClass));
  }

  if (entry.bodyLength !== undefined || entry.bodyWeight !== undefined) {
    parts.push(
      [entry.bodyLength !== undefined ? `${asNumber(entry.bodyLength).toFixed(1)} cm` : null, entry.bodyWeight !== undefined ? `${asNumber(entry.bodyWeight).toFixed(1)} kg` : null]
        .filter(Boolean)
        .join(" | ")
    );
  }

  return parts.filter(Boolean).join(" - ") || fallbackLabel;
}

function normalizePatient(patient = {}) {
  const intakeProfile = patient.intakeProfile && typeof patient.intakeProfile === "object" ? patient.intakeProfile : {};
  const predictionProfile = patient.predictionProfile && typeof patient.predictionProfile === "object" ? patient.predictionProfile : {};

  return {
    ...patient,
    id: asText(patient.id),
    name: asText(patient.name),
    ageMonths: asNumber(patient.ageMonths, 0),
    risk: asText(patient.risk, "Pending assessment"),
    hfaZ: Number.isFinite(Number(patient.hfaZ)) ? Number(patient.hfaZ) : "",
    followUp: asText(patient.followUp, "Pending assessment"),
    lastVisit: asText(patient.lastVisit, new Date().toISOString().slice(0, 10)),
    drivers: Array.isArray(patient.drivers) ? patient.drivers.map((entry) => asText(entry)) : [],
    interventions: Array.isArray(patient.interventions) ? patient.interventions.map((entry) => asText(entry)) : [],
    timeline: Array.isArray(patient.timeline) ? patient.timeline.map((entry) => asText(entry)) : [],
    medicalHistory: Array.isArray(patient.medicalHistory) ? patient.medicalHistory.map((entry) => asText(entry)) : [],
    caregiver: {
      name: asText(patient.caregiver?.name),
      phone: asText(patient.caregiver?.phone),
    },
    referralStatus: asText(patient.referralStatus, "Pending"),
    educationTopics: Array.isArray(patient.educationTopics) ? patient.educationTopics.map((entry) => asText(entry)) : [],
    growthSamples: Array.isArray(patient.growthSamples)
      ? patient.growthSamples.map((entry) => Number(entry)).filter((entry) => Number.isFinite(entry))
      : [],
    photos: Array.isArray(patient.photos) ? patient.photos.map((entry) => asText(entry)) : [],
    bodyWeight: asNumber(patient.bodyWeight, asNumber(intakeProfile.bodyWeight, 10)),
    bodyLength: asNumber(patient.bodyLength, asNumber(intakeProfile.bodyLength, 70)),
    headCircumference: asNumber(patient.headCircumference, asNumber(intakeProfile.headCircumference, 46)),
    gender: asText(patient.gender, asText(predictionProfile.gender, "Male")),
    intakeProfile: {
      gender: asText(intakeProfile.gender, asText(patient.gender, "Male")),
      ageMonths: asNumber(intakeProfile.ageMonths, asNumber(patient.ageMonths, 0)),
      bodyWeight: asNumber(intakeProfile.bodyWeight, asNumber(patient.bodyWeight, 10)),
      bodyLength: asNumber(intakeProfile.bodyLength, asNumber(patient.bodyLength, 70)),
      headCircumference: asNumber(intakeProfile.headCircumference, asNumber(patient.headCircumference, 46)),
    },
    predictionProfile: {
      gender: asText(predictionProfile.gender, asText(patient.gender, "Male")),
      age: asNumber(predictionProfile.age, asNumber(patient.ageMonths, 0)),
      birthWeight: asNumber(predictionProfile.birthWeight, 3.0),
      birthLength: asNumber(predictionProfile.birthLength, 49),
      bodyWeight: asNumber(predictionProfile.bodyWeight, asNumber(patient.bodyWeight, 10)),
      maternalHeight: asNumber(predictionProfile.maternalHeight, 160),
      maternalBmi: asNumber(predictionProfile.maternalBmi, 23),
      pregnancyComplications: Boolean(predictionProfile.pregnancyComplications),
      gestationalAge: asNumber(predictionProfile.gestationalAge, 38),
      cleanWater: predictionProfile.cleanWater !== undefined ? Boolean(predictionProfile.cleanWater) : true,
      sanitation: predictionProfile.sanitation !== undefined ? Boolean(predictionProfile.sanitation) : true,
      householdIncome: asText(predictionProfile.householdIncome, "Medium"),
      exclusiveBreastfeeding: Boolean(predictionProfile.exclusiveBreastfeeding),
      dietaryDiversity: asText(predictionProfile.dietaryDiversity, "Low"),
    },
    intakeHistory: cloneHistory(patient.intakeHistory),
    predictionHistory: cloneHistory(patient.predictionHistory),
  };
}

function syncFormsFromPatient(patient) {
  const normalized = normalizePatient(patient);

  patientForm.id = normalized.id;
  patientForm.name = normalized.name;
  patientForm.ageMonths = String(normalized.ageMonths);
  patientForm.risk = normalized.risk;
  patientForm.hfaZ = String(normalized.hfaZ);
  patientForm.followUp = normalized.followUp;
  patientForm.lastVisit = normalized.lastVisit;
  patientForm.driversText = normalized.drivers.join("\n");
  patientForm.interventionsText = normalized.interventions.join("\n");

  const intakeSource = latestHistoryEntry(normalized.intakeHistory) ?? normalized.intakeProfile;
  intakeForm.gender = asText(intakeSource.gender, normalized.gender || "Male");
  intakeForm.ageMonths = asNumber(intakeSource.ageMonths, normalized.ageMonths);
  intakeForm.bodyWeight = asNumber(intakeSource.bodyWeight, normalized.bodyWeight);
  intakeForm.bodyLength = asNumber(intakeSource.bodyLength, normalized.bodyLength);
  intakeForm.headCircumference = asNumber(intakeSource.headCircumference, normalized.headCircumference);

  const predictionSource = latestHistoryEntry(normalized.predictionHistory) ?? normalized.predictionProfile;
  predictionForm.gender = asText(predictionSource.gender, normalized.gender || "Male");
  predictionForm.age = asNumber(predictionSource.age, normalized.ageMonths);
  predictionForm.birthWeight = asNumber(predictionSource.birthWeight, predictionForm.birthWeight);
  predictionForm.birthLength = asNumber(predictionSource.birthLength, predictionForm.birthLength);
  predictionForm.bodyWeight = asNumber(predictionSource.bodyWeight, normalized.bodyWeight);
  predictionForm.maternalHeight = asNumber(predictionSource.maternalHeight, predictionForm.maternalHeight);
  predictionForm.maternalBmi = asNumber(predictionSource.maternalBmi, predictionForm.maternalBmi);
  predictionForm.pregnancyComplications = Boolean(predictionSource.pregnancyComplications);
  predictionForm.gestationalAge = asNumber(predictionSource.gestationalAge, predictionForm.gestationalAge);
  predictionForm.cleanWater = predictionSource.cleanWater !== undefined ? Boolean(predictionSource.cleanWater) : predictionForm.cleanWater;
  predictionForm.sanitation = predictionSource.sanitation !== undefined ? Boolean(predictionSource.sanitation) : predictionForm.sanitation;
  predictionForm.householdIncome = asText(predictionSource.householdIncome, predictionForm.householdIncome);
  predictionForm.exclusiveBreastfeeding = Boolean(predictionSource.exclusiveBreastfeeding);
  predictionForm.dietaryDiversity = asText(predictionSource.dietaryDiversity, predictionForm.dietaryDiversity);

  return normalized;
}

function normalizePatientsList(list) {
  return Array.isArray(list) ? list.map((patient) => normalizePatient(patient)) : [];
}

function selectedPatientIndex() {
  return patients.value.findIndex((patient) => patient.id === selectedPatientId.value);
}

function selectedPatientDraftFromForms() {
  const current = selectedPatient.value;
  if (!current) {
    return null;
  }

  return normalizePatient({
    ...current,
    bodyWeight: Number(intakeForm.bodyWeight) || current.bodyWeight,
    bodyLength: Number(intakeForm.bodyLength) || current.bodyLength,
    headCircumference: Number(intakeForm.headCircumference) || current.headCircumference,
    gender: predictionForm.gender,
    intakeProfile: {
      gender: intakeForm.gender,
      ageMonths: Number(intakeForm.ageMonths) || 0,
      bodyWeight: Number(intakeForm.bodyWeight) || 0,
      bodyLength: Number(intakeForm.bodyLength) || 0,
      headCircumference: Number(intakeForm.headCircumference) || 0,
    },
    predictionProfile: { ...predictionForm, age: Number(predictionForm.age) || 0 },
  });
}

async function persistSelectedPatientDraft(options = {}) {
  const idx = selectedPatientIndex();
  if (idx < 0) {
    return;
  }

  const existing = normalizePatient(patients.value[idx]);
  const draft = selectedPatientDraftFromForms();
  if (!draft) {
    return;
  }

  const merged = normalizePatient({
    ...existing,
    ...draft,
    drivers: existing.drivers,
    interventions: existing.interventions,
    timeline: existing.timeline,
    medicalHistory: existing.medicalHistory,
    caregiver: existing.caregiver,
    referralStatus: existing.referralStatus,
    educationTopics: existing.educationTopics,
    growthSamples: existing.growthSamples,
    photos: existing.photos,
    intakeHistory: existing.intakeHistory,
    predictionHistory: existing.predictionHistory,
  });

  patients.value[idx] = merged;

  if (options.save !== false) {
    await savePatientsToStore();
  }
}

function scheduleSelectedPatientAutosave() {
  if (!selectedPatient.value) {
    return;
  }

  window.clearTimeout(autosaveTimer);
  autosaveTimer = window.setTimeout(() => {
    persistSelectedPatientDraft().catch((error) => {
      storageMessage.value = `Auto-save failed: ${String(error)}`;
    });
  }, 500);
}

function startNewPatientEntry() {
  resetPatientForm();
  intervention.referralStatus = "Pending";
  zScoreResult.value = null;
  predictionResult.value = null;
  predictionStatus.value = "Not run yet";
  growthMessage.value = "Run calculation to update HFA Z-score";
  currentView.value = "newpatient";
}

function deriveRiskCategory(zScore, probability) {
  if (Number.isFinite(zScore)) {
    if (zScore <= -3) return "Red";
    if (zScore <= -2) return "Yellow";
    return "Green";
  }

  if (typeof probability === "number") {
    if (probability >= 0.8) return "Red";
    if (probability >= 0.55) return "Yellow";
    return "Green";
  }

  return "Pending assessment";
}

function deriveFollowUp(riskCategory) {
  if (riskCategory === "Red") return "Due this week";
  if (riskCategory === "Yellow") return "Next month";
  if (riskCategory === "Green") return "Routine";
  return "Pending assessment";
}

function updateDraftAssessment({ zScore, probability } = {}) {
  const parsedZScore = Number.isFinite(Number(zScore)) ? Number(zScore) : Number.NaN;
  const derivedRisk = deriveRiskCategory(parsedZScore, probability);

  if (Number.isFinite(parsedZScore)) {
    patientForm.hfaZ = String(parsedZScore);
  }

  patientForm.risk = derivedRisk;
  patientForm.followUp = deriveFollowUp(derivedRisk);
}

function splitLines(value) {
  return String(value ?? "")
    .split(/\n|,/)
    .map((item) => item.trim())
    .filter(Boolean);
}

function patientToForm(patient) {
  syncFormsFromPatient(patient);
}

function resetPatientForm() {
  patientForm.id = "";
  patientForm.name = "";
  patientForm.ageMonths = "";
  patientForm.risk = "Pending assessment";
  patientForm.hfaZ = "";
  patientForm.followUp = "Pending assessment";
  patientForm.lastVisit = new Date().toISOString().slice(0, 10);
  patientForm.driversText = "";
  patientForm.interventionsText = "";
}

function nextPatientId() {
  const numbers = patients.value
    .map((patient) => Number(String(patient.id).replace(/\D+/g, "")))
    .filter((value) => Number.isFinite(value));
  const nextNumber = numbers.length ? Math.max(...numbers) + 1 : 1000;
  return `P-${nextNumber}`;
}

function upsertPatient() {
  const id = String(patientForm.id ?? "").trim() || nextPatientId();
  const existing = patients.value.find((patient) => patient.id === id);

  if (patientForm.risk === "Pending assessment" || !String(patientForm.hfaZ).trim()) {
    alert("Run Patient Intake & Growth and Prediction & Risk first so the assessment fields are filled in.");
    return;
  }

  const normalizedExisting = existing ? normalizePatient(existing) : null;
  const payload = normalizePatient({
    ...(normalizedExisting ?? {}),
    id,
    name: String(patientForm.name ?? "").trim(),
    ageMonths: Number(patientForm.ageMonths) || 0,
    risk: patientForm.risk,
    hfaZ: Number(patientForm.hfaZ) || 0,
    followUp: patientForm.followUp,
    lastVisit: patientForm.lastVisit,
    drivers: splitLines(patientForm.driversText),
    interventions: splitLines(patientForm.interventionsText),
    bodyWeight: Number(intakeForm.bodyWeight) || 0,
    bodyLength: Number(intakeForm.bodyLength) || 0,
    headCircumference: Number(intakeForm.headCircumference) || 0,
    gender: predictionForm.gender,
    intakeProfile: {
      gender: intakeForm.gender,
      ageMonths: Number(intakeForm.ageMonths) || 0,
      bodyWeight: Number(intakeForm.bodyWeight) || 0,
      bodyLength: Number(intakeForm.bodyLength) || 0,
      headCircumference: Number(intakeForm.headCircumference) || 0,
    },
    predictionProfile: { ...predictionForm, age: Number(predictionForm.age) || 0 },
    timeline: normalizedExisting?.timeline ?? [],
    medicalHistory: normalizedExisting?.medicalHistory ?? [],
    caregiver: normalizedExisting?.caregiver ?? { name: "", phone: "" },
    referralStatus: intervention.referralStatus,
    educationTopics: normalizedExisting?.educationTopics ?? [],
    growthSamples: normalizedExisting?.growthSamples ?? [],
    photos: normalizedExisting?.photos ?? [],
    intakeHistory: [
      ...(normalizedExisting?.intakeHistory ?? []),
      {
        date: patientForm.lastVisit,
        gender: intakeForm.gender,
        ageMonths: Number(intakeForm.ageMonths) || 0,
        bodyWeight: Number(intakeForm.bodyWeight) || 0,
        bodyLength: Number(intakeForm.bodyLength) || 0,
        headCircumference: Number(intakeForm.headCircumference) || 0,
        zScore: zScoreResult.value?.z_score ?? null,
      },
    ],
    predictionHistory: [
      ...(normalizedExisting?.predictionHistory ?? []),
      ...(predictionResult.value
        ? [
            {
              date: new Date().toISOString().slice(0, 10),
              ...predictionForm,
              age: Number(predictionForm.age) || 0,
              probability: predictionResult.value.probability,
              predictedClass: predictionResult.value.predicted_class,
            },
          ]
        : []),
    ],
  });

  if (!payload.name) {
    alert("Patient name is required");
    return;
  }

  const idx = patients.value.findIndex((patient) => patient.id === id);
  if (idx >= 0) {
    patients.value[idx] = payload;
  } else {
    patients.value.unshift(payload);
  }

  selectedPatientId.value = id;
  patientToForm(payload);
  refreshDashboardSnapshot({ patients: patients.value, selectedPatientId: id }).catch(() => {});
}

async function assessNewPatientDraft() {
  const [zResult, prediction] = await Promise.all([
    invoke("calculate_hfa_z", {
      ageMonths: Number(intakeForm.ageMonths),
      lengthCm: Number(intakeForm.bodyLength),
      gender: intakeForm.gender,
    }),
    invoke("predict_stunting", {
      inputJson: JSON.stringify({
        Gender: predictionForm.gender,
        Age: Number(predictionForm.age),
        "Birth Weight": Number(predictionForm.birthWeight),
        "Birth Length": Number(predictionForm.birthLength),
        "Body Weight": Number(predictionForm.bodyWeight),
      }),
    }),
  ]);

  zScoreResult.value = zResult;
  predictionResult.value = prediction;
  growthMessage.value = `${zResult.category} (Z=${zResult.z_score})`;
  predictionStatus.value = `${prediction.predicted_class} (${Math.round(prediction.probability * 100)}%)`;
  updateDraftAssessment({ zScore: zResult.z_score, probability: prediction.probability });

  if (prediction.top_risk_drivers?.length) {
    patientForm.driversText = prediction.top_risk_drivers.join("\n");
  }

  return { zResult, prediction };
}

async function saveNewPatientWithAssessment() {
  assessmentBusy.value = true;
  assessmentStatus.value = "Running assessment...";

  try {
    await assessNewPatientDraft();
    assessmentStatus.value = "Assessment complete, saving patient...";
    upsertPatient();
    assessmentStatus.value = "Assessment saved with patient record";
  } catch (e) {
    assessmentStatus.value = `Assessment failed: ${String(e)}`;
    alert(assessmentStatus.value);
  } finally {
    assessmentBusy.value = false;
  }
}

function deletePatient(patientId) {
  if (!window.confirm(`Delete patient ${patientId}?`)) {
    return;
  }

  patients.value = patients.value.filter((patient) => patient.id !== patientId);
  if (selectedPatientId.value === patientId) {
    selectedPatientId.value = patients.value[0]?.id ?? "";
    if (patients.value[0]) {
      patientToForm(patients.value[0]);
    } else {
      resetPatientForm();
    }
  }

  refreshDashboardSnapshot({ patients: patients.value, selectedPatientId: selectedPatientId.value }).catch(() => {});
}

function selectPatient(patient) {
  const normalized = syncFormsFromPatient(patient);
  selectedPatientId.value = normalized.id;
  refreshDashboardSnapshot({ selectedPatientId: normalized.id }).catch(() => {});
}

async function refreshDashboardSnapshot(overrides = {}) {
  const request = {
    selectedPatientId: overrides.selectedPatientId ?? selectedPatientId.value,
    riskFilter: overrides.riskFilter ?? riskFilter.value,
    searchText: overrides.searchText ?? searchText.value,
  };

  const sourcePatients = overrides.patients ?? patients.value;
  if (Array.isArray(sourcePatients) && sourcePatients.length > 0) {
    request.patients = sourcePatients;
  }

  try {
    const snapshot = await invoke("dashboard_snapshot", {
      requestJson: JSON.stringify(request),
    });

    dashboardSnapshot.value = snapshot;
    patients.value = normalizePatientsList(snapshot.patients ?? []);
    selectedPatientId.value = asText(snapshot.selectedPatientId, patients.value[0]?.id ?? "");

    if (snapshot.selectedPatient) {
      patientToForm(snapshot.selectedPatient);
    } else if (patients.value[0]) {
      patientToForm(patients.value[0]);
    } else {
      resetPatientForm();
    }

    dashboardMessage.value = `Dashboard loaded from R (${patients.value.length} patients)`;
    return snapshot;
  } catch (e) {
    dashboardMessage.value = `Dashboard refresh failed: ${String(e)}`;
    throw e;
  }
}

const filteredPatients = computed(() => {
  const query = searchText.value.trim().toLowerCase();
  return patients.value.filter((patient) => {
    const riskMatch = riskFilter.value === "All" || patient.risk === riskFilter.value;
    const textMatch =
      !query ||
      patient.id.toLowerCase().includes(query) ||
      patient.name.toLowerCase().includes(query);
    return riskMatch && textMatch;
  });
});

const metrics = computed(() => {
  return dashboardSnapshot.value?.metrics ?? {
    total: patients.value.length,
    highRiskPct: patients.value.length ? Math.round((patients.value.filter((patient) => patient.risk === "Red").length / patients.value.length) * 100) : 0,
    due: patients.value.filter((patient) => patient.followUp === "Due this week" || patient.followUp === "Overdue").length,
  };
});

const urgentAlerts = computed(() => {
  return dashboardSnapshot.value?.urgentAlerts ?? patients.value
    .filter((patient) => patient.risk === "Red" || patient.followUp === "Overdue" || patient.hfaZ <= -2.8)
    .map((patient) => ({
      id: patient.id,
      name: patient.name,
      reason: patient.followUp === "Overdue" ? "Follow-up overdue" : patient.hfaZ <= -2.8 ? "Growth curve decline" : "High risk status",
    }));
});

const growthChartPoints = computed(() => {
  if (dashboardSnapshot.value?.growthChartPoints) {
    return dashboardSnapshot.value.growthChartPoints;
  }

  const samples = selectedPatient.value?.growthSamples ?? [64, 65, 66, 67];
  const minY = Math.min(...samples);
  const maxY = Math.max(...samples);
  const span = Math.max(maxY - minY, 1);
  return samples
    .map((value, index) => {
      const x = 20 + index * (240 / Math.max(samples.length - 1, 1));
      const y = 140 - ((value - minY) / span) * 100;
      return `${x},${y}`;
    })
    .join(" ");
});

async function authenticate() {
  if (!auth.storagePassphrase) {
    authMessage.value = "Fill storage passphrase";
    return;
  }

  try {
    if (auth.mode === "init") {
      await invoke("init_storage", { password: auth.storagePassphrase });
      storageMessage.value = "Storage initialized";
    } else {
      await invoke("unlock_storage", { password: auth.storagePassphrase });
      storageMessage.value = "Storage unlocked";
    }

    storageUnlocked.value = true;
    authenticated.value = true;
    authMessage.value = "Authenticated";
    currentView.value = "overview";
    await loadPatientsFromStore();
  } catch (e) {
    authMessage.value = `Auth failed: ${String(e)}`;
  }
}

function logout() {
  authenticated.value = false;
  storageUnlocked.value = false;
  auth.storagePassphrase = "";
  authMessage.value = "Signed out";
}

async function loadPatientsFromStore() {
  try {
    const res = await invoke("load_patients");
    const parsed = normalizePatientsList(JSON.parse(res));
    if (parsed.length > 0) {
      patients.value = parsed;
      await refreshDashboardSnapshot({ patients: parsed, selectedPatientId: parsed[0]?.id ?? "" });
      storageMessage.value = `Loaded ${patients.value.length} patients`;
      return;
    }

    await refreshDashboardSnapshot();
    storageMessage.value = `Loaded default patients (${patients.value.length})`;
  } catch (e) {
    storageMessage.value = `Load failed: ${String(e)}`;
    alert(storageMessage.value);
  }
}

async function savePatientsToStore() {
  try {
    await invoke("save_patients", { patientsJson: JSON.stringify(normalizePatientsList(patients.value)) });
    storageMessage.value = `Saved ${patients.value.length} patients`;
    await refreshDashboardSnapshot({ patients: patients.value, selectedPatientId: selectedPatientId.value }).catch(() => {});
  } catch (e) {
    storageMessage.value = `Save failed: ${String(e)}`;
    alert(storageMessage.value);
  }
}

async function calculateZScore() {
  try {
    const result = await invoke("calculate_hfa_z", {
      ageMonths: Number(intakeForm.ageMonths),
      lengthCm: Number(intakeForm.bodyLength),
      gender: intakeForm.gender,
    });

    zScoreResult.value = result;
    growthMessage.value = `${result.category} (Z=${result.z_score})`;
    updateDraftAssessment({ zScore: result.z_score, probability: predictionResult.value?.probability });

    if (selectedPatient.value) {
      const updatedPatient = normalizePatient({
        ...selectedPatient.value,
        hfaZ: Number(result.z_score),
        risk: result.z_score < -3 ? "Red" : result.z_score < -2 ? "Yellow" : "Green",
        growthSamples: [...(selectedPatient.value.growthSamples ?? []), Number(intakeForm.bodyLength)].slice(-8),
        intakeProfile: {
          gender: intakeForm.gender,
          ageMonths: Number(intakeForm.ageMonths) || 0,
          bodyWeight: Number(intakeForm.bodyWeight) || 0,
          bodyLength: Number(intakeForm.bodyLength) || 0,
          headCircumference: Number(intakeForm.headCircumference) || 0,
        },
        intakeHistory: [
          ...(selectedPatient.value.intakeHistory ?? []),
          {
            date: new Date().toISOString().slice(0, 10),
            gender: intakeForm.gender,
            ageMonths: Number(intakeForm.ageMonths) || 0,
            bodyWeight: Number(intakeForm.bodyWeight) || 0,
            bodyLength: Number(intakeForm.bodyLength) || 0,
            headCircumference: Number(intakeForm.headCircumference) || 0,
            zScore: Number(result.z_score),
          },
        ],
      });

      const idx = patients.value.findIndex((patient) => patient.id === updatedPatient.id);
      if (idx >= 0) {
        patients.value[idx] = updatedPatient;
      }

      patientToForm(updatedPatient);
    }
  } catch (e) {
    growthMessage.value = `Z-score failed: ${String(e)}`;
    alert(growthMessage.value);
    return;
  }

  if (selectedPatient.value) {
    await savePatientsToStore();
    await refreshDashboardSnapshot({ patients: patients.value, selectedPatientId: selectedPatientId.value }).catch(() => {});
  }
}

async function runPrediction() {
  predictionBusy.value = true;
  predictionStatus.value = "Running R model...";

  try {
    const modelInput = {
      Gender: predictionForm.gender,
      Age: Number(predictionForm.age),
      "Birth Weight": Number(predictionForm.birthWeight),
      "Birth Length": Number(predictionForm.birthLength),
      "Body Weight": Number(predictionForm.bodyWeight),
    };

    const result = await invoke("predict_stunting", { inputJson: JSON.stringify(modelInput) });
    predictionResult.value = result;
    predictionStatus.value = `${result.predicted_class} (${Math.round(result.probability * 100)}%)`;
    updateDraftAssessment({ zScore: zScoreResult.value?.z_score, probability: result.probability });

    if (result.top_risk_drivers?.length) {
      patientForm.driversText = result.top_risk_drivers.join("\n");
    }

    if (selectedPatient.value) {
      const updatedPatient = normalizePatient({
        ...selectedPatient.value,
        drivers: result.top_risk_drivers?.length ? result.top_risk_drivers : selectedPatient.value.drivers,
        predictionProfile: { ...predictionForm, age: Number(predictionForm.age) || 0 },
        predictionHistory: [
          ...(selectedPatient.value.predictionHistory ?? []),
          {
            date: new Date().toISOString().slice(0, 10),
            ...predictionForm,
            age: Number(predictionForm.age) || 0,
            probability: result.probability,
            predictedClass: result.predicted_class,
          },
        ],
      });

      const idx = patients.value.findIndex((patient) => patient.id === updatedPatient.id);
      if (idx >= 0) {
        patients.value[idx] = updatedPatient;
      }

      patientToForm(updatedPatient);
    }
  } catch (e) {
    predictionResult.value = null;
    predictionStatus.value = `Prediction failed: ${String(e)}`;
    alert(predictionStatus.value);
  } finally {
    predictionBusy.value = false;
  }

  if (selectedPatient.value) {
    await savePatientsToStore();
    await refreshDashboardSnapshot({ patients: patients.value, selectedPatientId: selectedPatientId.value }).catch(() => {});
  }
}

function handlePhotoUpload(event) {
  const file = event.target.files?.[0];
  if (!file || !selectedPatient.value) {
    return;
  }

  const reader = new FileReader();
  reader.onload = () => {
    const dataUrl = String(reader.result || "");
    selectedPhotoPreview.value = dataUrl;
    selectedPatient.value.photos = [...(selectedPatient.value.photos ?? []), dataUrl].slice(-5);
  };
  reader.readAsDataURL(file);
}

onMounted(() => {
  refreshDashboardSnapshot().catch((error) => {
    dashboardMessage.value = `Dashboard load failed: ${String(error)}`;
    if (patients.value[0]) {
      patientToForm(patients.value[0]);
    }
  });
});
</script>

<template>
  <main class="app-shell">
    <section v-if="!authenticated" class="auth-shell">
      <article class="auth-card">
        <p class="eyebrow">StuntGuard Access</p>
        <h1>Storage Unlock</h1>
        <p class="lede">Use your storage passphrase to initialize or unlock encrypted local storage.</p>

        <div class="form-grid single">
          <label>
            <span>Storage passphrase</span>
            <input id="auth-passphrase" name="auth-passphrase" v-model="auth.storagePassphrase" type="password" />
          </label>
          <label>
            <span>Mode</span>
            <select id="auth-mode" name="auth-mode" v-model="auth.mode">
              <option value="unlock">Unlock existing storage</option>
              <option value="init">Initialize new storage</option>
            </select>
          </label>
        </div>

        <div class="action-row top-gap">
          <button type="button" @click="authenticate">Access Dashboard</button>
        </div>
        <small class="status-line">{{ authMessage }}</small>
      </article>
    </section>

    <section v-else class="workspace">
      <aside class="sidebar">
        <h2>StuntGuard</h2>
        <nav>
          <button
            v-for="view in views"
            :key="view.id"
            type="button"
            :class="['nav-btn', { active: currentView === view.id }]"
            @click="currentView = view.id"
          >
            {{ view.label }}
          </button>
        </nav>
        <div class="sidebar-actions">
          <div v-if="selectedPatient" class="selected-patient-banner">
            <span>Selected patient</span>
            <strong>{{ selectedPatient.name }}</strong>
            <small>{{ selectedPatient.id }} | {{ selectedPatient.risk }}</small>
          </div>
          <button type="button" class="secondary" @click="loadPatientsFromStore">Load</button>
          <button type="button" class="secondary" @click="savePatientsToStore">Save</button>
          <button type="button" class="danger" @click="logout">Logout</button>
          <small class="status-line">{{ storageMessage }}</small>
          <small class="status-line">{{ dashboardMessage }}</small>
        </div>
      </aside>

      <section class="view-pane">
        <header class="view-header">
          <p class="eyebrow">{{ views.find((view) => view.id === currentView)?.label }}</p>
          <h1>Local-first stunting decision support</h1>
        </header>

        <section v-if="currentView === 'overview'" class="view-grid">
          <article class="panel metrics-panel">
            <h2>Key Metrics</h2>
            <div class="metrics-grid">
              <div class="metric-card">
                <span>Total patients</span>
                <strong>{{ metrics.total }}</strong>
              </div>
              <div class="metric-card">
                <span>High risk</span>
                <strong>{{ metrics.highRiskPct }}%</strong>
              </div>
              <div class="metric-card">
                <span>Follow-ups due</span>
                <strong>{{ metrics.due }}</strong>
              </div>
            </div>
          </article>

          <article class="panel">
            <h2>Urgent Alerts</h2>
            <ul class="simple-list">
              <li v-for="alert in urgentAlerts" :key="alert.id">
                <strong>{{ alert.name }}</strong> ({{ alert.id }}) - {{ alert.reason }}
              </li>
              <li v-if="urgentAlerts.length === 0">No urgent red flags.</li>
            </ul>
          </article>

          <article class="panel span-two">
            <div class="panel-header">
              <h2>Search & Filter</h2>
              <div class="filter-row">
                <input id="overview-search" name="overview-search" v-model="searchText" type="text" placeholder="Search by ID or name" />
                <select id="overview-risk" name="overview-risk" v-model="riskFilter">
                  <option>All</option>
                  <option>Green</option>
                  <option>Yellow</option>
                  <option>Red</option>
                </select>
              </div>
            </div>

            <ul class="patient-list">
              <li
                v-for="patient in filteredPatients"
                :key="patient.id"
                :class="['patient-row', { active: selectedPatientId === patient.id }]"
                @click="selectPatient(patient)"
              >
                <div>
                  <strong>{{ patient.name }}</strong>
                  <span>{{ patient.id }} - {{ patient.ageMonths }} months - {{ patient.lastVisit }}</span>
                </div>
                <span :class="['risk-chip', patient.risk.toLowerCase()]">{{ patient.risk }}</span>
              </li>
            </ul>
          </article>
        </section>

        <section v-if="currentView === 'newpatient'" class="view-grid">
          <article class="panel span-two">
            <div class="panel-header">
              <div>
                <h2>New Patient Entry</h2>
                <p class="lede">Create a new patient record using the risk factor checklist. HFA Z, risk category, and follow-up are filled from the calculation views.</p>
              </div>
              <button type="button" class="secondary" @click="resetPatientForm">Reset form</button>
            </div>

            <div class="form-grid">
              <label><span>ID</span><input id="new-patient-id" name="new-patient-id" v-model="patientForm.id" type="text" placeholder="Auto-generated if blank" /></label>
              <label><span>Name</span><input id="new-patient-name" name="new-patient-name" v-model="patientForm.name" type="text" /></label>
              <label><span>Age (months)</span><input id="new-patient-age" name="new-patient-age" v-model="patientForm.ageMonths" type="number" min="0" /></label>
            </div>

            <h3 class="section-subtitle">Risk factor checklist</h3>
            <div class="form-grid">
              <label><span>Gender</span><select id="new-patient-gender" name="new-patient-gender" v-model="predictionForm.gender"><option>Male</option><option>Female</option></select></label>
              <label><span>Birth Weight</span><input id="new-patient-birth-weight" name="new-patient-birth-weight" v-model="predictionForm.birthWeight" type="number" step="0.1" /></label>
              <label><span>Birth Length</span><input id="new-patient-birth-length" name="new-patient-birth-length" v-model="predictionForm.birthLength" type="number" step="0.1" /></label>
              <label><span>Current Weight</span><input id="new-patient-weight" name="new-patient-weight" v-model="predictionForm.bodyWeight" type="number" step="0.1" /></label>
              <label><span>Maternal Height (cm)</span><input id="new-patient-maternal-height" name="new-patient-maternal-height" v-model="predictionForm.maternalHeight" type="number" /></label>
              <label><span>Maternal BMI</span><input id="new-patient-maternal-bmi" name="new-patient-maternal-bmi" v-model="predictionForm.maternalBmi" type="number" step="0.1" /></label>
              <label><span>Pregnancy complications</span><select id="new-patient-complications" name="new-patient-complications" v-model="predictionForm.pregnancyComplications"><option :value="false">No</option><option :value="true">Yes</option></select></label>
              <label><span>Gestational age (weeks)</span><input id="new-patient-gestation" name="new-patient-gestation" v-model="predictionForm.gestationalAge" type="number" /></label>
              <label><span>Clean water access</span><select id="new-patient-water" name="new-patient-water" v-model="predictionForm.cleanWater"><option :value="true">Yes</option><option :value="false">No</option></select></label>
              <label><span>Sanitation</span><select id="new-patient-sanitation" name="new-patient-sanitation" v-model="predictionForm.sanitation"><option :value="true">Adequate</option><option :value="false">Limited</option></select></label>
              <label><span>Household income</span><select id="new-patient-income" name="new-patient-income" v-model="predictionForm.householdIncome"><option>Low</option><option>Medium</option><option>High</option></select></label>
              <label><span>Exclusive breastfeeding</span><select id="new-patient-breastfeeding" name="new-patient-breastfeeding" v-model="predictionForm.exclusiveBreastfeeding"><option :value="true">Yes</option><option :value="false">No</option></select></label>
              <label class="full-width"><span>Dietary diversity</span><select id="new-patient-diversity" name="new-patient-diversity" v-model="predictionForm.dietaryDiversity"><option>Low</option><option>Moderate</option><option>High</option></select></label>
            </div>

            <h3 class="section-subtitle">Calculated assessment</h3>
            <div class="metrics-grid assessment-grid">
              <div class="metric-card">
                <span>HFA Z</span>
                <strong>{{ patientForm.hfaZ || 'Run Patient Intake & Growth' }}</strong>
              </div>
              <div class="metric-card">
                <span>Risk category</span>
                <strong>{{ patientForm.risk }}</strong>
              </div>
              <div class="metric-card">
                <span>Follow-up</span>
                <strong>{{ patientForm.followUp }}</strong>
              </div>
              <div class="metric-card full-width">
                <span>Assessment note</span>
                <strong>{{ zScoreResult ? zScoreResult.category : 'Use the calculation views to populate this draft' }}</strong>
                <small v-if="predictionResult">Prediction: {{ predictionResult.predicted_class }} ({{ Math.round(predictionResult.probability * 100) }}%)</small>
              </div>
            </div>

            <div class="action-row top-gap">
              <button type="button" @click="saveNewPatientWithAssessment" :disabled="assessmentBusy">{{ assessmentBusy ? 'Assessing...' : 'Assess & save patient' }}</button>
              <button type="button" class="secondary" @click="startNewPatientEntry">Fresh entry</button>
              <button type="button" class="secondary" @click="currentView = 'profile'">Go to profile</button>
            </div>
            <small class="status-line">{{ assessmentStatus }}</small>
          </article>

          <article class="panel">
            <h2>Current Draft</h2>
            <div class="score-box">
              <span>Name</span>
              <strong>{{ patientForm.name || 'Untitled patient' }}</strong>
              <small>Auto ID: {{ patientForm.id || nextPatientId() }}</small>
              <small>Baseline risk: {{ patientForm.risk }}</small>
            </div>
          </article>

          <article class="panel">
            <h2>What is captured</h2>
            <ul class="simple-list">
              <li>Identity and age</li>
              <li>Initial risk and HFA Z-score</li>
              <li>Drivers and planned interventions</li>
              <li>Follow-up timing for continuity of care</li>
            </ul>
          </article>
        </section>

        <section v-if="currentView === 'intake'" class="view-grid">
          <article class="panel" @input="scheduleSelectedPatientAutosave" @change="scheduleSelectedPatientAutosave">
            <h2>Anthropometric Intake</h2>
            <div class="form-grid">
              <label><span>Gender</span><select id="intake-gender" name="intake-gender" v-model="intakeForm.gender"><option>Male</option><option>Female</option></select></label>
              <label><span>Age (months)</span><input id="intake-age" name="intake-age" v-model="intakeForm.ageMonths" type="number" min="0" /></label>
              <label><span>Weight (kg)</span><input id="intake-weight" name="intake-weight" v-model="intakeForm.bodyWeight" type="number" step="0.1" /></label>
              <label><span>Length/Height (cm)</span><input id="intake-length" name="intake-length" v-model="intakeForm.bodyLength" type="number" step="0.1" /></label>
              <label><span>Head circumference (cm)</span><input id="intake-head" name="intake-head" v-model="intakeForm.headCircumference" type="number" step="0.1" /></label>
            </div>
            <div class="action-row top-gap">
              <button type="button" @click="calculateZScore">Calculate HFA Z-score (R)</button>
            </div>
            <small class="status-line">{{ growthMessage }}</small>
          </article>

          <article class="panel">
            <h2>Selected Patient History</h2>
            <div v-if="selectedPatient" class="history-panel">
              <small class="status-line">Last intake entries for {{ selectedPatient.name }}</small>
              <ul class="simple-list compact-list">
                <li v-for="(entry, index) in selectedIntakeHistory.slice(-3).reverse()" :key="`intake-${index}`">
                  {{ historyLabel(entry, 'No intake history recorded') }}
                </li>
                <li v-if="selectedIntakeHistory.length === 0">No intake history recorded yet.</li>
              </ul>
            </div>
            <p v-else class="status-line">Select a patient to review intake history.</p>
          </article>

          <article class="panel">
            <h2>HFA Classification</h2>
            <div class="score-box">
              <span>Z-score</span>
              <strong>{{ zScoreResult ? zScoreResult.z_score : '-' }}</strong>
              <small>Stunting: $Z < -2$, Severe stunting: $Z < -3$</small>
              <small v-if="zScoreResult">Category: {{ zScoreResult.category }} | {{ zScoreResult.reference }}</small>
            </div>
          </article>

          <article class="panel span-two">
            <h2>Growth Chart (Interactive)</h2>
            <svg viewBox="0 0 280 160" class="growth-chart" role="img" aria-label="Growth curve">
              <polyline points="20,30 260,30" class="chart-line ref-high" />
              <polyline points="20,80 260,80" class="chart-line ref-mid" />
              <polyline points="20,130 260,130" class="chart-line ref-low" />
              <polyline :points="growthChartPoints" class="chart-line patient" />
            </svg>
            <small class="status-line">Patient curve against reference bands (WHO-inspired for prototype).</small>
          </article>
        </section>

        <section v-if="currentView === 'prediction'" class="view-grid">
          <article class="panel" @input="scheduleSelectedPatientAutosave" @change="scheduleSelectedPatientAutosave">
            <h2>Risk Factors Checklist</h2>
            <div class="form-grid">
              <label><span>Maternal Height (cm)</span><input id="pred-mh" name="pred-mh" v-model="predictionForm.maternalHeight" type="number" /></label>
              <label><span>Maternal BMI</span><input id="pred-bmi" name="pred-bmi" v-model="predictionForm.maternalBmi" type="number" step="0.1" /></label>
              <label><span>Pregnancy complications</span><select id="pred-comp" name="pred-comp" v-model="predictionForm.pregnancyComplications"><option :value="false">No</option><option :value="true">Yes</option></select></label>
              <label><span>Gestational age (weeks)</span><input id="pred-gest" name="pred-gest" v-model="predictionForm.gestationalAge" type="number" /></label>
              <label><span>Clean water access</span><select id="pred-water" name="pred-water" v-model="predictionForm.cleanWater"><option :value="true">Yes</option><option :value="false">No</option></select></label>
              <label><span>Sanitation</span><select id="pred-sani" name="pred-sani" v-model="predictionForm.sanitation"><option :value="true">Adequate</option><option :value="false">Limited</option></select></label>
              <label><span>Household income</span><select id="pred-income" name="pred-income" v-model="predictionForm.householdIncome"><option>Low</option><option>Medium</option><option>High</option></select></label>
              <label><span>Exclusive breastfeeding</span><select id="pred-ebf" name="pred-ebf" v-model="predictionForm.exclusiveBreastfeeding"><option :value="true">Yes</option><option :value="false">No</option></select></label>
              <label><span>Dietary diversity</span><select id="pred-dd" name="pred-dd" v-model="predictionForm.dietaryDiversity"><option>Low</option><option>Moderate</option><option>High</option></select></label>
              <label><span>Gender</span><select id="pred-gender" name="pred-gender" v-model="predictionForm.gender"><option>Male</option><option>Female</option></select></label>
              <label><span>Age</span><input id="pred-age" name="pred-age" v-model="predictionForm.age" type="number" /></label>
              <label><span>Birth Weight</span><input id="pred-bw" name="pred-bw" v-model="predictionForm.birthWeight" type="number" step="0.1" /></label>
              <label><span>Birth Length</span><input id="pred-bl" name="pred-bl" v-model="predictionForm.birthLength" type="number" step="0.1" /></label>
              <label><span>Current Weight</span><input id="pred-cw" name="pred-cw" v-model="predictionForm.bodyWeight" type="number" step="0.1" /></label>
            </div>
            <div class="action-row top-gap">
              <button type="button" @click="runPrediction" :disabled="predictionBusy">{{ predictionBusy ? 'Predicting...' : 'Run R Prediction' }}</button>
            </div>
          </article>

          <article class="panel">
            <h2>Selected Patient History</h2>
            <div v-if="selectedPatient" class="history-panel">
              <small class="status-line">Recent prediction runs for {{ selectedPatient.name }}</small>
              <ul class="simple-list compact-list">
                <li v-for="(entry, index) in selectedPredictionHistory.slice(-3).reverse()" :key="`prediction-${index}`">
                  {{ historyLabel(entry, 'No prediction history recorded') }}
                </li>
                <li v-if="selectedPredictionHistory.length === 0">No prediction history recorded yet.</li>
              </ul>
            </div>
            <p v-else class="status-line">Select a patient to review prediction history.</p>
          </article>

          <article class="panel">
            <h2>AI/ML Insights</h2>
            <div class="score-box">
              <span>Status</span>
              <strong>{{ predictionStatus }}</strong>
              <small v-if="predictionResult">Probability: {{ Math.round(predictionResult.probability * 100) }}%</small>
            </div>
            <h3>Top 3 Risk Drivers</h3>
            <ul class="simple-list">
              <li v-for="driver in (predictionResult?.top_risk_drivers ?? selectedPatient?.drivers ?? [])" :key="driver">{{ driver }}</li>
            </ul>
          </article>
        </section>

        <section v-if="currentView === 'profile'" class="view-grid">
          <article class="panel span-two">
            <h2>360° Profile: {{ selectedPatient?.name ?? 'No patient selected' }}</h2>
            <div class="detail-grid">
              <div>
                <h3>Timeline</h3>
                <ul class="simple-list">
                  <li v-for="item in (selectedPatient?.timeline ?? [])" :key="item">{{ item }}</li>
                </ul>
              </div>
              <div>
                <h3>Medical History</h3>
                <ul class="simple-list">
                  <li v-for="item in (selectedPatient?.medicalHistory ?? [])" :key="item">{{ item }}</li>
                </ul>
              </div>
              <div>
                <h3>Caregiver Contact</h3>
                <p>{{ selectedPatient?.caregiver?.name }}</p>
                <p>{{ selectedPatient?.caregiver?.phone }}</p>
                <div class="action-row">
                  <button type="button">Call caregiver</button>
                  <button type="button" class="secondary">Send SMS</button>
                </div>
              </div>
            </div>
          </article>

          <article class="panel">
            <h2>Photo Documentation</h2>
            <input id="photo-upload" name="photo-upload" type="file" accept="image/*" @change="handlePhotoUpload" />
            <img v-if="selectedPhotoPreview" :src="selectedPhotoPreview" alt="Uploaded photo preview" class="photo-preview" />
            <div class="photo-grid">
              <img v-for="(photo, idx) in (selectedPatient?.photos ?? [])" :key="idx" :src="photo" alt="Patient record photo" class="photo-thumb" />
            </div>
          </article>

          <article class="panel">
            <h2>Patient CRUD</h2>
            <div class="form-grid">
              <label><span>ID</span><input id="patient-id" name="patient-id" v-model="patientForm.id" type="text" /></label>
              <label><span>Name</span><input id="patient-name" name="patient-name" v-model="patientForm.name" type="text" /></label>
              <label><span>Age (months)</span><input id="patient-age" name="patient-age" v-model="patientForm.ageMonths" type="number" /></label>
              <label><span>Risk</span><select id="patient-risk" name="patient-risk" v-model="patientForm.risk"><option>Green</option><option>Yellow</option><option>Red</option></select></label>
              <label><span>HFA Z</span><input id="patient-hfa" name="patient-hfa" v-model="patientForm.hfaZ" type="number" step="0.1" /></label>
              <label><span>Follow-up</span><select id="patient-follow" name="patient-follow" v-model="patientForm.followUp"><option>Routine</option><option>Due this week</option><option>Next month</option><option>Overdue</option></select></label>
              <label class="full-width"><span>Drivers</span><textarea id="patient-drivers" name="patient-drivers" v-model="patientForm.driversText" rows="3"></textarea></label>
              <label class="full-width"><span>Interventions</span><textarea id="patient-interventions" name="patient-interventions" v-model="patientForm.interventionsText" rows="3"></textarea></label>
            </div>
            <div class="action-row top-gap">
              <button type="button" @click="upsertPatient">Save patient</button>
              <button type="button" class="secondary" @click="resetPatientForm">Clear</button>
              <button v-if="selectedPatient" type="button" class="danger" @click="deletePatient(selectedPatient.id)">Delete selected</button>
            </div>
          </article>
        </section>

        <section v-if="currentView === 'care'" class="view-grid">
          <article class="panel span-two">
            <h2>Intervention & Care Plan</h2>
            <div class="detail-grid">
              <div>
                <h3>Prescribed Actions</h3>
                <label><input id="care-sup" name="care-sup" type="checkbox" v-model="intervention.supplementation" /> Micronutrient Supplementation</label>
                <label><input id="care-dew" name="care-dew" type="checkbox" v-model="intervention.deworming" /> Deworming</label>
                <label><input id="care-feed" name="care-feed" type="checkbox" v-model="intervention.therapeuticFeeding" /> Therapeutic Feeding</label>
              </div>
              <div>
                <h3>Education Checklist</h3>
                <label><input id="care-protein" name="care-protein" type="checkbox" v-model="intervention.educationProtein" /> Importance of Protein</label>
                <label><input id="care-hand" name="care-hand" type="checkbox" v-model="intervention.educationHandwash" /> Handwashing</label>
              </div>
              <div>
                <h3>Referral Tracking</h3>
                <select id="care-referral" name="care-referral" v-model="intervention.referralStatus">
                  <option>Pending</option>
                  <option>In Progress</option>
                  <option>Completed</option>
                  <option>Closed</option>
                </select>
                <div class="action-row top-gap">
                  <button type="button" @click="savePatientsToStore">Save care plan</button>
                </div>
              </div>
            </div>
          </article>
        </section>
      </section>
    </section>
  </main>
</template>

<style scoped>
:global(:root) {
  font-family: Inter, Avenir, Helvetica, Arial, sans-serif;
  color: #edf4ff;
  background: linear-gradient(180deg, #08111e 0%, #0f1a2b 100%);
}

:global(body) {
  margin: 0;
  min-width: 320px;
  min-height: 100vh;
}

.app-shell {
  min-height: 100vh;
}

.auth-shell {
  min-height: 100vh;
  display: grid;
  place-items: center;
  padding: 20px;
}

.auth-card {
  width: min(620px, 100%);
  border-radius: 22px;
  padding: 24px;
  border: 1px solid rgba(148, 163, 184, 0.2);
  background: rgba(8, 15, 28, 0.82);
}

.workspace {
  display: grid;
  grid-template-columns: 260px minmax(0, 1fr);
  min-height: 100vh;
}

.sidebar {
  border-right: 1px solid rgba(148, 163, 184, 0.2);
  background: rgba(8, 15, 28, 0.9);
  padding: 20px;
  display: grid;
  grid-template-rows: auto 1fr auto;
  gap: 16px;
}

.sidebar h2 {
  margin: 0;
}

.sidebar nav {
  display: grid;
  gap: 10px;
  align-content: start;
}

.nav-btn {
  border: 1px solid rgba(148, 163, 184, 0.2);
  background: rgba(255, 255, 255, 0.03);
  color: #edf4ff;
  border-radius: 12px;
  padding: 10px 12px;
  text-align: left;
  cursor: pointer;
}

.nav-btn.active {
  border-color: rgba(56, 189, 248, 0.7);
  background: rgba(56, 189, 248, 0.14);
}

.sidebar-actions {
  display: grid;
  gap: 8px;
}

.selected-patient-banner {
  display: grid;
  gap: 3px;
  padding: 12px;
  border-radius: 14px;
  border: 1px solid rgba(56, 189, 248, 0.28);
  background: rgba(56, 189, 248, 0.1);
}

.selected-patient-banner span {
  font-size: 0.72rem;
  text-transform: uppercase;
  letter-spacing: 0.12em;
  color: #84d6ff;
}

.selected-patient-banner strong {
  font-size: 1rem;
}

.selected-patient-banner small {
  color: rgba(226, 234, 246, 0.8);
}

.view-pane {
  padding: 24px;
  display: grid;
  gap: 16px;
}

.view-header h1 {
  margin: 0;
  font-size: clamp(1.8rem, 3vw, 2.4rem);
}

.eyebrow {
  margin: 0 0 6px;
  text-transform: uppercase;
  letter-spacing: 0.14em;
  color: #84d6ff;
  font-size: 0.75rem;
}

.lede {
  margin: 0;
  color: rgba(226, 234, 246, 0.86);
}

.view-grid {
  display: grid;
  grid-template-columns: repeat(2, minmax(0, 1fr));
  gap: 16px;
}

.panel {
  border: 1px solid rgba(148, 163, 184, 0.2);
  border-radius: 20px;
  background: rgba(8, 15, 28, 0.8);
  padding: 18px;
}

.span-two {
  grid-column: span 2;
}

.metrics-grid {
  display: grid;
  grid-template-columns: repeat(3, minmax(0, 1fr));
  gap: 10px;
}

.metric-card {
  border: 1px solid rgba(148, 163, 184, 0.15);
  border-radius: 14px;
  padding: 12px;
  background: rgba(255, 255, 255, 0.03);
}

.metric-card strong {
  display: block;
  margin-top: 4px;
  font-size: 1.4rem;
}

.panel-header {
  display: flex;
  justify-content: space-between;
  gap: 12px;
  align-items: center;
}

.filter-row {
  display: flex;
  gap: 8px;
}

.form-grid {
  display: grid;
  grid-template-columns: repeat(2, minmax(0, 1fr));
  gap: 10px;
}

.form-grid.single {
  grid-template-columns: 1fr;
}

.full-width {
  grid-column: 1 / -1;
}

label {
  display: grid;
  gap: 6px;
}

input,
select,
textarea,
button {
  font: inherit;
}

input,
select,
textarea {
  width: 100%;
  box-sizing: border-box;
  border-radius: 12px;
  border: 1px solid rgba(148, 163, 184, 0.25);
  background: rgba(255, 255, 255, 0.05);
  color: #edf4ff;
  padding: 10px 12px;
}

button {
  border: 0;
  border-radius: 12px;
  padding: 10px 14px;
  background: linear-gradient(135deg, #38bdf8, #0ea5e9);
  color: #07111f;
  font-weight: 700;
  cursor: pointer;
}

button.secondary {
  color: #edf4ff;
  background: rgba(255, 255, 255, 0.08);
  border: 1px solid rgba(148, 163, 184, 0.2);
}

button.danger {
  color: #fecaca;
  background: rgba(248, 113, 113, 0.16);
  border: 1px solid rgba(248, 113, 113, 0.28);
}

.action-row {
  display: flex;
  gap: 8px;
  flex-wrap: wrap;
}

.top-gap {
  margin-top: 12px;
}

.simple-list {
  margin: 0;
  padding-left: 18px;
  line-height: 1.6;
}

.compact-list {
  margin-top: 8px;
  font-size: 0.92rem;
}

.history-panel {
  border-radius: 14px;
  padding: 12px;
  border: 1px solid rgba(148, 163, 184, 0.16);
  background: rgba(255, 255, 255, 0.03);
}

.patient-list {
  list-style: none;
  margin: 0;
  padding: 0;
  display: grid;
  gap: 8px;
}

.patient-row {
  border: 1px solid rgba(148, 163, 184, 0.2);
  border-radius: 12px;
  padding: 10px;
  display: flex;
  justify-content: space-between;
  gap: 10px;
  align-items: center;
  background: rgba(255, 255, 255, 0.03);
  cursor: pointer;
}

.patient-row.active {
  border-color: rgba(56, 189, 248, 0.7);
}

.risk-chip {
  border-radius: 999px;
  padding: 6px 10px;
  font-size: 0.78rem;
}

.risk-chip.green { background: rgba(74, 222, 128, 0.16); color: #b6f7cb; }
.risk-chip.yellow { background: rgba(251, 191, 36, 0.16); color: #fde68a; }
.risk-chip.red { background: rgba(248, 113, 113, 0.16); color: #fecaca; }

.detail-grid {
  display: grid;
  grid-template-columns: repeat(3, minmax(0, 1fr));
  gap: 12px;
}

.score-box {
  border-radius: 14px;
  padding: 12px;
  background: rgba(56, 189, 248, 0.14);
}

.growth-chart {
  width: 100%;
  max-width: 420px;
  height: auto;
  border-radius: 12px;
  background: rgba(255, 255, 255, 0.03);
  border: 1px solid rgba(148, 163, 184, 0.2);
}

.chart-line {
  fill: none;
  stroke-width: 2;
}

.chart-line.ref-high,
.chart-line.ref-mid,
.chart-line.ref-low {
  stroke: rgba(148, 163, 184, 0.4);
}

.chart-line.patient {
  stroke: #38bdf8;
  stroke-width: 3;
}

.status-line {
  color: rgba(203, 213, 225, 0.9);
}

.photo-preview {
  margin-top: 10px;
  width: 100%;
  max-width: 240px;
  border-radius: 10px;
}

.photo-grid {
  margin-top: 10px;
  display: flex;
  gap: 8px;
  flex-wrap: wrap;
}

.photo-thumb {
  width: 70px;
  height: 70px;
  object-fit: cover;
  border-radius: 8px;
  border: 1px solid rgba(148, 163, 184, 0.25);
}

@media (max-width: 1080px) {
  .workspace {
    grid-template-columns: 1fr;
  }

  .view-grid,
  .detail-grid,
  .metrics-grid,
  .form-grid {
    grid-template-columns: 1fr;
  }

  .span-two {
    grid-column: auto;
  }
}
</style>
