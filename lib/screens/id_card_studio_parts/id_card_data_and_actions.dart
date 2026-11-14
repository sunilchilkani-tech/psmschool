part of '../supabase_id_card_studio_screen.dart';

// ============================================================================
// STUDENT SELECTION, INSTANT FIELD INSERTION, FOLDER UPLOAD & SIGNATURE ACTIONS
// ============================================================================

extension _IdCardStudioActionsExt on _IdCardStudioViewState {
  void _scheduleWorkspaceAutoSave() {
    _workspaceSaveDebounceTimer?.cancel();
    _workspaceSaveDebounceTimer = Timer(const Duration(milliseconds: 450), () {
      if (mounted) {
        _saveWorkspaceToDeviceNow();
      }
    });
  }

  Future<void> _saveWorkspaceToDeviceNow() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final statePayload = <String, dynamic>{
        'version': 4,
        'cw': _cw,
        'ch': _ch,
        'tplTheme': _tplTheme.code,
        'tplHeaderTitle': _tplHeaderTitle,
        'tplAccentColor': _tplAccentColor.toARGB32(),
        'showPhoto': _showPhoto,
        'photoLockAspect': _photoLockAspect,
        'showSeal': _showSeal,
        'sealAspect': _sealAspect,
        'sealLockAspect': _sealLockAspect,
        'sealTolerance': _sealTolerance,
        'uploadedSealName': _uploadedSealName,
        'showSignature': _showSignature,
        'signatureAspect': _signatureAspect,
        'signatureLockAspect': _signatureLockAspect,
        'signatureTolerance': _signatureTolerance,
        'uploadedSignatureName': _uploadedSignatureName,
        'uploadedTemplateName': _uploadedTemplateName,
        'selectedClassId': _selectedClassId,
        'selectedDbHeaderKeys': _selectedDbHeaderKeys.toList(),
        'photoCol': _photoCol,
        'paperSize': _paperSize,
        'gapMm': _gapMm,
        'exportDpi': _exportDpi,
        'guideStyle': _guideStyle.code,
        'drawCutGuides': _drawCutGuides,
        'alternateSets': _alternateSets,
        'layouts': _layouts.map((l) => l.toJson()).toList(),
      };
      await prefs.setString(
        _IdCardStudioViewState._prefKeyWorkspaceState,
        jsonEncode(statePayload),
      );

      final imgPayload = <String, dynamic>{
        if (_uploadedTemplateBytes != null)
          'templateB64': base64Encode(_uploadedTemplateBytes!),
        if (_uploadedSealRawBytes != null)
          'sealRawB64': base64Encode(_uploadedSealRawBytes!),
        if (_uploadedSealBytes != null)
          'sealB64': base64Encode(_uploadedSealBytes!),
        if (_uploadedSignatureRawBytes != null)
          'sigRawB64': base64Encode(_uploadedSignatureRawBytes!),
        if (_uploadedSignatureBytes != null)
          'sigB64': base64Encode(_uploadedSignatureBytes!),
      };
      await prefs.setString(
        _IdCardStudioViewState._prefKeyWorkspaceImages,
        jsonEncode(imgPayload),
      );

      if (_uploadedPhotos.isNotEmpty) {
        final photoMap = <String, String>{};
        int count = 0;
        for (final entry in _uploadedPhotos.entries) {
          if (count >= 120) break;
          photoMap[entry.key] = base64Encode(entry.value);
          count++;
        }
        await prefs.setString(
          _IdCardStudioViewState._prefKeyWorkspacePhotos,
          jsonEncode(photoMap),
        );
      } else {
        await prefs.remove(_IdCardStudioViewState._prefKeyWorkspacePhotos);
      }
    } catch (_) {}
  }

  Future<void> _loadSavedStudioPreferences() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedTab = prefs.getInt(_IdCardStudioViewState._prefKeyLastTab);
      final savedZoom = prefs.getDouble(_IdCardStudioViewState._prefKeyZoom);
      final savedGrid = prefs.getBool(_IdCardStudioViewState._prefKeyShowGrid);
      final savedRulers =
          prefs.getBool(_IdCardStudioViewState._prefKeyShowRulers);
      final savedGuides =
          prefs.getBool(_IdCardStudioViewState._prefKeyShowGuides);
      final savedSnap =
          prefs.getBool(_IdCardStudioViewState._prefKeySnapEnabled);
      final savedFonts =
          prefs.getStringList(_IdCardStudioViewState._prefKeyRecentFonts);
      final savedWorkspaceStr =
          prefs.getString(_IdCardStudioViewState._prefKeyWorkspaceState);
      final savedImagesStr =
          prefs.getString(_IdCardStudioViewState._prefKeyWorkspaceImages);
      final savedPhotosStr =
          prefs.getString(_IdCardStudioViewState._prefKeyWorkspacePhotos);
      final savedPdfB64 =
          prefs.getString(_IdCardStudioViewState._prefKeyLastPdfB64);
      final savedPdfName =
          prefs.getString(_IdCardStudioViewState._prefKeyLastPdfName);
      final savedPrefixMode =
          prefs.getString(_IdCardStudioViewState._prefKeyDefaultPrefixMode);

      if (!mounted) return;
      _isRestoringWorkspace = true;
      _rebuild(() {
        if (savedTab != null &&
            savedTab >= 0 &&
            savedTab < _sideTabController.length) {
          _sideTabController.index = savedTab;
        }
        if (savedZoom != null) {
          _zoom = savedZoom.clamp(0.35, 1.6);
        }
        if (savedGrid != null) _showGrid = savedGrid;
        if (savedRulers != null) _showRulers = savedRulers;
        if (savedGuides != null) _showSafeZone = savedGuides;
        if (savedSnap != null) _snapEnabled = savedSnap;
        if (savedPrefixMode != null &&
            const {'none', 'label', 'header'}.contains(savedPrefixMode)) {
          _defaultPrefixMode = savedPrefixMode;
        }
        if (savedFonts != null && savedFonts.isNotEmpty) {
          _recentFonts = savedFonts;
        }
        if (savedPdfB64 != null && savedPdfB64.isNotEmpty) {
          try {
            _lastSavedPdfBytes = base64Decode(savedPdfB64);
            if (savedPdfName != null && savedPdfName.isNotEmpty) {
              _lastSavedPdfName = savedPdfName;
            }
          } catch (_) {}
        }
        if (savedWorkspaceStr != null && savedWorkspaceStr.isNotEmpty) {
          try {
            final map = jsonDecode(savedWorkspaceStr) as Map<String, dynamic>;
            _cw = (map['cw'] as num?)?.toDouble() ?? 840.0;
            _ch = (map['ch'] as num?)?.toDouble() ?? 540.0;
            _cardWmmCtrl.text =
                (_cw / 10.0).toStringAsFixed(1).replaceAll('.0', '');
            _cardHmmCtrl.text =
                (_ch / 10.0).toStringAsFixed(1).replaceAll('.0', '');
            _tplTheme =
                BuiltInTemplateTheme.fromCode(map['tplTheme'] as String?);
            _tplHeaderTitle = map['tplHeaderTitle'] as String? ?? '';
            _tplTitleCtrl.text = _tplHeaderTitle;
            if (map['tplAccentColor'] is num) {
              _tplAccentColor = Color((map['tplAccentColor'] as num).toInt());
            }
            _showPhoto = map['showPhoto'] as bool? ?? true;
            _photoLockAspect = map['photoLockAspect'] as bool? ?? false;
            _showSeal = map['showSeal'] as bool? ?? false;
            _sealAspect = (map['sealAspect'] as num?)?.toDouble() ?? 1.0;
            _sealLockAspect = map['sealLockAspect'] as bool? ?? false;
            _sealTolerance = (map['sealTolerance'] as num?)?.toInt() ?? 38;
            _uploadedSealName = map['uploadedSealName'] as String? ?? '';
            _showSignature = map['showSignature'] as bool? ?? false;
            _signatureAspect =
                (map['signatureAspect'] as num?)?.toDouble() ?? 2.4;
            _signatureLockAspect =
                map['signatureLockAspect'] as bool? ?? false;
            _signatureTolerance =
                (map['signatureTolerance'] as num?)?.toInt() ?? 38;
            _uploadedSignatureName =
                map['uploadedSignatureName'] as String? ?? '';
            _uploadedTemplateName =
                map['uploadedTemplateName'] as String? ?? '';
            if (map['selectedClassId'] is String &&
                (map['selectedClassId'] as String).isNotEmpty) {
              _selectedClassId = map['selectedClassId'] as String;
            }
            if (map['selectedDbHeaderKeys'] is List) {
              final keys = (map['selectedDbHeaderKeys'] as List)
                  .map((e) => e.toString())
                  .where((s) => s.isNotEmpty)
                  .toSet();
              if (keys.isNotEmpty) {
                _selectedDbHeaderKeys
                  ..clear()
                  ..addAll(keys);
              }
            }
            _photoCol = (map['photoCol'] as num?)?.toInt() ?? 1;
            _paperSize = map['paperSize'] as String? ?? '12x18';
            _gapMm = (map['gapMm'] as num?)?.toDouble() ?? 1.0;
            _exportDpi = (map['exportDpi'] as num?)?.toInt() ?? 200;
            _guideStyle = CutGuideStyle.fromCode(map['guideStyle'] as String?);
            _drawCutGuides = map['drawCutGuides'] as bool? ?? true;
            _alternateSets = false;
            final rawLayouts = map['layouts'] as List?;
            if (rawLayouts != null && rawLayouts.isNotEmpty) {
              _layouts = rawLayouts
                  .map((e) => CardLayoutSet.fromJson(
                      Map<String, dynamic>.from(e as Map)))
                  .toList();
              while (_layouts.length < 4) {
                _layouts.add(_layouts.first.copy());
              }
            }
          } catch (_) {}
        }
        if (savedImagesStr != null && savedImagesStr.isNotEmpty) {
          try {
            final imgMap = jsonDecode(savedImagesStr) as Map<String, dynamic>;
            if (imgMap['templateB64'] is String &&
                (imgMap['templateB64'] as String).isNotEmpty) {
              _uploadedTemplateBytes =
                  base64Decode(imgMap['templateB64'] as String);
              _cachedTemplateImage = MemoryImage(_uploadedTemplateBytes!);
            }
            if (imgMap['sealRawB64'] is String &&
                (imgMap['sealRawB64'] as String).isNotEmpty) {
              _uploadedSealRawBytes =
                  base64Decode(imgMap['sealRawB64'] as String);
            }
            if (imgMap['sealB64'] is String &&
                (imgMap['sealB64'] as String).isNotEmpty) {
              _uploadedSealBytes = base64Decode(imgMap['sealB64'] as String);
              _cachedSealImage = MemoryImage(_uploadedSealBytes!);
            }
            if (imgMap['sigRawB64'] is String &&
                (imgMap['sigRawB64'] as String).isNotEmpty) {
              _uploadedSignatureRawBytes =
                  base64Decode(imgMap['sigRawB64'] as String);
            }
            if (imgMap['sigB64'] is String &&
                (imgMap['sigB64'] as String).isNotEmpty) {
              _uploadedSignatureBytes =
                  base64Decode(imgMap['sigB64'] as String);
              _cachedSignatureImage = MemoryImage(_uploadedSignatureBytes!);
            }
          } catch (_) {}
        }
        if (savedPhotosStr != null && savedPhotosStr.isNotEmpty) {
          try {
            final pMap = jsonDecode(savedPhotosStr) as Map<String, dynamic>;
            for (final entry in pMap.entries) {
              if (entry.value is String && (entry.value as String).isNotEmpty) {
                final bytes = base64Decode(entry.value as String);
                _uploadedPhotos[entry.key] = bytes;
                _photoImageCache[entry.key] = MemoryImage(bytes);
              }
            }
          } catch (_) {}
        }
        _syncControllersToSelection();
      });
      _isRestoringWorkspace = false;
      _pushHistory();
    } catch (_) {
      _isRestoringWorkspace = false;
    }
  }

  Future<void> _saveLastOpenTab(int idx) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_IdCardStudioViewState._prefKeyLastTab, idx);
    } catch (_) {}
  }

  Future<void> _saveVisualPreferences() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble(_IdCardStudioViewState._prefKeyZoom, _zoom);
      await prefs.setBool(_IdCardStudioViewState._prefKeyShowGrid, _showGrid);
      await prefs.setBool(
          _IdCardStudioViewState._prefKeyShowRulers, _showRulers);
      await prefs.setBool(
          _IdCardStudioViewState._prefKeyShowGuides, _showSafeZone);
      await prefs.setBool(
          _IdCardStudioViewState._prefKeySnapEnabled, _snapEnabled);
      await prefs.setStringList(
          _IdCardStudioViewState._prefKeyRecentFonts, _recentFonts);
      await prefs.setString(
          _IdCardStudioViewState._prefKeyDefaultPrefixMode, _defaultPrefixMode);
    } catch (_) {}
  }

  // ==========================================================================
  // DEFAULT FIELD PREFIX (None by default; Admin chooses Label / Header / Custom)
  // ==========================================================================

  /// Prefix used for a newly inserted field according to the admin's choice.
  String _autoPrefixFor({DbStudentHeaderSpec? spec, String? headerName}) {
    switch (_defaultPrefixMode) {
      case 'label':
        if (spec != null && spec.defaultPrefix.isNotEmpty) {
          return spec.defaultPrefix;
        }
        final h = (headerName ?? spec?.labelGu ?? '').trim();
        return h.isEmpty ? '' : '$h: ';
      case 'header':
        final h = (headerName ?? spec?.labelEn ?? '').trim();
        return h.isEmpty ? '' : '$h: ';
      case 'none':
      default:
        return '';
    }
  }

  void _setDefaultPrefixMode(String mode, {bool applyToExisting = false}) {
    if (!const {'none', 'label', 'header'}.contains(mode)) return;
    _rebuild(() {
      _defaultPrefixMode = mode;
      if (applyToExisting) {
        final specs = _allAvailableDbHeaderSpecs();
        for (final l in _layouts) {
          for (final f in l.fields) {
            if (f.isDirectText) continue;
            final col = f.col;
            final header =
                (col >= 0 && col < _headers.length) ? _headers[col] : '';
            DbStudentHeaderSpec? spec;
            for (final sp in specs) {
              if (sp.labelEn.toLowerCase() == header.toLowerCase()) {
                spec = sp;
                break;
              }
            }
            f.prefix = _autoPrefixFor(spec: spec, headerName: header);
          }
        }
        AutoFitTypographyEngine.clearCache();
        _syncControllersToSelection();
      }
      _statusMessage = mode == 'none'
          ? 'Default prefix: None. New fields will show only the value.'
          : (mode == 'label'
              ? 'Default prefix: Label (e.g. "જન્મ તારીખ: ").'
              : 'Default prefix: Column header name.');
      if (applyToExisting) {
        _statusMessage = '$_statusMessage Applied to all fields on the card.';
      }
    });
    _saveVisualPreferences();
    if (applyToExisting) _pushHistory();
  }

  void _recordRecentFont(String font) {
    _recentFonts.remove(font);
    _recentFonts.insert(0, font);
    if (_recentFonts.length > 6) {
      _recentFonts = _recentFonts.sublist(0, 6);
    }
    _saveVisualPreferences();
  }

  // ==========================================================================
  // STUDENT SELECTION & FILTERING LOGIC (SHIFT+CLICK, CTRL+CLICK, SELECT ALL)
  // ==========================================================================

  List<int> _filteredStudentRowIndices() {
    if (!_filteredIndicesDirty && _cachedFilteredRowIndices.isNotEmpty) {
      return _cachedFilteredRowIndices;
    }
    final q = _studentPanelSearchQuery.trim().toLowerCase();
    if (q.isEmpty) {
      _cachedFilteredRowIndices = List<int>.generate(_rows.length, (i) => i);
    } else {
      final matches = <int>[];
      for (int i = 0; i < _rows.length; i++) {
        final r = _rows[i];
        bool hit = false;
        for (int c = 0; c < r.length; c++) {
          if (r[c].toLowerCase().contains(q)) {
            hit = true;
            break;
          }
        }
        if (hit) matches.add(i);
      }
      _cachedFilteredRowIndices = matches;
    }
    _filteredIndicesDirty = false;
    return _cachedFilteredRowIndices;
  }

  List<int> _previewNavigableRowIndices() {
    if (_selectedOnlyPreviewMode && _selectedStudentIndices.isNotEmpty) {
      final sorted = _selectedStudentIndices
          .where((i) => i >= 0 && i < _rows.length)
          .toList()
        ..sort();
      if (sorted.isNotEmpty) return sorted;
    }
    return List<int>.generate(_rows.length, (i) => i);
  }

  void _stepPreviewRecord(int delta) {
    final nav = _previewNavigableRowIndices();
    if (nav.isEmpty) return;
    final pos = nav.indexOf(_curRowIdx);
    final nextPos = pos < 0
        ? 0
        : (pos + delta).clamp(0, math.max(0, nav.length - 1)).toInt();
    _rebuild(() {
      _curRowIdx = nav[nextPos];
      _syncControllersToSelection();
    });
  }

  void _handleStudentRowClick(
    int rowIdx, {
    bool toggleCheckboxOnly = false,
  }) {
    if (rowIdx < 0 || rowIdx >= _rows.length) return;
    _studentListFocusNode.requestFocus();

    final isCtrl = HardwareKeyboard.instance.isControlPressed ||
        HardwareKeyboard.instance.isMetaPressed;
    final isShift = HardwareKeyboard.instance.isShiftPressed;
    final visible = _filteredStudentRowIndices();

    _rebuild(() {
      if (isShift && _lastClickedStudentIdx != null) {
        final p1 = visible.indexOf(_lastClickedStudentIdx!);
        final p2 = visible.indexOf(rowIdx);
        if (!isCtrl) {
          _selectedStudentIndices.clear();
        }
        if (p1 >= 0 && p2 >= 0) {
          final start = math.min(p1, p2);
          final end = math.max(p1, p2);
          for (int i = start; i <= end; i++) {
            _selectedStudentIndices.add(visible[i]);
          }
        } else {
          final start = math.min(_lastClickedStudentIdx!, rowIdx);
          final end = math.max(_lastClickedStudentIdx!, rowIdx);
          for (int i = start; i <= end; i++) {
            _selectedStudentIndices.add(i);
          }
        }
      } else if (isCtrl || toggleCheckboxOnly) {
        if (_selectedStudentIndices.contains(rowIdx)) {
          _selectedStudentIndices.remove(rowIdx);
        } else {
          _selectedStudentIndices.add(rowIdx);
        }
        _lastClickedStudentIdx = rowIdx;
      } else {
        _selectedStudentIndices
          ..clear()
          ..add(rowIdx);
        _lastClickedStudentIdx = rowIdx;
      }

      _curRowIdx = rowIdx;
      _syncControllersToSelection();
      _statusMessage =
          'Student #${rowIdx + 1} active • ${_selectedStudentIndices.length} of ${_rows.length} student(s) selected.';
    });
  }

  void _selectAllVisibleStudents() {
    final visible = _filteredStudentRowIndices();
    _rebuild(() {
      _selectedStudentIndices.addAll(visible);
      _statusMessage =
          'Selected all ${visible.length} visible student(s) (${_selectedStudentIndices.length} of ${_rows.length} total).';
    });
  }

  void _clearStudentSelection() {
    _rebuild(() {
      _selectedStudentIndices.clear();
      _statusMessage =
          'Cleared student selection (0 of ${_rows.length} selected).';
    });
  }

  void _invertVisibleStudentSelection() {
    final visible = _filteredStudentRowIndices();
    _rebuild(() {
      for (final idx in visible) {
        if (_selectedStudentIndices.contains(idx)) {
          _selectedStudentIndices.remove(idx);
        } else {
          _selectedStudentIndices.add(idx);
        }
      }
      _statusMessage =
          'Inverted selection • ${_selectedStudentIndices.length} of ${_rows.length} student(s) selected.';
    });
  }

  void _navigateStudentListByOffset(int delta, {required bool extendSelection}) {
    final visible = _filteredStudentRowIndices();
    if (visible.isEmpty) return;
    final curPos = visible.indexOf(_curRowIdx);
    final nextPos = curPos < 0
        ? 0
        : (curPos + delta).clamp(0, math.max(0, visible.length - 1)).toInt();
    final targetIdx = visible[nextPos];

    _rebuild(() {
      _curRowIdx = targetIdx;
      if (extendSelection) {
        final anchor = _lastClickedStudentIdx ?? targetIdx;
        final aPos = visible.indexOf(anchor);
        if (aPos >= 0) {
          final s = math.min(aPos, nextPos);
          final e = math.max(aPos, nextPos);
          for (int i = s; i <= e; i++) {
            _selectedStudentIndices.add(visible[i]);
          }
        } else {
          _selectedStudentIndices.add(targetIdx);
        }
      } else {
        _selectedStudentIndices
          ..clear()
          ..add(targetIdx);
        _lastClickedStudentIdx = targetIdx;
      }
      _syncControllersToSelection();
    });

    if (_studentListScrollCtrl.hasClients) {
      final targetOffset = math.max(0.0, (nextPos * 46.0) - 92.0);
      _studentListScrollCtrl.animateTo(
        targetOffset.clamp(
          0.0,
          _studentListScrollCtrl.position.maxScrollExtent,
        ),
        duration: const Duration(milliseconds: 110),
        curve: Curves.easeOut,
      );
    }
  }

  // ==========================================================================
  // DATABASE & WORKSPACE INITIALIZATION
  // ==========================================================================

  List<DbStudentHeaderSpec> _allAvailableDbHeaderSpecs() {
    final specs = List<DbStudentHeaderSpec>.from(kCoreStudentHeaderSpecs);
    for (int i = 1; i <= 11; i++) {
      final k = 'custom_$i';
      final lbl = (_customHeaderLabels[k] ?? '').trim();
      specs.add(
        DbStudentHeaderSpec(
          key: k,
          labelEn: lbl.isNotEmpty ? lbl : 'Custom Field $i',
          labelGu: lbl.isNotEmpty ? lbl : 'કસ્ટમ કોલમ $i',
          defaultPrefix: lbl.isNotEmpty ? '$lbl: ' : '',
        ),
      );
    }
    return specs;
  }

  void _initBlankWorkspace() {
    final specs = _allAvailableDbHeaderSpecs();
    _headers = [
      'Sr No',
      'Photo File',
      ...specs.map((s) => s.labelEn),
    ];
    _rows = [
      List<String>.generate(
        _headers.length,
        (i) => i == 0 ? '1' : (i == 1 ? 'stu_1' : ''),
      ),
    ];
    _filteredIndicesDirty = true;
    _selectedStudentIndices
      ..clear()
      ..add(0);
    _lastClickedStudentIdx = 0;
    _tplTheme = BuiltInTemplateTheme.none;
    _tplHeaderTitle = '';
    _tplTitleCtrl.text = '';
    _uploadedTemplateBytes = null;
    _cachedTemplateImage = null;
    _uploadedTemplateName = '';
    _showPhoto = true;
    _showSeal = false;
    _uploadedSealRawBytes = null;
    _uploadedSealBytes = null;
    _cachedSealImage = null;
    _uploadedSealName = '';
    _showSignature = false;
    _uploadedSignatureRawBytes = null;
    _uploadedSignatureBytes = null;
    _cachedSignatureImage = null;
    _uploadedSignatureName = '';
    _photoCol = 1;
    _curRowIdx = 0;
    _rangeFrom = 1;
    _rangeTo = 1;
    _rangeFromCtrl.text = '1';
    _rangeToCtrl.text = '1';
    _layouts = List.generate(4, (_) => _buildBlankCardLayout());
    _selKey = null;
    _multiSel = [];
    _syncControllersToSelection();
    _statusMessage =
        'Blank ID card ready. Tap any Header chip or "Insert Selected Headers" to place fields on the card.';
    _pushHistory();
  }

  CardLayoutSet _buildBlankCardLayout() {
    final isV = _cw < _ch;
    final photoW = isV
        ? (_cw * 0.37).roundToDouble()
        : (_cw * 0.245).roundToDouble();
    final photoH = isV
        ? (photoW * 1.24).roundToDouble()
        : (_ch * 0.475).roundToDouble();
    final photoX = isV
        ? ((_cw - photoW) / 2.0).roundToDouble()
        : (_cw * 0.057).roundToDouble();
    final photoY = isV
        ? (_ch * 0.14).roundToDouble()
        : (_ch * 0.22).roundToDouble();
    final sealDim = (math.min(_cw, _ch) * 0.175).roundToDouble();
    final signW = (_cw * 0.21).roundToDouble();
    final signH = (_ch * 0.135).roundToDouble();

    return CardLayoutSet(
      fields: <CardFieldItem>[],
      photo: CardPhotoBox(x: photoX, y: photoY, w: photoW, h: photoH),
      seal: CardSealBox(
        x: photoX + photoW - (sealDim * 0.55).roundToDouble(),
        y: photoY + photoH - (sealDim * 0.55).roundToDouble(),
        w: sealDim,
        h: sealDim,
      ),
      signature: CardSignatureBox(
        x: (_cw - signW - 24).clamp(12, _cw - signW - 12).roundToDouble(),
        y: (_ch - signH - 20).clamp(12, _ch - signH - 12).roundToDouble(),
        w: signW,
        h: signH,
      ),
    );
  }

  void _clearAllPreFilledData({bool alsoClearTemplate = false}) {
    _rebuild(() {
      for (final l in _layouts) {
        l.fields.clear();
      }
      _showSeal = false;
      _uploadedSealRawBytes = null;
      _uploadedSealBytes = null;
      _cachedSealImage = null;
      _uploadedSealName = '';
      _showSignature = false;
      _uploadedSignatureRawBytes = null;
      _uploadedSignatureBytes = null;
      _cachedSignatureImage = null;
      _uploadedSignatureName = '';
      _tplHeaderTitle = '';
      _tplTitleCtrl.text = '';
      if (alsoClearTemplate) {
        _uploadedTemplateBytes = null;
        _cachedTemplateImage = null;
        _uploadedTemplateName = '';
        _tplTheme = BuiltInTemplateTheme.none;
      }
      _selKey = null;
      _multiSel = [];
      AutoFitTypographyEngine.clearCache();
      _statusMessage =
          'Cleared all pre-filled fields, seal, and signature. Tap any Header chip or "Insert Selected Headers" to insert fields.';
    });
    _pushHistory();
  }

  Future<void> _loadSchoolRecordsFromDatabase({
    bool switchToDatabase = false,
  }) async {
    try {
      final client = Supabase.instance.client;
      if (client.auth.currentUser == null) return;
      final schoolRefObj = await client.rpc('current_school_ref');
      final schoolRef = (schoolRefObj ?? '').toString().trim();
      if (schoolRef.isEmpty) return;

      final results = await Future.wait<dynamic>([
        client.from('schools').select().eq('id', schoolRef).maybeSingle(),
        client
            .from('school_classes')
            .select('id,label,class_key,sort_order')
            .eq('school_ref', schoolRef)
            .eq('is_active', true)
            .order('sort_order'),
        client
            .from('students')
            .select()
            .eq('school_ref', schoolRef)
            .eq('is_active', true),
        client
            .from('school_custom_headers')
            .select()
            .eq('school_ref', schoolRef),
      ]);

      final schoolRow = results[0] is Map
          ? Map<String, dynamic>.from(results[0] as Map)
          : <String, dynamic>{};
      final classRows = results[1] is List ? results[1] as List : const [];
      final studentRows = results[2] is List ? results[2] as List : const [];
      final customHeaderRows =
          results[3] is List ? results[3] as List : const [];

      final schoolTitle = [
        schoolRow['school_name_gu'],
        schoolRow['school_name'],
        schoolRow['school_name_en'],
      ]
          .map((e) => (e ?? '').toString().trim())
          .firstWhere((s) => s.isNotEmpty, orElse: () => '');
      final schoolAddr = [
        schoolRow['school_address_gu'],
        schoolRow['school_address_en'],
      ]
          .map((e) => (e ?? '').toString().trim())
          .firstWhere((s) => s.isNotEmpty, orElse: () => '');

      final customLabels = <String, String>{};
      for (final ch in customHeaderRows) {
        if (ch is Map) {
          final slot =
              (ch['slot_number'] ?? ch['slot'] ?? '').toString().trim();
          final key = (ch['header_key'] ?? '').toString().trim();
          final lbl =
              (ch['label_gu'] ?? ch['label_en'] ?? ch['label'] ?? '')
                  .toString()
                  .trim();
          if (lbl.isNotEmpty) {
            if (key.startsWith('custom_')) {
              customLabels[key] = lbl;
            } else if (slot.isNotEmpty) {
              customLabels['custom_$slot'] = lbl;
            }
          }
        }
      }

      final parsedClasses = <Map<String, dynamic>>[];
      for (final c in classRows) {
        if (c is Map) {
          parsedClasses.add(Map<String, dynamic>.from(c));
        }
      }

      final parsedStudents = <Map<String, dynamic>>[];
      for (final s in studentRows) {
        if (s is Map) {
          final map = Map<String, dynamic>.from(s);
          final name =
              (map['student_name'] ?? map['name'] ?? '').toString().trim();
          if (name.isNotEmpty) {
            parsedStudents.add(map);
          }
        }
      }

      if (!mounted) return;
      _rebuild(() {
        _schoolTitle = schoolTitle;
        _schoolAddr = schoolAddr;
        _dbClasses = parsedClasses;
        _dbStudentsAll = parsedStudents;
        _customHeaderLabels = customLabels;
        if (switchToDatabase) {
          _excelDataSourceActive = false;
          _excelSourceFileName = '';
        }
        // Never overwrite rows that the admin uploaded from Excel/CSV.
        if (!_excelDataSourceActive) {
          _rebuildRowsFromStudentDatabase(
            preserveExistingLayoutFields: true,
          );
        }
      });
    } catch (_) {}
  }

  String _extractDbStudentFieldValue(
    Map<String, dynamic> s,
    String key,
    Map<String, String> classNameById,
  ) {
    String pick(List<String> keys) {
      for (final k in keys) {
        final v = (s[k] ?? '').toString().trim();
        if (v.isNotEmpty) return v;
      }
      final extra = s['extra_fields'];
      if (extra is Map) {
        for (final k in keys) {
          final v = (extra[k] ?? '').toString().trim();
          if (v.isNotEmpty) return v;
        }
      }
      final custom = s['custom_fields'];
      if (custom is Map) {
        for (final k in keys) {
          final v = (custom[k] ?? '').toString().trim();
          if (v.isNotEmpty) return v;
        }
      }
      return '';
    }

    switch (key) {
      case 'student_name':
        return pick(['student_name', 'name']);
      case 'class_label':
        final cid = pick(['class_id']);
        return classNameById[cid] ?? pick(['class_label', 'class_key']);
      case 'roll_no':
        return pick(['roll_number', 'roll_no']);
      case 'gr_no':
        return pick(['gr_no', 'gr_number', 'gr']);
      case 'birth_date':
        // Student records keep DOB in three columns (dd, mm, yyyy). Merge them
        // into DD/MM/YYYY; fall back to any single-column date value.
        final composed = _composeDdMmYyyy(
          pick(['dd', 'dob_dd', 'birth_dd']),
          pick(['mm', 'dob_mm', 'birth_mm']),
          pick(['yyyy', 'dob_yyyy', 'birth_yyyy']),
        );
        if (composed.isNotEmpty) return composed;
        return _formatAnyDateDmy(
            pick(['birth_date', 'dob', 'date_of_birth', 'birthdate']));
      case 'mobile':
        return pick(['mobile', 'parent_mobile', 'phone']);
      case 'father_name':
        return pick(['father_name', 'father']);
      case 'mother_name':
        return pick(['mother_name', 'mother']);
      case 'religion':
        return pick(['religion', 'ધર્મ']);
      case 'religion_en':
        return pick(['religion_en', 'RELIGION IN ENGLISH']);
      case 'caste':
        return pick(['caste', 'sub_caste']);
      case 'category':
        return pick(['category']);
      case 'gender':
        return pick(['gender', 'sex']);
      case 'address':
        return pick(['address', 'village', 'city']);
      case 'uid':
        return pick(['uid', 'aadhar_dise', 'aadhar_no']);
      case 'pen':
        return pick(['pen', 'pen_no']);
      case 'apaar_id':
        return pick(['apaar_id', 'apaar']);
      case 'enroll_school':
        return _formatAnyDateDmy(pick(['enroll_school', 'admission_date']));
      case 'school_name':
        return _schoolTitle;
      default:
        return pick([key]);
    }
  }

  /// Joins separate day / month / year parts into DD/MM/YYYY.
  String _composeDdMmYyyy(String dd, String mm, String yyyy) {
    String digits(String v) => v.replaceAll(RegExp(r'[^0-9]'), '');
    final d = digits(dd);
    final m = digits(mm);
    var y = digits(yyyy);
    if (d.isEmpty && m.isEmpty && y.isEmpty) return '';
    if (y.length == 2) {
      final yy = int.tryParse(y) ?? 0;
      y = '${yy > 40 ? 19 : 20}$y';
    }
    final parts = <String>[
      d.isEmpty ? '' : d.padLeft(2, '0'),
      m.isEmpty ? '' : m.padLeft(2, '0'),
      y,
    ];
    return parts.join('/');
  }

  /// Normalises ISO (2012-05-07), Excel serial (41036) or slash/dash dates to
  /// DD/MM/YYYY. Unknown formats are returned unchanged.
  String _formatAnyDateDmy(String raw) {
    final v = raw.trim();
    if (v.isEmpty) return '';
    final iso = RegExp(r'^(\d{4})-(\d{1,2})-(\d{1,2})').firstMatch(v);
    if (iso != null) {
      return _composeDdMmYyyy(iso.group(3)!, iso.group(2)!, iso.group(1)!);
    }
    final dmy =
        RegExp(r'^(\d{1,2})[./-](\d{1,2})[./-](\d{2,4})$').firstMatch(v);
    if (dmy != null) {
      return _composeDdMmYyyy(dmy.group(1)!, dmy.group(2)!, dmy.group(3)!);
    }
    final serial = double.tryParse(v);
    if (serial != null && serial > 10000 && serial < 80000) {
      final dt = DateTime(1899, 12, 30).add(Duration(days: serial.floor()));
      return _composeDdMmYyyy('${dt.day}', '${dt.month}', '${dt.year}');
    }
    return v;
  }

  void _rebuildRowsFromStudentDatabase({
    bool preserveExistingLayoutFields = true,
  }) {
    final specs = _allAvailableDbHeaderSpecs();
    final classNameById = <String, String>{};
    final classSortById = <String, int>{};
    for (final c in _dbClasses) {
      final id = (c['id'] ?? '').toString().trim();
      final lbl = (c['label'] ?? c['class_key'] ?? '').toString().trim();
      final sort = (c['sort_order'] as num?)?.toInt() ?? 999;
      if (id.isNotEmpty) {
        classNameById[id] = lbl;
        classSortById[id] = sort;
      }
    }

    final filtered = _dbStudentsAll.where((s) {
      if (_selectedClassId == '__ALL__') return true;
      return (s['class_id'] ?? '').toString().trim() == _selectedClassId;
    }).toList();

    filtered.sort((a, b) {
      final ca = (a['class_id'] ?? '').toString().trim();
      final cb = (b['class_id'] ?? '').toString().trim();
      final sa = classSortById[ca] ?? 999;
      final sb = classSortById[cb] ?? 999;
      if (sa != sb) return sa.compareTo(sb);
      final ra =
          int.tryParse((a['roll_number'] ?? a['roll_no'] ?? '').toString()) ??
              9999;
      final rb =
          int.tryParse((b['roll_number'] ?? b['roll_no'] ?? '').toString()) ??
              9999;
      return ra.compareTo(rb);
    });

    final newHeaders = <String>[
      'Sr No',
      'Photo File',
      ...specs.map((s) => s.labelEn),
    ];

    final newRows = <List<String>>[];
    for (int i = 0; i < filtered.length; i++) {
      final s = filtered[i];
      final sr = '${i + 1}';
      final gr = (s['gr_no'] ?? s['gr_number'] ?? '').toString().trim();
      final roll = (s['roll_number'] ?? s['roll_no'] ?? sr).toString().trim();
      final photoKey = gr.isNotEmpty ? gr : roll;
      final row = <String>[
        sr,
        photoKey,
        for (final spec in specs)
          _extractDbStudentFieldValue(s, spec.key, classNameById),
      ];
      newRows.add(row);
    }

    _headers = newHeaders;
    if (newRows.isNotEmpty) {
      _rows = newRows;
    } else {
      _rows = [
        List<String>.generate(
          _headers.length,
          (i) => i == 0 ? '1' : (i == 1 ? 'stu_1' : ''),
        ),
      ];
    }
    _filteredIndicesDirty = true;
    _selectedStudentIndices
      ..clear()
      ..addAll(List<int>.generate(_rows.length, (i) => i));
    _lastClickedStudentIdx = 0;
    _curRowIdx = 0;
    _sheetPageIdx = 0;
    _rangeFrom = 1;
    _rangeTo = _rows.length;
    _rangeFromCtrl.text = '1';
    _rangeToCtrl.text = '${_rows.length}';
    if (!preserveExistingLayoutFields) {
      _insertCheckedDatabaseHeadersOnCard(replaceExisting: true);
    } else {
      _syncControllersToSelection();
      _statusMessage = filtered.isNotEmpty
          ? 'Loaded ${filtered.length} student(s). Tap any Header chip or "Insert Selected Headers" to place fields on the card.'
          : 'No students found for this filter. You can still design and insert headers on the card.';
    }
  }

  /// Ensures a database header spec has a valid column index in `_headers` and `_rows`.
  int _ensureDbHeaderColumnIndex(DbStudentHeaderSpec spec) {
    final specs = _allAvailableDbHeaderSpecs();
    final canonicalIdx = specs.indexWhere((s) => s.key == spec.key) + 2;
    if (canonicalIdx >= 2 &&
        canonicalIdx < _headers.length &&
        _headers[canonicalIdx].toLowerCase() == spec.labelEn.toLowerCase()) {
      return canonicalIdx;
    }
    final existingByName = _headers.indexWhere(
      (h) =>
          h.trim().toLowerCase() == spec.labelEn.toLowerCase() ||
          h.trim().toLowerCase() == spec.labelGu.toLowerCase(),
    );
    if (existingByName >= 0) return existingByName;

    // Append missing header column to _headers and _rows
    _headers.add(spec.labelEn);
    final newColIdx = _headers.length - 1;
    for (final r in _rows) {
      while (r.length <= newColIdx) {
        r.add('');
      }
    }
    return newColIdx;
  }

  /// Immediately inserts or removes a single Database Header when its chip is toggled!
  void _toggleSingleDbHeaderOnCard(
    DbStudentHeaderSpec spec,
    bool checked,
  ) {
    _rebuild(() {
      if (checked) {
        _selectedDbHeaderKeys.add(spec.key);
        final colIdx = _ensureDbHeaderColumnIndex(spec);
        final isV = _cw < _ch;
        final isName = spec.key == 'student_name';

        for (final l in _layouts) {
          final alreadyOnCard =
              l.fields.any((f) => !f.isDirectText && f.col == colIdx);
          if (alreadyOnCard) continue;

          final fieldW = math
              .min(_cw * (isV ? 0.84 : 0.62),
                  _cw - _IdCardStudioViewState.kSafePad * 2)
              .roundToDouble();
          final fieldX = ((_cw - fieldW) / 2.0).roundToDouble();
          const boxH = 26.0;
          final centerStartY = ((_ch - boxH) / 2.0).roundToDouble();
          final lastF = l.fields.isNotEmpty ? l.fields.last : null;
          final nextY = lastF != null
              ? math.min(
                  _ch - boxH - _IdCardStudioViewState.kSafePad,
                  lastF.y + lastF.h + 5,
                )
              : centerStartY;

          l.fields.add(
            CardFieldItem(
              col: colIdx,
              x: fieldX,
              y: nextY,
              w: fieldW,
              h: boxH,
              fontSize: isName ? 11.0 : 9.5,
              minFontSize: 4.5,
              autoFit: true,
              align: TextAlign.center,
              prefix: _autoPrefixFor(spec: spec),
              prefixBold: true,
              bold: isName,
              color: isName
                  ? const Color(0xFF0F172A)
                  : const Color(0xFF1E293B),
            ),
          );
        }

        if (_curLayout.fields.isNotEmpty) {
          final idx = _curLayout.fields
              .lastIndexWhere((f) => !f.isDirectText && f.col == colIdx);
          if (idx >= 0) {
            _selKey = SelectedItemKey(SelectedItemType.field, idx);
            _multiSel = [_selKey!];
          }
        }
        _syncControllersToSelection();
        _statusMessage =
            'Inserted "${spec.labelEn} (${spec.labelGu})" onto the card. Drag or resize from any corner.';
      } else {
        _selectedDbHeaderKeys.remove(spec.key);
        final colIdx = _ensureDbHeaderColumnIndex(spec);
        for (final l in _layouts) {
          l.fields.removeWhere(
            (f) => !f.isDirectText && f.col == colIdx && !f.locked,
          );
        }
        _selKey = null;
        _multiSel = [];
        _statusMessage =
            'Removed "${spec.labelEn} (${spec.labelGu})" from the card.';
      }
      AutoFitTypographyEngine.clearCache();
    });
    _pushHistory();
  }

  /// Inserts/syncs all checked Student Database headers onto the card.
  void _insertCheckedDatabaseHeadersOnCard({bool replaceExisting = true}) {
    final specs = _allAvailableDbHeaderSpecs();
    final selectedSpecs =
        specs.where((s) => _selectedDbHeaderKeys.contains(s.key)).toList();
    if (selectedSpecs.isEmpty) {
      _rebuild(() {
        _statusMessage =
            'Please check at least one Student Database header chip first.';
      });
      return;
    }

    final isV = _cw < _ch;
    final count = selectedSpecs.length;

    _rebuild(() {
      final colIndices = <int>[
        for (final spec in selectedSpecs) _ensureDbHeaderColumnIndex(spec),
      ];

      for (final l in _layouts) {
        if (replaceExisting) {
          l.fields.removeWhere((f) => !f.isDirectText && !f.locked);
        }
        final existingCols = l.fields
            .where((f) => !f.isDirectText)
            .map((f) => f.col)
            .toSet();
        final specsToInsert = <int>[];
        for (int i = 0; i < selectedSpecs.length; i++) {
          if (replaceExisting || !existingCols.contains(colIndices[i])) {
            specsToInsert.add(i);
          }
        }
        final totalFieldsAfter = replaceExisting
            ? selectedSpecs.length
            : (l.fields.length + specsToInsert.length);
        final availH = math.max(
          100.0,
          _ch - _IdCardStudioViewState.kSafePad * 2,
        );
        final step = math.max(
          22.0,
          math.min(
            30.0,
            ((availH * 0.82) / math.max(1, totalFieldsAfter)).floorToDouble(),
          ),
        );
        final boxH = math.max(20.0, step - 4.0);
        final fieldW = math
            .min(_cw * (isV ? 0.84 : 0.62),
                _cw - _IdCardStudioViewState.kSafePad * 2)
            .roundToDouble();
        final fieldX = ((_cw - fieldW) / 2.0).roundToDouble();
        final totalBlockH =
            math.max(1, totalFieldsAfter) * step - (step - boxH);
        final centerStartY = ((_ch - totalBlockH) / 2.0)
            .clamp(
              _IdCardStudioViewState.kSafePad,
              math.max(
                _IdCardStudioViewState.kSafePad,
                _ch - totalBlockH - _IdCardStudioViewState.kSafePad,
              ),
            )
            .roundToDouble();

        for (int i = 0; i < selectedSpecs.length; i++) {
          final spec = selectedSpecs[i];
          final colIdx = colIndices[i];
          if (!replaceExisting && existingCols.contains(colIdx)) continue;
          final isName = spec.key == 'student_name';
          final slotIdx = replaceExisting ? i : l.fields.length;
          l.fields.add(
            CardFieldItem(
              col: colIdx,
              x: fieldX,
              y: (centerStartY + slotIdx * step)
                  .clamp(
                    _IdCardStudioViewState.kSafePad,
                    _ch - boxH - _IdCardStudioViewState.kSafePad,
                  )
                  .roundToDouble(),
              w: fieldW,
              h: boxH,
              fontSize: isName ? 11.0 : 9.5,
              minFontSize: 4.5,
              autoFit: true,
              align: TextAlign.center,
              prefix: _autoPrefixFor(spec: spec),
              prefixBold: true,
              bold: isName,
              color: isName
                  ? const Color(0xFF0F172A)
                  : const Color(0xFF1E293B),
            ),
          );
        }
      }
      if (_curLayout.fields.isNotEmpty) {
        _selKey = SelectedItemKey(
          SelectedItemType.field,
          _curLayout.fields.length - 1,
        );
        _multiSel = [_selKey!];
      }
      AutoFitTypographyEngine.clearCache();
      _syncControllersToSelection();
      _statusMessage =
          'Inserted ${selectedSpecs.length} selected header field(s) onto the card!';
    });
    _pushHistory();
  }

  /// Inserts any specific column index from `_headers` (e.g. from uploaded Excel).
  void _insertExcelHeaderColOnCard(int colIdx) {
    if (colIdx < 0 || colIdx >= _headers.length) return;
    final hName = _headers[colIdx];
    final isV = _cw < _ch;
    _rebuild(() {
      for (final l in _layouts) {
        final fieldW = math
            .min(_cw * (isV ? 0.84 : 0.62),
                _cw - _IdCardStudioViewState.kSafePad * 2)
            .roundToDouble();
        final fieldX = ((_cw - fieldW) / 2.0).roundToDouble();
        const boxH = 26.0;
        final lastF = l.fields.isNotEmpty ? l.fields.last : null;
        final nextY = lastF != null
            ? math.min(
                _ch - boxH - _IdCardStudioViewState.kSafePad,
                lastF.y + lastF.h + 5,
              )
            : ((_ch - boxH) / 2.0).roundToDouble();
        l.fields.add(
          CardFieldItem(
            col: colIdx,
            x: fieldX,
            y: nextY,
            w: fieldW,
            h: boxH,
            fontSize: 9.5,
            minFontSize: 4.5,
            autoFit: true,
            align: TextAlign.center,
            prefix: _autoPrefixFor(headerName: hName),
            prefixBold: true,
          ),
        );
      }
      _selKey = SelectedItemKey(
        SelectedItemType.field,
        _curLayout.fields.length - 1,
      );
      _multiSel = [_selKey!];
      AutoFitTypographyEngine.clearCache();
      _syncControllersToSelection();
      _statusMessage = 'Inserted column "$hName" onto the card.';
    });
    _pushHistory();
  }

  // ==========================================================================
  // FILE UPLOADS: TEMPLATE, EXCEL, PHOTO FOLDER, SEAL & PRINCIPAL SIGNATURE
  // ==========================================================================

  Future<void> _pickCardTemplateImage() async {
    try {
      final res = await FilePicker.platform.pickFiles(
        type: FileType.image,
        withData: true,
      );
      if (res == null || res.files.isEmpty) return;
      final file = res.files.first;
      final bytes = file.bytes;
      if (bytes == null || bytes.isEmpty) return;

      _rebuild(() {
        _uploadedTemplateBytes = bytes;
        _cachedTemplateImage = MemoryImage(bytes);
        _uploadedTemplateName = file.name;
        _statusMessage =
            'Uploaded card template "${file.name}". Existing fields and layout preserved.';
      });
    } catch (e) {
      _rebuild(() => _statusMessage = 'Template upload failed: $e');
    }
  }

  // --------------------------------------------------------------------------
  // EXCEL / CSV IMPORT HELPERS
  // --------------------------------------------------------------------------

  /// Converts one Excel cell to display text: dates become DD/MM/YYYY and
  /// whole numbers lose the trailing ".0" (mobile, GR, Aadhaar stay exact).
  String _excelCellText(xls.Data? cell) {
    final v = cell?.value;
    if (v == null) return '';
    if (v is xls.DateCellValue) {
      return _composeDdMmYyyy('${v.day}', '${v.month}', '${v.year}');
    }
    if (v is xls.DateTimeCellValue) {
      return _composeDdMmYyyy('${v.day}', '${v.month}', '${v.year}');
    }
    if (v is xls.IntCellValue) return '${v.value}';
    if (v is xls.DoubleCellValue) {
      final d = v.value;
      if (d.isFinite && d == d.roundToDouble() && d.abs() < 1e15) {
        return d.toInt().toString();
      }
      return d.toString();
    }
    if (v is xls.BoolCellValue) return v.value ? 'Yes' : 'No';
    return v.toString().trim();
  }

  /// RFC-4180 style CSV/TSV line splitter (handles quoted commas).
  List<String> _splitDelimitedLine(String line, String delim) {
    if (delim == '\t' || !line.contains('"')) {
      return line.split(delim).map((c) => c.trim()).toList();
    }
    final out = <String>[];
    final sb = StringBuffer();
    var inQuotes = false;
    for (var i = 0; i < line.length; i++) {
      final ch = line[i];
      if (ch == '"') {
        if (inQuotes && i + 1 < line.length && line[i + 1] == '"') {
          sb.write('"');
          i++;
        } else {
          inQuotes = !inQuotes;
        }
      } else if (ch == delim && !inQuotes) {
        out.add(sb.toString().trim());
        sb.clear();
      } else {
        sb.write(ch);
      }
    }
    out.add(sb.toString().trim());
    return out;
  }

  static String _normHeaderToken(String h) =>
      h.toLowerCase().replaceAll(RegExp(r'[\s._\-()/:]+'), '');

  static bool _isDayHeader(String h) => const {
        'dd', 'day', 'dobdd', 'birthday', 'dobday', 'તારીખ', 'દિવસ',
      }.contains(_normHeaderToken(h));
  static bool _isMonthHeader(String h) => const {
        'mm', 'month', 'dobmm', 'dobmonth', 'માસ', 'મહિનો',
      }.contains(_normHeaderToken(h));
  static bool _isYearHeader(String h) => const {
        'yyyy', 'yy', 'year', 'dobyyyy', 'dobyear', 'વર્ષ',
      }.contains(_normHeaderToken(h));

  /// Picks the header row (first row that looks like column names) and an
  /// optional sub-header row (e.g. "DD | MM | YYYY" under "જન્મ તારીખ").
  ({List<String> headers, List<List<String>> rows}) _normalizeImportedTable(
    List<List<String>> table,
  ) {
    final probe = math.min(table.length, 15);
    var maxFilled = 0;
    for (var i = 0; i < probe; i++) {
      maxFilled = math.max(
          maxFilled, table[i].where((c) => c.trim().isNotEmpty).length);
    }
    var headerIdx = 0;
    for (var i = 0; i < probe; i++) {
      final row = table[i];
      final filled = row.where((c) => c.trim().isNotEmpty).toList();
      final textual =
          filled.where((c) => double.tryParse(c.replaceAll(',', '')) == null);
      if (filled.length >= math.max(2, (maxFilled * 0.6).ceil()) &&
          textual.length >= math.max(2, (filled.length * 0.6).ceil())) {
        headerIdx = i;
        break;
      }
    }
    final width = table.fold<int>(0, (w, r) => math.max(w, r.length));
    final header = List<String>.generate(
      width,
      (i) => i < table[headerIdx].length ? table[headerIdx][i].trim() : '',
    );
    var dataStart = headerIdx + 1;

    // Two-row header: "Birth Date" spans DD / MM / YYYY in the next row.
    if (dataStart < table.length) {
      final next = table[dataStart];
      final hasDmy = next.any(_isDayHeader) &&
          next.any(_isMonthHeader) &&
          next.any(_isYearHeader);
      if (hasDmy) {
        for (var i = 0; i < width && i < next.length; i++) {
          final sub = next[i].trim();
          if (sub.isEmpty) continue;
          if (_isDayHeader(sub) || _isMonthHeader(sub) || _isYearHeader(sub) ||
              header[i].isEmpty) {
            header[i] = sub;
          }
        }
        dataStart++;
      }
    }

    for (var i = 0; i < header.length; i++) {
      if (header[i].isEmpty) header[i] = 'Column ${i + 1}';
    }
    var rows = <List<String>>[
      for (final r in table.skip(dataStart))
        if (r.any((c) => c.trim().isNotEmpty))
          List<String>.generate(width, (i) => i < r.length ? r[i].trim() : ''),
    ];

    // Merge DD / MM / YYYY into one "Birth Date" column (DD/MM/YYYY).
    final dIdx = header.indexWhere(_isDayHeader);
    final mIdx = header.indexWhere(_isMonthHeader);
    final yIdx = header.indexWhere(_isYearHeader);
    if (dIdx >= 0 && mIdx >= 0 && yIdx >= 0) {
      final drop = <int>{mIdx, yIdx}..remove(dIdx);
      final newHeader = <String>[];
      for (var i = 0; i < header.length; i++) {
        if (drop.contains(i)) continue;
        newHeader.add(i == dIdx ? 'Birth Date' : header[i]);
      }
      rows = rows.map((r) {
        final out = <String>[];
        for (var i = 0; i < r.length; i++) {
          if (drop.contains(i)) continue;
          out.add(i == dIdx ? _composeDdMmYyyy(r[dIdx], r[mIdx], r[yIdx]) : r[i]);
        }
        return out;
      }).toList();
      return (headers: newHeader, rows: rows);
    }

    // Normalise single-column birth/admission dates (ISO or Excel serials).
    for (var i = 0; i < header.length; i++) {
      final h = header[i].toLowerCase();
      if (h.contains('birth') || h.contains('dob') || h.contains('જન્મ') ||
          h.contains('date') || h.contains('તારીખ')) {
        for (final r in rows) {
          if (i < r.length) r[i] = _formatAnyDateDmy(r[i]);
        }
      }
    }
    return (headers: header, rows: rows);
  }

  Future<void> _pickExcelOrCsvFile() async {
    try {
      final res = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['xlsx', 'csv', 'txt'],
        withData: true,
      );
      if (res == null || res.files.isEmpty) return;
      final file = res.files.first;
      final bytes = file.bytes;
      if (bytes == null || bytes.isEmpty) return;

      final ext = (file.extension ?? '').toLowerCase();
      List<List<String>> table = [];

      if (ext == 'csv' || ext == 'txt') {
        var content = utf8.decode(bytes, allowMalformed: true);
        if (content.startsWith('﻿')) content = content.substring(1);
        final lines = content
            .split(RegExp(r'\r?\n'))
            .where((l) => l.trim().isNotEmpty)
            .toList();
        if (lines.isNotEmpty) {
          final delim = lines.first.contains('\t') ? '\t' : ',';
          table = lines.map((l) => _splitDelimitedLine(l, delim)).toList();
        }
      } else {
        final excel = xls.Excel.decodeBytes(bytes);
        // Use the sheet with the most filled rows (usually the student list).
        List<List<String>> best = [];
        for (final sheetName in excel.tables.keys) {
          final sheet = excel.tables[sheetName];
          if (sheet == null || sheet.rows.isEmpty) continue;
          final current = <List<String>>[];
          for (final r in sheet.rows) {
            final cells = r.map(_excelCellText).toList();
            if (cells.any((v) => v.isNotEmpty)) current.add(cells);
          }
          if (current.length > best.length) best = current;
        }
        table = best;
      }

      if (table.length < 2) {
        _rebuild(() {
          _statusMessage =
              'Excel/CSV file must have a header row and at least 1 data row.';
        });
        return;
      }

      final normalized = _normalizeImportedTable(table);
      final hdrs = normalized.headers;
      final dataRows = normalized.rows;
      if (dataRows.isEmpty) {
        _rebuild(() {
          _statusMessage = 'No data rows found below the header row.';
        });
        return;
      }

      int detectedPhotoCol = -1;
      for (final keys in const [
        ['photo', 'image', 'ફોટો'],
        ['gr', 'જી.આર', 'જીઆર'],
        ['roll', 'રોલ'],
      ]) {
        for (int i = 0; i < hdrs.length && detectedPhotoCol < 0; i++) {
          final h = hdrs[i].toLowerCase();
          if (keys.any(h.contains)) detectedPhotoCol = i;
        }
        if (detectedPhotoCol >= 0) break;
      }
      if (detectedPhotoCol < 0) detectedPhotoCol = 0;

      _rebuild(() {
        _headers = hdrs;
        _rows = dataRows;
        _excelDataSourceActive = true;
        _excelSourceFileName = file.name;
        _filteredIndicesDirty = true;
        _selectedStudentIndices
          ..clear()
          ..addAll(List<int>.generate(_rows.length, (i) => i));
        _lastClickedStudentIdx = 0;
        _photoCol = detectedPhotoCol;
        _curRowIdx = 0;
        _sheetPageIdx = 0;
        _rangeFrom = 1;
        _rangeTo = _rows.length;
        _rangeFromCtrl.text = '1';
        _rangeToCtrl.text = '${_rows.length}';
        for (final l in _layouts) {
          for (final f in l.fields) {
            if (!f.isDirectText) {
              f.col = f.col.clamp(0, math.max(0, _headers.length - 1)).toInt();
            }
          }
        }
        _syncControllersToSelection();
        _statusMessage =
            'Loaded ${_rows.length} rows and ${_headers.length} columns from "${file.name}". Choose the columns to print on the card.';
      });
      _pushHistory();
      if (mounted) await _showExcelColumnsToCardDialog();
    } catch (e) {
      _rebuild(() => _statusMessage = 'Excel/CSV load error: $e');
    }
  }

  /// Lets the admin tick Excel columns and creates one card field per column
  /// (stacked and centred). Photo-file column is chosen here too.
  Future<void> _showExcelColumnsToCardDialog() async {
    if (_headers.isEmpty) return;
    final checked = <int>{};
    for (var i = 0; i < _headers.length; i++) {
      final h = _headers[i].toLowerCase();
      if (h.contains('photo') || h.contains('ફોટો') || h == 'sr no' ||
          h.contains('sr.') || h == 'no' || h.startsWith('column ')) {
        continue;
      }
      if (checked.length < 7) checked.add(i);
    }
    var photoCol = _photoCol.clamp(0, _headers.length - 1).toInt();
    var replaceExisting = true;
    var prefixMode = _defaultPrefixMode;
    final sample = _rows.isNotEmpty ? _rows.first : const <String>[];

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: const Text('Create ID Cards from Excel Columns'),
          content: SizedBox(
            width: 560,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${_rows.length} records • ${_headers.length} columns. Tick the columns to print on every card:',
                  style: const TextStyle(fontSize: 12.5),
                ),
                const SizedBox(height: 8),
                Flexible(
                  child: SingleChildScrollView(
                    child: Column(
                      children: [
                        for (var i = 0; i < _headers.length; i++)
                          CheckboxListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            controlAffinity: ListTileControlAffinity.leading,
                            value: checked.contains(i),
                            title: Text(_headers[i],
                                style: const TextStyle(
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w700)),
                            subtitle: Text(
                              i < sample.length && sample[i].isNotEmpty
                                  ? 'e.g. ${sample[i]}'
                                  : '(empty in first row)',
                              style: const TextStyle(fontSize: 11),
                              overflow: TextOverflow.ellipsis,
                            ),
                            onChanged: (v) => setD(() {
                              if (v == true) {
                                checked.add(i);
                              } else {
                                checked.remove(i);
                              }
                            }),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<int>(
                        value: photoCol,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: 'Photo file name column',
                          isDense: true,
                          border: OutlineInputBorder(),
                        ),
                        items: [
                          for (var i = 0; i < _headers.length; i++)
                            DropdownMenuItem(
                                value: i,
                                child: Text(_headers[i],
                                    overflow: TextOverflow.ellipsis)),
                        ],
                        onChanged: (v) => setD(() => photoCol = v ?? photoCol),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        value: prefixMode,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: 'Prefix before value',
                          isDense: true,
                          border: OutlineInputBorder(),
                        ),
                        items: const [
                          DropdownMenuItem(
                              value: 'none', child: Text('None (default)')),
                          DropdownMenuItem(
                              value: 'header',
                              child: Text('Column header: value')),
                        ],
                        onChanged: (v) =>
                            setD(() => prefixMode = v ?? prefixMode),
                      ),
                    ),
                  ],
                ),
                CheckboxListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  value: replaceExisting,
                  title: const Text('Replace existing data fields on the card',
                      style: TextStyle(fontSize: 12)),
                  onChanged: (v) => setD(() => replaceExisting = v ?? true),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Skip (design manually)'),
            ),
            FilledButton.icon(
              onPressed:
                  checked.isEmpty ? null : () => Navigator.pop(ctx, true),
              icon: const Icon(Icons.auto_awesome, size: 16),
              label: Text('Create Card Fields (${checked.length})'),
            ),
          ],
        ),
      ),
    );
    if (ok != true) return;

    final cols = checked.toList()..sort();
    final isV = _cw < _ch;
    _defaultPrefixMode = prefixMode;
    _saveVisualPreferences();
    _rebuild(() {
      _photoCol = photoCol;
      for (final l in _layouts) {
        if (replaceExisting) {
          l.fields.removeWhere((f) => !f.isDirectText && !f.locked);
        }
        final start = l.fields.length;
        final total = start + cols.length;
        final availH = math.max(100.0, _ch - _IdCardStudioViewState.kSafePad * 2);
        final step = math.max(
          22.0,
          math.min(30.0, ((availH * 0.82) / math.max(1, total)).floorToDouble()),
        );
        final boxH = math.max(20.0, step - 4.0);
        final fieldW = math
            .min(_cw * (isV ? 0.84 : 0.62),
                _cw - _IdCardStudioViewState.kSafePad * 2)
            .roundToDouble();
        final fieldX = ((_cw - fieldW) / 2.0).roundToDouble();
        final blockH = math.max(1, total) * step - (step - boxH);
        final startY = ((_ch - blockH) / 2.0)
            .clamp(
              _IdCardStudioViewState.kSafePad,
              math.max(_IdCardStudioViewState.kSafePad,
                  _ch - blockH - _IdCardStudioViewState.kSafePad),
            )
            .roundToDouble();
        for (var i = 0; i < cols.length; i++) {
          final c = cols[i];
          final h = _headers[c].toLowerCase();
          final isName = h.contains('name') || h.contains('નામ');
          l.fields.add(CardFieldItem(
            col: c,
            x: fieldX,
            y: (startY + (start + i) * step)
                .clamp(_IdCardStudioViewState.kSafePad,
                    _ch - boxH - _IdCardStudioViewState.kSafePad)
                .roundToDouble(),
            w: fieldW,
            h: boxH,
            fontSize: isName ? 11.0 : 9.5,
            minFontSize: 4.5,
            autoFit: true,
            align: TextAlign.center,
            prefix: _autoPrefixFor(headerName: _headers[c]),
            prefixBold: true,
            bold: isName,
            color: isName ? const Color(0xFF0F172A) : const Color(0xFF1E293B),
          ));
        }
      }
      if (_curLayout.fields.isNotEmpty) {
        _selKey =
            SelectedItemKey(SelectedItemType.field, _curLayout.fields.length - 1);
        _multiSel = [_selKey!];
      }
      AutoFitTypographyEngine.clearCache();
      _syncControllersToSelection();
      _statusMessage =
          'Created ${cols.length} field(s) from Excel for ${_rows.length} ID cards. Drag to adjust, then export.';
    });
    _pushHistory();
  }

  /// Uploads an entire folder of student photos at once (webkitdirectory on Web,
  /// multi-image selection fallback on other platforms).
  Future<void> _pickStudentPhotoFolder() async {
    if (kIsWeb) {
      try {
        final input = html.FileUploadInputElement()
          ..multiple = true
          ..accept = 'image/*';
        input.setAttribute('webkitdirectory', '');
        input.setAttribute('directory', '');
        input.click();
        await input.onChange.first;
        final files = input.files;
        if (files == null || files.isEmpty) return;

        int loaded = 0;
        for (final f in files) {
          final nameLower = f.name.toLowerCase();
          if (!nameLower.endsWith('.png') &&
              !nameLower.endsWith('.jpg') &&
              !nameLower.endsWith('.jpeg') &&
              !nameLower.endsWith('.webp')) {
            continue;
          }
          final reader = html.FileReader();
          reader.readAsArrayBuffer(f);
          await reader.onLoadEnd.first;
          final res = reader.result;
          Uint8List? bytes;
          if (res is Uint8List) {
            bytes = res;
          } else if (res is ByteBuffer) {
            bytes = res.asUint8List();
          } else if (res is List<int>) {
            bytes = Uint8List.fromList(res);
          }
          if (bytes != null && bytes.isNotEmpty) {
            final baseName = f.name.split('/').last.split(r'\').last;
            final stem = baseName
                .replaceAll(RegExp(r'\.[^.]+$'), '')
                .trim()
                .toLowerCase();
            if (stem.isNotEmpty) {
              _uploadedPhotos[stem] = bytes;
              _photoImageCache[stem] = MemoryImage(bytes);
              loaded++;
            }
          }
        }
        if (!mounted) return;
        _rebuild(() {
          _statusMessage =
              'Uploaded photo folder: $loaded student photo(s) matched by Roll No / GR No / Photo column!';
        });
        return;
      } catch (_) {
        // Fall through to multi-file picker if folder input is unsupported
      }
    }
    await _pickStudentPhotos(forCurrentRecordOnly: false);
  }

  Future<void> _pickStudentPhotos({bool forCurrentRecordOnly = false}) async {
    try {
      final res = await FilePicker.platform.pickFiles(
        type: FileType.image,
        allowMultiple: !forCurrentRecordOnly,
        withData: true,
      );
      if (res == null || res.files.isEmpty) return;

      int count = 0;
      _rebuild(() {
        if (forCurrentRecordOnly && _curRowIdx < _rows.length) {
          final f = res.files.first;
          if (f.bytes != null && f.bytes!.isNotEmpty) {
            final row = _rows[_curRowIdx];
            final currentKey = _photoCol < row.length
                ? row[_photoCol].trim().toLowerCase()
                : 'stu_${_curRowIdx + 1}';
            final effectiveKey =
                currentKey.isNotEmpty ? currentKey : 'stu_${_curRowIdx + 1}';
            if (_photoCol < row.length && row[_photoCol].trim().isEmpty) {
              row[_photoCol] = effectiveKey;
            }
            _uploadedPhotos[effectiveKey] = f.bytes!;
            _photoImageCache[effectiveKey] = MemoryImage(f.bytes!);
            count = 1;
          }
        } else {
          for (final f in res.files) {
            final bytes = f.bytes;
            if (bytes == null || bytes.isEmpty) continue;
            final stem = f.name
                .replaceAll(RegExp(r'\.[^.]+$'), '')
                .trim()
                .toLowerCase();
            if (stem.isNotEmpty) {
              _uploadedPhotos[stem] = bytes;
              _photoImageCache[stem] = MemoryImage(bytes);
              count++;
            }
          }
        }
        _statusMessage = forCurrentRecordOnly
            ? 'Assigned photo to Record #${_curRowIdx + 1}.'
            : 'Loaded & cached $count student photo(s).';
      });
    } catch (e) {
      _rebuild(() => _statusMessage = 'Photo upload error: $e');
    }
  }

  MemoryImage? _resolveCachedPhotoProvider(List<String> row) {
    final candidates = <String>[
      if (_photoCol >= 0 && _photoCol < row.length)
        row[_photoCol].trim().toLowerCase(),
      if (row.length > 1) row[1].trim().toLowerCase(),
      if (row.length > 4) row[4].trim().toLowerCase(),
      if (row.length > 5) row[5].trim().toLowerCase(),
      if (row.isNotEmpty) row[0].trim().toLowerCase(),
    ];
    for (final c in candidates) {
      if (c.isEmpty) continue;
      final cached = _photoImageCache[c];
      if (cached != null) return cached;
      final bytes = _uploadedPhotos[c];
      if (bytes != null) {
        final mem = MemoryImage(bytes);
        _photoImageCache[c] = mem;
        return mem;
      }
    }
    return null;
  }

  Future<void> _pickSealImage() async {
    try {
      final res = await FilePicker.platform.pickFiles(
        type: FileType.image,
        withData: true,
      );
      if (res == null || res.files.isEmpty) return;
      final file = res.files.first;
      final bytes = file.bytes;
      if (bytes == null || bytes.isEmpty) return;

      _uploadedSealRawBytes = bytes;
      _uploadedSealName = file.name;
      await _reprocessSealWithTolerance();
    } catch (e) {
      _rebuild(() => _statusMessage = 'Seal upload error: $e');
    }
  }

  Future<void> _reprocessSealWithTolerance() async {
    final raw = _uploadedSealRawBytes;
    if (raw == null) return;
    final (processed, aspect) = await processSealRemoveWhiteBg(
      raw,
      tolerance: _sealTolerance,
    );
    if (!mounted) return;
    _rebuild(() {
      _uploadedSealBytes = processed;
      _cachedSealImage = MemoryImage(processed);
      _sealAspect = aspect <= 0 ? 1.0 : aspect;
      _showSeal = true;
      for (final l in _layouts) {
        if (_sealLockAspect) {
          l.seal.h = (l.seal.w / _sealAspect).roundToDouble();
        }
        _clampItemToCard(l.seal, minW: 18, minH: 18, pad: 2);
      }
      _selKey = const SelectedItemKey(SelectedItemType.seal, 0);
      _multiSel = [_selKey!];
      _syncControllersToSelection();
      _statusMessage =
          'Seal "${_uploadedSealName}" uploaded & selected. Drag any corner handle to resize!';
    });
  }

  /// Uploads Principal Signature PNG/image with automatic white-background removal
  /// and 8-direction corner drag resize handles!
  Future<void> _pickPrincipalSignatureImage() async {
    try {
      final res = await FilePicker.platform.pickFiles(
        type: FileType.image,
        withData: true,
      );
      if (res == null || res.files.isEmpty) return;
      final file = res.files.first;
      final bytes = file.bytes;
      if (bytes == null || bytes.isEmpty) return;

      _uploadedSignatureRawBytes = bytes;
      _uploadedSignatureName = file.name;
      await _reprocessSignatureWithTolerance();
    } catch (e) {
      _rebuild(() => _statusMessage = 'Principal signature upload error: $e');
    }
  }

  Future<void> _reprocessSignatureWithTolerance() async {
    final raw = _uploadedSignatureRawBytes;
    if (raw == null) return;
    final (processed, aspect) = await processSealRemoveWhiteBg(
      raw,
      tolerance: _signatureTolerance,
    );
    if (!mounted) return;
    _rebuild(() {
      _uploadedSignatureBytes = processed;
      _cachedSignatureImage = MemoryImage(processed);
      _signatureAspect = aspect <= 0 ? 2.2 : aspect;
      _showSignature = true;
      for (final l in _layouts) {
        if (_signatureLockAspect) {
          l.signature.h =
              math.max(24.0, (l.signature.w / _signatureAspect).roundToDouble());
        }
        _clampItemToCard(l.signature, minW: 24, minH: 14, pad: 2);
      }
      _selKey = const SelectedItemKey(SelectedItemType.signature, 0);
      _multiSel = [_selKey!];
      _syncControllersToSelection();
      _statusMessage =
          'Principal Sign "${_uploadedSignatureName}" uploaded & selected. Drag any corner on the card to resize!';
    });
  }

  Future<void> _downloadSampleCsv() async {
    const csvText =
        'Sr No,Photo File,Student Name,Class,Roll No,GR No,Birth Date,Mobile,Address\n'
        '1,101,પટેલ આરવકુમાર રમેશભાઈ,ધોરણ 6,1,1045,14/08/2014,9876543210,અમદાવાદ\n'
        '2,102,શાહ દેવાંશીબેન જિતેન્દ્રકુમાર,ધોરણ 7,2,1088,22/11/2013,9825011223,ગાંધીનગર\n';
    await PsmFileExportHelper.saveOrShare(
      bytes: Uint8List.fromList(utf8.encode('\uFEFF$csvText')),
      filename: 'id_card_sample_students.csv',
      title: 'id_card_sample_students.csv',
      mimeType: 'text/csv',
    );
  }

  Future<void> _backupLayoutJson() async {
    final payload = {
      'version': 4,
      'cw': _cw,
      'ch': _ch,
      'tplTheme': _tplTheme.code,
      'tplHeaderTitle': _tplHeaderTitle,
      'tplAccentColor': _tplAccentColor.toARGB32(),
      'showPhoto': _showPhoto,
      'showSeal': _showSeal,
      'showSignature': _showSignature,
      'photoCol': _photoCol,
      'paperSize': _paperSize,
      'gapMm': _gapMm,
      'headers': _headers,
      'layouts': _layouts.map((l) => l.toJson()).toList(),
    };
    final bytes = Uint8List.fromList(
      utf8.encode(const JsonEncoder.withIndent('  ').convert(payload)),
    );
    await PsmFileExportHelper.saveOrShare(
      bytes: bytes,
      filename: 'id_card_studio_layout_backup.json',
      title: 'id_card_studio_layout_backup.json',
      mimeType: 'application/json',
    );
    _rebuild(() {
      _statusMessage = 'Saved layout preset JSON backup.';
    });
  }

  Future<void> _restoreLayoutJson() async {
    try {
      final res = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['json'],
        withData: true,
      );
      if (res == null || res.files.isEmpty) return;
      final bytes = res.files.first.bytes;
      if (bytes == null) return;
      final map = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
      _rebuild(() {
        _cw = (map['cw'] as num?)?.toDouble() ?? 840.0;
        _ch = (map['ch'] as num?)?.toDouble() ?? 540.0;
        _tplTheme = BuiltInTemplateTheme.fromCode(map['tplTheme'] as String?);
        _tplHeaderTitle = map['tplHeaderTitle'] as String? ?? '';
        _tplTitleCtrl.text = _tplHeaderTitle;
        if (map['tplAccentColor'] is num) {
          _tplAccentColor = Color((map['tplAccentColor'] as num).toInt());
        }
        _showPhoto = map['showPhoto'] as bool? ?? true;
        _showSeal = map['showSeal'] as bool? ?? false;
        _showSignature = map['showSignature'] as bool? ?? false;
        _photoCol = (map['photoCol'] as num?)?.toInt() ?? 1;
        _paperSize = map['paperSize'] as String? ?? '12x18';
        _gapMm = (map['gapMm'] as num?)?.toDouble() ?? 1.0;
        final rawLayouts = map['layouts'] as List?;
        if (rawLayouts != null && rawLayouts.isNotEmpty) {
          _layouts = rawLayouts
              .map((e) =>
                  CardLayoutSet.fromJson(Map<String, dynamic>.from(e as Map)))
              .toList();
          while (_layouts.length < 4) {
            _layouts.add(_layouts.first.copy());
          }
        }
        _cardWmmCtrl.text =
            (_cw / 10.0).toStringAsFixed(1).replaceAll('.0', '');
        _cardHmmCtrl.text =
            (_ch / 10.0).toStringAsFixed(1).replaceAll('.0', '');
        AutoFitTypographyEngine.clearCache();
        _syncControllersToSelection();
        _statusMessage = 'Restored ID card layout preset from JSON.';
      });
      _pushHistory();
    } catch (e) {
      _rebuild(() => _statusMessage = 'Invalid layout JSON: $e');
    }
  }

  // ==========================================================================
  // DOUBLE-CLICK ON CARD TO INSERT OR EDIT DIRECT TEXT / DATA FIELD
  // ==========================================================================

  void _showDirectTextOrFieldDialog({
    CardFieldItem? existingField,
    int? existingIndex,
    double? clickX,
    double? clickY,
  }) {
    final isEditing = existingField != null;
    bool isDirect = existingField?.isDirectText ?? false;
    int selectedCol = (existingField != null && existingField.col >= 0)
        ? existingField.col.clamp(0, math.max(0, _headers.length - 1)).toInt()
        : (_headers.length > 2 ? 2 : 0);
    final staticCtrl = TextEditingController(
      text: existingField != null
          ? (existingField.isDirectText
              ? existingField.staticText
              : (_curRowIdx < _rows.length &&
                      selectedCol < _rows[_curRowIdx].length
                  ? _rows[_curRowIdx][selectedCol]
                  : ''))
          : '',
    );
    final prefixCtrl =
        TextEditingController(text: existingField?.prefix ?? '');
    double fontSize = existingField?.fontSize ?? 10.0;
    bool bold = existingField?.bold ?? false;

    showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text(
            isEditing
                ? 'Edit Card Text / Database Field'
                : 'Insert Field or Direct Text on Card',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          ),
          content: SizedBox(
            width: 440,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SegmentedButton<bool>(
                    segments: const [
                      ButtonSegment<bool>(
                        value: false,
                        icon: Icon(Icons.storage, size: 16),
                        label: Text('Database / Excel Column'),
                      ),
                      ButtonSegment<bool>(
                        value: true,
                        icon: Icon(Icons.edit_note, size: 16),
                        label: Text('Direct Text (All Cards)'),
                      ),
                    ],
                    selected: {isDirect},
                    onSelectionChanged: (s) {
                      setDialogState(() {
                        isDirect = s.first;
                      });
                    },
                  ),
                  const SizedBox(height: 12),
                  if (isDirect) ...[
                    TextField(
                      controller: staticCtrl,
                      autofocus: true,
                      maxLines: 2,
                      decoration: const InputDecoration(
                        labelText:
                            'Direct Text (Printed on card, e.g. School Name / Year / Label)',
                        hintText: 'Type any Gujarati or English text...',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ] else ...[
                    DropdownButtonFormField<int>(
                      isExpanded: true,
                      value: selectedCol
                          .clamp(0, math.max(0, _headers.length - 1))
                          .toInt(),
                      decoration: const InputDecoration(
                        labelText: 'Select Student Database / Excel Header',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      items: List.generate(
                        _headers.length,
                        (i) => DropdownMenuItem(
                          value: i,
                          child: Text('Col ${i + 1}: ${_headers[i]}'),
                        ),
                      ),
                      onChanged: (v) {
                        if (v == null) return;
                        setDialogState(() {
                          selectedCol = v;
                          if (_curRowIdx < _rows.length &&
                              v < _rows[_curRowIdx].length) {
                            staticCtrl.text = _rows[_curRowIdx][v];
                          }
                        });
                      },
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: staticCtrl,
                      decoration: const InputDecoration(
                        labelText:
                            'Value for Current Student Card (Optional Edit)',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ],
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: prefixCtrl,
                          decoration: const InputDecoration(
                            labelText: 'Prefix Label (e.g. GR No: )',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      if (!isDirect)
                        OutlinedButton(
                          onPressed: () {
                            setDialogState(() {
                              prefixCtrl.text = '${_headers[selectedCol]}: ';
                            });
                          },
                          child: const Text('Use Header'),
                        ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      const Text('Font Size (pt): ',
                          style: TextStyle(fontSize: 12.5)),
                      Expanded(
                        child: Slider(
                          value: fontSize.clamp(5.0, 36.0),
                          min: 5.0,
                          max: 36.0,
                          divisions: 62,
                          label: fontSize.toStringAsFixed(1),
                          onChanged: (v) =>
                              setDialogState(() => fontSize = v),
                        ),
                      ),
                      FilterChip(
                        label: const Text('Bold'),
                        selected: bold,
                        onSelected: (v) => setDialogState(() => bold = v),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          actions: [
            if (isEditing && existingIndex != null)
              TextButton.icon(
                style: TextButton.styleFrom(foregroundColor: Colors.red),
                onPressed: () {
                  Navigator.pop(ctx);
                  _rebuild(() {
                    if (existingIndex >= 0 &&
                        existingIndex < _curLayout.fields.length) {
                      if (_curLayout.fields[existingIndex].locked) {
                        _statusMessage =
                            'Field is locked. Press Ctrl+L to unlock before deleting.';
                        return;
                      }
                      _curLayout.fields.removeAt(existingIndex);
                      _selKey = null;
                      _multiSel = [];
                      _statusMessage = 'Deleted text field from card.';
                    }
                  });
                  _pushHistory();
                },
                icon: const Icon(Icons.delete_outline, size: 16),
                label: const Text('Delete Field'),
              ),
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            FilledButton.icon(
              onPressed: () {
                Navigator.pop(ctx);
                _rebuild(() {
                  if (isEditing && existingField != null) {
                    existingField.isDirectText = isDirect;
                    existingField.prefix = prefixCtrl.text;
                    existingField.fontSize = fontSize;
                    existingField.bold = bold;
                    if (isDirect) {
                      existingField.col = -1;
                      existingField.staticText = staticCtrl.text.isEmpty
                          ? 'Direct Text'
                          : staticCtrl.text;
                    } else {
                      existingField.col = selectedCol;
                      if (_curRowIdx < _rows.length &&
                          selectedCol < _rows[_curRowIdx].length) {
                        _rows[_curRowIdx][selectedCol] = staticCtrl.text;
                      }
                    }
                    AutoFitTypographyEngine.clearCache();
                    _syncControllersToSelection();
                    _statusMessage = 'Updated card field.';
                  } else {
                    final boxW = math.min(440.0, _cw * 0.56).roundToDouble();
                    final boxH = 28.0;
                    final x = ((clickX ?? (_cw * 0.32)) - boxW * 0.25)
                        .clamp(
                          _IdCardStudioViewState.kSafePad,
                          math.max(
                            _IdCardStudioViewState.kSafePad,
                            _cw - boxW - _IdCardStudioViewState.kSafePad,
                          ),
                        )
                        .roundToDouble();
                    final y = ((clickY ?? (_ch * 0.35)) - boxH * 0.5)
                        .clamp(
                          _IdCardStudioViewState.kSafePad,
                          math.max(
                            _IdCardStudioViewState.kSafePad,
                            _ch - boxH - _IdCardStudioViewState.kSafePad,
                          ),
                        )
                        .roundToDouble();
                    for (final l in _layouts) {
                      l.fields.add(
                        CardFieldItem(
                          col: isDirect ? -1 : selectedCol,
                          isDirectText: isDirect,
                          staticText: isDirect
                              ? (staticCtrl.text.isEmpty
                                  ? 'Direct Text'
                                  : staticCtrl.text)
                              : '',
                          x: x,
                          y: y,
                          w: boxW,
                          h: boxH,
                          prefix: prefixCtrl.text,
                          fontSize: fontSize,
                          bold: bold,
                          align: TextAlign.left,
                        ),
                      );
                    }
                    if (!isDirect &&
                        staticCtrl.text.trim().isNotEmpty &&
                        _curRowIdx < _rows.length &&
                        selectedCol < _rows[_curRowIdx].length) {
                      _rows[_curRowIdx][selectedCol] = staticCtrl.text;
                    }
                    _selKey = SelectedItemKey(
                      SelectedItemType.field,
                      _curLayout.fields.length - 1,
                    );
                    _multiSel = [_selKey!];
                    AutoFitTypographyEngine.clearCache();
                    _syncControllersToSelection();
                    _statusMessage = isDirect
                        ? 'Inserted direct text box on card.'
                        : 'Inserted "${_headers[selectedCol]}" field on card.';
                  }
                });
                _pushHistory();
              },
              icon: const Icon(Icons.check, size: 16),
              label: Text(isEditing ? 'Save Changes' : 'Insert on Card'),
            ),
          ],
        ),
      ),
    );
  }

  // ==========================================================================
  // MULTI-OBJECT SELECTION, GROUPING, LOCKING, ALIGNMENT & SIZING
  // ==========================================================================

  bool _isShiftPressed() => HardwareKeyboard.instance.isShiftPressed;

  bool _isCtrlPressed() =>
      HardwareKeyboard.instance.isControlPressed ||
      HardwareKeyboard.instance.isMetaPressed;

  CardBoxItem? _itemForKey(SelectedItemKey? k, [CardLayoutSet? layoutOverride]) {
    if (k == null) return null;
    final layout = layoutOverride ?? _curLayout;
    if (k.type == SelectedItemType.field) {
      if (k.index >= 0 && k.index < layout.fields.length) {
        return layout.fields[k.index];
      }
      return null;
    }
    if (k.type == SelectedItemType.photo) return layout.photo;
    if (k.type == SelectedItemType.signature) return layout.signature;
    return layout.seal;
  }

  List<SelectedItemKey> _effectiveSelectionKeys() {
    if (_multiSel.isNotEmpty) return List<SelectedItemKey>.from(_multiSel);
    if (_selKey != null) return <SelectedItemKey>[_selKey!];
    return const <SelectedItemKey>[];
  }

  List<CardFieldItem> _selectedFieldItems() {
    final keys = _effectiveSelectionKeys();
    final fields = <CardFieldItem>[];
    for (final k in keys) {
      if (k.type == SelectedItemType.field &&
          k.index >= 0 &&
          k.index < _curLayout.fields.length) {
        fields.add(_curLayout.fields[k.index]);
      }
    }
    return fields;
  }

  void _selectObjectOnCanvas(
    SelectedItemKey key, {
    bool forceAdditive = false,
  }) {
    _canvasFocusNode.requestFocus();
    final isShift = HardwareKeyboard.instance.isShiftPressed;
    final isCtrl = HardwareKeyboard.instance.isControlPressed ||
        HardwareKeyboard.instance.isMetaPressed;
    final clickedItem = _itemForKey(key);
    final gid = clickedItem?.groupId;

    final groupKeys = <SelectedItemKey>[key];
    if (gid != null) {
      for (int i = 0; i < _curLayout.fields.length; i++) {
        if (_curLayout.fields[i].groupId == gid) {
          final gk = SelectedItemKey(SelectedItemType.field, i);
          if (!groupKeys.contains(gk)) groupKeys.add(gk);
        }
      }
      if (_curLayout.photo.groupId == gid &&
          !groupKeys
              .contains(const SelectedItemKey(SelectedItemType.photo, 0))) {
        groupKeys.add(const SelectedItemKey(SelectedItemType.photo, 0));
      }
      if (_curLayout.seal.groupId == gid &&
          !groupKeys
              .contains(const SelectedItemKey(SelectedItemType.seal, 0))) {
        groupKeys.add(const SelectedItemKey(SelectedItemType.seal, 0));
      }
      if (_curLayout.signature.groupId == gid &&
          !groupKeys
              .contains(const SelectedItemKey(SelectedItemType.signature, 0))) {
        groupKeys.add(const SelectedItemKey(SelectedItemType.signature, 0));
      }
    }

    _rebuild(() {
      if (isCtrl) {
        if (_multiSel.contains(key)) {
          for (final gk in groupKeys) {
            _multiSel.remove(gk);
          }
          _selKey = _multiSel.isNotEmpty ? _multiSel.last : null;
        } else {
          for (final gk in groupKeys) {
            if (!_multiSel.contains(gk)) _multiSel.add(gk);
          }
          _selKey = key;
        }
      } else if (isShift || forceAdditive) {
        for (final gk in groupKeys) {
          if (!_multiSel.contains(gk)) _multiSel.add(gk);
        }
        _selKey = key;
      } else {
        if (_multiSel.length > 1 && _multiSel.contains(key)) {
          _selKey = key;
        } else {
          _multiSel = List<SelectedItemKey>.from(groupKeys);
          _selKey = key;
        }
      }
      _syncControllersToSelection();
    });
  }

  /// Moves all currently selected unlocked objects smoothly 1:1 with the cursor.
  void _moveSelectedItemsBy(double dx, double dy, {bool enableSnap = false}) {
    final keys = _effectiveSelectionKeys();
    if (keys.isEmpty) return;
    int movedCount = 0;
    int lockedCount = 0;

    for (final k in keys) {
      final it = _itemForKey(k);
      if (it == null) continue;
      if (it.locked) {
        lockedCount++;
        continue;
      }
      it.x += dx;
      it.y += dy;
      if (enableSnap && _snapEnabled && keys.length == 1) {
        final cx = it.x + it.w / 2;
        final cy = it.y + it.h / 2;
        _snapX = (cx - _cw / 2).abs() < 4.5;
        _snapY = (cy - _ch / 2).abs() < 4.5;
        if (_snapX) it.x = (_cw - it.w) / 2;
        if (_snapY) it.y = (_ch - it.h) / 2;
      }
      _clampItemToCard(it, minW: 20, minH: 12, pad: 2);
      movedCount++;
    }
    if (movedCount == 0 && lockedCount > 0) {
      _statusMessage =
          'Selected object(s) are locked. Press Ctrl+L to unlock before moving.';
    }
  }

  /// Resizes selected object(s) from any corner or edge handle smoothly.
  void _resizeSelectedItemsBy({
    required CardBoxItem primary,
    required double dx,
    required double dy,
    required double dw,
    required double dh,
  }) {
    if (primary.locked) {
      _statusMessage =
          'Object is locked. Press Ctrl+L to unlock before resizing.';
      return;
    }
    final keys = _effectiveSelectionKeys();
    if (keys.length <= 1) {
      primary.x += dx;
      primary.y += dy;
      primary.w += dw;
      primary.h += dh;
      _clampItemToCard(primary, minW: 20, minH: 12, pad: 2);
      _syncControllersToSelection();
      return;
    }
    for (final k in keys) {
      final it = _itemForKey(k);
      if (it == null || it.locked) continue;
      it.x += dx;
      it.y += dy;
      it.w += dw;
      it.h += dh;
      _clampItemToCard(it, minW: 20, minH: 12, pad: 2);
    }
    _syncControllersToSelection();
  }

  void _groupSelectedObjects() {
    final keys = _effectiveSelectionKeys();
    if (keys.length < 2) {
      _rebuild(() {
        _statusMessage =
            'Select at least 2 objects (Shift+Click or Ctrl+Click) to group (Ctrl+G).';
      });
      return;
    }
    final gid = _nextGroupId++;
    _rebuild(() {
      for (final k in keys) {
        _itemForKey(k)?.groupId = gid;
      }
      _statusMessage = 'Grouped ${keys.length} objects (Group #$gid).';
    });
    _pushHistory();
  }

  void _ungroupSelectedObjects() {
    final keys = _effectiveSelectionKeys();
    if (keys.isEmpty) return;
    _rebuild(() {
      for (final k in keys) {
        _itemForKey(k)?.groupId = null;
      }
      _statusMessage = 'Ungrouped ${keys.length} object(s).';
    });
    _pushHistory();
  }

  void _toggleLockSelectedObjects() {
    final keys = _effectiveSelectionKeys();
    if (keys.isEmpty) return;
    final items = keys.map(_itemForKey).whereType<CardBoxItem>().toList();
    if (items.isEmpty) return;
    final shouldLock = items.any((it) => !it.locked);
    _rebuild(() {
      for (final it in items) {
        it.locked = shouldLock;
      }
      _statusMessage = shouldLock
          ? 'Locked ${items.length} selected object(s) (Ctrl+L to unlock).'
          : 'Unlocked ${items.length} selected object(s).';
    });
    _pushHistory();
  }

  void _changeSelectedLayersOrder(int delta) {
    final fieldIndices = _effectiveSelectionKeys()
        .where((k) => k.type == SelectedItemType.field)
        .map((k) => k.index)
        .where((idx) => idx >= 0 && idx < _curLayout.fields.length)
        .toList()
      ..sort();
    if (fieldIndices.isEmpty) return;

    _rebuild(() {
      final fields = _curLayout.fields;
      if (delta > 0) {
        for (int i = fieldIndices.length - 1; i >= 0; i--) {
          final idx = fieldIndices[i];
          if (idx < fields.length - 1) {
            final tmp = fields[idx];
            fields[idx] = fields[idx + 1];
            fields[idx + 1] = tmp;
            fieldIndices[i] = idx + 1;
          }
        }
      } else {
        for (int i = 0; i < fieldIndices.length; i++) {
          final idx = fieldIndices[i];
          if (idx > 0) {
            final tmp = fields[idx];
            fields[idx] = fields[idx - 1];
            fields[idx - 1] = tmp;
            fieldIndices[i] = idx - 1;
          }
        }
      }
      _multiSel = fieldIndices
          .map((idx) => SelectedItemKey(SelectedItemType.field, idx))
          .toList();
      _selKey = _multiSel.first;
      _statusMessage = delta > 0
          ? 'Brought selected field(s) forward.'
          : 'Sent selected field(s) backward.';
    });
    _pushHistory();
  }

  void _copySelectedObjects({bool cut = false}) {
    final keys = _effectiveSelectionKeys();
    if (keys.isEmpty) return;
    final copiedFields = <CardFieldItem>[];
    CardPhotoBox? copiedPhoto;
    CardSealBox? copiedSeal;
    CardSignatureBox? copiedSign;

    for (final k in keys) {
      if (k.type == SelectedItemType.field &&
          k.index >= 0 &&
          k.index < _curLayout.fields.length) {
        copiedFields.add(_curLayout.fields[k.index].copy());
      } else if (k.type == SelectedItemType.photo) {
        copiedPhoto = _curLayout.photo.copy();
      } else if (k.type == SelectedItemType.seal) {
        copiedSeal = _curLayout.seal.copy();
      } else if (k.type == SelectedItemType.signature) {
        copiedSign = _curLayout.signature.copy();
      }
    }

    _clipboardPayload = CardClipboardPayload(
      fields: copiedFields,
      photo: copiedPhoto,
      seal: copiedSeal,
      signature: copiedSign,
    );

    if (cut) {
      _deleteSelectedItem(skipConfirmation: true);
      _rebuild(() {
        _statusMessage =
            'Cut ${keys.length} object(s) to clipboard (Ctrl+V to paste).';
      });
    } else {
      _rebuild(() {
        _statusMessage =
            'Copied ${keys.length} object(s) to clipboard (Ctrl+V to paste).';
      });
    }
  }

  void _pasteClipboardObjects() {
    final payload = _clipboardPayload;
    if (payload == null || payload.isEmpty) {
      _rebuild(() {
        _statusMessage =
            'Clipboard is empty. Select object(s) and press Ctrl+C first.';
      });
      return;
    }

    _rebuild(() {
      final newSel = <SelectedItemKey>[];
      for (final f in payload.fields) {
        final copy = f.copy()
          ..locked = false
          ..x = (f.x + 14).clamp(
            _IdCardStudioViewState.kSafePad,
            math.max(_IdCardStudioViewState.kSafePad, _cw - f.w - 8),
          )
          ..y = (f.y + 14).clamp(
            _IdCardStudioViewState.kSafePad,
            math.max(_IdCardStudioViewState.kSafePad, _ch - f.h - 8),
          );
        _curLayout.fields.add(copy);
        newSel.add(
          SelectedItemKey(
              SelectedItemType.field, _curLayout.fields.length - 1),
        );
      }
      if (payload.photo != null) {
        _showPhoto = true;
        _curLayout.photo = payload.photo!.copy();
        newSel.add(const SelectedItemKey(SelectedItemType.photo, 0));
      }
      if (payload.seal != null) {
        _showSeal = true;
        _curLayout.seal = payload.seal!.copy();
        newSel.add(const SelectedItemKey(SelectedItemType.seal, 0));
      }
      if (payload.signature != null) {
        _showSignature = true;
        _curLayout.signature = payload.signature!.copy();
        newSel.add(const SelectedItemKey(SelectedItemType.signature, 0));
      }
      if (newSel.isNotEmpty) {
        _multiSel = newSel;
        _selKey = newSel.last;
        _syncControllersToSelection();
      }
      _statusMessage = 'Pasted ${newSel.length} object(s) onto card.';
    });
    _pushHistory();
  }

  void _duplicateSelectedField() {
    final keys = _effectiveSelectionKeys();
    final selectedFields = _selectedFieldItems();
    if (selectedFields.isEmpty) {
      if (_clipboardPayload != null && !_clipboardPayload!.isEmpty) {
        _pasteClipboardObjects();
      }
      return;
    }
    _rebuild(() {
      final newSel = <SelectedItemKey>[];
      for (final source in selectedFields) {
        final copy = source.copy()
          ..locked = false
          ..y = math.min(
            _ch - source.h - _IdCardStudioViewState.kSafePad,
            source.y + source.h + 6,
          );
        _curLayout.fields.add(copy);
        newSel.add(
          SelectedItemKey(
              SelectedItemType.field, _curLayout.fields.length - 1),
        );
      }
      _multiSel = newSel;
      _selKey = newSel.last;
      _syncControllersToSelection();
      _statusMessage =
          'Duplicated ${selectedFields.length} field(s) onto card (${keys.length} selected).';
    });
    _pushHistory();
  }

  Future<void> _deleteSelectedItem({bool skipConfirmation = false}) async {
    final keys = _effectiveSelectionKeys();
    if (keys.isEmpty) return;

    final unlockedKeys = keys.where((k) {
      final it = _itemForKey(k);
      return it != null && !it.locked;
    }).toList();

    if (unlockedKeys.isEmpty) {
      _rebuild(() {
        _statusMessage =
            'Selected object(s) are locked. Press Ctrl+L to unlock before deleting.';
      });
      return;
    }

    if (!skipConfirmation && unlockedKeys.length > 1 && mounted) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Delete Multiple Objects?'),
          content: Text(
            'Are you sure you want to delete ${unlockedKeys.length} selected objects from the ID card? (You can Undo with Ctrl+Z.)',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Colors.red),
              onPressed: () => Navigator.pop(ctx, true),
              child: Text('Delete (${unlockedKeys.length})'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
    }

    _rebuild(() {
      final fieldIndices = <int>[];
      for (final k in unlockedKeys) {
        if (k.type == SelectedItemType.seal) {
          _showSeal = false;
          _uploadedSealRawBytes = null;
          _uploadedSealBytes = null;
          _cachedSealImage = null;
          _uploadedSealName = '';
        } else if (k.type == SelectedItemType.signature) {
          _showSignature = false;
          _uploadedSignatureRawBytes = null;
          _uploadedSignatureBytes = null;
          _cachedSignatureImage = null;
          _uploadedSignatureName = '';
        } else if (k.type == SelectedItemType.photo) {
          _showPhoto = false;
        } else if (k.type == SelectedItemType.field) {
          fieldIndices.add(k.index);
        }
      }
      fieldIndices.sort((a, b) => b.compareTo(a));
      for (final idx in fieldIndices.toSet()) {
        if (idx >= 0 && idx < _curLayout.fields.length) {
          _curLayout.fields.removeAt(idx);
        }
      }
      _selKey = null;
      _multiSel = [];
      _statusMessage = 'Deleted ${unlockedKeys.length} selected object(s).';
    });
    _pushHistory();
  }

  void _applyToSelectedFields(void Function(CardFieldItem f) mutator,
      [String? status]) {
    final fields = _selectedFieldItems();
    if (fields.isEmpty) return;
    _rebuild(() {
      for (final f in fields) {
        if (!f.locked) mutator(f);
      }
      AutoFitTypographyEngine.clearCache();
      _syncControllersToSelection();
      if (status != null) _statusMessage = status;
    });
    _pushHistory();
  }

  // ==========================================================================
  // CORELDRAW ALIGNMENT, DISTRIBUTION & SAME-SIZE ENGINE
  // ==========================================================================

  void _corelAlign(String mode) {
    final l = _curLayout;
    final targets = _multiSel.length > 1
        ? _multiSel
            .map((k) => MapEntry(k, _itemForKey(k)))
            .where((e) => e.value != null && !e.value!.locked)
            .map((e) => MapEntry(e.key, e.value!))
            .toList()
        : (_selKey != null &&
                _itemForKey(_selKey) != null &&
                !_itemForKey(_selKey)!.locked
            ? [MapEntry(_selKey!, _itemForKey(_selKey)!)]
            : <MapEntry<SelectedItemKey, CardBoxItem>>[]);

    if (targets.isEmpty) {
      _rebuild(() {
        _statusMessage =
            'Select an unlocked field, photo, seal, or principal sign first.';
      });
      return;
    }

    if (mode == 'DIST_V') {
      _distributeVertically();
      return;
    }
    if (mode == 'DIST_H') {
      _distributeHorizontally();
      return;
    }

    _rebuild(() {
      if (targets.length == 1) {
        final entry = targets.first;
        final it = entry.value;
        final isField = entry.key.type == SelectedItemType.field;
        final isV = _cw < _ch;
        final zoneLeft = (!isV &&
                isField &&
                _showPhoto &&
                l.photo.x < _cw / 2 &&
                it.x >= l.photo.x + l.photo.w - 10)
            ? l.photo.x + l.photo.w + 18
            : _IdCardStudioViewState.kSafePad * 1.5;
        final zoneRight = _cw - _IdCardStudioViewState.kSafePad * 1.5;
        final zoneTop = (isV &&
                isField &&
                _showPhoto &&
                l.photo.y < _ch / 2 &&
                it.y >= l.photo.y + l.photo.h - 10)
            ? l.photo.y + l.photo.h + 12
            : (_tplHeaderTitle.trim().isNotEmpty
                ? (_ch * 0.16).roundToDouble()
                : _IdCardStudioViewState.kSafePad * 1.5);
        final zoneBot = _ch - _IdCardStudioViewState.kSafePad * 1.5;

        switch (mode) {
          case 'L':
            it.x = zoneLeft;
            if (it is CardFieldItem) it.align = TextAlign.left;
            break;
          case 'R':
            it.x = math.max(_IdCardStudioViewState.kSafePad, zoneRight - it.w);
            if (it is CardFieldItem) it.align = TextAlign.right;
            break;
          case 'C':
            it.x = ((_cw - it.w) / 2).roundToDouble();
            if (it is CardFieldItem) it.align = TextAlign.center;
            break;
          case 'T':
            it.y = zoneTop;
            break;
          case 'B':
            it.y = math.max(_IdCardStudioViewState.kSafePad, zoneBot - it.h);
            break;
          case 'E':
            it.y = ((_ch - it.h) / 2).roundToDouble();
            break;
          case 'P':
            it.x = ((_cw - it.w) / 2).roundToDouble();
            it.y = ((_ch - it.h) / 2).roundToDouble();
            if (it is CardFieldItem) it.align = TextAlign.center;
            break;
        }
        _clampItemToCard(it);
      } else {
        final anchor = targets.last.value;
        for (final entry in targets) {
          final it = entry.value;
          switch (mode) {
            case 'L':
              it.x = anchor.x;
              if (it is CardFieldItem) it.align = TextAlign.left;
              break;
            case 'R':
              it.x = anchor.x + anchor.w - it.w;
              if (it is CardFieldItem) it.align = TextAlign.right;
              break;
            case 'C':
              it.x = (anchor.x + anchor.w / 2 - it.w / 2).roundToDouble();
              if (it is CardFieldItem) it.align = TextAlign.center;
              break;
            case 'T':
              it.y = anchor.y;
              break;
            case 'B':
              it.y = anchor.y + anchor.h - it.h;
              break;
            case 'E':
              it.y = (anchor.y + anchor.h / 2 - it.h / 2).roundToDouble();
              break;
            case 'P':
              it.x = ((_cw - it.w) / 2).roundToDouble();
              it.y = ((_ch - it.h) / 2).roundToDouble();
              break;
            case 'SAME_W':
              it.w = anchor.w;
              break;
            case 'SAME_H':
              it.h = anchor.h;
              break;
          }
          _clampItemToCard(it);
        }
      }
      AutoFitTypographyEngine.clearCache();
      _syncControllersToSelection();
      _statusMessage =
          'Applied alignment/sizing [$mode] to ${targets.length} object(s).';
    });
    _pushHistory();
  }

  void _distributeHorizontally() {
    final items = _effectiveSelectionKeys()
        .map(_itemForKey)
        .whereType<CardBoxItem>()
        .where((it) => !it.locked)
        .toList();
    if (items.length < 3) {
      _rebuild(() {
        _statusMessage =
            'Select at least 3 unlocked objects to distribute horizontally.';
      });
      return;
    }
    _rebuild(() {
      items.sort((a, b) => a.x.compareTo(b.x));
      final minLeft = items.first.x;
      final maxRight = items.last.x + items.last.w;
      final totalW = items.fold<double>(0, (s, it) => s + it.w);
      final gap =
          ((maxRight - minLeft - totalW) / math.max(1, items.length - 1));
      double cursor = minLeft;
      for (final it in items) {
        it.x = cursor.roundToDouble();
        _clampItemToCard(it);
        cursor += it.w + gap;
      }
      _statusMessage = 'Distributed ${items.length} objects horizontally.';
    });
    _pushHistory();
  }

  void _distributeVertically() {
    final l = _curLayout;
    final list = _multiSel
                .where((k) => k.type == SelectedItemType.field)
                .length >=
            2
        ? _multiSel
            .where((k) => k.type == SelectedItemType.field)
            .map((k) => l.fields[k.index])
            .where((f) => !f.locked)
            .toList()
        : l.fields.where((f) => !f.locked).toList();

    if (list.length < 2) return;
    _rebuild(() {
      list.sort((a, b) => a.y.compareTo(b.y));
      final isV = _cw < _ch;
      final minTop = math.max(
        _IdCardStudioViewState.kSafePad * 1.5,
        math.min(
          list.first.y,
          isV && _showPhoto
              ? l.photo.y + l.photo.h + 14
              : (_ch * 0.16).roundToDouble(),
        ),
      );
      final maxBot = math.min(
        _ch - _IdCardStudioViewState.kSafePad * 1.5,
        math.max(list.last.y + list.last.h, _ch - 26),
      );
      final totalH = list.fold<double>(0, (s, f) => s + f.h);
      final gap = math.max(
        4.0,
        ((maxBot - minTop - totalH) / math.max(1, list.length - 1))
            .floorToDouble(),
      );
      double yCursor = minTop;
      for (final f in list) {
        f.y = yCursor.roundToDouble();
        _clampItemToCard(f);
        yCursor += f.h + gap;
      }
      _statusMessage = 'Distributed ${list.length} fields vertically.';
    });
    _pushHistory();
  }

  void _autoArrangeFields() {
    _rebuild(() {
      final targets = _applyAllSets ? _layouts : [_curLayout];
      for (final l in targets) {
        final auto = _buildAutoLayout();
        for (int i = 0; i < l.fields.length; i++) {
          final f = l.fields[i];
          if (f.locked) continue;
          if (i < auto.fields.length) {
            f.x = auto.fields[i].x;
            f.y = auto.fields[i].y;
            f.w = auto.fields[i].w;
            f.h = auto.fields[i].h;
            f.align = auto.fields[i].align;
          }
        }
        _resolveLayoutCollisions(l, forceStack: true);
      }
      AutoFitTypographyEngine.clearCache();
      _statusMessage =
          'Auto-arranged fields inside safe zone with zero overlaps.';
    });
    _pushHistory();
  }

  CardLayoutSet _buildAutoLayout() {
    final isV = _cw < _ch;
    final startCol = _headers.length > 2 ? 2 : 0;
    final count = math.max(1, _headers.length - startCol);

    if (isV) {
      final photoW = (_cw * 0.37).roundToDouble();
      final photoH = (photoW * 1.24).roundToDouble();
      final photoX = ((_cw - photoW) / 2.0).roundToDouble();
      final photoY = (_ch * 0.14).roundToDouble();
      final availTop = photoY + photoH + (_ch * 0.032).roundToDouble();
      final availH =
          math.max(100.0, _ch - availTop - _IdCardStudioViewState.kSafePad * 2);
      final step = math
          .max(22.0, math.min(_ch * 0.068, (availH / count).floorToDouble()));
      final boxH = math.max(20.0, step - 5.0);
      final padX = math.max(
          _IdCardStudioViewState.kSafePad, (_cw * 0.065).roundToDouble());

      final fields = List.generate(
        _headers.length > startCol ? count : 0,
        (i) => CardFieldItem(
          col: startCol + i,
          x: padX,
          y: math.min(_ch - boxH - _IdCardStudioViewState.kSafePad,
              availTop + i * step),
          w: _cw - padX * 2,
          h: boxH,
          align: TextAlign.center,
          bold: i == 0,
        ),
      );
      final sealDim = (math.min(_cw, _ch) * 0.175).roundToDouble();
      return CardLayoutSet(
        fields: fields,
        photo: CardPhotoBox(x: photoX, y: photoY, w: photoW, h: photoH),
        seal: CardSealBox(
          x: photoX + photoW - (sealDim * 0.55).roundToDouble(),
          y: photoY + photoH - (sealDim * 0.55).roundToDouble(),
          w: sealDim,
          h: sealDim,
        ),
        signature: CardSignatureBox(
          x: (_cw - 160).roundToDouble(),
          y: (_ch - 80).roundToDouble(),
          w: 140,
          h: 60,
        ),
      );
    } else {
      final photoX = (_cw * 0.057).roundToDouble();
      final photoY = (_ch * 0.22).roundToDouble();
      final photoW = (_cw * 0.245).roundToDouble();
      final photoH = (_ch * 0.475).roundToDouble();
      final fieldX = photoX + photoW + (_cw * 0.038).roundToDouble();
      final fieldW =
          math.max(80.0, _cw - fieldX - (_cw * 0.038).roundToDouble());
      final availTop = (_ch * 0.20).roundToDouble();
      final availH = math.max(100.0, _ch - availTop - (_ch * 0.055));
      final step = math
          .max(22.0, math.min(_ch * 0.10, (availH / count).floorToDouble()));
      final boxH = math.max(20.0, step - 5.0);

      final fields = List.generate(
        _headers.length > startCol ? count : 0,
        (i) => CardFieldItem(
          col: startCol + i,
          x: fieldX,
          y: math.min(_ch - boxH - _IdCardStudioViewState.kSafePad,
              availTop + i * step),
          w: fieldW,
          h: boxH,
          align: TextAlign.left,
          bold: i == 0,
        ),
      );
      final sealDim = (math.min(_cw, _ch) * 0.175).roundToDouble();
      return CardLayoutSet(
        fields: fields,
        photo: CardPhotoBox(x: photoX, y: photoY, w: photoW, h: photoH),
        seal: CardSealBox(
          x: photoX + photoW - (sealDim * 0.55).roundToDouble(),
          y: photoY + photoH - (sealDim * 0.55).roundToDouble(),
          w: sealDim,
          h: sealDim,
        ),
        signature: CardSignatureBox(
          x: (_cw - 195).roundToDouble(),
          y: (_ch - 85).roundToDouble(),
          w: 175,
          h: 70,
        ),
      );
    }
  }

  void _clampItemToCard(
    CardBoxItem item, {
    double minW = 20,
    double minH = 12,
    double pad = 2.0,
  }) {
    item.w = item.w.clamp(minW, math.max(minW, _cw - pad * 2)).roundToDouble();
    item.h = item.h.clamp(minH, math.max(minH, _ch - pad * 2)).roundToDouble();
    item.x =
        item.x.clamp(pad, math.max(pad, _cw - pad - item.w)).roundToDouble();
    item.y =
        item.y.clamp(pad, math.max(pad, _ch - pad - item.h)).roundToDouble();
  }

  bool _boxesOverlap(CardBoxItem a, CardBoxItem b, [double gap = 1.0]) {
    return a.x < b.x + b.w - gap &&
        a.x + a.w > b.x + gap &&
        a.y < b.y + b.h - gap &&
        a.y + a.h > b.y + gap;
  }

  void _resolveLayoutCollisions(CardLayoutSet l, {bool forceStack = false}) {
    _clampItemToCard(l.photo, minW: 36, minH: 36, pad: 4);
    _clampItemToCard(l.seal, minW: 18, minH: 18, pad: 2);
    _clampItemToCard(l.signature, minW: 24, minH: 14, pad: 2);
    for (final f in l.fields) {
      _clampItemToCard(f, minW: 24, minH: 14, pad: 4);
    }
    if (!_preventOverlap && !forceStack) return;

    final p = l.photo;
    final isV = _cw < _ch;

    if (_showPhoto) {
      for (final f in l.fields) {
        if (f.locked) continue;
        if (_boxesOverlap(f, p, 2)) {
          if (!isV && p.x < _cw / 2) {
            final rightOfPhoto = p.x + p.w + 16;
            if (_cw - rightOfPhoto - _IdCardStudioViewState.kSafePad >= 90) {
              f.x = rightOfPhoto;
              f.w = math.min(f.w, _cw - f.x - _IdCardStudioViewState.kSafePad);
            }
          } else if (isV && p.y < _ch / 2) {
            f.y = math.max(f.y, p.y + p.h + 12);
          }
          _clampItemToCard(f, minW: 24, minH: 14, pad: 4);
        }
      }
    }

    final sorted = List<CardFieldItem>.from(l.fields)
      ..sort((a, b) => a.y.compareTo(b.y));
    for (int i = 0; i < sorted.length; i++) {
      for (int j = i + 1; j < sorted.length; j++) {
        final a = sorted[i];
        final b = sorted[j];
        if (b.locked) continue;
        final horizOverlap = a.x < b.x + b.w - 4 && a.x + a.w > b.x + 4;
        if (horizOverlap && b.y < a.y + a.h + 3) {
          b.y = a.y + a.h + 4;
        }
      }
    }
  }

  Set<int> _auditOverlappingFields(CardLayoutSet l) {
    final bad = <int>{};
    for (int i = 0; i < l.fields.length; i++) {
      final f = l.fields[i];
      if (f.x < 0 || f.y < 0 || f.x + f.w > _cw + 1 || f.y + f.h > _ch + 1) {
        bad.add(i);
      }
      if (_showPhoto && _boxesOverlap(f, l.photo, 2)) bad.add(i);
      for (int j = i + 1; j < l.fields.length; j++) {
        if (_boxesOverlap(f, l.fields[j], 2)) {
          bad.add(i);
          bad.add(j);
        }
      }
    }
    return bad;
  }

  void _applyNewCardSize(double newCW, double newCH, [String? customMsg]) {
    newCW = newCW.clamp(350.0, 2200.0).roundToDouble();
    newCH = newCH.clamp(250.0, 2200.0).roundToDouble();
    final rx = newCW / _cw;
    final ry = newCH / _ch;
    final rf = math.sqrt(rx * ry);

    _rebuild(() {
      if (_scaleItemsOnResize &&
          ((rx - 1).abs() > 0.005 || (ry - 1).abs() > 0.005)) {
        for (final l in _layouts) {
          l.photo
            ..x = (l.photo.x * rx).roundToDouble()
            ..y = (l.photo.y * ry).roundToDouble()
            ..w = math.max(40.0, (l.photo.w * rx).roundToDouble())
            ..h = math.max(40.0, (l.photo.h * ry).roundToDouble());
          l.seal
            ..x = (l.seal.x * rx).roundToDouble()
            ..y = (l.seal.y * ry).roundToDouble()
            ..w = math.max(20.0, (l.seal.w * rf).roundToDouble())
            ..h = math.max(20.0, (l.seal.h * rf).roundToDouble());
          l.signature
            ..x = (l.signature.x * rx).roundToDouble()
            ..y = (l.signature.y * ry).roundToDouble()
            ..w = math.max(24.0, (l.signature.w * rx).roundToDouble())
            ..h = math.max(14.0, (l.signature.h * ry).roundToDouble());
          for (final f in l.fields) {
            f
              ..x = (f.x * rx).roundToDouble()
              ..y = (f.y * ry).roundToDouble()
              ..w = math.max(44.0, (f.w * rx).roundToDouble())
              ..h = math.max(16.0, (f.h * ry).roundToDouble())
              ..fontSize = ((f.fontSize * rf * 2).roundToDouble() / 2)
                  .clamp(4.0, 60.0);
          }
        }
      }
      _cw = newCW;
      _ch = newCH;
      _cardWmmCtrl.text = (_cw / 10.0).toStringAsFixed(1).replaceAll('.0', '');
      _cardHmmCtrl.text = (_ch / 10.0).toStringAsFixed(1).replaceAll('.0', '');
      for (final l in _layouts) {
        _resolveLayoutCollisions(l);
      }
      AutoFitTypographyEngine.clearCache();
      _syncControllersToSelection();
      _statusMessage = customMsg ??
          'Card size updated to ${(_cw / 10).toStringAsFixed(1)} × ${(_ch / 10).toStringAsFixed(1)} mm.';
    });
    _pushHistory();
  }

  // ==========================================================================
  // UNDO / REDO HISTORY (PRESERVING SELECTION STATE)
  // ==========================================================================

  void _pushHistory() {
    if (_isRestoringHistory) return;
    final snap = jsonEncode({
      'cw': _cw,
      'ch': _ch,
      'showPhoto': _showPhoto,
      'showSeal': _showSeal,
      'showSignature': _showSignature,
      'layouts': _layouts.map((l) => l.toJson()).toList(),
      'selKey': _selKey?.toJson(),
      'multiSel': _multiSel.map((k) => k.toJson()).toList(),
    });
    if (_historyIdx >= 0 && _history[_historyIdx] == snap) return;
    if (_historyIdx < _history.length - 1) {
      _history.removeRange(_historyIdx + 1, _history.length);
    }
    _history.add(snap);
    if (_history.length > 45) _history.removeAt(0);
    _historyIdx = _history.length - 1;
  }

  void _restoreHistory(int delta) {
    final target = _historyIdx + delta;
    if (target < 0 || target >= _history.length) return;
    _isRestoringHistory = true;
    _historyIdx = target;
    final data = jsonDecode(_history[_historyIdx]) as Map<String, dynamic>;
    _rebuild(() {
      _cw = (data['cw'] as num).toDouble();
      _ch = (data['ch'] as num).toDouble();
      _showPhoto = data['showPhoto'] as bool? ?? true;
      _showSeal = data['showSeal'] as bool? ?? false;
      _showSignature = data['showSignature'] as bool? ?? false;
      _layouts = (data['layouts'] as List)
          .map((e) =>
              CardLayoutSet.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
      if (data['selKey'] is Map) {
        _selKey = SelectedItemKey.fromJson(
            Map<String, dynamic>.from(data['selKey'] as Map));
      } else {
        _selKey = null;
      }
      if (data['multiSel'] is List) {
        _multiSel = (data['multiSel'] as List)
            .whereType<Map>()
            .map((m) => SelectedItemKey.fromJson(Map<String, dynamic>.from(m)))
            .where((k) => _itemForKey(k) != null)
            .toList();
      } else {
        _multiSel = _selKey != null ? [_selKey!] : [];
      }
      if (_selKey != null && _itemForKey(_selKey) == null) {
        _selKey = _multiSel.isNotEmpty ? _multiSel.first : null;
      }
      _cardWmmCtrl.text = (_cw / 10.0).toStringAsFixed(1).replaceAll('.0', '');
      _cardHmmCtrl.text = (_ch / 10.0).toStringAsFixed(1).replaceAll('.0', '');
      AutoFitTypographyEngine.clearCache();
      _syncControllersToSelection();
      _statusMessage = delta < 0 ? 'Undid last change.' : 'Redid change.';
    });
    _isRestoringHistory = false;
  }

  void _syncControllersToSelection() {
    final p = _curLayout.photo;
    final s = _curLayout.seal;
    final sig = _curLayout.signature;
    _photoWmmCtrl.text = (p.w / 10.0).toStringAsFixed(1);
    _photoHmmCtrl.text = (p.h / 10.0).toStringAsFixed(1);
    _sealWmmCtrl.text = (s.w / 10.0).toStringAsFixed(1);
    _sealHmmCtrl.text = (s.h / 10.0).toStringAsFixed(1);
    _signWmmCtrl.text = (sig.w / 10.0).toStringAsFixed(1);
    _signHmmCtrl.text = (sig.h / 10.0).toStringAsFixed(1);

    final item = _itemForKey(_selKey);
    if (item is CardFieldItem) {
      _fieldWmmCtrl.text = (item.w / 10.0).toStringAsFixed(1);
      _fieldHmmCtrl.text = (item.h / 10.0).toStringAsFixed(1);
      if (_prefixCtrl.text != item.prefix) {
        _prefixCtrl.text = item.prefix;
      }
      final fsText =
          item.fontSize.toStringAsFixed(2).replaceAll(RegExp(r'\.?0+$'), '');
      if (_fontSizeCtrl.text != fsText) _fontSizeCtrl.text = fsText;

      final minFsText = item.minFontSize
          .toStringAsFixed(2)
          .replaceAll(RegExp(r'\.?0+$'), '');
      if (_minFontSizeCtrl.text != minFsText) _minFontSizeCtrl.text = minFsText;

      final lhText =
          item.lineHeight.toStringAsFixed(2).replaceAll(RegExp(r'\.?0+$'), '');
      if (_lineHeightCtrl.text != lhText) _lineHeightCtrl.text = lhText;

      final lsText = item.letterSpacing
          .toStringAsFixed(2)
          .replaceAll(RegExp(r'\.?0+$'), '');
      if (_letterSpacingCtrl.text != lsText) _letterSpacingCtrl.text = lsText;

      if (item.isDirectText) {
        if (_directTextCtrl.text != item.staticText) {
          _directTextCtrl.text = item.staticText;
        }
        if (_liveCellCtrl.text != item.staticText) {
          _liveCellCtrl.text = item.staticText;
        }
      } else if (_curRowIdx >= 0 &&
          _curRowIdx < _rows.length &&
          item.col >= 0 &&
          item.col < _rows[_curRowIdx].length) {
        final v = _rows[_curRowIdx][item.col];
        if (_liveCellCtrl.text != v) _liveCellCtrl.text = v;
        if (_directTextCtrl.text != v) _directTextCtrl.text = v;
      }
    }
  }

  void _addField({bool isDirectText = false}) {
    final l = _curLayout;
    final nextCol = isDirectText
        ? -1
        : math.min(_headers.length - 1, math.max(0, l.fields.length + 2));
    final lastF = l.fields.isNotEmpty ? l.fields.last : null;
    final isV = _cw < _ch;
    final defaultW = math
        .min(_cw * (isV ? 0.84 : 0.62), _cw - _IdCardStudioViewState.kSafePad * 2)
        .roundToDouble();
    final defaultX = ((_cw - defaultW) / 2.0).roundToDouble();
    final defaultPrefix = (!isDirectText &&
            nextCol >= 2 &&
            nextCol < _headers.length)
        ? _autoPrefixFor(headerName: _headers[nextCol])
        : '';

    _rebuild(() {
      for (final layout in _layouts) {
        layout.fields.add(
          CardFieldItem(
            col: nextCol,
            isDirectText: isDirectText,
            staticText: isDirectText ? 'Direct Text' : '',
            x: lastF?.x ?? defaultX,
            y: lastF != null
                ? math.min(_ch - 36, lastF.y + lastF.h + 5)
                : ((_ch - 28.0) / 2.0).roundToDouble(),
            w: lastF?.w ?? defaultW,
            h: lastF?.h ?? 28,
            prefix: defaultPrefix,
            fontFamily:
                _defaultStyleTemplate?.fontFamily ?? 'NotoSansGujaratiLocal',
            fontSize: _defaultStyleTemplate?.fontSize ?? 9.5,
            minFontSize: _defaultStyleTemplate?.minFontSize ?? 4.5,
            autoFit: _defaultStyleTemplate?.autoFit ?? true,
            textMode: _defaultStyleTemplate?.textMode ?? TextFitMode.auto,
            align: _defaultStyleTemplate?.align ??
                (isV ? TextAlign.center : TextAlign.left),
            valign: _defaultStyleTemplate?.valign ?? VerticalTextAlign.middle,
            color: _defaultStyleTemplate?.color ?? const Color(0xFF0F172A),
            bold: _defaultStyleTemplate?.bold ?? false,
            italic: _defaultStyleTemplate?.italic ?? false,
            underline: _defaultStyleTemplate?.underline ?? false,
          ),
        );
      }
      if (_preventOverlap) {
        _resolveLayoutCollisions(l, forceStack: true);
      }
      _selKey = SelectedItemKey(SelectedItemType.field, l.fields.length - 1);
      _multiSel = [_selKey!];
      AutoFitTypographyEngine.clearCache();
      _syncControllersToSelection();
      _statusMessage = isDirectText
          ? 'Added direct text box onto card.'
          : 'Added "${nextCol >= 0 && nextCol < _headers.length ? _headers[nextCol] : "DB Field"}" onto card.';
    });
    _pushHistory();
  }

  void _jumpToLongestRow() {
    if (_rows.isEmpty) return;
    int bestIdx = 0;
    int maxLen = -1;
    for (int i = 0; i < _rows.length; i++) {
      final len = _rows[i]
          .skip(2)
          .fold<int>(0, (sum, cell) => sum + cell.trim().length);
      if (len > maxLen) {
        maxLen = len;
        bestIdx = i;
      }
    }
    _rebuild(() {
      _curRowIdx = bestIdx;
      _syncControllersToSelection();
      _statusMessage =
          'Jumped to Record #${bestIdx + 1} (longest text: $maxLen chars) — Auto-Fit scales the font automatically!';
    });
  }

  // ==========================================================================
  // FOCUS-AWARE KEYBOARD SHORTCUT ROUTER
  // ==========================================================================

  bool _isEditableTextFocused() {
    final primary = FocusManager.instance.primaryFocus;
    final ctx = primary?.context;
    if (ctx == null) return false;
    if (ctx.widget is EditableText) return true;
    return ctx.findAncestorWidgetOfExactType<EditableText>() != null;
  }

  KeyEventResult _handleGlobalKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    final isShift = HardwareKeyboard.instance.isShiftPressed;

    if (key == LogicalKeyboardKey.f1 ||
        (!_isEditableTextFocused() &&
            isShift &&
            key == LogicalKeyboardKey.slash)) {
      _showShortcutsHelpDialog();
      return KeyEventResult.handled;
    }

    if (_isEditableTextFocused()) {
      if (key == LogicalKeyboardKey.escape) {
        FocusManager.instance.primaryFocus?.unfocus();
        _canvasFocusNode.requestFocus();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }

    if (_studentListFocusNode.hasFocus) {
      return _handleStudentListKeyEvent(node, event);
    }

    return _handleCanvasKeyEvent(node, event);
  }

  KeyEventResult _handleStudentListKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (_isEditableTextFocused()) return KeyEventResult.ignored;

    final key = event.logicalKey;
    final isCtrl = HardwareKeyboard.instance.isControlPressed ||
        HardwareKeyboard.instance.isMetaPressed;
    final isShift = HardwareKeyboard.instance.isShiftPressed;

    if (isCtrl && key == LogicalKeyboardKey.keyA) {
      if (isShift) {
        _clearStudentSelection();
      } else {
        _selectAllVisibleStudents();
      }
      return KeyEventResult.handled;
    }
    if (isCtrl && key == LogicalKeyboardKey.keyI) {
      _invertVisibleStudentSelection();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter) {
      _rebuild(() {
        if (_selectedStudentIndices.isNotEmpty) {
          _curRowIdx = _selectedStudentIndices.first;
          _syncControllersToSelection();
          _statusMessage = 'Previewing Student #${_curRowIdx + 1}.';
        }
      });
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowUp) {
      _navigateStudentListByOffset(-1, extendSelection: isShift);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowDown) {
      _navigateStudentListByOffset(1, extendSelection: isShift);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.escape) {
      _clearStudentSelection();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  KeyEventResult _handleCanvasKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (_isEditableTextFocused()) return KeyEventResult.ignored;

    final key = event.logicalKey;
    final isCtrl = HardwareKeyboard.instance.isControlPressed ||
        HardwareKeyboard.instance.isMetaPressed;
    final isShift = HardwareKeyboard.instance.isShiftPressed;

    if (key == LogicalKeyboardKey.escape) {
      _rebuild(() {
        _selKey = null;
        _multiSel = [];
        _statusMessage = 'Cleared canvas selection.';
      });
      return KeyEventResult.handled;
    }

    double step = 1.0;
    if (isShift) {
      step = 10.0;
    } else if (isCtrl) {
      step = 0.25;
    }
    double dx = 0, dy = 0;
    if (key == LogicalKeyboardKey.arrowLeft) dx = -step;
    if (key == LogicalKeyboardKey.arrowRight) dx = step;
    if (key == LogicalKeyboardKey.arrowUp) dy = -step;
    if (key == LogicalKeyboardKey.arrowDown) dy = step;
    if (dx != 0 || dy != 0) {
      if (_effectiveSelectionKeys().isNotEmpty) {
        _rebuild(() {
          _moveSelectedItemsBy(dx, dy);
          _syncControllersToSelection();
        });
        _pushHistory();
        return KeyEventResult.handled;
      }
    }

    if (isCtrl) {
      if (key == LogicalKeyboardKey.keyZ) {
        _restoreHistory(isShift ? 1 : -1);
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.keyY) {
        _restoreHistory(1);
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.keyA) {
        _rebuild(() {
          _multiSel = <SelectedItemKey>[
            for (int i = 0; i < _curLayout.fields.length; i++)
              SelectedItemKey(SelectedItemType.field, i),
            if (_showPhoto) const SelectedItemKey(SelectedItemType.photo, 0),
            if (_showSeal) const SelectedItemKey(SelectedItemType.seal, 0),
            if (_showSignature)
              const SelectedItemKey(SelectedItemType.signature, 0),
          ];
          if (_multiSel.isNotEmpty) _selKey = _multiSel.first;
          _syncControllersToSelection();
          _statusMessage =
              'Selected all ${_multiSel.length} design objects on card.';
        });
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.keyC) {
        _copySelectedObjects(cut: false);
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.keyX) {
        _copySelectedObjects(cut: true);
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.keyV) {
        _pasteClipboardObjects();
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.keyD) {
        _duplicateSelectedField();
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.keyG) {
        if (isShift) {
          _ungroupSelectedObjects();
        } else {
          _groupSelectedObjects();
        }
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.keyL) {
        _toggleLockSelectedObjects();
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.keyE) {
        if (isShift) {
          _distributeVertically();
        } else {
          _corelAlign('E');
        }
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.keyR) {
        _corelAlign('R');
        return KeyEventResult.handled;
      }
    } else {
      if (key == LogicalKeyboardKey.keyC) {
        _corelAlign('C');
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.keyE) {
        if (isShift) {
          _distributeVertically();
        } else {
          _corelAlign('E');
        }
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.keyL) {
        _corelAlign('L');
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.keyR) {
        _corelAlign('R');
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.keyT) {
        _corelAlign('T');
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.keyB) {
        _corelAlign('B');
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.keyP) {
        _corelAlign('P');
        return KeyEventResult.handled;
      }
    }

    if (key == LogicalKeyboardKey.delete ||
        key == LogicalKeyboardKey.backspace) {
      if (_effectiveSelectionKeys().isNotEmpty) {
        _deleteSelectedItem();
        return KeyEventResult.handled;
      }
    }

    return KeyEventResult.ignored;
  }

  // ==========================================================================
  // PRINT / EXPORT RECORD SCOPE & PROGRESS WITH CANCEL
  // ==========================================================================

  List<List<String>> _activeRangeRows() {
    if (_rows.isEmpty) return const [];
    switch (_printScope) {
      case PrintRecordScope.all:
        return _rows;
      case PrintRecordScope.selectedOnly:
        final sorted = _selectedStudentIndices
            .where((i) => i >= 0 && i < _rows.length)
            .toList()
          ..sort();
        if (sorted.isEmpty) {
          return [_rows[_curRowIdx.clamp(0, _rows.length - 1).toInt()]];
        }
        return sorted.map((i) => _rows[i]).toList();
      case PrintRecordScope.currentOnly:
        return [_rows[_curRowIdx.clamp(0, _rows.length - 1).toInt()]];
      case PrintRecordScope.filteredOnly:
        final vis = _filteredStudentRowIndices();
        if (vis.isEmpty) {
          return [_rows[_curRowIdx.clamp(0, _rows.length - 1).toInt()]];
        }
        return vis.map((i) => _rows[i]).toList();
      case PrintRecordScope.fromToRange:
        final s = (_rangeFrom - 1).clamp(0, _rows.length - 1).toInt();
        final e = (_rangeTo - 1).clamp(s, _rows.length - 1).toInt();
        return _rows.sublist(s, e + 1);
    }
  }

  SheetGeometry _computeSheetGeometry() {
    final cw = _cw / 10.0;
    final ch = _ch / 10.0;
    final paperMap = <String, List<double>>{
      '12x18': [457.2, 304.8],
      'A4': [210.0, 297.0],
      'A4L': [297.0, 210.0],
      'A3': [420.0, 297.0],
      'Letter': [215.9, 279.4],
      'Single': [cw, ch],
    };
    final p = paperMap[_paperSize] ?? paperMap['12x18']!;
    final isSingle = _paperSize == 'Single';
    final g = isSingle ? 0.0 : math.max(0.0, _gapMm);
    final margin = isSingle ? 0.0 : 4.0;
    final cols = isSingle
        ? 1
        : math.max(1, ((p[0] - 2 * margin + g) / (cw + g)).floor());
    final rws = isSingle
        ? 1
        : math.max(1, ((p[1] - 2 * margin + g) / (ch + g)).floor());
    final per = cols * rws;
    final totalActive = math.max(1, _activeRangeRows().length);
    final pages = math.max(1, (totalActive / per).ceil());
    return SheetGeometry(
      paperWmm: p[0],
      paperHmm: p[1],
      cardWmm: cw,
      cardHmm: ch,
      gapMm: g,
      cols: cols,
      rows: rws,
      perSheet: per,
      x0Mm: (p[0] - (cols * cw + (cols - 1) * g)) / 2.0,
      y0Mm: (p[1] - (rws * ch + (rws - 1) * g)) / 2.0,
      totalPages: pages,
    );
  }

  Future<void> _exportCurrentSheetPng({
    bool singleCardOnly = false,
    bool allSheetsInScope = false,
  }) async {
    if (_isExporting) return;
    final geom = _computeSheetGeometry();
    final activeRows = _activeRangeRows();

    if (allSheetsInScope && !singleCardOnly && geom.totalPages > 1) {
      _rebuild(() {
        _isExporting = true;
        _cancelExportRequested = false;
        _exportProcessedCount = 0;
        _exportTotalCount = activeRows.length;
        _statusMessage =
            'Exporting ${geom.totalPages} sheets (${activeRows.length} cards)...';
      });

      final origPage = _sheetPageIdx;
      for (int p = 0; p < geom.totalPages; p++) {
        if (_cancelExportRequested || !mounted) break;
        _rebuild(() {
          _sheetPageIdx = p;
        });
        await WidgetsBinding.instance.endOfFrame;
        if (_cancelExportRequested || !mounted) break;

        final boundary = _sheetBoundaryKey.currentContext?.findRenderObject()
            as RenderRepaintBoundary?;
        if (boundary != null) {
          final pixelRatio = _exportDpi / 96.0;
          final image = await boundary.toImage(pixelRatio: pixelRatio);
          final byteData =
              await image.toByteData(format: ui.ImageByteFormat.png);
          image.dispose();
          if (byteData != null) {
            final bytes = byteData.buffer.asUint8List();
            final fileName =
                'id-cards-${_printScope.code}-$_paperSize-sheet${p + 1}of${geom.totalPages}.png';
            widget.onExportSheetPng?.call(bytes, fileName);
          }
        }
        _rebuild(() {
          _exportProcessedCount =
              math.min(activeRows.length, (p + 1) * geom.perSheet);
        });
      }

      final wasCancelled = _cancelExportRequested;
      _rebuild(() {
        _isExporting = false;
        _cancelExportRequested = false;
        _sheetPageIdx = origPage.clamp(0, math.max(0, geom.totalPages - 1)).toInt();
        _statusMessage = wasCancelled
            ? 'Export cancelled after $_exportProcessedCount of $_exportTotalCount card(s).'
            : 'Completed export of $_exportProcessedCount card(s) across ${geom.totalPages} sheet(s).';
      });
      return;
    }

    try {
      _rebuild(() {
        _isExporting = true;
        if (singleCardOnly) _isCapturingCleanSingleCard = true;
        _cancelExportRequested = false;
        _exportTotalCount = singleCardOnly
            ? 1
            : math.min(
                geom.perSheet,
                math.max(0, activeRows.length - _sheetPageIdx * geom.perSheet),
              );
        _exportProcessedCount = 0;
      });
      await WidgetsBinding.instance.endOfFrame;

      final key =
          singleCardOnly ? _singleCardBoundaryKey : _sheetBoundaryKey;
      final boundary =
          key.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) {
        _rebuild(() {
          _isExporting = false;
          _isCapturingCleanSingleCard = false;
        });
        return;
      }
      final pixelRatio = _exportDpi / 96.0;
      final image = await boundary.toImage(pixelRatio: pixelRatio);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      if (singleCardOnly) {
        _rebuild(() => _isCapturingCleanSingleCard = false);
      }
      if (byteData == null) {
        _rebuild(() => _isExporting = false);
        return;
      }
      final bytes = byteData.buffer.asUint8List();
      final fileName = singleCardOnly
          ? 'id-card-record-${_curRowIdx + 1}-${(_cw / 10).toStringAsFixed(0)}x${(_ch / 10).toStringAsFixed(0)}mm.png'
          : 'id-cards-${_printScope.code}-$_paperSize-${(_cw / 10).toStringAsFixed(0)}x${(_ch / 10).toStringAsFixed(0)}mm-sheet${_sheetPageIdx + 1}.png';
      widget.onExportSheetPng?.call(bytes, fileName);
      _rebuild(() {
        _exportProcessedCount = _exportTotalCount;
        _isExporting = false;
        _statusMessage =
            'Exported $fileName (${bytes.lengthInBytes ~/ 1024} KB at $_exportDpi DPI • Scope: ${_printScope.label}).';
      });
    } catch (e) {
      _rebuild(() {
        _isExporting = false;
        _isCapturingCleanSingleCard = false;
        _statusMessage = 'Export error: $e';
      });
    }
  }

  Future<void> _exportCurrentSheetPdf({
    bool singleCardOnly = false,
    bool allSheetsInScope = false,
  }) async {
    if (_isExporting) return;
    final geom = _computeSheetGeometry();
    final activeRows = _activeRangeRows();
    final doc = pw.Document();

    try {
      if (singleCardOnly) {
        _rebuild(() {
          _isExporting = true;
          _isCapturingCleanSingleCard = true;
          _cancelExportRequested = false;
          _exportTotalCount = 1;
          _exportProcessedCount = 0;
          _statusMessage = 'Generating clean Single ID Card PDF (without editor grid)...';
        });
        await WidgetsBinding.instance.endOfFrame;

        final boundary = _singleCardBoundaryKey.currentContext
            ?.findRenderObject() as RenderRepaintBoundary?;
        if (boundary == null) {
          _rebuild(() {
            _isExporting = false;
            _isCapturingCleanSingleCard = false;
          });
          return;
        }
        final pixelRatio = _exportDpi / 96.0;
        final image = await boundary.toImage(pixelRatio: pixelRatio);
        final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
        image.dispose();
        _rebuild(() => _isCapturingCleanSingleCard = false);
        if (byteData == null) {
          _rebuild(() => _isExporting = false);
          return;
        }
        final pngBytes = byteData.buffer.asUint8List();
        final pageFmt = PdfPageFormat(
          (_cw / 10.0) * PdfPageFormat.mm,
          (_ch / 10.0) * PdfPageFormat.mm,
        );
        doc.addPage(
          pw.Page(
            pageFormat: pageFmt,
            margin: pw.EdgeInsets.zero,
            build: (_) => pw.Image(
              pw.MemoryImage(pngBytes),
              fit: pw.BoxFit.fill,
            ),
          ),
        );
      } else {
        final totalPagesToExport = allSheetsInScope ? geom.totalPages : 1;
        final startPage = allSheetsInScope ? 0 : _sheetPageIdx;
        final origPage = _sheetPageIdx;
        _rebuild(() {
          _isExporting = true;
          _cancelExportRequested = false;
          _exportProcessedCount = 0;
          _exportTotalCount = allSheetsInScope
              ? activeRows.length
              : math.min(
                  geom.perSheet,
                  math.max(0, activeRows.length - _sheetPageIdx * geom.perSheet),
                );
          _statusMessage =
              'Generating ID Card PDF ($totalPagesToExport sheet(s), grid hidden)...';
        });

        final pageFmt = PdfPageFormat(
          geom.paperWmm * PdfPageFormat.mm,
          geom.paperHmm * PdfPageFormat.mm,
        );

        for (int i = 0; i < totalPagesToExport; i++) {
          if (_cancelExportRequested || !mounted) break;
          final p = startPage + i;
          _rebuild(() => _sheetPageIdx = p);
          await WidgetsBinding.instance.endOfFrame;
          if (_cancelExportRequested || !mounted) break;

          final boundary = _sheetBoundaryKey.currentContext?.findRenderObject()
              as RenderRepaintBoundary?;
          if (boundary != null) {
            final pixelRatio = _exportDpi / 96.0;
            final image = await boundary.toImage(pixelRatio: pixelRatio);
            final byteData =
                await image.toByteData(format: ui.ImageByteFormat.png);
            image.dispose();
            if (byteData != null) {
              final pngBytes = byteData.buffer.asUint8List();
              doc.addPage(
                pw.Page(
                  pageFormat: pageFmt,
                  margin: pw.EdgeInsets.zero,
                  build: (_) => pw.Image(
                    pw.MemoryImage(pngBytes),
                    fit: pw.BoxFit.fill,
                  ),
                ),
              );
            }
          }
          _rebuild(() {
            _exportProcessedCount = math.min(
              _exportTotalCount,
              (i + 1) * geom.perSheet,
            );
          });
        }
        _rebuild(() {
          _sheetPageIdx =
              origPage.clamp(0, math.max(0, geom.totalPages - 1)).toInt();
        });
      }

      final pdfBytes = await doc.save();
      final pdfName = singleCardOnly
          ? 'id-card-record-${_curRowIdx + 1}-${(_cw / 10).toStringAsFixed(0)}x${(_ch / 10).toStringAsFixed(0)}mm.pdf'
          : (allSheetsInScope
              ? 'id-cards-${_printScope.code}-$_paperSize-all-${geom.totalPages}sheets.pdf'
              : 'id-cards-${_printScope.code}-$_paperSize-sheet${_sheetPageIdx + 1}.pdf');

      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(
          _IdCardStudioViewState._prefKeyLastPdfB64,
          base64Encode(pdfBytes),
        );
        await prefs.setString(
          _IdCardStudioViewState._prefKeyLastPdfName,
          pdfName,
        );
      } catch (_) {}

      await PsmFileExportHelper.saveOrShare(
        bytes: pdfBytes,
        filename: pdfName,
        title: pdfName,
        mimeType: 'application/pdf',
      );

      _rebuild(() {
        _lastSavedPdfBytes = pdfBytes;
        _lastSavedPdfName = pdfName;
        _isExporting = false;
        _isCapturingCleanSingleCard = false;
        _statusMessage =
            'Exported & saved PDF "$pdfName" (${pdfBytes.lengthInBytes ~/ 1024} KB • Grid excluded from print).';
      });
    } catch (e) {
      _rebuild(() {
        _isExporting = false;
        _isCapturingCleanSingleCard = false;
        _statusMessage = 'PDF export error: $e';
      });
    }
  }

  Future<void> _openLastSavedPdf() async {
    final bytes = _lastSavedPdfBytes;
    if (bytes == null || bytes.isEmpty) return;
    await PsmFileExportHelper.saveOrShare(
      bytes: bytes,
      filename: _lastSavedPdfName,
      title: _lastSavedPdfName,
      mimeType: 'application/pdf',
    );
  }

  void _showCsvImportDialog() {
    final ctrl = TextEditingController();
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Paste CSV or Excel Rows'),
        content: SizedBox(
          width: 520,
          child: TextField(
            controller: ctrl,
            maxLines: 10,
            decoration: const InputDecoration(
              hintText:
                  'Sr No,Photo,Student Name,Class,Roll No,GR No,Mobile\n1,101,Patel Aarav,Std 6,1,1045,9876543210',
              border: OutlineInputBorder(),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final lines = ctrl.text
                  .split(RegExp(r'\r?\n'))
                  .where((l) => l.trim().isNotEmpty)
                  .toList();
              if (lines.length >= 2) {
                final delimiter = lines.first.contains('\t') ? '\t' : ',';
                final parsed = _normalizeImportedTable(lines
                    .map((l) => _splitDelimitedLine(l, delimiter))
                    .toList());
                if (parsed.rows.isEmpty) {
                  Navigator.pop(ctx);
                  return;
                }
                _rebuild(() {
                  _headers = parsed.headers;
                  _rows = parsed.rows;
                  _excelDataSourceActive = true;
                  _excelSourceFileName = 'Pasted data';
                  _filteredIndicesDirty = true;
                  _selectedStudentIndices
                    ..clear()
                    ..addAll(List<int>.generate(_rows.length, (i) => i));
                  _lastClickedStudentIdx = 0;
                  _curRowIdx = 0;
                  _rangeFrom = 1;
                  _rangeTo = _rows.length;
                  _rangeFromCtrl.text = '1';
                  _rangeToCtrl.text = '${_rows.length}';
                  _statusMessage =
                      'Imported ${_rows.length} card records from pasted data.';
                });
                _pushHistory();
              }
              Navigator.pop(ctx);
            },
            child: const Text('Load Records'),
          ),
        ],
      ),
    );
  }

  void _showShortcutsHelpDialog() {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.keyboard_alt_outlined, color: Color(0xFF0D7480)),
            SizedBox(width: 8),
            Flexible(child: Text('ID Card Studio Pro — Keyboard Shortcuts (F1 / ?)')),
          ],
        ),
        content: const SizedBox(
          width: 620,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '1. Student Selection Shortcuts (When Students Panel is Active)',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5),
                ),
                SizedBox(height: 6),
                Text('• Click : Select one student & preview card'),
                Text('• Ctrl + Click : Add or remove one student from selection'),
                Text(
                    '• Shift + Click : Select complete range between previous & clicked student'),
                Text(
                    '• Ctrl + Shift + Click : Add range without clearing existing selection'),
                Text('• Ctrl + A : Select all visible students'),
                Text('• Ctrl + Shift + A : Clear student selection'),
                Text('• Ctrl + I : Invert student selection'),
                Text('• Enter : Preview selected student'),
                Text('• Up / Down : Move to previous or next student'),
                Text('• Shift + Up / Down : Extend student selection'),
                Divider(height: 22),
                Text(
                  '2. Canvas & Multi-Object Shortcuts (When Card Canvas is Active)',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5),
                ),
                SizedBox(height: 6),
                Text('• Double-Click on Card : Insert or edit direct text / DB field'),
                Text('• Drag Any Corner Handle : Resize Photo, Seal, Principal Sign, or Field'),
                Text('• Ctrl + A : Select all design objects on the card'),
                Text('• Shift + Click : Add object to multi-selection'),
                Text('• Ctrl + Click : Toggle object in multi-selection'),
                Text('• Ctrl + C / Ctrl + X / Ctrl + V : Copy / Cut / Paste objects'),
                Text('• Ctrl + D : Duplicate selected object(s)'),
                Text(
                    '• Delete / Backspace : Delete selected object(s) (warns if multiple)'),
                Text('• Ctrl + Z / Ctrl + Y : Undo / Redo (preserves selection)'),
                Text('• Arrow Keys : Move selected objects (0.1 mm)'),
                Text('• Shift + Arrow : Faster movement (1.0 mm)'),
                Text('• Ctrl + Arrow : Fine micro-movement (0.025 mm)'),
                Text('• Ctrl + G / Ctrl + Shift + G : Group / Ungroup objects'),
                Text('• Ctrl + L : Lock or unlock selected object(s)'),
                Text(
                    '• L, R, T, B, C, E, P : CorelDRAW Align Left, Right, Top, Bottom, Center, Even, Page'),
                Text('• Esc : Clear selection or exit text field'),
              ],
            ),
          ),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Got It'),
          ),
        ],
      ),
    );
  }
}
