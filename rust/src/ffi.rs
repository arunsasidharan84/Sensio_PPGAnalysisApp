//! C-compatible Foreign Function Interface (FFI) for Flutter cross-platform integration.

use std::ffi::{CStr, CString};
use std::fs::File;
use std::io::{BufRead, BufReader};
use std::os::raw::c_char;
use std::path::Path;

use chrono::{NaiveTime, Timelike};
use serde::Serialize;

use crate::pipeline::{analyze_session, SessionAnalysisResult};

#[derive(Serialize)]
struct FfiResponse<T: Serialize> {
    success: bool,
    error: Option<String>,
    data: Option<T>,
}

/// Read timestamps and raw values from a Ring PPG CSV file matching load_ring_ppg() in Python
pub fn load_ring_ppg_csv(path: &Path) -> Result<(Vec<f64>, Vec<f64>), String> {
    let file = File::open(path).map_err(|e| format!("Failed to open PPG file: {}", e))?;
    let reader = BufReader::new(file);

    let mut seconds_list = Vec::new();
    let mut values_list = Vec::new();
    let mut in_data = false;

    let mut prev_total_sec: Option<f64> = None;
    let mut day_offset = 0.0;

    for line_result in reader.lines() {
        let line = match line_result {
            Ok(l) => l,
            Err(_) => continue,
        };
        let trimmed = line.trim();
        if trimmed.is_empty() {
            continue;
        }

        let mut parts = trimmed.split(',');
        let col0 = match parts.next() {
            Some(c) => c.trim(),
            None => continue,
        };

        if !in_data {
            if col0.to_lowercase().starts_with("timestamp") {
                in_data = true;
            }
            continue;
        }

        let col1 = match parts.next() {
            Some(c) => c.trim(),
            None => continue,
        };

        let val: f64 = match col1.parse() {
            Ok(v) => v,
            Err(_) => continue,
        };

        // Format timestamp: HH:MM:SS:mmm -> HH:MM:SS.mmm
        let mut ts_str = col0.to_string();
        if ts_str.matches(':').count() == 3 {
            if let Some(idx) = ts_str.rfind(':') {
                ts_str.replace_range(idx..=idx, ".");
            }
        }

        let time_obj = match NaiveTime::parse_from_str(&ts_str, "%H:%M:%S%.f") {
            Ok(t) => t,
            Err(_) => continue,
        };

        let sec_of_day = (time_obj.hour() as f64) * 3600.0
            + (time_obj.minute() as f64) * 60.0
            + (time_obj.second() as f64)
            + (time_obj.nanosecond() as f64) / 1e9;

        if let Some(prev) = prev_total_sec {
            if sec_of_day < prev - 12.0 * 3600.0 {
                day_offset += 86400.0;
            }
        }
        prev_total_sec = Some(sec_of_day);

        seconds_list.push(sec_of_day + day_offset);
        values_list.push(val);
    }

    if values_list.is_empty() {
        return Err("No valid PPG data found in file".to_string());
    }

    Ok((seconds_list, values_list))
}

/// Read timestamps and values from a matching SigMot IMU CSV file
pub fn load_sigmot_csv(path: &Path) -> Option<(Vec<f64>, Vec<f64>)> {
    let file = File::open(path).ok()?;
    let reader = BufReader::new(file);

    let mut seconds_list = Vec::new();
    let mut values_list = Vec::new();
    let mut in_data = false;

    let mut prev_total_sec: Option<f64> = None;
    let mut day_offset = 0.0;

    for line_result in reader.lines() {
        let line = match line_result {
            Ok(l) => l,
            Err(_) => continue,
        };
        let trimmed = line.trim();
        if trimmed.is_empty() {
            continue;
        }

        let mut parts = trimmed.split(',');
        let col0 = match parts.next() {
            Some(c) => c.trim(),
            None => continue,
        };

        if !in_data {
            if col0.to_lowercase().starts_with("timestamp") {
                in_data = true;
            }
            continue;
        }

        let col1 = match parts.next() {
            Some(c) => c.trim(),
            None => continue,
        };

        let val: f64 = match col1.parse() {
            Ok(v) => v,
            Err(_) => continue,
        };

        let mut ts_str = col0.to_string();
        if ts_str.matches(':').count() == 3 {
            if let Some(idx) = ts_str.rfind(':') {
                ts_str.replace_range(idx..=idx, ".");
            }
        }

        let time_obj = match NaiveTime::parse_from_str(&ts_str, "%H:%M:%S%.f") {
            Ok(t) => t,
            Err(_) => continue,
        };

        let sec_of_day = (time_obj.hour() as f64) * 3600.0
            + (time_obj.minute() as f64) * 60.0
            + (time_obj.second() as f64)
            + (time_obj.nanosecond() as f64) / 1e9;

        if let Some(prev) = prev_total_sec {
            if sec_of_day < prev - 12.0 * 3600.0 {
                day_offset += 86400.0;
            }
        }
        prev_total_sec = Some(sec_of_day);

        seconds_list.push(sec_of_day + day_offset);
        values_list.push(val);
    }

    if values_list.is_empty() {
        None
    } else {
        Some((seconds_list, values_list))
    }
}

/// Helper to convert Rust String into C string pointer
fn to_c_string(s: String) -> *mut c_char {
    match CString::new(s) {
        Ok(c) => c.into_raw(),
        Err(_) => std::ptr::null_mut(),
    }
}

/// Free a C string allocated by sensio_ppg_core
#[no_mangle]
pub extern "C" fn sensio_free_string(ptr: *mut c_char) {
    if !ptr.is_null() {
        unsafe {
            let _ = CString::from_raw(ptr);
        }
    }
}

/// Returns library version string
#[no_mangle]
pub extern "C" fn sensio_get_version() -> *const c_char {
    static VERSION: &[u8] = b"1.0.0\0";
    VERSION.as_ptr() as *const c_char
}

/// Process a PPG CSV file with optional SigMot IMU file, returning JSON
#[no_mangle]
pub extern "C" fn sensio_process_file(
    ppg_path_ptr: *const c_char,
    sigmot_path_ptr: *const c_char,
    sample_rate: f64,
) -> *mut c_char {
    if ppg_path_ptr.is_null() {
        let resp: FfiResponse<SessionAnalysisResult> = FfiResponse {
            success: false,
            error: Some("Null PPG file path".to_string()),
            data: None,
        };
        return to_c_string(serde_json::to_string(&resp).unwrap());
    }

    let ppg_path_str = match unsafe { CStr::from_ptr(ppg_path_ptr) }.to_str() {
        Ok(s) => s,
        Err(e) => {
            let resp: FfiResponse<SessionAnalysisResult> = FfiResponse {
                success: false,
                error: Some(format!("Invalid UTF-8 in PPG path: {}", e)),
                data: None,
            };
            return to_c_string(serde_json::to_string(&resp).unwrap());
        }
    };

    let ppg_path = Path::new(ppg_path_str);
    let (raw_sec, raw_val) = match load_ring_ppg_csv(ppg_path) {
        Ok(data) => data,
        Err(e) => {
            let resp: FfiResponse<SessionAnalysisResult> = FfiResponse {
                success: false,
                error: Some(e),
                data: None,
            };
            return to_c_string(serde_json::to_string(&resp).unwrap());
        }
    };

    let (sig_sec, sig_val) = if !sigmot_path_ptr.is_null() {
        if let Ok(sig_str) = unsafe { CStr::from_ptr(sigmot_path_ptr) }.to_str() {
            let sig_path = Path::new(sig_str);
            if sig_path.exists() {
                match load_sigmot_csv(sig_path) {
                    Some((s, v)) => (Some(s), Some(v)),
                    None => (None, None),
                }
            } else {
                (None, None)
            }
        } else {
            (None, None)
        }
    } else {
        (None, None)
    };

    let fs = if sample_rate > 0.0 { sample_rate } else { 50.0 };

    let sig_sec_ref = sig_sec.as_deref();
    let sig_val_ref = sig_val.as_deref();

    match analyze_session(&raw_sec, &raw_val, fs, sig_sec_ref, sig_val_ref) {
        Ok(result) => {
            let resp = FfiResponse {
                success: true,
                error: None,
                data: Some(result),
            };
            to_c_string(serde_json::to_string(&resp).unwrap())
        }
        Err(e) => {
            let resp: FfiResponse<SessionAnalysisResult> = FfiResponse {
                success: false,
                error: Some(e),
                data: None,
            };
            to_c_string(serde_json::to_string(&resp).unwrap())
        }
    }
}
