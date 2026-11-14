import 'package:cross_file/cross_file.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../services/school_export_service.dart';

/// Reusable export button for AdminPanel and teacher class/report screens.
/// The service determines scope from the authenticated user's school/role.
class SchoolExportButton extends StatefulWidget {
  const SchoolExportButton({super.key, this.includePrivateDetails = false, this.label = 'Download Excel'});
  final bool includePrivateDetails;
  final String label;

  @override
  State<SchoolExportButton> createState() => _SchoolExportButtonState();
}

class _SchoolExportButtonState extends State<SchoolExportButton> {
  bool _busy = false;

  Future<void> _export() async {
    setState(() => _busy = true);
    try {
      final bundle = await SchoolExportService().exportForCurrentUser(
        includePrivateDetails: widget.includePrivateDetails,
      );
      await SharePlus.instance.share(ShareParams(
        title: 'Professional School Management export',
        subject: bundle.fileName,
        files: [XFile.fromData(
          bundle.bytes,
          name: bundle.fileName,
          mimeType: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
        )],
      ));
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Workbook prepared: ${bundle.fileName}')),
      );
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Export failed: $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => FilledButton.icon(
    onPressed: _busy ? null : _export,
    icon: _busy
        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
        : const Icon(Icons.file_download_outlined),
    label: Text(_busy ? 'Preparing…' : widget.label),
  );
}
