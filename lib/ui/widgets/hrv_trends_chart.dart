import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../theme.dart';
import '../../core/models/ppg_models.dart';

class HrvTrendsChart extends StatefulWidget {
  final TimeResolvedHrvResult hrvResult;
  final ValueChanged<double>? onSelectTimestamp;

  const HrvTrendsChart({
    super.key,
    required this.hrvResult,
    this.onSelectTimestamp,
  });

  @override
  State<HrvTrendsChart> createState() => _HrvTrendsChartState();
}

class _HrvTrendsChartState extends State<HrvTrendsChart> {
  String _selectedDomain = 'Time';
  String _selectedMetric = 'MeanHR';

  final Map<String, List<String>> _domainMetrics = {
    'Time': ['MeanHR', 'MeanNN', 'SDNN', 'RMSSD', 'pNN50', 'pNN20', 'CVNN'],
    'Frequency': ['LF', 'HF', 'LF_HF', 'LFn', 'HFn', 'VLF', 'Total_Power'],
    'Non-Linear': ['SD1', 'SD2', 'SD1_SD2', 'CSI', 'CVI', 'SampEn'],
    'Morphology': [
      'Morphology_Quality',
      'APG_b_a_Ratio',
      'APG_c_a_Ratio',
      'APG_d_a_Ratio',
      'APG_e_a_Ratio',
      'Morph_Pulse_Amp',
      'Morph_SD_Time_Ratio'
    ],
  };

  @override
  Widget build(BuildContext context) {
    final values = widget.hrvResult.metrics[_selectedMetric] ?? [];

    return Column(
      children: [
        // Controls Row: Domain Switcher & Metric Dropdown
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: SensioTheme.surface,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: SensioTheme.border.withValues(alpha: 0.4)),
          ),
          child: Row(
            children: [
              // Domain Segmented Buttons
              Expanded(
                child: Wrap(
                  spacing: 8,
                  children: _domainMetrics.keys.map((domain) {
                    final isSel = domain == _selectedDomain;
                    return ChoiceChip(
                      label: Text(domain),
                      selected: isSel,
                      selectedColor: SensioTheme.accent.withValues(alpha: 0.2),
                      backgroundColor: Colors.transparent,
                      labelStyle: TextStyle(
                        color: isSel ? SensioTheme.accent : Colors.white60,
                        fontWeight: isSel ? FontWeight.bold : FontWeight.normal,
                        fontSize: 12,
                      ),
                      side: BorderSide(
                        color: isSel ? SensioTheme.accent : SensioTheme.border.withValues(alpha: 0.3),
                      ),
                      onSelected: (selected) {
                        if (selected) {
                          setState(() {
                            _selectedDomain = domain;
                            _selectedMetric = _domainMetrics[domain]!.first;
                          });
                        }
                      },
                    );
                  }).toList(),
                ),
              ),

              // Metric Dropdown
              DropdownButton<String>(
                value: _selectedMetric,
                dropdownColor: SensioTheme.surface,
                underline: const SizedBox.shrink(),
                style: const TextStyle(color: SensioTheme.accent, fontWeight: FontWeight.bold),
                items: (_domainMetrics[_selectedDomain] ?? []).map((m) {
                  return DropdownMenuItem(value: m, child: Text(m));
                }).toList(),
                onChanged: (newM) {
                  if (newM != null) {
                    setState(() => _selectedMetric = newM);
                  }
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),

        // Trend Line Canvas
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              color: const Color(0xFF090D16),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: SensioTheme.border.withValues(alpha: 0.4)),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: CustomPaint(
                painter: _TrendChartPainter(
                  timestamps: widget.hrvResult.timestamps,
                  values: values,
                  metricName: _selectedMetric,
                ),
                child: Container(),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _TrendChartPainter extends CustomPainter {
  final List<double> timestamps;
  final List<double> values;
  final String metricName;

  _TrendChartPainter({
    required this.timestamps,
    required this.values,
    required this.metricName,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (timestamps.isEmpty || values.isEmpty) return;

    // Filter valid finite points
    final validPoints = <int>[];
    double minVal = double.infinity;
    double maxVal = -double.infinity;

    for (int i = 0; i < values.length; i++) {
      final v = values[i];
      if (v.isFinite) {
        validPoints.add(i);
        if (v < minVal) minVal = v;
        if (v > maxVal) maxVal = v;
      }
    }

    if (validPoints.isEmpty) {
      final tp = TextPainter(
        text: const TextSpan(
          text: 'No valid sliding-window samples for this metric in the current session',
          style: TextStyle(color: Colors.white54, fontSize: 13),
        ),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: size.width - 32);
      tp.paint(canvas, Offset((size.width - tp.width) / 2, (size.height - tp.height) / 2));
      return;
    }

    final tMin = timestamps.first;
    final tMax = timestamps.last;
    final tRange = math.max(tMax - tMin, 1.0);

    final span = math.max((maxVal - minVal).abs(), 1e-4);
    final margin = span * 0.15;
    final lower = minVal - margin;
    final upper = maxVal + margin;
    final range = upper - lower;

    // Draw horizontal grid lines
    final gridPaint = Paint()
      ..color = const Color(0xFF1E293B).withValues(alpha: 0.5)
      ..strokeWidth = 1.0;

    for (int i = 1; i <= 4; i++) {
      final y = size.height * (i / 5);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
      final labelVal = upper - (i / 5) * range;
      final tp = TextPainter(
        text: TextSpan(
          text: labelVal.toStringAsFixed(1),
          style: const TextStyle(color: Colors.white30, fontSize: 10),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(8, y - 12));
    }

    // Line Path
    final linePaint = Paint()
      ..color = SensioTheme.accent
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2
      ..strokeCap = StrokeCap.round
      ..isAntiAlias = true;

    final dotPaint = Paint()
      ..color = SensioTheme.accent
      ..style = PaintingStyle.fill;

    Path? path;
    int? lastIdx;

    for (final i in validPoints) {
      final x = ((timestamps[i] - tMin) / tRange) * (size.width - 40) + 20;
      final y = size.height - ((values[i] - lower) / range) * (size.height - 40) - 20;

      // Draw dot
      canvas.drawCircle(Offset(x, y), 3.0, dotPaint);

      // Connect if consecutive
      if (lastIdx == null || (i - lastIdx > 1)) {
        if (path != null) {
          canvas.drawPath(path, linePaint);
        }
        path = Path()..moveTo(x, y);
      } else {
        path!.lineTo(x, y);
      }
      lastIdx = i;
    }

    if (path != null) {
      canvas.drawPath(path, linePaint);
    }
  }

  @override
  bool shouldRepaint(covariant _TrendChartPainter oldDelegate) {
    return oldDelegate.metricName != metricName ||
        oldDelegate.values.length != values.length;
  }
}
