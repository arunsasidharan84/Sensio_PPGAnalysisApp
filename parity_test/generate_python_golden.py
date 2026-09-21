#!/usr/bin/env python3
"""
Generate Python golden reference output for full parity testing against Rust core engine.
Extracts:
1. Resampled timeline & filtered PPG signal
2. Usable and pulse masks
3. Window SQI battery, accepted flags, and reasons
4. Global systolic beats / peaks
5. All 26 time-resolved HRV and APG morphology parameters across all sliding windows
6. Statistical summary table (Mean, SD, Median, Min, Max for all 26 features)
7. Poincaré geometry (SD1, SD2, ellipse coordinates)
"""

import argparse
import json
from pathlib import Path
import sys
import numpy as np

# Ensure SenseIO Analysis is on path
SENSEIO_DIR = Path("/Users/arunsasidharan/EEGdata/SenseIO/RingData_20260906_onwards")
ANALYSIS_DIR = SENSEIO_DIR / "Analysis"
HRV_APP_DIR = ANALYSIS_DIR / "hrv_review_app"

for d in [str(ANALYSIS_DIR), str(HRV_APP_DIR), str(SENSEIO_DIR)]:
    if d not in sys.path:
        sys.path.insert(0, d)

import ppg_preprocess as ppg_pre
from plot_ring_ppg_mne import load_ring_ppg, find_matching_sigmot_file, load_sigmot_data
from hrv_review_app.data_manager import SessionData
from hrv_review_app.hrv_engine import (
    compute_time_resolved_hrv,
    compute_poincare_data,
    generate_feature_summary,
)


def serialize_ndarray(obj):
    if isinstance(obj, np.ndarray):
        return obj.tolist()
    if isinstance(obj, np.generic):
        return obj.item()
    if isinstance(obj, float) and (np.isnan(obj) or np.isinf(obj)):
        return None
    raise TypeError(f"Object of type {type(obj)} is not JSON serializable")


def clean_nan_for_json(data):
    """Replace NaN / Inf with null for standard JSON serialization."""
    if isinstance(data, dict):
        return {k: clean_nan_for_json(v) for k, v in data.items()}
    elif isinstance(data, list):
        return [clean_nan_for_json(v) for v in data]
    elif isinstance(data, float):
        if not np.isfinite(data):
            return None
        return float(data)
    elif isinstance(data, (np.floating, np.integer)):
        val = data.item()
        return None if (isinstance(val, float) and not np.isfinite(val)) else val
    elif isinstance(data, np.ndarray):
        return clean_nan_for_json(data.tolist())
    else:
        return data


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--file", type=Path, required=True)
    parser.add_argument("--sigmot", type=Path, default=None)
    parser.add_argument("--samples", type=int, default=30000)
    parser.add_argument("--out", type=Path, required=True)
    args = parser.parse_args()

    print(f"Loading PPG file: {args.file}")
    raw_sec, raw_val = load_ring_ppg(args.file)

    if args.samples and args.samples < len(raw_sec):
        print(f"Slicing first {args.samples} samples for parity test")
        raw_sec = raw_sec[:args.samples]
        raw_val = raw_val[:args.samples]

    sigmot_file = args.sigmot
    if not sigmot_file:
        sigmot_file = find_matching_sigmot_file(args.file)

    sig_sec, sig_val = None, None
    if sigmot_file and sigmot_file.exists():
        sig_data = load_sigmot_data(sigmot_file)
        if sig_data is not None:
            sig_sec, sig_val = sig_data

    target_fs = 50.0
    print("Running Python ppg_preprocess v3 pipeline...")
    res = ppg_pre.preprocess_ppg(
        raw_sec,
        raw_val,
        target_fs=target_fs,
        accel=sig_val,
        accel_seconds=sig_sec,
    )

    t0 = res.time[0]
    time_rel = res.time - t0

    print("Extracting global peaks and gapless segments via SessionData...")
    session = SessionData(args.file, target_fs=target_fs)
    session.res = res
    session.total_duration_s = float(res.time[-1] - res.time[0])
    session.raw_seconds = raw_sec
    session.raw_values = raw_val
    session._extract_global_peaks()
    session._generate_gapless_segments_from_pipeline()

    print(f"Detected {len(session.peaks_indices)} global beats.")

    print("Computing Time-Resolved HRV and APG Morphology...")
    hrv_res = compute_time_resolved_hrv(
        time_series=time_rel,
        signal_series=res.filtered,
        peaks_indices=session.peaks_indices,
        fs=target_fs,
        window_s=60.0,
        step_s=15.0,
        valid_mask=session.get_valid_mask(),
    )

    # Poincaré
    peak_times = time_rel[session.peaks_indices] if len(session.peaks_indices) > 0 else np.array([])
    rr_ms = np.diff(peak_times) * 1000.0 if len(peak_times) >= 2 else np.array([])
    poincare_res = compute_poincare_data(rr_ms, peak_times=peak_times)

    # Feature summary table
    summary_table = generate_feature_summary(hrv_res["metrics"])

    # Build windows JSON
    windows_out = []
    for w in res.windows:
        windows_out.append({
            "start_s": float(w.start_s),
            "end_s": float(w.end_s),
            "start_idx": int(w.start_idx),
            "end_idx": int(w.end_idx),
            "accepted": bool(w.accepted),
            "reason": str(w.reason) if w.reason else None,
            "hr_bpm": float(w.sqi.get("hr_bpm", np.nan)),
            "quality": float(w.sqi.get("quality", 0.0)),
            "periodicity": float(w.sqi.get("periodicity", 0.0)),
            "template_corr": float(w.sqi.get("template_corr", 0.0)),
            "harmonic_ratio": float(w.sqi.get("harmonic_ratio", 0.0)),
            "stationarity": float(w.sqi.get("stationarity", 0.0)),
            "rel_amplitude": float(w.sqi.get("rel_amplitude", 0.0)),
            "rr_smoothness": float(w.sqi.get("rr_smoothness", 0.0)),
            "asymmetry": float(w.sqi.get("asymmetry", 0.5)),
        })

    golden_data = {
        "sample_rate": float(target_fs),
        "total_duration_s": float(session.total_duration_s),
        "coverage_pct": float(res.coverage * 100.0),
        "time": time_rel.tolist(),
        "filtered": res.filtered.tolist(),
        "usable_mask": res.usable.tolist(),
        "pulse_mask": res.pulse.tolist(),
        "peaks_indices": session.peaks_indices.tolist(),
        "windows": windows_out,
        "hrv": hrv_res,
        "poincare": poincare_res,
        "summary": summary_table,
    }

    clean_golden = clean_nan_for_json(golden_data)

    args.out.parent.mkdir(parents=True, exist_ok=True)
    with open(args.out, "w", encoding="utf-8") as f:
        json.dump(clean_golden, f, indent=2)

    print(f"\nSuccessfully wrote Python golden data to: {args.out}")
    print(f"Total HRV metric keys: {len(hrv_res['metrics'])}")
    print(f"Total summary rows: {len(summary_table)}")


if __name__ == "__main__":
    main()
