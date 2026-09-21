import 'package:flutter/material.dart';
import '../theme.dart';
import '../../core/models/ppg_models.dart';

class TimelineRibbon extends StatelessWidget {
  final List<ContinuousSegment> segments;
  final double totalDurationS;
  final double currentStartS;
  final double windowDurationS;
  final ValueChanged<double> onSeek;

  const TimelineRibbon({
    super.key,
    required this.segments,
    required this.totalDurationS,
    required this.currentStartS,
    required this.windowDurationS,
    required this.onSeek,
  });

  @override
  Widget build(BuildContext context) {
    if (totalDurationS <= 0) return const SizedBox.shrink();

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (details) {
            final tapX = details.localPosition.dx.clamp(0.0, width);
            final targetS = (tapX / width) * totalDurationS;
            onSeek(targetS.clamp(0.0, (totalDurationS - windowDurationS).clamp(0.0, totalDurationS)));
          },
          onHorizontalDragUpdate: (details) {
            final tapX = details.localPosition.dx.clamp(0.0, width);
            final targetS = (tapX / width) * totalDurationS;
            onSeek(targetS.clamp(0.0, (totalDurationS - windowDurationS).clamp(0.0, totalDurationS)));
          },
          child: Container(
            height: 36,
            decoration: BoxDecoration(
              color: SensioTheme.surface,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: SensioTheme.border.withValues(alpha: 0.5)),
            ),
            clipBehavior: Clip.antiAlias,
            child: Stack(
              children: [
                // Render segments
                Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: segments.map((seg) {
                    final fraction = (seg.durationS / totalDurationS).clamp(0.0, 1.0);
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

                // Active window viewport indicator
                Positioned(
                  left: (currentStartS / totalDurationS) * width,
                  width: ((windowDurationS / totalDurationS) * width).clamp(6.0, width),
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
              ],
            ),
          ),
        );
      },
    );
  }
}
