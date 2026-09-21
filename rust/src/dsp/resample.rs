//! Timeline sanitation, BLE dropout detection, and uniform resampling.

#[derive(Debug, Clone)]
pub struct Timeline {
    pub seconds: Vec<f64>,
    pub values: Vec<f64>,
    pub nominal_dt: f64,
    pub gaps: Vec<(f64, f64)>,
}

impl Timeline {
    pub fn native_fs(&self) -> f64 {
        1.0 / self.nominal_dt
    }
}

/// Helper function to compute the median of a slice of f64.
pub fn median(x: &[f64]) -> f64 {
    if x.is_empty() {
        return 0.0;
    }
    let mut sorted = x.to_vec();
    sorted.sort_by(|a, b| a.partial_cmp(b).unwrap_or(std::cmp::Ordering::Equal));
    let n = sorted.len();
    if n % 2 == 1 {
        sorted[n / 2]
    } else {
        0.5 * (sorted[n / 2 - 1] + sorted[n / 2])
    }
}

/// Helper function to compute percentile (0 to 100) using linear interpolation.
pub fn percentile(x: &[f64], p: f64) -> f64 {
    if x.is_empty() {
        return 0.0;
    }
    let mut sorted = x.to_vec();
    sorted.sort_by(|a, b| a.partial_cmp(b).unwrap_or(std::cmp::Ordering::Equal));
    let n = sorted.len();
    if n == 1 {
        return sorted[0];
    }
    let rank = (p / 100.0) * (n as f64 - 1.0);
    let low = rank.floor() as usize;
    let high = rank.ceil() as usize;
    let weight = rank - low as f64;
    sorted[low] * (1.0 - weight) + sorted[high] * weight
}

/// 1D Linear interpolation matching numpy.interp
pub fn interp_1d(x_new: &[f64], xp: &[f64], fp: &[f64]) -> Vec<f64> {
    let mut out = Vec::with_capacity(x_new.len());
    let n = xp.len();
    if n == 0 {
        return vec![0.0; x_new.len()];
    }
    if n == 1 {
        return vec![fp[0]; x_new.len()];
    }

    let mut j = 0;
    for &x in x_new {
        if x <= xp[0] {
            out.push(fp[0]);
            continue;
        }
        if x >= xp[n - 1] {
            out.push(fp[n - 1]);
            continue;
        }

        while j < n - 2 && xp[j + 1] < x {
            j += 1;
        }

        let x0 = xp[j];
        let x1 = xp[j + 1];
        let y0 = fp[j];
        let y1 = fp[j + 1];

        let t = if (x1 - x0).abs() > 1e-12 {
            (x - x0) / (x1 - x0)
        } else {
            0.0
        };
        out.push(y0 + t * (y1 - y0));
    }
    out
}

/// Sanitize raw timestamps and values, locating BLE dropout gaps
pub fn sanitize_timeline(
    raw_seconds: &[f64],
    raw_values: &[f64],
    gap_factor: f64,
    abs_gap_s: f64,
) -> Result<Timeline, String> {
    if raw_seconds.len() != raw_values.len() {
        return Err("seconds and values must have the same length".to_string());
    }

    let mut finite_indices = Vec::with_capacity(raw_seconds.len());
    for i in 0..raw_seconds.len() {
        if raw_seconds[i].is_finite() && raw_values[i].is_finite() {
            finite_indices.push(i);
        }
    }

    if finite_indices.len() < 32 {
        return Err(format!("only {} usable PPG samples", finite_indices.len()));
    }

    // Stable sort by timestamps
    finite_indices.sort_by(|&a, &b| {
        raw_seconds[a]
            .partial_cmp(&raw_seconds[b])
            .unwrap_or(std::cmp::Ordering::Equal)
    });

    let mut seconds = Vec::with_capacity(finite_indices.len());
    let mut values = Vec::with_capacity(finite_indices.len());

    // Keep strictly increasing timestamps
    let first_idx = finite_indices[0];
    seconds.push(raw_seconds[first_idx]);
    values.push(raw_values[first_idx]);

    for &idx in &finite_indices[1..] {
        let t = raw_seconds[idx];
        if t > *seconds.last().unwrap() {
            seconds.push(t);
            values.push(raw_values[idx]);
        }
    }

    if seconds.len() < 32 {
        return Err(format!("only {} strictly increasing PPG samples", seconds.len()));
    }

    let mut dt = Vec::with_capacity(seconds.len() - 1);
    for i in 0..seconds.len() - 1 {
        dt.push(seconds[i + 1] - seconds[i]);
    }

    let nominal_dt = median(&dt);
    if !nominal_dt.is_finite() || nominal_dt <= 0.0 {
        return Err("could not infer a sampling interval".to_string());
    }

    let thresh = (gap_factor * nominal_dt).max(abs_gap_s);
    let mut gaps = Vec::new();
    for i in 0..dt.len() {
        if dt[i] > thresh {
            gaps.push((seconds[i], seconds[i + 1]));
        }
    }

    Ok(Timeline {
        seconds,
        values,
        nominal_dt,
        gaps,
    })
}

/// Uniform resampling matching resample_uniform() in ppg_preprocess.py
pub fn resample_uniform(tl: &Timeline, target_fs: f64) -> (Vec<f64>, Vec<f64>, Vec<bool>) {
    let t0 = tl.seconds[0];
    let t1 = *tl.seconds.last().unwrap();
    let dt = 1.0 / target_fs;

    // np.arange(t0, t1, 1.0 / target_fs)
    let mut grid_t = Vec::new();
    let mut curr_t = t0;
    while curr_t < t1 - 1e-9 {
        grid_t.push(curr_t);
        curr_t += dt;
    }

    let grid_x = interp_1d(&grid_t, &tl.seconds, &tl.values);

    let mut valid = vec![true; grid_t.len()];
    for &(g0, g1) in &tl.gaps {
        for i in 0..grid_t.len() {
            let t = grid_t[i];
            if t > g0 && t < g1 {
                valid[i] = false;
            }
        }
    }

    (grid_t, grid_x, valid)
}
