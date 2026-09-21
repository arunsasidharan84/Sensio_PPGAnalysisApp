import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../theme.dart';
import '../../core/models/ppg_models.dart';
import '../../core/services/ppg_analysis_service.dart';
import '../widgets/timeline_ribbon.dart';
import '../widgets/waveform_viewer.dart';
import '../widgets/poincare_chart.dart';
import '../widgets/hrv_trends_chart.dart';
import '../widgets/summary_table.dart';

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

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _pickFile() async {
    final res = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['csv'],
    );

    if (res != null && res.files.single.path != null) {
      final ppgPath = res.files.single.path!;
      final sigmotPath = PPGAnalysisService.findMatchingSigmot(ppgPath);
      setState(() {
        _selectedPpgPath = ppgPath;
        _detectedSigmotPath = sigmotPath;
        _errorMessage = null;
      });
      _runAnalysis();
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
      _tabController.animateTo(0); // Jump to Waveform tab
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
            if (_selectedPpgPath != null)
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
              )
            else
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: SensioTheme.accent,
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                ),
                icon: const Icon(Icons.file_upload, size: 18),
                label: const Text('Open PPG File', style: TextStyle(fontWeight: FontWeight.bold)),
                onPressed: _pickFile,
              ),
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
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: SensioTheme.accent),
                onPressed: _pickFile,
                child: const Text('Select Another File', style: TextStyle(color: Colors.black)),
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
          tabs: const [
            Tab(icon: Icon(Icons.show_chart, size: 18), text: 'Waveform & Timeline'),
            Tab(icon: Icon(Icons.scatter_plot, size: 18), text: 'HRV Dynamics & Poincaré'),
            Tab(icon: Icon(Icons.table_chart, size: 18), text: 'Clinical Summary (26 Features)'),
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

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      margin: const EdgeInsets.fromLTRB(12, 4, 12, 6),
      decoration: BoxDecoration(
        color: SensioTheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: SensioTheme.border.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _kpiItem('Pulse Coverage', '${res.coveragePct.toStringAsFixed(1)}%', SensioTheme.goodPulse),
          _kpiItem('Detected Beats', '${res.peaksIndices.length}', SensioTheme.accent),
          _kpiItem('Mean HR', meanHr.isFinite ? '${meanHr.toStringAsFixed(1)} BPM' : '-', Colors.white),
          _kpiItem('Mean SDNN', sdnn.isFinite ? '${sdnn.toStringAsFixed(1)} ms' : '-', SensioTheme.ppgSignal),
          _kpiItem('Mean RMSSD', rmssd.isFinite ? '${rmssd.toStringAsFixed(1)} ms' : '-', SensioTheme.accent),
          _kpiItem('Morphology Quality', mqi.isFinite ? mqi.toStringAsFixed(2) : '-', const Color(0xFFF472B6)),
        ],
      ),
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
          ),
          const SizedBox(height: 8),

          // High-Resolution 50 Hz Waveform Canvas
          Expanded(
            child: WaveformViewer(
              result: res,
              currentStartS: _currentStartS,
              windowDurationS: _windowDurationS,
              onSeek: _onSeek,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHrvDynamicsTab() {
    final res = _analysisResult!;

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
                    onSelectTimestamp: _onSelectBeatTimestamp,
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
                    height: 380,
                    child: HrvTrendsChart(
                      hrvResult: res.hrv,
                      onSelectTimestamp: _onSelectBeatTimestamp,
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
}
