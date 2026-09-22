import 'package:flutter_test/flutter_test.dart';
import 'package:sensio_ppg_app/core/models/ppg_models.dart';
import 'package:sensio_ppg_app/core/services/window_analysis_service.dart';

void main() {
  group('WindowAnalysisService Tests', () {
    late SessionAnalysisResult mockSession;

    setUp(() {
      final segments = [
        ContinuousSegment(
          id: 1,
          onsetS: 0.0,
          durationS: 100.0,
          endS: 100.0,
          description: 'Good Pulse',
          isGood: true,
        ),
        ContinuousSegment(
          id: 2,
          onsetS: 100.0,
          durationS: 50.0,
          endS: 150.0,
          description: 'Artifact Noise',
          isGood: false,
        ),
        ContinuousSegment(
          id: 3,
          onsetS: 150.0,
          durationS: 150.0,
          endS: 300.0,
          description: 'Good Pulse',
          isGood: true,
        ),
      ];

      final hrv = TimeResolvedHrvResult(
        timestamps: [15.0, 30.0, 45.0, 60.0, 120.0, 180.0, 240.0],
        windowS: 60.0,
        stepS: 15.0,
        metrics: {
          'MeanHR': [60.0, 62.0, 64.0, 66.0, 70.0, 72.0, 74.0],
          'SDNN': [40.0, 42.0, 44.0, 46.0, 50.0, 52.0, 54.0],
          'RMSSD': [30.0, 32.0, 34.0, 36.0, 40.0, 42.0, 44.0],
        },
      );

      final poincare = PoincareData(
        x: [1000.0, 980.0, 950.0, 930.0, 850.0, 830.0],
        y: [980.0, 950.0, 930.0, 850.0, 830.0, 810.0],
        timestamps: [10.0, 20.0, 30.0, 40.0, 190.0, 200.0],
        meanRr: 923.3,
        sd1: 25.0,
        sd2: 75.0,
        ellipseX: [923.3],
        ellipseY: [923.3],
      );

      mockSession = SessionAnalysisResult(
        totalDurationS: 300.0,
        startTimeOfDayS: 0.0,
        sessionStartDateTime: DateTime(2026, 9, 8, 22, 0, 0),
        sampleRate: 50.0,
        coveragePct: 83.33,
        acceptedWindowCount: 5,
        totalWindowCount: 6,
        time: List.generate(300, (i) => i.toDouble()),
        normPpg: List.generate(300, (_) => 0.0),
        filtered: List.generate(300, (_) => 0.0),
        usableMask: List.generate(300, (_) => true),
        pulseMask: List.generate(300, (_) => true),
        qualityTrace: List.generate(300, (_) => 1.0),
        sigmotTrace: List.generate(300, (_) => 0.0),
        peaksIndices: [10, 20, 30, 40, 190, 200, 250],
        gaplessSegments: segments,
        hrv: hrv,
        poincare: poincare,
        summary: [],
      );
    });

    test('Full session sub-window returns identical coverage and count', () {
      final stats = WindowAnalysisService.computeSubWindow(mockSession, 0.0, 300.0);
      expect(stats.windowDurationS, 300.0);
      // Good duration: 100 + 150 = 250s. Coverage = 250/300 = 83.33%
      expect(stats.coveragePct, closeTo(83.33, 0.01));
      expect(stats.detectedBeats, 7);
      expect(stats.summary.length, 3);
      final hrRow = stats.summary.firstWhere((r) => r.metric == 'MeanHR');
      expect(hrRow.count, 7);
      expect(hrRow.mean, closeTo(66.86, 0.01));
    });

    test('Sub-window isolates early interval (0 to 60s)', () {
      final stats = WindowAnalysisService.computeSubWindow(mockSession, 0.0, 60.0);
      expect(stats.windowDurationS, 60.0);
      // Interval 0..60 is completely in segment 1 (isGood: true) -> 100% coverage
      expect(stats.coveragePct, 100.0);
      // Peaks at 10, 20, 30, 40 fall in 0..60 -> 4 beats
      expect(stats.detectedBeats, 4);

      final hrRow = stats.summary.firstWhere((r) => r.metric == 'MeanHR');
      // Timestamps at 15, 30, 45, 60 -> values 60, 62, 64, 66 -> mean = 63.0
      expect(hrRow.count, 4);
      expect(hrRow.mean, 63.0);
      expect(hrRow.min, 60.0);
      expect(hrRow.max, 66.0);
    });

    test('Sub-window isolates noisy interval (100 to 150s)', () {
      final stats = WindowAnalysisService.computeSubWindow(mockSession, 100.0, 150.0);
      // Interval 100..150 is segment 2 (isGood: false) -> 0% coverage
      expect(stats.coveragePct, 0.0);
      expect(stats.detectedBeats, 0);
      // Timestamp at 120s falls in window -> 1 sample
      final hrRow = stats.summary.firstWhere((r) => r.metric == 'MeanHR');
      expect(hrRow.count, 1);
      expect(hrRow.mean, 70.0);
    });

    test('Poincare recalculation on sub-window produces valid geometry', () {
      final stats = WindowAnalysisService.computeSubWindow(mockSession, 0.0, 50.0);
      // Timestamps at 10, 20, 30, 40 fall in 0..50 -> 4 points
      expect(stats.poincare.x.length, 4);
      expect(stats.poincare.ellipseX.length, 100);
      expect(stats.poincare.sd1, greaterThan(0.0));
      expect(stats.poincare.sd2, greaterThan(0.0));
    });
  });
}
