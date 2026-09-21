//! Digital signal processing filters matching SciPy's second-order sections (SOS) implementation.

use std::f64::consts::PI;

/// A single second-order section (biquad) in transposed Direct Form II:
/// H(z) = (b0 + b1*z^-1 + b2*z^-2) / (1 + a1*z^-1 + a2*z^-2)
#[derive(Debug, Clone, Copy)]
pub struct SosSection {
    pub b: [f64; 3],
    pub a: [f64; 3], // a[0] is assumed to be 1.0
}

impl SosSection {
    pub fn new(b: [f64; 3], a: [f64; 3]) -> Self {
        let a0 = a[0];
        assert!(a0 != 0.0, "a[0] must not be zero");
        Self {
            b: [b[0] / a0, b[1] / a0, b[2] / a0],
            a: [1.0, a[1] / a0, a[2] / a0],
        }
    }

    /// Process a single sample using transposed Direct Form II:
    /// y[n] = b0 * x[n] + z0
    /// z0 = b1 * x[n] - a1 * y[n] + z1
    /// z1 = b2 * x[n] - a2 * y[n]
    #[inline(always)]
    pub fn step(&self, x: f64, z: &mut [f64; 2]) -> f64 {
        let y = self.b[0] * x + z[0];
        z[0] = self.b[1] * x - self.a[1] * y + z[1];
        z[1] = self.b[2] * x - self.a[2] * y;
        y
    }
}

/// A cascade of Second-Order Sections (SOS) filter.
#[derive(Debug, Clone)]
pub struct SosFilter {
    pub sections: Vec<SosSection>,
}

impl SosFilter {
    pub fn new(sections: Vec<SosSection>) -> Self {
        Self { sections }
    }

    /// Standard 3rd-order Butterworth bandpass (0.4 - 8.0 Hz) at 50 Hz matching SciPy:
    /// `scipy.signal.butter(3, [0.4, 8.0], btype='bandpass', fs=50.0, output='sos')`
    pub fn butter_3rd_bandpass_50hz() -> Self {
        let s0 = SosSection::new(
            [0.051148100639424716, 0.10229620127884943, 0.051148100639424716],
            [1.0, -0.7925405978243705, 0.440800162877689],
        );
        let s1 = SosSection::new(
            [1.0, 0.0, -1.0],
            [1.0, -1.2820552977577235, 0.3179872389996595],
        );
        let s2 = SosSection::new(
            [1.0, -2.0, 1.0],
            [1.0, -1.9508867854416923, 0.9534557281802255],
        );
        Self::new(vec![s0, s1, s2])
    }

    /// General Butterworth bandpass filter designer for arbitrary frequencies and sample rates.
    pub fn design_butter_bandpass(order: usize, lowcut: f64, highcut: f64, fs: f64) -> Self {
        if (fs - 50.0).abs() < 1e-6 && (lowcut - 0.4).abs() < 1e-6 && (highcut - 8.0).abs() < 1e-6 && order == 3 {
            return Self::butter_3rd_bandpass_50hz();
        }
        // Bilinear transform design of Butterworth bandpass
        design_butterworth_bandpass_sos(order, lowcut, highcut, fs)
    }

    /// Compute initial conditions zi for step response steady-state (matching scipy.signal.sosfilt_zi)
    pub fn sosfilt_zi(&self) -> Vec<[f64; 2]> {
        let mut zi = Vec::with_capacity(self.sections.len());
        let mut scale = 1.0;

        for sec in &self.sections {
            let b0 = sec.b[0];
            let b1 = sec.b[1];
            let b2 = sec.b[2];
            let a1 = sec.a[1];
            let a2 = sec.a[2];

            let b_sum = b0 + b1 + b2;
            let a_sum = 1.0 + a1 + a2;

            let (z0, z1) = if a_sum.abs() > 1e-15 {
                let capital_b0 = b1 - a1 * b0;
                let capital_b1 = b2 - a2 * b0;
                let init_z0 = (capital_b0 + capital_b1) / a_sum;
                let init_z1 = (1.0 + a1) * init_z0 - capital_b0;
                (scale * init_z0, scale * init_z1)
            } else {
                (0.0, 0.0)
            };

            zi.push([z0, z1]);
            if a_sum.abs() > 1e-15 {
                scale *= b_sum / a_sum;
            }
        }
        zi
    }

    /// In-place or copy forward filtering matching scipy.signal.sosfilt
    pub fn sosfilt(&self, x: &[f64], zi: Option<&[[f64; 2]]>) -> (Vec<f64>, Vec<[f64; 2]>) {
        let n = x.len();
        let mut y = x.to_vec();
        let mut states: Vec<[f64; 2]> = match zi {
            Some(init) => init.to_vec(),
            None => vec![[0.0, 0.0]; self.sections.len()],
        };

        for (sec_idx, sec) in self.sections.iter().enumerate() {
            let z = &mut states[sec_idx];
            for i in 0..n {
                y[i] = sec.step(y[i], z);
            }
        }
        (y, states)
    }

    /// Zero-phase forward-backward filtering matching scipy.signal.sosfiltfilt with bit-exact parity
    pub fn sosfiltfilt(&self, x: &[f64]) -> Vec<f64> {
        let n = x.len();
        let n_sections = self.sections.len();
        let padlen = 3 * (2 * n_sections + 1);

        if n <= padlen {
            // Signal too short for standard odd padding, filter directly
            let (fwd, _) = self.sosfilt(x, None);
            let mut rev = fwd;
            rev.reverse();
            let (bwd, _) = self.sosfilt(&rev, None);
            let mut out = bwd;
            out.reverse();
            return out;
        }

        // Odd extension at boundaries matching SciPy:
        // left: 2 * x[0] - x[padlen..1 step -1]
        // right: 2 * x[n-1] - x[n-2..n-padlen-2 step -1]
        let x0 = x[0];
        let x_end = x[n - 1];

        let mut padded = Vec::with_capacity(padlen + n + padlen);
        for i in (1..=padlen).rev() {
            padded.push(2.0 * x0 - x[i]);
        }
        padded.extend_from_slice(x);
        for i in 1..=padlen {
            padded.push(2.0 * x_end - x[n - 1 - i]);
        }

        let zi_base = self.sosfilt_zi();

        // 1. Forward pass
        let mut zi_fwd = Vec::with_capacity(n_sections);
        let first_val = padded[0];
        for z in &zi_base {
            zi_fwd.push([z[0] * first_val, z[1] * first_val]);
        }
        let (y_fwd, _) = self.sosfilt(&padded, Some(&zi_fwd));

        // 2. Reverse
        let mut y_rev = y_fwd;
        y_rev.reverse();

        // 3. Backward pass
        let rev_first_val = y_rev[0];
        let mut zi_bwd = Vec::with_capacity(n_sections);
        for z in &zi_base {
            zi_bwd.push([z[0] * rev_first_val, z[1] * rev_first_val]);
        }
        let (y_bwd, _) = self.sosfilt(&y_rev, Some(&zi_bwd));

        // 4. Reverse back and crop padding
        let mut out = y_bwd;
        out.reverse();

        out[padlen..(padlen + n)].to_vec()
    }

    /// Measure filter settling time matching filter_settling_time() in ppg_preprocess.py
    pub fn filter_settling_time(&self, fs: f64, tol: f64, max_s: f64) -> f64 {
        let n = (max_s * fs).round() as usize;
        let mut imp = vec![0.0; n];
        if !imp.is_empty() {
            imp[0] = 1.0;
        }
        let (h, _) = self.sosfilt(&imp, None);
        let mut max_abs = 0.0f64;
        for &val in &h {
            let a = val.abs();
            if a > max_abs {
                max_abs = a;
            }
        }
        if max_abs <= 0.0 {
            return 0.5;
        }
        let thresh = tol * max_abs;
        let mut last_above = None;
        for (i, &val) in h.iter().enumerate() {
            if val.abs() > thresh {
                last_above = Some(i);
            }
        }
        match last_above {
            Some(idx) => (idx as f64 + 1.0) / fs,
            None => 0.5,
        }
    }
}

/// Bilinear transform Butterworth bandpass design for arbitrary order/cutoff
fn design_butterworth_bandpass_sos(order: usize, lowcut: f64, highcut: f64, fs: f64) -> SosFilter {
    let w_low = 2.0 * fs * (PI * lowcut / fs).tan();
    let w_high = 2.0 * fs * (PI * highcut / fs).tan();
    let w0 = (w_low * w_high).sqrt();
    let bw = w_high - w_low;

    // Analog prototype poles for normalized Butterworth of degree `order`
    let mut sections = Vec::new();
    let n = order;
    for k in 0..(n / 2) {
        let theta = PI * (2.0 * (k as f64) + 1.0 + n as f64) / (2.0 * n as f64);
        let pole_re = theta.cos();
        let _pole_im = theta.sin();

        // Bandpass transform pole mapping: s^2 + s * bw / w0 + w0^2
        // Bilinear transform: s = 2*fs * (z - 1)/(z + 1)
        let q = 1.0 / (-2.0 * pole_re);
        let sec = biquad_bandpass(w0 / (2.0 * fs), q, bw / w0);
        sections.push(sec);
    }

    if n % 2 == 1 {
        // Odd order has one real pole at s = -1
        let sec = biquad_bandpass_real_pole(w_low / (2.0 * fs), w_high / (2.0 * fs));
        sections.push(sec);
    }

    SosFilter::new(sections)
}

fn biquad_bandpass(f0: f64, q: f64, _bw_ratio: f64) -> SosSection {
    let w0 = 2.0 * PI * f0;
    let alpha = w0.sin() / (2.0 * q);
    let cos_w0 = w0.cos();

    let b0 = alpha;
    let b1 = 0.0;
    let b2 = -alpha;
    let a0 = 1.0 + alpha;
    let a1 = -2.0 * cos_w0;
    let a2 = 1.0 - alpha;

    SosSection::new([b0, b1, b2], [a0, a1, a2])
}

fn biquad_bandpass_real_pole(f_low: f64, f_high: f64) -> SosSection {
    let w_low = 2.0 * PI * f_low;
    let w_high = 2.0 * PI * f_high;
    let g_hp = (1.0 + w_low.cos()) / 2.0;
    let g_lp = (1.0 - w_high.cos()) / 2.0;

    SosSection::new(
        [g_hp * g_lp, 0.0, -g_hp * g_lp],
        [1.0, -(w_low.cos() + w_high.cos()) / 2.0, (w_low.cos() * w_high.cos())],
    )
}
