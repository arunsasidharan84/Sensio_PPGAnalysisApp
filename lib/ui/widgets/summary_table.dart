import 'package:flutter/material.dart';
import '../theme.dart';
import '../../core/models/ppg_models.dart';

class SummaryTable extends StatefulWidget {
  final List<FeatureSummaryRow> rows;

  const SummaryTable({super.key, required this.rows});

  @override
  State<SummaryTable> createState() => _SummaryTableState();
}

class _SummaryTableState extends State<SummaryTable> {
  String _filterDomain = 'ALL';
  String _searchQuery = '';

  @override
  Widget build(BuildContext context) {
    final filteredRows = widget.rows.where((row) {
      if (_filterDomain != 'ALL' && row.domain != _filterDomain) {
        return false;
      }
      if (_searchQuery.isNotEmpty &&
          !row.metric.toLowerCase().contains(_searchQuery.toLowerCase())) {
        return false;
      }
      return true;
    }).toList();

    return Column(
      children: [
        // Filter Bar
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: SensioTheme.surface,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: SensioTheme.border.withValues(alpha: 0.4)),
          ),
          child: Row(
            children: [
              // Domain Chips
              Wrap(
                spacing: 6,
                children: ['ALL', 'Time', 'Frequency', 'Non-Linear', 'Morphology'].map((d) {
                  final isSel = d == _filterDomain;
                  return ChoiceChip(
                    label: Text(d),
                    selected: isSel,
                    selectedColor: SensioTheme.accent.withValues(alpha: 0.2),
                    backgroundColor: Colors.transparent,
                    labelStyle: TextStyle(
                      color: isSel ? SensioTheme.accent : Colors.white60,
                      fontWeight: isSel ? FontWeight.bold : FontWeight.normal,
                      fontSize: 11,
                    ),
                    side: BorderSide(
                      color: isSel ? SensioTheme.accent : SensioTheme.border.withValues(alpha: 0.3),
                    ),
                    onSelected: (selected) {
                      if (selected) setState(() => _filterDomain = d);
                    },
                  );
                }).toList(),
              ),
              const Spacer(),
              // Search Box
              SizedBox(
                width: 180,
                height: 36,
                child: TextField(
                  style: const TextStyle(fontSize: 12, color: Colors.white),
                  decoration: InputDecoration(
                    hintText: 'Search metric...',
                    hintStyle: const TextStyle(fontSize: 12, color: Colors.white38),
                    prefixIcon: const Icon(Icons.search, size: 16, color: Colors.white38),
                    contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 8),
                    filled: true,
                    fillColor: SensioTheme.background,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: SensioTheme.border.withValues(alpha: 0.4)),
                    ),
                  ),
                  onChanged: (val) => setState(() => _searchQuery = val),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),

        // Table
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              color: SensioTheme.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: SensioTheme.border.withValues(alpha: 0.4)),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: SingleChildScrollView(
                scrollDirection: Axis.vertical,
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: DataTable(
                    columnSpacing: 28,
                    horizontalMargin: 20,
                    headingRowColor: WidgetStateProperty.all(const Color(0xFF141E33)),
                    columns: const [
                      DataColumn(label: Text('DOMAIN', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: Colors.white60))),
                      DataColumn(label: Text('METRIC NAME', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: Colors.white60))),
                      DataColumn(label: Text('MEAN ± SD', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: Colors.white60))),
                      DataColumn(label: Text('MEDIAN', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: Colors.white60))),
                      DataColumn(label: Text('MIN - MAX', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: Colors.white60))),
                    ],
                    rows: filteredRows.map((r) {
                      Color domainColor = Colors.white70;
                      if (r.domain == 'Time') domainColor = SensioTheme.accent;
                      if (r.domain == 'Frequency') domainColor = SensioTheme.ppgSignal;
                      if (r.domain == 'Non-Linear') domainColor = const Color(0xFFFBBF24);
                      if (r.domain == 'Morphology') domainColor = const Color(0xFFF472B6);

                      final meanStr = r.mean.isFinite ? r.mean.toStringAsFixed(2) : '-';
                      final sdStr = r.sd.isFinite ? '± ${r.sd.toStringAsFixed(2)}' : '';
                      final medStr = r.median.isFinite ? r.median.toStringAsFixed(2) : '-';
                      final minStr = r.minVal.isFinite ? r.minVal.toStringAsFixed(2) : '-';
                      final maxStr = r.maxVal.isFinite ? r.maxVal.toStringAsFixed(2) : '-';

                      return DataRow(
                        cells: [
                          DataCell(Text(r.domain, style: TextStyle(color: domainColor, fontWeight: FontWeight.w600, fontSize: 12))),
                          DataCell(Text(r.metric, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.white))),
                          DataCell(Text('$meanStr $sdStr', style: const TextStyle(fontFamily: 'monospace', fontSize: 12))),
                          DataCell(Text(medStr, style: const TextStyle(fontFamily: 'monospace', fontSize: 12, color: SensioTheme.accent))),
                          DataCell(Text('$minStr to $maxStr', style: const TextStyle(fontFamily: 'monospace', fontSize: 12, color: Colors.white60))),
                        ],
                      );
                    }).toList(),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
