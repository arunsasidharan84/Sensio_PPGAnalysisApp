import 'dart:math' as math;
import '../models/ppg_models.dart';

class FilteredWindowStats {
  final double windowStartS;
  final double windowEndS;
  final double windowDurationS;
  final double coveragePct;
  final int detectedBeats;
  final List<FeatureSummaryRow> summary;
  final PoincareData poincare;

  FilteredWindowStats({
    required this.windowStartS,
    required this.windowEndS,
    required this.windowDurationS,
    required this.coveragePct,
    required this.detectedBeats,
    required this.summary,
    required this.poincare,
  });
}

class WindowAnalysisService {
  static const Map<String, String> domainMap = {
    'MeanHR': 'Time',
    'MeanNN': 'Time',
    'SDNN': 'Time',
    'RMSSD': 'Time',
    'pNN50': 'Time',
    'pNN20': 'Time',
    'CVNN': 'Time',
    'VLF': 'Frequency',
    'LF': 'Frequency',
    'HF': 'Frequency',
    'LF_HF': 'Frequency',
    'LFn': 'Frequency',
    'HFn': 'Frequency',
    'Total_Power': 'Frequency',
    'SD1': 'Non-Linear',
    'SD2': 'Non-Linear',
    'SD1_SD2': 'Non-Linear',
    'CSI': 'Non-Linear',
    'CVI': 'Non-Linear',
    'SampEn': 'Non-Linear',
    'Morphology_Quality': 'Morphology',
    'APG_b_a_Ratio': 'Morphology',
    'APG_c_a_Ratio': 'Morphology',
    'APG_d_a_Ratio': 'Morphology',
    'APG_e_a_Ratio': 'Morphology',
    'Morph_Pulse_Amp': 'Morphology',
    'Morph_SD_Time_Ratio': 'Morphology',
    'Skin_Temperature': 'Vitals & Activity',
    'Activity_Motion': 'Vitals & Activity',
  };

  /// Computes sub-window statistics in memory in < 1ms
  static FilteredWindowStats computeSubWindow(
    SessionAnalysisResult session,
    double startS,
    double endS,
  ) {
    final winStart = math.max(0.0, math.min(startS, endS));
    final winEnd = math.min(session.totalDurationS, math.max(startS, endS));
    final winDur = math.max(1.0, winEnd - winStart);

    // 1. Coverage within window based on gaplessSegments
    double goodDurationS = 0.0;
    for (final seg in session.gaplessSegments) {
      if (!seg.isGood) continue;
      final overlapStart = math.max(winStart, seg.onsetS);
      final overlapEnd = math.min(winEnd, seg.endS);
      if (overlapEnd > overlapStart) {
        goodDurationS += (overlapEnd - overlapStart);
      }
    }
    final coveragePct = ((goodDurationS / winDur) * 100.0 * 100.0).round() / 100.0;

    // 2. Detected beats within window
    int beatCount = 0;
    if (session.time.isNotEmpty) {
      for (final p in session.peaksIndices) {
        if (p < session.time.length) {
          final t = session.time[p];
          if (t >= winStart && t <= winEnd) {
            beatCount++;
          }
        }
      }
    } else {
      beatCount = session.peaksIndices.length;
    }

    // 3. Poincaré sub-window filtering and recalculation
    final poincare = _filterPoincare(session.poincare, winStart, winEnd);

    // 4. Feature Summary Table recalculation
    final summary = _computeFeatureSummary(session.hrv, winStart, winEnd);

    return FilteredWindowStats(
      windowStartS: winStart,
      windowEndS: winEnd,
      windowDurationS: winDur,
      coveragePct: coveragePct.clamp(0.0, 100.0),
      detectedBeats: beatCount,
      summary: summary,
      poincare: poincare,
    );
  }

  static PoincareData _filterPoincare(PoincareData orig, double winStart, double winEnd) {
    if (orig.timestamps.isEmpty || orig.x.isEmpty) {
      return orig;
    }

    final filteredX = <double>[];
    final filteredY = <double>[];
    final filteredTs = <double>[];

    final n = math.min(orig.x.length, math.min(orig.y.length, orig.timestamps.length));
    for (int i = 0; i < n; i++) {
      final t = orig.timestamps[i];
      if (t >= winStart && t <= winEnd) {
        filteredX.add(orig.x[i]);
        filteredY.add(orig.y[i]);
        filteredTs.add(t);
      }
    }

    if (filteredX.length < 3) {
      // Not enough points to compute a meaningful ellipse, return points with 0 ellipse
      return PoincareData(
        x: filteredX,
        y: filteredY,
        timestamps: filteredTs,
        meanRr: filteredX.isNotEmpty ? filteredX.reduce((a, b) => a + b) / filteredX.length : 0.0,
        sd1: 0.0,
        sd2: 0.0,
        ellipseX: [],
        ellipseY: [],
      );
    }

    final count = filteredX.length;
    final meanRr = filteredX.reduce((a, b) => a + b) / count;

    final diffXy = <double>[];
    final sumXy = <double>[];
    for (int i = 0; i < count; i++) {
      diffXy.add(filteredY[i] - filteredX[i]);
      sumXy.add(filteredY[i] + filteredX[i]);
    }

    final mDiff = diffXy.reduce((a, b) => a + b) / count;
    double varDiff = 0.0;
    for (final d in diffXy) {
      varDiff += math.pow(d - mDiff, 2);
    }
    final sd1 = (math.sqrt(varDiff / (count > 1 ? count - 1 : 1))) / math.sqrt(2);

    final mSum = sumXy.reduce((a, b) => a + b) / count;
    double varSum = 0.0;
    for (final s in sumXy) {
      varSum += math.pow(s - mSum, 2);
    }
    final sd2 = (math.sqrt(varSum / (count > 1 ? count - 1 : 1))) / math.sqrt(2);

    // 95% confidence ellipse geometry
    final a = 2.0 * sd2;
    final b = 2.0 * sd1;
    const rotAngle = math.pi / 4.0;
    final cosRot = math.cos(rotAngle);
    final sinRot = math.sin(rotAngle);

    final ellipseX = <double>[];
    final ellipseY = <double>[];

    for (int i = 0; i < 100; i++) {
      final theta = (i.toDouble()) * 2.0 * math.pi / 99.0;
      final ct = math.cos(theta);
      final st = math.sin(theta);

      final xRot = a * ct * cosRot - b * st * sinRot;
      final yRot = a * ct * sinRot + b * st * cosRot;

      ellipseX.add(xRot + meanRr);
      ellipseY.add(yRot + meanRr);
    }

    return PoincareData(
      x: filteredX,
      y: filteredY,
      timestamps: filteredTs,
      meanRr: meanRr,
      sd1: sd1,
      sd2: sd2,
      ellipseX: ellipseX,
      ellipseY: ellipseY,
    );
  }

  static List<FeatureSummaryRow> _computeFeatureSummary(
    TimeResolvedHrvResult hrv,
    double winStart,
    double winEnd,
  ) {
    final validIndices = <int>[];
    for (int i = 0; i < hrv.timestamps.length; i++) {
      final t = hrv.timestamps[i];
      if (t >= winStart && t <= winEnd) {
        validIndices.add(i);
      }
    }

    final summary = <FeatureSummaryRow>[];

    for (final entry in hrv.metrics.entries) {
      final metricKey = entry.key;
      final series = entry.value;

      final finiteVals = <double>[];
      for (final idx in validIndices) {
        if (idx < series.length) {
          final val = series[idx];
          if (val.isFinite) {
            finiteVals.add(val);
          }
        }
      }

      if (finiteVals.isEmpty) continue;

      final n = finiteVals.length;
      final mean = finiteVals.reduce((a, b) => a + b) / n;
      double sd = 0.0;
      if (n > 1) {
        double sumSq = 0.0;
        for (final v in finiteVals) {
          sumSq += math.pow(v - mean, 2);
        }
        sd = math.sqrt(sumSq / (n - 1));
      }

      final med = _median(finiteVals);
      final q25 = _percentile(finiteVals, 25.0);
      final q75 = _percentile(finiteVals, 75.0);
      final iqr = q75 - q25;

      double minVal = double.infinity;
      double maxVal = double.negativeInfinity;
      for (final v in finiteVals) {
        if (v < minVal) minVal = v;
        if (v > maxVal) maxVal = v;
      }

      final domain = domainMap[metricKey] ?? 'General';

      summary.add(FeatureSummaryRow(
        domain: domain,
        metric: metricKey,
        mean: _round2(mean),
        sd: _round2(sd),
        median: _round2(med),
        iqr: _round2(iqr),
        min: _round2(minVal),
        max: _round2(maxVal),
        count: n,
      ));
    }

    int domainOrder(String d) {
      switch (d) {
        case 'Time':
          return 0;
        case 'Frequency':
          return 1;
        case 'Non-Linear':
          return 2;
        case 'Morphology':
          return 3;
        case 'Vitals & Activity':
          return 4;
        default:
          return 5;
      }
    }

    summary.sort((a, b) {
      final ordA = domainOrder(a.domain);
      final ordB = domainOrder(b.domain);
      if (ordA != ordB) {
        return ordA.compareTo(ordB);
      }
      return a.metric.compareTo(b.metric);
    });

    return summary;
  }

  static double _round2(double v) => (v * 100.0).round() / 100.0;

  static double _median(List<double> list) {
    if (list.isEmpty) return 0.0;
    final sorted = List<double>.from(list)..sort();
    final n = sorted.length;
    if (n % 2 == 1) {
      return sorted[n ~/ 2];
    } else {
      return (sorted[n ~/ 2 - 1] + sorted[n ~/ 2]) / 2.0;
    }
  }

  static double _percentile(List<double> list, double p) {
    if (list.isEmpty) return 0.0;
    final sorted = List<double>.from(list)..sort();
    final n = sorted.length;
    if (n == 1) return sorted[0];

    final rank = (p / 100.0) * (n - 1);
    final low = rank.floor();
    final high = rank.ceil();
    final weight = rank - low;

    return sorted[low] * (1.0 - weight) + sorted[high] * weight;
  }
}
