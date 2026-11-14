import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../services/app_state.dart';
import '../services/supabase_attendance_report_service.dart';
import '../theme/app_theme.dart';
import '../widgets/common_widgets.dart';
import '../widgets/data_tables.dart';

class HistoryPanel extends StatefulWidget {
  const HistoryPanel({super.key});

  @override
  State<HistoryPanel> createState() => _HistoryPanelState();
}

class _HistoryPanelState extends State<HistoryPanel> {
  String? _selectedClass;
  bool _loading = false;
  String? _error;
  Map<String, AttendanceRecord>? _data;
  bool _didInit = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_didInit) {
      _didInit = true;
      final allowed = context.read<AppState>().allowedClasses;
      if (allowed.isNotEmpty) {
        final last = context.read<AppState>().lastSelectedClass;
        _selectedClass = allowed.any((c) => c.key == last) ? last : allowed.first.key;
        WidgetsBinding.instance.addPostFrameCallback((_) => _load());
      }
    }
  }

  Future<void> _load() async {
    if (_selectedClass == null) return;
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await SupabaseAttendanceReportService().getAttendanceHistory(_selectedClass!);
      if (!mounted) return;
      setState(() {
        _data = data;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = '$error';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final allowed = context.watch<AppState>().allowedClasses;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LayoutBuilder(builder: (context, c) {
            final narrow = c.maxWidth < 480;
            final title = const CardTitleRow(
              emoji: '📋',
              title: 'ઇતિહાસ — વર્ગ મુજબ',
              iconBg: AppColors.iconAmber,
              margin: EdgeInsets.zero,
            );
            final dropdown = SizedBox(
              width: narrow ? double.infinity : 200,
              child: DropdownButtonFormField<String>(
                value: allowed.any((c) => c.key == _selectedClass) ? _selectedClass : null,
                isExpanded: true,
                items: allowed.map((c) => DropdownMenuItem(value: c.key, child: Text(c.key))).toList(),
                onChanged: (v) {
                  setState(() => _selectedClass = v);
                  _load();
                },
              ),
            );
            if (narrow) {
              return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [title, const SizedBox(height: 12), dropdown]);
            }
            return Row(
              children: [
                Expanded(child: title),
                const SizedBox(width: 12),
                dropdown,
              ],
            );
          }),
          const SizedBox(height: 16),
          if (allowed.isEmpty)
            const MessageState(text: 'તમારા ખાતા સાથે કોઈ વર્ગ જોડાયેલ નથી.')
          else if (_loading)
            const LoadingState()
          else if (_error != null)
            AlertBox(kind: AlertKind.error, text: '❌ $_error')
          else if (_data == null || _data!.isEmpty)
            const MessageState(text: 'આ વર્ગ માટે હજુ કોઈ હાજરી નોંધાઈ નથી.')
          else
            _buildTable(_data!),
        ],
      ),
    );
  }

  Widget _buildTable(Map<String, AttendanceRecord> data) {
    final dates = data.keys.toList()..sort((a, b) => a.compareTo(b));
    final appState = context.read<AppState>();
    final schoolType = appState.schoolType.toLowerCase();
    final showCategoryTotal = appState.school['reportGenderSplitEnabled'] == null
        ? true
        : appState.school['reportGenderSplitEnabled'] == true;
    if (schoolType == 'boys' || schoolType == 'girls') {
      return AttendanceStatsTable(
        firstColumnLabel: 'તારીખ',
        rows: [for (final date in dates) StatsRow(date, data[date])],
      );
    }
    final metrics = <String, String>{
      'registered': 'નોંધાયેલ વિદ્યાર્થીઓ — Boys / Girls / Total',
      'present': 'હાજરી — Boys / Girls / Total',
      'mdm': 'PM Poshan — Boys / Girls / Total',
      'breakfast': 'અલ્પાહાર — Boys / Girls / Total',
    };
    final metricRows = <GenderMetricRow>[];
    for (var i = 0; i < dates.length; i++) {
      final date = dates[i];
      final record = data[date]!;
      metricRows.add(GenderMetricRow(
        label: '${i + 1}. $date',
        registered: record.registered ?? CategoryCounts(),
        present: record.present,
        mdm: record.mdm,
        breakfastTotal: record.breakfastTotal,
        genderBreakdown: record.genderBreakdown,
      ));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final entry in metrics.entries)
          GenderCategoryMetricTable(
            title: entry.value,
            metric: entry.key,
            rows: metricRows,
            showCategoryTotal: showCategoryTotal,
          ),
      ],
    );
  }

}

