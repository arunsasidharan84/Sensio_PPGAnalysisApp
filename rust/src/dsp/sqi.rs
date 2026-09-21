//! Structural quality assessment, signal quality index (SQI) battery,
//! parabolic sub-bin peak refinement, and consensus heart rate estimation.

use std::f64::consts::PI;

use num_complex::Complex;
use rustfft::FftPlanner;
use serde::{Deserialize, Serialize};

use crate::dsp::resample::{median, percentile};

/// Return [start, end) index pairs for each contiguous true run
pub fn runs(mask: &[bool]) -> Vec<(usize, usize)> {
    let mut out = Vec::new();
    let n = mask.len();
    if n == 0 {
        return out;
    }

    let mut in_run = false;
    let mut start = 0;

    for i in 0..n {
        if mask[i] {
            if !in_run {
                in_run = true;
                start = i;
            }
        } else if in_run {
            in_run = false;
            out.push((start, i));
        }
    }

    if in_run {
        out.push((start, n));
    }

    out
}

/// 1D Binary dilation with footprint radius k (structure size 2*k + 1)
pub fn dilate(mask: &[bool], k: usize) -> Vec<bool> {
    let n = mask.len();
    if k == 0 || n == 0 {
        return mask.to_vec();
    }

    let mut out = vec![false; n];
    for i in 0..n {
        if mask[i] {
            let start = if i >= k { i - k } else { 0 };
            let end = (i + k + 1).min(n);
            for j in start..end {
                out[j] = true;
            }
        }
    }
    out
}

/// 1D Binary erosion with footprint radius k (structure size 2*k + 1)
pub fn erode(mask: &[bool], k: usize) -> Vec<bool> {
    let n = mask.len();
    if k == 0 || n == 0 {
        return mask.to_vec();
    }

    let mut out = vec![false; n];
    for i in 0..n {
        let start = if i >= k { i - k } else { 0 };
        let end = (i + k + 1).min(n);
        let mut all_true = true;
        if start > 0 || end < n {
            // border_value = 0 matching scipy.ndimage.binary_erosion
            if i < k || i + k >= n {
                all_true = false;
            }
        }
        if all_true {
            for j in start..end {
                if !mask[j] {
                    all_true = false;
                    break;
                }
            }
        }
        out[i] = all_true;
    }
    out
}

/// Uniform 1D moving average filter matching scipy.ndimage.uniform_filter1d(mode='nearest')
pub fn uniform_filter1d(x: &[f64], w: usize) -> Vec<f64> {
    let n = x.len();
    if n == 0 {
        return Vec::new();
    }
    let w = w.max(1);
    if w == 1 {
        return x.to_vec();
    }

    let mut out = vec![0.0; n];
    let half_left = w / 2;
    let half_right = w - 1 - half_left;

    let mut sum = 0.0;
    // Initial window [ -half_left, half_right ] with nearest boundary clamp
    for offset in 0..w {
        let idx = if offset < half_left {
            0
        } else {
            (offset - half_left).min(n - 1)
        };
        sum += x[idx];
    }
    out[0] = sum / (w as f64);

    for i in 1..n {
        // Remove item leaving the window
        let old_idx = if i - 1 < half_left {
            0
        } else {
            (i - 1 - half_left).min(n - 1)
        };
        // Add item entering the window
        let new_idx = (i + half_right).min(n - 1);

        sum += x[new_idx] - x[old_idx];
        out[i] = sum / (w as f64);
    }

    out
}

/// Rolling standard deviation using uniform filters
pub fn rolling_std(x: &[f64], w: usize) -> Vec<f64> {
    let w = w.max(3);
    let m = uniform_filter1d(x, w);

    let x2: Vec<f64> = x.iter().map(|&v| v * v).collect();
    let m2 = uniform_filter1d(&x2, w);

    let mut out = Vec::with_capacity(x.len());
    for i in 0..x.len() {
        let var = (m2[i] - m[i] * m[i]).max(0.0);
        out.push(var.sqrt());
    }
    out
}

/// Robust scale: 1.4826 * median(|x - median(x)|)
pub fn robust_scale(x: &[f64]) -> f64 {
    if x.len() < 2 {
        return 1.0;
    }
    let med = median(x);
    let abs_diff: Vec<f64> = x.iter().map(|&v| (v - med).abs()).collect();
    let scale = 1.4826 * median(&abs_diff);
    scale.max(1e-9)
}

/// Soft clamp ramp into [0.0, 1.0]
#[inline(always)]
pub fn ramp(v: f64, lo: f64, hi: f64) -> f64 {
    if !v.is_finite() {
        return 0.0;
    }
    if hi <= lo {
        return 0.0;
    }
    ((v - lo) / (hi - lo)).clamp(0.0, 1.0)
}

/// Robust peak-to-peak amplitude (95th - 5th percentile)
pub fn amplitude(x: &[f64]) -> f64 {
    if x.len() < 2 {
        return 0.0;
    }
    percentile(x, 95.0) - percentile(x, 5.0)
}

/// Parabolic sub-bin interpolation for peak localization
#[inline(always)]
pub fn parabolic_peak(y: &[f64], k: usize) -> f64 {
    if k == 0 || k >= y.len() - 1 {
        return k as f64;
    }
    let a = y[k - 1];
    let b = y[k];
    let c = y[k + 1];
    let denom = a - 2.0 * b + c;
    if denom.abs() < 1e-15 {
        return k as f64;
    }
    (k as f64) + 0.5 * (a - c) / denom
}

/// Flag saturation, stuck ADC flatlines, and step discontinuities matching flag_raw_defects()
pub fn flag_raw_defects(
    x: &[f64],
    fs: f64,
    valid: &[bool],
    guard_s: f64,
    adc_min: Option<f64>,
    adc_max: Option<f64>,
    step_k: f64,
    flat_window_s: f64,
) -> Vec<bool> {
    let n = x.len();
    let mut bad = vec![false; n];
    for i in 0..n {
        if !valid[i] {
            bad[i] = true;
        }
    }

    if let Some(min_val) = adc_min {
        for i in 0..n {
            if x[i] <= min_val {
                bad[i] = true;
            }
        }
    }

    if let Some(max_val) = adc_max {
        for i in 0..n {
            if x[i] >= max_val {
                bad[i] = true;
            }
        }
    }

    // Stuck ADC check via rolling std
    let w = 3.max((flat_window_s * fs).round() as usize);
    let rstd = rolling_std(x, w);

    let mut unique_vals = x.to_vec();
    unique_vals.sort_by(|a, b| a.partial_cmp(b).unwrap_or(std::cmp::Ordering::Equal));
    unique_vals.dedup_by(|a, b| (*a - *b).abs() < 1e-9);

    let lsb = if unique_vals.len() >= 2 {
        let mut diffs = Vec::with_capacity(unique_vals.len() - 1);
        for i in 0..unique_vals.len() - 1 {
            diffs.push(unique_vals[i + 1] - unique_vals[i]);
        }
        median(&diffs)
    } else {
        1.0
    };

    let flat_thresh = 0.5 * lsb;
    for i in 0..n {
        if rstd[i] < flat_thresh {
            bad[i] = true;
        }
    }

    // Step discontinuity check
    let mut d = vec![0.0; n];
    for i in 1..n {
        d[i] = x[i] - x[i - 1];
    }
    let s = robust_scale(&d);
    if s > 0.0 {
        let step_thresh = step_k * s;
        for i in 0..n {
            if d[i].abs() > step_thresh {
                bad[i] = true;
            }
        }
    }

    let guard_k = (guard_s * fs).round() as usize;
    dilate(&bad, guard_k)
}

/// Outlier check on filtered signal matching flag_filtered_outliers()
pub fn flag_filtered_outliers(
    y: &[f64],
    fs: f64,
    bad: &[bool],
    guard_s: f64,
    k: f64,
    local_s: f64,
) -> Vec<bool> {
    let n = y.len();
    let w = 64.max((local_s * fs).round() as usize);
    let local_med = uniform_filter1d(y, w);
    let local_sig = rolling_std(y, w);

    let mut clean_sigs = Vec::new();
    for i in 0..n {
        if !bad[i] {
            clean_sigs.push(local_sig[i]);
        }
    }
    let ref_val = if !clean_sigs.is_empty() {
        median(&clean_sigs)
    } else {
        1.0
    };

    let floor = 0.1 * ref_val.max(1e-12);
    let mut hit = vec![false; n];
    for i in 0..n {
        let sig = local_sig[i].max(floor);
        if (y[i] - local_med[i]).abs() > k * sig {
            hit[i] = true;
        }
    }

    let guard_k = (guard_s * fs).round() as usize;
    let dilated_hit = dilate(&hit, guard_k);

    let mut out = bad.to_vec();
    for i in 0..n {
        if dilated_hit[i] {
            out[i] = true;
        }
    }
    out
}

/// Find peaks with height and distance constraints (matching scipy.signal.find_peaks)
pub fn find_peaks(
    x: &[f64],
    height: Option<f64>,
    distance: Option<usize>,
    prominence: Option<f64>,
) -> Vec<usize> {
    let n = x.len();
    if n < 3 {
        return Vec::new();
    }

    let mut candidates = Vec::new();
    for i in 1..n - 1 {
        if x[i] > x[i - 1] && x[i] >= x[i + 1] {
            if let Some(h) = height {
                if x[i] < h {
                    continue;
                }
            }
            candidates.push(i);
        }
    }

    if let Some(prom) = prominence {
        candidates.retain(|&idx| {
            let p_val = x[idx];
            // Search left
            let mut left_min = p_val;
            for j in (0..idx).rev() {
                if x[j] < left_min {
                    left_min = x[j];
                }
                if x[j] > p_val {
                    break;
                }
            }
            // Search right
            let mut right_min = p_val;
            for j in (idx + 1)..n {
                if x[j] < right_min {
                    right_min = x[j];
                }
                if x[j] > p_val {
                    break;
                }
            }
            let base = left_min.max(right_min);
            (p_val - base) >= prom
        });
    }

    if let Some(dist) = distance {
        if dist > 1 && !candidates.is_empty() {
            // Sort by peak height descending to keep highest peaks
            let mut order: Vec<usize> = (0..candidates.len()).collect();
            order.sort_by(|&a, &b| {
                x[candidates[b]]
                    .partial_cmp(&x[candidates[a]])
                    .unwrap_or(std::cmp::Ordering::Equal)
            });

            let mut keep = vec![true; candidates.len()];
            for i in 0..order.len() {
                let idx_i = order[i];
                if !keep[idx_i] {
                    continue;
                }
                let pos_i = candidates[idx_i];
                for j in (i + 1)..order.len() {
                    let idx_j = order[j];
                    if !keep[idx_j] {
                        continue;
                    }
                    let pos_j = candidates[idx_j];
                    if (pos_i as isize - pos_j as isize).unsigned_abs() < dist {
                        keep[idx_j] = false;
                    }
                }
            }

            candidates = candidates
                .into_iter()
                .enumerate()
                .filter(|(idx, _)| keep[*idx])
                .map(|(_, pos)| pos)
                .collect();
            candidates.sort();
        }
    }

    candidates
}

/// Unbiased autocorrelation with parabolic sub-bin refinement matching autocorr_hr()
pub fn autocorr_hr(x: &[f64], fs: f64, min_bpm: f64, max_bpm: f64) -> (f64, f64) {
    let n = x.len();
    if n < 16 {
        return (0.0, f64::NAN);
    }

    let mean_val = x.iter().sum::<f64>() / (n as f64);
    let mut std_acc = 0.0;
    for &val in x {
        let diff = val - mean_val;
        std_acc += diff * diff;
    }
    let sd = (std_acc / (n as f64)).sqrt();
    if sd <= 1e-12 {
        return (0.0, f64::NAN);
    }

    // FFT length: next power of 2 >= 2 * n
    let nfft = (2 * n).next_power_of_two();
    let mut planner = FftPlanner::new();
    let fft = planner.plan_fft_forward(nfft);

    let mut buf: Vec<Complex<f64>> = Vec::with_capacity(nfft);
    for &val in x {
        buf.push(Complex::new(val - mean_val, 0.0));
    }
    buf.resize(nfft, Complex::new(0.0, 0.0));

    fft.process(&mut buf);

    for c in &mut buf {
        let power = c.norm_sqr();
        *c = Complex::new(power, 0.0);
    }

    let ifft = planner.plan_fft_inverse(nfft);
    ifft.process(&mut buf);

    let mut ac = vec![0.0; n];
    let inv_nfft = 1.0 / (nfft as f64);
    for i in 0..n {
        let denom = (n - i).max(1) as f64;
        ac[i] = (buf[i].re * inv_nfft) / denom;
    }

    if ac[0] <= 0.0 {
        return (0.0, f64::NAN);
    }

    let ac0 = ac[0];
    for v in &mut ac {
        *v /= ac0;
    }

    let lo = 1.max((fs * 60.0 / max_bpm).round() as usize);
    let hi = (n - 2).min((fs * 60.0 / min_bpm).round() as usize);
    if hi <= lo {
        return (0.0, f64::NAN);
    }

    let min_lag_sep = 5.max((0.35 * fs).round() as usize);
    let cand_peaks = find_peaks(&ac[lo..=hi], Some(0.20), Some(min_lag_sep), None);

    if cand_peaks.is_empty() {
        let mut best_k = lo;
        let mut best_val = ac[lo];
        for k in lo..=hi {
            if ac[k] > best_val {
                best_val = ac[k];
                best_k = k;
            }
        }
        let lag = parabolic_peak(&ac, best_k);
        let bpm = 60.0 * fs / lag.max(1e-9);
        return (ac[best_k].clamp(0.0, 1.0), bpm);
    }

    let cand_lags: Vec<usize> = cand_peaks.iter().map(|&p| p + lo).collect();
    let max_h = cand_lags
        .iter()
        .map(|&l| ac[l])
        .fold(f64::NEG_INFINITY, f64::max);

    // Fundamental heartbeat preference: pick shortest lag if peak >= 68% max peak
    let mut chosen_k = cand_lags[0];
    for &lag_idx in &cand_lags {
        if ac[lag_idx] >= 0.68 * max_h {
            chosen_k = lag_idx;
            break;
        }
    }

    let lag = parabolic_peak(&ac, chosen_k);
    let bpm = 60.0 * fs / lag.max(1e-9);
    (ac[chosen_k].clamp(0.0, 1.0), bpm)
}

/// Compute Welch PSD with Hann window and 50% overlap
pub fn welch_psd(x: &[f64], fs: f64, nperseg: usize) -> (Vec<f64>, Vec<f64>) {
    let n = x.len();
    let nper = nperseg.min(n).max(8);
    let noverlap = nper / 2;
    let step = nper - noverlap;

    // Hann window
    let mut win = Vec::with_capacity(nper);
    let mut win_ss = 0.0;
    for i in 0..nper {
        let w = 0.5 * (1.0 - (2.0 * PI * (i as f64) / (nper as f64)).cos());
        win.push(w);
        win_ss += w * w;
    }

    let mut planner = FftPlanner::new();
    let fft = planner.plan_fft_forward(nper);

    let n_out = nper / 2 + 1;
    let mut psd_sum = vec![0.0; n_out];
    let mut n_chunks = 0;

    let mut s = 0;
    while s + nper <= n {
        let mut buf: Vec<Complex<f64>> = Vec::with_capacity(nper);
        // Remove segment mean
        let seg_mean = x[s..s + nper].iter().sum::<f64>() / (nper as f64);
        for i in 0..nper {
            buf.push(Complex::new((x[s + i] - seg_mean) * win[i], 0.0));
        }

        fft.process(&mut buf);

        // One-sided spectrum
        for k in 0..n_out {
            let p = buf[k].norm_sqr();
            let factor = if k == 0 || k == nper / 2 { 1.0 } else { 2.0 };
            psd_sum[k] += factor * p / (fs * win_ss);
        }
        n_chunks += 1;
        s += step;
    }

    if n_chunks == 0 {
        return (Vec::new(), Vec::new());
    }

    let df = fs / (nper as f64);
    let freqs: Vec<f64> = (0..n_out).map(|k| (k as f64) * df).collect();
    let psd: Vec<f64> = psd_sum.iter().map(|&v| v / (n_chunks as f64)).collect();

    (freqs, psd)
}

/// Dominant spectral frequency with parabolic sub-bin refinement matching spectral_hr()
pub fn spectral_hr(x: &[f64], fs: f64, fmin: f64, fmax: f64) -> f64 {
    let nper = x.len().min(256.max((16.0 * fs).round() as usize));
    let (freqs, psd) = welch_psd(x, fs, nper);
    if freqs.is_empty() {
        return f64::NAN;
    }

    let mut band_indices = Vec::new();
    for i in 0..freqs.len() {
        if freqs[i] >= fmin && freqs[i] <= fmax {
            band_indices.push(i);
        }
    }
    if band_indices.len() < 3 {
        return f64::NAN;
    }

    let mut best_k = band_indices[0];
    let mut best_p = psd[best_k];
    for &k in &band_indices {
        if psd[k] > best_p {
            best_p = psd[k];
            best_k = k;
        }
    }

    let df = freqs[1] - freqs[0];
    let peak_bin = parabolic_peak(&psd, best_k);
    60.0 * peak_bin * df
}

/// Detect beats matching detect_beats() with physiological refractory and dicrotic suppression
pub fn detect_beats(x: &[f64], fs: f64, hr_hint: f64) -> Vec<usize> {
    let n = x.len();
    if n < 4 {
        return Vec::new();
    }

    let mean_val = x.iter().sum::<f64>() / (n as f64);
    let sd = (x.iter().map(|&v| (v - mean_val).powi(2)).sum::<f64>() / (n as f64)).sqrt();
    if sd <= 1e-12 {
        return Vec::new();
    }

    let rr_expect = if hr_hint.is_finite() && hr_hint > 0.0 {
        60.0 / hr_hint
    } else {
        1.0
    };

    let min_dist = ((0.36 * fs).round() as usize).max((0.55 * rr_expect * fs).round() as usize);
    let raw_peaks = find_peaks(x, None, Some(min_dist), Some(0.32 * sd));
    if raw_peaks.len() < 2 {
        return raw_peaks;
    }

    // 1st derivative (central differences)
    let mut dx = vec![0.0; n];
    if n >= 2 {
        dx[0] = x[1] - x[0];
        for i in 1..n - 1 {
            dx[i] = 0.5 * (x[i + 1] - x[i - 1]);
        }
        dx[n - 1] = x[n - 1] - x[n - 2];
    }

    let mut pruned = Vec::new();
    let lookback = (0.12 * fs).round() as usize;

    for &p in &raw_peaks {
        if pruned.is_empty() {
            pruned.push(p);
        } else {
            let prev = *pruned.last().unwrap();
            let dt = (p as f64 - prev as f64) / fs;
            if dt < 0.55 * rr_expect {
                let s_curr = if p >= lookback { p - lookback } else { 0 };
                let up_curr = dx[s_curr..=p]
                    .iter()
                    .cloned()
                    .fold(f64::NEG_INFINITY, f64::max);

                let s_prev = if prev >= lookback { prev - lookback } else { 0 };
                let up_prev = dx[s_prev..=prev]
                    .iter()
                    .cloned()
                    .fold(f64::NEG_INFINITY, f64::max);

                if up_curr > up_prev || (up_curr >= 0.8 * up_prev && x[p] > x[prev]) {
                    *pruned.last_mut().unwrap() = p;
                }
            } else {
                pruned.push(p);
            }
        }
    }

    pruned
}

/// Octave relationship between two HR estimates
pub fn octave_relation(a: f64, b: f64, tol: f64) -> &'static str {
    if !a.is_finite() || !b.is_finite() || a <= 0.0 || b <= 0.0 {
        return "unknown";
    }
    let r = a / b;
    if (r - 1.0).abs() <= tol {
        return "agree";
    }
    let mut rr = r;
    let mut n = 0;
    while rr > 1.0 + tol && n < 3 {
        rr /= 2.0;
        n += 1;
    }
    while rr < 1.0 / (1.0 + tol) && n < 3 {
        rr *= 2.0;
        n += 1;
    }
    if (rr - 1.0).abs() <= tol {
        "octave"
    } else {
        "disagree"
    }
}

/// RR smoothness: fraction of consecutive RR intervals changing <= max_step
pub fn rr_smoothness(rr: &[f64], max_step: f64) -> f64 {
    if rr.len() < 3 {
        return 0.0;
    }
    let mut smooth_count = 0;
    for i in 0..rr.len() - 1 {
        let step = (rr[i + 1] - rr[i]).abs() / rr[i].max(1e-9);
        if step <= max_step {
            smooth_count += 1;
        }
    }
    (smooth_count as f64) / ((rr.len() - 1) as f64)
}

/// Consensus HR results
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ConsensusHr {
    pub periodicity: f64,
    pub ac_bpm: f64,
    pub spectral_bpm: f64,
    pub beat_bpm: f64,
    pub hr_bpm: f64,
    pub n_beats: usize,
    pub rr_cv: f64,
    pub rr_smoothness: f64,
    pub hr_status: String,
}

pub fn consensus_hr(x: &[f64], fs: f64, min_bpm: f64, max_bpm: f64) -> ConsensusHr {
    let (periodicity, ac_bpm) = autocorr_hr(x, fs, min_bpm, max_bpm);
    let spectral_bpm = spectral_hr(x, fs, min_bpm / 60.0, max_bpm / 60.0);

    let peaks = detect_beats(x, fs, ac_bpm);
    let n_beats = peaks.len();

    if n_beats < 4 {
        return ConsensusHr {
            periodicity,
            ac_bpm,
            spectral_bpm,
            beat_bpm: f64::NAN,
            hr_bpm: ac_bpm,
            n_beats,
            rr_cv: f64::NAN,
            rr_smoothness: 0.0,
            hr_status: "too_few_beats".to_string(),
        };
    }

    let mut rr = Vec::with_capacity(n_beats - 1);
    for i in 0..n_beats - 1 {
        rr.push((peaks[i + 1] - peaks[i]) as f64 / fs);
    }
    let med_rr = median(&rr);
    let beat_bpm = 60.0 / med_rr.max(1e-9);

    let mean_rr = rr.iter().sum::<f64>() / (rr.len() as f64);
    let rr_std = (rr.iter().map(|&v| (v - mean_rr).powi(2)).sum::<f64>() / (rr.len() as f64)).sqrt();
    let rr_cv = rr_std / mean_rr.max(1e-9);
    let smoothness = rr_smoothness(&rr, 0.25);

    let rel = octave_relation(beat_bpm, ac_bpm, 0.18);
    let (hr_bpm, hr_status) = if rel == "agree" {
        (0.5 * (beat_bpm + ac_bpm), "agree".to_string())
    } else if rel == "octave" {
        if (beat_bpm / ac_bpm - 2.0).abs() < 0.25 {
            (ac_bpm, "octave_resolved_dicrotic".to_string())
        } else {
            (beat_bpm, "octave_resolved_subharmonic".to_string())
        }
    } else if periodicity >= 0.40 && ac_bpm.is_finite() && ac_bpm >= 35.0 && ac_bpm <= 180.0 {
        (ac_bpm, "resolved_by_autocorr".to_string())
    } else {
        (beat_bpm, "disagree".to_string())
    };

    ConsensusHr {
        periodicity,
        ac_bpm,
        spectral_bpm,
        beat_bpm,
        hr_bpm,
        n_beats,
        rr_cv,
        rr_smoothness: smoothness,
        hr_status,
    }
}

/// Adaptive spectral SQI: harmonic energy concentration
pub fn adaptive_spectral_sqi(x: &[f64], fs: f64, hr_hint: f64, fmax: f64) -> (f64, f64) {
    let nper = x.len().min(128.max((8.0 * fs).round() as usize));
    let (freqs, psd) = welch_psd(x, fs, nper);
    if freqs.is_empty() {
        return (0.0, f64::NAN);
    }

    let mut total_power = 0.0;
    let mut band_max_p = 0.0;
    let mut f_spec = f64::NAN;

    for i in 0..freqs.len() {
        let f = freqs[i];
        if f >= 0.3 && f <= fmax {
            total_power += psd[i];
        }
        if f >= 0.5 && f <= 3.5 {
            if psd[i] > band_max_p {
                band_max_p = psd[i];
                f_spec = f;
            }
        }
    }

    let f0 = if hr_hint.is_finite() && hr_hint > 0.0 {
        hr_hint / 60.0
    } else {
        f_spec
    };

    let mut harm = 0.0;
    if f0.is_finite() && f0 > 0.0 && total_power > 0.0 {
        for h in [1.0, 2.0, 3.0] {
            let fc = h * f0;
            if fc > fmax {
                break;
            }
            let bw = 0.10f64.max(0.12 * fc);
            for i in 0..freqs.len() {
                let f = freqs[i];
                if f >= fc - bw && f <= fc + bw {
                    harm += psd[i];
                }
            }
        }
        harm /= total_power;
    }

    let spec_bpm = if f_spec.is_finite() {
        60.0 * f_spec
    } else {
        f64::NAN
    };
    (harm, spec_bpm)
}

/// Beat template correlation SQI
pub fn beat_sqi(x: &[f64], fs: f64, hr_hint: f64) -> f64 {
    let n = x.len();
    if n < (3.0 * fs).round() as usize {
        return 0.0;
    }

    let rr_expect = if hr_hint.is_finite() && hr_hint > 0.0 {
        60.0 / hr_hint
    } else {
        1.0
    };

    let peaks = detect_beats(x, fs, hr_hint);
    if peaks.len() < 4 {
        return 0.0;
    }

    let pre = (0.30 * rr_expect * fs).round() as usize;
    let post = (0.55 * rr_expect * fs).round() as usize;
    let beat_len = pre + post;

    let mut beats = Vec::new();
    for &p in &peaks {
        if p >= pre && p + post <= n {
            beats.push(&x[(p - pre)..(p + post)]);
        }
    }

    if beats.len() < 3 {
        return 0.0;
    }

    // Standardize each beat: (beat - mean) / std
    let mut standardized = Vec::new();
    for b in beats {
        let b_mean = b.iter().sum::<f64>() / (beat_len as f64);
        let b_std = (b.iter().map(|&v| (v - b_mean).powi(2)).sum::<f64>() / (beat_len as f64)).sqrt();
        if b_std > 1e-9 {
            let norm: Vec<f64> = b.iter().map(|&v| (v - b_mean) / b_std).collect();
            standardized.push(norm);
        }
    }

    if standardized.is_empty() {
        return 0.0;
    }

    // Average template
    let num_beats = standardized.len();
    let mut tmpl = vec![0.0; beat_len];
    for b in &standardized {
        for i in 0..beat_len {
            tmpl[i] += b[i];
        }
    }
    for v in &mut tmpl {
        *v /= num_beats as f64;
    }

    let tmpl_mean = tmpl.iter().sum::<f64>() / (beat_len as f64);
    let tmpl_std = (tmpl.iter().map(|&v| (v - tmpl_mean).powi(2)).sum::<f64>() / (beat_len as f64)).sqrt();
    if tmpl_std <= 1e-9 {
        return 0.0;
    }
    for v in &mut tmpl {
        *v = (*v - tmpl_mean) / tmpl_std;
    }

    // Correlation of each beat with template
    let mut total_corr = 0.0;
    for b in &standardized {
        let dot: f64 = b.iter().zip(&tmpl).map(|(a, b)| a * b).sum();
        total_corr += dot / (beat_len as f64);
    }
    (total_corr / (num_beats as f64)).clamp(0.0, 1.0)
}

/// Physiological pulse asymmetry SQI (T_down / T_up ratio)
pub fn pulse_asymmetry_sqi(x: &[f64], fs: f64, hr_hint: f64) -> f64 {
    let n = x.len();
    let mean_val = x.iter().sum::<f64>() / (n as f64);
    let sd = (x.iter().map(|&v| (v - mean_val).powi(2)).sum::<f64>() / (n as f64)).sqrt().max(1.0);

    let rr_expect = if hr_hint.is_finite() && hr_hint > 0.0 {
        60.0 / hr_hint
    } else {
        1.0
    };
    let min_dist = ((0.36 * fs).round() as usize).max((0.55 * rr_expect * fs).round() as usize);

    let peaks = find_peaks(x, None, Some(min_dist), Some(0.30 * sd));

    let neg_x: Vec<f64> = x.iter().map(|&v| -v).collect();
    let valleys = find_peaks(&neg_x, None, Some(min_dist), None);

    if peaks.len() < 2 || valleys.len() < 2 {
        return 0.5;
    }

    let mut ratios = Vec::new();
    for &p in &peaks {
        let v_pre = valleys.iter().filter(|&&v| v < p).cloned().last();
        let v_post = valleys.iter().find(|&&v| v > p).cloned();

        if let (Some(vp), Some(vn)) = (v_pre, v_post) {
            let t_up = (p - vp) as f64 / fs;
            let t_down = (vn - p) as f64 / fs;
            if t_up > 0.04 && t_down > 0.04 {
                ratios.push((t_down / t_up).max(t_up / t_down));
            }
        }
    }

    if ratios.is_empty() {
        return 0.5;
    }
    let med_ratio = median(&ratios);
    ((med_ratio - 1.0) / 0.5).clamp(0.0, 1.0)
}

/// Amplitude stationarity: min/max amplitude across sub-windows
pub fn amplitude_stationarity(x: &[f64], n_parts: usize) -> f64 {
    let n = x.len();
    if n < n_parts * 4 {
        return 0.0;
    }
    let chunk_size = n / n_parts;
    let mut amps = Vec::new();

    for i in 0..n_parts {
        let start = i * chunk_size;
        let end = if i == n_parts - 1 { n } else { (i + 1) * chunk_size };
        let part = &x[start..end];
        if part.len() > 4 {
            amps.push(amplitude(part));
        }
    }

    if amps.len() < 2 {
        return 0.0;
    }
    let max_amp = amps.iter().cloned().fold(f64::NEG_INFINITY, f64::max);
    let min_amp = amps.iter().cloned().fold(f64::INFINITY, f64::min);
    if max_amp <= 0.0 {
        return 0.0;
    }
    (min_amp / max_amp).clamp(0.0, 1.0)
}

/// Skewness and kurtosis
pub fn skew_kurtosis(x: &[f64]) -> (f64, f64) {
    let n = x.len();
    if n < 4 {
        return (0.0, 0.0);
    }
    let mean_val = x.iter().sum::<f64>() / (n as f64);
    let mut m2 = 0.0;
    let mut m3 = 0.0;
    let mut m4 = 0.0;
    for &v in x {
        let diff = v - mean_val;
        let d2 = diff * diff;
        m2 += d2;
        m3 += d2 * diff;
        m4 += d2 * d2;
    }
    m2 /= n as f64;
    m3 /= n as f64;
    m4 /= n as f64;

    let s = m2.sqrt();
    let skew = if s > 1e-12 { m3 / (s * s * s) } else { 0.0 };
    let kurt = if m2 > 1e-12 { m4 / (m2 * m2) - 3.0 } else { 0.0 };
    (skew, kurt)
}

/// Window SQI Metrics container
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct WindowSqi {
    pub hr_bpm: f64,
    pub periodicity: f64,
    pub template_corr: f64,
    pub harmonic_ratio: f64,
    pub stationarity: f64,
    pub rel_amplitude: f64,
    pub rr_smoothness: f64,
    pub asymmetry: f64,
    pub quality: f64,
    pub skew: f64,
    pub kurtosis: f64,
    pub motion_std: Option<f64>,
    pub n_beats: usize,
    pub hr_status: String,
}

/// Score a 12s window matching score_window() in ppg_preprocess.py
pub fn score_window(
    seg: &[f64],
    _seg_raw: &[f64],
    fs: f64,
    amp_reference: f64,
    motion: Option<f64>,
) -> WindowSqi {
    let c_res = consensus_hr(seg, fs, 30.0, 200.0);
    let (harm, _spec_bpm) = adaptive_spectral_sqi(seg, fs, c_res.ac_bpm, 8.0);
    let template_corr = beat_sqi(seg, fs, c_res.ac_bpm);
    let (skew, kurt) = skew_kurtosis(seg);
    let stationarity = amplitude_stationarity(seg, 4);
    let asymmetry = pulse_asymmetry_sqi(seg, fs, c_res.ac_bpm);

    let ac_amp = amplitude(seg);
    let rel_amplitude = ac_amp / amp_reference.max(1e-12);

    let quality = 0.25 * ramp(c_res.periodicity, 0.30, 0.75)
        + 0.20 * ramp(template_corr, 0.60, 0.85)
        + 0.15 * ramp(harm, 0.25, 0.55)
        + 0.10 * ramp(stationarity, 0.30, 0.60)
        + 0.10 * ramp(rel_amplitude, 0.15, 0.50)
        + 0.10 * ramp(c_res.rr_smoothness, 0.50, 0.85)
        + 0.10 * ramp(asymmetry, 0.20, 0.80);

    WindowSqi {
        hr_bpm: c_res.hr_bpm,
        periodicity: c_res.periodicity,
        template_corr,
        harmonic_ratio: harm,
        stationarity,
        rel_amplitude,
        rr_smoothness: c_res.rr_smoothness,
        asymmetry,
        quality,
        skew,
        kurtosis: kurt,
        motion_std: motion,
        n_beats: c_res.n_beats,
        hr_status: c_res.hr_status,
    }
}

/// Hard rejections veto matching veto() in ppg_preprocess.py
pub fn veto(
    sqi: &WindowSqi,
    min_bpm: f64,
    max_bpm: f64,
    min_rr_smoothness: f64,
    min_rel_amplitude: f64,
    motion_thresh: Option<f64>,
) -> Option<&'static str> {
    if sqi.n_beats < 4 {
        return Some("too_few_beats");
    }
    if !sqi.hr_bpm.is_finite() {
        return Some("no_hr");
    }
    if sqi.hr_bpm < min_bpm || sqi.hr_bpm > max_bpm {
        return Some("hr_out_of_range");
    }

    let motion_val = sqi.motion_std.unwrap_or(0.0);
    if sqi.asymmetry < 0.12 && sqi.skew < -0.10 && motion_val > 1.5 {
        return Some("symmetric_motion_noise");
    }

    let is_quiet_signal = match motion_thresh {
        Some(th) => motion_val <= 2.0 && motion_val <= th,
        None => true,
    };
    let high_periodicity = sqi.periodicity >= 0.40;
    let high_template = sqi.template_corr >= 0.70;

    if sqi.hr_status == "disagree" {
        if !(is_quiet_signal && (high_periodicity || high_template)) {
            return Some("hr_estimators_disagree");
        }
    }

    if sqi.rr_smoothness < min_rr_smoothness {
        if !(is_quiet_signal && (high_periodicity || high_template) && sqi.rr_smoothness >= 0.25) {
            return Some("rr_series_erratic");
        }
    }

    if sqi.rel_amplitude < min_rel_amplitude {
        return Some("no_perfusion");
    }

    if let Some(m_th) = motion_thresh {
        if motion_val > m_th {
            return Some("motion");
        }
    }

    None
}
