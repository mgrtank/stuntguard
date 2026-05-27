# StuntGuard

StuntGuard is a Tauri + Vue desktop app with a Rust backend and an R package for training and scoring a portable stunting-risk model.

## Collaboration Guide

This repository is ready to share as a normal Git project. For collaboration, commit the source and configuration files listed below, plus the generated model bundle in `src-tauri/r/stuntguardr/inst/models/` if you want everyone to run the same prediction model.

Do not share build outputs such as `node_modules/`, `dist/`, or `src-tauri/target/`. Those are recreated locally.

## Prerequisites

Install these tools before setting up the project:

- Node.js LTS and npm
- Rust stable toolchain with Cargo
- R with `Rscript.exe`

On Windows, if `Rscript.exe` is not installed in the default location, set the `STUNTGUARD_RSCRIPT` environment variable to the full path of your local `Rscript.exe`.

Example:

```powershell
$env:STUNTGUARD_RSCRIPT = "C:\Program Files\R\R-4.6.0\bin\Rscript.exe"
```

## Setup From Scratch

1. Clone or copy the repository to your machine.
2. Open a terminal in the project root.
3. Install the npm dependencies.

```powershell
npm install
```

If you want a fully reproducible install in a clean checkout, use the lockfile-aware form instead:

```powershell
npm ci
```

4. Verify that Rust is available.

```powershell
cargo --version
```

5. Verify that R is available.

```powershell
Rscript --version
```

6. If you need to regenerate the model bundle, run the R training script from the package directory.

```powershell
Set-Location src-tauri/r/stuntguardr
& $env:STUNTGUARD_RSCRIPT inst/scripts/train_model.R
```

The script reads `data/Stunting_Dataset.csv` from the repository root by default and writes the model bundle to `src-tauri/r/stuntguardr/inst/models/stunting_model.json` together with `training_metrics.json`.

## Run the App

Use Tauri for the full desktop app. It starts the Vite frontend and builds the Rust backend automatically.

```powershell
npm run tauri dev
```

For frontend-only development, run Vite directly:

```powershell
npm run dev
```

To create a production build:

```powershell
npm run tauri build
```

## Rust Checks

If you want to work on the backend directly, build the Rust side from `src-tauri`:

```powershell
Set-Location src-tauri
cargo build
```

## R Package Workflow

The R package lives in `src-tauri/r/stuntguardr`.

The package code does three jobs:

- prepares the stunting dataset
- trains and exports a portable model bundle
- scores new records for the desktop app

The prediction script used by the app is `src-tauri/r/stuntguardr/inst/scripts/predict_patient.R`.

The app calls the Rust command layer, which in turn runs the exported R model bundle.

## Required Source and Configuration Files

These are the files that should stay in version control for collaboration:

- `package.json`
- `package-lock.json`
- `vite.config.js`
- `index.html`
- `src/main.js`
- `src/App.vue`
- `src/assets/`
- `public/`
- `data/Stunting_Dataset.csv`
- `src-tauri/Cargo.toml`
- `src-tauri/build.rs`
- `src-tauri/tauri.conf.json`
- `src-tauri/capabilities/default.json`
- `src-tauri/src/main.rs`
- `src-tauri/src/lib.rs`
- `src-tauri/gen/schemas/`
- `src-tauri/r/stuntguardr/DESCRIPTION`
- `src-tauri/r/stuntguardr/NAMESPACE`
- `src-tauri/r/stuntguardr/README.md`
- `src-tauri/r/stuntguardr/R/data_prep.R`
- `src-tauri/r/stuntguardr/R/model.R`
- `src-tauri/r/stuntguardr/R/evaluation.R`
- `src-tauri/r/stuntguardr/inst/scripts/train_model.R`
- `src-tauri/r/stuntguardr/inst/scripts/predict_patient.R`
- `src-tauri/r/stuntguardr/inst/scripts/calculate_hfa_z.R`
- `src-tauri/r/stuntguardr/inst/models/stunting_model.json`
- `src-tauri/r/stuntguardr/inst/models/training_metrics.json`

## Notes For Collaborators

- Keep the model bundle files in sync with the training script when the dataset or model logic changes.
- Rebuild the app after editing any Rust, Vue, Tauri, or R source file.
- If the app cannot find `Rscript.exe`, define `STUNTGUARD_RSCRIPT` before starting Tauri.

## IDE Setup

Recommended VS Code extensions:

- Vue - Official
- Tauri
- rust-analyzer
