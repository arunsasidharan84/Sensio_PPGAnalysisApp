//! Elgendi et al. (2013) systolic peak detector with physiological refractory gating.

use crate::dsp::filter::{SosFilter, SosSection};
use crate::dsp::sqi::{find_peaks, uniform_filter1d};

/// 2nd order Butterworth bandpass (0.5 - 8.0 Hz) at 50 Hz matching NeuroKit2 ppg_clean(method="elgendi"):
/// `butter(2, [0.5, 8.0], btype='bandpass', fs=50.0, output='sos')`
fn elgendi_bandpass_50hz() -> SosFilter {
    let s0 = SosSection::new(
        [0.13110643991662593, 0.26221287983325187, 0.13110643991662593],
        [1.0, -0.7424725560571979, 0.29711776735931905],
    );
    let s1 = SosSection::new(
        [1.0, -2.0, 1.0],
        [1.0, -1.9119834584239155, 0.9161853239015634],
    );
    SosFilter::new(vec![s0, s1])
}

fn peak_prominence(x: &[f64], peak: usize) -> f64 {
    let p_val = x[peak];
    let mut left_min = p_val;
    for i in (0..peak).rev() {
        if x[i] < left_min {
            left_min = x[i];
        }
        if x[i] > p_val {
            break;
        }
    }
    let mut right_min = p_val;
    for i in (peak + 1)..x.len() {
        if x[i] < right_min {
            right_min = x[i];
        }
        if x[i] > p_val {
            break;
        }
    }
    p_val - left_min.max(right_min)
}

/// Detect systolic peaks using the Elgendi algorithm matching NeuroKit2 + data_manager.py
pub fn elgendi_find_peaks(signal: &[f64], fs: f64) -> Vec<usize> {
    let n = signal.len();
    if n < (1.5 * fs).round() as usize {
        return Vec::new();
    }

    // 1. Clean signal with 2nd order bandpass (0.5 - 8.0 Hz)
    let filter = if (fs - 50.0).abs() < 1e-3 {
        elgendi_bandpass_50hz()
    } else {
        SosFilter::design_butter_bandpass(2, 0.5, 8.0, fs)
    };
    let clean = filter.sosfiltfilt(signal);

    // 2. Rectify and square: signal_abs[signal_abs < 0] = 0; sqrd = signal_abs^2
    let mut sqrd = Vec::with_capacity(n);
    let mut sqrd_sum = 0.0;
    for &v in &clean {
        let val = if v > 0.0 { v * v } else { 0.0 };
        sqrd.push(val);
        sqrd_sum += val;
    }
    let sqrd_mean = sqrd_sum / (n as f64);

    // 3. Moving average thresholds
    let ma_peak_kernel = (0.111 * fs).round() as usize;
    let ma_beat_kernel = (0.667 * fs).round() as usize;

    let ma_peak = uniform_filter1d(&sqrd, ma_peak_kernel);
    let ma_beat = uniform_filter1d(&sqrd, ma_beat_kernel);

    let offset = 0.02 * sqrd_mean;
    let mut waves = vec![false; n];
    for i in 0..n {
        waves[i] = ma_peak[i] > (ma_beat[i] + offset);
    }

    // 4. Identify rising and falling edges of waves
    let mut beg_waves = Vec::new();
    let mut end_waves = Vec::new();
    for i in 0..n - 1 {
        if !waves[i] && waves[i + 1] {
            beg_waves.push(i);
        } else if waves[i] && !waves[i + 1] {
            end_waves.push(i);
        }
    }

    if beg_waves.is_empty() || end_waves.is_empty() {
        return Vec::new();
    }

    // Throw out wave-ends that precede first wave-start
    let first_beg = beg_waves[0];
    end_waves.retain(|&e| e > first_beg);

    let num_waves = beg_waves.len().min(end_waves.len());
    let min_len = (0.111 * fs).round() as usize;
    let min_delay = (0.30 * fs).round() as usize;

    let mut detected_peaks: Vec<usize> = Vec::new();
    let mut last_peak_or_zero: usize = 0;

    for i in 0..num_waves {
        let beg = beg_waves[i];
        let end = end_waves[i];
        if end <= beg || (end - beg) < min_len {
            continue;
        }

        // Peak search within clean signal
        let seg = &clean[beg..end];
        let locmax = find_peaks(seg, None, None, None);

        if !locmax.is_empty() {
            // Pick the most prominent peak in the wave matching scipy.signal.find_peaks(prominence)
            let mut best_idx = locmax[0];
            let mut best_prom = peak_prominence(seg, best_idx);

            for &pos in &locmax[1..] {
                let prom = peak_prominence(seg, pos);
                if prom > best_prom {
                    best_prom = prom;
                    best_idx = pos;
                }
            }
            let peak = beg + best_idx;

            if peak > last_peak_or_zero + min_delay {
                detected_peaks.push(peak);
                last_peak_or_zero = peak;
            }
        }
    }

    // 5. Physiological refractory filtering (minimum 360 ms between consecutive systolic peaks)
    // matching data_manager.py: if within 360ms, keep higher peak
    let min_refractory_samples = (0.36 * fs).round() as usize;
    detected_peaks.sort();

    let mut filtered_peaks: Vec<usize> = Vec::new();
    for p in detected_peaks {
        if filtered_peaks.is_empty() {
            filtered_peaks.push(p);
        } else {
            let last_idx = *filtered_peaks.last().unwrap();
            if p >= last_idx + min_refractory_samples {
                filtered_peaks.push(p);
            } else if signal[p] > signal[last_idx] {
                *filtered_peaks.last_mut().unwrap() = p;
            }
        }
    }

    filtered_peaks
}
