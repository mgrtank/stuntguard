// Simple encrypted local storage for StuntGuard
use std::{fs, path::PathBuf, process::Command, time::{SystemTime, UNIX_EPOCH}};

use aes_gcm::{aead::Aead, Aes256Gcm, KeyInit, Nonce};
use base64::{engine::general_purpose, Engine as _};
use hmac::Hmac;
use once_cell::sync::Lazy;
use pbkdf2::pbkdf2;
use rand::RngCore;
use sha2::Sha256;
use std::sync::Mutex;
use serde::{Deserialize, Serialize};
use serde_json::Value;

static KEYSTORE: Lazy<Mutex<Option<Vec<u8>>>> = Lazy::new(|| Mutex::new(None));

#[derive(Debug, Serialize, Deserialize)]
struct PredictionResponse {
    probability: f64,
    predicted_class: String,
    model_type: String,
    selected_features: Vec<String>,
    top_risk_drivers: Option<Vec<String>>,
    message: String,
}

#[derive(Debug, Serialize, Deserialize)]
struct ZScoreResponse {
    z_score: f64,
    category: String,
    reference: String,
}

fn package_root() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("r").join("stuntguardr")
}

fn model_bundle_path() -> PathBuf {
    package_root().join("inst").join("models").join("stunting_model.json")
}

fn prediction_script_path() -> PathBuf {
    package_root().join("inst").join("scripts").join("predict_patient.R")
}

fn zscore_script_path() -> PathBuf {
    package_root().join("inst").join("scripts").join("calculate_hfa_z.R")
}

fn dashboard_state_script_path() -> PathBuf {
    package_root().join("inst").join("scripts").join("dashboard_state.R")
}

fn find_rscript() -> Result<PathBuf, String> {
    if let Ok(path) = std::env::var("STUNTGUARD_RSCRIPT") {
        let candidate = PathBuf::from(path);
        if candidate.exists() {
            return Ok(candidate);
        }
    }

    let windows_default = PathBuf::from(r"C:\Program Files\R\R-4.6.0\bin\Rscript.exe");
    if windows_default.exists() {
        return Ok(windows_default);
    }

    #[cfg(target_os = "windows")]
    {
        return Err("Rscript.exe was not found. Set STUNTGUARD_RSCRIPT to your Rscript path.".into());
    }

    #[cfg(not(target_os = "windows"))]
    {
        Ok(PathBuf::from("Rscript"))
    }
}

fn app_storage_dir() -> Result<PathBuf, String> {
    let mut dir = dirs_next::data_local_dir()
        .or_else(|| dirs_next::data_dir())
        .ok_or("failed to get app dir")?;
    dir.push("stuntguard");
    fs::create_dir_all(&dir).map_err(|e| e.to_string())?;
    Ok(dir)
}

fn derive_key(password: &str, salt: &[u8]) -> Vec<u8> {
    type HmacSha256 = Hmac<Sha256>;
    let mut key = vec![0u8; 32];
    pbkdf2::<HmacSha256>(password.as_bytes(), salt, 100_000, &mut key);
    key
}

fn encrypt_with_key(key: &[u8], plaintext: &[u8]) -> Result<(Vec<u8>, Vec<u8>), String> {
    let cipher = Aes256Gcm::new_from_slice(key).map_err(|e| e.to_string())?;
    let mut nonce = [0u8; 12];
    rand::rngs::OsRng.fill_bytes(&mut nonce);
    let ct = cipher
        .encrypt(Nonce::from_slice(&nonce), plaintext)
        .map_err(|e| e.to_string())?;
    Ok((nonce.to_vec(), ct))
}

fn decrypt_with_key(key: &[u8], nonce: &[u8], ct: &[u8]) -> Result<Vec<u8>, String> {
    let cipher = Aes256Gcm::new_from_slice(key).map_err(|e| e.to_string())?;
    let pt = cipher
        .decrypt(Nonce::from_slice(nonce), ct)
        .map_err(|e| e.to_string())?;
    Ok(pt)
}

fn run_r_json_script(script_path: PathBuf, request_json: &str) -> Result<String, String> {
    let rscript = find_rscript()?;

    if !script_path.exists() {
        return Err(format!("R script not found: {}", script_path.display()));
    }

    let temp_dir = std::env::temp_dir();
    let unique_id = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map_err(|e| e.to_string())?
        .as_nanos();
    let request_path = temp_dir.join(format!("stg-request-{}-{}.json", std::process::id(), unique_id));
    fs::write(&request_path, request_json).map_err(|e| e.to_string())?;

    let output = Command::new(rscript)
        .arg("--vanilla")
        .arg(script_path)
        .arg(&request_path)
        .output()
        .map_err(|e| e.to_string())?;

    let _ = fs::remove_file(&request_path);

    if !output.status.success() {
        let stderr = String::from_utf8_lossy(&output.stderr).to_string();
        return Err(if stderr.trim().is_empty() {
            format!("R script failed with status {}", output.status)
        } else {
            stderr
        });
    }

    String::from_utf8(output.stdout).map_err(|e| e.to_string())
}

#[tauri::command]
fn init_storage(password: &str) -> Result<bool, String> {
    let dir = app_storage_dir()?;
    let salt_file = dir.join("meta.json");
    let data_file = dir.join("data.enc");

    if salt_file.exists() || data_file.exists() {
        return Err("Storage already initialized".into());
    }

    let mut salt = [0u8; 16];
    rand::rngs::OsRng.fill_bytes(&mut salt);
    let key = derive_key(password, &salt);

    let empty = b"[]";
    let (nonce, ct) = encrypt_with_key(&key, empty)?;

    let payload = serde_json::json!({
        "nonce": general_purpose::STANDARD.encode(&nonce),
        "ciphertext": general_purpose::STANDARD.encode(&ct)
    });
    fs::write(&data_file, payload.to_string()).map_err(|e| e.to_string())?;

    let meta = serde_json::json!({"salt": general_purpose::STANDARD.encode(&salt)});
    fs::write(&salt_file, meta.to_string()).map_err(|e| e.to_string())?;

    let mut ks = KEYSTORE.lock().map_err(|e| e.to_string())?;
    *ks = Some(key);

    Ok(true)
}

#[tauri::command]
fn unlock_storage(password: &str) -> Result<bool, String> {
    let dir = app_storage_dir()?;
    let salt_file = dir.join("meta.json");
    let data_file = dir.join("data.enc");

    if !salt_file.exists() || !data_file.exists() {
        return Err("Storage not initialized".into());
    }

    let meta = fs::read_to_string(&salt_file).map_err(|e| e.to_string())?;
    let meta_json: serde_json::Value = serde_json::from_str(&meta).map_err(|e| e.to_string())?;
    let salt_b64 = meta_json.get("salt").and_then(|v| v.as_str()).ok_or("invalid meta")?;
    let salt = general_purpose::STANDARD.decode(salt_b64).map_err(|e| e.to_string())?;

    let key = derive_key(password, &salt);

    // Try decrypt to verify password
    let data = fs::read_to_string(&data_file).map_err(|e| e.to_string())?;
    let data_json: serde_json::Value = serde_json::from_str(&data).map_err(|e| e.to_string())?;
    let nonce_b64 = data_json.get("nonce").and_then(|v| v.as_str()).ok_or("invalid data")?;
    let ct_b64 = data_json
        .get("ciphertext")
        .and_then(|v| v.as_str())
        .ok_or("invalid data")?;

    let nonce = general_purpose::STANDARD.decode(nonce_b64).map_err(|e| e.to_string())?;
    let ct = general_purpose::STANDARD.decode(ct_b64).map_err(|e| e.to_string())?;

    match decrypt_with_key(&key, &nonce, &ct) {
        Ok(_) => {
            let mut ks = KEYSTORE.lock().map_err(|e| e.to_string())?;
            *ks = Some(key);
            Ok(true)
        }
        Err(_) => Err("Incorrect password".into()),
    }
}

#[tauri::command]
fn save_patients(patients_json: &str) -> Result<bool, String> {
    let dir = app_storage_dir()?;
    let data_file = dir.join("data.enc");

    let ks = KEYSTORE.lock().map_err(|e| e.to_string())?;
    let key = ks.as_ref().ok_or("Storage locked")?;

    let (nonce, ct) = encrypt_with_key(key, patients_json.as_bytes())?;
    let payload = serde_json::json!({
        "nonce": general_purpose::STANDARD.encode(&nonce),
        "ciphertext": general_purpose::STANDARD.encode(&ct)
    });
    fs::write(&data_file, payload.to_string()).map_err(|e| e.to_string())?;

    Ok(true)
}

#[tauri::command]
fn load_patients() -> Result<String, String> {
    let dir = app_storage_dir()?;
    let data_file = dir.join("data.enc");

    let ks = KEYSTORE.lock().map_err(|e| e.to_string())?;
    let key = ks.as_ref().ok_or("Storage locked")?;

    let data = fs::read_to_string(&data_file).map_err(|e| e.to_string())?;
    let data_json: serde_json::Value = serde_json::from_str(&data).map_err(|e| e.to_string())?;
    let nonce_b64 = data_json.get("nonce").and_then(|v| v.as_str()).ok_or("invalid data")?;
    let ct_b64 = data_json
        .get("ciphertext")
        .and_then(|v| v.as_str())
        .ok_or("invalid data")?;

    let nonce = general_purpose::STANDARD.decode(nonce_b64).map_err(|e| e.to_string())?;
    let ct = general_purpose::STANDARD.decode(ct_b64).map_err(|e| e.to_string())?;

    let pt = decrypt_with_key(key, &nonce, &ct)?;
    let s = String::from_utf8(pt).map_err(|e| e.to_string())?;
    Ok(s)
}

#[tauri::command]
fn dashboard_snapshot(request_json: String) -> Result<Value, String> {
    let stdout = run_r_json_script(dashboard_state_script_path(), &request_json)?;
    let parsed: Value = serde_json::from_str(&stdout).map_err(|e| e.to_string())?;
    Ok(parsed)
}

#[tauri::command]
fn predict_stunting(input_json: &str) -> Result<PredictionResponse, String> {
    let rscript = find_rscript()?;
    let script_path = prediction_script_path();
    let bundle_path = model_bundle_path();

    if !script_path.exists() {
        return Err(format!("Prediction script not found: {}", script_path.display()));
    }

    if !bundle_path.exists() {
        return Err(format!("Model bundle not found: {}", bundle_path.display()));
    }

    let temp_dir = std::env::temp_dir();
    let unique_id = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map_err(|e| e.to_string())?
        .as_nanos();
    let request_path = temp_dir.join(format!("stg-request-{}-{}.json", std::process::id(), unique_id));
    fs::write(&request_path, input_json).map_err(|e| e.to_string())?;

    let output = Command::new(rscript)
        .arg("--vanilla")
        .arg(script_path)
        .arg(bundle_path)
        .arg(&request_path)
        .output()
        .map_err(|e| e.to_string())?;

    let _ = fs::remove_file(&request_path);

    if !output.status.success() {
        let stderr = String::from_utf8_lossy(&output.stderr).to_string();
        return Err(if stderr.trim().is_empty() {
            format!("Prediction script failed with status {}", output.status)
        } else {
            stderr
        });
    }

    let stdout = String::from_utf8(output.stdout).map_err(|e| e.to_string())?;
    let parsed: PredictionResponse = serde_json::from_str(&stdout).map_err(|e| e.to_string())?;
    Ok(parsed)
}

#[tauri::command]
fn calculate_hfa_z(age_months: f64, length_cm: f64, gender: &str) -> Result<ZScoreResponse, String> {
    let rscript = find_rscript()?;
    let script_path = zscore_script_path();

    if !script_path.exists() {
        return Err(format!("Z-score script not found: {}", script_path.display()));
    }

    let output = Command::new(rscript)
        .arg("--vanilla")
        .arg(script_path)
        .arg(age_months.to_string())
        .arg(length_cm.to_string())
        .arg(gender)
        .output()
        .map_err(|e| e.to_string())?;

    if !output.status.success() {
        let stderr = String::from_utf8_lossy(&output.stderr).to_string();
        return Err(if stderr.trim().is_empty() {
            format!("Z-score script failed with status {}", output.status)
        } else {
            stderr
        });
    }

    let stdout = String::from_utf8(output.stdout).map_err(|e| e.to_string())?;
    let parsed: ZScoreResponse = serde_json::from_str(&stdout).map_err(|e| e.to_string())?;
    Ok(parsed)
}

// Keep the original greet command for testing
#[tauri::command]
fn greet(name: &str) -> String {
    format!("Hello, {}! You've been greeted from Rust!", name)
}

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    tauri::Builder::default()
        .plugin(tauri_plugin_opener::init())
        .invoke_handler(tauri::generate_handler![
            greet,
            init_storage,
            unlock_storage,
            save_patients,
            load_patients,
            dashboard_snapshot,
            predict_stunting,
            calculate_hfa_z
        ])
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}
