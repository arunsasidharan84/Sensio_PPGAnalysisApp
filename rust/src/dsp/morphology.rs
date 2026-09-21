//! Advanced acceleration plethysmogram (APG = d^2(PPG)/dt^2) morphology extraction,
//! fiducial wave identification (a, b, c, d, e), and Morphology Quality Index (MQI).

use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MorphologyMetrics {
    pub apg_b_a_ratio: f64,
    pub apg_c_a_ratio: f64,
    pub apg_d_a_ratio: f64,
    pub apg_e_a_ratio: f64,
    pub morph_pulse_amp: f64,
    pub morph_sd_time_ratio: f64,
    pub morphology_quality: f64,
    pub valid_cycle_count: usize,
}

impl Default for MorphologyMetrics {
    fn default() -> Self {
        Self {
            apg_b_a_ratio: f64::NAN,
            apg_c_a_ratio: f64::NAN,
            apg_d_a_ratio: f64::NAN,
            apg_e_a_ratio: f64::NAN,
            morph_pulse_amp: f64::NAN,
            morph_sd_time_ratio: f64::NAN,
            morphology_quality: 0.0,
            valid_cycle_count: 0,
        }
    }
}

/// Savitzky-Golay 2nd derivative filter matching scipy.signal.savgol_filter(polyorder=3, deriv=2)
pub fn savgol_2nd_deriv(signal: &[f64], srate: f64, win_len: usize) -> Vec<f64> {
    let n = signal.len();
    if n < win_len || win_len < 5 {
        return vec![0.0; n];
    }

    let m = (win_len - 1) / 2;
    // Standard Savitzky-Golay 2nd derivative filter weights for polyorder=3
    // For win_len=9 (m=4): weights = [28, 7, -8, -17, -20, -17, -8, 7, 28] / 462 / dt^2
    // For win_len=7 (m=3): weights = [5, 0, -3, -4, -3, 0, 5] / 42 / dt^2
    // For win_len=5 (m=2): weights = [2, -1, -2, -1, 2] / 7 / dt^2
    let dt = 1.0 / srate;
    let dt2 = dt * dt;

    let (raw_weights, norm): (Vec<f64>, f64) = match win_len {
        9 => (
            vec![28.0, 7.0, -8.0, -17.0, -20.0, -17.0, -8.0, 7.0, 28.0],
            462.0 * dt2,
        ),
        7 => (
            vec![5.0, 0.0, -3.0, -4.0, -3.0, 0.0, 5.0],
            42.0 * dt2,
        ),
        _ => (
            vec![2.0, -1.0, -2.0, -1.0, 2.0],
            7.0 * dt2,
        ),
    };

    let weights: Vec<f64> = raw_weights.iter().map(|&w| w / norm).collect();

    let mut apg = vec![0.0; n];

    // Interior convolution
    for i in m..(n - m) {
        let mut sum = 0.0;
        for k in 0..win_len {
            sum += weights[k] * signal[i - m + k];
        }
        apg[i] = sum;
    }

    // Border extrapolation (nearest/linear extrapolation for boundaries)
    for i in 0..m {
        apg[i] = apg[m];
    }
    for i in (n - m)..n {
        apg[i] = apg[n - m - 1];
    }

    apg
}

fn nanmean(vals: &[f64]) -> f64 {
    let mut sum = 0.0;
    let mut count = 0;
    for &v in vals {
        if v.is_finite() {
            sum += v;
            count += 1;
        }
    }
    if count > 0 {
        sum / (count as f64)
    } else {
        f64::NAN
    }
}

/// Extract advanced APG morphology and Morphology Quality Index (MQI) matching hrv_engine.py
pub fn extract_advanced_morphology(
    signal: &[f64],
    peaks: &[usize],
    srate: f64,
) -> MorphologyMetrics {
    if peaks.len() < 2 || signal.len() < (srate * 2.0).round() as usize {
        return MorphologyMetrics::default();
    }

    let mut win_len = 9;
    if win_len >= signal.len() {
        win_len = 5.max(((signal.len() / 2) * 2).saturating_sub(1));
    }
    if win_len < 5 {
        return MorphologyMetrics::default();
    }

    let apg = savgol_2nd_deriv(signal, srate, win_len);

    // Find diastolic onsets (valleys before peaks)
    let mut onsets = Vec::with_capacity(peaks.len() - 1);
    for i in 0..peaks.len() - 1 {
        let p0 = peaks[i];
        let p1 = peaks[i + 1];
        if p1 > p0 {
            let win = &signal[p0..p1];
            let mut min_idx = 0;
            let mut min_val = win[0];
            for (k, &v) in win.iter().enumerate() {
                if v < min_val {
                    min_val = v;
                    min_idx = k;
                }
            }
            onsets.push(p0 + min_idx);
        } else {
            onsets.push(p0);
        }
    }

    if onsets.len() < 2 {
        return MorphologyMetrics::default();
    }

    let mut b_a = Vec::new();
    let mut c_a = Vec::new();
    let mut d_a = Vec::new();
    let mut e_a = Vec::new();
    let mut sd_r = Vec::new();
    let mut p_amps = Vec::new();
    let mut cycle_qualities = Vec::new();

    for i in 0..onsets.len() - 1 {
        let t_onset = onsets[i];
        let t_peak = if i + 1 < peaks.len() { peaks[i + 1] } else { onsets[i + 1] };
        let t_next_onset = onsets[i + 1];

        if !(t_onset < t_peak && t_peak < t_next_onset) {
            continue;
        }

        let cycle_len = t_next_onset - t_onset;
        if cycle_len < (0.3 * srate) as usize || cycle_len > (2.0 * srate) as usize {
            continue;
        }

        // Pulse amplitude
        let amp = signal[t_peak] - signal[t_onset];
        if amp <= 0.0 {
            continue;
        }
        p_amps.push(amp);

        // Systolic / Diastolic time ratio
        let sys_t = (t_peak - t_onset) as f64 / srate;
        let dia_t = (t_next_onset - t_peak) as f64 / srate;
        if sys_t > 0.0 && dia_t > 0.0 {
            sd_r.push(sys_t / dia_t);
        }

        // Look for APG waves:
        // a-wave: positive peak around systolic upstroke (between onset and peak)
        let a_window = &apg[t_onset..t_peak];
        if a_window.len() < 3 {
            cycle_qualities.push(0.0);
            continue;
        }

        let mut a_loc = 0;
        let mut a_val = a_window[0];
        for (k, &v) in a_window.iter().enumerate() {
            if v > a_val {
                a_val = v;
                a_loc = k;
            }
        }
        let a_idx = t_onset + a_loc;

        if a_val <= 1e-9 {
            cycle_qualities.push(0.0);
            continue;
        }

        let mut cycle_score: f64 = 0.25; // a-wave identified

        // b-wave: negative trough following a-wave within ~120 ms
        let b_max_len = ((0.18 * srate) as usize).min(t_peak - a_idx);
        let b_sub = &apg[a_idx..(a_idx + b_max_len)];
        let mut b_ratio_val = f64::NAN;

        if b_sub.len() >= 3 {
            let mut _b_loc = 0;
            let mut b_val = b_sub[0];
            for (k, &v) in b_sub.iter().enumerate() {
                if v < b_val {
                    b_val = v;
                    _b_loc = k;
                }
            }
            if b_val < 0.0 {
                b_ratio_val = b_val / a_val;
                b_a.push(b_ratio_val);
                cycle_score += 0.25; // b-wave identified
            }
        }

        // c & d waves: re-acceleration & notch trough between b-wave and dicrotic inflection
        let d_start = a_idx + (0.10 * srate) as usize;
        let d_end = t_next_onset.min(t_peak + (0.30 * srate) as usize);
        let mut d_idx_global = None;

        if d_end > d_start && (d_end - d_start) >= 3 {
            let d_sub = &apg[d_start..d_end];
            let half_len = 2.max(d_sub.len() / 2);

            // c-wave is intermediate peak
            let mut _c_loc = 0;
            let mut c_val = d_sub[0];
            for k in 0..half_len.min(d_sub.len()) {
                if d_sub[k] > c_val {
                    c_val = d_sub[k];
                    _c_loc = k;
                }
            }

            let check_idx = (a_idx + (0.05 * srate) as usize).min(signal.len() - 1);
            if c_val > 0.0 && (!b_ratio_val.is_finite() || c_val > apg[check_idx]) {
                c_a.push(c_val / a_val);
                cycle_score += 0.15;
            }

            // d-wave is trough
            let mut d_loc = 0;
            let mut d_val = d_sub[0];
            for (k, &v) in d_sub.iter().enumerate() {
                if v < d_val {
                    d_val = v;
                    d_loc = k;
                }
            }
            d_idx_global = Some(d_start + d_loc);

            if d_val < 0.0 {
                d_a.push(d_val / a_val);
                cycle_score += 0.20;
            }
        }

        // e-wave: positive diastolic peak following d-wave
        if let Some(d_idx) = d_idx_global {
            if d_idx < t_next_onset.saturating_sub(2) {
                let e_sub = &apg[d_idx..t_next_onset];
                if e_sub.len() >= 3 {
                    let mut e_val = e_sub[0];
                    for &v in e_sub {
                        if v > e_val {
                            e_val = v;
                        }
                    }
                    if e_val > 0.0 {
                        e_a.push(e_val / a_val);
                        cycle_score += 0.15;
                    }
                }
            }
        }

        cycle_qualities.push(cycle_score.min(1.0));
    }

    let mqi = if !cycle_qualities.is_empty() {
        cycle_qualities.iter().sum::<f64>() / (cycle_qualities.len() as f64)
    } else {
        0.0
    };

    MorphologyMetrics {
        apg_b_a_ratio: nanmean(&b_a),
        apg_c_a_ratio: nanmean(&c_a),
        apg_d_a_ratio: nanmean(&d_a),
        apg_e_a_ratio: nanmean(&e_a),
        morph_pulse_amp: nanmean(&p_amps),
        morph_sd_time_ratio: nanmean(&sd_r),
        morphology_quality: mqi,
        valid_cycle_count: p_amps.len(),
    }
}
