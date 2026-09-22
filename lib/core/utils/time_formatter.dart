class TimeFormatter {
  static const List<String> _monthNames = [
    '', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
  ];

  /// Formats seconds into either clock time (with optional date) or elapsed duration
  static String formatSeconds(
    double elapsedSeconds, {
    bool clockTime = false,
    DateTime? sessionStart,
    double t0SecondsOfDay = 0.0,
    bool includeDate = false,
    bool showMillis = false,
    bool showDayOffset = true,
  }) {
    if (clockTime) {
      if (sessionStart != null) {
        final targetDt = sessionStart.add(
          Duration(milliseconds: (elapsedSeconds * 1000).round()),
        );

        final hStr = targetDt.hour.toString().padLeft(2, '0');
        final mStr = targetDt.minute.toString().padLeft(2, '0');
        final sVal = targetDt.second + targetDt.millisecond / 1000.0;
        final sStr = showMillis
            ? sVal.toStringAsFixed(1).padLeft(4, '0')
            : targetDt.second.toString().padLeft(2, '0');

        final timeStr = '$hStr:$mStr:$sStr';

        if (includeDate) {
          final monthStr = _monthNames[targetDt.month];
          final dayStr = targetDt.day.toString().padLeft(2, '0');
          return '$dayStr $monthStr $timeStr';
        }

        // If not requested full date, but has crossed midnight compared to session start
        if (showDayOffset && (targetDt.day != sessionStart.day || targetDt.month != sessionStart.month)) {
          final diffDays = targetDt.difference(DateTime(sessionStart.year, sessionStart.month, sessionStart.day)).inDays;
          if (diffDays > 0) {
            return '$timeStr (+${diffDays}d)';
          }
        }

        return timeStr;
      } else {
        final totalSec = t0SecondsOfDay + elapsedSeconds;
        final positiveSec = totalSec < 0 ? 0.0 : totalSec;
        final days = (positiveSec ~/ 86400);
        final secOfDay = positiveSec % 86400.0;

        final h = (secOfDay ~/ 3600) % 24;
        final m = (secOfDay % 3600) ~/ 60;
        final s = secOfDay % 60;

        final hStr = h.toString().padLeft(2, '0');
        final mStr = m.toString().padLeft(2, '0');
        final sStr = showMillis
            ? s.toStringAsFixed(1).padLeft(4, '0')
            : s.toInt().toString().padLeft(2, '0');

        final timeStr = '$hStr:$mStr:$sStr';
        if (showDayOffset && days > 0) {
          return '$timeStr (+${days}d)';
        }
        return timeStr;
      }
    } else {
      final totalSec = elapsedSeconds.abs();
      final h = totalSec ~/ 3600;
      final m = (totalSec % 3600) ~/ 60;
      final s = totalSec % 60;
      final mStr = m.toString().padLeft(2, '0');
      final sStr = showMillis
          ? s.toStringAsFixed(1).padLeft(4, '0')
          : s.toInt().toString().padLeft(2, '0');
      if (h > 0) {
        final hStr = h.toString().padLeft(2, '0');
        return '$hStr:$mStr:$sStr';
      } else {
        return '$mStr:$sStr';
      }
    }
  }

  /// Formats date of session: e.g. "09 Sep 2026"
  static String formatSessionDate(DateTime? dt) {
    if (dt == null) return 'Unknown Date';
    final monthStr = _monthNames[dt.month];
    final dayStr = dt.day.toString().padLeft(2, '0');
    return '$dayStr $monthStr ${dt.year}';
  }

  /// Formats full session range: e.g. "09 Sep 20:24:52 — 10 Sep 11:49:44 (15h 24m)"
  static String formatSessionSpan(DateTime? sessionStart, double totalDurationS) {
    final durH = totalDurationS ~/ 3600;
    final durM = (totalDurationS % 3600) ~/ 60;
    final durS = (totalDurationS % 60).round();
    final durStr = durH > 0 ? '${durH}h ${durM}m ${durS}s' : '${durM}m ${durS}s';

    if (sessionStart == null) {
      return 'Duration: $durStr';
    }

    final startStr = formatSeconds(0.0, clockTime: true, sessionStart: sessionStart, includeDate: true);
    final endStr = formatSeconds(totalDurationS, clockTime: true, sessionStart: sessionStart, includeDate: true);

    return '$startStr  →  $endStr  ($durStr)';
  }
}
