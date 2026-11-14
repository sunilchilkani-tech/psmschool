part of '../supabase_id_card_studio_screen.dart';

// ============================================================================
// TOP HEADER, COMPACT PRO TOOLBAR, ZERO-LAG 1:1 POINTER STAGE & CACHED CANVAS
// ============================================================================

extension _IdCardStudioStageExt on _IdCardStudioViewState {
  Widget _buildTopHeaderBar(BuildContext context) {
    final selObjCount = _effectiveSelectionKeys().length;
    final selStuCount = _selectedStudentIndices.length;

    return Container(
      color: const Color(0xFF0F172A),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      child: Wrap(
        spacing: 10,
        runSpacing: 8,
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (Navigator.of(context).canPop()) ...[
                IconButton(
                  tooltip: 'પાછા જાઓ / Back',
                  onPressed: () => Navigator.of(context).maybePop(),
                  icon: const Icon(Icons.arrow_back_rounded,
                      color: Colors.white),
                ),
                const SizedBox(width: 4),
              ],
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  gradient: const LinearGradient(
                    colors: [Color(0xFF14B8A6), Color(0xFF0284C7)],
                  ),
                ),
                alignment: Alignment.center,
                child: const Text(
                  'ID',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Flexible(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 6,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      const Text(
                        'ID Card Studio Pro',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 15.5,
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0x3314B8A6),
                          borderRadius: BorderRadius.circular(99),
                          border: Border.all(color: const Color(0x665EEAD4)),
                        ),
                        child: Text(
                          '$selStuCount of ${_rows.length} Students Selected',
                          style: const TextStyle(
                            color: Color(0xFF5EEAD4),
                            fontSize: 10.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(
                          color: selObjCount > 0
                              ? const Color(0x33F59E0B)
                              : const Color(0x2294A3B8),
                          borderRadius: BorderRadius.circular(99),
                          border: Border.all(
                            color: selObjCount > 0
                                ? const Color(0x88FBBF24)
                                : const Color(0x4494A3B8),
                          ),
                        ),
                        child: Text(
                          '$selObjCount Object${selObjCount == 1 ? '' : 's'} Selected',
                          style: TextStyle(
                            color: selObjCount > 0
                                ? const Color(0xFFFDE68A)
                                : const Color(0xFFCBD5E1),
                            fontSize: 10.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                  Text(
                    'Scope: ${_printScope.label} (${_activeRangeRows().length} cards) • Corner Drag Resize • Grid Hidden in Print',
                    style: const TextStyle(
                        color: Color(0xFF94A3B8), fontSize: 11),
                  ),
                ],
              )),
            ],
          ),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFFE2E8F0),
                  side: const BorderSide(color: Color(0x4494A3B8)),
                  visualDensity: VisualDensity.compact,
                ),
                onPressed: _showShortcutsHelpDialog,
                icon: const Icon(Icons.help_outline, size: 15),
                label: const Text('Shortcuts (F1)'),
              ),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFFFCA5A5),
                  side: const BorderSide(color: Color(0x59EF4444)),
                  visualDensity: VisualDensity.compact,
                ),
                onPressed: () =>
                    _clearAllPreFilledData(alsoClearTemplate: false),
                icon: const Icon(Icons.layers_clear, size: 15),
                label: const Text('Blank Card'),
              ),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF6EE7B7),
                  side: const BorderSide(color: Color(0x5910B981)),
                  visualDensity: VisualDensity.compact,
                ),
                onPressed: () =>
                    _insertCheckedDatabaseHeadersOnCard(replaceExisting: false),
                icon: const Icon(Icons.playlist_add_check, size: 15),
                label: const Text('Insert Headers'),
              ),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFFFDE68A),
                  side: const BorderSide(color: Color(0x59F59E0B)),
                  visualDensity: VisualDensity.compact,
                ),
                onPressed: _pickStudentPhotoFolder,
                icon: const Icon(Icons.folder_open_outlined, size: 15),
                label: const Text('Photo Folder'),
              ),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFFC4B5FD),
                  side: const BorderSide(color: Color(0x598B5CF6)),
                  visualDensity: VisualDensity.compact,
                ),
                onPressed: _pickPrincipalSignatureImage,
                icon: const Icon(Icons.draw_outlined, size: 15),
                label: const Text('Principal Sign'),
              ),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF7DD3FC),
                  side: const BorderSide(color: Color(0x5938BDF8)),
                  visualDensity: VisualDensity.compact,
                ),
                onPressed: _pickCardTemplateImage,
                icon: const Icon(Icons.image_outlined, size: 15),
                label: const Text('Template'),
              ),
              if (widget.onToggleTheme != null)
                IconButton(
                  tooltip: 'Switch Light / Dark Theme',
                  onPressed: widget.onToggleTheme,
                  icon: const Icon(Icons.brightness_6,
                      color: Colors.white70, size: 18),
                ),
              if (_lastSavedPdfBytes != null)
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFFFDE68A),
                    side: const BorderSide(color: Color(0x66F59E0B)),
                    visualDensity: VisualDensity.compact,
                  ),
                  onPressed: _isExporting ? null : _openLastSavedPdf,
                  icon: const Icon(Icons.history_edu_outlined, size: 15),
                  label: const Text('Saved PDF'),
                ),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  side: const BorderSide(color: Colors.white30),
                  visualDensity: VisualDensity.compact,
                ),
                onPressed: _isExporting
                    ? null
                    : () => _exportCurrentSheetPng(singleCardOnly: true),
                icon: const Icon(Icons.image_outlined, size: 15),
                label: const Text('Single PNG'),
              ),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFFA7F3D0),
                  side: const BorderSide(color: Color(0x6610B981)),
                  visualDensity: VisualDensity.compact,
                ),
                onPressed: _isExporting
                    ? null
                    : () => _exportCurrentSheetPdf(singleCardOnly: true),
                icon: const Icon(Icons.picture_as_pdf_outlined, size: 15),
                label: const Text('Single PDF'),
              ),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF0D7480),
                  foregroundColor: Colors.white,
                  visualDensity: VisualDensity.compact,
                ),
                onPressed: _isExporting
                    ? null
                    : () => _exportCurrentSheetPdf(
                          singleCardOnly: false,
                          allSheetsInScope: true,
                        ),
                icon: const Icon(Icons.picture_as_pdf, size: 15),
                label: Text('Export PDF (${_activeRangeRows().length})'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCompactProToolbar(BuildContext context) {
    final hasSel = _effectiveSelectionKeys().isNotEmpty;
    final multiCount = _effectiveSelectionKeys().length;
    final zoomPct = (_zoom * 100).round();

    Widget toolBtn({
      required IconData icon,
      required String tooltip,
      required VoidCallback? onTap,
      Color? color,
      bool active = false,
    }) {
      return Tooltip(
        message: tooltip,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(5),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            decoration: BoxDecoration(
              color: active ? const Color(0x240D7480) : null,
              borderRadius: BorderRadius.circular(5),
              border: Border.all(
                color: active
                    ? const Color(0xFF0D7480)
                    : Theme.of(context).dividerColor.withAlpha(110),
              ),
            ),
            child: Icon(
              icon,
              size: 15.5,
              color: onTap == null
                  ? Theme.of(context).disabledColor
                  : (color ?? Theme.of(context).colorScheme.onSurface),
            ),
          ),
        ),
      );
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        border: Border(
          bottom: BorderSide(color: Theme.of(context).dividerColor),
        ),
      ),
      child: Wrap(
        spacing: 5,
        runSpacing: 5,
        crossAxisAlignment: WrapCrossAlignment.center,
        alignment: WrapAlignment.spaceBetween,
        children: [
          // History, Clipboard, Grouping, Locking & Layer Order
          Wrap(
            spacing: 4,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              toolBtn(
                icon: Icons.undo,
                tooltip: 'Undo (Ctrl+Z)',
                onTap: _historyIdx > 0 ? () => _restoreHistory(-1) : null,
              ),
              toolBtn(
                icon: Icons.redo,
                tooltip: 'Redo (Ctrl+Y)',
                onTap: _historyIdx < _history.length - 1
                    ? () => _restoreHistory(1)
                    : null,
              ),
              const SizedBox(width: 4),
              toolBtn(
                icon: Icons.copy,
                tooltip: 'Copy Selected Objects (Ctrl+C)',
                onTap: hasSel ? () => _copySelectedObjects(cut: false) : null,
              ),
              toolBtn(
                icon: Icons.content_cut,
                tooltip: 'Cut Selected Objects (Ctrl+X)',
                onTap: hasSel ? () => _copySelectedObjects(cut: true) : null,
              ),
              toolBtn(
                icon: Icons.content_paste,
                tooltip: 'Paste Objects (Ctrl+V)',
                onTap: (_clipboardPayload != null &&
                        !_clipboardPayload!.isEmpty)
                    ? _pasteClipboardObjects
                    : null,
              ),
              toolBtn(
                icon: Icons.control_point_duplicate,
                tooltip: 'Duplicate Selected (Ctrl+D)',
                onTap: hasSel ? _duplicateSelectedField : null,
              ),
              const SizedBox(width: 4),
              toolBtn(
                icon: Icons.group_work_outlined,
                tooltip: 'Group Selected Objects (Ctrl+G)',
                onTap: multiCount >= 2 ? _groupSelectedObjects : null,
              ),
              toolBtn(
                icon: Icons.workspaces_outline,
                tooltip: 'Ungroup Selected Objects (Ctrl+Shift+G)',
                onTap: hasSel ? _ungroupSelectedObjects : null,
              ),
              toolBtn(
                icon: Icons.lock_outline,
                tooltip: 'Lock / Unlock Selected Objects (Ctrl+L)',
                onTap: hasSel ? _toggleLockSelectedObjects : null,
              ),
              toolBtn(
                icon: Icons.flip_to_front,
                tooltip: 'Bring Selected Forward',
                onTap: hasSel ? () => _changeSelectedLayersOrder(1) : null,
              ),
              toolBtn(
                icon: Icons.flip_to_back,
                tooltip: 'Send Selected Backward',
                onTap: hasSel ? () => _changeSelectedLayersOrder(-1) : null,
              ),
              toolBtn(
                icon: Icons.delete_outline,
                tooltip: 'Delete Selected Objects (Delete)',
                color: Colors.red,
                onTap: hasSel ? () => _deleteSelectedItem() : null,
              ),
            ],
          ),

          // Alignment, Distribution & Same Width/Height
          Wrap(
            spacing: 4,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _buildAlignBtn(
                  context, '⇤ L', 'Align Left (L)', () => _corelAlign('L')),
              _buildAlignBtn(context, '࿇ C', 'Align Horizontal Center (Ctrl+C)',
                  () => _corelAlign('C')),
              _buildAlignBtn(
                  context, '⇥ R', 'Align Right (R)', () => _corelAlign('R')),
              _buildAlignBtn(
                  context, '⤒ T', 'Align Top (T)', () => _corelAlign('T')),
              _buildAlignBtn(context, '࿇ E', 'Align Vertical Center (Ctrl+E)',
                  () => _corelAlign('E')),
              _buildAlignBtn(
                  context, '⤓ B', 'Align Bottom (B)', () => _corelAlign('B')),
              _buildAlignBtn(context, '⊕ P', 'Center on Card (P)',
                  () => _corelAlign('P')),
              _buildAlignBtn(
                  context,
                  '↔ Dist H',
                  'Distribute Horizontally',
                  _distributeHorizontally),
              _buildAlignBtn(
                  context,
                  '↕ Dist V',
                  'Distribute Vertically (Ctrl+Shift+E)',
                  _distributeVertically),
              _buildAlignBtn(
                  context,
                  '=W',
                  'Make Same Width (Multi-select)',
                  () => _corelAlign('SAME_W')),
              _buildAlignBtn(
                  context,
                  '=H',
                  'Make Same Height (Multi-select)',
                  () => _corelAlign('SAME_H')),
            ],
          ),

          // Grid, Rulers, Guides, Snap & Zoom Controls
          Wrap(
            spacing: 4,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              toolBtn(
                icon: Icons.grid_on,
                tooltip: 'Toggle 5mm Editor Grid (Never shown in Print)',
                active: _showGrid,
                onTap: () {
                  _rebuild(() => _showGrid = !_showGrid);
                  _saveVisualPreferences();
                },
              ),
              toolBtn(
                icon: Icons.straighten,
                tooltip: 'Toggle Edge Rulers (Editor only)',
                active: _showRulers,
                onTap: () {
                  _rebuild(() => _showRulers = !_showRulers);
                  _saveVisualPreferences();
                },
              ),
              toolBtn(
                icon: Icons.crop_free,
                tooltip: 'Toggle Safe Zone Margin Guides',
                active: _showSafeZone,
                onTap: () {
                  _rebuild(() => _showSafeZone = !_showSafeZone);
                  _saveVisualPreferences();
                },
              ),
              toolBtn(
                icon: Icons.center_focus_strong_outlined,
                tooltip: 'Toggle Center & Alignment Snap Guides',
                active: _snapEnabled,
                onTap: () {
                  _rebuild(() => _snapEnabled = !_snapEnabled);
                  _saveVisualPreferences();
                },
              ),
              const SizedBox(width: 4),
              _buildAlignBtn(
                context,
                'Fit Card',
                'Reset Zoom to Fit Card (85%)',
                () {
                  _rebuild(() => _zoom = 0.85);
                  _saveVisualPreferences();
                },
              ),
              _buildAlignBtn(
                context,
                '100%',
                'Set Zoom to 100%',
                () {
                  _rebuild(() => _zoom = 1.0);
                  _saveVisualPreferences();
                },
              ),
              toolBtn(
                icon: Icons.zoom_out,
                tooltip: 'Zoom Out (-10%)',
                onTap: () {
                  _rebuild(() => _zoom = (_zoom - 0.1).clamp(0.35, 1.6));
                  _saveVisualPreferences();
                },
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(5),
                  border: Border.all(color: Theme.of(context).dividerColor),
                ),
                child: Text(
                  '$zoomPct%',
                  style: const TextStyle(
                      fontSize: 11, fontWeight: FontWeight.w700),
                ),
              ),
              toolBtn(
                icon: Icons.zoom_in,
                tooltip: 'Zoom In (+10%)',
                onTap: () {
                  _rebuild(() => _zoom = (_zoom + 0.1).clamp(0.35, 1.6));
                  _saveVisualPreferences();
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildExportProgressBanner(BuildContext context) {
    final total = math.max(1, _exportTotalCount);
    final done = _exportProcessedCount.clamp(0, total).toInt();
    final rem = math.max(0, total - done);
    final pct = (done / total).clamp(0.0, 1.0);

    return Container(
      color: const Color(0xFF0F766E),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Row(
        children: [
          const SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(
              strokeWidth: 2.2,
              color: Colors.white,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Exporting ID Cards: $done processed • $rem remaining (${(pct * 100).round()}%)',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 3),
                LinearProgressIndicator(
                  value: pct,
                  backgroundColor: Colors.white24,
                  color: Colors.amberAccent,
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          TextButton.icon(
            style: TextButton.styleFrom(
              foregroundColor: Colors.white,
              backgroundColor: Colors.red.shade700,
            ),
            onPressed: () {
              _rebuild(() {
                _cancelExportRequested = true;
                _statusMessage = 'Cancelling export...';
              });
            },
            icon: const Icon(Icons.cancel_outlined, size: 15),
            label: const Text('Cancel'),
          ),
        ],
      ),
    );
  }

  Widget _buildMainStage(BuildContext context, {bool shrinkWrap = false}) {
    final overlaps = _auditOverlappingFields(_curLayout);
    final curRow = _rows.isNotEmpty
        ? _rows[_curRowIdx.clamp(0, _rows.length - 1).toInt()]
        : <String>[];
    final sheetGeom = _computeSheetGeometry();
    final navIndices = _previewNavigableRowIndices();
    final curNavPos = navIndices.indexOf(_curRowIdx);
    Offset? lastDoubleTapLocal;

    final children = <Widget>[
      // 1. CARD EDITOR BOX
      Card(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: Theme.of(context).dividerColor),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Editor Top Bar
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerLow,
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(12)),
              ),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                alignment: WrapAlignment.spaceBetween,
                children: [
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      const Text('Card Editor',
                          style: TextStyle(fontWeight: FontWeight.w700)),
                      DropdownButton<int>(
                        value: _curLayoutIdx,
                        isDense: true,
                        underline: const SizedBox(),
                        items: List.generate(
                          4,
                          (i) => DropdownMenuItem(
                            value: i,
                            child: Text('Layout Set ${i + 1}',
                                style: const TextStyle(fontSize: 12)),
                          ),
                        ),
                        onChanged: (v) {
                          if (v != null) _rebuild(() => _curLayoutIdx = v);
                        },
                      ),
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        tooltip: 'Previous Student (Up Arrow)',
                        onPressed: curNavPos > 0
                            ? () => _stepPreviewRecord(-1)
                            : null,
                        icon: const Icon(Icons.chevron_left, size: 18),
                      ),
                      DropdownButton<int>(
                        value: _curRowIdx
                            .clamp(0, math.max(0, _rows.length - 1))
                            .toInt(),
                        isDense: true,
                        underline: const SizedBox(),
                        items: List.generate(
                          _rows.length,
                          (i) => DropdownMenuItem(
                            value: i,
                            child: Text(
                              '${_selectedStudentIndices.contains(i) ? "☑ " : ""}#${i + 1}: ${_rows[i].length > 2 && _rows[i][2].trim().isNotEmpty ? _rows[i][2] : "Card ${i + 1}"}',
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 12),
                            ),
                          ),
                        ),
                        onChanged: (v) {
                          if (v != null) {
                            _rebuild(() {
                              _curRowIdx = v;
                              _syncControllersToSelection();
                            });
                          }
                        },
                      ),
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        tooltip: 'Next Student (Down Arrow)',
                        onPressed:
                            curNavPos >= 0 && curNavPos < navIndices.length - 1
                                ? () => _stepPreviewRecord(1)
                                : null,
                        icon: const Icon(Icons.chevron_right, size: 18),
                      ),
                      ActionChip(
                        avatar: const Icon(Icons.playlist_add_check, size: 14),
                        tooltip: 'Insert checked Student Database headers',
                        label: const Text('Insert Headers',
                            style: TextStyle(fontSize: 11)),
                        onPressed: () => _insertCheckedDatabaseHeadersOnCard(
                            replaceExisting: false),
                      ),
                      ActionChip(
                        avatar:
                            const Icon(Icons.add_comment_outlined, size: 14),
                        tooltip:
                            'Double-click on card or tap here to insert text/data',
                        label: const Text('Insert Text',
                            style: TextStyle(fontSize: 11)),
                        onPressed: () => _showDirectTextOrFieldDialog(),
                      ),
                      ActionChip(
                        avatar: const Icon(Icons.straighten, size: 14),
                        tooltip: 'Jump to student with the longest text',
                        label: const Text('Longest Name',
                            style: TextStyle(fontSize: 11)),
                        onPressed: _jumpToLongestRow,
                      ),
                    ],
                  ),
                  Wrap(
                    spacing: 6,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      GestureDetector(
                        onTap: () {
                          _rebuild(() {
                            _resolveLayoutCollisions(_curLayout,
                                forceStack: true);
                          });
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: overlaps.isEmpty
                                ? const Color(0xFFDCFCE7)
                                : const Color(0xFFFEF3C7),
                            borderRadius: BorderRadius.circular(99),
                          ),
                          child: Text(
                            overlaps.isEmpty
                                ? '✓ Clean Layout'
                                : '⚠ ${overlaps.length} Overlap(s) — Fix',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: overlaps.isEmpty
                                  ? const Color(0xFF15803D)
                                  : const Color(0xFFD97706),
                            ),
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(6),
                          border:
                              Border.all(color: Theme.of(context).dividerColor),
                        ),
                        child: Text(
                          '${(_cw / 10).toStringAsFixed(1)} × ${(_ch / 10).toStringAsFixed(1)} mm',
                          style: const TextStyle(
                              fontSize: 11, fontWeight: FontWeight.w700),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // Interactive Card Canvas (Scroll-locked during pointer drag)
            Focus(
              focusNode: _canvasFocusNode,
              autofocus: true,
              onKeyEvent: _handleCanvasKeyEvent,
              // Clicking empty canvas clears the selection; a click that
              // started on an object keeps it selected until another click.
              child: Listener(
                behavior: HitTestBehavior.translucent,
                onPointerDown: (ev) {
                  _bgPointerDown = ev.pointer;
                  _bgPointerDownPos = ev.position;
                },
                onPointerUp: (ev) {
                  final startedOnObject = _lastObjectPointer == ev.pointer;
                  final sameClick = _bgPointerDown == ev.pointer &&
                      _bgPointerDownPos != null &&
                      (ev.position - _bgPointerDownPos!).distance < 6;
                  _bgPointerDown = null;
                  if (startedOnObject || !sameClick) return;
                  _canvasFocusNode.requestFocus();
                  if (_selKey == null && _multiSel.isEmpty) return;
                  _rebuild(() {
                    _selKey = null;
                    _multiSel = [];
                  });
                },
                child: Container(
                  color: const Color(0xFFCBD5E1),
                  padding: const EdgeInsets.all(22),
                  alignment: Alignment.center,
                  child: SingleChildScrollView(
                    physics: _isCanvasPointerDown
                        ? const NeverScrollableScrollPhysics()
                        : const ClampingScrollPhysics(),
                    scrollDirection: Axis.horizontal,
                    child: Transform.scale(
                      scale: _zoom,
                      alignment: Alignment.center,
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onDoubleTapDown: (details) {
                          lastDoubleTapLocal = details.localPosition;
                        },
                        onDoubleTap: () {
                          final pos = lastDoubleTapLocal;
                          _showDirectTextOrFieldDialog(
                            clickX: pos?.dx,
                            clickY: pos?.dy,
                          );
                        },
                        child: RepaintBoundary(
                          key: _singleCardBoundaryKey,
                          child: _buildCardWidget(
                            row: curRow,
                            layout: _curLayout,
                            isEditor: !_isCapturingCleanSingleCard,
                            overlaps: overlaps,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),

            // Status / Inspector Bar
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerLow,
                borderRadius:
                    const BorderRadius.vertical(bottom: Radius.circular(12)),
              ),
              child: Text(
                _statusMessage,
                style: const TextStyle(
                    fontSize: 11.5, fontWeight: FontWeight.w500),
              ),
            ),
          ],
        ),
      ),

      const SizedBox(height: 14),

      // 2. MULTI-CARD SHEET IMPOSITION PREVIEW (Grid never shown here)
      Card(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: Theme.of(context).dividerColor),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerLow,
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(12)),
              ),
              child: Wrap(
                spacing: 8,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                alignment: WrapAlignment.spaceBetween,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(child: const Text('Sheet Imposition Preview (Print View)',
                          style: TextStyle(fontWeight: FontWeight.w700))),
                      const SizedBox(width: 10),
                      Text(
                        'Sheet ${_sheetPageIdx + 1} of ${sheetGeom.totalPages} • ${sheetGeom.perSheet} cards/sheet (${sheetGeom.cols}×${sheetGeom.rows}) • Scope: ${_printScope.label} (${_activeRangeRows().length} cards)',
                        style: const TextStyle(fontSize: 12),
                      ),
                    ],
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ActionChip(
                        visualDensity: VisualDensity.compact,
                        label: Text(
                          _printScope == PrintRecordScope.selectedOnly
                              ? 'Showing Selected (${_selectedStudentIndices.length})'
                              : 'Filter: Selected Only',
                          style: const TextStyle(fontSize: 11),
                        ),
                        onPressed: () {
                          _rebuild(() {
                            _printScope =
                                _printScope == PrintRecordScope.selectedOnly
                                    ? PrintRecordScope.all
                                    : PrintRecordScope.selectedOnly;
                            _sheetPageIdx = 0;
                          });
                        },
                      ),
                      const SizedBox(width: 6),
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        tooltip: 'Previous Sheet Page',
                        onPressed: _sheetPageIdx > 0
                            ? () => _rebuild(() => _sheetPageIdx--)
                            : null,
                        icon: const Icon(Icons.chevron_left, size: 18),
                      ),
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        tooltip: 'Next Sheet Page',
                        onPressed: _sheetPageIdx < sheetGeom.totalPages - 1
                            ? () => _rebuild(() => _sheetPageIdx++)
                            : null,
                        icon: const Icon(Icons.chevron_right, size: 18),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Container(
              color: const Color(0xFFCBD5E1),
              padding: const EdgeInsets.all(16),
              alignment: Alignment.center,
              child: SingleChildScrollView(
                physics: _isCanvasPointerDown
                    ? const NeverScrollableScrollPhysics()
                    : const ClampingScrollPhysics(),
                scrollDirection: Axis.horizontal,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: RepaintBoundary(
                    key: _sheetBoundaryKey,
                    child: _buildSheetPageWidget(sheetGeom, _sheetPageIdx),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    ];

    if (shrinkWrap) {
      return Column(children: children);
    }
    return ListView(
      physics: _isCanvasPointerDown
          ? const NeverScrollableScrollPhysics()
          : const ClampingScrollPhysics(),
      padding: const EdgeInsets.all(12),
      children: children,
    );
  }

  Widget _buildAlignBtn(
    BuildContext context,
    String label,
    String tooltip,
    VoidCallback onTap,
  ) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: () {
          _canvasFocusNode.requestFocus();
          onTap();
        },
        borderRadius: BorderRadius.circular(5),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3.5),
          decoration: BoxDecoration(
            border: Border.all(color: Theme.of(context).dividerColor),
            borderRadius: BorderRadius.circular(5),
          ),
          child: Text(label,
              style:
                  const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700)),
        ),
      ),
    );
  }

  Widget _buildCardWidget({
    required List<String> row,
    required CardLayoutSet layout,
    required bool isEditor,
    double scale = 1.0,
    Set<int> overlaps = const {},
  }) {
    final cardW = _cw * scale;
    final cardH = _ch * scale;
    final ptScale = AutoFitTypographyEngine.kPtToEditorUnits * scale;
    final activePrimaryItem = isEditor && _selKey != null
        ? _itemForKey(_selKey!, layout)
        : null;

    return Container(
      width: cardW,
      height: cardH,
      clipBehavior: Clip.hardEdge,
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: isEditor
            ? const [
                BoxShadow(
                  color: Colors.black26,
                  blurRadius: 20,
                  offset: Offset(0, 6),
                )
              ]
            : null,
      ),
      child: Stack(
        clipBehavior: Clip.hardEdge,
        children: [
          // 1. Built-in Blank/Styled or Cached Uploaded Template Background
          Positioned.fill(
            child: _cachedTemplateImage != null
                ? Image(
                    image: _cachedTemplateImage!,
                    fit: BoxFit.fill,
                    gaplessPlayback: true,
                  )
                : (_uploadedTemplateBytes != null
                    ? Image.memory(
                        _uploadedTemplateBytes!,
                        fit: BoxFit.fill,
                        gaplessPlayback: true,
                      )
                    : CustomPaint(
                        painter: CardTemplatePainter(
                          theme: _tplTheme,
                          headerTitle: _tplHeaderTitle,
                          accentColor: _tplAccentColor,
                        ),
                      )),
          ),

          // 2. Optional 5mm Grid & Edge Rulers ONLY in Editor (NEVER in print/sheet!)
          if (isEditor && (_showGrid || _showRulers))
            Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(
                  painter: CardGridAndRulerPainter(
                    scale: scale,
                    showGrid: _showGrid,
                    showRulers: _showRulers,
                  ),
                ),
              ),
            ),

          // 3. Safe Zone & Dynamic Object Alignment Guides in Editor
          if (isEditor && _showSafeZone)
            Positioned.fill(
              child: IgnorePointer(
                child: Padding(
                  padding: EdgeInsets.all(20 * scale),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: const Color(0x440D7480),
                        width: 1,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          if (isEditor && _snapEnabled && _snapX)
            Positioned(
              left: cardW / 2,
              top: 0,
              bottom: 0,
              child: IgnorePointer(
                child: Container(width: 1.4, color: const Color(0xFF0D9488)),
              ),
            ),
          if (isEditor && _snapEnabled && _snapY)
            Positioned(
              top: cardH / 2,
              left: 0,
              right: 0,
              child: IgnorePointer(
                child: Container(height: 1.4, color: const Color(0xFF0D9488)),
              ),
            ),
          // Active Object Edge Alignment Crosshairs when dragging/resizing
          if (isEditor && _isCanvasPointerDown && activePrimaryItem != null) ...[
            Positioned(
              left: activePrimaryItem.x * scale,
              top: 0,
              bottom: 0,
              child: IgnorePointer(
                child: Container(
                  width: 0.9,
                  color: const Color(0x99F59E0B),
                ),
              ),
            ),
            Positioned(
              top: activePrimaryItem.y * scale,
              left: 0,
              right: 0,
              child: IgnorePointer(
                child: Container(
                  height: 0.9,
                  color: const Color(0x99F59E0B),
                ),
              ),
            ),
          ],

          // 4. Portrait Photo Box (if visible)
          if (_showPhoto)
            _buildPhotoItemWidget(
              row: row,
              photo: layout.photo,
              isEditor: isEditor,
              scale: scale,
            ),

          // 5. Auto-Fit Text & Direct Text Fields
          for (int i = 0; i < layout.fields.length; i++)
            _buildFieldItemWidget(
              index: i,
              field: layout.fields[i],
              rawValue: (!layout.fields[i].isDirectText &&
                      layout.fields[i].col >= 0 &&
                      layout.fields[i].col < row.length)
                  ? row[layout.fields[i].col]
                  : '',
              isEditor: isEditor,
              scale: scale,
              ptScale: ptScale,
              hasOverlapWarning: overlaps.contains(i),
            ),

          // 6. Official Seal Overlay (if enabled)
          if (_showSeal)
            _buildSealItemWidget(
              seal: layout.seal,
              isEditor: isEditor,
              scale: scale,
            ),

          // 7. Principal Signature PNG Overlay (if enabled)
          if (_showSignature)
            _buildSignatureItemWidget(
              signature: layout.signature,
              isEditor: isEditor,
              scale: scale,
            ),

          // 8. Live Move / Resize Coordinate & Size Indicator Badge (Editor only, never in print)
          if (isEditor && activePrimaryItem != null)
            Positioned(
              left: (activePrimaryItem.x * scale)
                  .clamp(4.0, math.max(4.0, cardW - 185.0)),
              top: activePrimaryItem.y * scale >= 24.0
                  ? activePrimaryItem.y * scale - 22.0
                  : (activePrimaryItem.y + activePrimaryItem.h) * scale + 4.0,
              child: IgnorePointer(
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xE60F172A),
                    borderRadius: BorderRadius.circular(4),
                    border:
                        Border.all(color: const Color(0xFFF59E0B), width: 0.8),
                  ),
                  child: Text(
                    'X:${(activePrimaryItem.x / 10).toStringAsFixed(1)} Y:${(activePrimaryItem.y / 10).toStringAsFixed(1)} mm • ${(activePrimaryItem.w / 10).toStringAsFixed(1)}×${(activePrimaryItem.h / 10).toStringAsFixed(1)} mm',
                    style: const TextStyle(
                      color: Color(0xFFFDE68A),
                      fontSize: 9.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ),

          // 9. Cut Guides (on sheet preview / export only)
          if (!isEditor && _drawCutGuides)
            Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(
                  painter: CutGuidePainter(style: _guideStyle),
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// Zero-slop 1:1 pointer interaction wrapper for Fields, Photo, Seal & Principal Signature.
  Widget _buildFieldItemWidget({
    required int index,
    required CardFieldItem field,
    required String rawValue,
    required bool isEditor,
    required double scale,
    required double ptScale,
    required bool hasOverlapWarning,
  }) {
    final key = SelectedItemKey(SelectedItemType.field, index);
    final isPrimarySel = isEditor && _selKey == key;
    final isMultiSel = isEditor && _multiSel.contains(key);
    final pad = isEditor ? _IdCardStudioViewState.kHandleHitPad : 0.0;

    // In Editor mode, if the cell value is blank on the current row, show `[Header Name]`
    // so newly inserted fields are always clearly visible and easy to drag/resize!
    String effectiveRawValue = rawValue;
    if (!field.isDirectText && effectiveRawValue.trim().isEmpty) {
      final colName = (field.col >= 0 && field.col < _headers.length)
          ? _headers[field.col]
          : 'Field ${index + 1}';
      if (isEditor || _dbStudentsAll.isEmpty) {
        effectiveRawValue = '[$colName]';
      }
    }

    final fitRes = AutoFitTypographyEngine.computeFittedFontSize(
      field,
      effectiveRawValue,
      scale: scale,
      ptScale: ptScale,
    );

    Alignment boxAlign;
    switch (field.valign) {
      case VerticalTextAlign.top:
        boxAlign = field.align == TextAlign.center
            ? Alignment.topCenter
            : (field.align == TextAlign.right
                ? Alignment.topRight
                : Alignment.topLeft);
        break;
      case VerticalTextAlign.bottom:
        boxAlign = field.align == TextAlign.center
            ? Alignment.bottomCenter
            : (field.align == TextAlign.right
                ? Alignment.bottomRight
                : Alignment.bottomLeft);
        break;
      case VerticalTextAlign.middle:
        boxAlign = field.align == TextAlign.center
            ? Alignment.center
            : (field.align == TextAlign.right
                ? Alignment.centerRight
                : Alignment.centerLeft);
        break;
    }

    final boxW = field.w * scale;
    final boxH = field.h * scale;

    return Positioned(
      left: field.x * scale - pad,
      top: field.y * scale - pad,
      width: boxW + pad * 2,
      height: boxH + pad * 2,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left: pad,
            top: pad,
            width: boxW,
            height: boxH,
            child: Listener(
              behavior: HitTestBehavior.opaque,
              onPointerDown: isEditor
                  ? (ev) {
                      _lastObjectPointer = ev.pointer;
                      _canvasFocusNode.requestFocus();
                      final now = DateTime.now();
                      final isDouble = _lastTapKey == key &&
                          _lastTapTime != null &&
                          now.difference(_lastTapTime!).inMilliseconds < 320;
                      _lastTapKey = key;
                      _lastTapTime = now;
                      if (isDouble) {
                        _rebuild(() => _isCanvasPointerDown = false);
                        _showDirectTextOrFieldDialog(
                          existingField: field,
                          existingIndex: index,
                        );
                        return;
                      }
                      _rebuild(() {
                        _isCanvasPointerDown = true;
                      });
                      if (!_multiSel.contains(key) ||
                          _isShiftPressed() ||
                          _isCtrlPressed()) {
                        _selectObjectOnCanvas(key);
                      }
                    }
                  : null,
              onPointerMove: isEditor
                  ? (ev) {
                      if (!_isCanvasPointerDown) return;
                      if (ev.delta.dx == 0 && ev.delta.dy == 0) return;
                      _rebuild(() {
                        _moveSelectedItemsBy(
                          ev.delta.dx / (_zoom * scale),
                          ev.delta.dy / (_zoom * scale),
                          enableSnap: true,
                        );
                      });
                    }
                  : null,
              onPointerUp: isEditor
                  ? (_) {
                      if (_isCanvasPointerDown) {
                        _rebuild(() {
                          _isCanvasPointerDown = false;
                          _snapX = false;
                          _snapY = false;
                        });
                        _pushHistory();
                      }
                    }
                  : null,
              onPointerCancel: isEditor
                  ? (_) {
                      _rebuild(() {
                        _isCanvasPointerDown = false;
                        _snapX = false;
                        _snapY = false;
                      });
                    }
                  : null,
              child: MouseRegion(
                cursor: isEditor
                    ? SystemMouseCursors.move
                    : MouseCursor.defer,
                child: Container(
                  width: boxW,
                  height: boxH,
                  padding: EdgeInsets.symmetric(
                      horizontal: 4 * scale, vertical: 2 * scale),
                  alignment: boxAlign,
                  decoration: isEditor
                      ? BoxDecoration(
                          color: hasOverlapWarning
                              ? const Color(0x1ADC2626)
                              : (isPrimarySel
                                  ? const Color(0x18F59E0B)
                                  : (isMultiSel
                                      ? const Color(0x180284C7)
                                      : const Color(0x082563EB))),
                          border: Border.all(
                            color: hasOverlapWarning
                                ? const Color(0xFFDC2626)
                                : (isPrimarySel
                                    ? const Color(0xFFF59E0B)
                                    : (isMultiSel
                                        ? const Color(0xFF0284C7)
                                        : const Color(0x662563EB))),
                            width: isPrimarySel || isMultiSel ? 1.6 : 0.9,
                          ),
                        )
                      : null,
                  child: RichText(
                    text: fitRes.span,
                    textAlign: field.align,
                    maxLines: field.textMode == TextFitMode.nowrap ? 1 : null,
                    overflow: TextOverflow.clip,
                  ),
                ),
              ),
            ),
          ),
          if (isEditor && (field.locked || field.groupId != null))
            Positioned(
              right: pad + 2,
              top: pad - 12,
              child: IgnorePointer(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (field.groupId != null)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 3, vertical: 0.5),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0284C7),
                          borderRadius: BorderRadius.circular(3),
                        ),
                        child: Text(
                          'G${field.groupId}',
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 8,
                              fontWeight: FontWeight.w700),
                        ),
                      ),
                    if (field.locked)
                      const Icon(Icons.lock,
                          size: 11, color: Color(0xFFD97706)),
                  ],
                ),
              ),
            ),
          if ((isPrimarySel || isMultiSel) && !field.locked)
            ..._buildEightWayResizeHandles(field, scale, pad),
        ],
      ),
    );
  }

  Widget _buildPhotoItemWidget({
    required List<String> row,
    required CardPhotoBox photo,
    required bool isEditor,
    required double scale,
  }) {
    const key = SelectedItemKey(SelectedItemType.photo, 0);
    final isSel = isEditor && (_selKey == key || _multiSel.contains(key));
    final cachedProvider = _resolveCachedPhotoProvider(row);
    final pad = isEditor ? _IdCardStudioViewState.kHandleHitPad : 0.0;

    final initials = row.length > 2 && row[2].trim().isNotEmpty
        ? row[2]
            .trim()
            .split(RegExp(r'\s+'))
            .take(2)
            .map((s) => s.characters.first.toUpperCase())
            .join()
        : '';

    final brightnessFactor = (photo.brightness / 100.0).clamp(0.5, 1.5);
    final boxW = photo.w * scale;
    final boxH = photo.h * scale;
    final clampedRadius =
        (photo.borderRadius * scale).clamp(0.0, math.min(boxW, boxH) / 2.0);

    return Positioned(
      left: photo.x * scale - pad,
      top: photo.y * scale - pad,
      width: boxW + pad * 2,
      height: boxH + pad * 2,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left: pad,
            top: pad,
            width: boxW,
            height: boxH,
            child: Listener(
              behavior: HitTestBehavior.opaque,
              onPointerDown: isEditor
                  ? (ev) {
                      _lastObjectPointer = ev.pointer;
                      _canvasFocusNode.requestFocus();
                      final now = DateTime.now();
                      final isDouble = _lastTapKey == key &&
                          _lastTapTime != null &&
                          now.difference(_lastTapTime!).inMilliseconds < 320;
                      _lastTapKey = key;
                      _lastTapTime = now;
                      if (isDouble) {
                        _rebuild(() => _isCanvasPointerDown = false);
                        _pickStudentPhotos(forCurrentRecordOnly: true);
                        return;
                      }
                      _rebuild(() => _isCanvasPointerDown = true);
                      if (!_multiSel.contains(key)) {
                        _selectObjectOnCanvas(key);
                      }
                    }
                  : null,
              onPointerMove: isEditor
                  ? (ev) {
                      if (!_isCanvasPointerDown) return;
                      if (ev.delta.dx == 0 && ev.delta.dy == 0) return;
                      _rebuild(() {
                        _moveSelectedItemsBy(
                          ev.delta.dx / (_zoom * scale),
                          ev.delta.dy / (_zoom * scale),
                          enableSnap: true,
                        );
                      });
                    }
                  : null,
              onPointerUp: isEditor
                  ? (_) {
                      if (_isCanvasPointerDown) {
                        _rebuild(() {
                          _isCanvasPointerDown = false;
                          _snapX = false;
                          _snapY = false;
                        });
                        _pushHistory();
                      }
                    }
                  : null,
              onPointerCancel: isEditor
                  ? (_) {
                      _rebuild(() {
                        _isCanvasPointerDown = false;
                        _snapX = false;
                        _snapY = false;
                      });
                    }
                  : null,
              child: MouseRegion(
                cursor:
                    isEditor ? SystemMouseCursors.move : MouseCursor.defer,
                child: CustomPaint(
                  foregroundPainter: UniformPhotoFramePainter(
                    cornerRadius: clampedRadius,
                    borderWidth: photo.borderWidth * scale,
                    borderColor: photo.borderColor,
                    isSelected: isSel,
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(clampedRadius),
                    child: SizedBox(
                      width: boxW,
                      height: boxH,
                      child: ColorFiltered(
                        colorFilter: ColorFilter.matrix(<double>[
                          brightnessFactor, 0, 0, 0, 0,
                          0, brightnessFactor, 0, 0, 0,
                          0, 0, brightnessFactor, 0, 0,
                          0, 0, 0, 1, 0,
                        ]),
                        child: cachedProvider != null
                            ? Image(
                                image: cachedProvider,
                                fit: photo.fit,
                                gaplessPlayback: true,
                              )
                            : CustomPaint(
                                painter: DemoAvatarPainter(initials: initials),
                              ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          if (isSel && !photo.locked)
            ..._buildEightWayResizeHandles(photo, scale, pad),
        ],
      ),
    );
  }

  Widget _buildSealItemWidget({
    required CardSealBox seal,
    required bool isEditor,
    required double scale,
  }) {
    const key = SelectedItemKey(SelectedItemType.seal, 0);
    final isSel = isEditor && (_selKey == key || _multiSel.contains(key));
    final pad = isEditor ? _IdCardStudioViewState.kHandleHitPad : 0.0;
    final boxW = seal.w * scale;
    final boxH = seal.h * scale;

    return Positioned(
      left: seal.x * scale - pad,
      top: seal.y * scale - pad,
      width: boxW + pad * 2,
      height: boxH + pad * 2,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left: pad,
            top: pad,
            width: boxW,
            height: boxH,
            child: Listener(
              behavior: HitTestBehavior.opaque,
              onPointerDown: isEditor
                  ? (ev) {
                      _lastObjectPointer = ev.pointer;
                      _canvasFocusNode.requestFocus();
                      final now = DateTime.now();
                      final isDouble = _lastTapKey == key &&
                          _lastTapTime != null &&
                          now.difference(_lastTapTime!).inMilliseconds < 320;
                      _lastTapKey = key;
                      _lastTapTime = now;
                      if (isDouble) {
                        _rebuild(() => _isCanvasPointerDown = false);
                        _pickSealImage();
                        return;
                      }
                      _rebuild(() => _isCanvasPointerDown = true);
                      if (!_multiSel.contains(key)) {
                        _selectObjectOnCanvas(key);
                      }
                    }
                  : null,
              onPointerMove: isEditor
                  ? (ev) {
                      if (!_isCanvasPointerDown) return;
                      if (ev.delta.dx == 0 && ev.delta.dy == 0) return;
                      _rebuild(() {
                        _moveSelectedItemsBy(
                          ev.delta.dx / (_zoom * scale),
                          ev.delta.dy / (_zoom * scale),
                          enableSnap: true,
                        );
                      });
                    }
                  : null,
              onPointerUp: isEditor
                  ? (_) {
                      if (_isCanvasPointerDown) {
                        _rebuild(() {
                          _isCanvasPointerDown = false;
                          _snapX = false;
                          _snapY = false;
                        });
                        _pushHistory();
                      }
                    }
                  : null,
              onPointerCancel: isEditor
                  ? (_) {
                      _rebuild(() {
                        _isCanvasPointerDown = false;
                        _snapX = false;
                        _snapY = false;
                      });
                    }
                  : null,
              child: MouseRegion(
                cursor:
                    isEditor ? SystemMouseCursors.move : MouseCursor.defer,
                child: Container(
                  width: boxW,
                  height: boxH,
                  decoration: isEditor
                      ? BoxDecoration(
                          border: Border.all(
                            color: isSel
                                ? const Color(0xFFF59E0B)
                                : const Color(0x880D7480),
                            width: isSel ? 1.5 : 1.0,
                          ),
                        )
                      : null,
                  child: _cachedSealImage != null
                      ? Image(
                          image: _cachedSealImage!,
                          fit: BoxFit.contain,
                          gaplessPlayback: true,
                        )
                      : (_uploadedSealBytes != null
                          ? Image.memory(
                              _uploadedSealBytes!,
                              fit: BoxFit.contain,
                              gaplessPlayback: true,
                            )
                          : const CustomPaint(painter: DemoSealPainter())),
                ),
              ),
            ),
          ),
          if (isSel && !seal.locked)
            ..._buildEightWayResizeHandles(seal, scale, pad),
        ],
      ),
    );
  }

  Widget _buildSignatureItemWidget({
    required CardSignatureBox signature,
    required bool isEditor,
    required double scale,
  }) {
    const key = SelectedItemKey(SelectedItemType.signature, 0);
    final isSel = isEditor && (_selKey == key || _multiSel.contains(key));
    final pad = isEditor ? _IdCardStudioViewState.kHandleHitPad : 0.0;
    final boxW = signature.w * scale;
    final boxH = signature.h * scale;

    return Positioned(
      left: signature.x * scale - pad,
      top: signature.y * scale - pad,
      width: boxW + pad * 2,
      height: boxH + pad * 2,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left: pad,
            top: pad,
            width: boxW,
            height: boxH,
            child: Listener(
              behavior: HitTestBehavior.opaque,
              onPointerDown: isEditor
                  ? (ev) {
                      _lastObjectPointer = ev.pointer;
                      _canvasFocusNode.requestFocus();
                      final now = DateTime.now();
                      final isDouble = _lastTapKey == key &&
                          _lastTapTime != null &&
                          now.difference(_lastTapTime!).inMilliseconds < 320;
                      _lastTapKey = key;
                      _lastTapTime = now;
                      if (isDouble) {
                        _rebuild(() => _isCanvasPointerDown = false);
                        _pickPrincipalSignatureImage();
                        return;
                      }
                      _rebuild(() => _isCanvasPointerDown = true);
                      if (!_multiSel.contains(key)) {
                        _selectObjectOnCanvas(key);
                      }
                    }
                  : null,
              onPointerMove: isEditor
                  ? (ev) {
                      if (!_isCanvasPointerDown) return;
                      if (ev.delta.dx == 0 && ev.delta.dy == 0) return;
                      _rebuild(() {
                        _moveSelectedItemsBy(
                          ev.delta.dx / (_zoom * scale),
                          ev.delta.dy / (_zoom * scale),
                          enableSnap: true,
                        );
                      });
                    }
                  : null,
              onPointerUp: isEditor
                  ? (_) {
                      if (_isCanvasPointerDown) {
                        _rebuild(() {
                          _isCanvasPointerDown = false;
                          _snapX = false;
                          _snapY = false;
                        });
                        _pushHistory();
                      }
                    }
                  : null,
              onPointerCancel: isEditor
                  ? (_) {
                      _rebuild(() {
                        _isCanvasPointerDown = false;
                        _snapX = false;
                        _snapY = false;
                      });
                    }
                  : null,
              child: MouseRegion(
                cursor:
                    isEditor ? SystemMouseCursors.move : MouseCursor.defer,
                child: Container(
                  width: boxW,
                  height: boxH,
                  decoration: isEditor
                      ? BoxDecoration(
                          border: Border.all(
                            color: isSel
                                ? const Color(0xFFF59E0B)
                                : const Color(0x886B21A8),
                            width: isSel ? 1.5 : 1.0,
                          ),
                        )
                      : null,
                  child: _cachedSignatureImage != null
                      ? Image(
                          image: _cachedSignatureImage!,
                          fit: BoxFit.contain,
                          gaplessPlayback: true,
                        )
                      : (_uploadedSignatureBytes != null
                          ? Image.memory(
                              _uploadedSignatureBytes!,
                              fit: BoxFit.contain,
                              gaplessPlayback: true,
                            )
                          : const CustomPaint(
                              painter: DemoSignaturePainter())),
                ),
              ),
            ),
          ),
          if (isSel && !signature.locked)
            ..._buildEightWayResizeHandles(signature, scale, pad),
        ],
      ),
    );
  }

  /// Builds 8-direction resize handles (NW, NE, SW, SE, N, S, E, W) inside the padded
  /// `Positioned` hit area using zero-slop `Listener` so corner dragging never gets stuck!
  List<Widget> _buildEightWayResizeHandles(
    CardBoxItem item,
    double scale,
    double pad,
  ) {
    final w = item.w * scale;
    final h = item.h * scale;
    const hitSize = 18.0;
    const visSize = 9.0;

    Widget handle({
      required double cx,
      required double cy,
      required MouseCursor cursor,
      required void Function(double dx, double dy) onDrag,
    }) {
      return Positioned(
        left: pad + cx - hitSize / 2,
        top: pad + cy - hitSize / 2,
        width: hitSize,
        height: hitSize,
        child: Listener(
          behavior: HitTestBehavior.opaque,
          onPointerDown: (ev) {
            _lastObjectPointer = ev.pointer;
            _canvasFocusNode.requestFocus();
            _rebuild(() => _isCanvasPointerDown = true);
          },
          onPointerMove: (ev) {
            if (!_isCanvasPointerDown) return;
            if (ev.delta.dx == 0 && ev.delta.dy == 0) return;
            _rebuild(() {
              onDrag(
                ev.delta.dx / (_zoom * scale),
                ev.delta.dy / (_zoom * scale),
              );
              AutoFitTypographyEngine.clearCache();
            });
          },
          onPointerUp: (_) {
            if (_isCanvasPointerDown) {
              _rebuild(() => _isCanvasPointerDown = false);
              _pushHistory();
            }
          },
          onPointerCancel: (_) {
            _rebuild(() => _isCanvasPointerDown = false);
          },
          child: MouseRegion(
            cursor: cursor,
            child: Center(
              child: Container(
                width: visSize,
                height: visSize,
                decoration: BoxDecoration(
                  color: Colors.white,
                  border:
                      Border.all(color: const Color(0xFFD97706), width: 1.8),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
          ),
        ),
      );
    }

    return [
      // SE
      handle(
        cx: w,
        cy: h,
        cursor: SystemMouseCursors.resizeDownRight,
        onDrag: (dx, dy) => _resizeSelectedItemsBy(
          primary: item,
          dx: 0,
          dy: 0,
          dw: dx,
          dh: dy,
        ),
      ),
      // NW
      handle(
        cx: 0,
        cy: 0,
        cursor: SystemMouseCursors.resizeUpLeft,
        onDrag: (dx, dy) => _resizeSelectedItemsBy(
          primary: item,
          dx: dx,
          dy: dy,
          dw: -dx,
          dh: -dy,
        ),
      ),
      // NE
      handle(
        cx: w,
        cy: 0,
        cursor: SystemMouseCursors.resizeUpRight,
        onDrag: (dx, dy) => _resizeSelectedItemsBy(
          primary: item,
          dx: 0,
          dy: dy,
          dw: dx,
          dh: -dy,
        ),
      ),
      // SW
      handle(
        cx: 0,
        cy: h,
        cursor: SystemMouseCursors.resizeDownLeft,
        onDrag: (dx, dy) => _resizeSelectedItemsBy(
          primary: item,
          dx: dx,
          dy: 0,
          dw: -dx,
          dh: dy,
        ),
      ),
      // E
      handle(
        cx: w,
        cy: h / 2,
        cursor: SystemMouseCursors.resizeLeftRight,
        onDrag: (dx, _) => _resizeSelectedItemsBy(
          primary: item,
          dx: 0,
          dy: 0,
          dw: dx,
          dh: 0,
        ),
      ),
      // W
      handle(
        cx: 0,
        cy: h / 2,
        cursor: SystemMouseCursors.resizeLeftRight,
        onDrag: (dx, _) => _resizeSelectedItemsBy(
          primary: item,
          dx: dx,
          dy: 0,
          dw: -dx,
          dh: 0,
        ),
      ),
      // S
      handle(
        cx: w / 2,
        cy: h,
        cursor: SystemMouseCursors.resizeUpDown,
        onDrag: (_, dy) => _resizeSelectedItemsBy(
          primary: item,
          dx: 0,
          dy: 0,
          dw: 0,
          dh: dy,
        ),
      ),
      // N
      handle(
        cx: w / 2,
        cy: 0,
        cursor: SystemMouseCursors.resizeUpDown,
        onDrag: (_, dy) => _resizeSelectedItemsBy(
          primary: item,
          dx: 0,
          dy: dy,
          dw: 0,
          dh: -dy,
        ),
      ),
    ];
  }

  Widget _buildSheetPageWidget(SheetGeometry g, int pageIndex) {
    final pageW = g.paperWmm * _IdCardStudioViewState.kMmToPx;
    final pageH = g.paperHmm * _IdCardStudioViewState.kMmToPx;
    final cardScale = (g.cardWmm * _IdCardStudioViewState.kMmToPx) / _cw;
    final rangeRows = _activeRangeRows();

    return Container(
      width: pageW,
      height: pageH,
      color: Colors.white,
      child: Stack(
        children: [
          for (int i = 0; i < g.perSheet; i++)
            if (pageIndex * g.perSheet + i < rangeRows.length)
              Positioned(
                left: (g.x0Mm + (i % g.cols) * (g.cardWmm + g.gapMm)) *
                    _IdCardStudioViewState.kMmToPx,
                top: (g.y0Mm + (i ~/ g.cols) * (g.cardHmm + g.gapMm)) *
                    _IdCardStudioViewState.kMmToPx,
                child: RepaintBoundary(
                  child: _buildCardWidget(
                    row: rangeRows[pageIndex * g.perSheet + i],
                    layout: _alternateSets
                        ? _layouts[(pageIndex * g.perSheet + i) % 4]
                        : _layouts[0],
                    isEditor: false,
                    scale: cardScale,
                  ),
                ),
              ),
        ],
      ),
    );
  }
}
