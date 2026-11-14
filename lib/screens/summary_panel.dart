import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../data/app_config.dart';
import '../models/models.dart';
import '../services/app_state.dart';
import '../services/supabase_attendance_report_service.dart';
import '../theme/app_theme.dart';
import '../widgets/common_widgets.dart';
import '../widgets/data_tables.dart';

/// "દૈનિક રિપોર્ટ (બધા વર્ગ)" - loops getRowData across all 18 class
/// sheets for one date and assembles the same grouped report the
/// original website's loadSummary() built: Registered + Present +
/// PM-Poshan + Breakfast per class, plus the group subtotal rows
/// (TOTAL 1-5 / BV-5 / 6-8 / 1-8 / BV-8).
class SummaryPanel extends StatefulWidget {
  const SummaryPanel({super.key});

  @override
  State<SummaryPanel> createState() => _SummaryPanelState();
}

class _SummaryPanelState extends State<SummaryPanel> {
  DateTime _date = DateTime.now();
  bool _loading = false;
  String? _lockMessage;
  Map<String, RowData?>? _byClass;
  bool _didInit = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_didInit) {
      _didInit = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => _load());
    }
  }

  String get _dateStr => DateFormat('yyyy-MM-dd').format(_date);

  Future<void> _load() async {
    final state = context.read<AppState>();
    if (!mounted) return;
    setState(() {
      _loading = true;
      _lockMessage = null;
      _byClass = null;
    });

    if (_date.weekday == DateTime.sunday) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _lockMessage = 'રવિવાર હોવાથી આ તારીખનો દૈનિક અહેવાલ ઉપલબ્ધ નથી.';
      });
      return;
    }

    final holidayReason = state.holidays[_dateStr];
    if (holidayReason != null) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _lockMessage = 'આ તારીખે જાહેર રજા છે: $holidayReason';
      });
      return;
    }

    final classes = state.allowedClasses;
    if (classes.isEmpty) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _lockMessage = 'તમારા ખાતા સાથે કોઈ વર્ગ જોડાયેલ નથી.';
      });
      return;
    }

    final reportService = SupabaseAttendanceReportService();
    Object? firstError;
    final results = await Future.wait(classes.map((schoolClass) async {
      try {
        final row = await reportService.getRowData(schoolClass.key, _dateStr);
        return MapEntry<String, RowData?>(schoolClass.key, row);
      } catch (error) {
        firstError ??= error;
        return MapEntry<String, RowData?>(schoolClass.key, null);
      }
    }));

    if (!mounted) return;
    final allFailed = results.isNotEmpty && results.every((entry) => entry.value == null);
    setState(() {
      _byClass = {for (final entry in results) entry.key: entry.value};
      _loading = false;
      if (allFailed) {
        _lockMessage = 'Supabase માંથી હાજરીનો અહેવાલ લોડ થયો નથી: ${firstError ?? 'અજ્ઞાત ભૂલ'}';
      }
    });
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2020),
      lastDate: DateTime(2035),
    );
    if (picked != null) {
      setState(() => _date = picked);
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LayoutBuilder(builder: (context, c) {
            final narrow = c.maxWidth < 480;
            final title = const CardTitleRow(
              emoji: '📊',
              title: 'દૈનિક રિપોર્ટ (બધા વર્ગ)',
              iconBg: AppColors.iconGreen,
              margin: EdgeInsets.zero,
            );
            final dateBtn = InkWell(
              onTap: _pickDate,
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 14),
                decoration: BoxDecoration(
                  color: AppColors.slateLight,
                  border: Border.all(color: AppColors.border, width: 1.5),
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                ),
                child: Text('📅 $_dateStr', style: guFont(fontSize: 13, fontWeight: FontWeight.w700)),
              ),
            );
            if (narrow) {
              return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [title, const SizedBox(height: 12), dateBtn]);
            }
            return Row(children: [Expanded(child: title), const SizedBox(width: 12), dateBtn]);
          }),
          const SizedBox(height: 16),
          if (_loading)
            const LoadingState(label: 'બધા વર્ગનો ડેટા લોડ થાય છે… (આમાં થોડો સમય લાગી શકે છે)')
          else if (_lockMessage != null)
            AlertBox(kind: AlertKind.error, text: _lockMessage!)
          else if (_byClass != null) ...[
            if (context.watch<AppState>().schoolType.toLowerCase() == 'boys' || context.watch<AppState>().schoolType.toLowerCase() == 'girls')
              SummaryReportTable(rows: _buildLegacySummaryRows(_byClass!))
            else ...[
              for (final metric in const <(String, String)>[
                ('registered', 'નોંધાયેલ વિદ્યાર્થીઓ — Boys / Girls / Total'),
                ('present', 'હાજરી — Boys / Girls / Total'),
                ('mdm', 'PM Poshan — Boys / Girls / Total'),
                ('breakfast', 'અલ્પાહાર — Boys / Girls / Total'),
              ])
                GenderCategoryMetricTable(
                  title: metric.$2,
                  metric: metric.$1,
                  rows: _buildGenderMetricRows(_byClass!, metric.$1),
                  showCategoryTotal: context.watch<AppState>().school['reportGenderSplitEnabled'] == null
                      ? true
                      : context.watch<AppState>().school['reportGenderSplitEnabled'] == true,
                ),
              Text('દરેક કેટેગરીમાં Total = Boys + Girls. જૂના રેકોર્ડમાં લિંગની માહિતી ઉપલબ્ધ ન હોય તો તે અલગ બાકી રહે છે અને તેને છોકરા/છોકરી તરીકે અનુમાનથી ઉમેરવામાં આવતું નથી.',
                  style: guFont(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.slate)),
            ],
          ],
        ],
      ),
    );
  }

  List<SummaryRow> _buildLegacySummaryRows(Map<String, RowData?> byClass) {
    final rows = <SummaryRow>[];
    final registered = CategoryCounts();
    final present = CategoryCounts();
    final mdm = CategoryCounts();
    var breakfast = 0;
    for (final schoolClass in context.read<AppState>().allSchoolClasses) {
      final row = byClass[schoolClass.key];
      final reg = row?.registered ?? CategoryCounts();
      final rec = row?.attendance;
      final pres = rec?.present ?? CategoryCounts();
      final meal = rec?.mdm ?? CategoryCounts();
      final bf = rec?.breakfastTotal ?? 0;
      rows.add(SummaryRow(label: schoolClass.label, reg: reg, present: pres, mdm: meal, bf: bf));
      for (final category in Category.values) {
        registered.set(category, registered[category] + reg[category]);
        present.set(category, present[category] + pres[category]);
        mdm.set(category, mdm[category] + meal[category]);
      }
      breakfast += bf;
    }
    rows.add(SummaryRow(label: 'TOTAL SCHOOL', reg: registered, present: present, mdm: mdm, bf: breakfast, isSubtotal: true));
    return rows;
  }

  Map<String, dynamic> _addGenderMaps(Map<String, dynamic> left, Map<String, dynamic> right) {
    final out = <String, dynamic>{};
    for (final gender in ['BOYS', 'GIRLS', 'UNSPECIFIED']) {
      final combined = <String, dynamic>{};
      for (final category in ['SC', 'ST', 'OBC', 'OTHER']) {
        final a = left[gender] is Map ? (left[gender] as Map)[category] : null;
        final b = right[gender] is Map ? (right[gender] as Map)[category] : null;
        if (a is Map || b is Map) {
          final metricValues = <String, dynamic>{};
          for (final metric in ['registered', 'present', 'mdm', 'breakfast']) {
            final av = a is Map ? int.tryParse('${a[metric] ?? 0}') ?? 0 : 0;
            final bv = b is Map ? int.tryParse('${b[metric] ?? 0}') ?? 0 : 0;
            metricValues[metric] = av + bv;
          }
          combined[category] = metricValues;
        }
      }
      final aOverall = left[gender] is Map ? (left[gender] as Map)['_OVERALL'] : null;
      final bOverall = right[gender] is Map ? (right[gender] as Map)['_OVERALL'] : null;
      if (aOverall is Map || bOverall is Map) {
        final overallValues = <String, dynamic>{};
        for (final metric in ['registered', 'present', 'mdm', 'breakfast']) {
          final av = aOverall is Map ? int.tryParse('${aOverall[metric] ?? 0}') ?? 0 : 0;
          final bv = bOverall is Map ? int.tryParse('${bOverall[metric] ?? 0}') ?? 0 : 0;
          overallValues[metric] = av + bv;
        }
        combined['_OVERALL'] = overallValues;
      }
      if (combined.isNotEmpty) out[gender] = combined;
    }
    return out;
  }

  List<GenderMetricRow> _buildGenderMetricRows(Map<String, RowData?> byClass, String metric) {
    final rows = <GenderMetricRow>[];
    final totalReg = CategoryCounts();
    final totalPresent = CategoryCounts();
    final totalMdm = CategoryCounts();
    var totalBreakfast = 0;
    var totalGender = <String, dynamic>{};

    for (final schoolClass in context.read<AppState>().allSchoolClasses) {
      final data = byClass[schoolClass.key];
      final attendance = data?.attendance;
      final registered = data?.registered ?? CategoryCounts();
      final present = attendance?.present ?? CategoryCounts();
      final mdm = attendance?.mdm ?? CategoryCounts();
      final breakfast = attendance?.breakfastTotal ?? 0;
      final gender = data?.genderBreakdown ?? attendance?.genderBreakdown ?? const <String, dynamic>{};

      rows.add(GenderMetricRow(
        label: schoolClass.label,
        registered: registered,
        present: present,
        mdm: mdm,
        breakfastTotal: breakfast,
        genderBreakdown: gender,
      ));
      for (final cat in Category.values) {
        totalReg.set(cat, totalReg[cat] + registered[cat]);
        totalPresent.set(cat, totalPresent[cat] + present[cat]);
        totalMdm.set(cat, totalMdm[cat] + mdm[cat]);
      }
      totalBreakfast += breakfast;
      totalGender = _addGenderMaps(totalGender, gender);
    }

    rows.add(GenderMetricRow(
      label: 'TOTAL SCHOOL',
      registered: totalReg,
      present: totalPresent,
      mdm: totalMdm,
      breakfastTotal: totalBreakfast,
      genderBreakdown: totalGender,
      isSubtotal: true,
    ));
    return rows;
  }

}



