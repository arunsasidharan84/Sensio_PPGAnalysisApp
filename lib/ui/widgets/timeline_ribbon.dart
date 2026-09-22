import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../theme.dart';
import '../../core/models/ppg_models.dart';
import '../../core/utils/time_formatter.dart';

enum _HandleDragTarget { none, startHandle, endHandle, windowSpan }

class TimelineRibbon extends StatefulWidget {
  final List<ContinuousSegment> segments;
  final double totalDurationS;
  final double currentStartS;
  final double windowDurationS;
  final ValueChanged<double> onSeek;
  final bool showClockTime;
  final double t0SecondsOfDay;
  final DateTime? sessionStart;
  final double analysisStartS;
  final double analysisEndS;
  final void Function(double startS, double endS) onAnalysisWindowChanged;
  final VoidCallback? onResetAnalysisWindow;

  const TimelineRibbon({
    super.key,
    required this.segments,
    required this.totalDurationS,
    required this.currentStartS,
    required this.windowDurationS,
    required this.onSeek,
    this.showClockTime = false,
    this.t0SecondsOfDay = 0.0,
    this.sessionStart,
    required this.analysisStartS,
    required this.analysisEndS,
    required this.onAnalysisWindowChanged,
    this.onResetAnalysisWindow,
  });

  @override
  State<TimelineRibbon> createState() => _TimelineRibbonState();
}

class _TimelineRibbonState extends State<TimelineRibbon> {
  _HandleDragTarget _dragTarget = _HandleDragTarget.none;
  double _dragStartMouseX = 0.0;
  double _dragInitStartS = 0.0;
  double _dragInitEndS = 0.0;

  void _applyNightPreset() {
    if (widget.totalDurationS <= 0) return;

    // Determine session start time of day in seconds
    double startTodS = widget.t0SecondsOfDay;
    if (widget.sessionStart != null) {
      startTodS = widget.sessionStart!.hour * 3600.0 +
          widget.sessionStart!.minute * 60.0 +
          widget.sessionStart!.second.toDouble();
    }

    // Target night: 22:00 (79200s) to 06:00 (21600s next day)
    const nightStartTod = 22.0 * 3600.0; // 79200s
    const nightEndTod = 6.0 * 3600.0; // 21600s next day

    double relStartS = 0.0;
    double relEndS = widget.totalDurationS;

    if (startTodS <= nightStartTod) {
      // Session starts before 22:00 on day 1
      relStartS = nightStartTod - startTodS;
      relEndS = relStartS + 8.0 * 3600.0; // 8 hours of sleep
    } else {
      // Session starts during the night (after 22:00)
      relStartS = 0.0;
      final remainingNightS = (24.0 * 3600.0 - startTodS) + nightEndTod;
      relEndS = remainingNightS;
    }

    relStartS = relStartS.clamp(0.0, widget.totalDurationS - 60.0);
    relEndS = relEndS.clamp(relStartS + 60.0, widget.totalDurationS);

    widget.onAnalysisWindowChanged(relStartS, relEndS);
  }

  void _applyDayPreset() {
    if (widget.totalDurationS <= 0) return;

    // Determine session start time of day in seconds
    double startTodS = widget.t0SecondsOfDay;
    if (widget.sessionStart != null) {
      startTodS = widget.sessionStart!.hour * 3600.0 +
          widget.sessionStart!.minute * 60.0 +
          widget.sessionStart!.second.toDouble();
    }

    // Target day: 06:00 (21600s) to 22:00 (79200s)
    const dayStartTod = 6.0 * 3600.0; // 21600s
    const dayEndTod = 22.0 * 3600.0; // 79200s

    double relStartS = 0.0;
    double relEndS = widget.totalDurationS;

    if (startTodS >= dayStartTod && startTodS < dayEndTod) {
      // Started during the day
      relStartS = 0.0;
      relEndS = (dayEndTod - startTodS).clamp(60.0, widget.totalDurationS);
    } else if (startTodS < dayStartTod) {
      // Started in early morning before 06:00
      relStartS = dayStartTod - startTodS;
      relEndS = (dayEndTod - startTodS).clamp(relStartS + 60.0, widget.totalDurationS);
    } else {
      // Started late evening after 22:00 -> day begins next morning at 06:00
      relStartS = (24.0 * 3600.0 - startTodS) + dayStartTod;
      relEndS = relStartS + 16.0 * 3600.0;
    }

    relStartS = relStartS.clamp(0.0, widget.totalDurationS - 60.0);
    relEndS = relEndS.clamp(relStartS + 60.0, widget.totalDurationS);

    widget.onAnalysisWindowChanged(relStartS, relEndS);
  }

  @override
  Widget build(BuildContext context) {
    if (widget.totalDurationS <= 0) return const SizedBox.shrink();

    final isSubWindowActive = widget.analysisStartS > 0.5 ||
        widget.analysisEndS < (widget.totalDurationS - 0.5);

    final startLabel = TimeFormatter.formatSeconds(
      0.0,
      clockTime: widget.showClockTime,
      sessionStart: widget.sessionStart,
      t0SecondsOfDay: widget.t0SecondsOfDay,
      includeDate: widget.showClockTime,
    );
    final endLabel = TimeFormatter.formatSeconds(
      widget.totalDurationS,
      clockTime: widget.showClockTime,
      sessionStart: widget.sessionStart,
      t0SecondsOfDay: widget.t0SecondsOfDay,
      includeDate: widget.showClockTime,
    );

    final windowStartLabel = TimeFormatter.formatSeconds(
      widget.analysisStartS,
      clockTime: widget.showClockTime,
      sessionStart: widget.sessionStart,
      t0SecondsOfDay: widget.t0SecondsOfDay,
      includeDate: false,
    );
    final windowEndLabel = TimeFormatter.formatSeconds(
      widget.analysisEndS,
      clockTime: widget.showClockTime,
      sessionStart: widget.sessionStart,
      t0SecondsOfDay: widget.t0SecondsOfDay,
      includeDate: false,
    );

    final winDurS = (widget.analysisEndS - widget.analysisStartS).clamp(0.0, widget.totalDurationS);
    final winDurHours = winDurS / 3600.0;
    final winDurText = winDurHours >= 1.0
        ? '${winDurHours.toStringAsFixed(1)}h'
        : '${(winDurS / 60.0).round()}m';

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Preset bar & Active Window Status
        Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Row(
            children: [
              // Analysis Window Info Badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: isSubWindowActive
                      ? SensioTheme.accent.withValues(alpha: 0.15)
                      : SensioTheme.surface,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: isSubWindowActive
                        ? SensioTheme.accent.withValues(alpha: 0.6)
                        : SensioTheme.border.withValues(alpha: 0.4),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      isSubWindowActive ? Icons.filter_alt : Icons.crop_free,
                      size: 13,
                      color: isSubWindowActive ? SensioTheme.accent : Colors.white60,
                    ),
                    const SizedBox(width: 5),
                    Text(
                      isSubWindowActive
                          ? 'Window: $windowStartLabel → $windowEndLabel ($winDurText)'
                          : 'Full Session Window ($winDurText)',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: isSubWindowActive ? FontWeight.bold : FontWeight.normal,
                        color: isSubWindowActive ? Colors.white : Colors.white70,
                        fontFamily: 'monospace',
                      ),
                    ),
                    if (isSubWindowActive) ...[
                      const SizedBox(width: 6),
                      InkWell(
                        borderRadius: BorderRadius.circular(4),
                        onTap: () {
                          widget.onResetAnalysisWindow?.call();
                          widget.onAnalysisWindowChanged(0.0, widget.totalDurationS);
                        },
                        child: Container(
                          padding: const EdgeInsets.all(2),
                          decoration: BoxDecoration(
                            color: Colors.white12,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Icon(Icons.close, size: 12, color: Colors.white),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const Spacer(),
              // Presets
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Presets: ', style: TextStyle(color: Colors.white38, fontSize: 10)),
                  _presetBtn('Full', () {
                    widget.onResetAnalysisWindow?.call();
                    widget.onAnalysisWindowChanged(0.0, widget.totalDurationS);
                  }, isSelected: !isSubWindowActive),
                  const SizedBox(width: 4),
                  _presetBtn('Night (22-06)', _applyNightPreset),
                  const SizedBox(width: 4),
                  _presetBtn('Day (06-22)', _applyDayPreset),
                ],
              ),
            ],
          ),
        ),

        // Timeline Bar with Draggable Range Handles
        LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;
            final winStartFrac = (widget.analysisStartS / widget.totalDurationS).clamp(0.0, 1.0);
            final winEndFrac = (widget.analysisEndS / widget.totalDurationS).clamp(0.0, 1.0);

            final leftHandleX = winStartFrac * width;
            final rightHandleX = winEndFrac * width;

            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onHorizontalDragStart: (details) {
                final mouseX = details.localPosition.dx.clamp(0.0, width);
                _dragStartMouseX = mouseX;
                _dragInitStartS = widget.analysisStartS;
                _dragInitEndS = widget.analysisEndS;

                // Handle hit testing
                const hitMargin = 16.0;
                if ((mouseX - leftHandleX).abs() <= hitMargin) {
                  _dragTarget = _HandleDragTarget.startHandle;
                } else if ((mouseX - rightHandleX).abs() <= hitMargin) {
                  _dragTarget = _HandleDragTarget.endHandle;
                } else if (mouseX > leftHandleX && mouseX < rightHandleX) {
                  // Inside window: drag entire span if near top/bottom, or seek waveform
                  _dragTarget = _HandleDragTarget.none;
                  final targetS = (mouseX / width) * widget.totalDurationS;
                  widget.onSeek(targetS.clamp(0.0, (widget.totalDurationS - widget.windowDurationS).clamp(0.0, widget.totalDurationS)));
                } else {
                  // Outside window: seek
                  _dragTarget = _HandleDragTarget.none;
                  final targetS = (mouseX / width) * widget.totalDurationS;
                  widget.onSeek(targetS.clamp(0.0, (widget.totalDurationS - widget.windowDurationS).clamp(0.0, widget.totalDurationS)));
                }
              },
              onHorizontalDragUpdate: (details) {
                final mouseX = details.localPosition.dx.clamp(0.0, width);
                final deltaFrac = (mouseX - _dragStartMouseX) / width;
                final deltaS = deltaFrac * widget.totalDurationS;

                if (_dragTarget == _HandleDragTarget.startHandle) {
                  final newStartS = (_dragInitStartS + deltaS).clamp(0.0, widget.analysisEndS - 10.0);
                  widget.onAnalysisWindowChanged(newStartS, widget.analysisEndS);
                } else if (_dragTarget == _HandleDragTarget.endHandle) {
                  final newEndS = (_dragInitEndS + deltaS).clamp(widget.analysisStartS + 10.0, widget.totalDurationS);
                  widget.onAnalysisWindowChanged(widget.analysisStartS, newEndS);
                } else if (_dragTarget == _HandleDragTarget.windowSpan) {
                  final span = _dragInitEndS - _dragInitStartS;
                  var newStart = (_dragInitStartS + deltaS).clamp(0.0, widget.totalDurationS - span);
                  var newEnd = newStart + span;
                  widget.onAnalysisWindowChanged(newStart, newEnd);
                } else {
                  final targetS = (mouseX / width) * widget.totalDurationS;
                  widget.onSeek(targetS.clamp(0.0, (widget.totalDurationS - widget.windowDurationS).clamp(0.0, widget.totalDurationS)));
                }
              },
              onHorizontalDragEnd: (_) {
                _dragTarget = _HandleDragTarget.none;
              },
              onTapDown: (details) {
                final tapX = details.localPosition.dx.clamp(0.0, width);
                const hitMargin = 16.0;
                if ((tapX - leftHandleX).abs() > hitMargin && (tapX - rightHandleX).abs() > hitMargin) {
                  final targetS = (tapX / width) * widget.totalDurationS;
                  widget.onSeek(targetS.clamp(0.0, (widget.totalDurationS - widget.windowDurationS).clamp(0.0, widget.totalDurationS)));
                }
              },
              child: SizedBox(
                height: 40,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    // Base colored ribbon
                    Positioned(
                      left: 0,
                      right: 0,
                      top: 4,
                      bottom: 4,
                      child: Container(
                        decoration: BoxDecoration(
                          color: SensioTheme.surface,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: SensioTheme.border.withValues(alpha: 0.5)),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: Stack(
                          children: [
                            // Render gapless segments
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: widget.segments.map((seg) {
                                final fraction = (seg.durationS / widget.totalDurationS).clamp(0.0, 1.0);
                                Color segColor = SensioTheme.rejectNoise;
                                if (seg.isGood) {
                                  segColor = SensioTheme.goodPulse;
                                } else if (seg.description.toLowerCase().contains('dropout') ||
                                    seg.description.toLowerCase().contains('defect') ||
                                    seg.description.toLowerCase().contains('artifact')) {
                                  segColor = SensioTheme.badArtifact;
                                }

                                return Expanded(
                                  flex: (fraction * 10000).round().clamp(1, 10000),
                                  child: Container(
                                    color: segColor.withValues(alpha: 0.85),
                                  ),
                                );
                              }).toList(),
                            ),

                            // Waveform zoom viewport indicator
                            Positioned(
                              left: (widget.currentStartS / widget.totalDurationS) * width,
                              width: ((widget.windowDurationS / widget.totalDurationS) * width).clamp(6.0, width),
                              top: 0,
                              bottom: 0,
                              child: Container(
                                decoration: BoxDecoration(
                                  border: Border.all(color: Colors.white, width: 2),
                                  color: Colors.white.withValues(alpha: 0.25),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                              ),
                            ),

                            // Dimming Scrim for excluded regions outside analysis window
                            if (leftHandleX > 0)
                              Positioned(
                                left: 0,
                                width: leftHandleX,
                                top: 0,
                                bottom: 0,
                                child: Container(
                                  color: Colors.black.withValues(alpha: 0.65),
                                ),
                              ),
                            if (rightHandleX < width)
                              Positioned(
                                left: rightHandleX,
                                right: 0,
                                top: 0,
                                bottom: 0,
                                child: Container(
                                  color: Colors.black.withValues(alpha: 0.65),
                                ),
                              ),

                            // Glowing border over active analysis window
                            Positioned(
                              left: leftHandleX,
                              width: math.max(2.0, rightHandleX - leftHandleX),
                              top: 0,
                              bottom: 0,
                              child: Container(
                                decoration: BoxDecoration(
                                  border: Border.symmetric(
                                    horizontal: BorderSide(
                                      color: isSubWindowActive ? SensioTheme.accent : Colors.transparent,
                                      width: 2,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    // Left Drag Handle (Start of Analysis Window)
                    Positioned(
                      left: leftHandleX - 8,
                      top: 0,
                      bottom: 0,
                      width: 16,
                      child: Center(
                        child: Container(
                          width: 10,
                          height: 36,
                          decoration: BoxDecoration(
                            color: isSubWindowActive ? SensioTheme.accent : Colors.white70,
                            borderRadius: BorderRadius.circular(4),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.5),
                                blurRadius: 4,
                                offset: const Offset(0, 1),
                              ),
                            ],
                          ),
                          child: const Icon(Icons.drag_indicator, size: 10, color: Colors.black),
                        ),
                      ),
                    ),

                    // Right Drag Handle (End of Analysis Window)
                    Positioned(
                      left: rightHandleX - 8,
                      top: 0,
                      bottom: 0,
                      width: 16,
                      child: Center(
                        child: Container(
                          width: 10,
                          height: 36,
                          decoration: BoxDecoration(
                            color: isSubWindowActive ? SensioTheme.accent : Colors.white70,
                            borderRadius: BorderRadius.circular(4),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.5),
                                blurRadius: 4,
                                offset: const Offset(0, 1),
                              ),
                            ],
                          ),
                          child: const Icon(Icons.drag_indicator, size: 10, color: Colors.black),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
        const SizedBox(height: 2),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              startLabel,
              style: const TextStyle(color: Colors.white38, fontSize: 10, fontFamily: 'monospace'),
            ),
            Text(
              endLabel,
              style: const TextStyle(color: Colors.white38, fontSize: 10, fontFamily: 'monospace'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _presetBtn(String label, VoidCallback onTap, {bool isSelected = false}) {
    return InkWell(
      borderRadius: BorderRadius.circular(4),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: isSelected ? SensioTheme.accent.withValues(alpha: 0.2) : SensioTheme.surface,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: isSelected ? SensioTheme.accent : SensioTheme.border.withValues(alpha: 0.4),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? SensioTheme.accent : Colors.white70,
            fontSize: 10,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ),
    );
  }
}
