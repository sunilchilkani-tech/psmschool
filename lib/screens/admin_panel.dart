import 'dart:typed_data';
import 'dart:convert';

import 'package:excel_community/excel_community.dart' as xls;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:share_plus/share_plus.dart';

import '../models/models.dart';
import '../data/app_config.dart';
import '../data/datewise_report_options.dart';
import '../services/app_state.dart';
import '../services/supabase_attendance_report_service.dart';
import '../theme/app_theme.dart';
import '../widgets/common_widgets.dart';
import '../widgets/dialogs.dart';
import '../widgets/admin_daily_attendance_dashboard.dart';
import 'setup_screen.dart';

/// "🏖️ રજા મેનેજર (ફક્ત આચાર્ય માટે)" block - holiday manager, app
/// settings (URL / password), and teacher messaging. Only rendered
/// when `AppState.isAdmin` is true.
class AdminPanel extends StatefulWidget {
  const AdminPanel({super.key});

  @override
  State<AdminPanel> createState() => _AdminPanelState();
}

class _AdminPanelState extends State<AdminPanel> {
  final _holidayDateCtrl = TextEditingController();
  DateTime? _holidayDate;
  final _holidayReasonCtrl = TextEditingController();
  bool _savingHoliday = false;

  DateTime? _msgDate;
  final _msgDateCtrl = TextEditingController();
  final _msgTextCtrl = TextEditingController();
  bool _sendingMsg = false;

  List<AdminMessage>? _messages;
  String? _messagesError;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadMessages());
  }

  @override
  void dispose() {
    _holidayDateCtrl.dispose();
    _holidayReasonCtrl.dispose();
    _msgDateCtrl.dispose();
    _msgTextCtrl.dispose();
    super.dispose();
  }

  Future<void> _openResultLockManager() async {
    String selectedClass = 'ALL';
    String selectedSem = '1';
    bool isLocked = true;
    bool isSaving = false;

    final classOptions = context.read<AppState>().allSchoolClasses;
    List<String> classes = [
      'ALL (બધા જ ધોરણ)',
      ...classOptions.map((c) => c.key),
    ];

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) {
          return AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            title: Text(
              '🔒 પરિણામ Lock / Unlock સેટિંગ્સ',
              style: guFont(fontWeight: FontWeight.bold, color: AppColors.navy),
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'જે સત્રનું પરિણામ લોક કરશો, તેમાં શિક્ષકો નવો ડેટા સેવ નહિ કરી શકે (માત્ર પ્રિન્ટ કાઢી શકશે).',
                  style: guFont(fontSize: 12, color: AppColors.slate),
                ),
                const SizedBox(height: 12),
                LabeledField(
                  label: 'ધોરણ પસંદ કરો',
                  child: DropdownButtonFormField<String>(
                    value: selectedClass,
                    isExpanded: true,
                    items: classes
                        .map(
                          (c) => DropdownMenuItem(
                            value: c == 'ALL (બધા જ ધોરણ)' ? 'ALL' : c,
                            child: Text(c),
                          ),
                        )
                        .toList(),
                    onChanged: (v) => setD(() => selectedClass = v!),
                  ),
                ),
                const SizedBox(height: 12),
                LabeledField(
                  label: 'સત્ર પસંદ કરો',
                  child: DropdownButtonFormField<String>(
                    value: selectedSem,
                    isExpanded: true,
                    items: const [
                      DropdownMenuItem(
                        value: '1',
                        child: Text('પ્રથમ સત્ર (Sem 1)'),
                      ),
                      DropdownMenuItem(
                        value: '2',
                        child: Text('દ્વિતીય સત્ર / વાર્ષિક (Sem 2)'),
                      ),
                    ],
                    onChanged: (v) => setD(() => selectedSem = v!),
                  ),
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 10,
                  children: [
                    ChoiceChip(
                      label: Text(
                        '🔒 LOCK કરો',
                        style: guFont(
                          fontWeight: FontWeight.bold,
                          color: isLocked ? Colors.white : AppColors.rose,
                        ),
                      ),
                      selected: isLocked,
                      selectedColor: AppColors.rose,
                      onSelected: (v) => setD(() => isLocked = true),
                    ),
                    ChoiceChip(
                      label: Text(
                        '🔓 UNLOCK કરો',
                        style: guFont(
                          fontWeight: FontWeight.bold,
                          color: !isLocked ? Colors.white : AppColors.greenDeep,
                        ),
                      ),
                      selected: !isLocked,
                      selectedColor: AppColors.greenDeep,
                      onSelected: (v) => setD(() => isLocked = false),
                    ),
                  ],
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('રદ કરો'),
              ),
              AppButton(
                label: isSaving ? 'સેવ થાય છે...' : '💾 સેટિંગ્સ લાગુ કરો',
                background: AppColors.navy,
                loading: isSaving,
                onPressed: isSaving
                    ? null
                    : () async {
                        setD(() => isSaving = true);
                        try {
                          final res = await context
                              .read<AppState>()
                              .resultApi!
                              .toggleResultLock(
                                className: selectedClass,
                                sem: selectedSem,
                                isLocked: isLocked,
                              );
                          if (ctx.mounted) Navigator.pop(ctx);
                          if (mounted)
                            showSnack(
                              context,
                              '✅ સેટિંગ્સ સફળતાપૂર્વક લાગુ થઈ ગયા!',
                            );
                        } catch (e) {
                          setD(() => isSaving = false);
                          if (mounted)
                            showSnack(context, '❌ Error: $e', error: true);
                        }
                      },
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _manageDateWiseColumns() async {
    final state = context.read<AppState>();
    if (!state.isAdmin) return;
    final service = SupabaseAttendanceReportService();
    showBusyDialog(context, 'DATE WISE column settings લોડ થાય છે…');
    List<String> loadedKeys;
    try {
      loadedKeys = await service.getDateWiseSelectedColumnKeys();
    } catch (e) {
      if (mounted) {
        hideBusyDialog(context);
        showSnack(
          context,
          '❌ DATE WISE settings લોડ ન થઈ શક્યાં: $e',
          error: true,
        );
      }
      return;
    }
    if (!mounted) return;
    hideBusyDialog(context);

    final selectedKeys = <String>{
      ...(loadedKeys.isEmpty ? DateWiseReportColumns.allKeyList : loadedKeys),
    }..retainAll(DateWiseReportColumns.allKeys);
    // A fresh school shows every column selected until the admin changes this.
    if (selectedKeys.isEmpty)
      selectedKeys.addAll(DateWiseReportColumns.allKeyList);
    final searchCtrl = TextEditingController();
    bool saving = false;
    String? error;

    try {
      await showDialog<void>(
        context: context,
        barrierDismissible: !saving,
        builder: (ctx) => StatefulBuilder(
          builder: (ctx, setD) {
            final search = searchCtrl.text.trim().toLowerCase();
            final visible = DateWiseReportColumns.all
                .where(
                  (option) =>
                      search.isEmpty ||
                      option.label.toLowerCase().contains(search) ||
                      option.key.toLowerCase().contains(search),
                )
                .toList();
            return AlertDialog(
              title: Text(
                '📊 DATE WISE — Column Selection',
                style: guFont(
                  fontWeight: FontWeight.w800,
                  color: AppColors.navy,
                ),
              ),
              content: SizedBox(
                width: 700,
                height: 540,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'આ પસંદગી આખી શાળા માટે એક જ વાર સેટ થશે. શિક્ષકોને આ settings બદલવાનો વિકલ્પ નહીં મળે.',
                      style: guFont(fontSize: 12, color: AppColors.slate),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: searchCtrl,
                      decoration: const InputDecoration(
                        prefixIcon: Icon(Icons.search),
                        hintText: 'Column શોધો…',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      onChanged: (_) => setD(() {}),
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 8,
                      children: [
                        TextButton.icon(
                          onPressed: saving
                              ? null
                              : () => setD(
                                  () => selectedKeys.addAll(
                                    DateWiseReportColumns.allKeyList,
                                  ),
                                ),
                          icon: const Icon(Icons.select_all),
                          label: const Text('Select All'),
                        ),
                        TextButton.icon(
                          onPressed: saving
                              ? null
                              : () => setD(
                                  () => selectedKeys.removeWhere(
                                    (key) => DateWiseReportColumns.allKeys
                                        .contains(key),
                                  ),
                                ),
                          icon: const Icon(Icons.deselect),
                          label: const Text('Clear Selection'),
                        ),
                      ],
                    ),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        '${selectedKeys.length} / ${DateWiseReportColumns.all.length} columns selected',
                        style: guFont(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          color: AppColors.navy,
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Expanded(
                      child: ListView.builder(
                        itemCount: visible.length,
                        itemBuilder: (context, index) {
                          final option = visible[index];
                          return CheckboxListTile(
                            dense: true,
                            value: selectedKeys.contains(option.key),
                            title: Text(
                              option.label,
                              style: guFont(fontSize: 12.5),
                            ),
                            controlAffinity: ListTileControlAffinity.leading,
                            contentPadding: EdgeInsets.zero,
                            onChanged: saving
                                ? null
                                : (checked) => setD(() {
                                    if (checked == true) {
                                      selectedKeys.add(option.key);
                                    } else {
                                      selectedKeys.remove(option.key);
                                    }
                                  }),
                          );
                        },
                      ),
                    ),
                    if (error != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(
                          error!,
                          style: guFont(
                            color: AppColors.rose,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: saving ? null : () => Navigator.pop(ctx),
                  child: const Text('Cancel'),
                ),
                AppButton(
                  label: saving ? 'Saving…' : '💾 Save for Entire School',
                  background: AppColors.navy,
                  loading: saving,
                  onPressed: saving
                      ? null
                      : () async {
                          if (selectedKeys.isEmpty) {
                            setD(
                              () => error = 'ઓછામાં ઓછો એક column પસંદ કરો.',
                            );
                            return;
                          }
                          setD(() {
                            saving = true;
                            error = null;
                          });
                          try {
                            await service.saveDateWiseSelectedColumnKeys(
                              DateWiseReportColumns.allKeyList
                                  .where(selectedKeys.contains)
                                  .toList(),
                            );
                            if (ctx.mounted) Navigator.pop(ctx);
                            if (mounted)
                              showSnack(
                                context,
                                '✅ DATE WISE columns આખી શાળા માટે સેવ થયા.',
                              );
                          } catch (e) {
                            setD(() {
                              saving = false;
                              error = '$e';
                            });
                          }
                        },
                ),
              ],
            );
          },
        ),
      );
    } finally {
      searchCtrl.dispose();
    }
  }

  String _excelCellText(dynamic cell) {
    if (cell == null || cell.value == null) return '';
    final value = cell.value;
    if (value is xls.TextCellValue) return value.value.toString().trim();
    if (value is xls.IntCellValue) return value.value.toString();
    if (value is xls.DoubleCellValue) {
      final number = value.value;
      return number == number.truncateToDouble()
          ? number.toInt().toString()
          : number.toString();
    }
    if (value is xls.DateCellValue) {
      return DateFormat('dd/MM/yyyy')
          .format(DateTime(value.year, value.month, value.day));
    }
    if (value is xls.DateTimeCellValue) {
      return DateFormat('dd/MM/yyyy')
          .format(DateTime(value.year, value.month, value.day));
    }
    return value.toString().trim();
  }

  String _excelDateToIso(dynamic cell) {
    if (cell != null && cell.value is xls.DateCellValue) {
      final value = cell.value as xls.DateCellValue;
      return DateFormat('yyyy-MM-dd')
          .format(DateTime(value.year, value.month, value.day));
    }
    if (cell != null && cell.value is xls.DateTimeCellValue) {
      final value = cell.value as xls.DateTimeCellValue;
      return DateFormat('yyyy-MM-dd')
          .format(DateTime(value.year, value.month, value.day));
    }
    final raw = _excelCellText(cell).trim();
    if (raw.isEmpty) return '';
    final number = double.tryParse(raw);
    if (number != null && number >= 20000 && number <= 90000) {
      final date = DateTime(1899, 12, 30).add(Duration(days: number.floor()));
      return DateFormat('yyyy-MM-dd').format(date);
    }
    final iso = DateTime.tryParse(raw);
    if (iso != null) return DateFormat('yyyy-MM-dd').format(iso);
    for (final pattern in const [
      'dd/MM/yyyy',
      'd/M/yyyy',
      'MM/dd/yyyy',
      'M/d/yyyy',
      'dd-MM-yyyy',
    ]) {
      try {
        return DateFormat(pattern)
            .parseStrict(raw)
            .toIso8601String()
            .substring(0, 10);
      } catch (_) {}
    }
    return '';
  }

  String _normalizeExcelHeader(String value) =>
      value.trim().toLowerCase().replaceAll(RegExp(r'[\s/_\-:()]+'), '');

  Future<void> _shareExcel({
    required String fileName,
    required String sheetName,
    required List<String> headers,
    required List<List<dynamic>> rows,
    required String shareText,
  }) async {
    final workbook = xls.Excel.createExcel();
    workbook.rename('Sheet1', sheetName);
    final sheet = workbook[sheetName];
    sheet.appendRow(headers.map((value) => xls.TextCellValue(value)).toList());
    for (final row in rows) {
      sheet.appendRow(
        row
            .map((value) => xls.TextCellValue(value == null ? '' : '$value'))
            .toList(),
      );
    }
    final bytes = workbook.encode();
    if (bytes == null || bytes.isEmpty)
      throw StateError('Excel ફાઈલ બનાવી શકાઈ નથી.');
    await Share.shareXFiles([
      XFile.fromData(
        Uint8List.fromList(bytes),
        name: fileName,
        mimeType:
            'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      ),
    ], text: shareText);
  }

  Future<void> _exportAdminMessages() async {
    final messages = await context.read<AppState>().api!.getMessages();
    messages.sort((a, b) => a.date.compareTo(b.date));
    await _shareExcel(
      fileName: 'AdminMessages.xlsx',
      sheetName: 'AdminMessage',
      headers: const ['Date', 'Message'],
      rows: messages.map((item) => <dynamic>[item.date, item.message]).toList(),
      shareText: 'School Admin Messages export',
    );
  }

  Future<void> _exportHolidays() async {
    final holidays = await context.read<AppState>().api!.getHolidays();
    final dates = holidays.keys.toList()..sort();
    await _shareExcel(
      fileName: 'SchoolHolidays.xlsx',
      sheetName: 'Holidays',
      headers: const ['Date', 'Reason'],
      rows: dates.map((date) => <dynamic>[date, holidays[date] ?? '']).toList(),
      shareText: 'School Holidays export',
    );
  }

  Future<void> _exportTeacherLeaveRecords() async {
    final response = await context
        .read<AppState>()
        .api!
        .getAllTeacherLeaveRecords();
    if (response['result'] != 'success') {
      throw StateError(
        '${response['message'] ?? 'Leave records export failed.'}',
      );
    }
    final leaves = (response['leaves'] as List? ?? const [])
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList();
    await _shareExcel(
      fileName: 'TeacherLeaveRecords.xlsx',
      sheetName: 'LeaveRecords',
      headers: const [
        'ID',
        'Teacher',
        'Charge Teacher',
        'From Date',
        'To Date',
        'Days',
        'Type',
        'Reason',
        'Status',
        'Timestamp',
      ],
      rows: leaves
          .map(
            (item) => <dynamic>[
              item['id'],
              item['teacher'],
              item['chargeTeacher'],
              item['fromDate'],
              item['toDate'],
              item['days'],
              item['leaveType'],
              item['reason'],
              item['status'],
              item['timestamp'],
            ],
          )
          .toList(),
      shareText: 'Teacher leave records export',
    );
  }

  Future<void> _importAdminRecords(String kind) async {
    final state = context.read<AppState>();
    if (!state.isAdmin || state.api == null) return;
    final selected = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['xlsx'],
      withData: true,
      allowMultiple: false,
    );
    if (selected == null || selected.files.isEmpty) return;
    final bytes = selected.files.single.bytes;
    if (bytes == null || bytes.isEmpty)
      throw StateError('Excel ફાઈલ વાંચી શકાઈ નથી.');

    final workbook = xls.Excel.decodeBytes(bytes);
    xls.Sheet? source;
    for (final name in workbook.tables.keys) {
      final sheet = workbook.tables[name];
      if (sheet != null && sheet.rows.isNotEmpty) {
        source = sheet;
        break;
      }
    }
    if (source == null)
      throw StateError('Excel ફાઈલમાં કોઈ sheet અથવા data મળ્યો નથી.');

    List<String>? headers;
    var headerRow = -1;
    final allRows = source.rows;
    for (var i = 0; i < allRows.length; i++) {
      final values = allRows[i].map(_excelCellText).toList();
      final normalized = values.map(_normalizeExcelHeader).toList();
      final hasDate = normalized.any(
        (value) => value == 'date' || value == 'તારીખ',
      );
      final hasValue = kind == 'messages'
          ? normalized.any((value) => value == 'message' || value == 'સંદેશ')
          : normalized.any(
              (value) =>
                  value == 'reason' || value == 'કારણ' || value == 'રજાનુંનામ',
            );
      if (hasDate && hasValue) {
        headers = values;
        headerRow = i;
        break;
      }
    }
    if (headers == null) {
      throw StateError(
        kind == 'messages'
            ? 'Messages Excel માં Date અને Message headers જરૂરી છે.'
            : 'Holidays Excel માં Date અને Reason headers જરૂરી છે.',
      );
    }

    final normalizedHeaders = headers.map(_normalizeExcelHeader).toList();
    final dateIndex = normalizedHeaders.indexWhere(
      (value) => value == 'date' || value == 'તારીખ',
    );
    final valueIndex = kind == 'messages'
        ? normalizedHeaders.indexWhere(
            (value) => value == 'message' || value == 'સંદેશ',
          )
        : normalizedHeaders.indexWhere(
            (value) =>
                value == 'reason' || value == 'કારણ' || value == 'રજાનુંનામ',
          );
    final records = <Map<String, dynamic>>[];
    for (var i = headerRow + 1; i < allRows.length; i++) {
      final row = allRows[i];
      final date = _excelDateToIso(
        dateIndex >= 0 && dateIndex < row.length ? row[dateIndex] : null,
      );
      final value = _excelCellText(
        valueIndex >= 0 && valueIndex < row.length ? row[valueIndex] : null,
      );
      if (date.isEmpty || value.isEmpty) continue;
      records.add(
        kind == 'messages'
            ? <String, dynamic>{'date': date, 'message': value}
            : <String, dynamic>{'date': date, 'reason': value},
      );
    }
    if (records.isEmpty)
      throw StateError('Excel માંથી કોઈ માન્ય record મળ્યો નથી.');

    final response = await state.api!.importAdminRecords(
      kind: kind,
      records: records,
    );
    if (response['result'] != 'success' && response['result'] != 'partial') {
      throw StateError('${response['message'] ?? 'Records import failed.'}');
    }
    if (kind == 'messages') {
      await _loadMessages();
    } else {
      await state.refreshHolidays();
    }
    if (mounted) {
      final partial = response['result'] == 'partial';
      final message =
          response['message']?.toString() ??
          '${response['imported'] ?? records.length} records import થયા.';
      showSnack(
        context,
        partial ? '⚠️ $message' : '✅ $message',
        error: partial,
      );
    }
  }

  Future<void> _openAdminDataTransferDialog() async {
    final state = context.read<AppState>();
    if (!state.isAdmin || state.api == null) return;
    bool busy = false;
    String? error;
    Future<void> runAction(
      Future<void> Function() action,
      void Function(void Function()) setD,
    ) async {
      setD(() {
        busy = true;
        error = null;
      });
      try {
        await action();
      } catch (e) {
        setD(() {
          error = '$e';
        });
      } finally {
        setD(() {
          busy = false;
        });
      }
    }

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: Text(
            '📂 Admin Records — Excel Import / Export',
            style: guFont(fontWeight: FontWeight.w800, color: AppColors.navy),
          ),
          content: SizedBox(
            width: 560,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'આ controls ફક્ત Admin માટે છે. Import date પ્રમાણે record ઉમેરે/અપડેટ કરે છે; ફાઈલમાં ન હોય તેવા જૂના records delete નહીં કરે.',
                    style: guFont(fontSize: 12, color: AppColors.slate),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    'Admin Messages',
                    style: guFont(fontWeight: FontWeight.w800),
                  ),
                  Wrap(
                    spacing: 8,
                    children: [
                      OutlinedButton.icon(
                        onPressed: busy
                            ? null
                            : () => runAction(_exportAdminMessages, setD),
                        icon: const Icon(Icons.download),
                        label: const Text('Export Messages'),
                      ),
                      OutlinedButton.icon(
                        onPressed: busy
                            ? null
                            : () => runAction(
                                () => _importAdminRecords('messages'),
                                setD,
                              ),
                        icon: const Icon(Icons.upload_file),
                        label: const Text('Import Messages'),
                      ),
                    ],
                  ),
                  const Divider(height: 22),
                  Text('Holidays', style: guFont(fontWeight: FontWeight.w800)),
                  Wrap(
                    spacing: 8,
                    children: [
                      OutlinedButton.icon(
                        onPressed: busy
                            ? null
                            : () => runAction(_exportHolidays, setD),
                        icon: const Icon(Icons.download),
                        label: const Text('Export Holidays'),
                      ),
                      OutlinedButton.icon(
                        onPressed: busy
                            ? null
                            : () => runAction(
                                () => _importAdminRecords('holidays'),
                                setD,
                              ),
                        icon: const Icon(Icons.upload_file),
                        label: const Text('Import Holidays'),
                      ),
                    ],
                  ),
                  const Divider(height: 22),
                  Text(
                    'Teacher Leave Records',
                    style: guFont(fontWeight: FontWeight.w800),
                  ),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: OutlinedButton.icon(
                      onPressed: busy
                          ? null
                          : () => runAction(_exportTeacherLeaveRecords, setD),
                      icon: const Icon(Icons.download),
                      label: const Text('Export All Leave Records'),
                    ),
                  ),
                  if (busy)
                    const Padding(
                      padding: EdgeInsets.only(top: 12),
                      child: LinearProgressIndicator(),
                    ),
                  if (error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Text(
                        error!,
                        style: guFont(
                          color: AppColors.rose,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: busy ? null : () => Navigator.pop(ctx),
              child: const Text('Close'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _loadMessages() async {
    final api = context.read<AppState>().api;
    if (api == null) return;
    try {
      final list = await api.getMessages();
      list.sort((a, b) => b.date.compareTo(a.date));
      if (!mounted) return;
      setState(() {
        _messages = list;
        _messagesError = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _messagesError = '$e');
    }
  }

  Future<void> _openHeaderManager() async {
    final api = context.read<AppState>().api!;
    showBusyDialog(context, 'Headers લાવે છે...');
    List<String> currentHeaders = [];
    try {
      currentHeaders = await api.getCustomHeaders();
      while (currentHeaders.length < 11) currentHeaders.add('');
    } catch (e) {
      if (mounted) {
        hideBusyDialog(context);
        showSnack(context, 'Error: $e', error: true);
      }
      return;
    }
    if (!mounted) return;
    hideBusyDialog(context);

    List<TextEditingController> ctrls = List.generate(
      11,
      (i) => TextEditingController(text: currentHeaders[i]),
    );
    bool isSaving = false;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) {
          return AlertDialog(
            title: Text(
              '🛠️ Custom Headers (BP થી BZ)',
              style: guFont(fontWeight: FontWeight.bold),
            ),
            content: SizedBox(
              width: double.maxFinite,
              height: 400,
              child: ListView.builder(
                itemCount: 11,
                itemBuilder: (_, i) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: LabeledField(
                    label:
                        'Column ${String.fromCharCode(66)}${String.fromCharCode(80 + i)}', // BP, BQ...
                    child: TextField(
                      controller: ctrls[i],
                      decoration: const InputDecoration(
                        hintText: 'હેડરનું નામ લખો (ખાલી રાખશો તો નહિ દેખાય)',
                      ),
                    ),
                  ),
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('રદ કરો'),
              ),
              AppButton(
                label: '💾 સેવ કરો',
                loading: isSaving,
                onPressed: isSaving
                    ? null
                    : () async {
                        setD(() => isSaving = true);
                        try {
                          await api.saveCustomHeaders(
                            ctrls.map((c) => c.text.trim()).toList(),
                          );
                          if (ctx.mounted) Navigator.pop(ctx);
                          if (mounted)
                            showSnack(context, '✅ Headers સેવ થઈ ગયા!');
                        } catch (e) {
                          setD(() => isSaving = false);
                          if (mounted)
                            showSnack(context, '❌ $e', error: true);
                        }
                      },
              ),
            ],
          );
        },
      ),
    );
  }

  /// Returns the message text already saved for the currently-selected
  /// message date (if any), mirroring the site's onMsgDateChange preview.
  String? _msgExistingPreview() {
    if (_msgDate == null || _messages == null) return null;
    final dateStr = DateFormat('yyyy-MM-dd').format(_msgDate!);
    for (final m in _messages!) {
      if (m.date == dateStr) return m.message;
    }
    return null;
  }

  Future<void> _addHoliday() async {
    final api = context.read<AppState>().api;
    if (api == null || _holidayDate == null) return;
    final dateStr = DateFormat('yyyy-MM-dd').format(_holidayDate!);
    final reason = _holidayReasonCtrl.text.trim().isEmpty
        ? 'જાહેર રજા'
        : _holidayReasonCtrl.text.trim();
    setState(() => _savingHoliday = true);
    try {
      await api.saveHoliday(dateStr, reason);
      if (!mounted) return;
      _holidayDate = null;
      _holidayDateCtrl.clear();
      _holidayReasonCtrl.clear();
      await context.read<AppState>().refreshHolidays();
      if (mounted) showSnack(context, '✅ રજા ઉમેરાઈ.');
    } catch (e) {
      if (mounted) showSnack(context, '❌ $e', error: true);
    } finally {
      if (mounted) setState(() => _savingHoliday = false);
    }
  }

  Future<void> _deleteHoliday(String date) async {
    final ok = await showConfirmDialog(
      context,
      message: '$date ની રજા દૂર કરવી છે?',
    );
    if (!ok) return;
    final api = context.read<AppState>().api;
    if (api == null) return;
    try {
      await api.deleteHoliday(date);
      await context.read<AppState>().refreshHolidays();
      if (mounted) showSnack(context, '✅ રજા દૂર કરી.');
    } catch (e) {
      if (mounted) showSnack(context, '❌ $e', error: true);
    }
  }

  Future<void> _sendMessage() async {
    final api = context.read<AppState>().api;
    if (api == null || _msgDate == null || _msgTextCtrl.text.trim().isEmpty) {
      showSnack(context, 'તારીખ અને સંદેશ બંને જરૂરી છે.', error: true);
      return;
    }
    setState(() => _sendingMsg = true);
    try {
      final dateStr = DateFormat('yyyy-MM-dd').format(_msgDate!);
      await api.saveMessage(dateStr, _msgTextCtrl.text.trim());
      _msgDate = null;
      _msgDateCtrl.clear();
      _msgTextCtrl.clear();
      await _loadMessages();
      if (mounted) showSnack(context, '✅ સંદેશ મોકલાયો.');
    } catch (e) {
      if (mounted) showSnack(context, '❌ $e', error: true);
    } finally {
      if (mounted) setState(() => _sendingMsg = false);
    }
  }

  Future<void> _deleteMessage(String date) async {
    final ok = await showConfirmDialog(
      context,
      message: '$date નો સંદેશ ડિલીટ કરવો છે?',
    );
    if (!ok) return;
    final api = context.read<AppState>().api;
    if (api == null) return;
    try {
      await api.deleteMessage(date);
      await _loadMessages();
      if (mounted) showSnack(context, '✅ સંદેશ ડિલીટ થયો.');
    } catch (e) {
      if (mounted) showSnack(context, '❌ $e', error: true);
    }
  }

  Future<void> _changeUrl() async {
    if (!context.read<AppState>().isAdmin) return;
    await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const SetupScreen(isChangeFlow: true)),
    );
  }

  Future<void> _manageSchoolProfile() async {
    final state = context.read<AppState>();
    if (!state.isAdmin || state.api == null) return;
    final school = Map<String, dynamic>.from(state.school);
    final name = TextEditingController(text: '${school['schoolName'] ?? ''}');
    final village = TextEditingController(text: '${school['village'] ?? ''}');
    final taluka = TextEditingController(text: '${school['taluka'] ?? ''}');
    final district = TextEditingController(text: '${school['district'] ?? ''}');
    final centerName = TextEditingController(
      text: '${school['centerName'] ?? ''}',
    );
    final crcName = TextEditingController(text: '${school['crcName'] ?? ''}');
    final medium = TextEditingController(
      text: '${school['medium'] ?? 'Gujarati'}',
    );
    final diseCode = TextEditingController(
      text: '${school['schoolDiseCode'] ?? ''}',
    );
    final authority = TextEditingController(
      text: '${school['educationAuthorityName'] ?? ''}',
    );
    final year = TextEditingController(text: '${school['academicYear'] ?? ''}');
    final resultDate = TextEditingController(
      text: '${school['resultDate'] ?? ''}',
    );
    var type = '${school['schoolType'] ?? 'coed'}'.toLowerCase();
    bool reportGenderSplit = school['reportGenderSplitEnabled'] == null
        ? type == 'coed'
        : school['reportGenderSplitEnabled'] == true;
    bool saving = false;
    String? error;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: Text(
            '🏫 School Profile',
            style: guFont(fontWeight: FontWeight.w800),
          ),
          content: SizedBox(
            width: 460,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: name,
                    decoration: const InputDecoration(
                      labelText: 'શાળાનું નામ / School name',
                    ),
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    value: ['boys', 'girls', 'coed'].contains(type)
                        ? type
                        : 'coed',
                    decoration: const InputDecoration(
                      labelText: 'School type (fixed at account creation)',
                    ),
                    items: const [
                      DropdownMenuItem(value: 'boys', child: Text('Boys only')),
                      DropdownMenuItem(
                        value: 'girls',
                        child: Text('Girls only'),
                      ),
                      DropdownMenuItem(
                        value: 'coed',
                        child: Text('Boys + Girls'),
                      ),
                    ],
                    onChanged: null,
                  ),
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Padding(
                      padding: EdgeInsets.only(top: 2, bottom: 6),
                      child: Text(
                        'School type controls attendance-sheet columns. Changing it requires a supervised data migration.',
                        style: TextStyle(fontSize: 11, color: Colors.blueGrey),
                      ),
                    ),
                  ),
                  TextField(
                    controller: village,
                    decoration: const InputDecoration(
                      labelText: 'Village / City',
                    ),
                  ),
                  TextField(
                    controller: taluka,
                    decoration: const InputDecoration(labelText: 'Taluka'),
                  ),
                  TextField(
                    controller: district,
                    decoration: const InputDecoration(labelText: 'District'),
                  ),
                  TextField(
                    controller: centerName,
                    decoration: const InputDecoration(
                      labelText: 'Pay centre / Centre name',
                    ),
                  ),
                  TextField(
                    controller: crcName,
                    decoration: const InputDecoration(labelText: 'CRC name'),
                  ),
                  TextField(
                    controller: medium,
                    decoration: const InputDecoration(
                      labelText: 'Medium / Language',
                    ),
                  ),
                  TextField(
                    controller: diseCode,
                    decoration: const InputDecoration(
                      labelText: 'School DISE / UDISE code',
                    ),
                  ),
                  TextField(
                    controller: authority,
                    decoration: const InputDecoration(
                      labelText: 'Result authority / header title',
                    ),
                  ),
                  TextField(
                    controller: year,
                    decoration: const InputDecoration(
                      labelText: 'Academic year',
                    ),
                  ),
                  TextField(
                    controller: resultDate,
                    decoration: const InputDecoration(
                      labelText: 'Result date (DD/MM/YYYY)',
                    ),
                  ),
                  const SizedBox(height: 10),
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      '📊 Reportsમાં Boys / Girls / Total',
                      style: guFont(fontWeight: FontWeight.w800),
                    ),
                    subtitle: Text(
                      'Co-ed school માટે ON રાખવાથી category-wise reportમાં Boys + Girls = Total દેખાશે. OFF રાખવાથી compact category-total report મળશે.',
                      style: guFont(fontSize: 11.5, color: AppColors.slate),
                    ),
                    value: reportGenderSplit,
                    onChanged: type == 'coed'
                        ? (v) => setD(() => reportGenderSplit = v)
                        : null,
                  ),
                  if (error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        error!,
                        style: const TextStyle(color: Colors.red),
                      ),
                    ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: saving ? null : () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: saving
                  ? null
                  : () async {
                      if (name.text.trim().isEmpty) {
                        setD(() => error = 'School name is required.');
                        return;
                      }
                      setD(() {
                        saving = true;
                        error = null;
                      });
                      try {
                        final res = await state.api!.updateSchoolConfig({
                          'schoolName': name.text.trim(),
                          'schoolType': type,
                          'village': village.text.trim(),
                          'taluka': taluka.text.trim(),
                          'district': district.text.trim(),
                          'centerName': centerName.text.trim(),
                          'crcName': crcName.text.trim(),
                          'medium': medium.text.trim(),
                          'schoolDiseCode': diseCode.text.trim(),
                          'educationAuthorityName': authority.text.trim(),
                          'academicYear': year.text.trim(),
                          'resultDate': resultDate.text.trim(),
                          'reportGenderSplitEnabled': reportGenderSplit
                              .toString(),
                        });
                        if (res['result'] != 'success')
                          throw Exception(res['message'] ?? 'Save failed');
                        await state.refreshSchoolConfig();
                        if (ctx.mounted) Navigator.pop(ctx);
                        if (mounted)
                          showSnack(context, '✅ School profile saved.');
                      } catch (e) {
                        setD(() {
                          saving = false;
                          error = '$e';
                        });
                      }
                    },
              child: Text(saving ? 'Saving…' : 'Save'),
            ),
          ],
        ),
      ),
    );
    name.dispose();
    village.dispose();
    taluka.dispose();
    district.dispose();
    centerName.dispose();
    crcName.dispose();
    medium.dispose();
    diseCode.dispose();
    authority.dispose();
    year.dispose();
    resultDate.dispose();
  }

  Future<void> _createClassDialog() async {
    final state = context.read<AppState>();
    if (!state.isAdmin || state.api == null) return;
    String standard = 'BALVATIKA';
    String section = 'A';
    bool saving = false;
    String? error;
    final standards = <String>[
      'BALVATIKA',
      '1',
      '2',
      '3',
      '4',
      '5',
      '6',
      '7',
      '8',
    ];
    final sections = List<String>.generate(
      26,
      (i) => String.fromCharCode(65 + i),
    );
    String label() =>
        standard == 'BALVATIKA' ? 'BALVATIKA $section' : '$standard$section';
    String group() {
      if (standard == 'BALVATIKA') return 'BALVATIKA';
      final n = int.tryParse(standard) ?? 0;
      if (n >= 1 && n <= 5) return '1TO5';
      if (n >= 6 && n <= 8) return '6TO8';
      return 'OTHER';
    }

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: Text(
            '➕ Create Class',
            style: guFont(fontWeight: FontWeight.w800),
          ),
          content: SizedBox(
            width: 430,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'ધોરણ / Report Group',
                  style: guFont(
                    fontWeight: FontWeight.w800,
                    color: AppColors.navy,
                  ),
                ),
                const SizedBox(height: 6),
                DropdownButtonFormField<String>(
                  value: standard,
                  isExpanded: true,
                  items: standards
                      .map(
                        (v) => DropdownMenuItem(
                          value: v,
                          child: Text(
                            v == 'BALVATIKA' ? 'BALVATIKA' : 'CLASS $v',
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: saving
                      ? null
                      : (v) => setD(() => standard = v ?? 'BALVATIKA'),
                ),
                const SizedBox(height: 12),
                Text(
                  'વિભાગ / Section',
                  style: guFont(
                    fontWeight: FontWeight.w800,
                    color: AppColors.navy,
                  ),
                ),
                const SizedBox(height: 6),
                DropdownButtonFormField<String>(
                  value: section,
                  isExpanded: true,
                  items: sections
                      .map(
                        (v) => DropdownMenuItem(
                          value: v,
                          child: Text('Section $v'),
                        ),
                      )
                      .toList(),
                  onChanged: saving
                      ? null
                      : (v) => setD(() => section = v ?? 'A'),
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.greenBg,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppColors.greenBorder),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Class: ${label()}',
                        style: guFont(
                          fontWeight: FontWeight.w900,
                          color: AppColors.greenDeep,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Report group: ${group() == 'BALVATIKA'
                            ? 'BALVATIKA'
                            : group() == '1TO5'
                            ? 'CLASS 1 TO 5'
                            : 'CLASS 6 TO 8'}',
                        style: guFont(fontSize: 12, color: AppColors.slate),
                      ),
                    ],
                  ),
                ),
                if (error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      error!,
                      style: const TextStyle(color: Colors.red),
                    ),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: saving ? null : () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: saving
                  ? null
                  : () async {
                      setD(() => saving = true);
                      try {
                        final res = await state.api!.createClass(
                          label: label(),
                          standard: standard,
                          section: section,
                          reportGroup: group(),
                        );
                        if (res['result'] != 'success')
                          throw Exception(
                            res['message'] ?? 'Class creation failed',
                          );
                        await state.refreshSchoolConfig();
                        if (ctx.mounted) Navigator.pop(ctx);
                        if (mounted)
                          showSnack(
                            context,
                            '✅ ${label()} and required sheets created.',
                          );
                      } catch (e) {
                        setD(() {
                          saving = false;
                          error = '$e';
                        });
                      }
                    },
              child: Text(saving ? 'Creating…' : 'Create'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _createTeacherDialog() async {
    final state = context.read<AppState>();
    if (!state.isAdmin || state.api == null) return;
    final name = TextEditingController();
    final pin = TextEditingController();
    final email = TextEditingController();
    final classes = state.allSchoolClasses.map((c) => c.key).toList();
    final selected = <String>{};
    String role = 'teacher';
    bool saving = false;
    String? error;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: const Text('👩‍🏫 Create Teacher Account'),
          content: SizedBox(
            width: 470,
            height: 480,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    controller: name,
                    decoration: const InputDecoration(
                      labelText: 'Teacher name',
                    ),
                  ),
                  TextField(
                    controller: pin,
                    obscureText: true,
                    maxLength: 8,
                    decoration: const InputDecoration(
                      labelText: 'PIN (minimum 4 characters)',
                    ),
                  ),
                  TextField(
                    controller: email,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(
                      labelText: 'Email (optional)',
                    ),
                  ),
                  DropdownButtonFormField<String>(
                    value: role,
                    decoration: const InputDecoration(labelText: 'Role'),
                    items: const [
                      DropdownMenuItem(
                        value: 'teacher',
                        child: Text('Teacher'),
                      ),
                      DropdownMenuItem(
                        value: 'pm_poshan',
                        child: Text('PM Poshan'),
                      ),
                      DropdownMenuItem(value: 'office', child: Text('Office')),
                      DropdownMenuItem(
                        value: 'admin',
                        child: Text('School Admin'),
                      ),
                    ],
                    onChanged: (v) => setD(() => role = v ?? 'teacher'),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Assigned classes (admins can access all)',
                    style: guFont(fontWeight: FontWeight.w800),
                  ),
                  if (classes.isEmpty) const Text('Create a class first.'),
                  for (final c in classes)
                    CheckboxListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: Text(c),
                      value: selected.contains(c),
                      onChanged: role == 'admin'
                          ? null
                          : (v) => setD(() {
                              if (v == true) {
                                selected.add(c);
                              } else {
                                selected.remove(c);
                              }
                            }),
                    ),
                  if (error != null)
                    Text(error!, style: const TextStyle(color: Colors.red)),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: saving ? null : () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: saving
                  ? null
                  : () async {
                      if (name.text.trim().isEmpty ||
                          pin.text.trim().length < 4) {
                        setD(
                          () => error = 'Name and a PIN of at least 4 characters are required.',
                        );
                        return;
                      }
                      if (role != 'admin' && selected.isEmpty) {
                        setD(() => error = 'Select at least one class.');
                        return;
                      }
                      setD(() => saving = true);
                      try {
                        final res = await state.api!.createTeacher(
                          name: name.text.trim(),
                          pin: pin.text.trim(),
                          classes: selected.toList(),
                          role: role,
                          email: email.text.trim(),
                        );
                        if (res['result'] != 'success')
                          throw Exception(
                            res['message'] ?? 'Teacher creation failed',
                          );
                        if (ctx.mounted) Navigator.pop(ctx);
                        if (mounted)
                          showSnack(context, '✅ Teacher account created.');
                      } catch (e) {
                        setD(() {
                          saving = false;
                          error = '$e';
                        });
                      }
                    },
              child: Text(saving ? 'Creating…' : 'Create'),
            ),
          ],
        ),
      ),
    );
    name.dispose();
    pin.dispose();
    email.dispose();
  }

  Future<void> _uploadSchoolLogo() async {
    final state = context.read<AppState>();
    if (!state.isAdmin || state.api == null) return;
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        withData: true,
        allowMultiple: false,
      );
      if (result == null || result.files.isEmpty) return;
      final file = result.files.single;
      final bytes = file.bytes;
      if (bytes == null || bytes.length > 2 * 1024 * 1024) {
        if (mounted)
          showSnack(
            context,
            'Logo must be available as bytes and no larger than 2 MB.',
            error: true,
          );
        return;
      }
      final ext = (file.extension ?? 'png').toLowerCase();
      final mime = ext == 'jpg' || ext == 'jpeg'
          ? 'image/jpeg'
          : ext == 'webp'
          ? 'image/webp'
          : 'image/png';
      showBusyDialog(context, 'Uploading school logo…');
      final res = await state.api!.uploadSchoolLogo(
        base64: base64Encode(bytes),
        mimeType: mime,
        fileName: file.name,
      );
      hideBusyDialog(context);
      if (res['result'] != 'success')
        throw Exception(res['message'] ?? 'Logo upload failed');
      await state.refreshSchoolConfig();
      if (mounted) showSnack(context, '✅ School logo updated.');
    } catch (e) {
      hideBusyDialog(context);
      if (mounted) showSnack(context, '❌ $e', error: true);
    }
  }

  Future<void> _exportGenderPdf() async {
    final state = context.read<AppState>();
    if (state.api == null) return;
    final now = DateTime.now();
    final month = TextEditingController(
      text: '${now.year}-${now.month.toString().padLeft(2, '0')}',
    );
    String group = 'ALL';
    bool exporting = false;
    String? error;
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: const Text('👧👦 Gender-wise Attendance PDF'),
          content: SizedBox(
            width: 360,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: month,
                  decoration: const InputDecoration(
                    labelText: 'Month (YYYY-MM)',
                  ),
                ),
                DropdownButtonFormField<String>(
                  value: group,
                  items: const [
                    DropdownMenuItem(value: 'ALL', child: Text('All classes')),
                    DropdownMenuItem(
                      value: 'Balvatika',
                      child: Text('Balvatika'),
                    ),
                    DropdownMenuItem(value: '1to5', child: Text('Std 1 to 5')),
                    DropdownMenuItem(value: '6to8', child: Text('Std 6 to 8')),
                  ],
                  onChanged: (v) => setD(() => group = v ?? 'ALL'),
                ),
                if (error != null)
                  Text(error!, style: const TextStyle(color: Colors.red)),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: exporting ? null : () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: exporting
                  ? null
                  : () async {
                      setD(() {
                        exporting = true;
                        error = null;
                      });
                      try {
                        final res = await state.api!.getGenderSummaryPdf(
                          month: month.text.trim(),
                          group: group,
                        );
                        if (res['result'] != 'success' ||
                            res['pdfBase64'] == null)
                          throw Exception(
                            res['message'] ?? 'PDF generation failed',
                          );
                        final bytes = base64Decode(res['pdfBase64'].toString());
                        await Share.shareXFiles([
                          XFile.fromData(
                            bytes,
                            name:
                                '${res['fileName'] ?? 'Gender-Wise-Attendance.pdf'}',
                            mimeType: 'application/pdf',
                          ),
                        ], text: 'Gender-wise attendance report');
                        if (ctx.mounted) Navigator.pop(ctx);
                      } catch (e) {
                        setD(() {
                          exporting = false;
                          error = '$e';
                        });
                      }
                    },
              child: Text(exporting ? 'Generating…' : 'Generate / Share PDF'),
            ),
          ],
        ),
      ),
    );
    month.dispose();
  }

  Future<void> _openExportDialog() async {
    final api = context.read<AppState>().api!;

    // ડાયલોગ ખુલતા પહેલા Custom Headers મંગાવી લઈએ
    showBusyDialog(context, 'માહિતી લોડ થાય છે...');
    List<String> customHeaders = [];
    try {
      customHeaders = await api.getCustomHeaders();
    } catch (_) {}
    if (!mounted) return;
    hideBusyDialog(context);

    String classFilter = 'ALL';
    String catFilter = 'ALL';
    String schFilter = 'ALL';

    final List<Map<String, dynamic>> availableGroups = [
      {
        'label': 'ધોરણ (Class)',
        'keys': ['className'],
      },
      {
        'label': 'Roll No',
        'keys': ['rollNumber'],
      },
      {
        'label': 'વિદ્યાર્થીનું નામ',
        'keys': ['name'],
      },
      {
        'label': 'GR નંબર',
        'keys': ['gr'],
      },
      {
        'label': 'જન્મ તારીખ (3)',
        'keys': ['dd', 'mm', 'yyyy'],
      },
      {
        'label': 'પેટા જ્ઞાતિ',
        'keys': ['caste'],
      },
      {
        'label': 'કેટેગરી',
        'keys': ['category'],
      },
      {
        'label': 'જાતિ (કુમાર / કન્યા)',
        'keys': ['gender'],
      },
      {
        'label': 'મોબાઈલ નંબર',
        'keys': ['mobile'],
      },
      {
        'label': 'પિતાનું નામ',
        'keys': ['fatherName'],
      },
      {
        'label': 'માતાનું નામ',
        'keys': ['motherName'],
      },
      {
        'label': 'પ્રવેશ તારીખો (2)',
        'keys': ['enrollSchool', 'enrollClass'],
      },
      {
        'label': 'પ્રવેશ ધોરણ વિગતો (2)',
        'keys': ['enrollSchClass', 'enrollSchClassWords'],
      },
      {
        'label': 'હાજર દિવસો',
        'keys': ['presentDays'],
      },
      {
        'label': 'જન્મ સ્થળ / શબ્દોમાં',
        'keys': ['birthPlace', 'dobWords'],
      },
      {
        'label': 'પૂર્વ શાળા',
        'keys': ['lastSchool'],
      },
      {
        'label': 'English વિગતો (9)',
        'keys': [
          'nameEn',
          'casteEn',
          'catEn',
          'motherEn',
          'birthPlaceEn',
          'dobEn',
          'lastSchoolEn',
          'enrollSchClassEn',
          'enrollSchClassWordsEn',
        ],
      },
      {
        'label': 'APAAR ID',
        'keys': ['apaarId'],
      },
      {
        'label': 'વતન / Native Place (2)',
        'keys': ['nativePlace', 'nativePlaceEn'],
      },
      {
        'label': 'શિષ્યવૃત્તિ (2)',
        'keys': ['scholarshipDone', 'scholarshipReason'],
      },
      {
        'label': 'UID / PEN (2)',
        'keys': ['uid', 'pen'],
      },
      {
        'label': 'બેંક વિગતો (5)',
        'keys': [
          'bankName',
          'bankBranch',
          'nameAsPassbook',
          'accountNumber',
          'ifscCode',
        ],
      },
    ];

    // જો એડમિને Custom Headers બનાવ્યા હોય તો તેને પણ લિસ્ટમાં ઉમેરો
    for (int i = 0; i < customHeaders.length; i++) {
      if (customHeaders[i].trim().isNotEmpty) {
        availableGroups.add({
          'label': customHeaders[i],
          'keys': ['c${i + 1}'],
        });
      }
    }

    List<Map<String, dynamic>> selectedGroups = [];
    selectedGroups.addAll(availableGroups.take(3)); // ડિફોલ્ટ 3 ખાના

    bool isExporting = false;
    String? exportError;

    // બધા ક્લાસનું લિસ્ટ
    List<String> allClassesList = [
      'ALL',
      ...context.read<AppState>().allSchoolClasses.map((c) => c.key),
    ];

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) {
          return AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            title: Row(
              children: [
                const Text(
                  '📊 સ્માર્ટ Excel એક્સપોર્ટ',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
                const Spacer(),
                if (!isExporting)
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(ctx),
                  ),
              ],
            ),
            content: SizedBox(
              width: double.maxFinite,
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'ફિલ્ટર્સ પસંદ કરો:',
                      style: guFont(
                        fontWeight: FontWeight.bold,
                        color: AppColors.navy,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        SizedBox(
                          width: 140,
                          child: LabeledField(
                            label: 'ધોરણ (Class)',
                            child: DropdownButtonFormField<String>(
                              value: classFilter,
                              isExpanded: true,
                              items: allClassesList
                                  .map(
                                    (c) => DropdownMenuItem(
                                      value: c,
                                      child: Text(
                                        c == 'ALL'
                                            ? 'બધા ધોરણ (All)'
                                            : c.replaceAll('Class ', ''),
                                      ),
                                    ),
                                  )
                                  .toList(),
                              onChanged: (v) => setD(() => classFilter = v!),
                            ),
                          ),
                        ),
                        SizedBox(
                          width: 140,
                          child: LabeledField(
                            label: 'કેટેગરી',
                            child: DropdownButtonFormField<String>(
                              value: catFilter,
                              isExpanded: true,
                              items: const [
                                DropdownMenuItem(
                                  value: 'ALL',
                                  child: Text('બધા (All)'),
                                ),
                                DropdownMenuItem(
                                  value: 'SC',
                                  child: Text('SC (અ. જા.)'),
                                ),
                                DropdownMenuItem(
                                  value: 'ST',
                                  child: Text('ST (અ. જ. જા.)'),
                                ),
                                DropdownMenuItem(
                                  value: 'OBC',
                                  child: Text('OBC (બક્ષીપંચ)'),
                                ),
                                DropdownMenuItem(
                                  value: 'OTHER',
                                  child: Text('OTHER (અન્ય)'),
                                ),
                              ],
                              onChanged: (v) => setD(() => catFilter = v!),
                            ),
                          ),
                        ),
                        SizedBox(
                          width: 160,
                          child: LabeledField(
                            label: 'શિષ્યવૃત્તિ',
                            child: DropdownButtonFormField<String>(
                              value: schFilter,
                              isExpanded: true,
                              items: const [
                                DropdownMenuItem(
                                  value: 'ALL',
                                  child: Text('બધા (All)'),
                                ),
                                DropdownMenuItem(
                                  value: 'YES',
                                  child: Text('હા (દરખાસ્ત કરેલ)'),
                                ),
                                DropdownMenuItem(
                                  value: 'NO',
                                  child: Text('ના (કારણ સાથે)'),
                                ),
                              ],
                              onChanged: (v) => setD(() => schFilter = v!),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      child: Divider(),
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            'તમે જે ક્રમમાં બટન દબાવશો, Excel માં એ જ ક્રમમાં કોલમ બનશે.',
                            style: guFont(
                              fontWeight: FontWeight.bold,
                              color: AppColors.navy,
                            ),
                          ),
                        ),
                        TextButton(
                          onPressed: () => setD(() {
                            if (selectedGroups.length == availableGroups.length)
                              selectedGroups.clear();
                            else
                              selectedGroups = List.from(availableGroups);
                          }),
                          child: Text(
                            selectedGroups.length == availableGroups.length
                                ? 'Clear All'
                                : 'Select All',
                          ),
                        ),
                      ],
                    ),
                    Text(
                      'નોંધ: "ક્રમ" (Serial Number) આપોઆપ પહેલી કોલમ બની જશે.',
                      style: guFont(fontSize: 11, color: AppColors.rose),
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: availableGroups.map((grp) {
                        final index = selectedGroups.indexOf(grp);
                        final isSel = index >= 0;
                        return FilterChip(
                          label: Text(
                            isSel
                                ? '${index + 1}. ${grp['label']}'
                                : grp['label'],
                            style: guFont(
                              fontSize: 12,
                              fontWeight: isSel
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                            ),
                          ),
                          selected: isSel,
                          selectedColor: AppColors.goldPale,
                          onSelected: (val) => setD(() {
                            if (val)
                              selectedGroups.add(grp);
                            else
                              selectedGroups.remove(grp);
                          }),
                        );
                      }).toList(),
                    ),
                    if (exportError != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        exportError!,
                        style: guFont(
                          color: AppColors.rose,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            actions: [
              AppButton(
                label: isExporting
                    ? 'ડેટા તૈયાર થાય છે...'
                    : '📥 EXCEL ડાઉનલોડ કરો',
                background: AppColors.greenDeep,
                loading: isExporting,
                onPressed: (isExporting || selectedGroups.isEmpty)
                    ? null
                    : () async {
                        setD(() {
                          isExporting = true;
                          exportError = null;
                        });
                        try {
                          List<String> finalCols = [];
                          for (var grp in selectedGroups) {
                            finalCols.addAll(grp['keys'] as List<String>);
                          }
                          final res = await api.exportStudentDataExcel(
                            classFilter: classFilter,
                            catFilter: catFilter,
                            schFilter: schFilter,
                            columns: finalCols,
                          );
                          if (res['result'] == 'success' &&
                              res['base64'] != null) {
                            final bytes = base64Decode(
                              res['base64'].toString(),
                            );
                            await Share.shareXFiles([
                              XFile.fromData(
                                bytes,
                                name: 'Student_Data.xlsx',
                                mimeType: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
                              ),
                            ], text: 'અહીં તમારો Excel ડેટા છે.');
                            if (ctx.mounted) Navigator.pop(ctx);
                          } else {
                            setD(() {
                              isExporting = false;
                              exportError =
                                  '❌ ${res['message'] ?? 'ભૂલ આવી.'}';
                            });
                          }
                        } catch (e) {
                          setD(() {
                            isExporting = false;
                            exportError = '❌ સર્વર એરર: $e';
                          });
                        }
                      },
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _openChangePasswordDialog() async {
    if (!context.read<AppState>().isAdmin || !mounted) return;
    final api = context.read<AppState>().api;
    if (api == null) return;
    List<Teacher>? teachers;
    try {
      teachers = await api.getTeachers();
    } catch (e) {
      if (mounted) showSnack(context, '❌ $e', error: true);
      return;
    }
    if (!mounted) return;
    String? selectedName = teachers.isNotEmpty ? teachers.first.name : null;
    final pinCtrl = TextEditingController();
    bool saving = false;
    String? error;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) {
          return AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            title: Text(
              '🔑 પાસવર્ડ બદલો',
              style: guFont(fontWeight: FontWeight.w800),
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                LabeledField(
                  label: 'ધોરણ',
                  child: DropdownButtonFormField<String>(
                    value: selectedName,
                    isExpanded: true,
                    items: teachers!
                        .map(
                          (t) => DropdownMenuItem(
                            value: t.name,
                            child: Text(t.name),
                          ),
                        )
                        .toList(),
                    onChanged: (v) => setD(() => selectedName = v),
                  ),
                ),
                const SizedBox(height: 12),
                LabeledField(
                  label: 'નવો PIN',
                  child: TextField(
                    controller: pinCtrl,
                    maxLength: 15,
                    decoration: const InputDecoration(
                      labelText: 'નવો પાસવર્ડ (4 થી 15 અક્ષર)',
                      counterText: '',
                    ),
                  ),
                ),
                if (error != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    error!,
                    style: guFont(
                      fontSize: 12,
                      color: AppColors.rose,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('રદ કરો'),
              ),
              AppButton(
                label: saving ? '...' : 'સેવ કરો',
                loading: saving,
                onPressed: saving
                    ? null
                    : () async {
                        if (selectedName == null ||
                            pinCtrl.text.trim().length < 4 ||
                            pinCtrl.text.trim().length > 15) {
                          setD(
                            () => error = 'શિક્ષક પસંદ કરો અને પાસવર્ડ 4 થી 15 અક્ષરનો દાખલ કરો.',
                          );
                          return;
                        }
                        setD(() => saving = true);
                        try {
                          final res = await api!.changePassword(
                            selectedName!,
                            pinCtrl.text.trim(),
                          );
                          if (res['result'] == 'success') {
                            if (ctx.mounted) Navigator.of(ctx).pop();
                            if (mounted)
                              showSnack(context, '✅ પાસવર્ડ બદલાયો.');
                          } else {
                            setD(() {
                              saving = false;
                              error = res['message']?.toString() ?? 'ભૂલ થઈ.';
                            });
                          }
                        } catch (e) {
                          setD(() {
                            saving = false;
                            error = '$e';
                          });
                        }
                      },
              ),
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final holidayEntries = state.holidays.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));

    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: AppColors.goldPale,
        border: Border.all(color: AppColors.gold),
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '🏖️ રજા મેનેજર (ફક્ત આચાર્ય માટે)',
            style: guFont(
              fontWeight: FontWeight.w800,
              color: AppColors.amberDeep,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              SizedBox(
                width: 160,
                child: _dateField(
                  _holidayDateCtrl,
                  (d) => setState(() => _holidayDate = d),
                ),
              ),
              SizedBox(
                width: 220,
                child: TextField(
                  controller: _holidayReasonCtrl,
                  decoration: const InputDecoration(
                    hintText: 'રજાનું નામ (દા.ત. દિવાળી)',
                  ),
                ),
              ),
              AppButton(
                label: 'રજા ઉમેરો',
                background: AppColors.gold,
                loading: _savingHoliday,
                onPressed: _holidayDate == null || _savingHoliday
                    ? null
                    : _addHoliday,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final h in holidayEntries)
                Chip(
                  label: Text(
                    '${h.key} · ${h.value}',
                    style: guFont(fontSize: 12, fontWeight: FontWeight.w700),
                  ),
                  onDeleted: () => _deleteHoliday(h.key),
                  backgroundColor: Colors.white,
                  side: const BorderSide(color: AppColors.amberBorder),
                ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 15),
            child: Divider(color: AppColors.amberBorder, height: 1),
          ),
          Text(
            '⚙️ ઍપ અને પાસવર્ડ સેટિંગ્સ',
            style: guFont(
              fontWeight: FontWeight.w800,
              color: AppColors.amberDeep,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              AppButton(
                label: '📬 રજા મંજૂર કરો (Pending Leaves)',
                background: Colors.orange,
                onPressed: () async {
                  showBusyDialog(context, 'Loading...');
                  try {
                    final res = await context
                        .read<AppState>()
                        .api!
                        .getPendingLeaves();
                    Navigator.pop(context);
                    if (res['result'] == 'success') {
                      final leaves = res['leaves'] as List;
                      showDialog(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          title: Text(
                            '📬 મંજૂરી માટે આવેલી રજાઓ',
                            style: guFont(fontWeight: FontWeight.bold),
                          ),
                          content: SizedBox(
                            width: 600,
                            height: 400,
                            child: leaves.isEmpty
                                ? Center(
                                    child: Text(
                                      'કોઈ નવી રજા પેન્ડિંગ નથી.',
                                      style: guFont(),
                                    ),
                                  )
                                : ListView.builder(
                                    itemCount: leaves.length,
                                    itemBuilder: (_, i) {
                                      final l = leaves[i];
                                      return Card(
                                        color: AppColors.slateLight,
                                        child: ListTile(
                                          title: Text(
                                            '${l['teacher']} (${l['days']} દિવસ)',
                                            style: guFont(
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                          subtitle: Text(
                                            'પ્રકાર: ${l['leaveType']}\nકારણ: ${l['reason']}\nતારીખ: ${l['fromDate']} થી ${l['toDate']}',
                                            style: guFont(fontSize: 12),
                                          ),
                                          trailing: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              IconButton(
                                                icon: const Icon(
                                                  Icons.check_circle,
                                                  color: Colors.green,
                                                ),
                                                onPressed: () async {
                                                  await context
                                                      .read<AppState>()
                                                      .api!
                                                      .approveLeave(
                                                        l['id'],
                                                        'Approved',
                                                      );
                                                  Navigator.pop(ctx);
                                                  ScaffoldMessenger.of(context)
                                                      .showSnackBar(
                                                        const SnackBar(
                                                          content: Text(
                                                            '✅ રજા મંજૂર કરવામાં આવી!',
                                                          ),
                                                        ),
                                                      );
                                                },
                                              ),
                                              IconButton(
                                                icon: const Icon(
                                                  Icons.cancel,
                                                  color: Colors.red,
                                                ),
                                                onPressed: () async {
                                                  await context
                                                      .read<AppState>()
                                                      .api!
                                                      .approveLeave(
                                                        l['id'],
                                                        'Rejected',
                                                      );
                                                  Navigator.pop(ctx);
                                                  ScaffoldMessenger.of(context)
                                                      .showSnackBar(
                                                        const SnackBar(
                                                          content: Text(
                                                            '❌ રજા નામંજૂર કરવામાં આવી.',
                                                          ),
                                                        ),
                                                      );
                                                },
                                              ),
                                            ],
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                          ),
                        ),
                      );
                    }
                  } catch (e) {
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context)
                        .showSnackBar(SnackBar(content: Text('❌ $e')));
                  }
                },
              ),
              AppButton(
                label: '🔗 લિંક (URL) બદલો',
                background: const Color(0xFF1E4A7A),
                onPressed: _changeUrl,
              ),
              AppButton(
                label: '🔑 પાસવર્ડ બદલો',
                background: AppColors.rose,
                onPressed: _openChangePasswordDialog,
              ),
              AppButton(
                label: '📥 ડેટા એક્સપોર્ટ (Excel)',
                background: AppColors.greenDeep,
                onPressed: _openExportDialog,
              ),
              AppButton(
                label: '🛠️️ Custom Headers બનાવો',
                background: AppColors.teal,
                onPressed: _openHeaderManager,
              ),
              AppButton(
                label: '🔒 પરિણામ Lock / Unlock',
                background: AppColors.slate,
                onPressed: _openResultLockManager,
              ),
              AppButton(
                label: '🏫 School Profile',
                background: const Color(0xFF356B8C),
                onPressed: _manageSchoolProfile,
              ),
              AppButton(
                label: '📊 DATE WISE Columns',
                background: const Color(0xFF4F46A5),
                onPressed: _manageDateWiseColumns,
              ),
              AppButton(
                label: '📂 Messages / Holidays / Leave Excel',
                background: AppColors.teal,
                onPressed: _openAdminDataTransferDialog,
              ),
              AppButton(
                label: '➕ Create Class',
                background: AppColors.greenDeep,
                onPressed: _createClassDialog,
              ),
              AppButton(
                label: '👩‍🏫 Create Teacher',
                background: AppColors.navyMid,
                onPressed: _createTeacherDialog,
              ),
              AppButton(
                label: '🖼️ Upload Logo',
                background: AppColors.teal,
                onPressed: _uploadSchoolLogo,
              ),
              AppButton(
                label: '👧👦 Gender-wise PDF',
                background: const Color(0xFF7047A3),
                onPressed: _exportGenderPdf,
              ),
            ],
          ),
          const SizedBox(height: 15),
          Container(
            padding: const EdgeInsets.all(15),
            decoration: BoxDecoration(
              color: AppColors.greenBg,
              border: Border.all(color: AppColors.greenBorder),
              borderRadius: BorderRadius.circular(AppRadius.sm),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  '📢 શિક્ષકો માટે સંદેશ મોકલો',
                  style: guFont(
                    fontWeight: FontWeight.w800,
                    color: AppColors.greenDeep,
                  ),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  crossAxisAlignment: WrapCrossAlignment.end,
                  children: [
                    SizedBox(
                      width: 160,
                      child: _dateField(
                        _msgDateCtrl,
                        (d) => setState(() => _msgDate = d),
                        label: '📅 તારીખ પસંદ કરો',
                      ),
                    ),
                    SizedBox(
                      width: 240,
                      child: LabeledField(
                        label: '✏️ સંદેશ',
                        child: TextField(
                          controller: _msgTextCtrl,
                          maxLines: 3,
                          minLines: 2,
                          decoration: const InputDecoration(
                            hintText: 'શિક્ષકો માટે સંદેશ અહીં લખો...',
                          ),
                        ),
                      ),
                    ),
                    AppButton(
                      label: '📤 સંદેશ મોકલો',
                      background: AppColors.greenDeep2,
                      loading: _sendingMsg,
                      onPressed: _sendingMsg ? null : _sendMessage,
                    ),
                  ],
                ),
                if (_msgExistingPreview() != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFF8E7),
                        border: Border.all(color: AppColors.amberBorder),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '✏️ આ તારીખ પર પહેલાંથી સંદેશ છે:\n${_msgExistingPreview()}',
                        style: guFont(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: AppColors.amberDeep,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ),
                const SizedBox(height: 12),
                Text(
                  '📋 મોકલેલ સંદેશ',
                  style: guFont(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: const Color(0xFF065F46),
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 8),
                if (_messagesError != null)
                  Text(
                    _messagesError!,
                    style: guFont(fontSize: 12, color: AppColors.rose),
                  )
                else if (_messages == null)
                  Text(
                    '⏳ લોડ...',
                    style: guFont(fontSize: 12, color: AppColors.slate),
                  )
                else if (_messages!.isEmpty)
                  Text(
                    'કોઈ સંદેશ નથી.',
                    style: guFont(fontSize: 12, color: AppColors.slate),
                  )
                else
                  Column(
                    children: [
                      for (final m in _messages!)
                        Container(
                          margin: const EdgeInsets.only(bottom: 6),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            children: [
                              Text(
                                m.date,
                                style: guFont(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w800,
                                  color: AppColors.slate,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  m.message,
                                  style: guFont(
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              IconButton(
                                icon: const Icon(
                                  Icons.delete_outline,
                                  size: 18,
                                  color: AppColors.rose,
                                ),
                                onPressed: () => _deleteMessage(m.date),
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                const SizedBox(height: 6),
                Text(
                  '💡 Google Sheet (AdminMessage) દ્વારા પણ સંદેશ ઉમેરી શકાય છે: Column A = ક્રમ | B = YYYY-MM-DD | C = સંદેશ',
                  style: guFont(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: const Color(0xFF6B7280),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          const AdminDailyAttendanceDashboard(
            initiallyExpanded: true,
          ),
        ],
      ),
    );
  }

  Widget _dateField(
    TextEditingController ctrl,
    ValueChanged<DateTime> onPicked, {
    String? label,
  }) {
    final field = InkWell(
      onTap: () async {
        final picked = await showDatePicker(
          context: context,
          initialDate: DateTime.now(),
          firstDate: DateTime(2020),
          lastDate: DateTime(2035),
        );
        if (picked != null) {
          ctrl.text = DateFormat('yyyy-MM-dd').format(picked);
          onPicked(picked);
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: AppColors.amberBorder, width: 1.5),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          ctrl.text.isEmpty ? 'તારીખ પસંદ કરો' : ctrl.text,
          style: guFont(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: ctrl.text.isEmpty ? AppColors.slate : AppColors.navy,
          ),
        ),
      ),
    );
    if (label == null) return field;
    return LabeledField(label: label, child: field);
  }
}
