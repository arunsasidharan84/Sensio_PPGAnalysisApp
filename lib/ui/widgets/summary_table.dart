import 'package:flutter/material.dart';
import '../theme.dart';
import '../../core/models/ppg_models.dart';

class ClinicalMetricInfo {
  final String metric;
  final String friendlyName;
  final String unit;
  final String meaning;
  final String highMeaning;
  final String lowMeaning;

  const ClinicalMetricInfo({
    required this.metric,
    required this.friendlyName,
    required this.unit,
    required this.meaning,
    required this.highMeaning,
    required this.lowMeaning,
  });
}

class ClinicalDictionary {
  static const Map<String, ClinicalMetricInfo> dictionary = {
    'MeanHR': ClinicalMetricInfo(
      metric: 'MeanHR',
      friendlyName: 'Mean Heart Rate',
      unit: 'BPM',
      meaning: 'Average cardiac rate over the epoch.',
      highMeaning: 'Sympathetic arousal, exercise, physical exertion, mental stress, fever, or tachycardia.',
      lowMeaning: 'Deep restorative sleep, parasympathetic dominance, athletic bradycardia, or relaxation.',
    ),
    'MeanNN': ClinicalMetricInfo(
      metric: 'MeanNN',
      friendlyName: 'Mean Normal-to-Normal Interval',
      unit: 'ms',
      meaning: 'Average duration between consecutive normal heartbeats.',
      highMeaning: 'Slower basal heart rate, deep parasympathetic rest, high cardiovascular recovery.',
      lowMeaning: 'Elevated heart rate, sympathetic dominance, physical strain, or anxiety.',
    ),
    'SDNN': ClinicalMetricInfo(
      metric: 'SDNN',
      friendlyName: 'Standard Deviation of NN Intervals',
      unit: 'ms',
      meaning: 'Standard deviation of all NN intervals; gold standard for total autonomic cardiac regulatory reserve.',
      highMeaning: 'Robust physiological adaptability, high resilience, healthy autonomic nervous system capacity.',
      lowMeaning: 'Autonomic fatigue, chronic stress, systemic exhaustion, overtraining, or cardiovascular risk.',
    ),
    'RMSSD': ClinicalMetricInfo(
      metric: 'RMSSD',
      friendlyName: 'Root Mean Square of Successive Differences',
      unit: 'ms',
      meaning: 'Beat-to-beat variance measuring parasympathetic (vagal) cardiac tone.',
      highMeaning: 'Deep restorative recovery, calm parasympathetic state, high readiness and sleep quality.',
      lowMeaning: 'Acute fatigue, mental stress, systemic inflammation, poor sleep, or dehydration.',
    ),
    'pNN50': ClinicalMetricInfo(
      metric: 'pNN50',
      friendlyName: 'Percentage of NN Intervals > 50ms',
      unit: '%',
      meaning: 'Proportion of consecutive beats differing by over 50 ms (rapid vagal adjustments).',
      highMeaning: 'Strong parasympathetic vagal modulation and agile heart rate buffering.',
      lowMeaning: 'Blunted vagal tone, sympathetic overactivity, or acute stress.',
    ),
    'pNN20': ClinicalMetricInfo(
      metric: 'pNN20',
      friendlyName: 'Percentage of NN Intervals > 20ms',
      unit: '%',
      meaning: 'Proportion of consecutive beats differing by over 20 ms; sensitive short-term vagal marker.',
      highMeaning: 'Active parasympathetic modulation and high physiological responsiveness.',
      lowMeaning: 'Suppressed autonomic flexibility, prolonged stress, or illness.',
    ),
    'CVNN': ClinicalMetricInfo(
      metric: 'CVNN',
      friendlyName: 'Coefficient of Variation of NN',
      unit: 'ratio',
      meaning: 'Normalized HRV (SDNN divided by MeanNN), eliminating heart rate dependence.',
      highMeaning: 'High intrinsic autonomic flexibility independent of resting heart rate.',
      lowMeaning: 'Monotonous, rigid cardiac pacing with reduced autonomic adaptability.',
    ),
    'VLF': ClinicalMetricInfo(
      metric: 'VLF',
      friendlyName: 'Very Low Frequency Power (0.0033–0.04 Hz)',
      unit: 'ms²',
      meaning: 'Slow physiological rhythms reflecting thermoregulation, renin-angiotensin, and endocrine cycles.',
      highMeaning: 'Active thermoregulation, healthy slow metabolic oscillations, and circadian rhythms.',
      lowMeaning: 'Chronic fatigue, systemic inflammatory states, burnout, or metabolic dysregulation.',
    ),
    'LF': ClinicalMetricInfo(
      metric: 'LF',
      friendlyName: 'Low Frequency Power (0.04–0.15 Hz)',
      unit: 'ms²',
      meaning: 'Baroreflex rhythm modulated jointly by sympathetic and vagal autonomic branches.',
      highMeaning: 'Active blood pressure baroreflex modulation and moderate sympathetic engagement.',
      lowMeaning: 'Blunted baroreflex responsiveness, dysautonomia, or severe physical exhaustion.',
    ),
    'HF': ClinicalMetricInfo(
      metric: 'HF',
      friendlyName: 'High Frequency Power (0.15–0.40 Hz)',
      unit: 'ms²',
      meaning: 'Respiratory Sinus Arrhythmia (RSA) mediated directly by the vagus nerve.',
      highMeaning: 'Deep relaxation, slow-wave restorative sleep, high vagal nerve activation.',
      lowMeaning: 'Acute distress, shallow breathing, sympathetic overdrive, or sleep disruption.',
    ),
    'LF_HF': ClinicalMetricInfo(
      metric: 'LF_HF',
      friendlyName: 'LF to HF Ratio',
      unit: 'ratio',
      meaning: 'Classic ratio reflecting the balance between sympathetic and parasympathetic influences.',
      highMeaning: 'Sympathetic dominance, mental workload, psychological tension, or physical exertion.',
      lowMeaning: 'Parasympathetic vagal dominance, restorative recovery, or deep rest.',
    ),
    'LFn': ClinicalMetricInfo(
      metric: 'LFn',
      friendlyName: 'Normalized Low Frequency Power',
      unit: 'nu',
      meaning: 'Proportion of baroreflex power relative to total active autonomic bands.',
      highMeaning: 'Predominant sympathetic/baroreflex modulation over respiration.',
      lowMeaning: 'Vagal respiratory dominance with minimal sympathetic drive.',
    ),
    'HFn': ClinicalMetricInfo(
      metric: 'HFn',
      friendlyName: 'Normalized High Frequency Power',
      unit: 'nu',
      meaning: 'Proportion of vagal respiratory power relative to total active autonomic bands.',
      highMeaning: 'High vagal respiratory modulation relative to baroreflex rhythms.',
      lowMeaning: 'Suppressed vagal respiratory drive relative to baroreflex rhythms.',
    ),
    'Total_Power': ClinicalMetricInfo(
      metric: 'Total_Power',
      friendlyName: 'Total Spectral Power',
      unit: 'ms²',
      meaning: 'Total variance across all spectral frequency bands, reflecting global autonomic capacity.',
      highMeaning: 'High autonomic vigor, superior cardiovascular health, and physical fitness.',
      lowMeaning: 'Autonomic depression, exhaustion, aging, chronic illness, or severe stress.',
    ),
    'SD1': ClinicalMetricInfo(
      metric: 'SD1',
      friendlyName: 'Poincaré Minor Axis Dispersion',
      unit: 'ms',
      meaning: 'Short-term beat-to-beat variability measuring instantaneous vagal braking (SD1 = RMSSD/√2).',
      highMeaning: 'High vagal parasympathetic braking and healthy respiratory sinus arrhythmia.',
      lowMeaning: 'Blunted beat-to-beat vagal modulation, sympathetic lock-in.',
    ),
    'SD2': ClinicalMetricInfo(
      metric: 'SD2',
      friendlyName: 'Poincaré Major Axis Dispersion',
      unit: 'ms',
      meaning: 'Continuous long-term autonomic variability along the line-of-identity.',
      highMeaning: 'Dynamic long-term cardiovascular adjustment and resilient baroreflex response.',
      lowMeaning: 'Reduced overall variability, rigid cardiac pacing.',
    ),
    'SD1_SD2': ClinicalMetricInfo(
      metric: 'SD1_SD2',
      friendlyName: 'Poincaré Ratio (SD1 / SD2)',
      unit: 'ratio',
      meaning: 'Ratio of instantaneous vagal dispersion to long-term cardiac drift.',
      highMeaning: 'Dominant short-term beat-to-beat variability relative to baseline drift.',
      lowMeaning: 'Attenuated beat-to-beat variability with excessive baseline fluctuation.',
    ),
    'CSI': ClinicalMetricInfo(
      metric: 'CSI',
      friendlyName: 'Cardiac Sympathetic Index',
      unit: 'ratio',
      meaning: 'Toichi index (4·SD2 / SD1) sensitive specifically to sympathetic excitation.',
      highMeaning: 'Elevated cardiac sympathetic arousal, anxiety, tachycardia, or stress.',
      lowMeaning: 'Low sympathetic drive, calm parasympathetic predominance.',
    ),
    'CVI': ClinicalMetricInfo(
      metric: 'CVI',
      friendlyName: 'Cardiac Vagal Index',
      unit: 'log',
      meaning: 'Logarithmic evaluation of Poincaré ellipse area (log10(SD1·SD2)).',
      highMeaning: 'Robust cardiac vagal tone and healthy parasympathetic autonomic reserve.',
      lowMeaning: 'Depleted vagal reserve, high vulnerability to stress.',
    ),
    'SampEn': ClinicalMetricInfo(
      metric: 'SampEn',
      friendlyName: 'Sample Entropy',
      unit: 'entropy',
      meaning: 'Non-linear complexity and information richness of the heartbeat time-series.',
      highMeaning: 'Healthy physiological complexity, chaotic adaptive autonomic regulation.',
      lowMeaning: 'Pathological regularity, monotonous pacing, or loss of regulatory complexity.',
    ),
    'Morphology_Quality': ClinicalMetricInfo(
      metric: 'Morphology_Quality',
      friendlyName: 'PPG Morphology Quality Index (MQI)',
      unit: 'score 0–1',
      meaning: 'Signal quality metric measuring waveform SNR, fiducial definition, and template conformity.',
      highMeaning: 'Pristine pulsatile PPG waveform with clean systolic peaks and dicrotic notches.',
      lowMeaning: 'Motion artifact, sensor lift-off, peripheral vasoconstriction, or degraded perfusion.',
    ),
    'APG_b_a_Ratio': ClinicalMetricInfo(
      metric: 'APG_b_a_Ratio',
      friendlyName: 'Accelerated PPG b/a Ratio',
      unit: 'ratio',
      meaning: 'Second-derivative PPG inflection ratio biomarker of arterial wall stiffness.',
      highMeaning: 'Increased arterial stiffness, elevated vascular resistance, vascular aging.',
      lowMeaning: 'High vascular elasticity, compliant youthful arterial walls.',
    ),
    'APG_c_a_Ratio': ClinicalMetricInfo(
      metric: 'APG_c_a_Ratio',
      friendlyName: 'Accelerated PPG c/a Ratio',
      unit: 'ratio',
      meaning: 'Second-derivative wave transmission ratio reflecting late systolic wave reflections.',
      highMeaning: 'Favorable arterial wave reflection and healthy cardiac output propagation.',
      lowMeaning: 'Attenuated wave reflection or altered pulse wave velocity.',
    ),
    'APG_d_a_Ratio': ClinicalMetricInfo(
      metric: 'APG_d_a_Ratio',
      friendlyName: 'Accelerated PPG d/a Ratio',
      unit: 'ratio',
      meaning: 'Second-derivative dicrotic notch inflection reflecting aortic valve closure dynamics.',
      highMeaning: 'Youthful vascular tone and distinct, crisp aortic valve recoil.',
      lowMeaning: 'Blunted dicrotic notch, decreased peripheral reflection, vascular stiffness.',
    ),
    'APG_e_a_Ratio': ClinicalMetricInfo(
      metric: 'APG_e_a_Ratio',
      friendlyName: 'Accelerated PPG e/a Ratio',
      unit: 'ratio',
      meaning: 'Early diastolic rebound wave reflecting microvascular peripheral compliance.',
      highMeaning: 'Strong peripheral rebound and good microvascular perfusion.',
      lowMeaning: 'Attenuated diastolic rebound, peripheral vasoconstriction.',
    ),
    'Morph_Pulse_Amp': ClinicalMetricInfo(
      metric: 'Morph_Pulse_Amp',
      friendlyName: 'PPG Pulse Amplitude',
      unit: 'a.u.',
      meaning: 'Peak-to-trough pulse amplitude reflecting local microvascular pulsatile blood volume.',
      highMeaning: 'Peripheral vasodilation, warm extremities, high stroke volume.',
      lowMeaning: 'Peripheral vasoconstriction (cold hands, sympathetic stress) or weak perfusion.',
    ),
    'Morph_SD_Time_Ratio': ClinicalMetricInfo(
      metric: 'Morph_SD_Time_Ratio',
      friendlyName: 'Systolic to Diastolic Time Ratio',
      unit: 'ratio',
      meaning: 'Ratio of systolic upstroke time to diastolic runoff time within each cardiac cycle.',
      highMeaning: 'Prolonged systolic ejection relative to runoff; higher peripheral vascular load.',
      lowMeaning: 'Rapid systolic ejection with prolonged diastolic filling; efficient cardiac rest.',
    ),
    'Skin_Temperature': ClinicalMetricInfo(
      metric: 'Skin_Temperature',
      friendlyName: 'Peripheral Skin Temperature',
      unit: '°C',
      meaning: 'Contact surface finger temperature measured adjacent to the optical sensor.',
      highMeaning: 'Peripheral vasodilation, comfortable thermal state, or distal warming during sleep onset.',
      lowMeaning: 'Peripheral vasoconstriction, cold environmental exposure, or acute stress.',
    ),
    'Activity_Motion': ClinicalMetricInfo(
      metric: 'Activity_Motion',
      friendlyName: 'Activity & Motion Intensity',
      unit: 'count',
      meaning: 'Tri-axial accelerometer motion metric tracking gross and fine physical activity.',
      highMeaning: 'Active physical movement, walking, exercise, or restlessness in bed.',
      lowMeaning: 'Quiet wakefulness, stationary rest, or deep still sleep.',
    ),
  };
}

class SummaryTable extends StatefulWidget {
  final List<FeatureSummaryRow> rows;

  const SummaryTable({super.key, required this.rows});

  @override
  State<SummaryTable> createState() => _SummaryTableState();
}

class _SummaryTableState extends State<SummaryTable> {
  String _filterDomain = 'ALL';
  String _searchQuery = '';
  final Set<String> _expandedMetrics = {};

  void _showMetricExplanationDialog(BuildContext context, ClinicalMetricInfo info) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: SensioTheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: SensioTheme.accent.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.medical_information_outlined, color: SensioTheme.accent, size: 20),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(info.friendlyName, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                  Text('${info.metric} (${info.unit})', style: const TextStyle(color: Colors.white54, fontSize: 12, fontFamily: 'monospace')),
                ],
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('PHYSIOLOGICAL MEANING', style: TextStyle(color: SensioTheme.accent, fontSize: 11, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text(info.meaning, style: const TextStyle(color: Colors.white, fontSize: 13, height: 1.4)),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFF1E293B),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.white12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.arrow_upward, size: 14, color: Color(0xFF38BDF8)),
                      const SizedBox(width: 6),
                      Expanded(
                        child: RichText(
                          text: TextSpan(
                            style: const TextStyle(fontSize: 12, color: Colors.white70, height: 1.3),
                            children: [
                              const TextSpan(text: 'High: ', style: TextStyle(color: Color(0xFF38BDF8), fontWeight: FontWeight.bold)),
                              TextSpan(text: info.highMeaning),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                  const Divider(height: 14, color: Colors.white10),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.arrow_downward, size: 14, color: Color(0xFFFBBF24)),
                      const SizedBox(width: 6),
                      Expanded(
                        child: RichText(
                          text: TextSpan(
                            style: const TextStyle(fontSize: 12, color: Colors.white70, height: 1.3),
                            children: [
                              const TextSpan(text: 'Low: ', style: TextStyle(color: Color(0xFFFBBF24), fontWeight: FontWeight.bold)),
                              TextSpan(text: info.lowMeaning),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: SensioTheme.accent,
              foregroundColor: Colors.black,
            ),
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Got it', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

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
                children: ['ALL', 'Time', 'Frequency', 'Non-Linear', 'Morphology', 'Vitals & Activity'].map((d) {
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

        // Table with inline clinical descriptions
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              color: SensioTheme.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: SensioTheme.border.withValues(alpha: 0.4)),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: ListView.separated(
                itemCount: filteredRows.length,
                separatorBuilder: (ctx, idx) => Divider(height: 1, color: SensioTheme.border.withValues(alpha: 0.2)),
                itemBuilder: (context, index) {
                  final r = filteredRows[index];
                  final info = ClinicalDictionary.dictionary[r.metric];
                  final isExpanded = _expandedMetrics.contains(r.metric);

                  Color domainColor = Colors.white70;
                  if (r.domain == 'Time') domainColor = SensioTheme.accent;
                  if (r.domain == 'Frequency') domainColor = SensioTheme.ppgSignal;
                  if (r.domain == 'Non-Linear') domainColor = const Color(0xFFFBBF24);
                  if (r.domain == 'Morphology') domainColor = const Color(0xFFF472B6);
                  if (r.domain == 'Vitals & Activity') domainColor = const Color(0xFF38BDF8);

                  final isTemp = r.metric == 'Skin_Temperature';
                  final unit = isTemp ? ' °C' : (info?.unit != null && info!.unit != 'ratio' && info.unit != 'count' && info.unit != 'score 0–1' && info.unit != 'entropy' && info.unit != 'a.u.' && info.unit != 'log' ? ' ${info.unit}' : '');

                  final meanStr = r.mean.isFinite ? '${r.mean.toStringAsFixed(2)}$unit' : '-';
                  final sdStr = r.sd.isFinite ? '± ${r.sd.toStringAsFixed(2)}$unit' : '';
                  final medStr = r.median.isFinite ? '${r.median.toStringAsFixed(2)}$unit' : '-';
                  final minStr = r.minVal.isFinite ? '${r.minVal.toStringAsFixed(2)}$unit' : '-';
                  final maxStr = r.maxVal.isFinite ? '${r.maxVal.toStringAsFixed(2)}$unit' : '-';

                  return InkWell(
                    onTap: () {
                      setState(() {
                        if (isExpanded) {
                          _expandedMetrics.remove(r.metric);
                        } else {
                          _expandedMetrics.add(r.metric);
                        }
                      });
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              // Domain badge
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: domainColor.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(4),
                                  border: Border.all(color: domainColor.withValues(alpha: 0.4)),
                                ),
                                child: Text(
                                  r.domain,
                                  style: TextStyle(color: domainColor, fontSize: 10, fontWeight: FontWeight.bold),
                                ),
                              ),
                              const SizedBox(width: 10),

                              // Metric Name & Units
                              Expanded(
                                flex: 3,
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Text(
                                          r.metric,
                                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.white),
                                        ),
                                        if (info != null) ...[
                                          const SizedBox(width: 6),
                                          IconButton(
                                            padding: EdgeInsets.zero,
                                            constraints: const BoxConstraints(),
                                            icon: const Icon(Icons.info_outline, size: 14, color: Colors.white38),
                                            tooltip: 'View detailed clinical meaning',
                                            onPressed: () => _showMetricExplanationDialog(context, info),
                                          ),
                                        ],
                                      ],
                                    ),
                                    if (info != null)
                                      Text(
                                        info.meaning,
                                        style: const TextStyle(color: Colors.white54, fontSize: 11),
                                        maxLines: isExpanded ? null : 1,
                                        overflow: isExpanded ? null : TextOverflow.ellipsis,
                                      ),
                                  ],
                                ),
                              ),

                              // Mean ± SD
                              Expanded(
                                flex: 2,
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text('MEAN ± SD', style: TextStyle(color: Colors.white38, fontSize: 9)),
                                    Text(
                                      '$meanStr $sdStr',
                                      style: const TextStyle(fontFamily: 'monospace', fontSize: 12, color: Colors.white),
                                    ),
                                  ],
                                ),
                              ),

                              // Median
                              Expanded(
                                flex: 1,
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text('MEDIAN', style: TextStyle(color: Colors.white38, fontSize: 9)),
                                    Text(
                                      medStr,
                                      style: const TextStyle(fontFamily: 'monospace', fontSize: 12, color: SensioTheme.accent, fontWeight: FontWeight.bold),
                                    ),
                                  ],
                                ),
                              ),

                              // Range (Min - Max)
                              Expanded(
                                flex: 2,
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text('MIN — MAX', style: TextStyle(color: Colors.white38, fontSize: 9)),
                                    Text(
                                      '$minStr — $maxStr',
                                      style: const TextStyle(fontFamily: 'monospace', fontSize: 12, color: Colors.white70),
                                    ),
                                  ],
                                ),
                              ),

                              // Expand Chevron
                              Icon(
                                isExpanded ? Icons.expand_less : Icons.expand_more,
                                size: 18,
                                color: Colors.white38,
                              ),
                            ],
                          ),

                          // Expanded Clinical Explanation Drawer
                          if (isExpanded && info != null) ...[
                            const SizedBox(height: 10),
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: const Color(0xFF0F172A),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: domainColor.withValues(alpha: 0.3)),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const Icon(Icons.arrow_upward, size: 13, color: Color(0xFF38BDF8)),
                                      const SizedBox(width: 6),
                                      Expanded(
                                        child: RichText(
                                          text: TextSpan(
                                            style: const TextStyle(fontSize: 11, color: Colors.white70, height: 1.3),
                                            children: [
                                              const TextSpan(text: 'High: ', style: TextStyle(color: Color(0xFF38BDF8), fontWeight: FontWeight.bold)),
                                              TextSpan(text: info.highMeaning),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 6),
                                  Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const Icon(Icons.arrow_downward, size: 13, color: Color(0xFFFBBF24)),
                                      const SizedBox(width: 6),
                                      Expanded(
                                        child: RichText(
                                          text: TextSpan(
                                            style: const TextStyle(fontSize: 11, color: Colors.white70, height: 1.3),
                                            children: [
                                              const TextSpan(text: 'Low: ', style: TextStyle(color: Color(0xFFFBBF24), fontWeight: FontWeight.bold)),
                                              TextSpan(text: info.lowMeaning),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ],
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
}
