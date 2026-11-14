import 'dart:typed_data';

import 'package:excel_community/excel_community.dart' as xls;

import '../screens/supabase_rojmel_screen.dart';
import 'indian_date.dart';

/// One data row read from the Rojmel upload sheet.
class RojmelImportRow {
  RojmelImportRow({
    required this.excelRow,
    required this.date,
    required this.type,
    required this.head,
    required this.narration,
    required this.expenseShort,
    required this.amount,
    required this.mode,
    required this.party,
    required this.voucher,
    required this.txn,
    required this.clearDate,
    required this.claim60,
    required this.date60,
    required this.claim40,
    required this.date40,
  });

  final int excelRow;
  final String date;
  final String type;
  final String head;
  final String narration;
  final String expenseShort;
  final double amount;
  final String mode;
  final String party;
  final String voucher;
  final String txn;
  final String clearDate;
  final String claim60;
  final String date60;
  final String claim40;
  final String date40;
}

/// Excel template (download → fill → upload) for Rojmel transactions.
///
/// Workbook sheets:
///  1. સૂચના — Gujarati step-by-step instructions.
///  2. ડેટા અપલોડ — the only sheet that is read on upload.
///  3. ગ્રાન્ટ હેડ — heads of this account with limit / opening balance.
///  4. નમૂના એન્ટ્રી — prefilled dummy entries for every account type and
///     mode (SNA SPARSH 60:40, PFMS, Bank / cheque, interest, bank charge,
///     cash and padar).
class RojmelExcelIO {
  RojmelExcelIO._();

  static const String instructionsSheet = 'સૂચના (Instructions)';
  static const String uploadSheet = 'ડેટા અપલોડ (Upload)';
  static const String headsSheet = 'ગ્રાન્ટ હેડ (Heads)';
  static const String examplesSheet = 'નમૂના એન્ટ્રી (Examples)';

  static const int _headerRow = 3; // 0-based row index of the column headers.
  static const int _uploadRows = 300;

  static const List<String> columns = <String>[
    'ક્રમ',
    'તારીખ * (01/12/2025, 1/12/25, 1-Dec-25)',
    'જમા / ઉધાર * (Credit / Debit)',
    'ગ્રાન્ટ હેડ *',
    'વિગત * (Description)',
    'ખર્ચની ટૂંકી વિગત (માત્ર Debit - ખર્ચ પત્રક)',
    'પૂરી રકમ 100% * (₹)',
    'માધ્યમ * (Mode)',
    'પાર્ટી / કોની પાસેથી (Party)',
    'વાઉચર નં. (Debit, વૈકલ્પિક)',
    'ચેક / PFMS / PPA નં. (Bank-PFMS Debit)',
    'સેટલમેન્ટ તારીખ (Bank-PFMS Debit)',
    '60% Claim નં. (SNA Debit)',
    '60% સેટલમેન્ટ તારીખ (SNA Debit)',
    '40% Claim નં. (SNA Debit)',
    '40% સેટલમેન્ટ તારીખ (SNA Debit)',
  ];

  static const List<double> _widths = <double>[
    6, 17, 16, 30, 42, 30, 14, 16, 24, 12, 20, 17, 18, 17, 18, 17,
  ];

  /// Modes allowed for an account type (same as the Data Entry screen).
  static List<String> modesFor(AccountMeta m) => m.type == 'SNA_PURE'
      ? const <String>['SNA SPARSH', 'Cash']
      : m.type == 'SNA'
          ? const <String>['SNA SPARSH', 'PFMS', 'Cash']
          : m.type == 'PFMS'
              ? const <String>['PFMS', 'Cash']
              : const <String>['Bank', 'Cash'];

  static String typeLabel(AccountMeta m) => switch (m.type) {
        'SNA_PURE' => 'SNA SPARSH (60:40)',
        'SNA' => 'PFMS + SNA SPARSH',
        'PFMS' => 'PFMS',
        _ => 'BANK',
      };

  // ---------------------------------------------------------------------------
  // TEMPLATE
  // ---------------------------------------------------------------------------

  static Uint8List buildTemplate(RojmelEngine engine, String acc) {
    final m = engine.getAccountMeta(acc);
    final heads = templateHeads(engine, acc);
    final modes = modesFor(m);
    final x = xls.Excel.createExcel();
    x.rename('Sheet1', instructionsSheet);

    final title = xls.CellStyle(
      bold: true,
      fontSize: 14,
      fontColorHex: xls.ExcelColor.fromHexString('#FFFFFF'),
      backgroundColorHex: xls.ExcelColor.fromHexString('#1A2744'),
    );
    final head = xls.CellStyle(
      bold: true,
      fontColorHex: xls.ExcelColor.fromHexString('#FFFFFF'),
      backgroundColorHex: xls.ExcelColor.fromHexString('#2F4580'),
      textWrapping: xls.TextWrapping.WrapText,
      horizontalAlign: xls.HorizontalAlign.Center,
      verticalAlign: xls.VerticalAlign.Center,
    );
    final note = xls.CellStyle(
      bold: true,
      fontColorHex: xls.ExcelColor.fromHexString('#92400E'),
      backgroundColorHex: xls.ExcelColor.fromHexString('#FFF8E7'),
    );
    final section = xls.CellStyle(
      bold: true,
      fontColorHex: xls.ExcelColor.fromHexString('#065F46'),
      backgroundColorHex: xls.ExcelColor.fromHexString('#DCFCE7'),
    );

    void put(xls.Sheet s, int r, int c, Object? v, [xls.CellStyle? st]) {
      final cell = s.cell(xls.CellIndex.indexByColumnRow(columnIndex: c, rowIndex: r));
      if (v is num) {
        cell.value = v == v.roundToDouble()
            ? xls.IntCellValue(v.toInt())
            : xls.DoubleCellValue(v.toDouble());
      } else {
        cell.value = xls.TextCellValue('${v ?? ''}');
      }
      if (st != null) cell.cellStyle = st;
    }

    // 1. Instructions -------------------------------------------------------
    final ins = x[instructionsSheet];
    ins.setColumnWidth(0, 6);
    ins.setColumnWidth(1, 120);
    put(ins, 0, 0, 'રોજમેળ Excel અપલોડ — પગલાવાર સૂચના', title);
    put(ins, 0, 1, '', title);
    put(ins, 1, 0, 'ખાતું', note);
    put(ins, 1, 1, '$acc  (${typeLabel(m)})', note);
    final steps = <String>[
      'પહેલાં રોજમેળમાં આ ખાતાના ગ્રાન્ટ હેડ ઉમેરો. SNA SPARSH / PFMS ખાતામાં દરેક હેડની વાર્ષિક મર્યાદા (Head Limit) સેટ કરો. BANK ખાતામાં હેડ-વાઈઝ ઉઘડતી સિલક દાખલ કરો (ન હોય તો 0).',
      'ત્યારબાદ જ આ ટેમ્પ્લેટ ડાઉનલોડ કરો — તેમાં લિમિટ / ઉઘડતી સિલક સાથેના હેડ "$headsSheet" શીટમાં આવે છે.',
      'એન્ટ્રી માત્ર "$uploadSheet" શીટમાં જ કરો. હેડર લાઇન (પંક્તિ ૪) બદલશો નહીં અને ખાતાનું નામ (પંક્તિ ૨) બદલશો નહીં.',
      'તારીખ કોઈ પણ ભારતીય રીતે લખો — 01/12/2025, 1/12/25, 01-12-2025, 1-12-25, 01.12.2025, 1-Dec-25, 1-Dec-2025, 1 December 2025, ૦૧/૧૨/૨૦૨૫ — બધું 1 ડિસેમ્બર 2025 જ વંચાશે (હંમેશા પહેલાં દિવસ, પછી મહિનો). નીચે માન્ય રીતોનું ટેબલ છે. નાણાકીય વર્ષ તારીખ પરથી આપમેળે નક્કી થાય છે.',
      'તારીખના બધા ખાના પહેલેથી જ "Text" ફોર્મેટમાં છે, એટલે કમ્પ્યુટર US / અન્ય સેટિંગમાં હોય તો પણ Excel તારીખ ફેરવી નાખતું નથી. ખોટી તારીખ (દા.ત. 31/02/2026) હશે તો અપલોડ વખતે પંક્તિ નંબર સાથે બતાવાશે.',
      'જમા / ઉધાર, ગ્રાન્ટ હેડ અને માધ્યમ ખાનામાં ક્લિક કરતાં યાદી (ડ્રોપડાઉન) આવશે — તેમાંથી પસંદ કરો.',
      'ગ્રાન્ટ હેડ "$headsSheet" શીટમાં છે તે જ નામ (કોપી-પેસ્ટ) લખો.',
      'રકમ હંમેશા પૂરી 100% લખો. SNA SPARSH માધ્યમમાં સિસ્ટમ આપમેળે 60% અને 40% ની બે એન્ટ્રી બનાવશે.',
      'માધ્યમ (Mode): આ ખાતા માટે માન્ય — ${modes.join(' / ')}. રોકડ / પદર માટે "Cash" લખો.',
      'ખર્ચની ટૂંકી વિગત માત્ર Debit માટે છે — તે ખર્ચ પત્રકમાં છપાય છે. Credit માટે ખાલી રાખો.',
      'Bank / PFMS Debit માટે ચેક / PFMS / PPA નંબર અને સેટલમેન્ટ તારીખ ફરજિયાત છે.',
      'SNA SPARSH Debit માટે 60% અને 40% બંનેના Claim નંબર તથા સેટલમેન્ટ તારીખ ફરજિયાત છે.',
      'વાઉચર નંબર ખાલી રાખશો તો Debit ની તારીખ મુજબ આપમેળે નંબર આવશે.',
      'દરેક પ્રકારની સાચી એન્ટ્રી કેવી રીતે લખવી તે "$examplesSheet" શીટમાં જુઓ (તે શીટ અપલોડ થતી નથી).',
      'ફાઈલ સેવ કરી રોજમેળ → Import Excel માં "Excel અપલોડ કરો" પર ક્લિક કરો. પહેલાં બધી પંક્તિ ચકાસાય છે; એક પણ ભૂલ હોય તો કોઈ એન્ટ્રી ઉમેરાતી નથી અને ભૂલની પંક્તિ નંબર બતાવાય છે.',
      'સફળ અપલોડ પછી "Save to Server" દબાવો, જેથી ડેટા ક્લાઉડમાં સચવાય.',
    ];
    for (var i = 0; i < steps.length; i++) {
      put(ins, 3 + i, 0, i + 1);
      put(ins, 3 + i, 1, steps[i]);
    }
    // Accepted date styles (all read day first).
    var fr = 3 + steps.length + 1;
    ins.setColumnWidth(2, 22);
    ins.setColumnWidth(3, 26);
    put(ins, fr, 0, '', section);
    put(ins, fr, 1, 'માન્ય તારીખ ફોર્મેટ — ડાબે રીત, જમણે ઉદાહરણ (બધા = 1 ડિસેમ્બર 2025)', section);
    put(ins, fr, 2, 'ઉદાહરણ', section);
    put(ins, fr, 3, 'વંચાશે', section);
    fr++;
    for (final (style, sample) in IndianDate.examples) {
      put(ins, fr, 1, style);
      put(ins, fr, 2, sample);
      put(ins, fr, 3, IndianDate.toDmy(sample) ?? '');
      fr++;
    }

    // 2. Upload sheet --------------------------------------------------------
    final up = x[uploadSheet];
    put(up, 0, 0, 'રોજમેળ ડેટા અપલોડ — માત્ર આ શીટ વંચાશે', title);
    for (var c = 1; c < columns.length; c++) {
      put(up, 0, c, '', title);
    }
    put(up, 1, 0, 'ખાતું', note);
    put(up, 1, 1, acc, note);
    put(up, 1, 3, 'પ્રકાર: ${typeLabel(m)}', note);
    put(up, 1, 4, 'માન્ય માધ્યમ: ${modes.join(' / ')}', note);
    put(up, 2, 0, 'નીચેની લાઇનથી એન્ટ્રી શરૂ કરો. * વાળા ખાના ફરજિયાત છે.');
    for (var c = 0; c < columns.length; c++) {
      put(up, _headerRow, c, columns[c], head);
      up.setColumnWidth(c, _widths[c]);
    }
    // Date cells are pre-set to Text ("@"): whatever the teacher types
    // (01/12/2025, 1-12-25, 1-Dec-25 …) is kept exactly as typed and read day
    // first on upload. A date-formatted cell would let a US-locale Excel turn
    // 01/12/2025 into 12 January silently, and refuse 25/12/2025.
    final dateStyle = xls.CellStyle(
      numberFormat: xls.NumFormat.standard_49,
      horizontalAlign: xls.HorizontalAlign.Center,
    );
    const dateCols = <int>[1, 11, 13, 15];
    for (var r = 0; r < _uploadRows; r++) {
      put(up, _headerRow + 1 + r, 0, r + 1);
      for (final c in dateCols) {
        up
            .cell(xls.CellIndex.indexByColumnRow(columnIndex: c, rowIndex: _headerRow + 1 + r))
            .cellStyle = dateStyle;
      }
    }
    final first = _headerRow + 2; // 1-based Excel row of the first entry
    final last = _headerRow + 1 + _uploadRows;
    for (final col in const ['B', 'L', 'N', 'P']) {
      up.addDataValidation(
        '$col$first:$col$last',
        xls.DataValidation.inputMessage(
          'તારીખ (પહેલાં દિવસ)',
          'કોઈ પણ રીતે લખો: 01/12/2025, 1/12/25, 01-12-2025, 1-12-25, 01.12.2025, 1-Dec-25, 1-Dec-2025, 1 Dec 2025',
        ),
      );
    }
    up.addDataValidation(
      'C$first:C$last',
      xls.DataValidation.list(const ['Credit', 'Debit'])
          .withPrompt('જમા / ઉધાર', 'યાદીમાંથી Credit (આવક) અથવા Debit (જાવક) પસંદ કરો.')
          .withError('ખોટી કિંમત', 'માત્ર Credit અથવા Debit પસંદ કરો.'),
    );
    up.addDataValidation(
      'H$first:H$last',
      xls.DataValidation.list(modes)
          .withPrompt('માધ્યમ', 'યાદીમાંથી માધ્યમ પસંદ કરો: ${modes.join(' / ')}')
          .withError('ખોટું માધ્યમ', 'આ ખાતા માટે માન્ય: ${modes.join(' / ')}'),
    );
    if (heads.isNotEmpty) {
      up.addDataValidation(
        'D$first:D$last',
        xls.DataValidation.listFromRange('B3:B${heads.length + 2}', sheetName: headsSheet)
            .withPrompt('ગ્રાન્ટ હેડ', 'યાદીમાંથી ગ્રાન્ટ હેડ પસંદ કરો.')
            .withError('ખોટો હેડ', 'ગ્રાન્ટ હેડ શીટમાંનો જ હેડ પસંદ કરો.'),
      );
    }

    // 3. Heads sheet ---------------------------------------------------------
    final hs = x[headsSheet];
    final isBank = !m.isSnaOrPfms;
    final hHeaders = isBank
        ? const ['ક્રમ', 'ગ્રાન્ટ હેડ (આ જ નામ લખો)', 'ઉઘડતી રોકડ ₹', 'ઉઘડતી બેન્ક ₹', 'કુલ ઉઘડતી ₹']
        : const ['ક્રમ', 'ગ્રાન્ટ હેડ (આ જ નામ લખો)', 'વાર્ષિક લિમિટ ₹', 'વપરાયેલ ₹', 'બાકી લિમિટ ₹'];
    put(hs, 0, 0, '$acc — ગ્રાન્ટ હેડ', title);
    for (var c = 0; c < hHeaders.length; c++) {
      put(hs, 1, c, hHeaders[c], head);
    }
    hs.setColumnWidth(0, 6);
    hs.setColumnWidth(1, 46);
    for (var c = 2; c < 5; c++) {
      hs.setColumnWidth(c, 16);
    }
    final today = DateTime.now();
    final todayIso =
        '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';
    for (var i = 0; i < heads.length; i++) {
      final h = heads[i];
      put(hs, 2 + i, 0, i + 1);
      put(hs, 2 + i, 1, h);
      if (isBank) {
        final o = engine.getHeadOpening(acc, h);
        put(hs, 2 + i, 2, o.cash);
        put(hs, 2 + i, 3, o.bank);
        put(hs, 2 + i, 4, o.total);
      } else {
        final b = engine.getHeadCashBankBalanceAtDate(acc, h, todayIso);
        put(hs, 2 + i, 2, b['limit'] ?? 0);
        put(hs, 2 + i, 3, b['usedYear'] ?? 0);
        put(hs, 2 + i, 4, b['remLimit'] ?? 0);
      }
    }

    // 4. Examples ------------------------------------------------------------
    final ex = x[examplesSheet];
    put(ex, 0, 0, 'નમૂના એન્ટ્રી — સમજવા માટે (આ શીટ અપલોડ થતી નથી)', title);
    for (var c = 1; c < columns.length; c++) {
      put(ex, 0, c, '', title);
    }
    for (var c = 0; c < columns.length; c++) {
      put(ex, 1, c, columns[c], head);
      ex.setColumnWidth(c, _widths[c]);
    }
    final h1 = heads.isNotEmpty ? heads.first : 'શાળા સંયુક્ત ગ્રાન્ટ';
    final h2 = heads.length > 1 ? heads[1] : h1;
    final groups = <(String, List<List<Object>>)>[
      (
        'A. SNA SPARSH ખાતું — 100% રકમ લખો, 60% + 40% આપમેળે બનશે',
        [
          [1, '01/06/2026', 'Credit', h1, 'ગ્રાન્ટ જમા થઈ', '', 50000, 'SNA SPARSH', 'SSA', '', '', '', '', '', '', ''],
          [2, '15-06-2026', 'Debit', h1, 'SHREE ENTERPRISE નું બીલ ચૂકવ્યું', 'સ્ટેશનરી વસ્તુઓ, કાગળ', 5000, 'SNA SPARSH', 'SHREE ENTERPRISE', '', '', '', 'C0626001', '16/6/26', 'C0626002', '16-Jun-26'],
        ],
      ),
      (
        'B. PFMS ખાતું (અથવા PFMS + SNA નો PFMS સમયગાળો)',
        [
          [3, '5/6/26', 'Credit', h1, 'ગ્રાન્ટ જમા થઈ', '', 25000, 'PFMS', 'SSA', '', '', '', '', '', '', ''],
          [4, '20-Jun-2026', 'Debit', h2, 'રંગકામનું બીલ ચૂકવ્યું', 'રંગ સામગ્રી અને મજૂરી', 8000, 'PFMS', 'MAHADEV PAINTS', '', 'PPA0012345', '21.06.2026', '', '', '', ''],
        ],
      ),
      (
        'C. BANK ખાતું — ચેક / વ્યાજ / બેંક ચાર્જ',
        [
          [5, '30-06-26', 'Credit', h1, 'બેંકનું વ્યાજ જમા થયું', '', 350, 'Bank', 'બેંક', '', '', '', '', '', '', ''],
          [6, '2 July 2026', 'Debit', h1, 'RAJ FURNITURE ને ચેકથી ચૂકવ્યા', 'ફર્નિચર રીપેર', 4500, 'Bank', 'RAJ FURNITURE', '', '000123', '04/07/2026', '', '', '', ''],
          [7, '31/07/2026', 'Debit', h1, 'બેન્ક દ્વારા ચાર્જ કપાયો', 'બેંક ચાર્જ', 59, 'Bank', 'બેંક', '', 'બેન્ક ચાર્જ', '31/07/2026', '', '', '', ''],
        ],
      ),
      (
        'D. રોકડ / પદર — દરેક પ્રકારના ખાતામાં "Cash" માધ્યમ',
        [
          [8, '૧૦/૦૭/૨૦૨૬', 'Credit', h1, 'પદર તરીકે આચાર્યશ્રીએ નાણા રોક્યા', '', 2000, 'Cash', 'આચાર્યશ્રી', '', '', '', '', '', '', ''],
          [9, '12-7-26', 'Debit', h1, 'SMC મીટિંગ ચા-નાસ્તો રોકડેથી ચૂકવ્યો', 'ચા-નાસ્તો', 600, 'Cash', 'JALARAM TEA', '', '', '', '', '', '', ''],
          [10, '25-Jul-26', 'Debit', h1, 'રોકેલ પદરના નાણાં પરત', '', 1400, 'Cash', 'આચાર્યશ્રી', '', '', '', '', '', '', ''],
        ],
      ),
    ];
    var r = 2;
    for (final g in groups) {
      put(ex, r, 0, g.$1, section);
      for (var c = 1; c < columns.length; c++) {
        put(ex, r, c, '', section);
      }
      r++;
      for (final row in g.$2) {
        for (var c = 0; c < row.length; c++) {
          put(ex, r, c, row[c]);
        }
        r++;
      }
      r++;
    }

    // encode() (not save()) so the web build does not auto-download twice.
    final bytes = x.encode();
    if (bytes == null) throw StateError('Excel template could not be created.');
    return Uint8List.fromList(bytes);
  }

  /// Heads included in the template: SNA / PFMS heads need a limit; BANK
  /// heads are all included (opening may be 0).
  static List<String> templateHeads(RojmelEngine engine, String acc) {
    final m = engine.getAccountMeta(acc);
    final heads = engine
        .getAccountSpecificHeads(acc)
        .where((h) => engine.grantHeadActiveMap[h] != 'no')
        .toList();
    if (!m.isSnaOrPfms) return heads;
    return heads.where((h) => engine.getHeadLimit(acc, h) > 0).toList();
  }

  // ---------------------------------------------------------------------------
  // UPLOAD
  // ---------------------------------------------------------------------------

  static String _cellText(xls.Data? cell) {
    final v = cell?.value;
    if (v == null) return '';
    String dmy(int d, int m, int y) =>
        '${d.toString().padLeft(2, '0')}/${m.toString().padLeft(2, '0')}/$y';
    if (v is xls.DateCellValue) return dmy(v.day, v.month, v.year);
    if (v is xls.DateTimeCellValue) return dmy(v.day, v.month, v.year);
    if (v is xls.IntCellValue) return '${v.value}';
    if (v is xls.DoubleCellValue) {
      final d = v.value;
      return d == d.roundToDouble() ? '${d.toInt()}' : '$d';
    }
    return v.toString().trim();
  }

  /// Any Indian date style (or an Excel date number) as DD/MM/YYYY; text
  /// that is not a date is kept so the error can show it.
  static String _date(String raw) => IndianDate.toDmy(raw) ?? raw.trim();

  /// Reads the upload sheet. Returns the account named in the sheet, the rows
  /// and structural errors (wrong file, missing header, bad numbers).
  static ({String account, List<RojmelImportRow> rows, List<String> errors})
      parseUpload(Uint8List bytes) {
    final errors = <String>[];
    final rows = <RojmelImportRow>[];
    final x = xls.Excel.decodeBytes(bytes);
    xls.Sheet? sheet = x.tables[uploadSheet];
    sheet ??= x.tables.values.firstWhere(
      (s) => s.rows.take(8).any((r) => r.any((c) => _cellText(c).startsWith('ગ્રાન્ટ હેડ'))),
      orElse: () => x.tables.values.first,
    );
    final all = sheet.rows;
    var headerIdx = -1;
    for (var i = 0; i < all.length && i < 10; i++) {
      if (all[i].any((c) => _cellText(c).startsWith('ગ્રાન્ટ હેડ'))) {
        headerIdx = i;
        break;
      }
    }
    if (headerIdx < 0) {
      return (
        account: '',
        rows: rows,
        errors: ['આ ફાઈલ રોજમેળ ટેમ્પ્લેટ નથી — "$uploadSheet" શીટમાં હેડર લાઇન મળી નથી. પહેલાં નવું ટેમ્પ્લેટ ડાઉનલોડ કરો.'],
      );
    }
    var account = '';
    if (headerIdx >= 2 && all[headerIdx - 2].length > 1) {
      account = _cellText(all[headerIdx - 2][1]);
    }
    String at(List<xls.Data?> r, int c) => c < r.length ? _cellText(r[c]) : '';
    for (var i = headerIdx + 1; i < all.length; i++) {
      final r = all[i];
      final head = at(r, 3);
      final amountText = at(r, 6).replaceAll(',', '').replaceAll('₹', '').trim();
      final typeText = at(r, 2);
      if (head.isEmpty && amountText.isEmpty && typeText.isEmpty && at(r, 4).isEmpty) {
        continue; // blank row (serial number only)
      }
      final amount = double.tryParse(amountText) ?? 0;
      final excelRow = i + 1;
      final t = typeText.toLowerCase();
      final type = (t.contains('credit') || t.contains('જમા') || t.contains('આવક'))
          ? 'credit'
          : (t.contains('debit') || t.contains('ઉધાર') || t.contains('જાવક'))
              ? 'debit'
              : '';
      if (type.isEmpty) {
        errors.add('પંક્તિ $excelRow: જમા / ઉધારમાં Credit અથવા Debit લખો.');
      }
      if (amount <= 0) {
        errors.add('પંક્તિ $excelRow: પૂરી રકમ સાચી લખો (₹ 0 થી વધુ).');
      }
      rows.add(RojmelImportRow(
        excelRow: excelRow,
        date: _date(at(r, 1)),
        type: type,
        head: head,
        narration: at(r, 4),
        expenseShort: at(r, 5),
        amount: amount,
        mode: at(r, 7),
        party: at(r, 8),
        voucher: at(r, 9),
        txn: at(r, 10),
        clearDate: _date(at(r, 11)),
        claim60: at(r, 12),
        date60: _date(at(r, 13)),
        claim40: at(r, 14),
        date40: _date(at(r, 15)),
      ));
    }
    if (rows.isEmpty && errors.isEmpty) {
      errors.add('"$uploadSheet" શીટમાં કોઈ એન્ટ્રી મળી નથી.');
    }
    return (account: account, rows: rows, errors: errors);
  }

  /// True for a real calendar date (any Indian style, years 2000–2100).
  static bool _isRealDate(String raw) => isRojmelDate(raw);

  static String? _normaliseMode(String raw, AccountMeta m) {
    final v = raw.trim().toLowerCase();
    final allowed = modesFor(m);
    String? mode;
    if (v.contains('sna') || v.contains('sparsh')) {
      mode = 'SNA SPARSH';
    } else if (v.contains('pfms') || v.contains('ppa')) {
      mode = 'PFMS';
    } else if (v.contains('cash') || v.contains('રોકડ') || v.contains('પદર') || v.contains('padar')) {
      mode = 'Cash';
    } else if (v.contains('bank') || v.contains('બેન્ક') || v.contains('બેંક') || v.contains('cheque') || v.contains('ચેક')) {
      mode = 'Bank';
    } else if (v.isEmpty) {
      mode = allowed.first;
    }
    return mode != null && allowed.contains(mode) ? mode : null;
  }

  /// Adds the rows to [engine] (oldest first, credits before debits on the
  /// same date) using the same validations as manual Data Entry. Returns the
  /// row-numbered errors; the caller runs this on a copy first so nothing is
  /// imported unless every row is valid.
  static List<String> applyRows(
    RojmelEngine engine,
    String acc,
    List<RojmelImportRow> rows,
  ) {
    final m = engine.getAccountMeta(acc);
    final heads = templateHeads(engine, acc).toSet();
    final errors = <String>[];
    final ordered = List<RojmelImportRow>.from(rows)
      ..sort((a, b) {
        final c = normalizeToIsoDate(a.date).compareTo(normalizeToIsoDate(b.date));
        if (c != 0) return c;
        if (a.type != b.type) return a.type == 'credit' ? -1 : 1;
        return a.excelRow.compareTo(b.excelRow);
      });
    for (final r in ordered) {
      final iso = normalizeToIsoDate(r.date);
      if (!_isRealDate(r.date)) {
        errors.add(r.date.trim().isEmpty
            ? 'પંક્તિ ${r.excelRow}: તારીખ લખો.'
            : 'પંક્તિ ${r.excelRow}: તારીખ "${r.date}" સાચી નથી — આ રીતે લખો: ${IndianDate.formatsHint}.');
        continue;
      }
      if (!heads.contains(r.head)) {
        errors.add(m.isSnaOrPfms
            ? 'પંક્તિ ${r.excelRow}: "${r.head}" હેડ આ ખાતામાં નથી અથવા તેની લિમિટ સેટ નથી.'
            : 'પંક્તિ ${r.excelRow}: "${r.head}" હેડ આ ખાતામાં નથી.');
        continue;
      }
      final mode = _normaliseMode(r.mode, m);
      if (mode == null) {
        errors.add('પંક્તિ ${r.excelRow}: માધ્યમ "${r.mode}" આ ખાતા માટે માન્ય નથી (${modesFor(m).join(' / ')}).');
        continue;
      }
      if (r.type.isEmpty || r.amount <= 0) continue; // already reported
      final err = engine.addTransactionV06(
        account: acc,
        head: r.head,
        date: iso,
        type: r.type,
        rawNarration: r.narration,
        expenseShort: r.type == 'debit' ? r.expenseShort : '',
        amount: r.amount,
        medium: mode,
        party: r.party,
        manualVoucher: r.type == 'debit' ? r.voucher : '',
        txn: r.txn,
        clearDate: r.clearDate,
        sna60Claim: r.claim60,
        sna60Date: r.date60,
        sna40Claim: r.claim40,
        sna40Date: r.date40,
      );
      if (err != null) errors.add('પંક્તિ ${r.excelRow}: $err');
    }
    int rowOf(String e) =>
        int.tryParse(RegExp(r'પંક્તિ (\d+)').firstMatch(e)?.group(1) ?? '') ?? 0;
    errors.sort((a, b) => rowOf(a).compareTo(rowOf(b)));
    return errors;
  }
}
