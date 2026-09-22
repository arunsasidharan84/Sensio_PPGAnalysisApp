import 'dart:math' as math;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import '../theme.dart';
import '../../core/models/ppg_models.dart';
import '../../core/utils/time_formatter.dart';

class WaveformViewer extends StatefulWidget {
  final SessionAnalysisResult result;
  final double currentStartS;
  final double windowDurationS;
  final ValueChanged<double> onSeek;
  final bool showClockTime;
  final double t0SecondsOfDay;
  final DateTime? sessionStart;

  const WaveformViewer({
    super.key,
    required this.result,
    required this.currentStartS,
    required this.windowDurationS,
    required this.onSeek,
    this.showClockTime = false,
    this.t0SecondsOfDay = 0.0,
    this.sessionStart,
  });

  @override
  State<WaveformViewer> createState() => _WaveformViewerState();
}

class _WaveformViewerState extends State<WaveformViewer> {
  double _verticalGain = 1.0;
  double _baseGain = 1.0;

  void _adjustGain(double delta) {
    setState(() {
      _verticalGain = (_verticalGain * delta).clamp(0.2, 15.0);
    });
  }

  void _setGain(double gain) {
    setState(() {
      _verticalGain = gain.clamp(0.2, 15.0);
    });
  }

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

    // Formatted time range
    final startFormatted = TimeFormatter.formatSeconds(
      widget.currentStartS,
      clockTime: widget.showClockTime,
      sessionStart: widget.sessionStart,
      t0SecondsOfDay: widget.t0SecondsOfDay,
      includeDate: widget.showClockTime,
      showMillis: true,
    );
    final endFormatted = TimeFormatter.formatSeconds(
      widget.currentStartS + widget.windowDurationS,
      clockTime: widget.showClockTime,
      sessionStart: widget.sessionStart,
      t0SecondsOfDay: widget.t0SecondsOfDay,
      includeDate: false,
      showMillis: true,
    );
    final totalFormatted = TimeFormatter.formatSeconds(
      widget.result.totalDurationS,
      clockTime: false,
      sessionStart: widget.sessionStart,
      t0SecondsOfDay: widget.t0SecondsOfDay,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Waveform Canvas with Pinch Gesture and Scroll Listener
        Expanded(
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFF090D16),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: SensioTheme.border.withValues(alpha: 0.4)),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Stack(
                children: [
                  Listener(
                    onPointerSignal: (pointerSignal) {
                      if (pointerSignal is PointerScrollEvent) {
                        final dy = pointerSignal.scrollDelta.dy;
                        if (dy != 0) {
                          _adjustGain(dy < 0 ? 1.15 : 0.87);
                        }
                      }
                    },
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onScaleStart: (details) {
                        _baseGain = _verticalGain;
                      },
                      onScaleUpdate: (details) {
                        // Pinch to adjust vertical pulse amplitude
                        final scale = details.verticalScale != 1.0
                            ? details.verticalScale
                            : details.scale;
                        setState(() {
                          _verticalGain = (_baseGain * scale).clamp(0.2, 15.0);
                        });
                      },
                      child: CustomPaint(
                        size: Size.infinite,
                        painter: _PpgWaveformPainter(
                          times: windowTimes,
                          filtered: windowFiltered,
                          allTimes: widget.result.time,
                          peaks: inWinPeaks,
                          startIdx: startIdx,
                          startS: widget.currentStartS,
                          durationS: widget.windowDurationS,
                          verticalGain: _verticalGain,
                          showClockTime: widget.showClockTime,
                          t0SecondsOfDay: widget.t0SecondsOfDay,
                          sessionStart: widget.sessionStart,
                        ),
                      ),
                    ),
                  ),

                  // Overlay Badge: Current Gain & Reset Button
                  Positioned(
                    top: 10,
                    right: 12,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: SensioTheme.surface.withValues(alpha: 0.85),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: SensioTheme.border.withValues(alpha: 0.4)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'Gain: ${_verticalGain.toStringAsFixed(1)}x',
                            style: const TextStyle(
                              color: SensioTheme.ppgSignal,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              fontFamily: 'monospace',
                            ),
                          ),
                          if ((_verticalGain - 1.0).abs() > 0.05) ...[
                            const SizedBox(width: 6),
                            InkWell(
                              onTap: () => _setGain(1.0),
                              child: const Icon(Icons.refresh, size: 13, color: Colors.white70),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),

        // Navigation Bar & Height Adjust Controls
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final isNarrow = constraints.maxWidth < 950;

              final jumpControls = Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.first_page, color: Colors.white70, size: 20),
                    tooltip: 'Start of session',
                    onPressed: () => widget.onSeek(0.0),
                  ),
                  IconButton(
                    icon: const Icon(Icons.chevron_left, color: Colors.white70, size: 20),
                    tooltip: 'Step back 15s',
                    onPressed: () => widget.onSeek(
                      math.max(0.0, widget.currentStartS - 15.0),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.chevron_right, color: Colors.white70, size: 20),
                    tooltip: 'Step forward 15s',
                    onPressed: () => widget.onSeek(
                      math.min(
                        widget.result.totalDurationS - widget.windowDurationS,
                        widget.currentStartS + 15.0,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.last_page, color: Colors.white70, size: 20),
                    tooltip: 'End of session',
                    onPressed: () => widget.onSeek(
                      math.max(0.0, widget.result.totalDurationS - widget.windowDurationS),
                    ),
                  ),
                  const SizedBox(width: 4),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: SensioTheme.goodPulse.withValues(alpha: 0.2),
                      foregroundColor: SensioTheme.goodPulse,
                      side: const BorderSide(color: SensioTheme.goodPulse, width: 1),
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    ),
                    icon: const Icon(Icons.favorite, size: 13),
                    label: const Text('Next Clean Pulse', style: TextStyle(fontSize: 11)),
                    onPressed: _jumpToNextCleanPulse,
                  ),
                ],
              );

              final heightControls = Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Pulse Height:',
                    style: TextStyle(color: Colors.white54, fontSize: 11),
                  ),
                  const SizedBox(width: 2),
                  IconButton(
                    icon: const Icon(Icons.remove_circle_outline, size: 18),
                    color: Colors.white70,
                    tooltip: 'Decrease height (zoom out)',
                    onPressed: () => _adjustGain(0.8),
                  ),
                  IconButton(
                    icon: const Icon(Icons.add_circle_outline, size: 18),
                    color: SensioTheme.accent,
                    tooltip: 'Increase height (zoom in)',
                    onPressed: () => _adjustGain(1.25),
                  ),
                  // Preset Chips
                  ...[0.5, 1.0, 2.0, 4.0].map((preset) {
                    final isSel = (_verticalGain - preset).abs() < 0.1;
                    return Padding(
                      padding: const EdgeInsets.only(left: 3),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(4),
                        onTap: () => _setGain(preset),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                          decoration: BoxDecoration(
                            color: isSel ? SensioTheme.accent : Colors.transparent,
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(
                              color: isSel ? SensioTheme.accent : SensioTheme.border.withValues(alpha: 0.4),
                            ),
                          ),
                          child: Text(
                            '${preset.toStringAsFixed(preset == 1.0 || preset == 2.0 || preset == 4.0 ? 0 : 1)}x',
                            style: TextStyle(
                              color: isSel ? Colors.black : Colors.white70,
                              fontSize: 10,
                              fontWeight: isSel ? FontWeight.bold : FontWeight.normal,
                            ),
                          ),
                        ),
                      ),
                    );
                  }),
                ],
              );

              final timeBadge = Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: SensioTheme.surface.withValues(alpha: 0.7),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: SensioTheme.border.withValues(alpha: 0.3)),
                ),
                child: Text(
                  '$startFormatted  →  $endFormatted  (Total: $totalFormatted)',
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    fontFamily: 'monospace',
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              );

              if (isNarrow) {
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          jumpControls,
                          const SizedBox(width: 8),
                          heightControls,
                        ],
                      ),
                    ),
                    const SizedBox(height: 4),
                    timeBadge,
                  ],
                );
              } else {
                return Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    jumpControls,
                    heightControls,
                    Flexible(child: timeBadge),
                  ],
                );
              }
            },
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
  final double verticalGain;
  final bool showClockTime;
  final double t0SecondsOfDay;
  final DateTime? sessionStart;

  _PpgWaveformPainter({
    required this.times,
    required this.filtered,
    required this.allTimes,
    required this.peaks,
    required this.startIdx,
    required this.startS,
    required this.durationS,
    required this.verticalGain,
    required this.showClockTime,
    required this.t0SecondsOfDay,
    this.sessionStart,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (times.isEmpty || filtered.isEmpty) return;

    final bottomPadding = 26.0;
    final plotHeight = size.height - bottomPadding;

    // Draw background horizontal grid
    final gridPaint = Paint()
      ..color = const Color(0xFF1E293B).withValues(alpha: 0.6)
      ..strokeWidth = 1.0;

    const numHorizontalLines = 4;
    for (int i = 1; i <= numHorizontalLines; i++) {
      final y = plotHeight * (i / (numHorizontalLines + 1));
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

    // If signal is flat zeros (startup stabilization / artifact), show prompt to user
    if (span < 0.05) {
      final tp = TextPainter(
        text: const TextSpan(
          text: 'Signal Baseline / Artifact Episode — Click "Next Clean Pulse" below',
          style: TextStyle(color: Colors.white38, fontSize: 13, fontStyle: FontStyle.italic),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset((size.width - tp.width) / 2, (plotHeight - tp.height) / 2 - 16));
    }

    // Baseline-centered vertical scaling with verticalGain
    final midVal = (minVal + maxVal) / 2.0;
    final effectiveSpan = (span * 1.3) / verticalGain;
    final lower = midVal - effectiveSpan / 2.0;
    final upper = midVal + effectiveSpan / 2.0;
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
      final y = plotHeight - ((filtered[i] - lower) / range) * plotHeight;

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
        final y = plotHeight - ((filtered[localIdx] - lower) / range) * plotHeight;

        // Draw vertical tick and dot
        canvas.drawLine(Offset(x, y - 16), Offset(x, y - 4), tickPaint);
        canvas.drawCircle(Offset(x, y), 3.5, peakPaint);
      }
    }

    // Time Axis Ticks at bottom
    const numTimeTicks = 5;
    for (int i = 0; i < numTimeTicks; i++) {
      final frac = i / (numTimeTicks - 1);
      final x = frac * (size.width - 60) + 30;
      final tickTimeS = startS + frac * durationS;
      final timeText = TimeFormatter.formatSeconds(
        tickTimeS,
        clockTime: showClockTime,
        sessionStart: sessionStart,
        t0SecondsOfDay: t0SecondsOfDay,
        showMillis: false,
      );

      final tp = TextPainter(
        text: TextSpan(
          text: timeText,
          style: const TextStyle(color: Colors.white38, fontSize: 10, fontFamily: 'monospace'),
        ),
        textDirection: TextDirection.ltr,
      )..layout();

      tp.paint(canvas, Offset(x - tp.width / 2, size.height - 18));
    }
  }

  @override
  bool shouldRepaint(covariant _PpgWaveformPainter oldDelegate) {
    return oldDelegate.startS != startS ||
        oldDelegate.durationS != durationS ||
        oldDelegate.verticalGain != verticalGain ||
        oldDelegate.showClockTime != showClockTime ||
        oldDelegate.sessionStart != sessionStart ||
        oldDelegate.filtered.length != filtered.length;
  }
}
