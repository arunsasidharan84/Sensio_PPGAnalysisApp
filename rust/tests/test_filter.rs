use sensio_ppg_core::dsp::filter::SosFilter;
use std::fs::File;
use std::io::Read;

    #[test]
    fn test_segment_filter_parity() {
        let mut f = File::open("../parity_test/test_seg.json").expect("open test_seg.json");
        let mut s = String::new();
        f.read_to_string(&mut s).unwrap();
        let data: serde_json::Value = serde_json::from_str(&s).unwrap();

        let detrended: Vec<f64> = data["detrended"]
            .as_array()
            .unwrap()
            .iter()
            .map(|v| v.as_f64().unwrap())
            .collect();
        let scipy_filt: Vec<f64> = data["scipy_filt"]
            .as_array()
            .unwrap()
            .iter()
            .map(|v| v.as_f64().unwrap())
            .collect();

        let filter = SosFilter::butter_3rd_bandpass_50hz();
        let rs_filt = filter.sosfiltfilt(&detrended);

        assert_eq!(rs_filt.len(), scipy_filt.len());
        let mut max_diff = 0.0f64;
        for i in 0..rs_filt.len() {
            let diff = (rs_filt[i] - scipy_filt[i]).abs();
            if diff > max_diff {
                max_diff = diff;
            }
        }
        println!("test_segment_filter_parity MAX DIFF: {}", max_diff);
        assert!(max_diff < 1e-10, "max diff was {}", max_diff);
    }
