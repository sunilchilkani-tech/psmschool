import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:excel_community/excel_community.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../services/app_state.dart';
import '../theme/app_theme.dart';

class BulkUploadScreen extends StatefulWidget {
  const BulkUploadScreen({super.key});

  @override
  State<BulkUploadScreen> createState() => _BulkUploadScreenState();
}

class _BulkUploadScreenState extends State<BulkUploadScreen> {
  bool _isLoading = false;

  String _getCellValue(dynamic cell) {
    if (cell == null || cell.value == null) return '';
    final v = cell.value;
    if (v is TextCellValue) return v.value.toString();
    if (v is IntCellValue) return v.value.toString();
    if (v is DoubleCellValue) {
      final d = v.value;
      return d == d.truncateToDouble() ? d.toInt().toString() : d.toString();
    }
    if (v is DateCellValue) {
      return DateFormat('dd/MM/yyyy').format(DateTime(v.year, v.month, v.day));
    }
    if (v is DateTimeCellValue) {
      return DateFormat('dd/MM/yyyy').format(DateTime(v.year, v.month, v.day));
    }
    return v.toString();
  }

  String _normaliseHeader(String value) => value
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'[\s/_\-:()]+'), '');

  String _normaliseClass(String value) => value
      .trim()
      .replaceFirst(RegExp(r'^Class\s+', caseSensitive: false), '')
      .toLowerCase()
      .replaceAll(RegExp(r'[\s._\-]+'), '');

  bool _rowIsBlank(List<String> row) => row.every((value) => value.trim().isEmpty);

  Future<void> _uploadExcel() async {
    final state = context.read<AppState>();
    if (state.api == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Login session / API is missing. Please sign in again.')));
      return;
    }

    FilePickerResult? selectedFile;
    try {
      selectedFile = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['xlsx'],
        withData: true,
      );
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('ફાઈલ પસંદ કરી શકાઈ નથી: $e')));
      return;
    }
    if (selectedFile == null || selectedFile.files.isEmpty) return;
    final bytes = selectedFile.files.single.bytes;
    if (bytes == null || bytes.isEmpty) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Excel ફાઈલ વાંચી શકાઈ નથી.')));
      return;
    }

    setState(() => _isLoading = true);
    try {
      final workbook = Excel.decodeBytes(bytes);
      List<String>? authoritativeHeaders;
      final dataByClass = <String, List<List<dynamic>>>{};
      final allClasses = state.allSchoolClasses;
      final assignedClasses = state.isAdmin ? allClasses : state.allowedClasses;
      final allowedKeys = <String>{};
      for (final schoolClass in assignedClasses) {
        allowedKeys.add(_normaliseClass(schoolClass.key));
        allowedKeys.add(_normaliseClass(schoolClass.label));
        allowedKeys.add(_normaliseClass(schoolClass.sheetName));
      }

      for (final sheetName in workbook.tables.keys) {
        final sheet = workbook.tables[sheetName];
        if (sheet == null || sheet.rows.isEmpty) continue;

        var headerIndex = -1;
        List<String>? sheetHeaders;
        for (var i = 0; i < sheet.rows.length; i++) {
          final candidate = sheet.rows[i].map(_getCellValue).toList();
          final normalized = candidate.map(_normaliseHeader).toList();
          final hasClass = normalized.any((v) => v == 'ધોરણ' || v == 'classname' || v == 'class');
          final hasName = normalized.any((v) => v == 'વિદ્યાર્થીનુંનામ' || v == 'studentname' || v == 'name');
          final hasRoll = normalized.any((v) => v == 'rollnumber' || v == 'rollno');
          if (hasClass && hasName && hasRoll) {
            headerIndex = i;
            sheetHeaders = candidate;
            break;
          }
        }
        if (headerIndex < 0 || sheetHeaders == null) {
          // Ignore unrelated worksheets, but do not silently accept an old
          // positional template as its fields could be shifted.
          continue;
        }
        if (authoritativeHeaders == null) {
          authoritativeHeaders = sheetHeaders;
        } else if (authoritativeHeaders.join('\u0000') != sheetHeaders.join('\u0000')) {
          throw Exception('Excel ની બધી data sheets માં headers એકસરખા હોવા જોઈએ. નવી Blank Template ડાઉનલોડ કરો.');
        }

        final normalizedHeaders = sheetHeaders.map(_normaliseHeader).toList();
        final classIndex = normalizedHeaders.indexWhere((v) => v == 'ધોરણ' || v == 'classname' || v == 'class');
        final rollIndex = normalizedHeaders.indexWhere((v) => v == 'rollnumber' || v == 'rollno');
        final nameIndex = normalizedHeaders.indexWhere((v) => v == 'વિદ્યાર્થીનુંનામ' || v == 'studentname' || v == 'name');
        for (var i = headerIndex + 1; i < sheet.rows.length; i++) {
          final rowData = sheet.rows[i].map(_getCellValue).toList();
          if (_rowIsBlank(rowData)) continue;
          while (rowData.length < sheetHeaders.length) {
            rowData.add('');
          }
          final roll = rollIndex >= 0 && rollIndex < rowData.length ? rowData[rollIndex].trim() : '';
          final studentName = nameIndex >= 0 && nameIndex < rowData.length ? rowData[nameIndex].trim() : '';
          if (roll.isEmpty && studentName.isEmpty) continue;
          final className = classIndex >= 0 && classIndex < rowData.length ? rowData[classIndex].trim() : '';
          if (className.isEmpty) {
            throw Exception('Student "$studentName" માટે ધોરણ પસંદ કરો. Excel માં row ${i + 1}.');
          }
          final normClass = _normaliseClass(className);
          if (!allowedKeys.contains(normClass)) {
            throw Exception('ધોરણ "$className" તમારા account માટે મંજૂર નથી અથવા Admin દ્વારા બનાવેલ active class નથી. નવી Template ના dropdown માંથી ધોરણ પસંદ કરો.');
          }
          (dataByClass[className] ??= <List<dynamic>>[]).add(rowData);
        }
      }

      if (authoritativeHeaders == null || dataByClass.isEmpty) {
        throw Exception('માન્ય data headers અથવા વિદ્યાર્થીની rows મળી નથી. નવી Blank Template ડાઉનલોડ કરો.');
      }

      final response = await state.api!.uploadWholeSchoolData(
        dataByClass,
        headers: authoritativeHeaders,
      );
      if (!mounted) return;
      if (response['result'] == 'success') {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('âœ… ${response['message'] ?? 'Excel data uploaded successfully.'}', style: guFont())),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('âŒ ${response['message'] ?? 'Upload failed.'}', style: guFont(color: Colors.white)), backgroundColor: Colors.red),
        );
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('âŒ Error: $e', style: guFont(color: Colors.white)), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: Text('માત્ર હાજરીપત્રકમાટે માહિતી અપલોડ કરો', style: guFont(fontSize: 18, color: Colors.white, fontWeight: FontWeight.bold)),
        backgroundColor: AppColors.navy,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: _isLoading 
            ? const CircularProgressIndicator()
            : Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.cloud_upload_outlined, size: 80, color: AppColors.teal),
                  const SizedBox(height: 30),
                  
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(backgroundColor: AppColors.navy, padding: const EdgeInsets.symmetric(horizontal: 25, vertical: 15)),
                    icon: const Icon(Icons.download, color: Colors.white),
                    label: Text('ખાલી ટેમ્પલેટ ડાઉનલોડ કરો', style: guFont(fontSize: 16, color: Colors.white, fontWeight: FontWeight.bold)),
                    onPressed: () async {
                      setState(() => _isLoading = true);
                      try {
                        await context.read<AppState>().api!.downloadExcelTemplate();
                      } catch (e) {
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('âŒ Error: $e', style: guFont())));
                      }
                      setState(() => _isLoading = false);
                    },
                  ),
                  
                  const SizedBox(height: 25),
                  Text('નવી Template માં Admin દ્વારા બનાવેલા ધોરણોનો dropdown છે. કો-એડ શાળામાં જાતિ માટે કુમાર અથવા કન્યા પસંદ કરો; ત્યારબાદ ફાઈલ અપલોડ કરો.', textAlign: TextAlign.center, style: guFont(fontSize: 14, color: Colors.grey.shade700)),
                  const SizedBox(height: 25),

                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.orange, padding: const EdgeInsets.symmetric(horizontal: 25, vertical: 15)),
                    icon: const Icon(Icons.upload_file, color: Colors.white),
                    label: Text('એક્સેલ ફાઈલ અપલોડ કરો', style: guFont(fontSize: 16, color: Colors.white, fontWeight: FontWeight.bold)),
                    onPressed: _uploadExcel,
                  ),
                ],
              ),
        ),
      ),
    );
  }
}