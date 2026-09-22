import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import '../models/ppg_models.dart';
import '../utils/time_formatter.dart';

class CsvExportService {
  /// Generate the comprehensive time-series CSV string
  static String generateTimeSeriesCsv(SessionAnalysisResult result) {
    final sb = StringBuffer();
    final hrv = result.hrv;
    final timestamps = hrv.timestamps;
    final metrics = hrv.metrics;

    final metricKeys = metrics.keys.toList();

    // Headers
    sb.write('Window_Index,Elapsed_Time_s,Clock_Time');
    for (final k in metricKeys) {
      sb.write(',$k');
    }
    sb.writeln();

    for (int i = 0; i < timestamps.length; i++) {
      final ts = timestamps[i];
      final clockTimeStr = TimeFormatter.formatSeconds(
        ts,
        clockTime: true,
        sessionStart: result.sessionStartDateTime,
        t0SecondsOfDay: result.startTimeOfDayS,
        includeDate: false,
        showMillis: false,
      );

      sb.write('$i,${ts.toStringAsFixed(1)},$clockTimeStr');
      for (final k in metricKeys) {
        final valList = metrics[k];
        final val = (valList != null && i < valList.length) ? valList[i] : double.nan;
        if (val.isFinite) {
          if (k == 'Skin_Temperature') {
            sb.write(',${val.toStringAsFixed(2)}');
          } else if (val.abs() >= 100) {
            sb.write(',${val.toStringAsFixed(2)}');
          } else if (val.abs() >= 1) {
            sb.write(',${val.toStringAsFixed(3)}');
          } else {
            sb.write(',${val.toStringAsFixed(4)}');
          }
        } else {
          sb.write(',NaN');
        }
      }
      sb.writeln();
    }

    return sb.toString();
  }

  /// Generate the summary statistics CSV string
  static String generateSummaryCsv(SessionAnalysisResult result) {
    final sb = StringBuffer();
    sb.writeln('Domain,Metric,Mean,SD,Median,IQR,Min,Max,Valid_Count');
    for (final row in result.summary) {
      sb.writeln(
        '${row.domain},${row.metric},'
        '${row.mean.isFinite ? row.mean.toStringAsFixed(4) : "NaN"},'
        '${row.sd.isFinite ? row.sd.toStringAsFixed(4) : "NaN"},'
        '${row.median.isFinite ? row.median.toStringAsFixed(4) : "NaN"},'
        '${row.iqr.isFinite ? row.iqr.toStringAsFixed(4) : "NaN"},'
        '${row.minVal.isFinite ? row.minVal.toStringAsFixed(4) : "NaN"},'
        '${row.maxVal.isFinite ? row.maxVal.toStringAsFixed(4) : "NaN"},'
        '${row.count}',
      );
    }
    return sb.toString();
  }

  /// Save CSV string to a file via save dialog or fallback path
  static Future<String?> saveCsv({
    required String defaultFileName,
    required String csvContent,
    String? fallbackDirectory,
  }) async {
    try {
      if (Platform.isMacOS) {
        try {
          await FilePicker.skipEntitlementsChecks();
        } catch (_) {}
      }

      final savePath = await FilePicker.saveFile(
        dialogTitle: 'Save Analysis CSV',
        fileName: defaultFileName,
        type: FileType.custom,
        allowedExtensions: ['csv'],
      );

      if (savePath != null && savePath.isNotEmpty) {
        final targetPath = savePath.endsWith('.csv') ? savePath : '$savePath.csv';
        final file = File(targetPath);
        await file.writeAsString(csvContent);
        return file.path;
      }
    } catch (_) {
      // Fallback if save dialog fails
      if (fallbackDirectory != null) {
        final fallbackPath = '$fallbackDirectory/$defaultFileName';
        final file = File(fallbackPath);
        await file.writeAsString(csvContent);
        return file.path;
      }
    }
    return null;
  }

  /// Copy CSV content to system clipboard
  static Future<void> copyToClipboard(String content) async {
    await Clipboard.setData(ClipboardData(text: content));
  }
}
