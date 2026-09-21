use std::env;
use std::fs::File;
use std::io::Write;
use std::path::PathBuf;
use std::time::Instant;

use sensio_ppg_core::ffi::{load_ring_ppg_csv, load_sigmot_csv};
use sensio_ppg_core::pipeline::analyze_session;

fn main() {
    let args: Vec<String> = env::args().collect();

    let mut ppg_file: Option<PathBuf> = None;
    let mut sigmot_file: Option<PathBuf> = None;
    let mut out_json: Option<PathBuf> = None;
    let mut max_samples: Option<usize> = None;
    let sample_rate = 50.0;

    let mut i = 1;
    while i < args.len() {
        match args[i].as_str() {
            "--file" | "-f" => {
                if i + 1 < args.len() {
                    ppg_file = Some(PathBuf::from(&args[i + 1]));
                    i += 1;
                }
            }
            "--sigmot" | "-s" => {
                if i + 1 < args.len() {
                    sigmot_file = Some(PathBuf::from(&args[i + 1]));
                    i += 1;
                }
            }
            "--out" | "-o" => {
                if i + 1 < args.len() {
                    out_json = Some(PathBuf::from(&args[i + 1]));
                    i += 1;
                }
            }
            "--samples" | "-n" => {
                if i + 1 < args.len() {
                    max_samples = args[i + 1].parse().ok();
                    i += 1;
                }
            }
            _ => {}
        }
        i += 1;
    }

    let ppg_path = match ppg_file {
        Some(p) => p,
        None => {
            eprintln!("Usage: sensio_ppg_engine --file <ppg_data.csv> [--sigmot <sigmot_data.csv>] [--out <output.json>] [--samples <N>]");
            std::process::exit(1);
        }
    };

    println!("============================================================");
    println!("  SENSIO PPG RUST CORE ENGINE (CLI RUNNER)");
    println!("============================================================");
    println!("Loading PPG file: {}", ppg_path.display());

    let t_start = Instant::now();
    let (mut raw_sec, mut raw_val) = match load_ring_ppg_csv(&ppg_path) {
        Ok(data) => data,
        Err(e) => {
            eprintln!("Error loading PPG file: {}", e);
            std::process::exit(1);
        }
    };

    if let Some(n) = max_samples {
        if n < raw_sec.len() {
            println!("Slicing first {} samples for rapid verification", n);
            raw_sec.truncate(n);
            raw_val.truncate(n);
        }
    }

    let sigmot_path = if let Some(s_path) = sigmot_file {
        if s_path.exists() {
            Some(s_path)
        } else {
            None
        }
    } else if let Some(parent) = ppg_path.parent() {
        if let Some(fname) = ppg_path.file_name().and_then(|f| f.to_str()) {
            let cand = parent.join(fname.replace("_ppg_data.csv", "_sigmot_data.csv"));
            if cand.exists() {
                Some(cand)
            } else {
                None
            }
        } else {
            None
        }
    } else {
        None
    };

    let (sig_sec, sig_val) = if let Some(ref s_path) = sigmot_path {
        println!("Loading SigMot file: {}", s_path.display());
        match load_sigmot_csv(s_path) {
            Some((s, v)) => (Some(s), Some(v)),
            None => (None, None),
        }
    } else {
        (None, None)
    };

    println!(
        "Raw samples: {} | Duration: {:.1} s | Target Fs: {:.1} Hz",
        raw_val.len(),
        raw_sec.last().unwrap_or(&0.0) - raw_sec.first().unwrap_or(&0.0),
        sample_rate
    );

    let sig_sec_ref = sig_sec.as_deref();
    let sig_val_ref = sig_val.as_deref();

    let res = match analyze_session(&raw_sec, &raw_val, sample_rate, sig_sec_ref, sig_val_ref) {
        Ok(r) => r,
        Err(e) => {
            eprintln!("Analysis error: {}", e);
            std::process::exit(1);
        }
    };

    let elapsed = t_start.elapsed();
    println!("\nAnalysis completed in: {:.2?}", elapsed);
    println!("------------------------------------------------------------");
    println!("  Coverage: {:.1}%", res.coverage_pct);
    println!(
        "  Windows: {} total ({} accepted)",
        res.total_window_count, res.accepted_window_count
    );
    println!("  Detected Beats: {}", res.peaks_indices.len());
    println!("  Gapless Macro-Episodes: {}", res.gapless_segments.len());
    println!("  HRV Sliding Bins: {}", res.hrv.timestamps.len());

    println!("\nTop Clinical Feature Summary:");
    for row in res.summary.iter().take(12) {
        println!(
            "  [{:<10}] {:<20}: Mean={:>7.2} ± {:>6.2} | Median={:>7.2}",
            row.domain, row.metric, row.mean, row.sd, row.median
        );
    }

    if let Some(out_path) = out_json {
        if let Some(parent) = out_path.parent() {
            let _ = std::fs::create_dir_all(parent);
        }
        let json_str = serde_json::to_string_pretty(&res).unwrap();
        let mut file = File::create(&out_path).expect("Failed to create output JSON");
        file.write_all(json_str.as_bytes()).expect("Failed to write JSON");
        println!("\nExported complete analysis result to: {}", out_path.display());
    }
}
