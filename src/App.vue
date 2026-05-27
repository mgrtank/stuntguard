<script setup>
import { computed, reactive, ref } from "vue";
import { invoke } from "@tauri-apps/api/core";

const views = [
  { id: "overview", label: "Practitioner Overview" },
  { id: "newpatient", label: "New Patient Entry" },
  { id: "intake", label: "Patient Intake & Growth" },
  { id: "prediction", label: "Prediction & Risk" },
  { id: "profile", label: "360° Patient View" },
  { id: "care", label: "Intervention & Care Plan" },
];

const defaultPatients = [
  {
    id: "P-1042",
    name: "Amina K.",
    ageMonths: 18,
    risk: "Red",
    hfaZ: -2.8,
    followUp: "Due this week",
    lastVisit: "2026-05-21",
    drivers: ["Frequent diarrheal episodes", "Low birth weight", "Food insecurity"],
    interventions: ["Micronutrient supplementation", "Caregiver counseling"],
    timeline: [
      "2026-05-21 Growth plateau detected",
      "2026-05-13 Diarrheal episode",
      "2026-05-01 Nutrition follow-up",
    ],
    medicalHistory: ["Chronic diarrhea", "Mild respiratory infection"],
    caregiver: { name: "Mariam K.", phone: "+48 500 222 111" },
    referralStatus: "Pending",
    educationTopics: ["Protein intake", "Handwashing"],
    growthSamples: [66.2, 67.1, 67.3, 67.2],
    photos: [],
  },
  {
    id: "P-1088",
    name: "Noah M.",
    ageMonths: 22,
    risk: "Yellow",
    hfaZ: -1.9,
    followUp: "Next month",
    lastVisit: "2026-05-12",
    drivers: ["Prematurity", "Limited dietary diversity", "Household sanitation"],
    interventions: ["Growth monitoring", "Feeding education"],
    timeline: [
      "2026-05-12 Vaccination review",
      "2026-04-20 Follow-up consultation",
      "2026-04-01 Intake visit",
    ],
    medicalHistory: ["Prematurity"],
    caregiver: { name: "Anna M.", phone: "+48 500 333 444" },
    referralStatus: "Not required",
    educationTopics: ["Diet diversity"],
    growthSamples: [69.0, 69.5, 70.1, 70.2],
    photos: [],
  },
  {
    id: "P-1105",
    name: "Lina S.",
    ageMonths: 14,
    risk: "Green",
    hfaZ: -0.7,
    followUp: "Routine",
    lastVisit: "2026-05-24",
    drivers: ["No active clinical red flags", "Stable growth", "Breastfeeding maintained"],
    interventions: ["Routine review"],
    timeline: [
      "2026-05-24 Routine review",
      "2026-05-01 Immunization update",
      "2026-04-10 Intake visit",
    ],
    medicalHistory: ["No significant infections"],
    caregiver: { name: "Olga S.", phone: "+48 500 111 222" },
    referralStatus: "Closed",
    educationTopics: ["Complementary feeding"],
    growthSamples: [63.0, 63.8, 64.4, 65.0],
    photos: [],
  },
];

const patients = ref([...defaultPatients]);
const currentView = ref("overview");
const selectedPatientId = ref(defaultPatients[0].id);
const riskFilter = ref("All");
const searchText = ref("");

const auth = reactive({
  storagePassphrase: "",
  mode: "unlock",
});

const authenticated = ref(false);
const authMessage = ref("Sign in to access the practitioner dashboard");

const storageUnlocked = ref(false);
const storageMessage = ref("Storage locked");

const selectedPatient = computed(() => patients.value.find((patient) => patient.id === selectedPatientId.value) ?? null);

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
  return value
    .split(/\n|,/)
    .map((item) => item.trim())
    .filter(Boolean);
}

function patientToForm(patient) {
  patientForm.id = patient.id;
  patientForm.name = patient.name;
  patientForm.ageMonths = String(patient.ageMonths);
  patientForm.risk = patient.risk;
  patientForm.hfaZ = String(patient.hfaZ);
  patientForm.followUp = patient.followUp;
  patientForm.lastVisit = patient.lastVisit;
  patientForm.driversText = patient.drivers.join("\n");
  patientForm.interventionsText = patient.interventions.join("\n");

  intakeForm.ageMonths = patient.ageMonths;
  intakeForm.bodyWeight = Number(patient.bodyWeight ?? 10);
  intakeForm.bodyLength = Number(patient.bodyLength ?? 70);
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
  const id = patientForm.id.trim() || nextPatientId();
  const existing = patients.value.find((patient) => patient.id === id);

  if (patientForm.risk === "Pending assessment" || !String(patientForm.hfaZ).trim()) {
    alert("Run Patient Intake & Growth and Prediction & Risk first so the assessment fields are filled in.");
    return;
  }

  const payload = {
    ...(existing ?? {}),
    id,
    name: patientForm.name.trim(),
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
    timeline: existing?.timeline ?? [],
    medicalHistory: existing?.medicalHistory ?? [],
    caregiver: existing?.caregiver ?? { name: "", phone: "" },
    referralStatus: intervention.referralStatus,
    educationTopics: existing?.educationTopics ?? [],
    growthSamples: existing?.growthSamples ?? [],
    photos: existing?.photos ?? [],
  };

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
}

function selectPatient(patient) {
  selectedPatientId.value = patient.id;
  patientToForm(patient);
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
  const total = patients.value.length;
  const highRisk = patients.value.filter((patient) => patient.risk === "Red").length;
  const due = patients.value.filter((patient) => patient.followUp === "Due this week" || patient.followUp === "Overdue").length;

  return {
    total,
    highRiskPct: total ? Math.round((highRisk / total) * 100) : 0,
    due,
  };
});

const urgentAlerts = computed(() => {
  return patients.value
    .filter((patient) => patient.risk === "Red" || patient.followUp === "Overdue" || patient.hfaZ <= -2.8)
    .map((patient) => ({
      id: patient.id,
      name: patient.name,
      reason: patient.followUp === "Overdue" ? "Follow-up overdue" : patient.hfaZ <= -2.8 ? "Growth curve decline" : "High risk status",
    }));
});

const growthChartPoints = computed(() => {
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
  } catch (e) {
    authMessage.value = `Auth failed: ${String(e)}`;
  }
}

function logout() {
  authenticated.value = false;
  storageUnlocked.value = false;
  authMessage.value = "Signed out";
}

async function loadPatientsFromStore() {
  try {
    const res = await invoke("load_patients");
    const parsed = JSON.parse(res);
    patients.value = parsed;
    if (patients.value[0]) {
      selectPatient(patients.value[0]);
    }
    storageMessage.value = `Loaded ${patients.value.length} patients`;
  } catch (e) {
    storageMessage.value = `Load failed: ${String(e)}`;
    alert(storageMessage.value);
  }
}

async function savePatientsToStore() {
  try {
    await invoke("save_patients", { patientsJson: JSON.stringify(patients.value) });
    storageMessage.value = `Saved ${patients.value.length} patients`;
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

    if (currentView.value === "profile" && selectedPatient.value) {
      selectedPatient.value.hfaZ = Number(result.z_score);
      selectedPatient.value.risk = result.z_score < -3 ? "Red" : result.z_score < -2 ? "Yellow" : "Green";
      selectedPatient.value.growthSamples = [...(selectedPatient.value.growthSamples ?? []), Number(intakeForm.bodyLength)].slice(-8);
      patientForm.hfaZ = String(result.z_score);
    }
  } catch (e) {
    growthMessage.value = `Z-score failed: ${String(e)}`;
    alert(growthMessage.value);
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

    if (currentView.value === "profile" && selectedPatient.value) {
      selectedPatient.value.drivers = result.top_risk_drivers?.length ? result.top_risk_drivers : selectedPatient.value.drivers;
    }
  } catch (e) {
    predictionResult.value = null;
    predictionStatus.value = `Prediction failed: ${String(e)}`;
    alert(predictionStatus.value);
  } finally {
    predictionBusy.value = false;
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

if (patients.value[0]) {
  patientToForm(patients.value[0]);
}
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
          <button type="button" class="secondary" @click="loadPatientsFromStore">Load</button>
          <button type="button" class="secondary" @click="savePatientsToStore">Save</button>
          <button type="button" class="danger" @click="logout">Logout</button>
          <small class="status-line">{{ storageMessage }}</small>
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
              <button type="button" @click="upsertPatient">Save new patient</button>
              <button type="button" class="secondary" @click="startNewPatientEntry">Fresh entry</button>
              <button type="button" class="secondary" @click="currentView = 'profile'">Go to profile</button>
            </div>
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
          <article class="panel">
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
          <article class="panel">
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
