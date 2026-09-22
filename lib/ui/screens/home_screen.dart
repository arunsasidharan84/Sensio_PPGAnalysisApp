import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../theme.dart';
import '../../core/models/ppg_models.dart';
import '../../core/services/ppg_analysis_service.dart';
import '../../core/utils/time_formatter.dart';
import '../widgets/timeline_ribbon.dart';
import '../widgets/waveform_viewer.dart';
import '../widgets/poincare_chart.dart';
import '../widgets/hrv_trends_chart.dart';
import '../widgets/summary_table.dart';
import '../widgets/csv_explorer_widget.dart';
import '../../core/services/csv_export_service.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  String? _selectedPpgPath;
  String? _detectedSigmotPath;
  bool _isAnalyzing = false;
  String? _errorMessage;
  SessionAnalysisResult? _analysisResult;

  double _currentStartS = 0.0;
  double _windowDurationS = 30.0; // 30s default zoom
  bool _showClockTime = false; // Toggle between elapsed time and clock time

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _pickFile() async {
    try {
      if (Platform.isMacOS) {
        try {
          await FilePicker.skipEntitlementsChecks();
        } catch (_) {}
      }

      final res = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['csv'],
      );

      if (res != null && res.files.isNotEmpty && res.files.first.path != null) {
        final ppgPath = res.files.first.path!;
        final sigmotPath = PPGAnalysisService.findMatchingSigmot(ppgPath);
        setState(() {
          _selectedPpgPath = ppgPath;
          _detectedSigmotPath = sigmotPath;
          _errorMessage = null;
        });
        _runAnalysis();
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Error opening file picker: $e\n\nYou can also enter the absolute path directly.';
      });
    }
  }

  Future<void> _showManualPathDialog() async {
    final controller = TextEditingController(text: _selectedPpgPath ?? '');
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: SensioTheme.surface,
        title: const Text('Open PPG Recording by Path', style: TextStyle(color: Colors.white, fontSize: 16)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Enter the absolute path to a *_ppg_data.csv file:',
              style: TextStyle(color: Colors.white70, fontSize: 12),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              style: const TextStyle(color: Colors.white, fontSize: 12, fontFamily: 'monospace'),
              decoration: const InputDecoration(
                hintText: '/path/to/session_ppg_data.csv',
                hintStyle: TextStyle(color: Colors.white38),
                filled: true,
                fillColor: Color(0xFF0F172A),
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel', style: TextStyle(color: Colors.white60)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: SensioTheme.accent),
            onPressed: () {
              final path = controller.text.trim();
              Navigator.pop(ctx);
              if (path.isNotEmpty) {
                final file = File(path);
                if (file.existsSync()) {
                  final sigmotPath = PPGAnalysisService.findMatchingSigmot(path);
                  setState(() {
                    _selectedPpgPath = path;
                    _detectedSigmotPath = sigmotPath;
                    _errorMessage = null;
                  });
                  _runAnalysis();
                } else {
                  setState(() {
                    _errorMessage = 'File does not exist: $path';
                  });
                }
              }
            },
            child: const Text('Load & Analyze', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Future<void> _quickExportCsv({required bool isTimeSeries}) async {
    if (_analysisResult == null) return;
    try {
      final baseName = _selectedPpgPath != null
          ? _selectedPpgPath!.split('/').last.replaceAll('_ppg_data.csv', '')
          : 'sensio_session';

      final defaultFileName = isTimeSeries
          ? '${baseName}_hrv_timeseries.csv'
          : '${baseName}_hrv_summary.csv';

      final content = isTimeSeries
          ? CsvExportService.generateTimeSeriesCsv(_analysisResult!)
          : CsvExportService.generateSummaryCsv(_analysisResult!);

      final fallbackDir = _selectedPpgPath?.substring(0, _selectedPpgPath!.lastIndexOf('/'));

      final saved = await CsvExportService.saveCsv(
        defaultFileName: defaultFileName,
        csvContent: content,
        fallbackDirectory: fallbackDir,
      );

      if (mounted && saved != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: SensioTheme.accent,
            content: Text(
              'Exported: $saved',
              style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: SensioTheme.rejectNoise,
            content: Text('Export failed: $e'),
          ),
        );
      }
    }
  }

  Future<void> _runAnalysis() async {
    if (_selectedPpgPath == null) return;

    setState(() {
      _isAnalyzing = true;
      _errorMessage = null;
    });

    try {
      final result = await PPGAnalysisService.analyzeFile(
        _selectedPpgPath!,
        sigmotPath: _detectedSigmotPath,
        sampleRate: 50.0,
      );

      setState(() {
        _analysisResult = result;
        _isAnalyzing = false;
        _currentStartS = 0.0;
      });
    } catch (e) {
      setState(() {
        _errorMessage = e.toString();
        _isAnalyzing = false;
      });
    }
  }

  void _onSeek(double newStartS) {
    if (_analysisResult == null) return;
    setState(() {
      _currentStartS = newStartS.clamp(
        0.0,
        (_analysisResult!.totalDurationS - _windowDurationS).clamp(0.0, _analysisResult!.totalDurationS),
      );
    });
  }

  void _onSelectBeatTimestamp(double ts) {
    if (_analysisResult == null) return;
    setState(() {
      _currentStartS = (ts - _windowDurationS / 2.0).clamp(
        0.0,
        (_analysisResult!.totalDurationS - _windowDurationS).clamp(0.0, _analysisResult!.totalDurationS),
      );
      _tabController.animateTo(0); // Jump to Waveform tab for individual beat
    });
  }

  void _onSyncWaveformFromTrend(double ts) {
    if (_analysisResult == null) return;
    setState(() {
      _currentStartS = (ts - _windowDurationS / 2.0).clamp(
        0.0,
        (_analysisResult!.totalDurationS - _windowDurationS).clamp(0.0, _analysisResult!.totalDurationS),
      );
      // Stay on HRV Dynamics tab while inspecting
    });
  }

  void _onJumpToWaveform(double ts) {
    if (_analysisResult == null) return;
    setState(() {
      _currentStartS = (ts - _windowDurationS / 2.0).clamp(
        0.0,
        (_analysisResult!.totalDurationS - _windowDurationS).clamp(0.0, _analysisResult!.totalDurationS),
      );
      _tabController.animateTo(0); // Explicitly requested tab jump
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: SensioTheme.accent.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.monitor_heart, color: SensioTheme.accent, size: 22),
            ),
            const SizedBox(width: 12),
            const Text('Sensio PPG Analysis Studio', style: TextStyle(fontWeight: FontWeight.bold)),
            const Spacer(),
            if (_analysisResult != null) ...[
              Container(
                decoration: BoxDecoration(
                  color: SensioTheme.surface,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: SensioTheme.border.withValues(alpha: 0.5)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    InkWell(
                      borderRadius: const BorderRadius.horizontal(left: Radius.circular(7)),
                      onTap: () => setState(() => _showClockTime = false),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        color: !_showClockTime ? SensioTheme.accent.withValues(alpha: 0.2) : Colors.transparent,
                        child: Row(
                          children: [
                            Icon(Icons.timer_outlined, size: 14, color: !_showClockTime ? SensioTheme.accent : Colors.white60),
                            const SizedBox(width: 4),
                            Text(
                              'Elapsed',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: !_showClockTime ? FontWeight.bold : FontWeight.normal,
                                color: !_showClockTime ? SensioTheme.accent : Colors.white60,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    Container(width: 1, height: 20, color: SensioTheme.border.withValues(alpha: 0.4)),
                    InkWell(
                      borderRadius: const BorderRadius.horizontal(right: Radius.circular(7)),
                      onTap: () => setState(() => _showClockTime = true),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        color: _showClockTime ? SensioTheme.accent.withValues(alpha: 0.2) : Colors.transparent,
                        child: Row(
                          children: [
                            Icon(Icons.access_time, size: 14, color: _showClockTime ? SensioTheme.accent : Colors.white60),
                            const SizedBox(width: 4),
                            Text(
                              'Clock Time',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: _showClockTime ? FontWeight.bold : FontWeight.normal,
                                color: _showClockTime ? SensioTheme.accent : Colors.white60,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
            ],
            if (_selectedPpgPath != null) ...[
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white70,
                  side: const BorderSide(color: SensioTheme.border),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                ),
                icon: const Icon(Icons.folder_open, size: 16),
                label: Text(
                  File(_selectedPpgPath!).uri.pathSegments.last,
                  style: const TextStyle(fontSize: 12),
                ),
                onPressed: _pickFile,
              ),
              const SizedBox(width: 8),
              if (_analysisResult != null)
                PopupMenuButton<String>(
                  tooltip: 'Export CSV Results',
                  color: SensioTheme.surface,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: SensioTheme.accent.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: SensioTheme.accent.withValues(alpha: 0.4)),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.download, size: 15, color: SensioTheme.accent),
                        SizedBox(width: 4),
                        Text(
                          'Export CSV',
                          style: TextStyle(
                            color: SensioTheme.accent,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                  itemBuilder: (ctx) => [
                    const PopupMenuItem(
                      value: 'timeseries',
                      child: Row(
                        children: [
                          Icon(Icons.timeline, size: 16, color: SensioTheme.accent),
                          SizedBox(width: 8),
                          Text('Export Time-Series CSV (*.features.csv)', style: TextStyle(fontSize: 12, color: Colors.white)),
                        ],
                      ),
                    ),
                    const PopupMenuItem(
                      value: 'summary',
                      child: Row(
                        children: [
                          Icon(Icons.table_chart, size: 16, color: SensioTheme.ppgSignal),
                          SizedBox(width: 8),
                          Text('Export Summary Stats CSV (*.summary.csv)', style: TextStyle(fontSize: 12, color: Colors.white)),
                        ],
                      ),
                    ),
                    const PopupMenuItem(
                      value: 'copy',
                      child: Row(
                        children: [
                          Icon(Icons.copy, size: 16, color: Colors.white70),
                          SizedBox(width: 8),
                          Text('Copy Time-Series to Clipboard', style: TextStyle(fontSize: 12, color: Colors.white)),
                        ],
                      ),
                    ),
                  ],
                  onSelected: (val) async {
                    final messenger = ScaffoldMessenger.of(context);
                    if (val == 'timeseries') {
                      await _quickExportCsv(isTimeSeries: true);
                    } else if (val == 'summary') {
                      await _quickExportCsv(isTimeSeries: false);
                    } else if (val == 'copy') {
                      final csv = CsvExportService.generateTimeSeriesCsv(_analysisResult!);
                      await CsvExportService.copyToClipboard(csv);
                      if (mounted) {
                        messenger.showSnackBar(
                          const SnackBar(
                            backgroundColor: SensioTheme.accent,
                            content: Text(
                              'Time-series CSV copied to clipboard!',
                              style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
                            ),
                          ),
                        );
                      }
                    }
                  },
                ),
            ],
          ],
        ),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isAnalyzing) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: SensioTheme.accent),
            SizedBox(height: 16),
            Text('Processing high-efficiency Rust DSP & HRV Engine...',
                style: TextStyle(color: Colors.white70, fontSize: 14)),
          ],
        ),
      );
    }

    if (_errorMessage != null) {
      return Center(
        child: Container(
          padding: const EdgeInsets.all(24),
          margin: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: SensioTheme.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: SensioTheme.badArtifact),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, color: SensioTheme.badArtifact, size: 40),
              const SizedBox(height: 12),
              Text(_errorMessage!,
                  style: const TextStyle(color: Colors.white), textAlign: TextAlign.center),
              const SizedBox(height: 16),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(backgroundColor: SensioTheme.accent),
                    onPressed: _pickFile,
                    child: const Text('Select Another File', style: TextStyle(color: Colors.black)),
                  ),
                  const SizedBox(width: 12),
                  OutlinedButton(
                    style: OutlinedButton.styleFrom(foregroundColor: Colors.white70),
                    onPressed: _showManualPathDialog,
                    child: const Text('Enter Path Directly'),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    }

    if (_analysisResult == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.insights, size: 64, color: SensioTheme.border.withValues(alpha: 0.6)),
            const SizedBox(height: 16),
            const Text('No PPG Session Loaded',
                style: TextStyle(color: Colors.white70, fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            const Text('Select a Ring PPG CSV recording to compute high-precision HRV & morphology',
                style: TextStyle(color: Colors.white38, fontSize: 13)),
            const SizedBox(height: 24),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: SensioTheme.accent,
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  ),
                  icon: const Icon(Icons.folder_open),
                  label: const Text('Select CSV File', style: TextStyle(fontWeight: FontWeight.bold)),
                  onPressed: _pickFile,
                ),
                const SizedBox(width: 12),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white70,
                    side: const BorderSide(color: SensioTheme.border),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  ),
                  icon: const Icon(Icons.edit_note, size: 18),
                  label: const Text('Enter Path Directly'),
                  onPressed: _showManualPathDialog,
                ),
              ],
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        // KPI Quick Summary Bar
        _buildKpiBar(),

        // Tab Navigation
        TabBar(
          controller: _tabController,
          tabs: [
            const Tab(icon: Icon(Icons.show_chart, size: 18), text: 'Waveform & Timeline'),
            const Tab(icon: Icon(Icons.scatter_plot, size: 18), text: 'HRV Dynamics & Poincaré'),
            Tab(
              icon: const Icon(Icons.table_chart, size: 18),
              text: 'Clinical Summary (${_analysisResult?.summary.length ?? 28} Features)',
            ),
            const Tab(icon: Icon(Icons.dataset_outlined, size: 18), text: 'CSV Data Explorer'),
          ],
        ),

        // Tab Views
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              _buildWaveformTab(),
              _buildHrvDynamicsTab(),
              _buildSummaryTab(),
              _buildCsvExplorerTab(),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildKpiBar() {
    final res = _analysisResult!;
    final summary = {for (final r in res.summary) r.metric: r};

    final meanHr = summary['MeanHR']?.mean ?? double.nan;
    final sdnn = summary['SDNN']?.mean ?? double.nan;
    final rmssd = summary['RMSSD']?.mean ?? double.nan;
    final mqi = summary['Morphology_Quality']?.mean ?? double.nan;
    final skinTemp = summary['Skin_Temperature']?.mean ?? double.nan;
    final actMotion = summary['Activity_Motion']?.mean ?? double.nan;

    final dateLabel = TimeFormatter.formatSessionDate(res.sessionStartDateTime);
    final spanLabel = TimeFormatter.formatSessionSpan(res.sessionStartDateTime, res.totalDurationS);

    final kpiWidgets = [
      _kpiItem('Pulse Coverage', '${res.coveragePct.toStringAsFixed(1)}%', SensioTheme.goodPulse),
      _kpiItem('Detected Beats', '${res.peaksIndices.length}', SensioTheme.accent),
      _kpiItem('Mean HR', meanHr.isFinite ? '${meanHr.toStringAsFixed(1)} BPM' : '-', Colors.white),
      _kpiItem('Mean SDNN', sdnn.isFinite ? '${sdnn.toStringAsFixed(1)} ms' : '-', SensioTheme.ppgSignal),
      _kpiItem('Mean RMSSD', rmssd.isFinite ? '${rmssd.toStringAsFixed(1)} ms' : '-', SensioTheme.accent),
      if (skinTemp.isFinite)
        _kpiItem('Skin Temp', '${skinTemp.toStringAsFixed(2)} °C', const Color(0xFF38BDF8)),
      if (actMotion.isFinite)
        _kpiItem('Mean Activity', actMotion.toStringAsFixed(1), SensioTheme.sigmotSignal),
      _kpiItem('Morphology Quality', mqi.isFinite ? mqi.toStringAsFixed(2) : '-', const Color(0xFFF472B6)),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final isNarrow = constraints.maxWidth < 800;

        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Session Date & Time Span Strip
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              margin: const EdgeInsets.fromLTRB(12, 4, 12, 4),
              decoration: BoxDecoration(
                color: SensioTheme.surface.withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: SensioTheme.border.withValues(alpha: 0.3)),
              ),
              child: isNarrow
                  ? Wrap(
                      spacing: 12,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.calendar_today, size: 14, color: SensioTheme.accent),
                            const SizedBox(width: 6),
                            Text(
                              dateLabel,
                              style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.schedule, size: 14, color: Colors.white54),
                            const SizedBox(width: 6),
                            Text(
                              spanLabel,
                              style: const TextStyle(color: Colors.white70, fontSize: 12, fontFamily: 'monospace'),
                            ),
                          ],
                        ),
                      ],
                    )
                  : Row(
                      children: [
                        const Icon(Icons.calendar_today, size: 15, color: SensioTheme.accent),
                        const SizedBox(width: 6),
                        Text(
                          dateLabel,
                          style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(width: 16),
                        const Icon(Icons.schedule, size: 15, color: Colors.white54),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            spanLabel,
                            style: const TextStyle(color: Colors.white70, fontSize: 12, fontFamily: 'monospace'),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
            ),

            // KPI Badges
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              margin: const EdgeInsets.fromLTRB(12, 0, 12, 6),
              decoration: BoxDecoration(
                color: SensioTheme.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: SensioTheme.border.withValues(alpha: 0.3)),
              ),
              child: isNarrow
                  ? Wrap(
                      spacing: 16,
                      runSpacing: 8,
                      alignment: WrapAlignment.spaceAround,
                      children: kpiWidgets,
                    )
                  : SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: kpiWidgets
                            .map(
                              (w) => Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 10),
                                child: w,
                              ),
                            )
                            .toList(),
                      ),
                    ),
            ),
          ],
        );
      },
    );
  }

  Widget _kpiItem(String label, String val, Color color) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: const TextStyle(color: Colors.white54, fontSize: 11)),
        const SizedBox(height: 2),
        Text(val, style: TextStyle(color: color, fontSize: 15, fontWeight: FontWeight.bold)),
      ],
    );
  }

  Widget _buildWaveformTab() {
    final res = _analysisResult!;
    final t0 = res.startTimeOfDayS > 0 ? res.startTimeOfDayS : (res.time.isNotEmpty ? res.time.first : 0.0);

    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Gapless Quality Strip Header & Ribbon
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'GAPLESS QUALITY EPISODES (Click to Jump)',
                style: TextStyle(color: Colors.white60, fontSize: 11, fontWeight: FontWeight.bold),
              ),
              // Zoom Level Presets
              Row(
                children: [
                  const Text('Zoom: ', style: TextStyle(color: Colors.white54, fontSize: 11)),
                  ...[15.0, 30.0, 60.0, 120.0, 300.0].map((dur) {
                    final label = dur >= 60.0 ? '${(dur / 60).round()}m' : '${dur.round()}s';
                    final isSel = _windowDurationS == dur;
                    return Padding(
                      padding: const EdgeInsets.only(left: 4),
                       child: InkWell(
                        borderRadius: BorderRadius.circular(4),
                        onTap: () => setState(() => _windowDurationS = dur),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: isSel ? SensioTheme.accent : Colors.transparent,
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(
                              color: isSel ? SensioTheme.accent : SensioTheme.border.withValues(alpha: 0.4),
                            ),
                          ),
                          child: Text(
                            label,
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
              ),
            ],
          ),
          const SizedBox(height: 6),

          // Interactive Gapless Ribbon
          TimelineRibbon(
            segments: res.segments,
            totalDurationS: res.totalDurationS,
            currentStartS: _currentStartS,
            windowDurationS: _windowDurationS,
            onSeek: _onSeek,
            showClockTime: _showClockTime,
            t0SecondsOfDay: t0,
            sessionStart: res.sessionStartDateTime,
          ),
          const SizedBox(height: 8),

          // High-Resolution 50 Hz Waveform Canvas
          Expanded(
            child: WaveformViewer(
              result: res,
              currentStartS: _currentStartS,
              windowDurationS: _windowDurationS,
              onSeek: _onSeek,
              showClockTime: _showClockTime,
              t0SecondsOfDay: t0,
              sessionStart: res.sessionStartDateTime,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHrvDynamicsTab() {
    final res = _analysisResult!;
    final t0 = res.startTimeOfDayS > 0 ? res.startTimeOfDayS : (res.time.isNotEmpty ? res.time.first : 0.0);

    return Padding(
      padding: const EdgeInsets.all(12),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isWide = constraints.maxWidth > 850;

          if (isWide) {
            return Row(
              children: [
                Expanded(
                  flex: 5,
                  child: PoincareChart(
                    data: res.poincare,
                    onSelectBeatTimestamp: _onSelectBeatTimestamp,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 6,
                  child: HrvTrendsChart(
                    hrvResult: res.hrv,
                    onSelectTimestamp: _onSyncWaveformFromTrend,
                    onJumpToWaveform: _onJumpToWaveform,
                    showClockTime: _showClockTime,
                    t0SecondsOfDay: t0,
                    sessionStart: res.sessionStartDateTime,
                  ),
                ),
              ],
            );
          } else {
            return SingleChildScrollView(
              child: Column(
                children: [
                  SizedBox(
                    height: 380,
                    child: PoincareChart(
                      data: res.poincare,
                      onSelectBeatTimestamp: _onSelectBeatTimestamp,
                    ),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    height: 480,
                    child: HrvTrendsChart(
                      hrvResult: res.hrv,
                      onSelectTimestamp: _onSyncWaveformFromTrend,
                      onJumpToWaveform: _onJumpToWaveform,
                      showClockTime: _showClockTime,
                      t0SecondsOfDay: t0,
                      sessionStart: res.sessionStartDateTime,
                    ),
                  ),
                ],
              ),
            );
          }
        },
      ),
    );
  }

  Widget _buildSummaryTab() {
    final res = _analysisResult!;
    return Padding(
      padding: const EdgeInsets.all(12),
      child: SummaryTable(rows: res.summary),
    );
  }

  Widget _buildCsvExplorerTab() {
    final res = _analysisResult!;
    return Padding(
      padding: const EdgeInsets.all(12),
      child: CsvExplorerWidget(
        result: res,
        sourceFilePath: _selectedPpgPath,
      ),
    );
  }
}
