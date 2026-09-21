import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../theme.dart';
import '../../core/models/ppg_models.dart';

class WaveformViewer extends StatefulWidget {
  final SessionAnalysisResult result;
  final double currentStartS;
  final double windowDurationS;
  final ValueChanged<double> onSeek;

  const WaveformViewer({
    super.key,
    required this.result,
    required this.currentStartS,
    required this.windowDurationS,
    required this.onSeek,
  });

  @override
  State<WaveformViewer> createState() => _WaveformViewerState();
}

class _WaveformViewerState extends State<WaveformViewer> {
  @override
  Widget build(BuildContext context) {
    // Slice samples in current window
    final fs = widget.result.sampleRate > 0 ? widget.result.sampleRate : 50.0;
    final startIdx = (widget.currentStartS * fs).floor().clamp(0, widget.result.time.length);
    final endIdx = ((widget.currentStartS + widget.windowDurationS) * fs).ceil().clamp(0, widget.result.time.length);

    final windowTimes = widget.result.time.sublist(startIdx, endIdx);
    final windowFiltered = widget.result.filtered.sublist(startIdx, endIdx);

    // Filter peaks in current window
    final inWinPeaks = widget.result.peaksIndices
        .where((idx) => idx >= startIdx && idx < endIdx)
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Waveform Canvas
        Expanded(
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFF090D16),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: SensioTheme.border.withValues(alpha: 0.4)),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: CustomPaint(
                painter: _PpgWaveformPainter(
                  times: windowTimes,
                  filtered: windowFiltered,
                  allTimes: widget.result.time,
                  peaks: inWinPeaks,
                  startIdx: startIdx,
                  startS: widget.currentStartS,
                  durationS: widget.windowDurationS,
                ),
                child: Container(),
              ),
            ),
          ),
        ),

        // Navigation Bar
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // Jump Controls
              Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.first_page, color: Colors.white70),
                    tooltip: 'Start of session',
                    onPressed: () => widget.onSeek(0.0),
                  ),
                  IconButton(
                    icon: const Icon(Icons.chevron_left, color: Colors.white70),
                    tooltip: 'Step back 15s',
                    onPressed: () => widget.onSeek(
                      math.max(0.0, widget.currentStartS - 15.0),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.chevron_right, color: Colors.white70),
                    tooltip: 'Step forward 15s',
                    onPressed: () => widget.onSeek(
                      math.min(
                        widget.result.totalDurationS - widget.windowDurationS,
                        widget.currentStartS + 15.0,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.last_page, color: Colors.white70),
                    tooltip: 'End of session',
                    onPressed: () => widget.onSeek(
                      math.max(0.0, widget.result.totalDurationS - widget.windowDurationS),
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Jump to Next Clean Pulse Button
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: SensioTheme.goodPulse.withValues(alpha: 0.2),
                      foregroundColor: SensioTheme.goodPulse,
                      side: const BorderSide(color: SensioTheme.goodPulse, width: 1),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    ),
                    icon: const Icon(Icons.favorite, size: 16),
                    label: const Text('Next Clean Pulse', style: TextStyle(fontSize: 12)),
                    onPressed: _jumpToNextCleanPulse,
                  ),
                ],
              ),

              // Time indicator
              Text(
                '${widget.currentStartS.toStringAsFixed(1)}s - ${(widget.currentStartS + widget.windowDurationS).toStringAsFixed(1)}s '
                '(/ ${widget.result.totalDurationS.toStringAsFixed(1)}s)',
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  fontFamily: 'monospace',
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  void _jumpToNextCleanPulse() {
    for (final seg in widget.result.segments) {
      if (seg.isGood && seg.onsetS > widget.currentStartS + 1.0) {
        widget.onSeek(math.min(
          widget.result.totalDurationS - widget.windowDurationS,
          seg.onsetS,
        ));
        return;
      }
    }
    // Loop back to first good segment
    for (final seg in widget.result.segments) {
      if (seg.isGood) {
        widget.onSeek(seg.onsetS);
        return;
      }
    }
  }
}

class _PpgWaveformPainter extends CustomPainter {
  final List<double> times;
  final List<double> filtered;
  final List<double> allTimes;
  final List<int> peaks;
  final int startIdx;
  final double startS;
  final double durationS;

  _PpgWaveformPainter({
    required this.times,
    required this.filtered,
    required this.allTimes,
    required this.peaks,
    required this.startIdx,
    required this.startS,
    required this.durationS,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (times.isEmpty || filtered.isEmpty) return;

    // Draw background grid
    final gridPaint = Paint()
      ..color = const Color(0xFF1E293B).withValues(alpha: 0.6)
      ..strokeWidth = 1.0;

    const numHorizontalLines = 4;
    for (int i = 1; i <= numHorizontalLines; i++) {
      final y = size.height * (i / (numHorizontalLines + 1));
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    // Min & max for auto-scaling
    double minVal = filtered.first;
    double maxVal = filtered.first;
    for (final v in filtered) {
      if (v < minVal) minVal = v;
      if (v > maxVal) maxVal = v;
    }

    final span = math.max((maxVal - minVal).abs(), 1e-4);
    final margin = span * 0.15;
    final lower = minVal - margin;
    final upper = maxVal + margin;
    final range = upper - lower;

    // Signal path
    final wavePaint = Paint()
      ..color = SensioTheme.ppgSignal
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8
      ..strokeCap = StrokeCap.round
      ..isAntiAlias = true;

    final path = Path();
    for (int i = 0; i < filtered.length; i++) {
      final x = (i / math.max(filtered.length - 1, 1)) * size.width;
      final y = size.height - ((filtered[i] - lower) / range) * size.height;

      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    canvas.drawPath(path, wavePaint);

    // Peak markers
    final peakPaint = Paint()
      ..color = SensioTheme.systolicPeak
      ..style = PaintingStyle.fill;

    final tickPaint = Paint()
      ..color = SensioTheme.systolicPeak
      ..strokeWidth = 1.5;

    for (final p in peaks) {
      final localIdx = p - startIdx;
      if (localIdx >= 0 && localIdx < filtered.length) {
        final x = (localIdx / math.max(filtered.length - 1, 1)) * size.width;
        final y = size.height - ((filtered[localIdx] - lower) / range) * size.height;

        // Draw vertical tick and dot
        canvas.drawLine(Offset(x, y - 18), Offset(x, y - 4), tickPaint);
        canvas.drawCircle(Offset(x, y), 3.5, peakPaint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _PpgWaveformPainter oldDelegate) {
    return oldDelegate.startS != startS ||
        oldDelegate.durationS != durationS ||
        oldDelegate.filtered.length != filtered.length;
  }
}
