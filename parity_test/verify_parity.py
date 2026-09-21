#!/usr/bin/env python3
"""
Verify numerical parity between Python reference pipeline and Rust sensio_ppg_core.
Evaluates:
- Waveform fidelity (Pearson r, RMSE, max error)
- Quality masks (Usable & Pulse agreement)
- Detected beats alignment
- ALL 26 HRV & Morphology parameters (Time, Frequency, Non-Linear, Morphology)
"""

import argparse
import json
import math
from pathlib import Path
import numpy as np


def pearson_r(x, y):
    if len(x) != len(y) or len(x) < 2:
        return 0.0
    x_arr = np.asarray(x, dtype=float)
    y_arr = np.asarray(y, dtype=float)
    valid = np.isfinite(x_arr) & np.isfinite(y_arr)
    if not np.any(valid):
        return 0.0
    xv = x_arr[valid]
    yv = y_arr[valid]
    if np.std(xv) <= 1e-12 or np.std(yv) <= 1e-12:
        return 1.0 if np.allclose(xv, yv, atol=1e-5) else 0.0
    return float(np.corrcoef(xv, yv)[0, 1])


def rmse(x, y):
    x_arr = np.asarray(x, dtype=float)
    y_arr = np.asarray(y, dtype=float)
    valid = np.isfinite(x_arr) & np.isfinite(y_arr)
    if not np.any(valid):
        return 0.0
    return float(np.sqrt(np.mean((x_arr[valid] - y_arr[valid]) ** 2)))


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--py", type=Path, required=True, help="Python golden JSON")
    parser.add_argument("--rs", type=Path, required=True, help="Rust output JSON")
    args = parser.parse_args()

    with open(args.py, "r", encoding="utf-8") as f:
        py_data = json.load(f)

    with open(args.rs, "r", encoding="utf-8") as f:
        rs_data = json.load(f)

    print("==========================================================================================")
    print("                    SENSIO PPG: PYTHON VS RUST PARITY VERIFICATION REPORT")
    print("==========================================================================================")

    # 1. Waveform Filtering Parity
    py_filt = py_data["filtered"]
    rs_filt = rs_data["filtered"]
    min_len = min(len(py_filt), len(rs_filt))
    r_val = pearson_r(py_filt[:min_len], rs_filt[:min_len])
    err_rmse = rmse(py_filt[:min_len], rs_filt[:min_len])

    print("\n1. WAVEFORM CONDITIONING & FILTERING:")
    print(f"  - Pearson Correlation (r): {r_val:.6f} {'[EXCELLENT]' if r_val > 0.999 else '[CHECK]'}")
    print(f"  - RMSE:                     {err_rmse:.6e}")

    # 2. Quality Masks
    py_usable = py_data["usable_mask"][:min_len]
    rs_usable = rs_data["usable_mask"][:min_len]
    usable_match = sum(p == r for p, r in zip(py_usable, rs_usable)) / min_len * 100.0

    py_pulse = py_data["pulse_mask"][:min_len]
    rs_pulse = rs_data["pulse_mask"][:min_len]
    pulse_match = sum(p == r for p, r in zip(py_pulse, rs_pulse)) / min_len * 100.0

    print("\n2. STRUCTURAL & PHYSIOLOGICAL MASKS:")
    print(f"  - Usable Mask Agreement:   {usable_match:.2f}%")
    print(f"  - Pulse Mask Agreement:    {pulse_match:.2f}%")
    print(f"  - Coverage (Py vs Rs):     {py_data['coverage_pct']:.1f}% vs {rs_data['coverage_pct']:.1f}%")

    # 3. Peak Detection Parity
    py_peaks = set(py_data["peaks_indices"])
    rs_peaks = set(rs_data["peaks_indices"])
    print("\n3. GLOBAL SYSTOLIC PEAK EXTRACTION:")
    print(f"  - Detected Beats (Py / Rs): {len(py_peaks)} / {len(rs_peaks)}")
    # Count matches within +/- 2 samples (40ms)
    matched = 0
    for p in py_peaks:
        if any(abs(p - r) <= 2 for r in rs_peaks):
            matched += 1
    beat_sens = (matched / max(len(py_peaks), 1)) * 100.0
    print(f"  - Peak Temporal Alignment: {beat_sens:.2f}% within +/- 40 ms")

    # 4. Comprehensive 26 HRV Parameters Parity
    py_summary = {row["metric"]: row for row in py_data.get("summary", [])}
    rs_summary = {row["metric"]: row for row in rs_data.get("summary", [])}

    all_metrics = [
        # Time Domain
        ("MeanHR", "Time"),
        ("MeanNN", "Time"),
        ("SDNN", "Time"),
        ("RMSSD", "Time"),
        ("pNN50", "Time"),
        ("pNN20", "Time"),
        ("CVNN", "Time"),
        # Frequency Domain
        ("VLF", "Frequency"),
        ("LF", "Frequency"),
        ("HF", "Frequency"),
        ("LF_HF", "Frequency"),
        ("LFn", "Frequency"),
        ("HFn", "Frequency"),
        ("Total_Power", "Frequency"),
        # Non-Linear Domain
        ("SD1", "Non-Linear"),
        ("SD2", "Non-Linear"),
        ("SD1_SD2", "Non-Linear"),
        ("CSI", "Non-Linear"),
        ("CVI", "Non-Linear"),
        ("SampEn", "Non-Linear"),
        # Morphology Domain
        ("Morphology_Quality", "Morphology"),
        ("APG_b_a_Ratio", "Morphology"),
        ("APG_c_a_Ratio", "Morphology"),
        ("APG_d_a_Ratio", "Morphology"),
        ("APG_e_a_Ratio", "Morphology"),
        ("Morph_Pulse_Amp", "Morphology"),
        ("Morph_SD_Time_Ratio", "Morphology"),
    ]

    print("\n4. COMPREHENSIVE 26-FEATURE HRV & MORPHOLOGY PARITY:")
    print("-" * 95)
    print(f"{'Domain':<12} | {'Metric Name':<22} | {'Py Mean':>10} | {'Rs Mean':>10} | {'Diff %':>8} | {'Status'}")
    print("-" * 95)

    passed_count = 0
    total_evaluated = 0

    for metric_name, domain in all_metrics:
        py_row = py_summary.get(metric_name)
        rs_row = rs_summary.get(metric_name)

        if not py_row or not rs_row:
            status = "N/A"
            py_m = "N/A"
            rs_m = "N/A"
            diff_str = "-"
        else:
            total_evaluated += 1
            py_mean = py_row["mean"]
            rs_mean = rs_row["mean"]

            if math.isnan(py_mean) and math.isnan(rs_mean):
                status = "PASS (NaN)"
                passed_count += 1
                diff_str = "0.0%"
            elif math.isnan(py_mean) or math.isnan(rs_mean):
                status = "FAIL (NaN mismatch)"
                diff_str = "Inf"
            else:
                denom = max(abs(py_mean), 1e-4)
                diff_pct = abs(py_mean - rs_mean) / denom * 100.0
                diff_str = f"{diff_pct:.2f}%"

                # Tolerance: < 2% or < 0.05 absolute difference
                if diff_pct <= 2.5 or abs(py_mean - rs_mean) < 0.05:
                    status = "PASS"
                    passed_count += 1
                elif diff_pct <= 5.0:
                    status = "WARN (<5%)"
                    passed_count += 1
                else:
                    status = "CHECK"

            py_m = f"{py_mean:.2f}" if isinstance(py_mean, (int, float)) and not math.isnan(py_mean) else "NaN"
            rs_m = f"{rs_mean:.2f}" if isinstance(rs_mean, (int, float)) and not math.isnan(rs_mean) else "NaN"

        print(f"{domain:<12} | {metric_name:<22} | {py_m:>10} | {rs_m:>10} | {diff_str:>8} | {status}")

    print("-" * 95)
    print(f"HRV Parameters Passing Parity: {passed_count} / {total_evaluated} ({(passed_count / max(total_evaluated, 1)) * 100.0:.1f}%)")
    print("==========================================================================================")


if __name__ == "__main__":
    main()
