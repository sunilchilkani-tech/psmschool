import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../services/app_state.dart';
import '../services/certificate_service.dart';
import '../theme/app_theme.dart';
import 'package:pmshri_attendance/services/class_label.dart';

class LeaveReportScreen extends StatefulWidget {
  const LeaveReportScreen({super.key});

  @override
  State<LeaveReportScreen> createState() => _LeaveReportScreenState();
}

class _LeaveReportScreenState extends State<LeaveReportScreen> {
  bool _loading = true;
  List<Map<String, dynamic>> _teachers = [];
  String? _selectedTeacherName;
  String? _selectedChargeTeacherName;

  DateTime _fromDate = DateTime.now();
  DateTime _toDate = DateTime.now();

  bool _isHalfDay = false; // અડધી રજા ટ્રેક કરવા માટે નવો વેરીએબલ

  String _leaveType = 'પ્રાસંગિક રજા (CL)';
  final List<String> _leaveTypes = [
    'પ્રાસંગિક રજા (CL)', 
    'મરજિયાત રજા', 
    'વળતર રજા', 
    'તબીબી રજા (ML)', 
    'અર્ધ પગારી રજા (HPL)', 
    'પ્રસુતિ રજા', 
    'અન્ય'
  ];

  String _reasonType = 'સામાજિક કારણસર';
  final List<String> _reasonTypes = ['સામાજિક કારણસર', 'ધાર્મિક કારણસર', 'તબિયત ખરાબ હોવાના', 'અન્ય (Other)'];
  final _customReasonCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _fetchTeachers();
    });
  }

  Future<void> _fetchTeachers() async {
    final api = context.read<AppState>().api;
    if (api == null) {
      setState(() => _loading = false);
      return;
    }
    try {
      final rawData = await api.getTeachersRaw();
      if (mounted) {
        setState(() {
          _teachers = rawData;
        });
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  bool get _isSingleDay {
    return _fromDate.year == _toDate.year && _fromDate.month == _toDate.month && _fromDate.day == _toDate.day;
  }

  double get _totalDays {
    if (_isSingleDay && _isHalfDay) return 0.5;
    final diff = DateTime(_toDate.year, _toDate.month, _toDate.day)
        .difference(DateTime(_fromDate.year, _fromDate.month, _fromDate.day))
        .inDays;
    return (diff >= 0 ? diff + 1 : 0).toDouble();
  }

  Future<void> _selectDate(BuildContext context, bool isFromDate) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: isFromDate ? _fromDate : _toDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked != null) {
      setState(() {
        if (isFromDate) {
          _fromDate = picked;
          if (_toDate.isBefore(_fromDate)) _toDate = _fromDate;
        } else {
          _toDate = picked;
          if (_fromDate.isAfter(_toDate)) _fromDate = _toDate;
        }
        if (!_isSingleDay) {
          _isHalfDay = false; // જો એક કરતાં વધુ દિવસ હોય તો 'અડધો દિવસ' બંધ
        }
      });
    }
  }

  Map<String, dynamic>? _getTeacherInfo(String? name) {
    try {
      return _teachers.firstWhere((t) => t['name'] == name);
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return Scaffold(appBar: AppBar(title: const Text('રજા રિપોર્ટ')), body: const Center(child: CircularProgressIndicator()));

    final teacherInfo = _getTeacherInfo(_selectedTeacherName);
    final chargeInfo = _getTeacherInfo(_selectedChargeTeacherName);

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: Text('📝 રજા રિપોર્ટ (Leave Report)', style: guFont(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
        backgroundColor: AppColors.navy,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Card(
          elevation: 2,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildDropdown('અરજદાર શિક્ષકનું નામ:', _teachers, _selectedTeacherName, (v) {
                  setState(() {
                    _selectedTeacherName = v;
                    if (_selectedChargeTeacherName == v) _selectedChargeTeacherName = null;
                  });
                }),
                if (teacherInfo != null) ...[
                  const SizedBox(height: 8),
                  Text('વર્ગ: ${teacherInfo['assignedClass'] ?? ''} | પ્રવાહ: ${teacherInfo['stream'] ?? ''}', style: guFont(color: AppColors.teal, fontWeight: FontWeight.bold)),
                ],
                const Divider(height: 30),

                Row(
                  children: [
                    Expanded(child: _buildDateBox('રજા શરૂ તારીખ', _fromDate, () => _selectDate(context, true))),
                    const SizedBox(width: 16),
                    Expanded(child: _buildDateBox('રજા પૂર્ણ તારીખ', _toDate, () => _selectDate(context, false))),
                  ],
                ),
                
                // જો રજા એક જ દિવસની હોય, તો આખો કે અડધો દિવસ પૂછશે
                if (_isSingleDay) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                    decoration: BoxDecoration(color: Colors.blue.shade50, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.blue.shade100)),
                    child: Row(
                      children: [
                        Text('રજાનો સમય:', style: guFont(fontWeight: FontWeight.bold, color: AppColors.navy)),
                        const Spacer(),
                        Radio<bool>(value: false, groupValue: _isHalfDay, activeColor: AppColors.teal, onChanged: (v) => setState(() => _isHalfDay = v!)),
                        Text('આખો દિવસ', style: guFont()),
                        const SizedBox(width: 5),
                        Radio<bool>(value: true, groupValue: _isHalfDay, activeColor: AppColors.teal, onChanged: (v) => setState(() => _isHalfDay = v!)),
                        Text('અડધો દિવસ', style: guFont()),
                      ],
                    ),
                  ),
                ],

                const SizedBox(height: 12),
                Text('કુલ રજાના દિવસો: ${_totalDays % 1 == 0 ? _totalDays.toInt() : _totalDays}', style: guFont(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.rose)),
                const Divider(height: 30),

                _buildSimpleDropdown('રજાનો પ્રકાર:', _leaveTypes, _leaveType, (v) => setState(() => _leaveType = v!)),
                const SizedBox(height: 16),
                
                _buildSimpleDropdown('રજાનું કારણ:', _reasonTypes, _reasonType, (v) => setState(() => _reasonType = v!)),
                if (_reasonType == 'અન્ય (Other)') ...[
                  const SizedBox(height: 10),
                  TextField(
                    controller: _customReasonCtrl,
                    style: guFont(),
                    decoration: const InputDecoration(labelText: 'કારણ લખો', border: OutlineInputBorder()),
                  ),
                ],
                const Divider(height: 30),

                _buildDropdown('ચાર્જ સોંપેલ શિક્ષક:', _teachers.where((t) => t['name'] != _selectedTeacherName).toList(), _selectedChargeTeacherName, (v) => setState(() => _selectedChargeTeacherName = v)),
                if (chargeInfo != null) ...[
                  const SizedBox(height: 8),
                  Text('ચાર્જ લેનારનું ધોરણ: ${ClassLabel.bare(chargeInfo['assignedClass'])}', style: guFont(color: AppColors.teal, fontWeight: FontWeight.bold)),
                ],
                const SizedBox(height: 30),

                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.orange, padding: const EdgeInsets.symmetric(vertical: 14)),
                        icon: const Icon(Icons.send, color: Colors.white),
                        label: Text('Send to Admin', style: guFont(color: Colors.white, fontWeight: FontWeight.bold)),
                        onPressed: () async {
                          if (_selectedTeacherName == null || _selectedChargeTeacherName == null) {
                            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('શિક્ષક પસંદ કરો')));
                            return;
                          }
                          String finalReason = _reasonType == 'અન્ય (Other)' ? _customReasonCtrl.text.trim() : _reasonType;
                          
                          showDialog(context: context, barrierDismissible: false, builder: (_) => const Center(child: CircularProgressIndicator()));
                          try {
                            final res = await context.read<AppState>().api!.submitLeave({
                              'teacher': _selectedTeacherName!,
                              'chargeTeacher': _selectedChargeTeacherName!,
                              'fromDate': DateFormat('dd/MM/yyyy').format(_fromDate),
                              'toDate': DateFormat('dd/MM/yyyy').format(_toDate),
                              'days': (_totalDays % 1 == 0 ? _totalDays.toInt() : _totalDays).toString(),
                              'leaveType': _leaveType,
                              'reason': finalReason.isEmpty ? '-' : finalReason,
                            });
                            if (context.mounted) Navigator.pop(context); // Close loader
                            if (res['result'] == 'success') {
                              if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('✅ રજા મંજૂરી માટે આચાર્યશ્રીને મોકલાઈ ગઈ છે!')));
                            } else {
                              if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('❌ ભૂલ: ${res['message']}')));
                            }
                          } catch (e) {
                            if (context.mounted) Navigator.pop(context);
                            if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('❌ $e')));
                          }
                        },
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(backgroundColor: AppColors.teal, padding: const EdgeInsets.symmetric(vertical: 14)),
                        icon: const Icon(Icons.picture_as_pdf, color: Colors.white),
                        label: Text('Make PDF', style: guFont(color: Colors.white, fontWeight: FontWeight.bold)),
                        onPressed: () async {
                          if (teacherInfo == null || chargeInfo == null) {
                            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('શિક્ષક અને ચાર્જ શિક્ષક પસંદ કરો')));
                            return;
                          }
                          
                          String finalReason = _reasonType == 'અન્ય (Other)' ? _customReasonCtrl.text.trim() : _reasonType;
                          if (finalReason.isEmpty) finalReason = '-';

                          showDialog(context: context, barrierDismissible: false, builder: (_) => const Center(child: CircularProgressIndicator()));
                          
                          try {
                            final utilizedRes = await context.read<AppState>().api!.getUtilizedLeaves(_selectedTeacherName!);
                            if (context.mounted) Navigator.pop(context);

                            await CertificateService.generateLeavePDF(
                              teacher: teacherInfo,
                              chargeTeacher: chargeInfo,
                              leaveType: _leaveType,
                              reason: finalReason,
                              fromDate: DateFormat('dd/MM/yyyy').format(_fromDate),
                              toDate: DateFormat('dd/MM/yyyy').format(_toDate),
                              totalDays: (_totalDays % 1 == 0 ? _totalDays.toInt() : _totalDays).toString(),
                              utilizedLeaves: utilizedRes,
                              schoolName: context.read<AppState>().schoolName,
                            );
                          } catch (e) {
                            if (context.mounted) Navigator.pop(context);
                            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('❌ $e')));
                          }
                        },
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDropdown(String label, List<Map<String, dynamic>> items, String? value, Function(String?) onChanged) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: guFont(fontWeight: FontWeight.bold)),
        const SizedBox(height: 5),
        DropdownButtonFormField<String>(
          decoration: const InputDecoration(border: OutlineInputBorder(), contentPadding: EdgeInsets.symmetric(horizontal: 10)),
          value: value,
          isExpanded: true,
          items: items.map((t) => DropdownMenuItem(value: t['name'] as String, child: Text(t['name'] as String, style: guFont()))).toList(),
          onChanged: onChanged,
        ),
      ],
    );
  }

  Widget _buildSimpleDropdown(String label, List<String> items, String value, Function(String?) onChanged) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: guFont(fontWeight: FontWeight.bold)),
        const SizedBox(height: 5),
        DropdownButtonFormField<String>(
          decoration: const InputDecoration(border: OutlineInputBorder(), contentPadding: EdgeInsets.symmetric(horizontal: 10)),
          value: value,
          isExpanded: true,
          items: items.map((i) => DropdownMenuItem(value: i, child: Text(i, style: guFont()))).toList(),
          onChanged: onChanged,
        ),
      ],
    );
  }

  Widget _buildDateBox(String label, DateTime date, VoidCallback onTap) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: guFont(fontSize: 12, fontWeight: FontWeight.bold)),
        const SizedBox(height: 5),
        InkWell(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade400), borderRadius: BorderRadius.circular(5)),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(DateFormat('dd/MM/yyyy').format(date), style: const TextStyle(fontWeight: FontWeight.bold)),
                const Icon(Icons.calendar_month, color: AppColors.navy, size: 18),
              ],
            ),
          ),
        ),
      ],
    );
  }
}