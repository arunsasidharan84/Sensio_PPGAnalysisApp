import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import '../ffi_bindings.dart';
import '../models/ppg_models.dart';

class AnalysisRequest {
  final String ppgPath;
  final String? sigmotPath;
  final double sampleRate;

  AnalysisRequest({
    required this.ppgPath,
    this.sigmotPath,
    this.sampleRate = 50.0,
  });
}

class PPGAnalysisService {
  static String? findMatchingSigmot(String ppgPath) {
    final ppgFile = File(ppgPath);
    final dir = ppgFile.parent;
    final name = ppgFile.uri.pathSegments.last;

    if (name.contains('_ppg_data.csv')) {
      final sigmotName = name.replaceAll('_ppg_data.csv', '_sigmot_data.csv');
      final candidate = File('${dir.path}/$sigmotName');
      if (candidate.existsSync()) {
        return candidate.path;
      }
    }
    return null;
  }

  /// Run session analysis in a background isolate for smooth 120fps UI
  static Future<SessionAnalysisResult> analyzeFile(
    String ppgPath, {
    String? sigmotPath,
    double sampleRate = 50.0,
  }) async {
    final resolvedSigmot = sigmotPath ?? findMatchingSigmot(ppgPath);

    final req = AnalysisRequest(
      ppgPath: ppgPath,
      sigmotPath: resolvedSigmot,
      sampleRate: sampleRate,
    );

    return compute(_isolateAnalyze, req);
  }

  static SessionAnalysisResult _isolateAnalyze(AnalysisRequest req) {
    final bindings = SensioNativeBindings.tryLoad();
    if (bindings == null) {
      throw Exception('Failed to load native sensio_ppg_core library.');
    }

    final jsonStr = bindings.processFile(
      req.ppgPath,
      sigmotPath: req.sigmotPath,
      sampleRate: req.sampleRate,
    );

    final dynamic decoded = jsonDecode(jsonStr);
    if (decoded is! Map<String, dynamic>) {
      throw Exception('Invalid native response format');
    }

    final success = decoded['success'] as bool? ?? false;
    if (!success) {
      final err = decoded['error'] as String? ?? 'Unknown native error';
      throw Exception('Analysis failed: $err');
    }

    final data = decoded['data'] as Map<String, dynamic>?;
    if (data == null) {
      throw Exception('No analysis data returned');
    }

    return SessionAnalysisResult.fromJson(data);
  }
}
