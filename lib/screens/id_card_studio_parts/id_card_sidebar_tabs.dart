part of '../supabase_id_card_studio_screen.dart';

// ============================================================================
// 6 PROFESSIONAL SIDEBAR TABS:
// 1. STUDENTS  2. DESIGN  3. FIELDS & FONT  4. PHOTOS & SIGN  5. LAYERS  6. EXPORT
// ============================================================================

extension _IdCardStudioSidebarExt on _IdCardStudioViewState {
  Widget _buildSidebar(BuildContext context, {bool shrinkWrap = false}) {
    final layerCount = _curLayout.fields.length +
        (_showPhoto ? 1 : 0) +
        (_showSeal ? 1 : 0) +
        (_showSignature ? 1 : 0);

    final content = Column(
      mainAxisSize: shrinkWrap ? MainAxisSize.min : MainAxisSize.max,
      children: [
        TabBar(
          controller: _sideTabController,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          labelPadding: const EdgeInsets.symmetric(horizontal: 11),
          onTap: (idx) {
            _rebuild(() {});
            _saveLastOpenTab(idx);
          },
          tabs: [
            Tab(
              text:
                  'Students (${_selectedStudentIndices.length}/${_rows.length})',
            ),
            const Tab(text: 'Design'),
            const Tab(text: 'Fields & Font'),
            const Tab(text: 'Photos & Sign'),
            Tab(text: 'Layers ($layerCount)'),
            const Tab(text: 'Export'),
          ],
        ),
        if (shrinkWrap)
          Padding(
            padding: const EdgeInsets.all(12),
            child: _buildActiveSidebarTab(context),
          )
        else
          Expanded(
            child: SingleChildScrollView(
              physics: _isCanvasPointerDown
                  ? const NeverScrollableScrollPhysics()
                  : const ClampingScrollPhysics(),
              padding: const EdgeInsets.all(12),
              child: _buildActiveSidebarTab(context),
            ),
          ),
      ],
    );
    return Card(
      margin: shrinkWrap ? EdgeInsets.zero : const EdgeInsets.all(10),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Theme.of(context).dividerColor),
      ),
      child: content,
    );
  }

  Widget _buildActiveSidebarTab(BuildContext context) {
    switch (_sideTabController.index) {
      case 0:
        return _buildStudentsSelectionTab(context);
      case 1:
        return _buildDesignAndFilesTab(context);
      case 2:
        return _buildFieldsAndTypographyTab(context);
      case 3:
        return _buildPhotoTab(context);
      case 4:
        return _buildLayersTab(context);
      case 5:
      default:
        return _buildSheetAndExportTab(context);
    }
  }

  Widget _buildSectionCard({
    required BuildContext context,
    required String title,
    String? badge,
    required List<Widget> children,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(9),
        border:
            Border.all(color: Theme.of(context).dividerColor.withAlpha(120)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  title.toUpperCase(),
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.4,
                    color: Theme.of(context).colorScheme.secondary,
                  ),
                ),
              ),
              if (badge != null)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                  decoration: BoxDecoration(
                    color: Theme.of(context)
                        .colorScheme
                        .primaryContainer
                        .withAlpha(160),
                    borderRadius: BorderRadius.circular(99),
                  ),
                  child: Text(
                    badge,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          ...children,
        ],
      ),
    );
  }

  /// Shared Quick Header Selector widget shown in both Tab 1 (Students) and Tab 3 (Fields & Font)
  /// so checking a header chip or clicking "Insert Selected Headers" works immediately from anywhere!
  Widget _buildQuickDatabaseHeadersCard(BuildContext context) {
    final dbSpecs = _allAvailableDbHeaderSpecs();
    return _buildSectionCard(
      context: context,
      title: 'Quick Insert Student Headers onto Card',
      badge: '${_curLayout.fields.length} on card',
      children: [
        const Text(
          'Tap any header chip below to immediately insert or remove it on the ID card, or click "Insert Selected Headers":',
          style: TextStyle(fontSize: 11, color: Color(0xFF0D7480)),
        ),
        const SizedBox(height: 8),
        _buildDefaultPrefixSelector(),
        const SizedBox(height: 8),
        Wrap(
          spacing: 5,
          runSpacing: 5,
          children: dbSpecs.map((spec) {
            final colIdx = _headers.indexWhere(
              (h) => h.trim().toLowerCase() == spec.labelEn.trim().toLowerCase(),
            );
            final isOnCard = colIdx >= 0 &&
                _curLayout.fields
                    .any((f) => !f.isDirectText && f.col == colIdx);
            final checked =
                _selectedDbHeaderKeys.contains(spec.key) || isOnCard;
            return FilterChip(
              visualDensity: VisualDensity.compact,
              selected: checked,
              label: Text(
                '${spec.labelEn} (${spec.labelGu})',
                style: const TextStyle(fontSize: 11),
              ),
              onSelected: (v) {
                _toggleSingleDbHeaderOnCard(spec, v);
              },
            );
          }).toList(),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: FilledButton.icon(
                onPressed: () =>
                    _insertCheckedDatabaseHeadersOnCard(replaceExisting: false),
                icon: const Icon(Icons.playlist_add_check, size: 16),
                label: const Text(
                  'Insert Selected Headers',
                  style: TextStyle(fontSize: 11.5),
                ),
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () =>
                    _insertCheckedDatabaseHeadersOnCard(replaceExisting: true),
                icon: const Icon(Icons.autorenew, size: 15),
                label: const Text(
                  'Rebuild All Checked',
                  style: TextStyle(fontSize: 11.5),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  /// Admin-controlled default prefix (None by default).
  Widget _buildDefaultPrefixSelector() {
    return Row(
      children: [
        Expanded(
          child: DropdownButtonFormField<String>(
            value: _defaultPrefixMode,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'Prefix before value (new fields)',
              isDense: true,
              border: OutlineInputBorder(),
            ),
            items: const [
              DropdownMenuItem(
                value: 'none',
                child: Text('None — only value (default)',
                    style: TextStyle(fontSize: 12)),
              ),
              DropdownMenuItem(
                value: 'label',
                child: Text('Label — e.g. "જન્મ તારીખ: 05/06/2014"',
                    style: TextStyle(fontSize: 12)),
              ),
              DropdownMenuItem(
                value: 'header',
                child: Text('Column header — e.g. "Birth Date: …"',
                    style: TextStyle(fontSize: 12)),
              ),
            ],
            onChanged: (v) {
              if (v != null) _setDefaultPrefixMode(v);
            },
          ),
        ),
        const SizedBox(width: 6),
        Tooltip(
          message:
              'Apply this prefix choice to every data field already on the card',
          child: OutlinedButton(
            onPressed: () =>
                _setDefaultPrefixMode(_defaultPrefixMode, applyToExisting: true),
            child: const Text('Apply to all', style: TextStyle(fontSize: 11)),
          ),
        ),
      ],
    );
  }

  /// Shows where card records come from and lets the admin switch between
  /// the school student database and an uploaded Excel / CSV file.
  Widget _buildDataSourceCard(BuildContext context) {
    final isExcel = _excelDataSourceActive;
    return _buildSectionCard(
      context: context,
      title: 'Data Source for ID Cards',
      badge: isExcel ? 'Excel • ${_rows.length} rows' : 'School DB',
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: isExcel ? const Color(0xFFEFF6FF) : const Color(0xFFECFDF5),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isExcel ? const Color(0xFF93C5FD) : const Color(0xFF6EE7B7),
            ),
          ),
          child: Row(
            children: [
              Icon(
                isExcel ? Icons.table_chart_outlined : Icons.cloud_done_outlined,
                size: 18,
                color: isExcel ? const Color(0xFF1D4ED8) : const Color(0xFF047857),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  isExcel
                      ? 'Using "$_excelSourceFileName" — ${_rows.length} records, ${_headers.length} columns'
                      : 'Using school student database — ${_dbStudentsAll.length} students (DOB merged as DD/MM/YYYY)',
                  style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: FilledButton.icon(
                onPressed: _pickExcelOrCsvFile,
                icon: const Icon(Icons.upload_file, size: 16),
                label: const Text('Upload Excel / CSV',
                    style: TextStyle(fontSize: 11.5)),
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: isExcel
                  ? OutlinedButton.icon(
                      onPressed: _showExcelColumnsToCardDialog,
                      icon: const Icon(Icons.auto_awesome, size: 16),
                      label: const Text('Pick Columns for Card',
                          style: TextStyle(fontSize: 11.5)),
                    )
                  : OutlinedButton.icon(
                      onPressed: _downloadSampleCsv,
                      icon: const Icon(Icons.download, size: 16),
                      label: const Text('Sample CSV',
                          style: TextStyle(fontSize: 11.5)),
                    ),
            ),
          ],
        ),
        if (isExcel) ...[
          const SizedBox(height: 6),
          SizedBox(
            width: double.infinity,
            child: TextButton.icon(
              onPressed: () =>
                  _loadSchoolRecordsFromDatabase(switchToDatabase: true),
              icon: const Icon(Icons.storage_rounded, size: 16),
              label: const Text('Switch back to School Student Database',
                  style: TextStyle(fontSize: 11.5)),
            ),
          ),
        ],
        const SizedBox(height: 4),
        const Text(
          'Excel tips: first row = column names. Separate DD / MM / YYYY columns are merged automatically into Birth Date. Dates and mobile numbers keep their exact format.',
          style: TextStyle(fontSize: 10.5, color: Color(0xFF64748B)),
        ),
      ],
    );
  }

  // ==========================================================================
  // TAB 1: PROFESSIONAL STUDENT SELECTION PANEL + QUICK HEADER INSERT
  // ==========================================================================

  Widget _buildStudentsSelectionTab(BuildContext context) {
    final visibleIndices = _filteredStudentRowIndices();
    final selectedCount = _selectedStudentIndices.length;
    final totalCount = _rows.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildDataSourceCard(context),
        _buildSectionCard(
          context: context,
          title: '1. Class Filter, Photo Folder & Print Scope',
          badge: '$selectedCount of $totalCount selected',
          children: [
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    isExpanded: true,
                    value: _dbClasses.any((c) =>
                            (c['id'] ?? '').toString().trim() ==
                            _selectedClassId)
                        ? _selectedClassId
                        : '__ALL__',
                    decoration: InputDecoration(
                      labelText: _excelDataSourceActive
                          ? 'Class Filter (disabled — Excel data in use)'
                          : 'Class Filter (Keeps Current Card Design)',
                      isDense: true,
                      border: const OutlineInputBorder(),
                    ),
                    items: [
                      DropdownMenuItem(
                        value: '__ALL__',
                        child: Text(
                          'All Classes / Whole School (${_dbStudentsAll.length})',
                          style: const TextStyle(fontSize: 12),
                        ),
                      ),
                      for (final c in _dbClasses)
                        DropdownMenuItem(
                          value: (c['id'] ?? '').toString().trim(),
                          child: Text(
                            (c['label'] ?? c['class_key'] ?? 'Class')
                                .toString(),
                            style: const TextStyle(fontSize: 12),
                          ),
                        ),
                    ],
                    onChanged: _excelDataSourceActive
                        ? null
                        : (v) {
                            if (v == null) return;
                            _rebuild(() {
                              _selectedClassId = v;
                              _rebuildRowsFromStudentDatabase(
                                preserveExistingLayoutFields: true,
                              );
                            });
                          },
                  ),
                ),
                const SizedBox(width: 6),
                IconButton.filledTonal(
                  tooltip: 'Refresh Students from School Database',
                  onPressed: () =>
                      _loadSchoolRecordsFromDatabase(switchToDatabase: true),
                  icon: const Icon(Icons.sync, size: 18),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: FilledButton.tonalIcon(
                    onPressed: _pickStudentPhotoFolder,
                    icon: const Icon(Icons.folder_open_outlined, size: 16),
                    label: Text(
                      _uploadedPhotos.isEmpty
                          ? 'Upload Photo Folder'
                          : 'Photo Folder (${_uploadedPhotos.length})',
                      style: const TextStyle(fontSize: 11.5),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _pickPrincipalSignatureImage,
                    icon: const Icon(Icons.draw_outlined, size: 16),
                    label: Text(
                      _showSignature ? 'Principal Sign ✓' : 'Principal Sign PNG',
                      style: const TextStyle(fontSize: 11.5),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<PrintRecordScope>(
              isExpanded: true,
              value: _printScope,
              decoration: const InputDecoration(
                labelText: 'Generate / Print ID Cards For',
                isDense: true,
                border: OutlineInputBorder(),
              ),
              items: PrintRecordScope.values
                  .map(
                    (s) => DropdownMenuItem(
                      value: s,
                      child: Text(
                        s == PrintRecordScope.selectedOnly
                            ? '${s.label} ($selectedCount selected)'
                            : (s == PrintRecordScope.filteredOnly
                                ? '${s.label} (${visibleIndices.length} visible)'
                                : s.label),
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                  )
                  .toList(),
              onChanged: (v) {
                if (v == null) return;
                _rebuild(() {
                  _printScope = v;
                  _sheetPageIdx = 0;
                  _statusMessage =
                      'Print/Export scope set to "${v.label}" (${_activeRangeRows().length} card(s)).';
                });
              },
            ),
            const SizedBox(height: 6),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              title: const Text(
                'Selected-Only Preview Mode (Prev/Next cycles selected students)',
                style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600),
              ),
              value: _selectedOnlyPreviewMode,
              onChanged: (v) {
                _rebuild(() {
                  _selectedOnlyPreviewMode = v;
                  if (v) {
                    _printScope = PrintRecordScope.selectedOnly;
                    if (_selectedStudentIndices.isNotEmpty &&
                        !_selectedStudentIndices.contains(_curRowIdx)) {
                      final sorted = _selectedStudentIndices.toList()..sort();
                      _curRowIdx = sorted.first;
                      _syncControllersToSelection();
                    }
                  }
                });
              },
            ),
          ],
        ),

        // Quick Header Selector right inside Tab 1 so user never gets stuck
        _buildQuickDatabaseHeadersCard(context),

        _buildSectionCard(
          context: context,
          title: '2. Student Selection (Shift+Click / Ctrl+Click)',
          badge: '${visibleIndices.length} visible',
          children: [
            TextField(
              controller: _studentSearchCtrl,
              decoration: InputDecoration(
                labelText: 'Search Name, Roll No, GR No, Class, Mobile...',
                isDense: true,
                border: const OutlineInputBorder(),
                prefixIcon: const Icon(Icons.search, size: 18),
                suffixIcon: _studentPanelSearchQuery.isNotEmpty
                    ? IconButton(
                        tooltip: 'Clear Search',
                        icon: const Icon(Icons.clear, size: 16),
                        onPressed: () {
                          _studentSearchCtrl.clear();
                          _rebuild(() {
                            _studentPanelSearchQuery = '';
                            _filteredIndicesDirty = true;
                          });
                        },
                      )
                    : null,
              ),
              onChanged: (val) {
                _searchDebounceTimer?.cancel();
                _searchDebounceTimer =
                    Timer(const Duration(milliseconds: 140), () {
                  if (!mounted) return;
                  _rebuild(() {
                    _studentPanelSearchQuery = val;
                    _filteredIndicesDirty = true;
                  });
                });
              },
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                ActionChip(
                  avatar: const Icon(Icons.select_all, size: 14),
                  tooltip: 'Select All Visible Students (Ctrl+A)',
                  label: const Text('Select All (Ctrl+A)',
                      style: TextStyle(fontSize: 11)),
                  onPressed: _selectAllVisibleStudents,
                ),
                ActionChip(
                  avatar: const Icon(Icons.deselect, size: 14),
                  tooltip: 'Clear Selection (Ctrl+Shift+A)',
                  label: const Text('Clear (Ctrl+Shift+A)',
                      style: TextStyle(fontSize: 11)),
                  onPressed: _clearStudentSelection,
                ),
                ActionChip(
                  avatar: const Icon(Icons.swap_horiz, size: 14),
                  tooltip: 'Invert Selection (Ctrl+I)',
                  label: const Text('Invert (Ctrl+I)',
                      style: TextStyle(fontSize: 11)),
                  onPressed: _invertVisibleStudentSelection,
                ),
                ActionChip(
                  avatar: const Icon(Icons.print_outlined, size: 14),
                  tooltip: 'Set Print Scope to Selected Students Only',
                  label: Text('Use Selected ($selectedCount)',
                      style: const TextStyle(fontSize: 11)),
                  onPressed: () {
                    _rebuild(() {
                      _printScope = PrintRecordScope.selectedOnly;
                      _sheetPageIdx = 0;
                      _statusMessage =
                          'Sheet preview now showing $selectedCount selected student(s).';
                    });
                  },
                ),
              ],
            ),
            const SizedBox(height: 6),
            const Text(
              'Click: Select 1 • Ctrl+Click: Toggle • Shift+Click: Range • Ctrl+Shift+Click: Add Range',
              style: TextStyle(fontSize: 10.5, color: Color(0xFF0D7480)),
            ),
            const SizedBox(height: 6),
            Focus(
              focusNode: _studentListFocusNode,
              onKeyEvent: _handleStudentListKeyEvent,
              child: Container(
                height: 290,
                decoration: BoxDecoration(
                  border: Border.all(color: Theme.of(context).dividerColor),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: visibleIndices.isEmpty
                    ? const Center(
                        child: Text(
                          'No matching students found.',
                          style: TextStyle(fontSize: 12),
                        ),
                      )
                    : ListView.builder(
                        controller: _studentListScrollCtrl,
                        itemExtent: 46.0,
                        itemCount: visibleIndices.length,
                        itemBuilder: (ctx, visIdx) {
                          final rowIdx = visibleIndices[visIdx];
                          final r = _rows[rowIdx];
                          final isChecked =
                              _selectedStudentIndices.contains(rowIdx);
                          final isCurrent = _curRowIdx == rowIdx;
                          final name = r.length > 2 && r[2].trim().isNotEmpty
                              ? r[2].trim()
                              : 'Student #${rowIdx + 1}';
                          final cls = r.length > 3 ? r[3].trim() : '';
                          final roll = r.length > 4 ? r[4].trim() : '';
                          final gr = r.length > 5 ? r[5].trim() : '';
                          final subtitleParts = <String>[
                            if (cls.isNotEmpty) cls,
                            if (roll.isNotEmpty) 'Roll: $roll',
                            if (gr.isNotEmpty) 'GR: $gr',
                          ];

                          return InkWell(
                            onTap: () => _handleStudentRowClick(
                              rowIdx,
                              toggleCheckboxOnly: false,
                            ),
                            child: Container(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 8),
                              decoration: BoxDecoration(
                                color: isCurrent
                                    ? const Color(0x220D7480)
                                    : (isChecked
                                        ? const Color(0x120284C7)
                                        : null),
                                border: Border(
                                  bottom: BorderSide(
                                    color: Theme.of(context)
                                        .dividerColor
                                        .withAlpha(90),
                                  ),
                                ),
                              ),
                              child: Row(
                                children: [
                                  SizedBox(
                                    width: 28,
                                    child: Checkbox(
                                      visualDensity: VisualDensity.compact,
                                      value: isChecked,
                                      onChanged: (_) => _handleStudentRowClick(
                                        rowIdx,
                                        toggleCheckboxOnly: true,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  Expanded(
                                    child: Column(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          '${rowIdx + 1}. $name',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            fontSize: 12,
                                            fontWeight: isCurrent
                                                ? FontWeight.w700
                                                : FontWeight.w600,
                                          ),
                                        ),
                                        if (subtitleParts.isNotEmpty)
                                          Text(
                                            subtitleParts.join(' • '),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                              fontSize: 10.5,
                                              color: Color(0xFF64748B),
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                  if (isCurrent)
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF0D7480),
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: const Text(
                                        'Preview',
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontSize: 9.5,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: FilledButton.tonalIcon(
                    onPressed: () {
                      final nextNum = _rows.length + 1;
                      final newRow = List<String>.generate(
                        _headers.length,
                        (i) =>
                            i == 0 ? '$nextNum' : (i == 1 ? 'stu_$nextNum' : ''),
                      );
                      _rebuild(() {
                        _rows.add(newRow);
                        _filteredIndicesDirty = true;
                        _curRowIdx = _rows.length - 1;
                        _selectedStudentIndices.add(_curRowIdx);
                        _rangeTo = _rows.length;
                        _rangeToCtrl.text = '${_rows.length}';
                        _syncControllersToSelection();
                        _statusMessage =
                            'Added Blank Student Card #${_rows.length}.';
                      });
                    },
                    icon: const Icon(Icons.person_add_alt_1, size: 15),
                    label: const Text('Add Blank Row',
                        style: TextStyle(fontSize: 11.5)),
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _rows.length <= 1
                        ? null
                        : () {
                            _rebuild(() {
                              _rows.removeAt(_curRowIdx);
                              _filteredIndicesDirty = true;
                              _selectedStudentIndices.remove(_curRowIdx);
                              _curRowIdx = math.max(0, _curRowIdx - 1);
                              _rangeTo = _rows.length;
                              _rangeToCtrl.text = '${_rows.length}';
                              _syncControllersToSelection();
                              _statusMessage =
                                  'Deleted student row. ${_rows.length} remaining.';
                            });
                          },
                    icon: const Icon(Icons.delete_outline, size: 15),
                    label: const Text('Delete Row',
                        style: TextStyle(fontSize: 11.5)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ],
    );
  }

  // ==========================================================================
  // TAB 2: DESIGN, TEMPLATES, FILES & CARD DIMENSIONS
  // ==========================================================================

  Widget _buildDesignAndFilesTab(BuildContext context) {
    final blankThemes =
        BuiltInTemplateTheme.values.where((t) => t.isBlankStyle).toList();
    final colorThemes =
        BuiltInTemplateTheme.values.where((t) => !t.isBlankStyle).toList();
    final sizeBadge =
        '${(_cw / 10).toStringAsFixed(1).replaceAll('.0', '')} × ${(_ch / 10).toStringAsFixed(1).replaceAll('.0', '')} mm';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionCard(
          context: context,
          title: '1. Upload Card Template, Excel, Photo Folder & Principal Sign',
          badge: _uploadedTemplateBytes != null
              ? 'Custom Template'
              : 'Preserves Design',
          children: [
            Row(
              children: [
                Expanded(
                  child: FilledButton.tonalIcon(
                    onPressed: _pickCardTemplateImage,
                    icon: const Icon(Icons.image_outlined, size: 16),
                    label: Text(
                      _uploadedTemplateName.isNotEmpty
                          ? 'Template: $_uploadedTemplateName'
                          : 'Upload Card Template',
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 11.5),
                    ),
                  ),
                ),
                if (_uploadedTemplateBytes != null) ...[
                  const SizedBox(width: 6),
                  IconButton(
                    tooltip: 'Remove Uploaded Card Template',
                    onPressed: () {
                      _rebuild(() {
                        _uploadedTemplateBytes = null;
                        _cachedTemplateImage = null;
                        _uploadedTemplateName = '';
                        _statusMessage =
                            'Removed uploaded card template. Existing fields preserved.';
                      });
                    },
                    icon: const Icon(Icons.delete_outline,
                        color: Colors.red, size: 18),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _pickStudentPhotoFolder,
                    icon: const Icon(Icons.folder_open_outlined, size: 16),
                    label: Text(
                      _uploadedPhotos.isEmpty
                          ? 'Upload Photo Folder'
                          : 'Folder (${_uploadedPhotos.length} Photos)',
                      style: const TextStyle(fontSize: 11.5),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () =>
                        _pickStudentPhotos(forCurrentRecordOnly: false),
                    icon: const Icon(Icons.photo_library_outlined, size: 16),
                    label: const Text('Select Photos',
                        style: TextStyle(fontSize: 11.5)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _pickPrincipalSignatureImage,
                    icon: const Icon(Icons.draw_outlined, size: 16),
                    label: Text(
                      _showSignature
                          ? 'Principal Sign ✓'
                          : 'Principal Sign PNG',
                      style: const TextStyle(fontSize: 11.5),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _pickExcelOrCsvFile,
                    icon: const Icon(Icons.table_view_outlined, size: 16),
                    label: const Text('Upload Excel / CSV',
                        style: TextStyle(fontSize: 11.5)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                ActionChip(
                  avatar: const Icon(Icons.verified_outlined, size: 14),
                  label: Text(
                    _showSeal ? 'Upload / Change Seal' : 'Upload Seal PNG',
                    style: const TextStyle(fontSize: 11),
                  ),
                  onPressed: _pickSealImage,
                ),
                ActionChip(
                  avatar: const Icon(Icons.paste, size: 14),
                  label: const Text('Paste CSV/Excel',
                      style: TextStyle(fontSize: 11)),
                  onPressed: _showCsvImportDialog,
                ),
                ActionChip(
                  avatar: const Icon(Icons.download, size: 14),
                  label: const Text('Sample CSV',
                      style: TextStyle(fontSize: 11)),
                  onPressed: _downloadSampleCsv,
                ),
                ActionChip(
                  avatar: const Icon(Icons.save_alt, size: 14),
                  label: const Text('Backup JSON',
                      style: TextStyle(fontSize: 11)),
                  onPressed: _backupLayoutJson,
                ),
                ActionChip(
                  avatar: const Icon(Icons.restore_page, size: 14),
                  label: const Text('Restore JSON',
                      style: TextStyle(fontSize: 11)),
                  onPressed: _restoreLayoutJson,
                ),
              ],
            ),
          ],
        ),

        _buildSectionCard(
          context: context,
          title: '2. Blank & Built-in Card Backgrounds',
          badge: _uploadedTemplateBytes != null
              ? 'Uploaded Image'
              : _tplTheme.label,
          children: [
            const Text(
              'Blank Printable Backgrounds:',
              style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: blankThemes.map((t) {
                final selected =
                    _uploadedTemplateBytes == null && _tplTheme == t;
                return ChoiceChip(
                  label: Text(t.label, style: const TextStyle(fontSize: 11.5)),
                  selected: selected,
                  onSelected: (_) => _rebuild(() {
                    _uploadedTemplateBytes = null;
                    _cachedTemplateImage = null;
                    _uploadedTemplateName = '';
                    _tplTheme = t;
                    _statusMessage = 'Applied "${t.label}" background.';
                  }),
                );
              }).toList(),
            ),
            const SizedBox(height: 8),
            const Text(
              'Styled Color Templates:',
              style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: colorThemes.map((t) {
                final selected =
                    _uploadedTemplateBytes == null && _tplTheme == t;
                return ChoiceChip(
                  label: Text(t.label, style: const TextStyle(fontSize: 11.5)),
                  selected: selected,
                  onSelected: (_) => _rebuild(() {
                    _uploadedTemplateBytes = null;
                    _cachedTemplateImage = null;
                    _uploadedTemplateName = '';
                    _tplTheme = t;
                    _statusMessage = 'Applied "${t.label}" card template.';
                  }),
                );
              }).toList(),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _tplTitleCtrl,
              decoration: InputDecoration(
                labelText: 'Optional Top Header Title (Leave blank for none)',
                isDense: true,
                border: const OutlineInputBorder(),
                suffixIcon: _tplHeaderTitle.isNotEmpty
                    ? IconButton(
                        tooltip: 'Clear Header Title',
                        onPressed: () {
                          _rebuild(() {
                            _tplHeaderTitle = '';
                            _tplTitleCtrl.clear();
                          });
                        },
                        icon: const Icon(Icons.clear, size: 16),
                      )
                    : null,
              ),
              onChanged: (v) => _rebuild(() => _tplHeaderTitle = v),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                const Text('Accent Color:',
                    style:
                        TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600)),
                for (final col in const [
                  Color(0xFF0F766E),
                  Color(0xFF1E3A8A),
                  Color(0xFFB91C1C),
                  Color(0xFF78350F),
                  Color(0xFF0F172A),
                  Color(0xFF6B21A8),
                ])
                  GestureDetector(
                    onTap: () => _rebuild(() => _tplAccentColor = col),
                    child: Container(
                      width: 22,
                      height: 22,
                      decoration: BoxDecoration(
                        color: col,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: _tplAccentColor == col
                              ? Colors.amber
                              : Colors.transparent,
                          width: 2.5,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),

        _buildSectionCard(
          context: context,
          title: '3. Card Dimensions & Orientation',
          badge: sizeBadge,
          children: [
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final preset in const [
                  MapEntry('Standard 84×54', [840.0, 540.0]),
                  MapEntry('CR80 85.6×54', [856.0, 540.0]),
                  MapEntry('Small 70×45', [700.0, 450.0]),
                  MapEntry('Event 95×65', [950.0, 650.0]),
                  MapEntry('XL A7 105×74', [1050.0, 740.0]),
                ])
                  ActionChip(
                    label:
                        Text(preset.key, style: const TextStyle(fontSize: 11)),
                    onPressed: () {
                      final isV = _cw < _ch;
                      final w = isV ? preset.value[1] : preset.value[0];
                      final h = isV ? preset.value[0] : preset.value[1];
                      _applyNewCardSize(w, h);
                    },
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _cardWmmCtrl,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                      labelText: 'Width (mm)',
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                    onSubmitted: (v) {
                      final mm = double.tryParse(v) ?? 84.0;
                      _applyNewCardSize(mm * 10.0, _ch);
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _cardHmmCtrl,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                      labelText: 'Height (mm)',
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                    onSubmitted: (v) {
                      final mm = double.tryParse(v) ?? 54.0;
                      _applyNewCardSize(_cw, mm * 10.0);
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: DropdownButtonFormField<bool>(
                    isExpanded: true,
                    value: _cw < _ch,
                    decoration: const InputDecoration(
                      labelText: 'Orient.',
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                    items: const [
                      DropdownMenuItem(
                          value: false,
                          child: Text('Horiz.',
                              style: TextStyle(fontSize: 12))),
                      DropdownMenuItem(
                          value: true,
                          child:
                              Text('Vert.', style: TextStyle(fontSize: 12))),
                    ],
                    onChanged: (isV) {
                      if (isV == null) return;
                      final minD = math.min(_cw, _ch);
                      final maxD = math.max(_cw, _ch);
                      _applyNewCardSize(isV ? minD : maxD, isV ? maxD : minD);
                    },
                  ),
                ),
              ],
            ),
          ],
        ),
      ],
    );
  }

  // ==========================================================================
  // TAB 3: DATA FIELDS, HEADER BOX SIZE SETTING & FONT / TYPOGRAPHY CONTROLS
  // ==========================================================================

  Widget _buildFieldsAndTypographyTab(BuildContext context) {
    final selFields = _selectedFieldItems();
    final selField = selFields.isNotEmpty ? selFields.last : null;
    final filteredFonts = kAllAvailableStudioFonts
        .where((f) =>
            _fontSearchQuery.trim().isEmpty ||
            f.toLowerCase().contains(_fontSearchQuery.trim().toLowerCase()))
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 1. DATABASE HEADER SELECTOR (INSTANT INSERT ON CLICK)
        _buildQuickDatabaseHeadersCard(context),

        // 1B. INSERT ANY ACTIVE / EXCEL COLUMN CHIP
        _buildSectionCard(
          context: context,
          title: 'Active / Excel Columns (Tap to Insert on Card)',
          badge: '${_headers.length} cols',
          children: [
            Wrap(
              spacing: 5,
              runSpacing: 5,
              children: List.generate(_headers.length, (i) {
                final onCard = _curLayout.fields
                    .any((f) => !f.isDirectText && f.col == i);
                return ActionChip(
                  visualDensity: VisualDensity.compact,
                  avatar: Icon(
                    onCard ? Icons.check_circle : Icons.add_circle_outline,
                    size: 14,
                    color: onCard ? const Color(0xFF0D7480) : null,
                  ),
                  label: Text(
                    _headers[i],
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: onCard ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                  onPressed: () => _insertExcelHeaderColOnCard(i),
                );
              }),
            ),
          ],
        ),

        // 2. FIELD & HEADER BOX SIZE SETTING (CORNER DRAG + NUMERIC MM)
        _buildSectionCard(
          context: context,
          title: '2. Header / Field Box Size & Controls',
          badge: selField != null
              ? '${(selField.w / 10).toStringAsFixed(1)}×${(selField.h / 10).toStringAsFixed(1)} mm'
              : '${_curLayout.fields.length} total',
          children: [
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () => _addField(isDirectText: false),
                    icon: const Icon(Icons.add, size: 15),
                    label: const Text('Add DB Field',
                        style: TextStyle(fontSize: 11.5)),
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: FilledButton.tonalIcon(
                    onPressed: () => _addField(isDirectText: true),
                    icon: const Icon(Icons.text_fields, size: 15),
                    label: const Text('Add Direct Text',
                        style: TextStyle(fontSize: 11.5)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                ActionChip(
                  avatar: const Icon(Icons.copy_all_outlined, size: 14),
                  tooltip: 'Duplicate Selected Objects (Ctrl+D)',
                  label: const Text('Duplicate (Ctrl+D)',
                      style: TextStyle(fontSize: 11)),
                  onPressed: _effectiveSelectionKeys().isNotEmpty
                      ? _duplicateSelectedField
                      : null,
                ),
                ActionChip(
                  avatar: Icon(
                    selField?.locked == true
                        ? Icons.lock_open
                        : Icons.lock_outline,
                    size: 14,
                  ),
                  tooltip: 'Lock or Unlock Selected Objects (Ctrl+L)',
                  label: Text(
                    selField?.locked == true
                        ? 'Unlock (Ctrl+L)'
                        : 'Lock (Ctrl+L)',
                    style: const TextStyle(fontSize: 11),
                  ),
                  onPressed: _effectiveSelectionKeys().isNotEmpty
                      ? _toggleLockSelectedObjects
                      : null,
                ),
                ActionChip(
                  avatar: const Icon(Icons.group_work_outlined, size: 14),
                  tooltip: 'Group Selected Objects (Ctrl+G)',
                  label: const Text('Group (Ctrl+G)',
                      style: TextStyle(fontSize: 11)),
                  onPressed: _effectiveSelectionKeys().length >= 2
                      ? _groupSelectedObjects
                      : null,
                ),
                ActionChip(
                  avatar: const Icon(Icons.delete_outline,
                      size: 14, color: Colors.red),
                  tooltip: 'Delete Selected Objects (Del)',
                  label: const Text('Delete (Del)',
                      style: TextStyle(fontSize: 11, color: Colors.red)),
                  onPressed: _effectiveSelectionKeys().isNotEmpty
                      ? () => _deleteSelectedItem()
                      : null,
                ),
              ],
            ),
            if (selField != null) ...[
              const SizedBox(height: 10),
              const Text(
                'Header / Field Box Size (mm) — Or drag any corner handle on card:',
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _fieldWmmCtrl,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(
                        labelText: 'Box Width (mm)',
                        isDense: true,
                        border: OutlineInputBorder(),
                      ),
                      onSubmitted: (v) {
                        final mm = double.tryParse(v);
                        if (mm != null) {
                          final newW = (mm * 10.0).clamp(18.0, _cw);
                          _applyToSelectedFields((f) {
                            f.w = newW;
                            _clampItemToCard(f, minW: 18, minH: 10);
                          }, 'Set field box width to ${mm.toStringAsFixed(1)} mm.');
                          _syncControllersToSelection();
                        }
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _fieldHmmCtrl,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(
                        labelText: 'Box Height (mm)',
                        isDense: true,
                        border: OutlineInputBorder(),
                      ),
                      onSubmitted: (v) {
                        final mm = double.tryParse(v);
                        if (mm != null) {
                          final newH = (mm * 10.0).clamp(10.0, _ch);
                          _applyToSelectedFields((f) {
                            f.h = newH;
                            _clampItemToCard(f, minW: 18, minH: 10);
                          }, 'Set field box height to ${mm.toStringAsFixed(1)} mm.');
                          _syncControllersToSelection();
                        }
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(
                    child: _buildNumberSpinner(
                      context: context,
                      label: 'Width Step (mm)',
                      value: selField.w / 10.0,
                      min: 1.8,
                      max: _cw / 10.0,
                      step: 1.0,
                      onChanged: (mm) {
                        _applyToSelectedFields((f) {
                          f.w = (mm * 10.0).clamp(18.0, _cw);
                          _clampItemToCard(f, minW: 18, minH: 10);
                        });
                        _syncControllersToSelection();
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _buildNumberSpinner(
                      context: context,
                      label: 'Height Step (mm)',
                      value: selField.h / 10.0,
                      min: 1.0,
                      max: _ch / 10.0,
                      step: 0.5,
                      onChanged: (mm) {
                        _applyToSelectedFields((f) {
                          f.h = (mm * 10.0).clamp(10.0, _ch);
                          _clampItemToCard(f, minW: 18, minH: 10);
                        });
                        _syncControllersToSelection();
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: const Text(
                  'Direct Static Text Mode (Same text on all cards)',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                ),
                value: selField.isDirectText,
                onChanged: (v) {
                  _applyToSelectedFields((f) {
                    f.isDirectText = v;
                    if (v && f.staticText.isEmpty) {
                      final col = f.col
                          .clamp(0, math.max(0, _headers.length - 1))
                          .toInt();
                      f.staticText = (_curRowIdx < _rows.length &&
                              col < _rows[_curRowIdx].length)
                          ? _rows[_curRowIdx][col]
                          : 'Direct Text';
                    } else if (!v && f.col < 0) {
                      f.col = _headers.length > 2 ? 2 : 0;
                    }
                  });
                },
              ),
              if (selField.isDirectText) ...[
                TextField(
                  controller: _directTextCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Direct Text (Printed on Card)',
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (v) {
                    _applyToSelectedFields((f) => f.staticText = v);
                  },
                ),
              ] else ...[
                DropdownButtonFormField<int>(
                  isExpanded: true,
                  value: selField.col
                      .clamp(0, math.max(0, _headers.length - 1))
                      .toInt(),
                  decoration: const InputDecoration(
                    labelText: 'Database / Excel Column for Selected Field',
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                  items: List.generate(
                    _headers.length,
                    (i) => DropdownMenuItem(
                      value: i,
                      child: Text('Col ${i + 1}: ${_headers[i]}',
                          style: const TextStyle(fontSize: 12)),
                    ),
                  ),
                  onChanged: (v) {
                    if (v == null) return;
                    _rebuild(() {
                      selField.col = v;
                      AutoFitTypographyEngine.clearCache();
                      _syncControllersToSelection();
                    });
                  },
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _liveCellCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Live Text for Current Student Card',
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (v) {
                    _rebuild(() {
                      if (_curRowIdx < _rows.length &&
                          selField.col >= 0 &&
                          selField.col < _rows[_curRowIdx].length) {
                        _rows[_curRowIdx][selField.col] = v;
                        AutoFitTypographyEngine.clearCache();
                      }
                    });
                  },
                ),
              ],
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _prefixCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Prefix / Label (optional)',
                        isDense: true,
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (v) =>
                          _applyToSelectedFields((f) => f.prefix = v),
                    ),
                  ),
                  const SizedBox(width: 6),
                  if (!selField.isDirectText)
                    OutlinedButton(
                      onPressed: () {
                        final col = selField.col
                            .clamp(0, math.max(0, _headers.length - 1))
                            .toInt();
                        final h = _headers[col];
                        _applyToSelectedFields((f) => f.prefix = '$h: ');
                      },
                      child: const Text('Use Col Name',
                          style: TextStyle(fontSize: 11)),
                    ),
                ],
              ),
            ],
          ],
        ),

        // 3. BETTER FONT CONTROLS (DECIMAL SIZE, QUICK SIZES, SEARCH, GUJARATI PREVIEW)
        _buildSectionCard(
          context: context,
          title: '3. Better Font & Typography Controls',
          badge: selFields.length > 1
              ? 'Multi-Edit (${selFields.length})'
              : (selField?.autoFit == false ? 'Fixed Size' : 'Auto-Fit ON'),
          children: [
            if (selField == null)
              const Text(
                'Select one or more text fields on the card (Shift+Click / Ctrl+Click / Ctrl+A) to customize font family, decimal font size, color, case, spacing, and alignment.',
                style: TextStyle(fontSize: 12),
              )
            else ...[
              Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: TextField(
                      controller: _fontSizeCtrl,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(
                        labelText: 'Font Size (pt, decimal OK)',
                        isDense: true,
                        border: OutlineInputBorder(),
                      ),
                      onSubmitted: (v) {
                        final parsed = double.tryParse(v);
                        if (parsed != null) {
                          final clamped = parsed.clamp(3.5, 72.0);
                          _applyToSelectedFields(
                            (f) => f.fontSize = clamped,
                            'Set font size to $clamped pt on ${selFields.length} field(s).',
                          );
                        }
                      },
                    ),
                  ),
                  const SizedBox(width: 6),
                  IconButton.filledTonal(
                    tooltip: 'Decrease Font Size (-0.5 pt)',
                    onPressed: () {
                      final next = (selField.fontSize - 0.5).clamp(3.5, 72.0);
                      _applyToSelectedFields(
                        (f) => f.fontSize = next,
                        'Font size: $next pt',
                      );
                    },
                    icon: const Icon(Icons.text_decrease, size: 17),
                  ),
                  const SizedBox(width: 4),
                  IconButton.filledTonal(
                    tooltip: 'Increase Font Size (+0.5 pt)',
                    onPressed: () {
                      final next = (selField.fontSize + 0.5).clamp(3.5, 72.0);
                      _applyToSelectedFields(
                        (f) => f.fontSize = next,
                        'Font size: $next pt',
                      );
                    },
                    icon: const Icon(Icons.text_increase, size: 17),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              const Text(
                'Quick Font Sizes (pt):',
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 4),
              Wrap(
                spacing: 4,
                runSpacing: 4,
                children: kQuickFontSizes.map((sz) {
                  final label =
                      sz.toStringAsFixed(1).replaceAll(RegExp(r'\.0$'), '');
                  final isCur = (selField.fontSize - sz).abs() < 0.08;
                  return ChoiceChip(
                    visualDensity: VisualDensity.compact,
                    label: Text(label, style: const TextStyle(fontSize: 11)),
                    selected: isCur,
                    onSelected: (_) {
                      _applyToSelectedFields(
                        (f) => f.fontSize = sz,
                        'Applied $label pt font size to ${selFields.length} field(s).',
                      );
                    },
                  );
                }).toList(),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _fontSearchCtrl,
                decoration: InputDecoration(
                  labelText: 'Search Font Family (Gujarati / English)',
                  isDense: true,
                  border: const OutlineInputBorder(),
                  prefixIcon:
                      const Icon(Icons.font_download_outlined, size: 17),
                  suffixIcon: _fontSearchQuery.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear, size: 15),
                          onPressed: () {
                            _fontSearchCtrl.clear();
                            _rebuild(() => _fontSearchQuery = '');
                          },
                        )
                      : null,
                ),
                onChanged: (v) => _rebuild(() => _fontSearchQuery = v),
              ),
              const SizedBox(height: 6),
              if (_recentFonts.isNotEmpty) ...[
                const Text(
                  'Recently Used Fonts:',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 5,
                  runSpacing: 5,
                  children: _recentFonts.map((fn) {
                    final active = selField.fontFamily == fn;
                    return ActionChip(
                      visualDensity: VisualDensity.compact,
                      backgroundColor:
                          active ? const Color(0x240D7480) : null,
                      label: Text(
                        fn == 'NotoSansGujaratiLocal'
                            ? 'Noto Sans Gujarati'
                            : (fn == 'LohitGujaratiLocal'
                                ? 'Lohit Gujarati'
                                : fn),
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight:
                              active ? FontWeight.w700 : FontWeight.w500,
                        ),
                      ),
                      onPressed: () {
                        _recordRecentFont(fn);
                        _applyToSelectedFields(
                          (f) => f.fontFamily = fn,
                          'Applied font "$fn" to ${selFields.length} field(s).',
                        );
                      },
                    );
                  }).toList(),
                ),
                const SizedBox(height: 8),
              ],
              DropdownButtonFormField<String>(
                isExpanded: true,
                value: filteredFonts.contains(selField.fontFamily)
                    ? selField.fontFamily
                    : (filteredFonts.isNotEmpty
                        ? filteredFonts.first
                        : 'NotoSansGujaratiLocal'),
                decoration: const InputDecoration(
                  labelText: 'Select Font Family',
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
                items: (filteredFonts.isNotEmpty
                        ? filteredFonts
                        : kAllAvailableStudioFonts)
                    .map(
                      (fn) => DropdownMenuItem(
                        value: fn,
                        child: Text(
                          fn == 'NotoSansGujaratiLocal'
                              ? 'Noto Sans Gujarati (Default)'
                              : (fn == 'LohitGujaratiLocal'
                                  ? 'Lohit Gujarati'
                                  : fn),
                          style: TextStyle(fontFamily: fn, fontSize: 12.5),
                        ),
                      ),
                    )
                    .toList(),
                onChanged: (v) {
                  if (v == null) return;
                  _recordRecentFont(v);
                  _applyToSelectedFields(
                    (f) => f.fontFamily = v,
                    'Applied font "$v" to ${selFields.length} field(s).',
                  );
                },
              ),
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(7),
                  border: Border.all(color: Theme.of(context).dividerColor),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'GUJARATI & ENGLISH FONT PREVIEW',
                      style: TextStyle(
                        fontSize: 9.5,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF64748B),
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      'અ આ ઇ ઈ ઉ ઊ • શાળા ઓળખપત્ર • ૧૨૩૪૫૬૭૮૯૦ • Student ID 2026',
                      style: TextStyle(
                        fontFamily: selField.fontFamily,
                        fontSize: 13.5,
                        fontWeight:
                            selField.bold ? FontWeight.w700 : FontWeight.w400,
                        fontStyle: selField.italic
                            ? FontStyle.italic
                            : FontStyle.normal,
                        decoration: selField.underline
                            ? TextDecoration.underline
                            : TextDecoration.none,
                        letterSpacing: selField.letterSpacing,
                        height: selField.lineHeight,
                        color: selField.color == const Color(0xFFFFFFFF)
                            ? const Color(0xFF0F172A)
                            : selField.color,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: _buildNumberSpinner(
                      context: context,
                      label: 'Min Fit (pt)',
                      value: selField.minFontSize,
                      min: 3.0,
                      max: 36.0,
                      step: 0.5,
                      onChanged: (v) =>
                          _applyToSelectedFields((f) => f.minFontSize = v),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: _buildNumberSpinner(
                      context: context,
                      label: 'Line Height',
                      value: selField.lineHeight,
                      min: 0.85,
                      max: 2.2,
                      step: 0.05,
                      onChanged: (v) =>
                          _applyToSelectedFields((f) => f.lineHeight = v),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: _buildNumberSpinner(
                      context: context,
                      label: 'Letter Space',
                      value: selField.letterSpacing,
                      min: -1.0,
                      max: 8.0,
                      step: 0.2,
                      onChanged: (v) =>
                          _applyToSelectedFields((f) => f.letterSpacing = v),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<TextCaseTransform>(
                isExpanded: true,
                value: selField.textCase,
                decoration: const InputDecoration(
                  labelText:
                      'Text Case Tool (Uppercase / Lowercase / Title Case)',
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
                items: TextCaseTransform.values
                    .map(
                      (c) => DropdownMenuItem(
                        value: c,
                        child:
                            Text(c.label, style: const TextStyle(fontSize: 12)),
                      ),
                    )
                    .toList(),
                onChanged: (c) {
                  if (c == null) return;
                  _applyToSelectedFields(
                    (f) => f.textCase = c,
                    'Applied "${c.label}" to ${selFields.length} field(s).',
                  );
                },
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: SegmentedButton<TextAlign>(
                      segments: const [
                        ButtonSegment(
                          value: TextAlign.left,
                          icon: Icon(Icons.format_align_left, size: 15),
                        ),
                        ButtonSegment(
                          value: TextAlign.center,
                          icon: Icon(Icons.format_align_center, size: 15),
                        ),
                        ButtonSegment(
                          value: TextAlign.right,
                          icon: Icon(Icons.format_align_right, size: 15),
                        ),
                      ],
                      selected: {selField.align},
                      onSelectionChanged: (s) =>
                          _applyToSelectedFields((f) => f.align = s.first),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: SegmentedButton<VerticalTextAlign>(
                      segments: const [
                        ButtonSegment(
                          value: VerticalTextAlign.top,
                          icon: Icon(Icons.vertical_align_top, size: 15),
                        ),
                        ButtonSegment(
                          value: VerticalTextAlign.middle,
                          icon: Icon(Icons.vertical_align_center, size: 15),
                        ),
                        ButtonSegment(
                          value: VerticalTextAlign.bottom,
                          icon: Icon(Icons.vertical_align_bottom, size: 15),
                        ),
                      ],
                      selected: {selField.valign},
                      onSelectionChanged: (s) =>
                          _applyToSelectedFields((f) => f.valign = s.first),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  const Text('Color:',
                      style: TextStyle(
                          fontSize: 11.5, fontWeight: FontWeight.w600)),
                  for (final col in const [
                    Color(0xFF0F172A),
                    Color(0xFF0D7480),
                    Color(0xFF1E3A8A),
                    Color(0xFFB91C1C),
                    Color(0xFF15803D),
                    Color(0xFF78350F),
                    Color(0xFF6B21A8),
                    Color(0xFFFFFFFF),
                  ])
                    GestureDetector(
                      onTap: () => _applyToSelectedFields((f) => f.color = col),
                      child: Container(
                        width: 22,
                        height: 22,
                        decoration: BoxDecoration(
                          color: col,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: selField.color.toARGB32() == col.toARGB32()
                                ? Colors.amber
                                : Colors.grey,
                            width: selField.color.toARGB32() == col.toARGB32()
                                ? 2.5
                                : 1.0,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  FilterChip(
                    visualDensity: VisualDensity.compact,
                    label: const Text('Bold', style: TextStyle(fontSize: 11.5)),
                    selected: selField.bold,
                    onSelected: (v) =>
                        _applyToSelectedFields((f) => f.bold = v),
                  ),
                  FilterChip(
                    visualDensity: VisualDensity.compact,
                    label:
                        const Text('Italic', style: TextStyle(fontSize: 11.5)),
                    selected: selField.italic,
                    onSelected: (v) =>
                        _applyToSelectedFields((f) => f.italic = v),
                  ),
                  FilterChip(
                    visualDensity: VisualDensity.compact,
                    label: const Text('Underline',
                        style: TextStyle(fontSize: 11.5)),
                    selected: selField.underline,
                    onSelected: (v) =>
                        _applyToSelectedFields((f) => f.underline = v),
                  ),
                  FilterChip(
                    visualDensity: VisualDensity.compact,
                    label: const Text('Bold Prefix',
                        style: TextStyle(fontSize: 11.5)),
                    selected: selField.prefixBold,
                    onSelected: (v) =>
                        _applyToSelectedFields((f) => f.prefixBold = v),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.tonalIcon(
                      onPressed: () {
                        final curRow = _rows.isNotEmpty
                            ? _rows[
                                _curRowIdx.clamp(0, _rows.length - 1).toInt()]
                            : const <String>[];
                        _applyToSelectedFields((f) {
                          f.autoFit = true;
                          final raw = (!f.isDirectText &&
                                  f.col >= 0 &&
                                  f.col < curRow.length)
                              ? curRow[f.col]
                              : f.staticText;
                          final fit =
                              AutoFitTypographyEngine.computeFittedFontSize(
                                  f, raw);
                          f.fontSize = fit.fittedPt;
                        }, 'Auto-fitted text inside selected field box(es).');
                      },
                      icon: const Icon(Icons.fit_screen_outlined, size: 15),
                      label: const Text('Fit Text Now',
                          style: TextStyle(fontSize: 11.5)),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () {
                        _applyToSelectedFields(
                          (f) => f.resetToOriginalStyle(),
                          'Reset selected field(s) to original text style.',
                        );
                      },
                      icon: const Icon(Icons.restart_alt, size: 15),
                      label: const Text('Reset Style',
                          style: TextStyle(fontSize: 11.5)),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              ExpansionTile(
                tilePadding: EdgeInsets.zero,
                childrenPadding: EdgeInsets.zero,
                title: const Text(
                  'Advanced Auto-Fit & Global Style Options',
                  style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600),
                ),
                children: [
                  DropdownButtonFormField<TextFitMode>(
                    isExpanded: true,
                    value: selField.textMode,
                    decoration: const InputDecoration(
                      labelText: 'Long Text Behaviour',
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                    items: TextFitMode.values
                        .map((m) => DropdownMenuItem(
                              value: m,
                              child: Text(m.label,
                                  style: const TextStyle(fontSize: 12)),
                            ))
                        .toList(),
                    onChanged: (m) {
                      if (m != null) {
                        _applyToSelectedFields((f) => f.textMode = m);
                      }
                    },
                  ),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    title: const Text(
                      'Auto-fit font size so long names never cut off',
                      style: TextStyle(fontSize: 11.5),
                    ),
                    value: selField.autoFit,
                    onChanged: (v) =>
                        _applyToSelectedFields((f) => f.autoFit = v ?? true),
                  ),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    title: const Text(
                      'Prevent field overlaps & keep inside card',
                      style: TextStyle(fontSize: 11.5),
                    ),
                    value: _preventOverlap,
                    onChanged: (v) => _rebuild(() {
                      _preventOverlap = v ?? false;
                      if (_preventOverlap) {
                        _resolveLayoutCollisions(_curLayout, forceStack: true);
                      }
                    }),
                  ),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.tonal(
                      onPressed: () {
                        _rebuild(() {
                          final targets =
                              _applyAllSets ? _layouts : [_curLayout];
                          for (final l in targets) {
                            for (final f in l.fields) {
                              if (f.locked) continue;
                              if (_incFont) f.fontFamily = selField.fontFamily;
                              if (_incSize) {
                                f.fontSize = selField.fontSize;
                                f.minFontSize = selField.minFontSize;
                              }
                              if (_incAlign) {
                                f.align = selField.align;
                                f.valign = selField.valign;
                              }
                              if (_incColor) f.color = selField.color;
                              if (_incStyle) {
                                f.bold = selField.bold;
                                f.italic = selField.italic;
                                f.underline = selField.underline;
                              }
                              if (_incAutoFit) {
                                f.autoFit = selField.autoFit;
                                f.textMode = selField.textMode;
                              }
                            }
                          }
                          _defaultStyleTemplate = selField.copy();
                          AutoFitTypographyEngine.clearCache();
                          _statusMessage =
                              'Applied style to all unlocked fields.';
                        });
                        _pushHistory();
                      },
                      child: const Text('Apply Style to All Card Fields'),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ],
    );
  }

  // ==========================================================================
  // TAB 4: PHOTO SIZE, UNIFORM PHOTO FRAME, PRINCIPAL SIGN PNG & SEAL OVERLAY
  // ==========================================================================

  Widget _buildPhotoTab(BuildContext context) {
    final p = _curLayout.photo;
    final s = _curLayout.seal;
    final sig = _curLayout.signature;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 1. PORTRAIT PHOTO FRAME & SIZE SETTING
        _buildSectionCard(
          context: context,
          title: '1. Portrait Photo Frame & Size Setting',
          badge: _showPhoto
              ? '${(p.w / 10).toStringAsFixed(1)}×${(p.h / 10).toStringAsFixed(1)} mm'
              : 'Hidden',
          children: [
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              title: const Text('Show Student Photo Box on Card',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
              value: _showPhoto,
              onChanged: (v) => _rebuild(() => _showPhoto = v),
            ),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _pickStudentPhotoFolder,
                    icon: const Icon(Icons.folder_open_outlined, size: 15),
                    label: Text(
                      _uploadedPhotos.isEmpty
                          ? 'Upload Photo Folder'
                          : 'Photo Folder (${_uploadedPhotos.length})',
                      style: const TextStyle(fontSize: 11.5),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: FilledButton.tonalIcon(
                    onPressed: () =>
                        _pickStudentPhotos(forCurrentRecordOnly: false),
                    icon: const Icon(Icons.photo_library_outlined, size: 15),
                    label: const Text('Select Photos',
                        style: TextStyle(fontSize: 11.5)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () =>
                        _pickStudentPhotos(forCurrentRecordOnly: true),
                    icon: const Icon(Icons.add_a_photo_outlined, size: 15),
                    label: const Text('Photo for Current Student',
                        style: TextStyle(fontSize: 11.5)),
                  ),
                ),
                const SizedBox(width: 6),
                if (_showPhoto)
                  OutlinedButton.icon(
                    style:
                        OutlinedButton.styleFrom(foregroundColor: Colors.red),
                    onPressed: () {
                      _rebuild(() {
                        _showPhoto = false;
                        if (_selKey?.type == SelectedItemType.photo) {
                          _selKey = null;
                          _multiSel = [];
                        }
                      });
                    },
                    icon: const Icon(Icons.delete_outline, size: 15),
                    label: const Text('Hide Photo',
                        style: TextStyle(fontSize: 11.5)),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<int>(
              isExpanded: true,
              value:
                  _photoCol.clamp(0, math.max(0, _headers.length - 1)).toInt(),
              decoration: const InputDecoration(
                labelText: 'Photo Match Column (Matches Photo Filename / GR / Roll)',
                isDense: true,
                border: OutlineInputBorder(),
              ),
              items: List.generate(
                _headers.length,
                (i) => DropdownMenuItem(
                  value: i,
                  child: Text('Col ${i + 1}: ${_headers[i]}',
                      style: const TextStyle(fontSize: 12)),
                ),
              ),
              onChanged: (v) {
                if (v != null) _rebuild(() => _photoCol = v);
              },
            ),
            const SizedBox(height: 10),
            const Text(
              'Photo Size Setting (mm) — Or drag any corner handle on card:',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _photoWmmCtrl,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                      labelText: 'Photo Width (mm)',
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                    onSubmitted: (v) {
                      final mm = double.tryParse(v);
                      if (mm != null) {
                        _rebuild(() {
                          _showPhoto = true;
                          final aspect =
                              p.h > 0 ? p.w / p.h : (20.5 / 25.5);
                          p.w = (mm * 10.0).clamp(24.0, _cw);
                          if (_photoLockAspect) {
                            p.h = (p.w / aspect).clamp(24.0, _ch);
                          }
                          _clampItemToCard(p, minW: 24, minH: 24);
                          _syncControllersToSelection();
                        });
                        _pushHistory();
                      }
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _photoHmmCtrl,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                      labelText: 'Photo Height (mm)',
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                    onSubmitted: (v) {
                      final mm = double.tryParse(v);
                      if (mm != null) {
                        _rebuild(() {
                          _showPhoto = true;
                          final aspect =
                              p.h > 0 ? p.w / p.h : (20.5 / 25.5);
                          p.h = (mm * 10.0).clamp(24.0, _ch);
                          if (_photoLockAspect) {
                            p.w = (p.h * aspect).clamp(24.0, _cw);
                          }
                          _clampItemToCard(p, minW: 24, minH: 24);
                          _syncControllersToSelection();
                        });
                        _pushHistory();
                      }
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: _buildNumberSpinner(
                    context: context,
                    label: 'Photo Width (mm)',
                    value: p.w / 10.0,
                    min: 2.4,
                    max: _cw / 10.0,
                    step: 0.5,
                    onChanged: (mm) {
                      _rebuild(() {
                        _showPhoto = true;
                        final aspect = p.h > 0 ? p.w / p.h : (20.5 / 25.5);
                        p.w = (mm * 10.0).clamp(24.0, _cw);
                        if (_photoLockAspect) {
                          p.h = (p.w / aspect).clamp(24.0, _ch);
                        }
                        _clampItemToCard(p, minW: 24, minH: 24);
                        _syncControllersToSelection();
                      });
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildNumberSpinner(
                    context: context,
                    label: 'Photo Height (mm)',
                    value: p.h / 10.0,
                    min: 2.4,
                    max: _ch / 10.0,
                    step: 0.5,
                    onChanged: (mm) {
                      _rebuild(() {
                        _showPhoto = true;
                        final aspect = p.h > 0 ? p.w / p.h : (20.5 / 25.5);
                        p.h = (mm * 10.0).clamp(24.0, _ch);
                        if (_photoLockAspect) {
                          p.w = (p.h * aspect).clamp(24.0, _cw);
                        }
                        _clampItemToCard(p, minW: 24, minH: 24);
                        _syncControllersToSelection();
                      });
                    },
                  ),
                ),
              ],
            ),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              title: const Text(
                'Lock Photo Aspect Ratio when resizing',
                style: TextStyle(fontSize: 11.5),
              ),
              value: _photoLockAspect,
              onChanged: (v) => _rebuild(() => _photoLockAspect = v ?? false),
            ),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                ActionChip(
                  label: const Text('Passport 35×45',
                      style: TextStyle(fontSize: 11.5)),
                  onPressed: () => _rebuild(() {
                    _showPhoto = true;
                    p.w = (_cw * 0.24).roundToDouble();
                    p.h = (_cw * 0.30).roundToDouble();
                    p.borderRadius = 10;
                    _clampItemToCard(p);
                    _syncControllersToSelection();
                  }),
                ),
                ActionChip(
                  label: const Text('Square 1:1',
                      style: TextStyle(fontSize: 11.5)),
                  onPressed: () => _rebuild(() {
                    _showPhoto = true;
                    final d = (math.min(_cw, _ch) * 0.38).roundToDouble();
                    p.w = d;
                    p.h = d;
                    p.borderRadius = 14;
                    _clampItemToCard(p);
                    _syncControllersToSelection();
                  }),
                ),
                ActionChip(
                  label: const Text('Circle Frame',
                      style: TextStyle(fontSize: 11.5)),
                  onPressed: () => _rebuild(() {
                    _showPhoto = true;
                    final d = (math.min(_cw, _ch) * 0.38).roundToDouble();
                    p.w = d;
                    p.h = d;
                    p.borderRadius = 300;
                    _clampItemToCard(p);
                    _syncControllersToSelection();
                  }),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
                'Uniform Frame Border Thickness: ${p.borderWidth.toStringAsFixed(1)} px',
                style: const TextStyle(fontSize: 12)),
            Slider(
              value: p.borderWidth.clamp(0, 16),
              min: 0,
              max: 16,
              onChanged: (v) => _rebuild(() => p.borderWidth = v),
            ),
            Wrap(
              spacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                const Text('Frame Color:',
                    style:
                        TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600)),
                for (final col in const [
                  Color(0xFF0D7480),
                  Color(0xFF0F172A),
                  Color(0xFF1E3A8A),
                  Color(0xFFB91C1C),
                  Color(0xFFD97706),
                  Color(0xFFFFFFFF),
                ])
                  GestureDetector(
                    onTap: () => _rebuild(() => p.borderColor = col),
                    child: Container(
                      width: 20,
                      height: 20,
                      decoration: BoxDecoration(
                        color: col,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: p.borderColor.toARGB32() == col.toARGB32()
                              ? Colors.amber
                              : Colors.grey,
                          width: p.borderColor.toARGB32() == col.toARGB32()
                              ? 2.5
                              : 1.0,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
                'Corner Radius (Uniform Thickness): ${p.borderRadius.toInt()}',
                style: const TextStyle(fontSize: 12)),
            Slider(
              value: p.borderRadius.clamp(0, 200),
              min: 0,
              max: 200,
              onChanged: (v) => _rebuild(() => p.borderRadius = v),
            ),
            Text('Brightness: ${p.brightness.toInt()}%',
                style: const TextStyle(fontSize: 12)),
            Slider(
              value: p.brightness.clamp(50, 150),
              min: 50,
              max: 150,
              onChanged: (v) => _rebuild(() => p.brightness = v),
            ),
          ],
        ),

        // 2. PRINCIPAL SIGNATURE PNG OVERLAY & CORNER DRAG SIZE SETTING
        _buildSectionCard(
          context: context,
          title: '2. Principal Signature PNG & Size Setting',
          badge: _showSignature
              ? '${(sig.w / 10).toStringAsFixed(1)}×${(sig.h / 10).toStringAsFixed(1)} mm'
              : 'Off',
          children: [
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              title: const Text('Show Principal Signature on Card',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
              value: _showSignature,
              onChanged: (v) => _rebuild(() => _showSignature = v),
            ),
            Row(
              children: [
                Expanded(
                  child: FilledButton.tonalIcon(
                    onPressed: _pickPrincipalSignatureImage,
                    icon: const Icon(Icons.draw_outlined, size: 15),
                    label: Text(
                      _uploadedSignatureName.isNotEmpty
                          ? 'Sign: $_uploadedSignatureName'
                          : 'Upload Principal Sign PNG',
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 11.5),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
                  onPressed: () {
                    _rebuild(() {
                      _showSignature = false;
                      _uploadedSignatureRawBytes = null;
                      _uploadedSignatureBytes = null;
                      _cachedSignatureImage = null;
                      _uploadedSignatureName = '';
                      if (_selKey?.type == SelectedItemType.signature) {
                        _selKey = null;
                        _multiSel = [];
                      }
                      _statusMessage = 'Deleted Principal Signature from card.';
                    });
                    _pushHistory();
                  },
                  icon: const Icon(Icons.delete_outline, size: 15),
                  label: const Text('Delete Sign',
                      style: TextStyle(fontSize: 11.5)),
                ),
              ],
            ),
            if (_uploadedSignatureRawBytes != null) ...[
              const SizedBox(height: 8),
              Text(
                'White Background Removal Tolerance: $_signatureTolerance',
                style: const TextStyle(fontSize: 12),
              ),
              Slider(
                value: _signatureTolerance.toDouble().clamp(0, 80),
                min: 0,
                max: 80,
                divisions: 80,
                onChanged: (v) {
                  _rebuild(() => _signatureTolerance = v.round());
                },
                onChangeEnd: (_) => _reprocessSignatureWithTolerance(),
              ),
            ],
            const SizedBox(height: 8),
            const Text(
              'Principal Sign Size (mm) — Or drag any corner handle on card:',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _signWmmCtrl,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                      labelText: 'Sign Width (mm)',
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                    onSubmitted: (v) {
                      final mm = double.tryParse(v);
                      if (mm != null) {
                        _rebuild(() {
                          _showSignature = true;
                          sig.w = (mm * 10.0).clamp(18.0, _cw);
                          if (_signatureLockAspect) {
                            sig.h =
                                (sig.w / _signatureAspect).clamp(12.0, _ch);
                          }
                          _clampItemToCard(sig, minW: 18, minH: 12, pad: 2);
                          _syncControllersToSelection();
                        });
                        _pushHistory();
                      }
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _signHmmCtrl,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                      labelText: 'Sign Height (mm)',
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                    onSubmitted: (v) {
                      final mm = double.tryParse(v);
                      if (mm != null) {
                        _rebuild(() {
                          _showSignature = true;
                          sig.h = (mm * 10.0).clamp(12.0, _ch);
                          if (_signatureLockAspect) {
                            sig.w =
                                (sig.h * _signatureAspect).clamp(18.0, _cw);
                          }
                          _clampItemToCard(sig, minW: 18, minH: 12, pad: 2);
                          _syncControllersToSelection();
                        });
                        _pushHistory();
                      }
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: _buildNumberSpinner(
                    context: context,
                    label: 'Sign Width (mm)',
                    value: sig.w / 10.0,
                    min: 1.8,
                    max: _cw / 10.0,
                    step: 0.5,
                    onChanged: (mm) {
                      _rebuild(() {
                        _showSignature = true;
                        sig.w = (mm * 10.0).clamp(18.0, _cw);
                        if (_signatureLockAspect) {
                          sig.h = (sig.w / _signatureAspect).clamp(12.0, _ch);
                        }
                        _clampItemToCard(sig, minW: 18, minH: 12, pad: 2);
                        _syncControllersToSelection();
                      });
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildNumberSpinner(
                    context: context,
                    label: 'Sign Height (mm)',
                    value: sig.h / 10.0,
                    min: 1.2,
                    max: _ch / 10.0,
                    step: 0.5,
                    onChanged: (mm) {
                      _rebuild(() {
                        _showSignature = true;
                        sig.h = (mm * 10.0).clamp(12.0, _ch);
                        if (_signatureLockAspect) {
                          sig.w = (sig.h * _signatureAspect).clamp(18.0, _cw);
                        }
                        _clampItemToCard(sig, minW: 18, minH: 12, pad: 2);
                        _syncControllersToSelection();
                      });
                    },
                  ),
                ),
              ],
            ),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              title: const Text(
                'Lock Principal Sign Aspect Ratio',
                style: TextStyle(fontSize: 11.5),
              ),
              value: _signatureLockAspect,
              onChanged: (v) =>
                  _rebuild(() => _signatureLockAspect = v ?? false),
            ),
          ],
        ),

        // 3. OFFICIAL STAMP / SEAL OVERLAY & CORNER DRAG SIZE SETTING
        _buildSectionCard(
          context: context,
          title: '3. Official Stamp / Seal Overlay & Size Setting',
          badge: _showSeal
              ? '${(s.w / 10).toStringAsFixed(1)}×${(s.h / 10).toStringAsFixed(1)} mm'
              : 'Deleted / Off',
          children: [
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              title: const Text('Show Official Seal on Card',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
              value: _showSeal,
              onChanged: (v) => _rebuild(() => _showSeal = v),
            ),
            Row(
              children: [
                Expanded(
                  child: FilledButton.tonalIcon(
                    onPressed: _pickSealImage,
                    icon: const Icon(Icons.upload_file, size: 15),
                    label: const Text('Upload Seal Image',
                        style: TextStyle(fontSize: 11.5)),
                  ),
                ),
                const SizedBox(width: 6),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
                  onPressed: () {
                    _rebuild(() {
                      _showSeal = false;
                      _uploadedSealRawBytes = null;
                      _uploadedSealBytes = null;
                      _cachedSealImage = null;
                      _uploadedSealName = '';
                      if (_selKey?.type == SelectedItemType.seal) {
                        _selKey = null;
                        _multiSel = [];
                      }
                      _statusMessage = 'Deleted Seal from card.';
                    });
                    _pushHistory();
                  },
                  icon: const Icon(Icons.delete_outline, size: 15),
                  label: const Text('Delete Seal',
                      style: TextStyle(fontSize: 11.5)),
                ),
              ],
            ),
            if (_uploadedSealRawBytes != null) ...[
              const SizedBox(height: 8),
              Text(
                'White Background Removal Tolerance: $_sealTolerance',
                style: const TextStyle(fontSize: 12),
              ),
              Slider(
                value: _sealTolerance.toDouble().clamp(0, 80),
                min: 0,
                max: 80,
                divisions: 80,
                onChanged: (v) {
                  _rebuild(() => _sealTolerance = v.round());
                },
                onChangeEnd: (_) => _reprocessSealWithTolerance(),
              ),
            ],
            const SizedBox(height: 8),
            const Text(
              'Seal Size Setting (mm) — Or drag any corner handle on card:',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _sealWmmCtrl,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                      labelText: 'Seal Width (mm)',
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                    onSubmitted: (v) {
                      final mm = double.tryParse(v);
                      if (mm != null) {
                        _rebuild(() {
                          _showSeal = true;
                          s.w = (mm * 10.0).clamp(18.0, _cw);
                          if (_sealLockAspect) {
                            s.h = (s.w / _sealAspect).clamp(18.0, _ch);
                          }
                          _clampItemToCard(s, minW: 18, minH: 18, pad: 2);
                          _syncControllersToSelection();
                        });
                        _pushHistory();
                      }
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _sealHmmCtrl,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                      labelText: 'Seal Height (mm)',
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                    onSubmitted: (v) {
                      final mm = double.tryParse(v);
                      if (mm != null) {
                        _rebuild(() {
                          _showSeal = true;
                          s.h = (mm * 10.0).clamp(18.0, _ch);
                          if (_sealLockAspect) {
                            s.w = (s.h * _sealAspect).clamp(18.0, _cw);
                          }
                          _clampItemToCard(s, minW: 18, minH: 18, pad: 2);
                          _syncControllersToSelection();
                        });
                        _pushHistory();
                      }
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: _buildNumberSpinner(
                    context: context,
                    label: 'Seal Width (mm)',
                    value: s.w / 10.0,
                    min: 1.8,
                    max: _cw / 10.0,
                    step: 0.5,
                    onChanged: (mm) {
                      _rebuild(() {
                        _showSeal = true;
                        s.w = (mm * 10.0).clamp(18.0, _cw);
                        if (_sealLockAspect) {
                          s.h = (s.w / _sealAspect).clamp(18.0, _ch);
                        }
                        _clampItemToCard(s, minW: 18, minH: 18, pad: 2);
                        _syncControllersToSelection();
                      });
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildNumberSpinner(
                    context: context,
                    label: 'Seal Height (mm)',
                    value: s.h / 10.0,
                    min: 1.8,
                    max: _ch / 10.0,
                    step: 0.5,
                    onChanged: (mm) {
                      _rebuild(() {
                        _showSeal = true;
                        s.h = (mm * 10.0).clamp(18.0, _ch);
                        if (_sealLockAspect) {
                          s.w = (s.h * _sealAspect).clamp(18.0, _cw);
                        }
                        _clampItemToCard(s, minW: 18, minH: 18, pad: 2);
                        _syncControllersToSelection();
                      });
                    },
                  ),
                ),
              ],
            ),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              title: const Text(
                'Lock Seal Aspect Ratio',
                style: TextStyle(fontSize: 11.5),
              ),
              value: _sealLockAspect,
              onChanged: (v) => _rebuild(() => _sealLockAspect = v ?? false),
            ),
            Slider(
              value: s.w.clamp(20, 350),
              min: 20,
              max: 350,
              onChanged: (v) => _rebuild(() {
                _showSeal = true;
                final cx = s.x + s.w / 2;
                final cy = s.y + s.h / 2;
                s.w = v;
                if (_sealLockAspect) {
                  s.h = v / _sealAspect;
                } else {
                  s.h = v;
                }
                s.x = cx - s.w / 2;
                s.y = cy - s.h / 2;
                _clampItemToCard(s, minW: 18, minH: 18, pad: 2);
                _syncControllersToSelection();
              }),
            ),
          ],
        ),
      ],
    );
  }

  // ==========================================================================
  // TAB 5: LAYERS, GROUPING, LOCKING & Z-ORDER PANEL
  // ==========================================================================

  Widget _buildLayersTab(BuildContext context) {
    final fields = _curLayout.fields;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionCard(
          context: context,
          title: 'Object Layers, Grouping & Locking',
          badge: '${_effectiveSelectionKeys().length} selected',
          children: [
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                ActionChip(
                  avatar: const Icon(Icons.arrow_upward, size: 14),
                  tooltip: 'Bring Selected Forward',
                  label: const Text('Bring Forward',
                      style: TextStyle(fontSize: 11)),
                  onPressed: () => _changeSelectedLayersOrder(1),
                ),
                ActionChip(
                  avatar: const Icon(Icons.arrow_downward, size: 14),
                  tooltip: 'Send Selected Backward',
                  label: const Text('Send Backward',
                      style: TextStyle(fontSize: 11)),
                  onPressed: () => _changeSelectedLayersOrder(-1),
                ),
                ActionChip(
                  avatar: const Icon(Icons.group_work_outlined, size: 14),
                  tooltip: 'Group Selected Objects (Ctrl+G)',
                  label: const Text('Group (Ctrl+G)',
                      style: TextStyle(fontSize: 11)),
                  onPressed: _groupSelectedObjects,
                ),
                ActionChip(
                  avatar: const Icon(Icons.workspaces_outline, size: 14),
                  tooltip: 'Ungroup Selected Objects (Ctrl+Shift+G)',
                  label: const Text('Ungroup (Ctrl+Shift+G)',
                      style: TextStyle(fontSize: 11)),
                  onPressed: _ungroupSelectedObjects,
                ),
                ActionChip(
                  avatar: const Icon(Icons.lock_outline, size: 14),
                  tooltip: 'Lock / Unlock Selected (Ctrl+L)',
                  label: const Text('Lock/Unlock (Ctrl+L)',
                      style: TextStyle(fontSize: 11)),
                  onPressed: _toggleLockSelectedObjects,
                ),
              ],
            ),
            const SizedBox(height: 8),
            // Principal Signature layer row
            if (_showSignature)
              _buildLayerRowTile(
                context: context,
                keyItem: const SelectedItemKey(SelectedItemType.signature, 0),
                item: _curLayout.signature,
                title: 'Principal Signature PNG',
                subtitle:
                    '${(_curLayout.signature.w / 10).toStringAsFixed(1)}×${(_curLayout.signature.h / 10).toStringAsFixed(1)} mm',
                icon: Icons.draw_outlined,
              ),
            // Seal layer row
            if (_showSeal)
              _buildLayerRowTile(
                context: context,
                keyItem: const SelectedItemKey(SelectedItemType.seal, 0),
                item: _curLayout.seal,
                title: 'Official Seal Overlay',
                subtitle:
                    '${(_curLayout.seal.w / 10).toStringAsFixed(1)}×${(_curLayout.seal.h / 10).toStringAsFixed(1)} mm',
                icon: Icons.verified_outlined,
              ),
            // Photo layer row
            if (_showPhoto)
              _buildLayerRowTile(
                context: context,
                keyItem: const SelectedItemKey(SelectedItemType.photo, 0),
                item: _curLayout.photo,
                title: 'Student Portrait Photo',
                subtitle:
                    '${(_curLayout.photo.w / 10).toStringAsFixed(1)}×${(_curLayout.photo.h / 10).toStringAsFixed(1)} mm',
                icon: Icons.account_box_outlined,
              ),
            // Text Field layers (top-most first)
            for (int i = fields.length - 1; i >= 0; i--)
              _buildLayerRowTile(
                context: context,
                keyItem: SelectedItemKey(SelectedItemType.field, i),
                item: fields[i],
                title: fields[i].isDirectText
                    ? 'Direct: "${fields[i].staticText}"'
                    : 'DB Col: ${fields[i].col >= 0 && fields[i].col < _headers.length ? _headers[fields[i].col] : "Field ${i + 1}"}',
                subtitle:
                    '${fields[i].fontFamily} • ${fields[i].fontSize.toStringAsFixed(1)} pt • ${(fields[i].w / 10).toStringAsFixed(1)}×${(fields[i].h / 10).toStringAsFixed(1)} mm',
                icon: fields[i].isDirectText
                    ? Icons.text_fields
                    : Icons.storage_outlined,
              ),
          ],
        ),
      ],
    );
  }

  Widget _buildLayerRowTile({
    required BuildContext context,
    required SelectedItemKey keyItem,
    required CardBoxItem item,
    required String title,
    required String subtitle,
    required IconData icon,
  }) {
    final isSel = _effectiveSelectionKeys().contains(keyItem);
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      decoration: BoxDecoration(
        color: isSel ? const Color(0x1E0D7480) : null,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: isSel
              ? const Color(0xFF0D7480)
              : Theme.of(context).dividerColor.withAlpha(110),
        ),
      ),
      child: ListTile(
        dense: true,
        visualDensity: VisualDensity.compact,
        contentPadding: const EdgeInsets.symmetric(horizontal: 8),
        leading: Icon(icon, size: 17, color: const Color(0xFF0D7480)),
        title: Row(
          children: [
            Expanded(
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style:
                    const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
              ),
            ),
            if (item.groupId != null)
              Container(
                margin: const EdgeInsets.only(left: 4),
                padding:
                    const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: const Color(0xFFE0F2FE),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  'G${item.groupId}',
                  style: const TextStyle(
                    fontSize: 9.5,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF0369A1),
                  ),
                ),
              ),
          ],
        ),
        subtitle: Text(subtitle, style: const TextStyle(fontSize: 10.5)),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              visualDensity: VisualDensity.compact,
              tooltip: item.locked ? 'Unlock Object' : 'Lock Object',
              icon: Icon(
                item.locked ? Icons.lock : Icons.lock_open,
                size: 16,
                color: item.locked ? Colors.amber.shade800 : Colors.grey,
              ),
              onPressed: () {
                _rebuild(() {
                  item.locked = !item.locked;
                  _statusMessage = item.locked
                      ? 'Locked "$title".'
                      : 'Unlocked "$title".';
                });
              },
            ),
          ],
        ),
        onTap: () => _selectObjectOnCanvas(keyItem),
      ),
    );
  }

  // ==========================================================================
  // TAB 6: SHEET IMPOSITION & EXPORT TAB
  // ==========================================================================

  Widget _buildSheetAndExportTab(BuildContext context) {
    final activeCount = _activeRangeRows().length;
    final geom = _computeSheetGeometry();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionCard(
          context: context,
          title: '1. Print / Generate ID Cards Scope',
          badge: '$activeCount Card(s)',
          children: [
            DropdownButtonFormField<PrintRecordScope>(
              isExpanded: true,
              value: _printScope,
              decoration: const InputDecoration(
                labelText: 'Generate / Print Scope',
                isDense: true,
                border: OutlineInputBorder(),
              ),
              items: PrintRecordScope.values
                  .map(
                    (s) => DropdownMenuItem(
                      value: s,
                      child:
                          Text(s.label, style: const TextStyle(fontSize: 12.5)),
                    ),
                  )
                  .toList(),
              onChanged: (v) {
                if (v != null) {
                  _rebuild(() {
                    _printScope = v;
                    _sheetPageIdx = 0;
                  });
                }
              },
            ),
            if (_printScope == PrintRecordScope.fromToRange) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _rangeFromCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'From Row #',
                        isDense: true,
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (v) {
                        final n = int.tryParse(v) ?? 1;
                        _rebuild(() {
                          _rangeFrom =
                              n.clamp(1, math.max(1, _rows.length)).toInt();
                          _sheetPageIdx = 0;
                        });
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _rangeToCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'To Row #',
                        isDense: true,
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (v) {
                        final n = int.tryParse(v) ?? _rows.length;
                        _rebuild(() {
                          _rangeTo = n
                              .clamp(_rangeFrom, math.max(1, _rows.length))
                              .toInt();
                          _sheetPageIdx = 0;
                        });
                      },
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),

        _buildSectionCard(
          context: context,
          title: '2. Sheet & Cut Guides Setup (Grid Hidden in Print)',
          badge: '${geom.perSheet}/sheet',
          children: [
            const Text(
              'Note: The Editor alignment grid and coordinate indicators are automatically excluded from printed sheets and exported PNGs.',
              style: TextStyle(fontSize: 11, color: Color(0xFF0D7480)),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    isExpanded: true,
                    value: _paperSize,
                    decoration: const InputDecoration(
                      labelText: 'Paper Size',
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                    items: const [
                      DropdownMenuItem(
                          value: '12x18',
                          child: Text('12 × 18 in',
                              style: TextStyle(fontSize: 12.5))),
                      DropdownMenuItem(
                          value: 'A4',
                          child: Text('A4 Portrait',
                              style: TextStyle(fontSize: 12.5))),
                      DropdownMenuItem(
                          value: 'A4L',
                          child: Text('A4 Landscape',
                              style: TextStyle(fontSize: 12.5))),
                      DropdownMenuItem(
                          value: 'A3',
                          child: Text('A3 Landscape',
                              style: TextStyle(fontSize: 12.5))),
                      DropdownMenuItem(
                          value: 'Letter',
                          child: Text('US Letter',
                              style: TextStyle(fontSize: 12.5))),
                      DropdownMenuItem(
                          value: 'Single',
                          child: Text('Single Card',
                              style: TextStyle(fontSize: 12.5))),
                    ],
                    onChanged: (v) {
                      if (v != null) _rebuild(() => _paperSize = v);
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: DropdownButtonFormField<int>(
                    isExpanded: true,
                    value: _exportDpi,
                    decoration: const InputDecoration(
                      labelText: 'Export DPI',
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                    items: const [
                      DropdownMenuItem(
                          value: 150,
                          child:
                              Text('150 DPI', style: TextStyle(fontSize: 12))),
                      DropdownMenuItem(
                          value: 200,
                          child:
                              Text('200 DPI', style: TextStyle(fontSize: 12))),
                      DropdownMenuItem(
                          value: 300,
                          child: Text('300 DPI (Print)',
                              style: TextStyle(fontSize: 12))),
                    ],
                    onChanged: (v) {
                      if (v != null) _rebuild(() => _exportDpi = v);
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _buildNumberSpinner(
                    context: context,
                    label: 'Card Gap (mm)',
                    value: _gapMm,
                    min: 0.0,
                    max: 15.0,
                    step: 0.5,
                    onChanged: (v) => _rebuild(() => _gapMm = v),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: DropdownButtonFormField<CutGuideStyle>(
                    isExpanded: true,
                    value: _guideStyle,
                    decoration: const InputDecoration(
                      labelText: 'Cut Guide Style',
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                    items: CutGuideStyle.values
                        .map((g) => DropdownMenuItem(
                              value: g,
                              child: Text(g.label,
                                  style: const TextStyle(fontSize: 12)),
                            ))
                        .toList(),
                    onChanged: (v) {
                      if (v != null) _rebuild(() => _guideStyle = v);
                    },
                  ),
                ),
              ],
            ),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              title: const Text('Draw cut guides on sheet',
                  style: TextStyle(fontSize: 12)),
              value: _drawCutGuides,
              onChanged: (v) => _rebuild(() => _drawCutGuides = v ?? true),
            ),
            const SizedBox(height: 6),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _isExporting
                    ? null
                    : () => _exportCurrentSheetPdf(
                          singleCardOnly: false,
                          allSheetsInScope: true,
                        ),
                icon: const Icon(Icons.picture_as_pdf, size: 16),
                label: Text(
                  'Export All Sheets PDF ($activeCount Cards • ${geom.totalPages} Page(s))',
                ),
              ),
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: FilledButton.tonalIcon(
                    onPressed: _isExporting
                        ? null
                        : () => _exportCurrentSheetPdf(
                              singleCardOnly: false,
                              allSheetsInScope: false,
                            ),
                    icon: const Icon(Icons.picture_as_pdf_outlined, size: 15),
                    label: Text(
                      'Current Sheet PDF (${_sheetPageIdx + 1}/${geom.totalPages})',
                      style: const TextStyle(fontSize: 11.5),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: FilledButton.tonalIcon(
                    onPressed: _isExporting
                        ? null
                        : () => _exportCurrentSheetPdf(singleCardOnly: true),
                    icon: const Icon(Icons.badge_outlined, size: 15),
                    label: const Text(
                      'Single Card PDF',
                      style: TextStyle(fontSize: 11.5),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _isExporting
                        ? null
                        : () => _exportCurrentSheetPng(
                              singleCardOnly: false,
                              allSheetsInScope: false,
                            ),
                    icon: const Icon(Icons.image_outlined, size: 15),
                    label: Text(
                      'Sheet PNG (${_sheetPageIdx + 1}/${geom.totalPages})',
                      style: const TextStyle(fontSize: 11.5),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _isExporting
                        ? null
                        : () => _exportCurrentSheetPng(singleCardOnly: true),
                    icon: const Icon(Icons.photo_outlined, size: 15),
                    label: const Text(
                      'Single Card PNG',
                      style: TextStyle(fontSize: 11.5),
                    ),
                  ),
                ),
              ],
            ),
            if (_lastSavedPdfBytes != null) ...[
              const SizedBox(height: 6),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _isExporting ? null : _openLastSavedPdf,
                  icon: const Icon(Icons.history_edu_outlined, size: 16),
                  label: Text(
                    'Open Last Saved PDF ($_lastSavedPdfName)',
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 11.5),
                  ),
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }

  Widget _buildNumberSpinner({
    required BuildContext context,
    required String label,
    required double value,
    required double min,
    required double max,
    required double step,
    required ValueChanged<double> onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        Container(
          decoration: BoxDecoration(
            border: Border.all(color: Theme.of(context).dividerColor),
            borderRadius: BorderRadius.circular(7),
          ),
          child: Row(
            children: [
              IconButton(
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.remove, size: 14),
                onPressed: () => onChanged((value - step).clamp(min, max)),
              ),
              Expanded(
                child: Text(
                  value.toStringAsFixed(2).replaceAll(RegExp(r'\.?0+$'), ''),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontSize: 11.5, fontWeight: FontWeight.w700),
                ),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.add, size: 14),
                onPressed: () => onChanged((value + step).clamp(min, max)),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
