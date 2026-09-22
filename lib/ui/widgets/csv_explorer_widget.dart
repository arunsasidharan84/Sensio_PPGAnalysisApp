import 'package:flutter/material.dart';
import '../theme.dart';
import '../../core/models/ppg_models.dart';
import '../../core/services/csv_export_service.dart';
import '../../core/utils/time_formatter.dart';

enum CsvViewMode {
  timeSeries,
  rawCsv,
}

class CsvExplorerWidget extends StatefulWidget {
  final SessionAnalysisResult result;
  final String? sourceFilePath;

  const CsvExplorerWidget({
    super.key,
    required this.result,
    this.sourceFilePath,
  });

  @override
  State<CsvExplorerWidget> createState() => _CsvExplorerWidgetState();
}

class _CsvExplorerWidgetState extends State<CsvExplorerWidget> {
  CsvViewMode _viewMode = CsvViewMode.timeSeries;
  String _searchQuery = '';
  int _rowsPerPage = 50;
  int _currentPage = 0;
  bool _isExporting = false;

  late String _cachedTimeSeriesCsv;

  @override
  void initState() {
    super.initState();
    _cachedTimeSeriesCsv = CsvExportService.generateTimeSeriesCsv(widget.result);
  }

  @override
  void didUpdateWidget(covariant CsvExplorerWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.result != widget.result) {
      _cachedTimeSeriesCsv = CsvExportService.generateTimeSeriesCsv(widget.result);
      _currentPage = 0;
    }
  }

  Future<void> _exportCurrentCsv() async {
    setState(() => _isExporting = true);
    try {
      final csvContent = _cachedTimeSeriesCsv;

      final baseName = widget.sourceFilePath != null
          ? widget.sourceFilePath!.split('/').last.replaceAll('_ppg_data.csv', '')
          : 'sensio_session';

      final defaultFileName = '${baseName}_hrv_timeseries.csv';

      final fallbackDir = widget.sourceFilePath?.substring(0, widget.sourceFilePath!.lastIndexOf('/'));

      final savedPath = await CsvExportService.saveCsv(
        defaultFileName: defaultFileName,
        csvContent: csvContent,
        fallbackDirectory: fallbackDir,
      );

      if (mounted) {
        if (savedPath != null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              backgroundColor: SensioTheme.accent,
              content: Text(
                'Saved CSV to: $savedPath',
                style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
              ),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: SensioTheme.rejectNoise,
            content: Text('Failed to export CSV: $e'),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isExporting = false);
      }
    }
  }

  Future<void> _copyCurrentCsv() async {
    await CsvExportService.copyToClipboard(_cachedTimeSeriesCsv);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: SensioTheme.accent,
          duration: Duration(seconds: 2),
          content: Text(
            'CSV data copied to clipboard!',
            style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // 1. Toolbar: Mode selector, Search, Action buttons
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: SensioTheme.surface,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: SensioTheme.border.withValues(alpha: 0.4)),
          ),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final isNarrow = constraints.maxWidth < 750;

              final modeSelector = SegmentedButton<CsvViewMode>(
                segments: const [
                  ButtonSegment(
                    value: CsvViewMode.timeSeries,
                    icon: Icon(Icons.timeline, size: 16),
                    label: Text('Time-Series Data Grid', style: TextStyle(fontSize: 11)),
                  ),
                  ButtonSegment(
                    value: CsvViewMode.rawCsv,
                    icon: Icon(Icons.code, size: 16),
                    label: Text('Raw CSV Stream', style: TextStyle(fontSize: 11)),
                  ),
                ],
                selected: {_viewMode},
                onSelectionChanged: (set) {
                  setState(() {
                    _viewMode = set.first;
                    _currentPage = 0;
                  });
                },
                style: ButtonStyle(
                  visualDensity: VisualDensity.compact,
                  backgroundColor: WidgetStateProperty.resolveWith((states) {
                    if (states.contains(WidgetState.selected)) {
                      return SensioTheme.accent.withValues(alpha: 0.2);
                    }
                    return Colors.transparent;
                  }),
                ),
              );

              final searchBox = SizedBox(
                width: isNarrow ? double.infinity : 180,
                height: 34,
                child: TextField(
                  style: const TextStyle(fontSize: 12, color: Colors.white),
                  decoration: InputDecoration(
                    hintText: 'Search data...',
                    hintStyle: const TextStyle(fontSize: 12, color: Colors.white38),
                    prefixIcon: const Icon(Icons.search, size: 16, color: Colors.white38),
                    contentPadding: EdgeInsets.zero,
                    filled: true,
                    fillColor: SensioTheme.background,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: SensioTheme.border.withValues(alpha: 0.4)),
                    ),
                  ),
                  onChanged: (val) => setState(() {
                    _searchQuery = val;
                    _currentPage = 0;
                  }),
                ),
              );

              final actionButtons = Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white70,
                      side: const BorderSide(color: SensioTheme.border),
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      visualDensity: VisualDensity.compact,
                    ),
                    icon: const Icon(Icons.copy, size: 14),
                    label: const Text('Copy CSV', style: TextStyle(fontSize: 11)),
                    onPressed: _copyCurrentCsv,
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: SensioTheme.accent,
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      visualDensity: VisualDensity.compact,
                    ),
                    icon: _isExporting
                        ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                        : const Icon(Icons.download, size: 15),
                    label: Text(
                      _isExporting ? 'Exporting...' : 'Export CSV',
                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                    ),
                    onPressed: _isExporting ? null : _exportCurrentCsv,
                  ),
                ],
              );

              if (isNarrow) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    modeSelector,
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(child: searchBox),
                        const SizedBox(width: 8),
                        actionButtons,
                      ],
                    ),
                  ],
                );
              }

              return Row(
                children: [
                  modeSelector,
                  const Spacer(),
                  searchBox,
                  const SizedBox(width: 12),
                  actionButtons,
                ],
              );
            },
          ),
        ),
        const SizedBox(height: 8),

        // 2. Data Content
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              color: SensioTheme.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: SensioTheme.border.withValues(alpha: 0.4)),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: _buildContent(),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildContent() {
    switch (_viewMode) {
      case CsvViewMode.timeSeries:
        return _buildTimeSeriesGrid();
      case CsvViewMode.rawCsv:
        return _buildRawCsvView();
    }
  }

  Widget _buildTimeSeriesGrid() {
    final hrv = widget.result.hrv;
    final timestamps = hrv.timestamps;
    final metrics = hrv.metrics;
    final metricKeys = metrics.keys.toList();

    // Prepare rows
    final allRows = <Map<String, String>>[];
    for (int i = 0; i < timestamps.length; i++) {
      final ts = timestamps[i];
      final clockTimeStr = TimeFormatter.formatSeconds(
        ts,
        clockTime: true,
        sessionStart: widget.result.sessionStartDateTime,
        t0SecondsOfDay: widget.result.startTimeOfDayS,
        includeDate: false,
        showMillis: false,
      );

      final row = <String, String>{
        '#': i.toString(),
        'Elapsed (s)': ts.toStringAsFixed(1),
        'Clock Time': clockTimeStr,
      };

      for (final k in metricKeys) {
        final valList = metrics[k];
        final val = (valList != null && i < valList.length) ? valList[i] : double.nan;
        if (val.isFinite) {
          if (k == 'Skin_Temperature') {
            row[k] = '${val.toStringAsFixed(2)} °C';
          } else if (val.abs() >= 100) {
            row[k] = val.toStringAsFixed(2);
          } else if (val.abs() >= 1) {
            row[k] = val.toStringAsFixed(3);
          } else {
            row[k] = val.toStringAsFixed(4);
          }
        } else {
          row[k] = '-';
        }
      }
      allRows.add(row);
    }

    // Filter
    final filtered = _searchQuery.isEmpty
        ? allRows
        : allRows.where((r) {
            return r.values.any((v) => v.toLowerCase().contains(_searchQuery.toLowerCase()));
          }).toList();

    final totalRows = filtered.length;
    final totalPages = (totalRows / _rowsPerPage).ceil().clamp(1, 999999);
    final curPage = _currentPage.clamp(0, totalPages - 1);
    final startIndex = curPage * _rowsPerPage;
    final endIndex = (startIndex + _rowsPerPage).clamp(0, totalRows);
    final pageRows = (startIndex < totalRows) ? filtered.sublist(startIndex, endIndex) : <Map<String, String>>[];

    final columns = ['#', 'Elapsed (s)', 'Clock Time', ...metricKeys];

    return Column(
      children: [
        // Paging bar
        _buildPagingBar(
          totalCount: totalRows,
          label: 'time steps (15s intervals) • ${columns.length} columns',
          currentPage: curPage,
          totalPages: totalPages,
          onPrev: curPage > 0 ? () => setState(() => _currentPage--) : null,
          onNext: curPage < totalPages - 1 ? () => setState(() => _currentPage++) : null,
        ),
        const Divider(height: 1, color: Color(0xFF1E293B)),
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.vertical,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                columnSpacing: 20,
                horizontalMargin: 16,
                headingRowColor: WidgetStateProperty.all(const Color(0xFF141E33)),
                columns: columns.map((col) {
                  Color colColor = Colors.white60;
                  if (col == 'Clock Time') colColor = SensioTheme.accent;
                  if (col == 'MeanHR') colColor = Colors.white;
                  if (col == 'Skin_Temperature') colColor = const Color(0xFF38BDF8);
                  if (col == 'Activity_Motion') colColor = SensioTheme.sigmotSignal;

                  return DataColumn(
                    label: Text(
                      col,
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: colColor),
                    ),
                  );
                }).toList(),
                rows: pageRows.map((r) {
                  return DataRow(
                    cells: columns.map((col) {
                      final val = r[col] ?? '';
                      Color textColor = Colors.white;
                      if (col == 'Clock Time') textColor = SensioTheme.accent;
                      if (col == 'Skin_Temperature') textColor = const Color(0xFF38BDF8);
                      if (col == 'Activity_Motion') textColor = SensioTheme.sigmotSignal;
                      if (val == '-') textColor = Colors.white24;

                      return DataCell(
                        Text(
                          val,
                          style: TextStyle(fontFamily: 'monospace', fontSize: 11, color: textColor),
                        ),
                      );
                    }).toList(),
                  );
                }).toList(),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildRawCsvView() {
    final csvText = _cachedTimeSeriesCsv;
    final lineCount = '\n'.allMatches(csvText).length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          color: const Color(0xFF141E33),
          child: Row(
            children: [
              Text(
                'Raw CSV Stream ($lineCount lines, ${(csvText.length / 1024).toStringAsFixed(1)} KB)',
                style: const TextStyle(fontSize: 12, color: Colors.white70, fontWeight: FontWeight.bold),
              ),
              const Spacer(),
              TextButton.icon(
                style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                icon: const Icon(Icons.copy, size: 14, color: SensioTheme.accent),
                label: const Text('Copy All', style: TextStyle(color: SensioTheme.accent, fontSize: 11)),
                onPressed: _copyCurrentCsv,
              ),
            ],
          ),
        ),
        Expanded(
          child: Container(
            color: const Color(0xFF090D16),
            padding: const EdgeInsets.all(12),
            child: SingleChildScrollView(
              child: SelectableText(
                csvText,
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 11,
                  color: Colors.white70,
                  height: 1.4,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPagingBar({
    required int totalCount,
    required String label,
    required int currentPage,
    required int totalPages,
    required VoidCallback? onPrev,
    required VoidCallback? onNext,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      color: const Color(0xFF141E33),
      child: Row(
        children: [
          Text(
            '$totalCount $label',
            style: const TextStyle(fontSize: 11, color: Colors.white60),
          ),
          const Spacer(),
          // Rows per page selector
          const Text('Rows/page: ', style: TextStyle(fontSize: 11, color: Colors.white38)),
          DropdownButton<int>(
            value: _rowsPerPage,
            dropdownColor: const Color(0xFF141E33),
            underline: const SizedBox(),
            style: const TextStyle(fontSize: 11, color: Colors.white),
            items: [25, 50, 100, 250].map((n) {
              return DropdownMenuItem<int>(value: n, child: Text('$n'));
            }).toList(),
            onChanged: (val) {
              if (val != null) {
                setState(() {
                  _rowsPerPage = val;
                  _currentPage = 0;
                });
              }
            },
          ),
          const SizedBox(width: 16),
          // Page nav
          IconButton(
            icon: const Icon(Icons.chevron_left, size: 18),
            onPressed: onPrev,
            visualDensity: VisualDensity.compact,
            color: onPrev != null ? Colors.white70 : Colors.white24,
          ),
          Text(
            'Page ${currentPage + 1} of $totalPages',
            style: const TextStyle(fontSize: 11, color: Colors.white70, fontFamily: 'monospace'),
          ),
          IconButton(
            icon: const Icon(Icons.chevron_right, size: 18),
            onPressed: onNext,
            visualDensity: VisualDensity.compact,
            color: onNext != null ? Colors.white70 : Colors.white24,
          ),
        ],
      ),
    );
  }
}
