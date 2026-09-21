import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../theme.dart';
import '../../core/models/ppg_models.dart';

class PoincareChart extends StatelessWidget {
  final PoincareData data;
  final ValueChanged<double>? onSelectBeatTimestamp;

  const PoincareChart({
    super.key,
    required this.data,
    this.onSelectBeatTimestamp,
  });

  @override
  Widget build(BuildContext context) {
    if (data.x.isEmpty || data.y.isEmpty) {
      return const Center(
        child: Text(
          'Insufficient valid beats for Poincaré Phase Space plot',
          style: TextStyle(color: Colors.white54),
        ),
      );
    }

    return Column(
      children: [
        // Metrics Summary Header
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: SensioTheme.surface,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: SensioTheme.border.withValues(alpha: 0.4)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _metricChip('Mean RR', '${data.meanRr.toStringAsFixed(1)} ms'),
              _metricChip('SD1 (short-term)', '${data.sd1.toStringAsFixed(1)} ms'),
              _metricChip('SD2 (long-term)', '${data.sd2.toStringAsFixed(1)} ms'),
              _metricChip('SD1/SD2', (data.sd2 > 0 ? (data.sd1 / data.sd2).toStringAsFixed(3) : '-')),
              _metricChip('Total Beats', '${data.x.length}'),
            ],
          ),
        ),
        const SizedBox(height: 12),

        // Scatter & Ellipse Canvas
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              color: const Color(0xFF090D16),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: SensioTheme.border.withValues(alpha: 0.4)),
            ),
            child: LayoutBuilder(
              builder: (context, constraints) {
                return GestureDetector(
                  onTapDown: (details) {
                    if (onSelectBeatTimestamp == null) return;
                    _handleTap(details.localPosition, constraints.biggest);
                  },
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: CustomPaint(
                      size: constraints.biggest,
                      painter: _PoincarePainter(data: data),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  void _handleTap(Offset localPos, Size size) {
    if (data.timestamps.isEmpty) return;

    double minVal = 400.0;
    double maxVal = 1400.0;
    for (int i = 0; i < data.x.length; i++) {
      if (data.x[i] < minVal) minVal = data.x[i];
      if (data.x[i] > maxVal) maxVal = data.x[i];
      if (data.y[i] < minVal) minVal = data.y[i];
      if (data.y[i] > maxVal) maxVal = data.y[i];
    }
    final range = maxVal - minVal;

    int? nearestIdx;
    double minDistance = double.infinity;

    for (int i = 0; i < data.x.length; i++) {
      final px = ((data.x[i] - minVal) / range) * size.width;
      final py = size.height - ((data.y[i] - minVal) / range) * size.height;

      final dist = (localPos.dx - px) * (localPos.dx - px) + (localPos.dy - py) * (localPos.dy - py);
      if (dist < minDistance && dist < 400.0) { // Within 20px
        minDistance = dist;
        nearestIdx = i;
      }
    }

    if (nearestIdx != null && nearestIdx < data.timestamps.length) {
      onSelectBeatTimestamp!(data.timestamps[nearestIdx]);
    }
  }

  Widget _metricChip(String label, String value) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: const TextStyle(color: Colors.white54, fontSize: 11),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: const TextStyle(
            color: SensioTheme.accent,
            fontSize: 14,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }
}

class _PoincarePainter extends CustomPainter {
  final PoincareData data;

  _PoincarePainter({required this.data});

  @override
  void paint(Canvas canvas, Size size) {
    if (data.x.isEmpty) return;

    double minVal = 400.0;
    double maxVal = 1400.0;
    for (int i = 0; i < data.x.length; i++) {
      if (data.x[i] < minVal) minVal = data.x[i];
      if (data.x[i] > maxVal) maxVal = data.x[i];
      if (data.y[i] < minVal) minVal = data.y[i];
      if (data.y[i] > maxVal) maxVal = data.y[i];
    }

    // Add padding
    final margin = (maxVal - minVal) * 0.1;
    minVal -= margin;
    maxVal += margin;
    final range = math.max(maxVal - minVal, 1.0);

    // Identity line: y = x
    final idPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.2)
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke;

    final p0 = Offset(0, size.height);
    final p1 = Offset(size.width, 0);
    canvas.drawLine(p0, p1, idPaint);

    // Confidence Ellipse
    if (data.ellipseX.isNotEmpty && data.ellipseY.isNotEmpty) {
      final ellipsePaint = Paint()
        ..color = SensioTheme.accent.withValues(alpha: 0.8)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0;

      final ellipseFill = Paint()
        ..color = SensioTheme.accent.withValues(alpha: 0.12)
        ..style = PaintingStyle.fill;

      final ellipsePath = Path();
      for (int i = 0; i < data.ellipseX.length; i++) {
        final x = ((data.ellipseX[i] - minVal) / range) * size.width;
        final y = size.height - ((data.ellipseY[i] - minVal) / range) * size.height;

        if (i == 0) {
          ellipsePath.moveTo(x, y);
        } else {
          ellipsePath.lineTo(x, y);
        }
      }
      ellipsePath.close();
      canvas.drawPath(ellipsePath, ellipseFill);
      canvas.drawPath(ellipsePath, ellipsePaint);
    }

    // Scatter points
    final dotPaint = Paint()
      ..color = SensioTheme.ppgSignal.withValues(alpha: 0.75)
      ..style = PaintingStyle.fill;

    for (int i = 0; i < data.x.length; i++) {
      final x = ((data.x[i] - minVal) / range) * size.width;
      final y = size.height - ((data.y[i] - minVal) / range) * size.height;
      canvas.drawCircle(Offset(x, y), 2.5, dotPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _PoincarePainter oldDelegate) {
    return oldDelegate.data.x.length != data.x.length;
  }
}
