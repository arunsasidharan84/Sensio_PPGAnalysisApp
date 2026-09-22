import 'dart:math' as math;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import '../theme.dart';
import '../../core/models/ppg_models.dart';
import '../../core/utils/time_formatter.dart';

class HrvTrendsChart extends StatefulWidget {
  final TimeResolvedHrvResult hrvResult;
  final ValueChanged<double>? onSelectTimestamp;
  final ValueChanged<double>? onJumpToWaveform;
  final bool showClockTime;
  final double t0SecondsOfDay;
  final DateTime? sessionStart;

  const HrvTrendsChart({
    super.key,
    required this.hrvResult,
    this.onSelectTimestamp,
    this.onJumpToWaveform,
    this.showClockTime = false,
    this.t0SecondsOfDay = 0.0,
    this.sessionStart,
  });

  @override
  State<HrvTrendsChart> createState() => _HrvTrendsChartState();
}

class _HrvTrendsChartState extends State<HrvTrendsChart> {
  String _metric1 = 'MeanHR';
  String _metric2 = 'none'; // 'none' means single metric mode

  // Zoom & Pan State
  double? _visibleStartS;
  double? _visibleEndS;
  double _verticalGain = 1.0;
  double _verticalPanFraction = 0.0;

  // Inspected Point
  double? _inspectedTs;

  // Interaction tracking
  double? _baseStartS;
  double? _baseEndS;
  double _baseGain = 1.0;

  static const Map<String, List<String>> _domainMetrics = {
    'Vitals & Activity': ['Skin_Temperature', 'Activity_Motion'],
    'Time Domain': ['MeanHR', 'MeanNN', 'SDNN', 'RMSSD', 'pNN50', 'pNN20', 'CVNN'],
    'Frequency Domain': ['LF', 'HF', 'LF_HF', 'LFn', 'HFn', 'VLF', 'Total_Power'],
    'Non-Linear': ['SD1', 'SD2', 'SD1_SD2', 'CSI', 'CVI', 'SampEn'],
    'Morphology': [
      'Morphology_Quality',
      'APG_b_a_Ratio',
      'APG_c_a_Ratio',
      'APG_d_a_Ratio',
      'APG_e_a_Ratio',
      'Morph_Pulse_Amp',
      'Morph_SD_Time_Ratio',
    ],
  };

  double get _totalStartS =>
      widget.hrvResult.timestamps.isNotEmpty ? widget.hrvResult.timestamps.first : 0.0;
  double get _totalEndS =>
      widget.hrvResult.timestamps.isNotEmpty ? widget.hrvResult.timestamps.last : 1.0;
  double get _totalDurationS => math.max(_totalEndS - _totalStartS, 1.0);

  double get _currentStartS => _visibleStartS ?? _totalStartS;
  double get _currentEndS => _visibleEndS ?? _totalEndS;
  double get _currentSpanS => math.max(_currentEndS - _currentStartS, 10.0);

  bool get _isTimeZoomed =>
      _visibleStartS != null || _visibleEndS != null;

  bool get _isZoomed =>
      _isTimeZoomed ||
      (_verticalGain - 1.0).abs() > 0.05 ||
      _verticalPanFraction.abs() > 0.02;

  void _resetZoom() {
    setState(() {
      _visibleStartS = null;
      _visibleEndS = null;
      _verticalGain = 1.0;
      _verticalPanFraction = 0.0;
      _inspectedTs = null;
    });
  }

  void _zoomTime(double factor, {double focalFrac = 0.5}) {
    setState(() {
      final curStart = _currentStartS;
      final curEnd = _currentEndS;
      final curSpan = curEnd - curStart;

      final newSpan = (curSpan / factor).clamp(15.0, _totalDurationS);
      final focalTime = curStart + curSpan * focalFrac;

      var newStart = focalTime - newSpan * focalFrac;
      var newEnd = newStart + newSpan;

      if (newStart < _totalStartS) {
        newStart = _totalStartS;
        newEnd = math.min(_totalEndS, newStart + newSpan);
      }
      if (newEnd > _totalEndS) {
        newEnd = _totalEndS;
        newStart = math.max(_totalStartS, newEnd - newSpan);
      }

      if ((newSpan - _totalDurationS).abs() < 1.0) {
        _visibleStartS = null;
        _visibleEndS = null;
      } else {
        _visibleStartS = newStart;
        _visibleEndS = newEnd;
      }
    });
  }

  void _panTime(double deltaS) {
    if (!_isTimeZoomed) return;
    setState(() {
      final curSpan = _currentSpanS;
      var newStart = _currentStartS + deltaS;
      var newEnd = newStart + curSpan;

      if (newStart < _totalStartS) {
        newStart = _totalStartS;
        newEnd = newStart + curSpan;
      }
      if (newEnd > _totalEndS) {
        newEnd = _totalEndS;
        newStart = newEnd - curSpan;
      }

      _visibleStartS = newStart;
      _visibleEndS = newEnd;
    });
  }

  void _setTimePreset(double durationS) {
    setState(() {
      if (durationS >= _totalDurationS) {
        _visibleStartS = null;
        _visibleEndS = null;
      } else {
        final curCenter = (_currentStartS + _currentEndS) / 2.0;
        var newStart = curCenter - durationS / 2.0;
        var newEnd = newStart + durationS;
        if (newStart < _totalStartS) {
          newStart = _totalStartS;
          newEnd = newStart + durationS;
        }
        if (newEnd > _totalEndS) {
          newEnd = _totalEndS;
          newStart = math.max(_totalStartS, newEnd - durationS);
        }
        _visibleStartS = newStart;
        _visibleEndS = newEnd;
      }
    });
  }

  void _adjustVerticalGain(double factor) {
    setState(() {
      _verticalGain = (_verticalGain * factor).clamp(0.4, 15.0);
    });
  }

  List<DropdownMenuItem<String>> _buildMetricDropdownItems({required bool isOverlay}) {
    final items = <DropdownMenuItem<String>>[];

    if (isOverlay) {
      items.add(
        const DropdownMenuItem<String>(
          value: 'none',
          child: Text('None (Single Metric)', style: TextStyle(color: Colors.white54, fontSize: 13)),
        ),
      );
    }

    for (final entry in _domainMetrics.entries) {
      final available = entry.value.where((m) => widget.hrvResult.metrics.containsKey(m)).toList();
      if (available.isEmpty) continue;

      items.add(
        DropdownMenuItem<String>(
          enabled: false,
          value: '__cat_${entry.key}__',
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Text(
              '— ${entry.key.toUpperCase()} —',
              style: TextStyle(
                color: isOverlay ? SensioTheme.rejectNoise : SensioTheme.accent,
                fontWeight: FontWeight.bold,
                fontSize: 11,
                letterSpacing: 1.1,
              ),
            ),
          ),
        ),
      );

      for (final metric in available) {
        String label = metric;
        if (metric == 'Skin_Temperature') label = 'Skin Temperature (°C)';
        if (metric == 'Activity_Motion') label = 'Activity / Motion';

        items.add(
          DropdownMenuItem<String>(
            value: metric,
            child: Padding(
              padding: const EdgeInsets.only(left: 10),
              child: Text(
                label,
                style: const TextStyle(fontSize: 13, color: Colors.white),
              ),
            ),
          ),
        );
      }
    }

    return items;
  }

  @override
  Widget build(BuildContext context) {
    final values1 = widget.hrvResult.metrics[_metric1] ?? [];
    final values2 = (_metric2 != 'none') ? (widget.hrvResult.metrics[_metric2] ?? []) : <double>[];

    return Column(
      children: [
        // 1. Metric Selectors Row: Primary Feature & Overlay Feature
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: SensioTheme.surface,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: SensioTheme.border.withValues(alpha: 0.4)),
          ),
          child: Row(
            children: [
              // Feature 1 (Primary / Left Axis, Cyan)
              Expanded(
                child: Row(
                  children: [
                    Container(
                      width: 9,
                      height: 9,
                      decoration: const BoxDecoration(
                        color: SensioTheme.accent,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    const Text(
                      'Primary (Left):',
                      style: TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: _metric1,
                          isExpanded: true,
                          dropdownColor: SensioTheme.surface,
                          style: const TextStyle(color: SensioTheme.accent, fontWeight: FontWeight.bold, fontSize: 12),
                          items: _buildMetricDropdownItems(isOverlay: false),
                          onChanged: (newVal) {
                            if (newVal != null && !newVal.startsWith('__cat_')) {
                              setState(() => _metric1 = newVal);
                            }
                          },
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(width: 12),
              Container(width: 1, height: 24, color: SensioTheme.border.withValues(alpha: 0.5)),
              const SizedBox(width: 12),

              // Feature 2 (Secondary / Overlay / Right Axis, Amber)
              Expanded(
                child: Row(
                  children: [
                    Container(
                      width: 9,
                      height: 9,
                      decoration: BoxDecoration(
                        color: _metric2 != 'none' ? SensioTheme.rejectNoise : Colors.white30,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    const Text(
                      'Overlay (Right):',
                      style: TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: _metric2,
                          isExpanded: true,
                          dropdownColor: SensioTheme.surface,
                          style: TextStyle(
                            color: _metric2 != 'none' ? SensioTheme.rejectNoise : Colors.white60,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                          items: _buildMetricDropdownItems(isOverlay: true),
                          onChanged: (newVal) {
                            if (newVal != null && !newVal.startsWith('__cat_')) {
                              setState(() => _metric2 = newVal);
                            }
                          },
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 6),

        // 2. 2D Zoom & Pan Toolbar (Responsive Wrap / Row)
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: const Color(0xFF131C2E),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: SensioTheme.border.withValues(alpha: 0.3)),
          ),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final isNarrow = constraints.maxWidth < 750;

              final timeZoomRow = Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.schedule, size: 14, color: Colors.white54),
                  const SizedBox(width: 4),
                  const Text('Time Zoom:', style: TextStyle(color: Colors.white60, fontSize: 11)),
                  IconButton(
                    icon: const Icon(Icons.remove, size: 14),
                    color: Colors.white70,
                    tooltip: 'Zoom Out Time (wider span)',
                    padding: const EdgeInsets.all(4),
                    constraints: const BoxConstraints(),
                    onPressed: () => _zoomTime(0.7),
                  ),
                  IconButton(
                    icon: const Icon(Icons.add, size: 14),
                    color: SensioTheme.accent,
                    tooltip: 'Zoom In Time (narrow span)',
                    padding: const EdgeInsets.all(4),
                    constraints: const BoxConstraints(),
                    onPressed: () => _zoomTime(1.4),
                  ),
                  const SizedBox(width: 4),
                  ...[
                    {'label': '15m', 'sec': 900.0},
                    {'label': '30m', 'sec': 1800.0},
                    {'label': '1h', 'sec': 3600.0},
                    {'label': '4h', 'sec': 14400.0},
                    {'label': 'All', 'sec': _totalDurationS},
                  ].map((preset) {
                    final sec = preset['sec'] as double;
                    final isSel = (_currentSpanS - sec).abs() < 60.0 ||
                        (sec == _totalDurationS && _visibleStartS == null && _visibleEndS == null);
                    return Padding(
                      padding: const EdgeInsets.only(left: 3),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(4),
                        onTap: () => _setTimePreset(sec),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                          decoration: BoxDecoration(
                            color: isSel ? SensioTheme.accent.withValues(alpha: 0.25) : Colors.transparent,
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(
                              color: isSel ? SensioTheme.accent : SensioTheme.border.withValues(alpha: 0.3),
                            ),
                          ),
                          child: Text(
                            preset['label'] as String,
                            style: TextStyle(
                              color: isSel ? SensioTheme.accent : Colors.white70,
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

              final yZoomRow = Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.height, size: 14, color: Colors.white54),
                  const SizedBox(width: 4),
                  const Text('Y-Axis:', style: TextStyle(color: Colors.white60, fontSize: 11)),
                  IconButton(
                    icon: const Icon(Icons.remove, size: 14),
                    color: Colors.white70,
                    tooltip: 'Zoom Out Y-scale',
                    padding: const EdgeInsets.all(4),
                    constraints: const BoxConstraints(),
                    onPressed: () => _adjustVerticalGain(0.8),
                  ),
                  IconButton(
                    icon: const Icon(Icons.add, size: 14),
                    color: SensioTheme.accent,
                    tooltip: 'Zoom In Y-scale',
                    padding: const EdgeInsets.all(4),
                    constraints: const BoxConstraints(),
                    onPressed: () => _adjustVerticalGain(1.25),
                  ),
                  const SizedBox(width: 4),
                  ...[1.0, 2.0, 4.0].map((preset) {
                    final isSel = (_verticalGain - preset).abs() < 0.1;
                    return Padding(
                      padding: const EdgeInsets.only(left: 3),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(4),
                        onTap: () => setState(() => _verticalGain = preset),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                          decoration: BoxDecoration(
                            color: isSel ? SensioTheme.accent.withValues(alpha: 0.25) : Colors.transparent,
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(
                              color: isSel ? SensioTheme.accent : SensioTheme.border.withValues(alpha: 0.3),
                            ),
                          ),
                          child: Text(
                            '${preset.toInt()}x',
                            style: TextStyle(
                              color: isSel ? SensioTheme.accent : Colors.white70,
                              fontSize: 10,
                              fontWeight: isSel ? FontWeight.bold : FontWeight.normal,
                            ),
                          ),
                        ),
                      ),
                    );
                  }),
                  if (_isZoomed) ...[
                    const SizedBox(width: 8),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: SensioTheme.surface,
                        foregroundColor: SensioTheme.accent,
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        minimumSize: Size.zero,
                        side: const BorderSide(color: SensioTheme.accent, width: 0.8),
                      ),
                      icon: const Icon(Icons.refresh, size: 11),
                      label: const Text('Reset', style: TextStyle(fontSize: 10)),
                      onPressed: _resetZoom,
                    ),
                  ],
                ],
              );

              if (isNarrow) {
                return SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      timeZoomRow,
                      const SizedBox(width: 12),
                      yZoomRow,
                    ],
                  ),
                );
              } else {
                return Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    timeZoomRow,
                    yZoomRow,
                  ],
                );
              }
            },
          ),
        ),
        const SizedBox(height: 4),

        // 3. Dedicated Timeline Scrollbar & Scrubber (Appears when zoomed in time)
        if (_isTimeZoomed)
          Container(
            margin: const EdgeInsets.only(bottom: 4),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: const Color(0xFF0F172A),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: SensioTheme.border.withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.chevron_left, size: 18, color: Colors.white70),
                  tooltip: 'Scroll back in time',
                  padding: const EdgeInsets.all(2),
                  constraints: const BoxConstraints(),
                  onPressed: () => _panTime(-_currentSpanS * 0.25),
                ),
                Expanded(
                  child: SliderTheme(
                    data: SliderThemeData(
                      trackHeight: 4,
                      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                      activeTrackColor: SensioTheme.accent,
                      inactiveTrackColor: const Color(0xFF1E293B),
                      thumbColor: Colors.white,
                      overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
                    ),
                    child: Slider(
                      value: _currentStartS.clamp(
                        _totalStartS,
                        math.max(_totalStartS, _totalEndS - _currentSpanS),
                      ),
                      min: _totalStartS,
                      max: math.max(_totalStartS, _totalEndS - _currentSpanS),
                      onChanged: (newStart) {
                        setState(() {
                          _visibleStartS = newStart;
                          _visibleEndS = newStart + _currentSpanS;
                        });
                      },
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.chevron_right, size: 18, color: Colors.white70),
                  tooltip: 'Scroll forward in time',
                  padding: const EdgeInsets.all(2),
                  constraints: const BoxConstraints(),
                  onPressed: () => _panTime(_currentSpanS * 0.25),
                ),
                const SizedBox(width: 6),
                Text(
                  '${TimeFormatter.formatSeconds(_currentStartS, clockTime: widget.showClockTime, sessionStart: widget.sessionStart, t0SecondsOfDay: widget.t0SecondsOfDay)} → ${TimeFormatter.formatSeconds(_currentEndS, clockTime: widget.showClockTime, sessionStart: widget.sessionStart, t0SecondsOfDay: widget.t0SecondsOfDay)}',
                  style: const TextStyle(
                    color: Colors.white60,
                    fontSize: 10,
                    fontFamily: 'monospace',
                  ),
                ),
              ],
            ),
          ),

        // 4. Interactive Inspection Banner (When a point is tapped/clicked)
        if (_inspectedTs != null)
          _buildInspectionBanner(values1, values2),

        // 5. Interactive Trend Lines Canvas (with Drag-to-Scroll, Pinch Zoom, Tap-to-Inspect)
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              color: const Color(0xFF090D16),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: SensioTheme.border.withValues(alpha: 0.4)),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final chartLeft = 55.0;
                  final chartRight = constraints.maxWidth - (_metric2 != 'none' ? 55.0 : 20.0);
                  final chartWidth = chartRight - chartLeft;

                  return Listener(
                    onPointerSignal: (pointerSignal) {
                      if (pointerSignal is PointerScrollEvent) {
                        final dx = pointerSignal.scrollDelta.dx;
                        final dy = pointerSignal.scrollDelta.dy;

                        // Scroll wheel horizontal pans time; vertical scrolls or zooms
                        if (dx != 0.0 && chartWidth > 0) {
                          final panS = (dx / chartWidth) * _currentSpanS * 0.5;
                          _panTime(panS);
                        } else if (dy != 0.0) {
                          _adjustVerticalGain(dy < 0 ? 1.15 : 0.87);
                        }
                      }
                    },
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onDoubleTap: _resetZoom,
                      onScaleStart: (details) {
                        _baseStartS = _currentStartS;
                        _baseEndS = _currentEndS;
                        _baseGain = _verticalGain;
                      },
                      onScaleUpdate: (details) {
                        // Horizontal Pinch: Scale Time
                        if (details.horizontalScale != 1.0 && _baseStartS != null && _baseEndS != null) {
                          final baseSpan = _baseEndS! - _baseStartS!;
                          final focalRatio = ((details.localFocalPoint.dx - chartLeft) / chartWidth).clamp(0.0, 1.0);
                          final newSpan = (baseSpan / details.horizontalScale).clamp(15.0, _totalDurationS);

                          var newStart = (_baseStartS! + baseSpan * focalRatio) - newSpan * focalRatio;
                          var newEnd = newStart + newSpan;
                          if (newStart < _totalStartS) {
                            newStart = _totalStartS;
                            newEnd = newStart + newSpan;
                          }
                          if (newEnd > _totalEndS) {
                            newEnd = _totalEndS;
                            newStart = newEnd - newSpan;
                          }
                          setState(() {
                            _visibleStartS = newStart;
                            _visibleEndS = newEnd;
                          });
                        }

                        // Vertical Pinch: Scale Amplitude
                        if (details.verticalScale != 1.0) {
                          setState(() {
                            _verticalGain = (_baseGain * details.verticalScale).clamp(0.4, 15.0);
                          });
                        }

                        // 1-finger / Mouse Drag: Smoothly Pan Time & Vertical Amplitude
                        if (details.scale == 1.0) {
                          if (details.focalPointDelta.dx != 0.0 && chartWidth > 0) {
                            final deltaS = -(details.focalPointDelta.dx / chartWidth) * _currentSpanS;
                            _panTime(deltaS);
                          }
                          if (details.focalPointDelta.dy != 0.0) {
                            setState(() {
                              _verticalPanFraction = (_verticalPanFraction + details.focalPointDelta.dy / 250.0).clamp(-1.0, 1.0);
                            });
                          }
                        }
                      },
                      onTapUp: (details) {
                        // Tapping selects/inspects point without forcing a tab navigation!
                        if (chartWidth <= 0 || widget.hrvResult.timestamps.isEmpty) return;
                        final tapX = details.localPosition.dx.clamp(chartLeft, chartRight);
                        final frac = (tapX - chartLeft) / chartWidth;
                        final selectedTs = _currentStartS + frac * (_currentEndS - _currentStartS);

                        setState(() {
                          _inspectedTs = selectedTs;
                        });
                        widget.onSelectTimestamp?.call(selectedTs);
                      },
                      child: CustomPaint(
                        size: Size.infinite,
                        painter: _DualTrendChartPainter(
                          timestamps: widget.hrvResult.timestamps,
                          values1: values1,
                          metric1: _metric1,
                          values2: values2,
                          metric2: _metric2,
                          visibleStartS: _currentStartS,
                          visibleEndS: _currentEndS,
                          verticalGain: _verticalGain,
                          verticalPanFraction: _verticalPanFraction,
                          showClockTime: widget.showClockTime,
                          t0SecondsOfDay: widget.t0SecondsOfDay,
                          sessionStart: widget.sessionStart,
                          inspectedTs: _inspectedTs,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildInspectionBanner(List<double> values1, List<double> values2) {
    final ts = _inspectedTs!;
    final timeStr = TimeFormatter.formatSeconds(
      ts,
      clockTime: widget.showClockTime,
      sessionStart: widget.sessionStart,
      t0SecondsOfDay: widget.t0SecondsOfDay,
      includeDate: widget.showClockTime,
      showMillis: true,
    );

    // Find closest sample index
    int closestIdx = 0;
    double closestDiff = double.infinity;
    for (int i = 0; i < widget.hrvResult.timestamps.length; i++) {
      final diff = (widget.hrvResult.timestamps[i] - ts).abs();
      if (diff < closestDiff) {
        closestDiff = diff;
        closestIdx = i;
      }
    }

    final val1 = closestIdx < values1.length ? values1[closestIdx] : double.nan;
    final val2 = closestIdx < values2.length ? values2[closestIdx] : double.nan;

    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: SensioTheme.accent.withValues(alpha: 0.5)),
      ),
      child: Row(
        children: [
          const Icon(Icons.location_on, size: 14, color: SensioTheme.accent),
          const SizedBox(width: 4),
          Text(
            timeStr,
            style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold, fontFamily: 'monospace'),
          ),
          const SizedBox(width: 10),
          Text(
            '$_metric1: ${val1.isFinite ? (_metric1 == 'Skin_Temperature' ? '${val1.toStringAsFixed(2)} °C' : val1.toStringAsFixed(2)) : '-'}',
            style: const TextStyle(color: SensioTheme.accent, fontSize: 11, fontWeight: FontWeight.bold),
          ),
          if (_metric2 != 'none') ...[
            const SizedBox(width: 10),
            Text(
              '$_metric2: ${val2.isFinite ? (_metric2 == 'Skin_Temperature' ? '${val2.toStringAsFixed(2)} °C' : val2.toStringAsFixed(2)) : '-'}',
              style: const TextStyle(color: SensioTheme.rejectNoise, fontSize: 11, fontWeight: FontWeight.bold),
            ),
          ],
          const Spacer(),
          if (widget.onJumpToWaveform != null) ...[
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: SensioTheme.accent.withValues(alpha: 0.2),
                foregroundColor: SensioTheme.accent,
                side: const BorderSide(color: SensioTheme.accent, width: 0.8),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                minimumSize: Size.zero,
              ),
              icon: const Icon(Icons.open_in_new, size: 11),
              label: const Text('View in Waveform', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
              onPressed: () => widget.onJumpToWaveform!(ts),
            ),
            const SizedBox(width: 6),
          ],
          InkWell(
            onTap: () => setState(() => _inspectedTs = null),
            child: const Icon(Icons.close, size: 14, color: Colors.white54),
          ),
        ],
      ),
    );
  }
}

class _DualTrendChartPainter extends CustomPainter {
  final List<double> timestamps;
  final List<double> values1;
  final String metric1;
  final List<double> values2;
  final String metric2;
  final double visibleStartS;
  final double visibleEndS;
  final double verticalGain;
  final double verticalPanFraction;
  final bool showClockTime;
  final double t0SecondsOfDay;
  final DateTime? sessionStart;
  final double? inspectedTs;

  _DualTrendChartPainter({
    required this.timestamps,
    required this.values1,
    required this.metric1,
    required this.values2,
    required this.metric2,
    required this.visibleStartS,
    required this.visibleEndS,
    required this.verticalGain,
    required this.verticalPanFraction,
    required this.showClockTime,
    required this.t0SecondsOfDay,
    this.sessionStart,
    this.inspectedTs,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (timestamps.isEmpty || values1.isEmpty) return;

    final hasSecondary = metric2 != 'none' && values2.isNotEmpty;

    // Chart margins
    final leftMargin = 55.0;
    final rightMargin = hasSecondary ? 55.0 : 20.0;
    final topMargin = 28.0;
    final bottomMargin = 26.0;

    final plotWidth = size.width - leftMargin - rightMargin;
    final plotHeight = size.height - topMargin - bottomMargin;
    if (plotWidth <= 0 || plotHeight <= 0) return;

    final tMin = visibleStartS;
    final tMax = visibleEndS;
    final tRange = math.max(tMax - tMin, 1.0);

    // Compute range for Metric 1
    double minVal1 = double.infinity;
    double maxVal1 = -double.infinity;
    final validPoints1 = <int>[];
    for (int i = 0; i < values1.length; i++) {
      final t = timestamps[i];
      if (t >= tMin - 30.0 && t <= tMax + 30.0) {
        final v = values1[i];
        if (v.isFinite) {
          validPoints1.add(i);
          if (v < minVal1) minVal1 = v;
          if (v > maxVal1) maxVal1 = v;
        }
      }
    }

    if (validPoints1.isEmpty) {
      final tp = TextPainter(
        text: const TextSpan(
          text: 'No valid sliding-window samples in this time window',
          style: TextStyle(color: Colors.white54, fontSize: 13),
        ),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: size.width - 32);
      tp.paint(canvas, Offset((size.width - tp.width) / 2, (size.height - tp.height) / 2));
      return;
    }

    final span1 = math.max((maxVal1 - minVal1).abs(), 1e-4);
    final midVal1 = (minVal1 + maxVal1) / 2.0 + verticalPanFraction * span1;
    final effectiveSpan1 = (span1 * 1.3) / verticalGain;
    final lower1 = midVal1 - effectiveSpan1 / 2.0;
    final upper1 = midVal1 + effectiveSpan1 / 2.0;
    final range1 = upper1 - lower1;

    // Compute range for Metric 2 (if present)
    double lower2 = 0.0;
    double upper2 = 1.0;
    double range2 = 1.0;
    final validPoints2 = <int>[];

    if (hasSecondary) {
      double minVal2 = double.infinity;
      double maxVal2 = -double.infinity;
      for (int i = 0; i < values2.length; i++) {
        final t = timestamps[i];
        if (t >= tMin - 30.0 && t <= tMax + 30.0) {
          final v = values2[i];
          if (v.isFinite) {
            validPoints2.add(i);
            if (v < minVal2) minVal2 = v;
            if (v > maxVal2) maxVal2 = v;
          }
        }
      }
      if (validPoints2.isNotEmpty) {
        final span2 = math.max((maxVal2 - minVal2).abs(), 1e-4);
        final midVal2 = (minVal2 + maxVal2) / 2.0 + verticalPanFraction * span2;
        final effectiveSpan2 = (span2 * 1.3) / verticalGain;
        lower2 = midVal2 - effectiveSpan2 / 2.0;
        upper2 = midVal2 + effectiveSpan2 / 2.0;
        range2 = upper2 - lower2;
      }
    }

    // Draw background horizontal grid lines and Y-axis tick labels
    final gridPaint = Paint()
      ..color = const Color(0xFF1E293B).withValues(alpha: 0.5)
      ..strokeWidth = 1.0;

    const numYDivisions = 4;
    for (int i = 0; i <= numYDivisions; i++) {
      final y = topMargin + plotHeight * (i / numYDivisions);
      canvas.drawLine(Offset(leftMargin, y), Offset(size.width - rightMargin, y), gridPaint);

      // Metric 1 Y-axis labels (Left Axis, Cyan)
      final val1 = upper1 - (i / numYDivisions) * range1;
      final val1Str = _formatMetricVal(val1);
      final tp1 = TextPainter(
        text: TextSpan(
          text: val1Str,
          style: const TextStyle(color: SensioTheme.accent, fontSize: 10, fontFamily: 'monospace'),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp1.paint(canvas, Offset(leftMargin - tp1.width - 6, y - tp1.height / 2));

      // Metric 2 Y-axis labels (Right Axis, Amber)
      if (hasSecondary && validPoints2.isNotEmpty) {
        final val2 = upper2 - (i / numYDivisions) * range2;
        final val2Str = _formatMetricVal(val2);
        final tp2 = TextPainter(
          text: TextSpan(
            text: val2Str,
            style: const TextStyle(color: SensioTheme.rejectNoise, fontSize: 10, fontFamily: 'monospace'),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        tp2.paint(canvas, Offset(size.width - rightMargin + 6, y - tp2.height / 2));
      }
    }

    // Top Legend & Zoom Badge
    _drawLegend(canvas, size, leftMargin, hasSecondary);

    // Draw Metric 1 (Cyan)
    final linePaint1 = Paint()
      ..color = SensioTheme.accent
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..strokeCap = StrokeCap.round
      ..isAntiAlias = true;

    final dotPaint1 = Paint()
      ..color = SensioTheme.accent
      ..style = PaintingStyle.fill;

    _drawSeries(
      canvas: canvas,
      timestamps: timestamps,
      values: values1,
      validPoints: validPoints1,
      tMin: tMin,
      tRange: tRange,
      leftMargin: leftMargin,
      plotWidth: plotWidth,
      topMargin: topMargin,
      plotHeight: plotHeight,
      lower: lower1,
      range: range1,
      linePaint: linePaint1,
      dotPaint: dotPaint1,
    );

    // Draw Metric 2 (Amber, if active)
    if (hasSecondary && validPoints2.isNotEmpty) {
      final linePaint2 = Paint()
        ..color = SensioTheme.rejectNoise
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0
        ..strokeCap = StrokeCap.round
        ..isAntiAlias = true;

      final dotPaint2 = Paint()
        ..color = SensioTheme.rejectNoise
        ..style = PaintingStyle.fill;

      _drawSeries(
        canvas: canvas,
        timestamps: timestamps,
        values: values2,
        validPoints: validPoints2,
        tMin: tMin,
        tRange: tRange,
        leftMargin: leftMargin,
        plotWidth: plotWidth,
        topMargin: topMargin,
        plotHeight: plotHeight,
        lower: lower2,
        range: range2,
        linePaint: linePaint2,
        dotPaint: dotPaint2,
      );
    }

    // Draw Inspected Point Cursor Line (if any)
    if (inspectedTs != null && inspectedTs! >= tMin && inspectedTs! <= tMax) {
      final cursorX = leftMargin + ((inspectedTs! - tMin) / tRange) * plotWidth;
      final cursorPaint = Paint()
        ..color = Colors.white60
        ..strokeWidth = 1.2
        ..style = PaintingStyle.stroke;

      // Vertical dashed line
      for (double dy = topMargin; dy < topMargin + plotHeight; dy += 8) {
        canvas.drawLine(Offset(cursorX, dy), Offset(cursorX, math.min(dy + 4, topMargin + plotHeight)), cursorPaint);
      }
    }

    // X-Axis Time Ticks with Date / Time formatting
    const numTimeTicks = 5;
    for (int i = 0; i < numTimeTicks; i++) {
      final frac = i / (numTimeTicks - 1);
      final x = leftMargin + frac * plotWidth;
      final ts = tMin + frac * tRange;

      final includeDate = showClockTime && (tRange > 3600.0 * 12.0 || (sessionStart != null && sessionStart!.day != sessionStart!.add(Duration(seconds: ts.round())).day));

      final timeStr = TimeFormatter.formatSeconds(
        ts,
        clockTime: showClockTime,
        sessionStart: sessionStart,
        t0SecondsOfDay: t0SecondsOfDay,
        includeDate: includeDate,
        showMillis: false,
      );

      final tp = TextPainter(
        text: TextSpan(
          text: timeStr,
          style: const TextStyle(color: Colors.white38, fontSize: 10, fontFamily: 'monospace'),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(x - tp.width / 2, size.height - bottomMargin + 6));
    }
  }

  void _drawSeries({
    required Canvas canvas,
    required List<double> timestamps,
    required List<double> values,
    required List<int> validPoints,
    required double tMin,
    required double tRange,
    required double leftMargin,
    required double plotWidth,
    required double topMargin,
    required double plotHeight,
    required double lower,
    required double range,
    required Paint linePaint,
    required Paint dotPaint,
  }) {
    canvas.save();
    canvas.clipRect(Rect.fromLTWH(leftMargin - 2, topMargin - 2, plotWidth + 4, plotHeight + 4));

    Path? path;
    int? lastIdx;

    for (final i in validPoints) {
      final x = leftMargin + ((timestamps[i] - tMin) / tRange) * plotWidth;
      final y = topMargin + plotHeight - ((values[i] - lower) / range) * plotHeight;

      canvas.drawCircle(Offset(x, y), 2.8, dotPaint);

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

    canvas.restore();
  }

  void _drawLegend(Canvas canvas, Size size, double leftMargin, bool hasSecondary) {
    final text1 = '● $metric1 (Left Axis)';
    final tp1 = TextPainter(
      text: TextSpan(
        text: text1,
        style: const TextStyle(color: SensioTheme.accent, fontSize: 11, fontWeight: FontWeight.bold),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp1.paint(canvas, Offset(leftMargin, 8));

    if (hasSecondary) {
      final text2 = '● $metric2 (Right Axis)';
      final tp2 = TextPainter(
        text: TextSpan(
          text: text2,
          style: const TextStyle(color: SensioTheme.rejectNoise, fontSize: 11, fontWeight: FontWeight.bold),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp2.paint(canvas, Offset(leftMargin + tp1.width + 20, 8));
    }

    // Zoom Level badge on top right
    final zoomStr = 'Zoom: ${((timestamps.last - timestamps.first) / (visibleEndS - visibleStartS)).toStringAsFixed(1)}x Time • ${verticalGain.toStringAsFixed(1)}x Y';
    final tpZoom = TextPainter(
      text: TextSpan(
        text: zoomStr,
        style: const TextStyle(color: Colors.white30, fontSize: 10, fontFamily: 'monospace'),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tpZoom.paint(canvas, Offset(size.width - (hasSecondary ? 55.0 : 20.0) - tpZoom.width, 8));
  }

  String _formatMetricVal(double v) {
    if (v.abs() >= 1000) {
      return v.toStringAsFixed(0);
    } else if (v.abs() >= 100) {
      return v.toStringAsFixed(1);
    } else if (v.abs() >= 1) {
      return v.toStringAsFixed(2);
    } else {
      return v.toStringAsFixed(3);
    }
  }

  @override
  bool shouldRepaint(covariant _DualTrendChartPainter oldDelegate) {
    return oldDelegate.metric1 != metric1 ||
        oldDelegate.metric2 != metric2 ||
        oldDelegate.visibleStartS != visibleStartS ||
        oldDelegate.visibleEndS != visibleEndS ||
        oldDelegate.verticalGain != verticalGain ||
        oldDelegate.verticalPanFraction != verticalPanFraction ||
        oldDelegate.showClockTime != showClockTime ||
        oldDelegate.sessionStart != sessionStart ||
        oldDelegate.t0SecondsOfDay != t0SecondsOfDay ||
        oldDelegate.inspectedTs != inspectedTs ||
        oldDelegate.values1.length != values1.length ||
        oldDelegate.values2.length != values2.length;
  }
}
