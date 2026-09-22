//! Multi-domain Heart Rate Variability (HRV) and Autonomic Dynamics engine.
//! Computes 26 comprehensive Time, Frequency, Non-Linear, and Morphology metrics.

use std::collections::HashMap;
use std::f64::consts::PI;

use serde::{Deserialize, Serialize};

use crate::dsp::morphology::{extract_advanced_morphology, MorphologyMetrics};
use crate::dsp::resample::percentile;
use crate::dsp::sqi::welch_psd;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct HrvWindowMetrics {
    // Time Domain
    pub mean_nn: f64,
    pub sdnn: f64,
    pub rmssd: f64,
    pub pnn50: f64,
    pub pnn20: f64,
    pub cvnn: f64,
    pub mean_hr: f64,

    // Frequency Domain
    pub vlf: f64,
    pub lf: f64,
    pub hf: f64,
    pub lf_hf: f64,
    pub lfn: f64,
    pub hfn: f64,
    pub total_power: f64,

    // Non-Linear Domain
    pub sd1: f64,
    pub sd2: f64,
    pub sd1_sd2: f64,
    pub csi: f64,
    pub cvi: f64,
    pub samp_en: f64,

    // Morphology Domain
    pub morphology_quality: f64,
    pub apg_b_a_ratio: f64,
    pub apg_c_a_ratio: f64,
    pub apg_d_a_ratio: f64,
    pub apg_e_a_ratio: f64,
    pub morph_pulse_amp: f64,
    pub morph_sd_time_ratio: f64,
}

impl Default for HrvWindowMetrics {
    fn default() -> Self {
        Self {
            mean_nn: f64::NAN,
            sdnn: f64::NAN,
            rmssd: f64::NAN,
            pnn50: f64::NAN,
            pnn20: f64::NAN,
            cvnn: f64::NAN,
            mean_hr: f64::NAN,

            vlf: f64::NAN,
            lf: f64::NAN,
            hf: f64::NAN,
            lf_hf: f64::NAN,
            lfn: f64::NAN,
            hfn: f64::NAN,
            total_power: f64::NAN,

            sd1: f64::NAN,
            sd2: f64::NAN,
            sd1_sd2: f64::NAN,
            csi: f64::NAN,
            cvi: f64::NAN,
            samp_en: f64::NAN,

            morphology_quality: 0.0,
            apg_b_a_ratio: f64::NAN,
            apg_c_a_ratio: f64::NAN,
            apg_d_a_ratio: f64::NAN,
            apg_e_a_ratio: f64::NAN,
            morph_pulse_amp: f64::NAN,
            morph_sd_time_ratio: f64::NAN,
        }
    }
}

/// Filter physiological RR outliers (350ms to 1600ms, relative step <= 20%)
pub fn filter_rr_outliers(
    rr_intervals_ms: &[f64],
    min_ms: f64,
    max_ms: f64,
    relative_threshold: f64,
) -> Vec<f64> {
    if rr_intervals_ms.len() < 2 {
        return rr_intervals_ms.to_vec();
    }

    // 1. Absolute physiological limits
    let mut valid = Vec::new();
    for &rr in rr_intervals_ms {
        if rr >= min_ms && rr <= max_ms {
            valid.push(rr);
        }
    }
    if valid.len() < 2 {
        return valid;
    }

    // 2. Relative step threshold
    let mut out = Vec::with_capacity(valid.len());
    out.push(valid[0]);

    for i in 0..valid.len() - 1 {
        let diff = (valid[i + 1] - valid[i]).abs();
        if diff <= valid[i] * relative_threshold {
            out.push(valid[i + 1]);
        }
    }

    out
}

/// Sample Entropy (SampEn) computation matching compute_sample_entropy() in hrv_engine.py
pub fn compute_sample_entropy(data: &[f64], m: usize, r: f64) -> f64 {
    let n = data.len();
    if n < 10 {
        return f64::NAN;
    }

    let mean_val = data.iter().sum::<f64>() / (n as f64);
    let sd = (data.iter().map(|&v| (v - mean_val).powi(2)).sum::<f64>() / (n as f64)).sqrt();
    let r_tol = r * sd;
    if r_tol <= 1e-9 {
        return f64::NAN;
    }

    let count_matches = |m_len: usize| -> (usize, usize) {
        let n_patterns = n.saturating_sub(m_len) + 1;
        let mut matches = 0;
        let mut total_pairs = 0;

        for i in 0..n_patterns {
            for j in (i + 1)..n_patterns {
                let mut max_diff = 0.0f64;
                for k in 0..m_len {
                    let d = (data[i + k] - data[j + k]).abs();
                    if d > max_diff {
                        max_diff = d;
                    }
                }
                if max_diff <= r_tol {
                    matches += 1;
                }
                total_pairs += 1;
            }
        }
        (matches, total_pairs)
    };

    let (matches_m, pairs_m) = count_matches(m);
    let (matches_m1, pairs_m1) = count_matches(m + 1);

    if matches_m == 0 || matches_m1 == 0 || pairs_m == 0 || pairs_m1 == 0 {
        return f64::NAN;
    }

    let phi_m = (matches_m as f64) / (pairs_m as f64);
    let phi_m1 = (matches_m1 as f64) / (pairs_m1 as f64);

    if phi_m <= 0.0 || phi_m1 <= 0.0 {
        return f64::NAN;
    }

    -(phi_m1 / phi_m).ln()
}

/// Trapezoidal numerical integration matching numpy.trapezoid
pub fn trapz(y: &[f64], x: &[f64]) -> f64 {
    let n = y.len().min(x.len());
    if n < 2 {
        return 0.0;
    }
    let mut sum = 0.0;
    for i in 0..n - 1 {
        let dx = x[i + 1] - x[i];
        sum += 0.5 * (y[i] + y[i + 1]) * dx;
    }
    sum
}

/// Compute single window HRV metrics matching compute_hrv_window() in hrv_engine.py
pub fn compute_hrv_window(
    rr_ms: &[f64],
    signal_segment: Option<&[f64]>,
    peaks_segment: Option<&[usize]>,
    fs: f64,
) -> HrvWindowMetrics {
    let clean_rr = filter_rr_outliers(rr_ms, 350.0, 1600.0, 0.20);
    let n_beats = clean_rr.len();

    if n_beats < 4 {
        return HrvWindowMetrics::default();
    }

    // 1. Time Domain
    let mean_nn = clean_rr.iter().sum::<f64>() / (n_beats as f64);
    let var_nn = clean_rr
        .iter()
        .map(|&v| (v - mean_nn).powi(2))
        .sum::<f64>()
        / ((n_beats - 1) as f64);
    let sdnn = var_nn.sqrt();

    let mut diff_rr = Vec::with_capacity(n_beats - 1);
    for i in 0..n_beats - 1 {
        diff_rr.push(clean_rr[i + 1] - clean_rr[i]);
    }

    let rmssd = if !diff_rr.is_empty() {
        (diff_rr.iter().map(|&d| d * d).sum::<f64>() / (diff_rr.len() as f64)).sqrt()
    } else {
        0.0
    };

    let pnn50 = if !diff_rr.is_empty() {
        (diff_rr.iter().filter(|&&d| d.abs() > 50.0).count() as f64)
            / (diff_rr.len() as f64)
            * 100.0
    } else {
        0.0
    };

    let pnn20 = if !diff_rr.is_empty() {
        (diff_rr.iter().filter(|&&d| d.abs() > 20.0).count() as f64)
            / (diff_rr.len() as f64)
            * 100.0
    } else {
        0.0
    };

    let cvnn = if mean_nn > 0.0 { sdnn / mean_nn } else { 0.0 };
    let mean_hr = if mean_nn > 0.0 { 60000.0 / mean_nn } else { f64::NAN };

    // 2. Non-Linear Domain
    let (sd1, sd2, sd1_sd2, csi, cvi) = if diff_rr.len() >= 2 {
        let mut diff_xy = Vec::with_capacity(n_beats - 1);
        let mut sum_xy = Vec::with_capacity(n_beats - 1);
        for i in 0..n_beats - 1 {
            let x = clean_rr[i];
            let y = clean_rr[i + 1];
            diff_xy.push(y - x);
            sum_xy.push(y + x);
        }

        let m_diff = diff_xy.iter().sum::<f64>() / (diff_xy.len() as f64);
        let sd_diff = (diff_xy.iter().map(|&v| (v - m_diff).powi(2)).sum::<f64>()
            / ((diff_xy.len() - 1) as f64))
            .sqrt()
            / 2.0f64.sqrt();

        let m_sum = sum_xy.iter().sum::<f64>() / (sum_xy.len() as f64);
        let sd_sum = (sum_xy.iter().map(|&v| (v - m_sum).powi(2)).sum::<f64>()
            / ((sum_xy.len() - 1) as f64))
            .sqrt()
            / 2.0f64.sqrt();

        let ratio = sd_diff / sd_sum.max(1e-9);
        let csi_val = sd_sum / sd_diff.max(1e-9);
        let cvi_val = (16.0 * sd_diff * sd_sum).max(1e-9).log10();
        (sd_diff, sd_sum, ratio, csi_val, cvi_val)
    } else {
        (f64::NAN, f64::NAN, f64::NAN, f64::NAN, f64::NAN)
    };

    let samp_en = if n_beats >= 15 {
        compute_sample_entropy(&clean_rr, 2, 0.20)
    } else {
        f64::NAN
    };

    // 3. Frequency Domain (Welch PSD on 4Hz resampled tachogram)
    let mut vlf = f64::NAN;
    let mut lf = f64::NAN;
    let mut hf = f64::NAN;
    let mut lf_hf = f64::NAN;
    let mut lfn = f64::NAN;
    let mut hfn = f64::NAN;
    let mut total_power = f64::NAN;

    let mut t_rr = Vec::with_capacity(n_beats);
    let mut cum_t = 0.0;
    for &rr in &clean_rr {
        cum_t += rr / 1000.0;
        t_rr.push(cum_t);
    }

    if let (Some(&t_start), Some(&t_end)) = (t_rr.first(), t_rr.last()) {
        let total_time = t_end - t_start;
        if total_time >= 10.0 {
            let fs_tacho = 4.0;
            let dt_tacho = 1.0 / fs_tacho;
            let mut grid_t = Vec::new();
            let mut cur = t_start;
            while cur < t_end {
                grid_t.push(cur);
                cur += dt_tacho;
            }

            if grid_t.len() >= 32 {
                let rr_interp = crate::dsp::resample::interp_1d(&grid_t, &t_rr, &clean_rr);
                let m_interp = rr_interp.iter().sum::<f64>() / (rr_interp.len() as f64);
                let detrended: Vec<f64> = rr_interp.iter().map(|&v| v - m_interp).collect();

                let nperseg = detrended.len().min((64.0 * fs_tacho).round() as usize);
                let (freqs, psd) = welch_psd(&detrended, fs_tacho, nperseg);

                if !freqs.is_empty() {
                    let mut vlf_f = Vec::new();
                    let mut vlf_p = Vec::new();
                    let mut lf_f = Vec::new();
                    let mut lf_p = Vec::new();
                    let mut hf_f = Vec::new();
                    let mut hf_p = Vec::new();

                    for i in 0..freqs.len() {
                        let f = freqs[i];
                        let p = psd[i];
                        if f >= 0.0033 && f < 0.04 {
                            vlf_f.push(f);
                            vlf_p.push(p);
                        }
                        if f >= 0.04 && f < 0.15 {
                            lf_f.push(f);
                            lf_p.push(p);
                        }
                        if f >= 0.15 && f < 0.40 {
                            hf_f.push(f);
                            hf_p.push(p);
                        }
                    }

                    let vlf_val = trapz(&vlf_p, &vlf_f);
                    let lf_val = trapz(&lf_p, &lf_f);
                    let hf_val = trapz(&hf_p, &hf_f);
                    let tp = vlf_val + lf_val + hf_val;

                    vlf = vlf_val;
                    lf = lf_val;
                    hf = hf_val;
                    total_power = tp;
                    lf_hf = lf_val / hf_val.max(1e-9);
                    let denom = (lf_val + hf_val).max(1e-9);
                    lfn = (lf_val / denom) * 100.0;
                    hfn = (hf_val / denom) * 100.0;
                }
            }
        }
    }

    // 4. APG Morphology & MQI
    let morph = if let (Some(sig), Some(pks)) = (signal_segment, peaks_segment) {
        if pks.len() >= 2 {
            extract_advanced_morphology(sig, pks, fs)
        } else {
            MorphologyMetrics::default()
        }
    } else {
        MorphologyMetrics::default()
    };

    HrvWindowMetrics {
        mean_nn,
        sdnn,
        rmssd,
        pnn50,
        pnn20,
        cvnn,
        mean_hr,

        vlf,
        lf,
        hf,
        lf_hf,
        lfn,
        hfn,
        total_power,

        sd1,
        sd2,
        sd1_sd2,
        csi,
        cvi,
        samp_en,

        morphology_quality: morph.morphology_quality,
        apg_b_a_ratio: morph.apg_b_a_ratio,
        apg_c_a_ratio: morph.apg_c_a_ratio,
        apg_d_a_ratio: morph.apg_d_a_ratio,
        apg_e_a_ratio: morph.apg_e_a_ratio,
        morph_pulse_amp: morph.morph_pulse_amp,
        morph_sd_time_ratio: morph.morph_sd_time_ratio,
    }
}

/// Time-resolved HRV results container
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TimeResolvedHrvResult {
    pub timestamps: Vec<f64>,
    pub window_s: f64,
    pub step_s: f64,
    pub metrics: HashMap<String, Vec<f64>>,
}

/// Compute time-resolved HRV metrics across sliding windows matching compute_time_resolved_hrv()
pub fn compute_time_resolved_hrv(
    time_series: &[f64],
    signal_series: &[f64],
    peaks_indices: &[usize],
    fs: f64,
    window_s: f64,
    step_s: f64,
    valid_mask: Option<&[bool]>,
) -> TimeResolvedHrvResult {
    if time_series.is_empty() {
        return TimeResolvedHrvResult {
            timestamps: Vec::new(),
            window_s,
            step_s,
            metrics: HashMap::new(),
        };
    }

    let t0 = time_series[0];
    let t_end = *time_series.last().unwrap();
    let total_duration = t_end - t0;

    let (win_s, st_s) = if total_duration < window_s {
        (total_duration, total_duration)
    } else {
        (window_s, step_s)
    };

    let mut starts = Vec::new();
    let mut cur_s = t0;
    while cur_s <= t_end - win_s + 0.1 {
        starts.push(cur_s);
        cur_s += st_s;
    }
    if starts.is_empty() {
        starts.push(t0);
    }

    let mut timestamps = Vec::with_capacity(starts.len());
    let mut records = Vec::with_capacity(starts.len());

    for win_start in starts {
        let win_end = win_start + win_s;
        let mid_time = (win_start + win_end) / 2.0;

        // Check valid mask coverage
        let mut in_win_indices = Vec::new();
        let mut valid_count = 0;
        for i in 0..time_series.len() {
            let t = time_series[i];
            if t >= win_start && t < win_end {
                in_win_indices.push(i);
                if let Some(vm) = valid_mask {
                    if vm[i] {
                        valid_count += 1;
                    }
                }
            }
        }

        if let Some(_vm) = valid_mask {
            if in_win_indices.is_empty()
                || (valid_count as f64) / (in_win_indices.len() as f64) < 0.40
            {
                timestamps.push(mid_time - t0);
                records.push(HrvWindowMetrics::default());
                continue;
            }
        }

        let mut win_peak_times = Vec::new();
        let mut rel_peaks = Vec::new();
        let seg_start_idx = if !in_win_indices.is_empty() {
            in_win_indices[0]
        } else {
            0
        };

        for &p in peaks_indices {
            let pt = time_series[p];
            if pt >= win_start && pt < win_end {
                win_peak_times.push(pt);
                if p >= seg_start_idx {
                    rel_peaks.push(p - seg_start_idx);
                }
            }
        }

        let record = if win_peak_times.len() >= 3 && !in_win_indices.is_empty() {
            let mut rr_ms = Vec::with_capacity(win_peak_times.len() - 1);
            for i in 0..win_peak_times.len() - 1 {
                rr_ms.push((win_peak_times[i + 1] - win_peak_times[i]) * 1000.0);
            }
            let seg_end_idx = *in_win_indices.last().unwrap() + 1;
            let seg_sig = &signal_series[seg_start_idx..seg_end_idx];

            compute_hrv_window(&rr_ms, Some(seg_sig), Some(&rel_peaks), fs)
        } else {
            HrvWindowMetrics::default()
        };

        timestamps.push(mid_time - t0);
        records.push(record);
    }

    let mut metrics: HashMap<String, Vec<f64>> = HashMap::new();
    let keys = [
        "MeanNN",
        "SDNN",
        "RMSSD",
        "pNN50",
        "pNN20",
        "CVNN",
        "MeanHR",
        "VLF",
        "LF",
        "HF",
        "LF_HF",
        "LFn",
        "HFn",
        "Total_Power",
        "SD1",
        "SD2",
        "SD1_SD2",
        "CSI",
        "CVI",
        "SampEn",
        "Morphology_Quality",
        "APG_b_a_Ratio",
        "APG_c_a_Ratio",
        "APG_d_a_Ratio",
        "APG_e_a_Ratio",
        "Morph_Pulse_Amp",
        "Morph_SD_Time_Ratio",
    ];

    for &k in &keys {
        metrics.insert(k.to_string(), Vec::with_capacity(records.len()));
    }

    for r in &records {
        metrics.get_mut("MeanNN").unwrap().push(r.mean_nn);
        metrics.get_mut("SDNN").unwrap().push(r.sdnn);
        metrics.get_mut("RMSSD").unwrap().push(r.rmssd);
        metrics.get_mut("pNN50").unwrap().push(r.pnn50);
        metrics.get_mut("pNN20").unwrap().push(r.pnn20);
        metrics.get_mut("CVNN").unwrap().push(r.cvnn);
        metrics.get_mut("MeanHR").unwrap().push(r.mean_hr);

        metrics.get_mut("VLF").unwrap().push(r.vlf);
        metrics.get_mut("LF").unwrap().push(r.lf);
        metrics.get_mut("HF").unwrap().push(r.hf);
        metrics.get_mut("LF_HF").unwrap().push(r.lf_hf);
        metrics.get_mut("LFn").unwrap().push(r.lfn);
        metrics.get_mut("HFn").unwrap().push(r.hfn);
        metrics.get_mut("Total_Power").unwrap().push(r.total_power);

        metrics.get_mut("SD1").unwrap().push(r.sd1);
        metrics.get_mut("SD2").unwrap().push(r.sd2);
        metrics.get_mut("SD1_SD2").unwrap().push(r.sd1_sd2);
        metrics.get_mut("CSI").unwrap().push(r.csi);
        metrics.get_mut("CVI").unwrap().push(r.cvi);
        metrics.get_mut("SampEn").unwrap().push(r.samp_en);

        metrics.get_mut("Morphology_Quality").unwrap().push(r.morphology_quality);
        metrics.get_mut("APG_b_a_Ratio").unwrap().push(r.apg_b_a_ratio);
        metrics.get_mut("APG_c_a_Ratio").unwrap().push(r.apg_c_a_ratio);
        metrics.get_mut("APG_d_a_Ratio").unwrap().push(r.apg_d_a_ratio);
        metrics.get_mut("APG_e_a_Ratio").unwrap().push(r.apg_e_a_ratio);
        metrics.get_mut("Morph_Pulse_Amp").unwrap().push(r.morph_pulse_amp);
        metrics.get_mut("Morph_SD_Time_Ratio").unwrap().push(r.morph_sd_time_ratio);
    }

    TimeResolvedHrvResult {
        timestamps,
        window_s: win_s,
        step_s: st_s,
        metrics,
    }
}

/// Poincaré geometry and scatter points matching compute_poincare_data()
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PoincareData {
    pub x: Vec<f64>,
    pub y: Vec<f64>,
    pub timestamps: Vec<f64>,
    pub mean_rr: f64,
    pub sd1: f64,
    pub sd2: f64,
    pub ellipse_x: Vec<f64>,
    pub ellipse_y: Vec<f64>,
}

pub fn compute_poincare_data(rr_ms: &[f64], peak_times: Option<&[f64]>) -> PoincareData {
    let empty = PoincareData {
        x: Vec::new(),
        y: Vec::new(),
        timestamps: Vec::new(),
        mean_rr: 0.0,
        sd1: 0.0,
        sd2: 0.0,
        ellipse_x: Vec::new(),
        ellipse_y: Vec::new(),
    };

    if rr_ms.len() < 3 {
        return empty;
    }

    let t_rr: Vec<f64> = match peak_times {
        Some(pts) if pts.len() >= 2 => {
            if pts.len() == rr_ms.len() + 1 {
                pts[..rr_ms.len()].to_vec()
            } else {
                pts.to_vec()
            }
        }
        _ => vec![0.0; rr_ms.len()],
    };

    // 1. Absolute physiological limits (350ms to 1600ms)
    let mut valid_rr = Vec::new();
    let mut valid_t = Vec::new();
    for i in 0..rr_ms.len() {
        let r = rr_ms[i];
        if r >= 350.0 && r <= 1600.0 {
            valid_rr.push(r);
            if i < t_rr.len() {
                valid_t.push(t_rr[i]);
            } else {
                valid_t.push(0.0);
            }
        }
    }

    // Relative filter (25% jump)
    let mut clean_rr = Vec::new();
    let mut clean_t = Vec::new();
    if valid_rr.len() >= 2 {
        clean_rr.push(valid_rr[0]);
        clean_t.push(valid_t[0]);
        for i in 0..valid_rr.len() - 1 {
            let diff = (valid_rr[i + 1] - valid_rr[i]).abs();
            if diff <= valid_rr[i] * 0.25 {
                clean_rr.push(valid_rr[i + 1]);
                clean_t.push(valid_t[i + 1]);
            }
        }
    }

    if clean_rr.len() < 3 {
        return empty;
    }

    let n = clean_rr.len();
    let mut x = Vec::with_capacity(n - 1);
    let mut y = Vec::with_capacity(n - 1);
    let mut timestamps = Vec::with_capacity(n - 1);

    for i in 0..n - 1 {
        x.push(clean_rr[i]);
        y.push(clean_rr[i + 1]);
        timestamps.push((clean_t[i] * 1000.0).round() / 1000.0);
    }

    let mean_rr = clean_rr.iter().sum::<f64>() / (n as f64);

    let mut diff_xy = Vec::with_capacity(n - 1);
    let mut sum_xy = Vec::with_capacity(n - 1);
    for i in 0..n - 1 {
        diff_xy.push(y[i] - x[i]);
        sum_xy.push(y[i] + x[i]);
    }

    let m_diff = diff_xy.iter().sum::<f64>() / ((n - 1) as f64);
    let sd1 = (diff_xy.iter().map(|&v| (v - m_diff).powi(2)).sum::<f64>() / ((n - 2) as f64)).sqrt()
        / 2.0f64.sqrt();

    let m_sum = sum_xy.iter().sum::<f64>() / ((n - 1) as f64);
    let sd2 = (sum_xy.iter().map(|&v| (v - m_sum).powi(2)).sum::<f64>() / ((n - 2) as f64)).sqrt()
        / 2.0f64.sqrt();

    // 95% confidence ellipse geometry
    let a = 2.0 * sd2;
    let b = 2.0 * sd1;
    let rot_angle = PI / 4.0;
    let cos_rot = rot_angle.cos();
    let sin_rot = rot_angle.sin();

    let mut ellipse_x = Vec::with_capacity(100);
    let mut ellipse_y = Vec::with_capacity(100);

    for i in 0..100 {
        let theta = (i as f64) * 2.0 * PI / 99.0;
        let ct = theta.cos();
        let st = theta.sin();

        let x_rot = a * ct * cos_rot - b * st * sin_rot;
        let y_rot = a * ct * sin_rot + b * st * cos_rot;

        ellipse_x.push(x_rot + mean_rr);
        ellipse_y.push(y_rot + mean_rr);
    }

    PoincareData {
        x,
        y,
        timestamps,
        mean_rr,
        sd1,
        sd2,
        ellipse_x,
        ellipse_y,
    }
}

/// Comprehensive 26-feature statistical summary row
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct FeatureSummaryRow {
    pub domain: String,
    pub metric: String,
    pub mean: f64,
    pub sd: f64,
    pub median: f64,
    pub iqr: f64,
    pub min: f64,
    pub max: f64,
    pub count: usize,
}

pub fn generate_feature_summary(metrics: &HashMap<String, Vec<f64>>) -> Vec<FeatureSummaryRow> {
    let domain_map: HashMap<&'static str, &'static str> = [
        ("MeanHR", "Time"),
        ("MeanNN", "Time"),
        ("SDNN", "Time"),
        ("RMSSD", "Time"),
        ("pNN50", "Time"),
        ("pNN20", "Time"),
        ("CVNN", "Time"),
        ("VLF", "Frequency"),
        ("LF", "Frequency"),
        ("HF", "Frequency"),
        ("LF_HF", "Frequency"),
        ("LFn", "Frequency"),
        ("HFn", "Frequency"),
        ("Total_Power", "Frequency"),
        ("SD1", "Non-Linear"),
        ("SD2", "Non-Linear"),
        ("SD1_SD2", "Non-Linear"),
        ("CSI", "Non-Linear"),
        ("CVI", "Non-Linear"),
        ("SampEn", "Non-Linear"),
        ("Morphology_Quality", "Morphology"),
        ("APG_b_a_Ratio", "Morphology"),
        ("APG_c_a_Ratio", "Morphology"),
        ("APG_d_a_Ratio", "Morphology"),
        ("APG_e_a_Ratio", "Morphology"),
        ("Morph_Pulse_Amp", "Morphology"),
        ("Morph_SD_Time_Ratio", "Morphology"),
        ("Skin_Temperature", "Vitals & Activity"),
        ("Activity_Motion", "Vitals & Activity"),
    ]
    .iter()
    .cloned()
    .collect();

    let mut summary = Vec::new();

    for (k, vals) in metrics {
        let finite: Vec<f64> = vals.iter().cloned().filter(|v| v.is_finite()).collect();
        if finite.is_empty() {
            continue;
        }

        let n = finite.len();
        let mean = finite.iter().sum::<f64>() / (n as f64);
        let sd = if n > 1 {
            (finite.iter().map(|&v| (v - mean).powi(2)).sum::<f64>() / ((n - 1) as f64)).sqrt()
        } else {
            0.0
        };

        let med = crate::dsp::resample::median(&finite);
        let q25 = percentile(&finite, 25.0);
        let q75 = percentile(&finite, 75.0);
        let iqr = q75 - q25;

        let min_val = finite.iter().cloned().fold(f64::INFINITY, f64::min);
        let max_val = finite.iter().cloned().fold(f64::NEG_INFINITY, f64::max);

        let domain = domain_map.get(k.as_str()).unwrap_or(&"General").to_string();

        summary.push(FeatureSummaryRow {
            domain,
            metric: k.clone(),
            mean: (mean * 100.0).round() / 100.0,
            sd: (sd * 100.0).round() / 100.0,
            median: (med * 100.0).round() / 100.0,
            iqr: (iqr * 100.0).round() / 100.0,
            min: (min_val * 100.0).round() / 100.0,
            max: (max_val * 100.0).round() / 100.0,
            count: n,
        });
    }

    let order = |d: &str| match d {
        "Time" => 0,
        "Frequency" => 1,
        "Non-Linear" => 2,
        "Morphology" => 3,
        _ => 4,
    };

    summary.sort_by(|a, b| {
        let ord_a = order(&a.domain);
        let ord_b = order(&b.domain);
        if ord_a != ord_b {
            ord_a.cmp(&ord_b)
        } else {
            a.metric.cmp(&b.metric)
        }
    });

    summary
}
