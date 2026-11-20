import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:xml/xml.dart';

/// Repairs common OOXML issues produced by `excel_community` and template XML
/// transforms so every generated `.xlsx` opens cleanly in Microsoft Excel
/// without "We found a problem with some content" repair dialogs.
///
/// Preserves all cell values, formulas, totals, layouts, margins, logos, and
/// print settings; only fixes schema-invalid XML artifacts.
class XlsxSanitizer {
  XlsxSanitizer._();

  static const List<String> _worksheetElementOrder = <String>[
    'sheetPr',
    'dimension',
    'sheetViews',
    'sheetFormatPr',
    'cols',
    'sheetData',
    'sheetCalcPr',
    'sheetProtection',
    'protectedRanges',
    'scenarios',
    'autoFilter',
    'sortState',
    'dataConsolidate',
    'customSheetViews',
    'mergeCells',
    'phoneticPr',
    'conditionalFormatting',
    'dataValidations',
    'hyperlinks',
    'printOptions',
    'pageMargins',
    'pageSetup',
    'headerFooter',
    'rowBreaks',
    'colBreaks',
    'customProperties',
    'cellWatches',
    'ignoredErrors',
    'smartTags',
    'drawing',
    'legacyDrawing',
    'legacyDrawingHF',
    'drawingHF',
    'picture',
    'oleObjects',
    'controls',
    'webPublishItems',
    'tableParts',
    'extLst',
  ];

  static const List<String> _borderChildOrder = <String>[
    'left',
    'right',
    'start',
    'end',
    'top',
    'bottom',
    'diagonal',
    'vertical',
    'horizontal',
  ];

  static final RegExp _illegalXmlChars =
      RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F\uFFFE\uFFFF]');

  static final RegExp _openingTagWithAttrs = RegExp(
    r'\x3C([A-Za-z_][\w:.-]*)((?:\s+[A-Za-z_][\w:.-]*\s*=\s*(?:"[^"]*"|\x27[^\x27]*\x27))+)\s*(/?)\x3E',
  );

  static final RegExp _singleAttr = RegExp(
    r'([A-Za-z_][\w:.-]*)\s*=\s*("[^"]*"|\x27[^\x27]*\x27)',
  );

  static Uint8List clean(Uint8List bytes) {
    if (bytes.length < 4 || bytes[0] != 0x50 || bytes[1] != 0x4B) {
      return bytes;
    }
    final Archive archive;
    try {
      archive = ZipDecoder().decodeBytes(bytes);
    } catch (_) {
      return bytes;
    }

    String normPath(String p) =>
        p.replaceAll('\\', '/').replaceFirst(RegExp(r'^/+'), '');

    ArchiveFile? find(String name) {
      final target = normPath(name);
      for (final f in archive.files) {
        if (normPath(f.name) == target) return f;
      }
      return null;
    }

    String? read(String name) {
      final f = find(name);
      final c = f?.readBytes();
      return c == null ? null : utf8.decode(c, allowMalformed: true);
    }

    var changed = false;

    void write(String name, String text) {
      final target = normPath(name);
      for (var i = 0; i < archive.files.length; i++) {
        final original = archive.files[i];
        if (normPath(original.name) != target) continue;
        final replacement = ArchiveFile.bytes(original.name, utf8.encode(text));
        replacement.compression = original.compression;
        replacement.comment = original.comment;
        archive.modifyAtIndex(i, replacement);
        changed = true;
        return;
      }
    }

    // 1. Remove stale calcChain.xml (Excel rebuilds calculation chain cleanly).
    final calc = find('xl/calcChain.xml');
    if (calc != null) {
      archive.removeFile(calc);
      changed = true;
    }

    // 2. Sanitize illegal XML 1.0 control chars & duplicate attributes on all XML/rels parts.
    for (var i = 0; i < archive.files.length; i++) {
      final f = archive.files[i];
      if (!f.isFile) continue;
      final lower = f.name.toLowerCase();
      if (!lower.endsWith('.xml') && !lower.endsWith('.rels')) continue;
      final rawBytes = f.readBytes();
      if (rawBytes == null || rawBytes.isEmpty) continue;
      final originalText = utf8.decode(rawBytes, allowMalformed: true);
      final cleaned = _dedupeTagAttributes(_stripControlChars(originalText));
      if (cleaned != originalText) {
        write(f.name, cleaned);
      }
    }

    // Collect existing file paths after calcChain removal.
    final existingPaths = <String>{
      for (final f in archive.files)
        if (f.isFile) normPath(f.name),
    };

    // 3. Sanitize xl/workbook.xml (sheetIds, activeTab, definedNames).
    final sheetNames = <String>[];
    final hiddenSheetIndices = <int>{};
    final sheetRIds = <String>[];
    var activeTabIndex = 0;

    final wbRaw = read('xl/workbook.xml');
    if (wbRaw == null) return bytes;
    final wbDoc = _parseXml(wbRaw);
    if (wbDoc == null) return bytes;

    var wbChanged = false;
    final wbRoot = wbDoc.rootElement;
    final sheetsEl = _firstChild(wbRoot, 'sheets');
    if (sheetsEl != null) {
      final usedIds = <int>{};
      var nextId = 1;
      final sheets = sheetsEl.childElements
          .where((e) => e.name.local == 'sheet')
          .toList();
      for (var i = 0; i < sheets.length; i++) {
        final s = sheets[i];
        sheetNames.add(_attr(s, 'name') ?? '');
        sheetRIds.add(_attr(s, 'id') ?? '');
        final state = (_attr(s, 'state') ?? '').toLowerCase();
        if (state == 'hidden' || state == 'veryhidden') {
          hiddenSheetIndices.add(i);
        }
        final parsedId = int.tryParse(_attr(s, 'sheetId') ?? '');
        if (parsedId == null || parsedId <= 0 || !usedIds.add(parsedId)) {
          while (usedIds.contains(nextId)) {
            nextId++;
          }
          usedIds.add(nextId);
          s.setAttribute('sheetId', '$nextId');
          wbChanged = true;
        }
      }

      final visibleIndices = <int>[
        for (var i = 0; i < sheets.length; i++)
          if (!hiddenSheetIndices.contains(i)) i,
      ];
      final fallbackActive =
          visibleIndices.isNotEmpty ? visibleIndices.first : 0;

      final bookViews = _firstChild(wbRoot, 'bookViews');
      if (bookViews != null) {
        for (final view in bookViews.childElements
            .where((e) => e.name.local == 'workbookView')) {
          final rawTab = _attr(view, 'activeTab');
          final parsedTab = int.tryParse(rawTab ?? '');
          if (parsedTab == null ||
              parsedTab < 0 ||
              parsedTab >= sheets.length ||
              hiddenSheetIndices.contains(parsedTab)) {
            activeTabIndex = fallbackActive;
            if (rawTab != '$fallbackActive') {
              view.setAttribute('activeTab', '$fallbackActive');
              wbChanged = true;
            }
          } else {
            activeTabIndex = parsedTab;
          }
        }
      } else {
        activeTabIndex = fallbackActive;
      }

      final definedNamesEl = _firstChild(wbRoot, 'definedNames');
      if (definedNamesEl != null) {
        final existing = definedNamesEl.childElements
            .where((e) => e.name.local == 'definedName')
            .toList();
        final valid = <XmlElement>[];
        for (final dn in existing) {
          final value = dn.innerText.trim();
          final nameAttr = (_attr(dn, 'name') ?? '').trim();
          final localAttr = _attr(dn, 'localSheetId');
          if (nameAttr.isEmpty || value.isEmpty || value.contains('#REF!')) {
            wbChanged = true;
            continue;
          }
          final refSheets = <String>{};
          var hasMissingSheet = false;
          for (final ref in RegExp(
            r"(?:'((?:[^']|'')+)'|([A-Za-z0-9_.]+))!",
          ).allMatches(value)) {
            final sName =
                (ref.group(1) ?? ref.group(2) ?? '').replaceAll("''", "'");
            if (sName.isEmpty) continue;
            if (!sheetNames.contains(sName)) {
              hasMissingSheet = true;
              break;
            }
            refSheets.add(sName);
          }
          if (hasMissingSheet) {
            wbChanged = true;
            continue;
          }

          if (refSheets.length == 1 &&
              (localAttr != null || nameAttr.startsWith('_xlnm.'))) {
            final actualIndex = sheetNames.indexOf(refSheets.first);
            if (actualIndex >= 0 && localAttr != '$actualIndex') {
              dn.setAttribute('localSheetId', '$actualIndex');
              wbChanged = true;
            }
          } else if (localAttr != null) {
            final parsedLocal = int.tryParse(localAttr);
            if (parsedLocal == null ||
                parsedLocal < 0 ||
                parsedLocal >= sheetNames.length) {
              wbChanged = true;
              continue;
            }
          }
          valid.add(dn);
        }

        // Deduplicate by (name, localSheetId), keeping the last definition.
        final deduped = <XmlElement>[];
        final seenKeys = <String>{};
        for (var i = valid.length - 1; i >= 0; i--) {
          final dn = valid[i];
          final key =
              '${(_attr(dn, 'name') ?? '').toLowerCase()}|${_attr(dn, 'localSheetId') ?? ''}';
          if (seenKeys.add(key)) {
            deduped.add(dn);
          } else {
            wbChanged = true;
          }
        }
        final ordered = deduped.reversed.toList();
        if (ordered.isEmpty) {
          definedNamesEl.remove();
          wbChanged = true;
        } else if (wbChanged) {
          definedNamesEl.children.clear();
          definedNamesEl.children.addAll(ordered);
        }
      }
    }

    if (wbChanged) {
      write('xl/workbook.xml', wbDoc.toXmlString());
    }

    // 4. Sanitize xl/styles.xml (invalid rgb="none" / #hex colors, border order, counts, bounds).
    final stylesRaw = read('xl/styles.xml');
    if (stylesRaw != null) {
      final stylesDoc = _parseXml(stylesRaw);
      if (stylesDoc != null && _sanitizeStyles(stylesDoc)) {
        write('xl/styles.xml', stylesDoc.toXmlString());
      }
    }

    // 5. Sanitize xl/sharedStrings.xml (uniqueCount / count sync).
    int? sharedStringCount;
    final ssRaw = read('xl/sharedStrings.xml');
    if (ssRaw != null) {
      final ssDoc = _parseXml(ssRaw);
      if (ssDoc != null) {
        final ssRoot = ssDoc.rootElement;
        final siCount =
            ssRoot.childElements.where((e) => e.name.local == 'si').length;
        sharedStringCount = siCount;
        var ssChanged = false;
        final rawUnique = _attr(ssRoot, 'uniqueCount');
        if (rawUnique != '$siCount') {
          ssRoot.setAttribute('uniqueCount', '$siCount');
          ssChanged = true;
        }
        final rawCount = int.tryParse(_attr(ssRoot, 'count') ?? '');
        if (rawCount == null || rawCount < siCount) {
          ssRoot.setAttribute('count', '$siCount');
          ssChanged = true;
        }
        if (ssChanged) {
          write('xl/sharedStrings.xml', ssDoc.toXmlString());
        }
      }
    }

    // 6. Map r:id -> worksheet path from xl/_rels/workbook.xml.rels.
    final rIdToTarget = <String, String>{};
    final wbRelsRaw = read('xl/_rels/workbook.xml.rels');
    if (wbRelsRaw != null) {
      final wbRelsDoc = _parseXml(wbRelsRaw);
      if (wbRelsDoc != null) {
        for (final rel in wbRelsDoc.rootElement.childElements
            .where((e) => e.name.local == 'Relationship')) {
          final id = _attr(rel, 'Id') ?? '';
          final target = _attr(rel, 'Target') ?? '';
          final mode = (_attr(rel, 'TargetMode') ?? '').toLowerCase();
          if (id.isNotEmpty && target.isNotEmpty && mode != 'external') {
            rIdToTarget[id] = _resolveZipTarget('xl/_rels/workbook.xml.rels', target);
          }
        }
      }
    }

    String? activeSheetPath;
    final hiddenSheetPaths = <String>{};
    for (var i = 0; i < sheetRIds.length; i++) {
      final path = rIdToTarget[sheetRIds[i]];
      if (path == null) continue;
      if (i == activeTabIndex) activeSheetPath = path;
      if (hiddenSheetIndices.contains(i)) hiddenSheetPaths.add(path);
    }

    // 7. Sanitize every worksheet XML (cols, sheetData, mergeCells, tabSelected, XSD tag order).
    for (final path in existingPaths.where(
      (p) => p.startsWith('xl/worksheets/') && p.endsWith('.xml'),
    )) {
      final sheetRaw = read(path);
      if (sheetRaw == null) continue;
      final sheetDoc = _parseXml(sheetRaw);
      if (sheetDoc == null) continue;
      final isHidden = hiddenSheetPaths.contains(path);
      final isActive = activeSheetPath != null && activeSheetPath == path;
      if (_sanitizeWorksheet(
        sheetDoc,
        isActive: isActive,
        isHidden: isHidden,
        sharedStringCount: sharedStringCount,
      )) {
        write(path, sheetDoc.toXmlString());
      }
    }

    // 8. Remove dangling internal <Relationship> targets in all .rels parts.
    for (final relsPath in existingPaths.where((p) => p.endsWith('.rels'))) {
      final relsRaw = read(relsPath);
      if (relsRaw == null) continue;
      final relsDoc = _parseXml(relsRaw);
      if (relsDoc == null) continue;
      var relsChanged = false;
      final rels = relsDoc.rootElement.childElements
          .where((e) => e.name.local == 'Relationship')
          .toList();
      for (final rel in rels) {
        final mode = (_attr(rel, 'TargetMode') ?? '').toLowerCase();
        if (mode == 'external') continue;
        final target = _attr(rel, 'Target') ?? '';
        if (target.isEmpty) continue;
        final resolved = _resolveZipTarget(relsPath, target);
        if (!existingPaths.contains(resolved)) {
          rel.remove();
          relsChanged = true;
        }
      }
      if (relsChanged) {
        write(relsPath, relsDoc.toXmlString());
      }
    }

    // 9. Remove dangling <Override> entries in [Content_Types].xml.
    final ctRaw = read('[Content_Types].xml');
    if (ctRaw != null) {
      final ctDoc = _parseXml(ctRaw);
      if (ctDoc != null) {
        var ctChanged = false;
        final overrides = ctDoc.rootElement.childElements
            .where((e) => e.name.local == 'Override')
            .toList();
        for (final ov in overrides) {
          final partName = _attr(ov, 'PartName') ?? '';
          if (partName.isEmpty) continue;
          final normalized = normPath(partName);
          if (!existingPaths.contains(normalized)) {
            ov.remove();
            ctChanged = true;
          }
        }
        if (ctChanged) {
          write('[Content_Types].xml', ctDoc.toXmlString());
        }
      }
    }

    if (!changed) return bytes;
    final out = ZipEncoder().encode(archive);
    return out.isEmpty ? bytes : Uint8List.fromList(out);
  }

  static bool _sanitizeStyles(XmlDocument doc) {
    var changed = false;
    final root = doc.rootElement;

    // Normalize/clean invalid color rgb values (e.g. rgb="none", #RRGGBB, 6-char hex).
    final colorEls = doc.descendants
        .whereType<XmlElement>()
        .where(
          (e) =>
              e.name.local == 'color' ||
              e.name.local == 'fgColor' ||
              e.name.local == 'bgColor',
        )
        .toList();

    for (final el in colorEls) {
      if (el.parent == null) continue;
      final rawRgb = _attr(el, 'rgb');
      if (rawRgb == null) continue;
      final trimmed = rawRgb.trim().replaceFirst('#', '').toUpperCase();
      if (trimmed.length == 6 && RegExp(r'^[0-9A-F]{6}$').hasMatch(trimmed)) {
        el.setAttribute('rgb', 'FF$trimmed');
        changed = true;
      } else if (trimmed.length == 8 &&
          RegExp(r'^[0-9A-F]{8}$').hasMatch(trimmed)) {
        if (rawRgb != trimmed) {
          el.setAttribute('rgb', trimmed);
          changed = true;
        }
      } else {
        // Invalid rgb such as "none" or empty string.
        if (el.name.local == 'fgColor') {
          final parent = el.parent;
          if (parent is XmlElement &&
              parent.name.local == 'patternFill' &&
              (_attr(parent, 'patternType') ?? '').toLowerCase() == 'solid') {
            parent.setAttribute('patternType', 'none');
            parent.children.removeWhere(
              (n) =>
                  n is XmlElement &&
                  (n.name.local == 'fgColor' || n.name.local == 'bgColor'),
            );
            changed = true;
            continue;
          }
        }
        el.attributes.removeWhere((a) => a.name.local == 'rgb');
        if (el.attributes.isEmpty) {
          el.remove();
        }
        changed = true;
      }
    }

    // Ensure <border> children follow strict OOXML schema order.
    final bordersEl = _firstChild(root, 'borders');
    if (bordersEl != null) {
      for (final border in bordersEl.childElements
          .where((e) => e.name.local == 'border')) {
        if (_reorderChildren(border, _borderChildOrder)) {
          changed = true;
        }
      }
    }

    int countOf(String sectionName, String childName) {
      final sec = _firstChild(root, sectionName);
      if (sec == null) return 0;
      return sec.childElements.where((e) => e.name.local == childName).length;
    }

    final fontCount = countOf('fonts', 'font');
    final fillCount = countOf('fills', 'fill');
    final borderCount = countOf('borders', 'border');
    final styleXfCount = countOf('cellStyleXfs', 'xf');

    // Clamp out-of-range style references in cellXfs and cellStyleXfs.
    for (final xfSectionName in const <String>['cellStyleXfs', 'cellXfs']) {
      final sec = _firstChild(root, xfSectionName);
      if (sec == null) continue;
      for (final xf in sec.childElements.where((e) => e.name.local == 'xf')) {
        if (fontCount > 0) {
          final v = int.tryParse(_attr(xf, 'fontId') ?? '');
          if (v != null && (v < 0 || v >= fontCount)) {
            xf.setAttribute('fontId', '0');
            changed = true;
          }
        }
        if (fillCount > 0) {
          final v = int.tryParse(_attr(xf, 'fillId') ?? '');
          if (v != null && (v < 0 || v >= fillCount)) {
            xf.setAttribute('fillId', '0');
            changed = true;
          }
        }
        if (borderCount > 0) {
          final v = int.tryParse(_attr(xf, 'borderId') ?? '');
          if (v != null && (v < 0 || v >= borderCount)) {
            xf.setAttribute('borderId', '0');
            changed = true;
          }
        }
        if (xfSectionName == 'cellXfs' && styleXfCount > 0) {
          final v = int.tryParse(_attr(xf, 'xfId') ?? '');
          if (v != null && (v < 0 || v >= styleXfCount)) {
            xf.setAttribute('xfId', '0');
            changed = true;
          }
        }
      }
    }

    // Keep count attributes accurate on all style collections.
    const sections = <(String, String, bool)>[
      ('numFmts', 'numFmt', true),
      ('fonts', 'font', false),
      ('fills', 'fill', false),
      ('borders', 'border', false),
      ('cellStyleXfs', 'xf', false),
      ('cellXfs', 'xf', false),
      ('cellStyles', 'cellStyle', false),
      ('dxfs', 'dxf', true),
      ('tableStyles', 'tableStyle', true),
    ];
    for (final (secName, childName, removeIfEmpty) in sections) {
      final sec = _firstChild(root, secName);
      if (sec == null) continue;
      final cnt = sec.childElements.where((e) => e.name.local == childName).length;
      if (cnt == 0 && removeIfEmpty) {
        sec.remove();
        changed = true;
      } else if (_attr(sec, 'count') != '$cnt') {
        sec.setAttribute('count', '$cnt');
        changed = true;
      }
    }

    return changed;
  }

  static bool _sanitizeWorksheet(
    XmlDocument doc, {
    required bool isActive,
    required bool isHidden,
    required int? sharedStringCount,
  }) {
    var changed = false;
    final root = doc.rootElement;

    // 1. Sync tabSelected so hidden sheets are never selected.
    final sheetViews = _firstChild(root, 'sheetViews');
    if (sheetViews != null) {
      for (final sv in sheetViews.childElements
          .where((e) => e.name.local == 'sheetView')) {
        final cur = _attr(sv, 'tabSelected');
        if (isHidden) {
          if (cur != null) {
            sv.attributes.removeWhere((a) => a.name.local == 'tabSelected');
            changed = true;
          }
        } else if (isActive) {
          if (cur != '1') {
            sv.setAttribute('tabSelected', '1');
            changed = true;
          }
        } else if (cur == '1') {
          sv.attributes.removeWhere((a) => a.name.local == 'tabSelected');
          changed = true;
        }
      }
    }

    // 2. Sanitize <cols>: drop invalid ranges and empty <cols/> containers.
    final colsEl = _firstChild(root, 'cols');
    if (colsEl != null) {
      final cols =
          colsEl.childElements.where((e) => e.name.local == 'col').toList();
      for (final col in cols) {
        final minV = int.tryParse(_attr(col, 'min') ?? '');
        final maxV = int.tryParse(_attr(col, 'max') ?? '');
        if (minV == null ||
            maxV == null ||
            minV < 1 ||
            maxV < 1 ||
            minV > maxV ||
            maxV > 16384) {
          col.remove();
          changed = true;
          continue;
        }
        final rawW = _attr(col, 'width');
        if (rawW != null) {
          final w = double.tryParse(rawW);
          if (w == null || !w.isFinite || w < 0) {
            col.setAttribute('width', '8.43');
            changed = true;
          }
        }
      }
      if (colsEl.childElements.where((e) => e.name.local == 'col').isEmpty) {
        colsEl.remove();
        changed = true;
      }
    }

    // 3. Sanitize <sheetData>: ascending rows/cells, valid numeric/sharedString/bool values.
    final sheetData = _firstChild(root, 'sheetData');
    if (sheetData != null) {
      final rows = sheetData.childElements
          .where((e) => e.name.local == 'row')
          .toList();
      var prevRowNum = 0;
      var rowsNeedReorder = false;
      final rowByNum = <int, XmlElement>{};

      for (final row in rows) {
        final rNum = int.tryParse(_attr(row, 'r') ?? '');
        if (rNum == null || rNum < 1) {
          row.remove();
          changed = true;
          continue;
        }
        if (rNum <= prevRowNum || rowByNum.containsKey(rNum)) {
          rowsNeedReorder = true;
        }
        prevRowNum = rNum;
        rowByNum[rNum] = row;

        // Sanitize cells inside this row.
        final cells =
            row.childElements.where((e) => e.name.local == 'c').toList();
        var prevCol = 0;
        var cellsNeedReorder = false;
        final cellByCol = <int, XmlElement>{};

        for (final c in cells) {
          final ref = _attr(c, 'r') ?? '';
          final m = RegExp(r'^([A-Z]{1,3})(\d+)$').firstMatch(ref);
          if (m == null) {
            c.remove();
            changed = true;
            continue;
          }
          final colNum = _colToNum(m.group(1)!);
          if (colNum <= prevCol || cellByCol.containsKey(colNum)) {
            cellsNeedReorder = true;
          }
          prevCol = colNum;
          cellByCol[colNum] = c;

          final cellType = _attr(c, 't');
          final vEl = _firstChild(c, 'v');
          final fEl = _firstChild(c, 'f');

          if (fEl != null && fEl.innerText.trim().isEmpty && fEl.attributes.isEmpty) {
            fEl.remove();
            changed = true;
          }

          if (cellType == null || cellType == 'n') {
            if (vEl != null) {
              final vText = vEl.innerText.trim();
              final parsed = double.tryParse(vText);
              if (vText.isEmpty || parsed == null || !parsed.isFinite) {
                vEl.remove();
                changed = true;
              }
            }
          } else if (cellType == 's') {
            final idx = int.tryParse(vEl?.innerText.trim() ?? '');
            if (idx == null ||
                idx < 0 ||
                (sharedStringCount != null && idx >= sharedStringCount)) {
              c.attributes.removeWhere((a) => a.name.local == 't');
              vEl?.remove();
              changed = true;
            }
          } else if (cellType == 'b') {
            final vText = (vEl?.innerText ?? '').trim().toLowerCase();
            if (vText == 'true') {
              vEl!.children
                ..clear()
                ..add(XmlText('1'));
              changed = true;
            } else if (vText == 'false') {
              vEl!.children
                ..clear()
                ..add(XmlText('0'));
              changed = true;
            } else if (vText != '0' && vText != '1') {
              c.attributes.removeWhere((a) => a.name.local == 't');
              vEl?.remove();
              changed = true;
            }
          } else if (cellType == 'inlineStr') {
            if (_firstChild(c, 'is') == null) {
              c.attributes.removeWhere((a) => a.name.local == 't');
              changed = true;
            }
          }
        }

        if (cellsNeedReorder) {
          final sortedCols = cellByCol.keys.toList()..sort();
          final reorderedCells = <XmlNode>[
            for (final col in sortedCols) cellByCol[col]!,
          ];
          row.children.clear();
          row.children.addAll(reorderedCells);
          changed = true;
        }
      }

      if (rowsNeedReorder) {
        final sortedRowNums = rowByNum.keys.toList()..sort();
        final reorderedRows = <XmlNode>[
          for (final rn in sortedRowNums) rowByNum[rn]!,
        ];
        sheetData.children.clear();
        sheetData.children.addAll(reorderedRows);
        changed = true;
      }
    }

    // 4. Sanitize <mergeCells>: drop inverted, single-cell, duplicate, and overlapping merges.
    final mergeCellsEl = _firstChild(root, 'mergeCells');
    if (mergeCellsEl != null) {
      final merges = mergeCellsEl.childElements
          .where((e) => e.name.local == 'mergeCell')
          .toList();
      final keptRects = <({int c1, int r1, int c2, int r2})>[];
      var keptCount = 0;

      for (final mc in merges) {
        final ref = (_attr(mc, 'ref') ?? '').trim();
        final m = RegExp(r'^([A-Z]{1,3})(\d+):([A-Z]{1,3})(\d+)$').firstMatch(ref);
        if (m == null) {
          mc.remove();
          changed = true;
          continue;
        }
        final c1 = _colToNum(m.group(1)!);
        final r1 = int.tryParse(m.group(2)!) ?? 0;
        final c2 = _colToNum(m.group(3)!);
        final r2 = int.tryParse(m.group(4)!) ?? 0;
        if (c1 < 1 || r1 < 1 || c2 < c1 || r2 < r1 || (c1 == c2 && r1 == r2)) {
          mc.remove();
          changed = true;
          continue;
        }
        final overlaps = keptRects.any(
          (o) => !(c2 < o.c1 || c1 > o.c2 || r2 < o.r1 || r1 > o.r2),
        );
        if (overlaps) {
          mc.remove();
          changed = true;
          continue;
        }
        keptRects.add((c1: c1, r1: r1, c2: c2, r2: r2));
        keptCount++;
      }

      if (keptCount == 0) {
        mergeCellsEl.remove();
        changed = true;
      } else if (_attr(mergeCellsEl, 'count') != '$keptCount') {
        mergeCellsEl.setAttribute('count', '$keptCount');
        changed = true;
      }
    }

    // 5. Enforce strict OOXML CT_Worksheet child element order.
    if (_reorderChildren(root, _worksheetElementOrder)) {
      changed = true;
    }

    return changed;
  }

  static bool _reorderChildren(XmlElement parent, List<String> order) {
    final elements = parent.childElements.toList();
    if (elements.length <= 1) return false;

    int rankOf(XmlElement e) {
      final idx = order.indexOf(e.name.local);
      return idx < 0 ? order.length : idx;
    }

    var alreadyOrdered = true;
    for (var i = 1; i < elements.length; i++) {
      if (rankOf(elements[i]) < rankOf(elements[i - 1])) {
        alreadyOrdered = false;
        break;
      }
    }
    if (alreadyOrdered) return false;

    final indexed = elements.asMap().entries.toList()
      ..sort((a, b) {
        final cmp = rankOf(a.value).compareTo(rankOf(b.value));
        return cmp != 0 ? cmp : a.key.compareTo(b.key);
      });
    final reordered = <XmlNode>[for (final entry in indexed) entry.value];
    parent.children.clear();
    parent.children.addAll(reordered);
    return true;
  }

  static XmlDocument? _parseXml(String raw) {
    try {
      return XmlDocument.parse(raw);
    } catch (_) {
      try {
        return XmlDocument.parse(_dedupeTagAttributes(_stripControlChars(raw)));
      } catch (_) {
        return null;
      }
    }
  }

  static String _stripControlChars(String input) =>
      input.replaceAll(_illegalXmlChars, '');

  static String _dedupeTagAttributes(String xml) {
    return xml.replaceAllMapped(_openingTagWithAttrs, (m) {
      final tagName = m.group(1)!;
      final attrsRaw = m.group(2)!;
      final selfClose = m.group(3)!;
      final seen = <String, String>{};
      var hasDuplicate = false;
      for (final a in _singleAttr.allMatches(attrsRaw)) {
        final k = a.group(1)!;
        final v = a.group(2)!;
        if (seen.containsKey(k)) {
          hasDuplicate = true;
        }
        seen[k] = v;
      }
      if (!hasDuplicate) return m.group(0)!;
      final rebuilt = seen.entries.map((e) => '${e.key}=${e.value}').join(' ');
      return '\x3C$tagName $rebuilt$selfClose\x3E';
    });
  }

  static XmlElement? _firstChild(XmlElement parent, String localName) {
    for (final e in parent.childElements) {
      if (e.name.local == localName) return e;
    }
    return null;
  }

  static String? _attr(XmlElement el, String localName) {
    for (final a in el.attributes) {
      if (a.name.local == localName) return a.value;
    }
    return null;
  }

  static int _colToNum(String col) {
    var n = 0;
    for (final cu in col.codeUnits) {
      if (cu >= 65 && cu <= 90) {
        n = n * 26 + (cu - 64);
      }
    }
    return n;
  }

  static String _resolveZipTarget(String relsPath, String target) {
    final cleanTarget = target.replaceAll('\\', '/').trim();
    if (cleanTarget.startsWith('/')) {
      return cleanTarget.replaceFirst(RegExp(r'^/+'), '');
    }
    // relsPath is e.g. "_rels/.rels", "xl/_rels/workbook.xml.rels", "xl/worksheets/_rels/sheet1.xml.rels"
    final normRels = relsPath.replaceAll('\\', '/');
    final relsMarker = normRels.indexOf('_rels/');
    final baseDir = relsMarker <= 0 ? '' : normRels.substring(0, relsMarker);
    final combined = baseDir.isEmpty ? cleanTarget : '$baseDir$cleanTarget';
    final out = <String>[];
    for (final part in combined.split('/')) {
      if (part.isEmpty || part == '.') continue;
      if (part == '..') {
        if (out.isNotEmpty) out.removeLast();
      } else {
        out.add(part);
      }
    }
    return out.join('/');
  }
}