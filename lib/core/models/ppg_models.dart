/// Represents a contiguous gapless segment on the timeline
class ContinuousSegment {
  final int id;
  final double onsetS;
  final double durationS;
  final double endS;
  final String description;
  final bool isGood;
  final double? hrBpm;
  final double? qualityScore;
  final String? reason;

  ContinuousSegment({
    required this.id,
    required this.onsetS,
    required this.durationS,
    required this.endS,
    required this.description,
    required this.isGood,
    this.hrBpm,
    this.qualityScore,
    this.reason,
  });

  factory ContinuousSegment.fromJson(Map<String, dynamic> json) {
    return ContinuousSegment(
      id: json['id'] as int? ?? 0,
      onsetS: (json['onset_s'] as num?)?.toDouble() ?? 0.0,
      durationS: (json['duration_s'] as num?)?.toDouble() ?? 0.0,
      endS: (json['end_s'] as num?)?.toDouble() ?? 0.0,
      description: json['description'] as String? ?? '',
      isGood: json['is_good'] as bool? ?? false,
      hrBpm: (json['hr_bpm'] as num?)?.toDouble(),
      qualityScore: (json['quality_score'] as num?)?.toDouble(),
      reason: json['reason'] as String?,
    );
  }
}

/// Poincaré geometry and scatter points
class PoincareData {
  final List<double> x;
  final List<double> y;
  final List<double> timestamps;
  final double meanRr;
  final double sd1;
  final double sd2;
  final List<double> ellipseX;
  final List<double> ellipseY;

  PoincareData({
    required this.x,
    required this.y,
    required this.timestamps,
    required this.meanRr,
    required this.sd1,
    required this.sd2,
    required this.ellipseX,
    required this.ellipseY,
  });

  factory PoincareData.fromJson(Map<String, dynamic> json) {
    return PoincareData(
      x: (json['x'] as List<dynamic>? ?? []).map((e) => (e as num).toDouble()).toList(),
      y: (json['y'] as List<dynamic>? ?? []).map((e) => (e as num).toDouble()).toList(),
      timestamps: (json['timestamps'] as List<dynamic>? ?? []).map((e) => (e as num).toDouble()).toList(),
      meanRr: (json['mean_rr'] as num?)?.toDouble() ?? 0.0,
      sd1: (json['sd1'] as num?)?.toDouble() ?? 0.0,
      sd2: (json['sd2'] as num?)?.toDouble() ?? 0.0,
      ellipseX: (json['ellipse_x'] as List<dynamic>? ?? []).map((e) => (e as num).toDouble()).toList(),
      ellipseY: (json['ellipse_y'] as List<dynamic>? ?? []).map((e) => (e as num).toDouble()).toList(),
    );
  }
}

/// Time-resolved sliding-window HRV metrics
class TimeResolvedHrvResult {
  final List<double> timestamps;
  final double windowS;
  final double stepS;
  final Map<String, List<double>> metrics;

  TimeResolvedHrvResult({
    required this.timestamps,
    required this.windowS,
    required this.stepS,
    required this.metrics,
  });

  factory TimeResolvedHrvResult.fromJson(Map<String, dynamic> json) {
    final rawMetrics = json['metrics'] as Map<String, dynamic>? ?? {};
    final parsedMetrics = <String, List<double>>{};

    rawMetrics.forEach((key, val) {
      if (val is List) {
        parsedMetrics[key] = val.map((e) => (e as num?)?.toDouble() ?? double.nan).toList();
      }
    });

    return TimeResolvedHrvResult(
      timestamps: (json['timestamps'] as List<dynamic>? ?? []).map((e) => (e as num).toDouble()).toList(),
      windowS: (json['window_s'] as num?)?.toDouble() ?? 60.0,
      stepS: (json['step_s'] as num?)?.toDouble() ?? 15.0,
      metrics: parsedMetrics,
    );
  }
}

/// A single row in the 26-feature statistical summary table
class FeatureSummaryRow {
  final String domain;
  final String metric;
  final double mean;
  final double sd;
  final double median;
  final double iqr;
  final double min;
  final double max;
  final int count;

  FeatureSummaryRow({
    required this.domain,
    required this.metric,
    required this.mean,
    required this.sd,
    required this.median,
    required this.iqr,
    required this.min,
    required this.max,
    required this.count,
  });

  double get minVal => min;
  double get maxVal => max;

  factory FeatureSummaryRow.fromJson(Map<String, dynamic> json) {
    return FeatureSummaryRow(
      domain: json['domain'] as String? ?? 'General',
      metric: json['metric'] as String? ?? '',
      mean: (json['mean'] as num?)?.toDouble() ?? 0.0,
      sd: (json['sd'] as num?)?.toDouble() ?? 0.0,
      median: (json['median'] as num?)?.toDouble() ?? 0.0,
      iqr: (json['iqr'] as num?)?.toDouble() ?? 0.0,
      min: (json['min'] as num?)?.toDouble() ?? 0.0,
      max: (json['max'] as num?)?.toDouble() ?? 0.0,
      count: json['count'] as int? ?? 0,
    );
  }
}

/// Full session analysis output from Rust core
class SessionAnalysisResult {
  final double totalDurationS;
  final double sampleRate;
  final double coveragePct;
  final int acceptedWindowCount;
  final int totalWindowCount;
  final List<double> time;
  final List<double> normPpg;
  final List<double> filtered;
  final List<bool> usableMask;
  final List<bool> pulseMask;
  final List<double> qualityTrace;
  final List<double> sigmotTrace;
  final List<int> peaksIndices;
  final List<ContinuousSegment> gaplessSegments;
  final TimeResolvedHrvResult hrv;
  final PoincareData poincare;
  final List<FeatureSummaryRow> summary;

  SessionAnalysisResult({
    required this.totalDurationS,
    required this.sampleRate,
    required this.coveragePct,
    required this.acceptedWindowCount,
    required this.totalWindowCount,
    required this.time,
    required this.normPpg,
    required this.filtered,
    required this.usableMask,
    required this.pulseMask,
    required this.qualityTrace,
    required this.sigmotTrace,
    required this.peaksIndices,
    required this.gaplessSegments,
    required this.hrv,
    required this.poincare,
    required this.summary,
  });

  List<ContinuousSegment> get segments => gaplessSegments;

  factory SessionAnalysisResult.fromJson(Map<String, dynamic> json) {
    return SessionAnalysisResult(
      totalDurationS: (json['total_duration_s'] as num?)?.toDouble() ?? 0.0,
      sampleRate: (json['sample_rate'] as num?)?.toDouble() ?? 50.0,
      coveragePct: (json['coverage_pct'] as num?)?.toDouble() ?? 0.0,
      acceptedWindowCount: json['accepted_window_count'] as int? ?? 0,
      totalWindowCount: json['total_window_count'] as int? ?? 0,
      time: (json['time'] as List<dynamic>? ?? []).map((e) => (e as num).toDouble()).toList(),
      normPpg: (json['norm_ppg'] as List<dynamic>? ?? []).map((e) => (e as num).toDouble()).toList(),
      filtered: (json['filtered'] as List<dynamic>? ?? []).map((e) => (e as num).toDouble()).toList(),
      usableMask: (json['usable_mask'] as List<dynamic>? ?? []).map((e) => e as bool).toList(),
      pulseMask: (json['pulse_mask'] as List<dynamic>? ?? []).map((e) => e as bool).toList(),
      qualityTrace: (json['quality_trace'] as List<dynamic>? ?? []).map((e) => (e as num).toDouble()).toList(),
      sigmotTrace: (json['sigmot_trace'] as List<dynamic>? ?? []).map((e) => (e as num).toDouble()).toList(),
      peaksIndices: (json['peaks_indices'] as List<dynamic>? ?? []).map((e) => e as int).toList(),
      gaplessSegments: (json['gapless_segments'] as List<dynamic>? ?? [])
          .map((e) => ContinuousSegment.fromJson(e as Map<String, dynamic>))
          .toList(),
      hrv: TimeResolvedHrvResult.fromJson(json['hrv'] as Map<String, dynamic>? ?? {}),
      poincare: PoincareData.fromJson(json['poincare'] as Map<String, dynamic>? ?? {}),
      summary: (json['summary'] as List<dynamic>? ?? [])
          .map((e) => FeatureSummaryRow.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}
