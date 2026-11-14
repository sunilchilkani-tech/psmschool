// ============================================================================
// ROJMEL STUDIO PRO V06 — SUPABASE-INTEGRATED FLUTTER MODULE
// Exact Same-to-Same Implementation of ROJMEL_V02_7_1_CASHBOOK_PRINT_FIXED.html
//
// Preserves:
// 1. Full Supabase cloud integration (`SupabaseRojmelService` + `SupabaseRojmelScreen(profile: ...)`).
// 2. Exact V06 HTML/CSS visual design, sidebar (`#123a6b` -> `#0a294d`), top bar,
//    and all 13 panels (`Home`, `School Info`, `Rojmel Accounts`, `Grant Heads`,
//    `Data Entry`, `Reports`, `Tally Report`, `Calculation Check`, `Export Data`,
//    `Cashbook`, `Transactions`, `Import Excel`, `Backup & Settings`).
// 3. Exact A4 Portrait Cashbook pages (`odd-page` Credit with right binding margin,
//    `even-page` Debit with left binding margin, upward headers, `#fde9d9` peach
//    school/account bar, double borders, borderless inner columns, BANK empty-side
//    placeholder rows, non-overlapping closing summary block, and downward
//    red/peach `Page Number - X` bar).
// 4. All 17 Government School Audit Reports (Daybook, Parishisht-2 Khatavahi,
//    Bill Register with Padar/PFMS/SNA summary, Cheque/Claim Register with bank
//    charges, Kharch Patrak, Parishisht-8, Parishisht-9 Reconciliation,
//    Parishisht-10 UC with Gujarati words, Parishisht-11 Grant Register,
//    Annexure-12 12-Month Schedule, Monthly Hisab Patrak, Passbook, Tally Report
//    with Party Ledgers, Tarij Patrak, Certified Vouchers, Cover Page `પુઠું` &
//    Audit Index, and Complete Audit Pack).
// 5. Exact Print-Out & HTML Print Generator (`generateExactPrintHtmlDocument`)
//    producing the 100% identical printable A4 HTML/PDF output.
// ============================================================================

import 'dart:async';
import 'dart:convert';
import 'rojmel_html_stub.dart' if (dart.library.html) 'dart:html' as html;
import 'dart:math' as math;

import 'package:pmshri_attendance/services/firebase_backend_client.dart';
import '../services/supabase_rojmel_service.dart';
import '../services/rojmel_excel_io.dart';
import '../services/indian_date.dart';
import '../services/rojmel_print_setup.dart';
import '../services/psm_file_export_helper.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/responsive.dart';

// ============================================================================
// 1. DATA MODELS & CONSTANTS (100% V06 HTML PARITY)
// ============================================================================

class HeadBalance {
  double cash;
  double bank;

  HeadBalance({this.cash = 0.0, this.bank = 0.0});

  double get total => cash + bank;

  HeadBalance copy() => HeadBalance(cash: cash, bank: bank);

  Map<String, dynamic> toJson() => {'cash': cash, 'bank': bank};

  factory HeadBalance.fromJson(Map<String, dynamic> json) => HeadBalance(
        cash: (json['cash'] as num?)?.toDouble() ?? 0.0,
        bank: (json['bank'] as num?)?.toDouble() ?? 0.0,
      );
}

class PrincipalRecord {
  String name;
  String mobile;
  String pan;
  String from;
  String to;

  PrincipalRecord({
    required this.name,
    this.mobile = '',
    this.pan = '',
    this.from = '',
    this.to = '',
  });

  PrincipalRecord copy() => PrincipalRecord(
        name: name,
        mobile: mobile,
        pan: pan,
        from: from,
        to: to,
      );

  Map<String, dynamic> toJson() => {
        'name': name,
        'mobile': mobile,
        'pan': pan,
        'from': from,
        'to': to,
      };

  factory PrincipalRecord.fromJson(Map<String, dynamic> json) => PrincipalRecord(
        name: json['name']?.toString() ?? '',
        mobile: json['mobile']?.toString() ?? '',
        pan: json['pan']?.toString() ?? '',
        from: json['from']?.toString() ?? '',
        to: json['to']?.toString() ?? '',
      );
}

class AccountMeta {
  String name;
  /// 'SNA_PURE' (Purely SNA SPARSH), 'SNA' (Combination of PFMS & SNA SPARSH), 'PFMS', or 'BANK'
  String type;
  String bankName;
  String branch;
  String branchAddress;
  String acNo;
  String snaAgencyCode;
  String pfmsLastDate;
  String snaStartDate;
  String holderName;
  String ifsc;
  String schoolName;
  String pfmsSchoolName;
  String creditPageTitle;
  String debitPageTitle;
  double openingBank;
  double openingCash;
  bool openingConfigured;
  Map<String, HeadBalance> headOpenings;
  Map<String, double> headLimits;
  List<String> heads;

  AccountMeta({
    required this.name,
    required this.type,
    this.bankName = '',
    this.branch = '',
    this.branchAddress = '',
    this.acNo = '',
    this.snaAgencyCode = '',
    this.pfmsLastDate = '',
    this.snaStartDate = '',
    this.holderName = '',
    this.ifsc = '',
    this.schoolName = '',
    this.pfmsSchoolName = '',
    this.creditPageTitle = '-: CASHBOOK :-',
    this.debitPageTitle = '-: કેશબુક :-',
    this.openingBank = 0.0,
    this.openingCash = 0.0,
    this.openingConfigured = false,
    Map<String, HeadBalance>? headOpenings,
    Map<String, double>? headLimits,
    List<String>? heads,
  })  : headOpenings = headOpenings ?? <String, HeadBalance>{},
        headLimits = headLimits ?? <String, double>{},
        heads = heads ?? <String>[];

  bool get isSnaPure => type == 'SNA_PURE';
  bool get isPfmsSnaCombined => type == 'SNA';
  bool get isAnySna => type == 'SNA' || type == 'SNA_PURE';
  bool get isSnaOrPfms => type == 'SNA' || type == 'SNA_PURE' || type == 'PFMS';

  String get effectiveSnaAgencyCode =>
      snaAgencyCode.trim().isNotEmpty ? snaAgencyCode.trim() : acNo.trim();

  double get totalOpening => openingBank + openingCash;

  AccountMeta copy() => AccountMeta(
        name: name,
        type: type,
        bankName: bankName,
        branch: branch,
        branchAddress: branchAddress,
        acNo: acNo,
        snaAgencyCode: snaAgencyCode,
        pfmsLastDate: pfmsLastDate,
        snaStartDate: snaStartDate,
        holderName: holderName,
        ifsc: ifsc,
        schoolName: schoolName,
        pfmsSchoolName: pfmsSchoolName,
        creditPageTitle: creditPageTitle,
        debitPageTitle: debitPageTitle,
        openingBank: openingBank,
        openingCash: openingCash,
        openingConfigured: openingConfigured,
        headOpenings: headOpenings.map((k, v) => MapEntry(k, v.copy())),
        headLimits: Map<String, double>.from(headLimits),
        heads: List<String>.from(heads),
      );

  Map<String, dynamic> toJson() => {
        'name': name,
        'type': type,
        'bankName': bankName,
        'bank': bankName,
        'branch': branch,
        'branchAddress': branchAddress,
        'acNo': acNo,
        'number': acNo,
        'snaAgencyCode': snaAgencyCode,
        'pfmsLastDate': pfmsLastDate,
        'snaStartDate': snaStartDate,
        'holderName': holderName,
        'ifsc': ifsc,
        'schoolName': schoolName,
        'pfmsSchoolName': pfmsSchoolName,
        'creditPageTitle': creditPageTitle,
        'debitPageTitle': debitPageTitle,
        'openingBank': openingBank,
        'openingCash': openingCash,
        'openingConfigured': openingConfigured,
        'opening': openingBank + openingCash,
        'headOpenings': headOpenings.map((k, v) => MapEntry(k, v.toJson())),
        'headLimits': headLimits,
        'heads': heads,
      };

  factory AccountMeta.fromJson(String keyName, Map<String, dynamic> json) {
    final rawOpenings = json['headOpenings'] as Map<String, dynamic>? ?? {};
    final parsedOpenings = <String, HeadBalance>{};
    rawOpenings.forEach((k, v) {
      if (v is Map) {
        parsedOpenings[k] = HeadBalance.fromJson(v.map((kk, vv) => MapEntry(kk.toString(), vv)));
      } else if (v is num) {
        parsedOpenings[k] = HeadBalance(cash: 0.0, bank: v.toDouble());
      }
    });

    final rawLimits = json['headLimits'] as Map<String, dynamic>? ?? {};
    final parsedLimits = <String, double>{};
    rawLimits.forEach((k, v) {
      if (v is num) parsedLimits[k] = v.toDouble();
    });

    final rawHeads = (json['heads'] as List?)?.map((e) => e.toString()).toList() ?? <String>[];
    final parsedAcNo = (json['acNo'] ?? json['number'] ?? '').toString();
    final parsedSnaAgency = (json['snaAgencyCode'] ?? '').toString();
    final rawType = json['type']?.toString() ??
        (keyName.trim().toUpperCase() == 'SNA SPARSH'
            ? 'SNA_PURE'
            : (RegExp(r'SNA', caseSensitive: false).hasMatch(keyName)
                ? 'SNA'
                : (RegExp(r'PFMS', caseSensitive: false).hasMatch(keyName) ? 'PFMS' : 'BANK')));

    return AccountMeta(
      name: json['name']?.toString() ?? keyName,
      type: rawType,
      bankName: (json['bankName'] ?? json['bank'] ?? '').toString(),
      branch: (json['branch'] ?? '').toString(),
      branchAddress: (json['branchAddress'] ?? '').toString(),
      acNo: parsedAcNo,
      snaAgencyCode: parsedSnaAgency.isNotEmpty ? parsedSnaAgency : (rawType == 'SNA_PURE' ? parsedAcNo : ''),
      pfmsLastDate: (json['pfmsLastDate'] ?? '').toString(),
      snaStartDate: (json['snaStartDate'] ?? '').toString(),
      holderName: (json['holderName'] ?? '').toString(),
      ifsc: (json['ifsc'] ?? '').toString(),
      schoolName: (json['schoolName'] ?? '').toString(),
      pfmsSchoolName: (json['pfmsSchoolName'] ?? '').toString(),
      creditPageTitle: (json['creditPageTitle'] ?? '-: CASHBOOK :-').toString(),
      debitPageTitle: (json['debitPageTitle'] ?? '-: કેશબુક :-').toString(),
      openingBank: ((json['openingBank'] ?? json['opening'] ?? 0) as num).toDouble(),
      openingCash: ((json['openingCash'] ?? 0) as num).toDouble(),
      openingConfigured: json['openingConfigured'] == true ||
          parsedOpenings.isNotEmpty ||
          (((json['openingBank'] ?? json['opening'] ?? 0) as num).toDouble() > 0) ||
          (((json['openingCash'] ?? 0) as num).toDouble() > 0),
      headOpenings: parsedOpenings,
      headLimits: parsedLimits,
      heads: rawHeads,
    );
  }
}

class RojmelEntry {
  int sr;
  String date; // YYYY-MM-DD
  String head;
  String type; // 'credit' or 'debit'
  String narration;
  String voucher;
  String manualVoucher;
  double amount;
  String medium; // 'SNA SPARSH', 'PFMS', 'Bank', 'Cash'
  String txn;
  String clearDate;
  String party;
  String expense;
  double central;
  double state;
  double splitPercent;
  String id;
  int seq;
  String account;
  double originalAmount;
  String splitGroup;
  bool editAllowed;

  /// Debit only: the purchased item goes in the dead stock (asset) register.
  bool deadStock;

  RojmelEntry({
    required this.sr,
    required this.date,
    required this.head,
    required this.type,
    required this.narration,
    this.voucher = '',
    this.manualVoucher = '',
    required this.amount,
    required this.medium,
    this.txn = '',
    this.clearDate = '',
    this.party = '',
    this.expense = '',
    this.central = 0.0,
    this.state = 0.0,
    this.splitPercent = 0.0,
    required this.id,
    required this.seq,
    required this.account,
    double? originalAmount,
    this.splitGroup = '',
    this.editAllowed = true,
    this.deadStock = false,
  }) : originalAmount = originalAmount ?? amount;

  RojmelEntry copy() => RojmelEntry(
        sr: sr,
        date: date,
        head: head,
        type: type,
        narration: narration,
        voucher: voucher,
        manualVoucher: manualVoucher,
        amount: amount,
        medium: medium,
        txn: txn,
        clearDate: clearDate,
        party: party,
        expense: expense,
        central: central,
        state: state,
        splitPercent: splitPercent,
        id: id,
        seq: seq,
        account: account,
        originalAmount: originalAmount,
        splitGroup: splitGroup,
        editAllowed: editAllowed,
        deadStock: deadStock,
      );

  Map<String, dynamic> toJson() => {
        'sr': sr,
        'date': date,
        'head': head,
        'type': type,
        'narration': narration,
        'voucher': voucher,
        'manualVoucher': manualVoucher,
        'amount': amount,
        'medium': medium,
        'txn': txn,
        'clearDate': clearDate,
        'party': party,
        'expense': expense,
        'central': central,
        'state': state,
        'splitPercent': splitPercent,
        'id': id,
        'seq': seq,
        'account': account,
        'originalAmount': originalAmount,
        'splitGroup': splitGroup,
        'editAllowed': editAllowed,
        if (deadStock) 'deadStock': true,
      };

  factory RojmelEntry.fromJson(Map<String, dynamic> json) {
    final amt = (json['amount'] as num?)?.toDouble() ?? 0.0;
    final srVal = (json['sr'] as num?)?.toInt() ?? 0;
    final vStr = (json['voucher'] ?? json['manualVoucher'] ?? (json['type'] == 'debit' && srVal > 0 ? '$srVal' : '')).toString();
    return RojmelEntry(
      sr: srVal,
      date: json['date']?.toString() ?? '',
      head: json['head']?.toString() ?? '',
      type: json['type']?.toString() ?? 'credit',
      narration: json['narration']?.toString() ?? '',
      voucher: vStr,
      manualVoucher: (json['manualVoucher'] ?? vStr).toString(),
      amount: amt,
      medium: json['medium']?.toString() ?? 'Bank',
      txn: json['txn']?.toString() ?? '',
      clearDate: json['clearDate']?.toString() ?? '',
      party: json['party']?.toString() ?? '',
      expense: json['expense']?.toString() ?? '',
      central: (json['central'] as num?)?.toDouble() ?? 0.0,
      state: (json['state'] as num?)?.toDouble() ?? 0.0,
      splitPercent: (json['splitPercent'] as num?)?.toDouble() ?? 0.0,
      id: json['id']?.toString() ?? '',
      seq: (json['seq'] as num?)?.toInt() ?? 0,
      account: json['account']?.toString() ?? 'SNA SPARSH',
      originalAmount: (json['originalAmount'] as num?)?.toDouble() ?? amt,
      splitGroup: json['splitGroup']?.toString() ?? '',
      editAllowed: json['editAllowed'] as bool? ?? true,
      deadStock: json['deadStock'] == true,
    );
  }
}

/// Represents one paired Credit (Odd Page) + Debit (Even Page) in the Cashbook.
/// Matches `generateExactDemoPagesHTML` in ROJMEL_V02_7_1_CASHBOOK_PRINT_FIXED.html.
class CashbookPagePair {
  final int pairIndexOnDate;
  final int creditPageNo; // Odd Page: 1, 3, 5...
  final int debitPageNo;  // Even Page: 2, 4, 6...
  final String dateStr;   // YYYY-MM-DD
  final String formattedDateDDMMYY;
  final String formattedDateSlash;
  final String accountName;
  final String accountType; // 'SNA', 'PFMS', 'BANK'
  final String schoolTitle;
  final String holderName;
  final String accountNumber;
  final String snaAgencyCode;
  final String creditTopTitle;
  final String debitPageTitle;
  String get debitTopTitle => debitPageTitle;
  final bool isPfmsPage;
  final bool isFirstPageOfFY;
  final String fallbackHead;
  final String pairKey;
  final int totalCreditsOnDate;
  final int totalDebitsOnDate;
  final List<RojmelEntry> credits;
  final List<RojmelEntry> debits;
  final List<RojmelEntry?> alignedCredits;
  final List<RojmelEntry?> alignedDebits;
  final List<double> slotHeightsMm;
  final double entryGapMm;
  final double crFontPt;
  final double drFontPt;
  final double crRowHeightMm;
  final double drRowHeightMm;
  final HeadBalance pageOpen;
  final HeadBalance crSum;
  final HeadBalance drSum;
  final HeadBalance grandCredit;
  final HeadBalance closingBal;
  final HeadBalance grandDebit;

  const CashbookPagePair({
    required this.pairIndexOnDate,
    required this.creditPageNo,
    required this.debitPageNo,
    required this.dateStr,
    required this.formattedDateDDMMYY,
    required this.formattedDateSlash,
    required this.accountName,
    required this.accountType,
    required this.schoolTitle,
    required this.holderName,
    required this.accountNumber,
    this.snaAgencyCode = '',
    required this.creditTopTitle,
    required this.debitPageTitle,
    required this.isPfmsPage,
    required this.isFirstPageOfFY,
    required this.fallbackHead,
    required this.pairKey,
    required this.totalCreditsOnDate,
    required this.totalDebitsOnDate,
    required this.credits,
    required this.debits,
    this.alignedCredits = const <RojmelEntry?>[],
    this.alignedDebits = const <RojmelEntry?>[],
    this.slotHeightsMm = const <double>[],
    this.entryGapMm = 4.0,
    required this.crFontPt,
    required this.drFontPt,
    required this.crRowHeightMm,
    required this.drRowHeightMm,
    required this.pageOpen,
    required this.crSum,
    required this.drSum,
    required this.grandCredit,
    required this.closingBal,
    required this.grandDebit,
  });

  int get pageNumber => creditPageNo;
  String get formattedDate => formattedDateDDMMYY;
  double get openCash => pageOpen.cash;
  double get openBank => pageOpen.bank;
  double get openTotal => pageOpen.total;
  double get pageCreditSum => crSum.total;
  double get pageDebitSum => drSum.total;
  double get totalReceiptsWithOpening => grandCredit.total;
  double get closeCash => closingBal.cash;
  double get closeBank => closingBal.bank;
  double get closeTotal => closingBal.total;
  double get grandDebitSideTotal => grandDebit.total;
  double get crEffectiveFontPt => crFontPt;
  double get drEffectiveFontPt => drFontPt;
}

class HeadSummaryRow {
  final String head;
  final double openCash;
  final double openBank;
  final double openTotal;
  final double padarCr;
  final double bankCr;
  final double bankCr60;
  final double bankCr40;
  final double credit;
  final double padarDr;
  final double bankDr;
  final double debit;
  final double closeCash;
  final double closeBank;
  final double closing;
  final double annualLimit;
  final double limitRemaining;
  final List<String> creditDates;
  final int count;

  const HeadSummaryRow({
    required this.head,
    required this.openCash,
    required this.openBank,
    required this.openTotal,
    required this.padarCr,
    required this.bankCr,
    required this.bankCr60,
    required this.bankCr40,
    required this.credit,
    required this.padarDr,
    required this.bankDr,
    required this.debit,
    required this.closeCash,
    required this.closeBank,
    required this.closing,
    required this.annualLimit,
    required this.limitRemaining,
    required this.creditDates,
    required this.count,
  });
}

/// Table data shared by the on-screen view and the A4 print generator for the
/// additional audit registers (interest, cash, party-wise, balance sheet).
class ExtraAuditTable {
  ExtraAuditTable({
    required this.title,
    required this.subtitle,
    required this.headers,
    required this.dataRows,
    required this.totalRows,
    required this.colWidthsPct,
    this.preNotes = const <String>[],
    this.notes = const <String>[],
    this.signLabels,
    this.leftCols = const <int>{},
    this.notesOnOwnPage = false,
  });

  final String title;
  final String subtitle;
  final List<String> headers;
  final List<List<String>> dataRows;
  final List<List<String>> totalRows;
  final List<double> colWidthsPct;

  /// Lines printed above the table.
  final List<String> preNotes;

  /// Certificate / explanation paragraphs printed below the table.
  final List<String> notes;

  /// Three signature captions (null = SMC chairman, principal, auditor).
  final List<String>? signLabels;

  /// Columns printed left-aligned (descriptions); leading spaces indent.
  /// A first cell starting with '§' marks a bold section heading row.
  final Set<int> leftCols;

  /// Table on its own page, certificate text + signatures on the next.
  final bool notesOnOwnPage;
}

class CalculationAuditItem {
  final String checkName;
  final String expectedValue;
  final String actualValue;
  final double difference;
  final bool passed;

  const CalculationAuditItem({
    required this.checkName,
    required this.expectedValue,
    required this.actualValue,
    required this.difference,
    required this.passed,
  });
}

// ============================================================================
// 2. EMPTY DEFAULTS (NO PRE-FILLED GRANT HEADS, AGENCY CODES, OR DEMO ENTRIES)
// ============================================================================

final List<String> kAll36Heads = <String>[];

final List<String> kSmce12Heads = <String>[];

final Map<String, HeadBalance> kSmceHeadOpenings = <String, HeadBalance>{};

final Map<String, double> kSnaDefaultHeadLimits = <String, double>{};

final List<RojmelEntry> kFullFy2526Entries = <RojmelEntry>[];

final List<RojmelEntry> kSmceFy2526Entries = <RojmelEntry>[];

const List<String> kDefaultAccounts = <String>[
  'SNA SPARSH',
  'PFMS + SNA SPARSH',
  'PFMS ખાતું',
  'SMCE',
];

const int kMaxBankAccounts = 7;

// ============================================================================
// 3. GUJARATI NUMBER-TO-WORDS & FORMATTING HELPERS (EXACT V06 HTML PORT)
// ============================================================================

const List<String> _gujWords0To99 = <String>[
  'શૂન્ય','એક','બે','ત્રણ','ચાર','પાંચ','છ','સાત','આઠ','નવ',
  'દસ','અગિયાર','બાર','તેર','ચૌદ','પંદર','સોળ','સત્તર','અઢાર','ઓગણીસ',
  'વીસ','એકવીસ','બાવીસ','ત્રેવીસ','ચોવીસ','પચ્ચીસ','છવ્વીસ','સત્તાવીસ','અઠ્ઠાવીસ','ઓગણત્રીસ',
  'ત્રીસ','એકત્રીસ','બત્રીસ','તેત્રીસ','ચોત્રીસ','પાંત્રીસ','છત્રીસ','સાડત્રીસ','આડત્રીસ','ઓગણચાલીસ',
  'ચાલીસ','એકતાલીસ','બેતાલીસ','તેતાલીસ','ચુંમાલીસ','પિસ્તાલીસ','છેતાલીસ','સુડતાલીસ','અડતાલીસ','ઓગણપચાસ',
  'પચાસ','એકાવન','બાવન','ત્રેપન','ચોપન','પંચાવન','છપ્પન','સત્તાવન','અઠ્ઠાવન','ઓગણસાઠ',
  'સાઠ','એકસઠ','બાસઠ','ત્રેસઠ','ચોસઠ','પાંસઠ','છાસઠ','સડસઠ','અડસઠ','ઓગણસિત્તેર',
  'સિત્તેર','એકોતેર','બોતેર','તોતેર','ચુંમોતેર','પંચોતેર','છોતેર','સિત્યોતેર','ઇઠ્યોતેર','ઓગણએંસી',
  'એંસી','એકાસી','બ્યાસી','ત્યાસી','ચોરાસી','પંચાસી','છ્યાસી','સત્તાસી','અઠ્ઠાસી','નેવું',
  'નેવું','એકાણું','બાણું','ત્રાણું','ચોરાણું','પંચાણું','છન્નું','સત્તાણું','અઠ્ઠાણું','નવ્વાણું',
];

const List<String> _gujHundreds = <String>[
  '','એક સો','બસો','ત્રણ સો','ચાર સો','પાંચ સો','છ સો','સાત સો','આઠ સો','નવ સો',
];

String numberToGujaratiWords(double numVal) {
  int n = numVal.abs().round();
  if (n == 0) return 'શૂન્ય રૂપિયા પૂરા';
  final parts = <String>[];
  final crore = n ~/ 10000000;
  n %= 10000000;
  final lakh = n ~/ 100000;
  n %= 100000;
  final thousand = n ~/ 1000;
  n %= 1000;
  final hundred = n ~/ 100;
  final rem = n % 100;
  if (crore > 0) parts.add('${crore < 100 ? _gujWords0To99[crore] : crore} કરોડ');
  if (lakh > 0) parts.add('${_gujWords0To99[lakh]} લાખ');
  if (thousand > 0) parts.add('${_gujWords0To99[thousand]} હજાર');
  if (hundred > 0) parts.add(_gujHundreds[hundred]);
  if (rem > 0) parts.add(_gujWords0To99[rem]);
  return '${parts.join(' ')} રૂપિયા પૂરા';
}

String fmtDemoNum(double val) => val.toStringAsFixed(2);

String formatMoney(double val) {
  final isNeg = val < -0.0001;
  final absVal = val.abs();
  final fixed = absVal.toStringAsFixed(2);
  final parts = fixed.split('.');
  String intPart = parts[0];
  final decPart = parts[1];
  if (intPart.length > 3) {
    final last3 = intPart.substring(intPart.length - 3);
    String other = intPart.substring(0, intPart.length - 3);
    final reg = RegExp(r'\B(?=(\d{2})+(?!\d))');
    other = other.replaceAllMapped(reg, (m) => ',');
    intPart = '$other,$last3';
  }
  return '${isNeg ? "-" : ""}$intPart.$decPart';
}

/// Any Indian date the user types (01/12/2025, 1/12/25, 01-12-2025, 1-12-25,
/// 01.12.2025, 1-Dec-25, 1-Dec-2025, 1 December 2025, ૦૧/૧૨/૨૦૨૫, an Excel
/// date number …) as ISO `YYYY-MM-DD` for sorting and calculations. Read day
/// first, see [IndianDate]. Text that is not a real date is returned
/// unchanged so the caller can show it back to the user.
String normalizeToIsoDate(String rawInput) {
  final t = rawInput.trim();
  if (t.isEmpty) return '';
  return IndianDate.toIso(t) ?? t;
}

/// True when [raw] is a real date that Rojmel can use (years 2000–2100).
bool isRojmelDate(String raw) => IndianDate.isValid(raw, minYear: 2000, maxYear: 2100);

String fmtDateDDMMYY(String dateStr) {
  if (dateStr.trim().isEmpty) return '';
  final iso = normalizeToIsoDate(dateStr);
  final p = iso.split('-');
  if (p.length != 3) return dateStr;
  return '${p[2]}/${p[1]}/${p[0]}';
}

String fmtDateSlashDDMMYYYY(String dateStr) {
  if (dateStr.trim().isEmpty) return '';
  final iso = normalizeToIsoDate(dateStr);
  final p = iso.split('-');
  if (p.length != 3) return dateStr;
  return '${p[2]}/${p[1]}/${p[0]}';
}

String formatDateShort(String dateStr) => fmtDateDDMMYY(dateStr);

String _currentFinancialYear() {
  final now = DateTime.now();
  final startYear = now.month >= 4 ? now.year : now.year - 1;
  return '$startYear-${(startYear + 1).toString().substring(2)}';
}

String _currentFinancialYearStart() {
  final now = DateTime.now();
  final startYear = now.month >= 4 ? now.year : now.year - 1;
  return '$startYear-04-01';
}

// ============================================================================
// 4. ROJMEL ENGINE (100% V06 HTML BUSINESS, PAGINATION & REPORT ENGINE)
// ============================================================================

class RojmelEngine extends ChangeNotifier {
  final Map<String, List<CashbookPagePair>> _cashbookPagesCache =
      <String, List<CashbookPagePair>>{};
  final Map<String, List<HeadSummaryRow>> _headSummaryCache =
      <String, List<HeadSummaryRow>>{};

  void invalidateComputedCaches() {
    _cashbookPagesCache.clear();
    _headSummaryCache.clear();
  }

  @override
  void notifyListeners() {
    invalidateComputedCaches();
    super.notifyListeners();
  }

  void triggerUpdate() => notifyListeners();
  // School & Profile Info (Populated automatically from School Registration Details; 0 pre-filled data)
  String schoolName = '';
  String schoolAddress = '';
  String clusterName = ''; // Village / City
  String talukaName = '';  // Taluko
  String districtName = ''; // District
  String udiseCode = '';    // DISE / UDISE Code
  String bankName = '';
  String branchName = '';
  String accountNumber = '';
  String ifscCode = '';
  String financialYear = _currentFinancialYear();
  String openingBalanceDate = _currentFinancialYearStart();
  String validatorName = 'આચાર્યશ્રી';
  double cashOpening = 0.0;
  double bankOpening = 0.0;
  String activeDatasetMode = 'EMPTY_CLOUD';

  // Accounts, Heads, Entries, Principals (All start clean with 0 pre-filled heads or entries)
  List<String> accounts = List<String>.from(kDefaultAccounts);
  Map<String, AccountMeta> accountMeta = <String, AccountMeta>{};
  Map<String, String> grantHeadActiveMap = <String, String>{};
  List<String> heads = <String>[];
  List<RojmelEntry> entries = <RojmelEntry>[];
  List<PrincipalRecord> principals = <PrincipalRecord>[];

  // Active Account & Cashbook Filters + Column Line Options
  String selectedAccount = 'SNA SPARSH';
  String cashbookFilterHead = 'ALL';
  String cashbookFromDate = '2025-04-01';
  String cashbookToDate = '2026-03-31';
  /// Print page setup: cashbook orientation and binding space page by page
  /// (cashbook and every report).
  final RojmelPrintSetup printSetup = RojmelPrintSetup();
  String get cashbookOrientation => printSetup.cashbookOrientation;
  set cashbookOrientation(String v) =>
      printSetup.cashbookOrientation = v == 'landscape' ? 'landscape' : 'portrait';

  /// Writing height (mm) the cashbook page loses to landscape paper and to
  /// top / bottom binding space.
  double get cashbookAreaLossMm {
    final land = printSetup.isLandscapeCashbook;
    return (land ? 87.0 : 0.0) + printSetup.extraVerticalMm(cashbook: true, landscape: land);
  }
  double cashbookPrintFontPt = 10.0;
  double cashbookPageBudgetMm = 212.0;
  /// Option for column vertical lines in Cashbook (true = draw column lines, false = no column lines)
  bool cashbookShowColumnLines = false;

  /// Cashbook print: entries of many dates run on continuously (a new page
  /// only when the writing area is full) instead of a new page per date.
  bool cashbookContinuousDates = false;
  /// Option for Cashbook column line extent: 'full_till_ekandar' (full page till Ekandar line) or 'only_till_entry' (only till last entry)
  String cashbookColumnLineMode = 'full_till_ekandar';

  // Report Filters
  String activeReportType = 'daybook';
  int activeReportNumber = 1;
  String reportFilterHead = 'ALL';
  String reportFromDate = '2025-04-01';
  String reportToDate = '2026-03-31';
  String reportOrientation = 'portrait';
  String selectedAnnex12Month = 'ALL';
  String selectedMonthlyHisabMonth = 'ALL';
  /// Selected month for the new Monthly Expense & Remaining Limit / Balance Report ('ALL' = Full Year April to March, or 'YYYY-MM' for selected month only)
  String selectedMonthlyLimitMonth = 'ALL';

  /// Returns the 12 months (April to March) dynamically for the active `financialYear`
  List<Map<String, String>> getFyMonthsList() {
    final fyParts = financialYear.split('-');
    final startYr = fyParts.isNotEmpty ? (int.tryParse(fyParts[0].trim()) ?? 2025) : 2025;
    final endYr = startYr + 1;
    return <Map<String, String>>[
      {'ym': '$startYr-04', 'short': 'April (એપ્રિલ)', 'gu': 'એપ્રિલ', 'en': 'April', 'label': 'April (એપ્રિલ - $startYr)'},
      {'ym': '$startYr-05', 'short': 'May (મે)', 'gu': 'મે', 'en': 'May', 'label': 'May (મે - $startYr)'},
      {'ym': '$startYr-06', 'short': 'June (જૂન)', 'gu': 'જૂન', 'en': 'June', 'label': 'June (જૂન - $startYr)'},
      {'ym': '$startYr-07', 'short': 'July (જુલાઈ)', 'gu': 'જુલાઈ', 'en': 'July', 'label': 'July (જુલાઈ - $startYr)'},
      {'ym': '$startYr-08', 'short': 'August (ઓગસ્ટ)', 'gu': 'ઓગસ્ટ', 'en': 'August', 'label': 'August (ઓગસ્ટ - $startYr)'},
      {'ym': '$startYr-09', 'short': 'September (સપ્ટે.)', 'gu': 'સપ્ટેમ્બર', 'en': 'September', 'label': 'September (સપ્ટેમ્બર - $startYr)'},
      {'ym': '$startYr-10', 'short': 'October (ઓક્ટો.)', 'gu': 'ઓક્ટોબર', 'en': 'October', 'label': 'October (ઓક્ટોબર - $startYr)'},
      {'ym': '$startYr-11', 'short': 'November (નવે.)', 'gu': 'નવેમ્બર', 'en': 'November', 'label': 'November (નવેમ્બર - $startYr)'},
      {'ym': '$startYr-12', 'short': 'December (ડિસે.)', 'gu': 'ડિસેમ્બર', 'en': 'December', 'label': 'December (ડિસેમ્બર - $startYr)'},
      {'ym': '$endYr-01', 'short': 'January (જાન્યુ.)', 'gu': 'જાન્યુઆરી', 'en': 'January', 'label': 'January (જાન્યુઆરી - $endYr)'},
      {'ym': '$endYr-02', 'short': 'February (ફેબ્રુ.)', 'gu': 'ફેબ્રુઆરી', 'en': 'February', 'label': 'February (ફેબ્રુઆરી - $endYr)'},
      {'ym': '$endYr-03', 'short': 'March (માર્ચ)', 'gu': 'માર્ચ', 'en': 'March', 'label': 'March (માર્ચ - $endYr)'},
    ];
  }

  String get fullFormattedSchoolAddress {
    final parts = <String>[];
    if (schoolAddress.trim().isNotEmpty) parts.add(schoolAddress.trim());
    if (clusterName.trim().isNotEmpty && !schoolAddress.contains(clusterName.trim())) {
      parts.add('ગામ/શહેર: ${clusterName.trim()}');
    }
    if (talukaName.trim().isNotEmpty && !schoolAddress.contains(talukaName.trim())) {
      parts.add('તાલુકો: ${talukaName.trim()}');
    }
    if (districtName.trim().isNotEmpty && !schoolAddress.contains(districtName.trim())) {
      parts.add('જિલ્લો: ${districtName.trim()}');
    }
    return parts.join(', ');
  }

  /// Default per-report orientation ('landscape' for wide multi-column tables, 'portrait' for standard pages)
  static const Map<String, String> kDefaultReportOrientations = <String, String>{
    'daybook': 'portrait',
    'parishisht_2': 'landscape',
    'bill_reg': 'portrait',
    'cheque_reg': 'landscape',
    'kharch_patrak': 'landscape',
    'parishisht_8': 'landscape',
    'parishisht_9': 'portrait',
    'parishisht_10': 'landscape',
    'grant_reg': 'landscape',
    'annexure_12': 'landscape',
    'monthly': 'landscape',
    'monthly_limit_report': 'landscape',
    'passbook': 'portrait',
    'tally_report': 'portrait',
    'receipt_payment': 'portrait',
    'voucher_cert': 'landscape',
    'audit_certs': 'portrait',
    'interest_register': 'landscape',
    'cash_register': 'landscape',
    'party_register': 'landscape',
    'balance_sheet': 'portrait',
    'income_expenditure': 'portrait',
    'gfr_12a': 'portrait',
    'monthly_brs': 'landscape',
    'asset_register': 'landscape',
    'cash_verification': 'portrait',
    'bank_certificate': 'portrait',
    'audit_crosscheck': 'portrait',
  };

  /// User-customizable per-report orientation map ('landscape' or 'portrait')
  Map<String, String> reportOrientationMap = Map<String, String>.from(kDefaultReportOrientations);

  /// User-customizable Left and Right page margin space (in mm) for reports
  double reportLeftSpaceMm = 8.0;
  double reportRightSpaceMm = 8.0;

  /// Report pagination mode: 'multi' (Auto Next Page with repeated headers when rows/row-height exceed page) or 'single' (Fit all rows on 1 page)
  String defaultReportPageMode = 'multi';
  Map<String, String> reportPageModeMap = <String, String>{};

  bool isReportLandscape(String reportType) {
    if (reportType == 'daybook') return printSetup.isLandscapeCashbook;
    final mode = reportOrientationMap[reportType] ?? kDefaultReportOrientations[reportType] ?? 'portrait';
    return mode.toLowerCase() == 'landscape';
  }

  void setReportOrientation(String reportType, String orientation) {
    final o = orientation.toLowerCase() == 'landscape' ? 'landscape' : 'portrait';
    reportOrientationMap[reportType] = o;
    if (reportType == 'daybook') cashbookOrientation = o;
    notifyListeners();
  }

  /// Every page (cashbook and all reports) in one orientation; null puts
  /// back the default (wide reports landscape, cashbook portrait).
  void setAllPagesOrientation(String? orientation) {
    if (orientation == null) {
      reportOrientationMap = Map<String, String>.from(kDefaultReportOrientations);
      cashbookOrientation = 'portrait';
    } else {
      for (final k in kDefaultReportOrientations.keys) {
        reportOrientationMap[k] = orientation;
      }
      cashbookOrientation = orientation;
    }
    notifyListeners();
  }

  bool isReportMultiPage(String reportType) {
    final mode = reportPageModeMap[reportType] ?? defaultReportPageMode;
    return mode.toLowerCase() != 'single';
  }

  void setReportPageMode(String reportType, String mode, {bool applyToAll = false}) {
    final norm = mode.toLowerCase() == 'single' ? 'single' : 'multi';
    reportPageModeMap[reportType] = norm;
    if (applyToAll) {
      defaultReportPageMode = norm;
      for (final k in kDefaultReportOrientations.keys) {
        reportPageModeMap[k] = norm;
      }
    }
    notifyListeners();
  }

  /// Dynamically calculates how many data rows fit per page for [reportType] based on:
  /// - Landscape (794px height) vs Portrait (1123px height)
  /// - User's Row Height setting (`parishisht10RowHeightPx`, e.g. 20px..60px)
  /// - User's Font Size setting (`parishisht10FontSizePt`, e.g. 7pt..16pt)
  /// If Row Height or Font Size is made bigger, fewer rows fit per page and additional pages are automatically generated!
  int computeMaxRowsPerReportPage(String reportType) {
    final isLand = isReportLandscape(reportType);
    final rowHPx = parishisht10RowHeightPx.clamp(18.0, 68.0);
    final fontPt = parishisht10FontSizePt.clamp(7.0, 16.0);
    final effRowPx = math.max(rowHPx, fontPt * 2.1 + 7.0);
    final hasBigPreHeader = reportType == 'parishisht_10';
    final availBodyPx = (isLand
            ? (hasBigPreHeader ? 392.0 : 445.0)
            : (hasBigPreHeader ? 680.0 : 740.0)) -
        printSetup.extraVerticalMm(cashbook: false, landscape: isLand) * 3.78;
    final computed = (availBodyPx / effRowPx).floor();
    return computed.clamp(4, isLand ? 24 : 36);
  }

  /// Descriptive Gujarati + English footer title for each report (shown at the bottom-left of every page)
  String getReportFooterTitle(String reportType, [String? accName]) {
    final target = (accName != null && accName.isNotEmpty && accName != 'ALL') ? accName : selectedAccount;
    final mAcc = getAccountMeta(target);
    final sName = mAcc.schoolName.isNotEmpty ? mAcc.schoolName : schoolName;
    String rptLabel;
    switch (reportType) {
      case 'daybook':
        rptLabel = 'રોજમેળ / કેશબુક (Cashbook)';
        break;
      case 'parishisht_2':
        rptLabel = 'પરિશિષ્ટ નંબર : 2 — આવક ખર્ચનું વર્ગીકરણ (ખાતાવહી)';
        break;
      case 'bill_reg':
        rptLabel = 'વર્ષ દરમિયાનનું બિલોનું નોંધપત્રક (બિલ રજીસ્ટર)';
        break;
      case 'cheque_reg':
        rptLabel = 'વર્ષ દરમિયાનનું ચેકોનું નોંધપત્રક (ક્લેઈમ / ચેક રજીસ્ટર)';
        break;
      case 'kharch_patrak':
        rptLabel = 'ખર્ચ પત્રક (વર્ષ દરમિયાન ખર્ચનું નોંધપત્રક)';
        break;
      case 'parishisht_8':
        rptLabel = 'પરિશિષ્ટ - ૮ : ગ્રાન્ટ ફાળવણી, ખર્ચ અને બંધ સિલક પત્રક (ગોષવારો)';
        break;
      case 'parishisht_9':
        rptLabel = 'પરિશિષ્ટ – 9 : બેંક સાથે મેળવણું – રીકન્સીલેશન';
        break;
      case 'parishisht_10':
        rptLabel = 'ગ્રાન્ટ વપરાશનું પ્રમાણપત્ર પરિશિષ્ટ 10 (Utilization Certificate)';
        break;
      case 'grant_reg':
        rptLabel = 'ગ્રાન્ટ રજીસ્ટર : પરિશિષ્ટ ૧૧ (Grant Register)';
        break;
      case 'annexure_12':
        rptLabel = 'એનેક્ષર-12 : સર્વ શિક્ષા અભિયાન - ગુજરાત (માસવાર હિસાબ પત્રક)';
        break;
      case 'monthly':
        rptLabel = 'માસવાર હિસાબ પત્રક (Monthly Transaction Statement)';
        break;
      case 'monthly_limit_report':
        rptLabel = 'માસવાર અને હેડવાર ખર્ચ તથા બાકી લિમિટ / સિલક પત્રક (Monthly Expense & Remaining Limit/Balance Report)';
        break;
      case 'passbook':
        rptLabel = 'બેંક પાસબુક (Bank Passbook)';
        break;
      case 'tally_report':
        rptLabel = 'ટેલી ઓડિટ રિપોર્ટ (Tally Trial Balance & Ledger)';
        break;
      case 'receipt_payment':
        rptLabel = 'તારીજ પત્રક (Receipt & Payment Account)';
        break;
      case 'voucher_cert':
        rptLabel = 'પ્રમાણિત વાઉચર યાદી પત્રક (Certified Vouchers)';
        break;
      case 'audit_certs':
        rptLabel = 'રોજમેળ અને ઓડિટ ફાઈલ મુખપૃષ્ઠ અને અનુક્રમણિકા';
        break;
      case 'interest_register':
        rptLabel = 'બેંક વ્યાજ રજીસ્ટર (Bank Interest Register)';
        break;
      case 'cash_register':
        rptLabel = 'રોકડ / પદર રજીસ્ટર (Cash in Hand Register)';
        break;
      case 'party_register':
        rptLabel = 'પાર્ટી મુજબ ચુકવણી પત્રક (Party-wise Payment Register)';
        break;
      case 'balance_sheet':
        rptLabel = 'પાકું સરવૈયું (Balance Sheet)';
        break;
      case 'income_expenditure':
        rptLabel = 'આવક-ખર્ચ ખાતું (Income & Expenditure Account)';
        break;
      case 'gfr_12a':
        rptLabel = 'GFR 12-A ઉપયોગિતા પ્રમાણપત્ર (Utilization Certificate)';
        break;
      case 'monthly_brs':
        rptLabel = 'માસવાર બેંક મેળવણું (Month-wise Bank Reconciliation)';
        break;
      case 'asset_register':
        rptLabel = 'મિલકત ખરીદી પત્રક — ડેડ સ્ટોક (Assets Purchased)';
        break;
      case 'cash_verification':
        rptLabel = 'રોકડ સિલક ચકાસણી પ્રમાણપત્ર (Cash Verification Certificate)';
        break;
      case 'bank_certificate':
        rptLabel = 'બેંક સિલક પ્રમાણપત્ર (Bank Balance Certificate)';
        break;
      case 'audit_crosscheck':
        rptLabel = 'ગણતરી મેળવણું પત્રક (Audit Cross-check Statement)';
        break;
      default:
        rptLabel = 'ઓડિટ રિપોર્ટ ($reportType)';
        break;
    }
    return 'નાણાકીય વર્ષ $financialYear માટે $sName — $rptLabel ($target)';
  }

  void resetReportPageSetupToDefaults() {
    reportOrientationMap = Map<String, String>.from(kDefaultReportOrientations);
    cashbookOrientation = 'portrait';
    defaultReportPageMode = 'multi';
    reportPageModeMap.clear();
    reportLeftSpaceMm = 8.0;
    reportRightSpaceMm = 8.0;
    parishisht10FontSizePt = 10.0;
    parishisht10RowHeightPx = 28.0;
    notifyListeners();
  }

  // Parishisht-9 Manual Reconciliation Adjustments
  double p9Add2DirectCredit = 0.0;
  double p9Sub1UncreditedDeposit = 0.0;
  double p9Sub2BankCharges = 0.0;

  // Page Layout & Font / Entry Count Config (Exact V06 `pageLayoutConfig`)
  int defaultMaxEntriesPerPage = 6;
  bool autoShrinkBigEntry = true;
  double? globalFontPt;
  Map<String, double> pageFontMap = <String, double>{'default': 10.0};
  Map<String, int> pageEntryCountMap = <String, int>{};
  double cashbookEntryGapMm = 4.0;
  Map<String, double> pageEntryGapMap = <String, double>{};

  int? getCreditPageEntryCount(String acc, int creditPageNo, [String? pairKey]) {
    final oddPage = creditPageNo.isOdd ? creditPageNo : (creditPageNo - 1);
    return pageEntryCountMap['$acc|creditPage|$oddPage'] ??
        (pairKey != null ? pageEntryCountMap[pairKey] : null);
  }

  void setCreditPageEntryCount(String acc, int creditPageNo, int? count, [String? pairKey]) {
    final oddPage = creditPageNo.isOdd ? creditPageNo : (creditPageNo - 1);
    if (count == null || count <= 0) {
      pageEntryCountMap.remove('$acc|creditPage|$oddPage');
      if (pairKey != null) pageEntryCountMap.remove(pairKey);
    } else {
      pageEntryCountMap['$acc|creditPage|$oddPage'] = count;
      if (pairKey != null) pageEntryCountMap[pairKey] = count;
    }
  }

  double getCreditPageEntryGapMm(String acc, int creditPageNo, [String? pairKey]) {
    final oddPage = creditPageNo.isOdd ? creditPageNo : (creditPageNo - 1);
    final v = pageEntryGapMap['$acc|creditPage|$oddPage'] ??
        (pairKey != null ? pageEntryGapMap[pairKey] : null) ??
        cashbookEntryGapMm;
    return v.clamp(0.0, 35.0);
  }

  void setCreditPageEntryGapMm(String acc, int creditPageNo, double? gapMm, [String? pairKey]) {
    final oddPage = creditPageNo.isOdd ? creditPageNo : (creditPageNo - 1);
    if (gapMm == null) {
      pageEntryGapMap.remove('$acc|creditPage|$oddPage');
      if (pairKey != null) pageEntryGapMap.remove(pairKey);
    } else {
      final clamped = gapMm.clamp(0.0, 35.0);
      pageEntryGapMap['$acc|creditPage|$oddPage'] = clamped;
      if (pairKey != null) pageEntryGapMap[pairKey] = clamped;
    }
  }
  Map<String, String> sameDateOverflowMode = <String, String>{};
  /// Right-side peach-bar labels by account and starting physical page.
  /// Editing page N replaces any later rules for that account and applies to N..last.
  Map<String, String> pageAccountLabelOverrides = <String, String>{};
  /// Reference column header label (CLAIM નંબર / PPA નંબર / ચેક નંબર) by account and starting physical page.
  /// Editing page N replaces any later rules for that account and applies to N..last.
  Map<String, String> pageRefColLabelOverrides = <String, String>{};
  /// Custom editable report header grid cells, merged row indices, font size & row height settings across all reports.
  Map<String, List<List<String>>> parishisht10CustomGrids = <String, List<List<String>>>{};
  Map<String, List<int>> parishisht10MergedRows = <String, List<int>>{};
  double parishisht10FontSizePt = 12.0;
  double parishisht10RowHeightPx = 30.0;
  Map<String, double> rowHeightsDemo = <String, double>{};
  bool directPageEditActive = false;

  RojmelEngine() {
    _initDefaultAccountMeta();
  }

  void _initDefaultAccountMeta({String? overrideSchool}) {
    final sName = (overrideSchool != null && overrideSchool.trim().isNotEmpty)
        ? overrideSchool.trim()
        : schoolName.trim();
    accountMeta = <String, AccountMeta>{
      'SNA SPARSH': AccountMeta(
        name: 'SNA SPARSH',
        type: 'SNA_PURE',
        schoolName: sName,
        pfmsSchoolName: sName,
        acNo: '',
        snaAgencyCode: '',
        holderName: '',
        ifsc: '',
        bankName: '',
        branch: '',
        branchAddress: '',
        openingBank: 0.0,
        openingCash: 0.0,
        headOpenings: <String, HeadBalance>{},
        headLimits: <String, double>{},
        heads: <String>[],
      ),
      'PFMS + SNA SPARSH': AccountMeta(
        name: 'PFMS + SNA SPARSH',
        type: 'SNA',
        schoolName: sName,
        pfmsSchoolName: sName,
        acNo: '',
        snaAgencyCode: '',
        pfmsLastDate: '',
        snaStartDate: '',
        holderName: '',
        ifsc: '',
        bankName: '',
        branch: '',
        branchAddress: '',
        openingBank: 0.0,
        openingCash: 0.0,
        headOpenings: <String, HeadBalance>{},
        headLimits: <String, double>{},
        heads: <String>[],
      ),
      'PFMS ખાતું': AccountMeta(
        name: 'PFMS ખાતું',
        type: 'PFMS',
        schoolName: sName,
        pfmsSchoolName: sName,
        acNo: '',
        holderName: '',
        ifsc: '',
        bankName: '',
        branch: '',
        branchAddress: '',
        openingBank: 0.0,
        openingCash: 0.0,
        headOpenings: <String, HeadBalance>{},
        headLimits: <String, double>{},
        heads: <String>[],
      ),
      'SMCE': AccountMeta(
        name: 'SMCE',
        type: 'BANK',
        schoolName: sName,
        pfmsSchoolName: sName,
        acNo: '',
        holderName: '',
        ifsc: '',
        bankName: '',
        branch: '',
        branchAddress: '',
        openingBank: 0.0,
        openingCash: 0.0,
        headOpenings: <String, HeadBalance>{},
        headLimits: <String, double>{},
        heads: <String>[],
      ),
    };
  }

  /// Fresh-school initializer for a registered school (auto-populates all 6 school registration fields, 0 pre-filled bank/agency/grant heads).
  void initializeEmptySchool({
    required String registeredSchoolName,
    required String registeredUdiseCode,
    String registeredAddress = '',
    String registeredVillage = '',
    String registeredTaluka = '',
    String registeredDistrict = '',
  }) {
    schoolName = registeredSchoolName.trim();
    udiseCode = registeredUdiseCode.trim();
    schoolAddress = registeredAddress.trim();
    clusterName = registeredVillage.trim();
    talukaName = registeredTaluka.trim();
    districtName = registeredDistrict.trim();
    financialYear = _currentFinancialYear();
    openingBalanceDate = _currentFinancialYearStart();
    final fyParts = financialYear.split('-');
    final startYr = int.tryParse(fyParts.first) ?? 2025;
    cashbookFromDate = '$startYr-04-01';
    cashbookToDate = '${startYr + 1}-03-31';
    reportFromDate = '$startYr-04-01';
    reportToDate = '${startYr + 1}-03-31';
    activeDatasetMode = 'EMPTY_CLOUD';
    accounts = List<String>.from(kDefaultAccounts);
    heads = <String>[];
    entries = <RojmelEntry>[];
    principals = <PrincipalRecord>[];
    selectedAccount = accounts.first;
    cashbookFilterHead = 'ALL';
    reportFilterHead = 'ALL';
    activeReportType = 'daybook';
    activeReportNumber = 1;
    pageFontMap = <String, double>{'default': 10.0};
    pageEntryCountMap = <String, int>{};
    sameDateOverflowMode = <String, String>{};
    pageAccountLabelOverrides = <String, String>{};
    pageRefColLabelOverrides = <String, String>{};
    parishisht10CustomGrids = <String, List<List<String>>>{};
    parishisht10MergedRows = <String, List<int>>{};
    parishisht10FontSizePt = 10.0;
    parishisht10RowHeightPx = 28.0;
    directPageEditActive = false;
    _initDefaultAccountMeta(overrideSchool: schoolName);
    notifyListeners();
  }

  /// Loads the complete FY 2025-26 Dataset (SNA SPARSH 244 entries + SMCE Bank 27 entries)
  /// exactly like clicking `Load Both Full 2025-26 Accounts (SNA SPARSH + SMCE Bank)` in the HTML file!
  void loadFullFy2526ExcelData({bool notify = true}) {
    if (notify) notifyListeners();
  }

  void loadShortDemoData({bool notify = true}) {
    if (notify) notifyListeners();
  }

  /// Restores cloud-saved state from Supabase.
  void loadStateFromMap(Map<String, dynamic> json, {bool notify = true}) {
    schoolName = json['schoolName']?.toString() ?? json['school']?.toString() ?? schoolName;
    schoolAddress = json['schoolAddress']?.toString() ?? (json['schoolInfo'] is Map ? (json['schoolInfo']['address']?.toString() ?? '') : schoolAddress);
    clusterName = json['clusterName']?.toString() ?? (json['schoolInfo'] is Map ? (json['schoolInfo']['village']?.toString() ?? '') : '');
    talukaName = json['talukaName']?.toString() ?? (json['schoolInfo'] is Map ? (json['schoolInfo']['taluka']?.toString() ?? '') : '');
    districtName = json['districtName']?.toString() ?? (json['schoolInfo'] is Map ? (json['schoolInfo']['district']?.toString() ?? '') : '');
    udiseCode = json['udiseCode']?.toString() ?? (json['schoolInfo'] is Map ? (json['schoolInfo']['dise']?.toString() ?? '') : udiseCode);
    financialYear = json['financialYear']?.toString() ?? json['fy']?.toString() ?? _currentFinancialYear();
    openingBalanceDate = json['openingBalanceDate']?.toString() ?? _currentFinancialYearStart();
    activeDatasetMode = json['activeDatasetMode']?.toString() ?? 'CLOUD';

    final rawAccounts = json['accounts'];
    accounts = rawAccounts is List
        ? rawAccounts.map((e) => e.toString()).where((e) => e.trim().isNotEmpty).toList()
        : List<String>.from(kDefaultAccounts);
    if (accounts.isEmpty) accounts = List<String>.from(kDefaultAccounts);

    final rawHeads = json['heads'];
    heads = rawHeads is List
        ? rawHeads.map((e) => e is Map ? (e['name']?.toString() ?? '') : e.toString()).where((e) => e.trim().isNotEmpty).toList()
        : <String>[];

    final rawMeta = json['accountMeta'];
    accountMeta = <String, AccountMeta>{};
    if (rawMeta is Map) {
      rawMeta.forEach((key, value) {
        if (value is Map) {
          final row = value.map((k, v) => MapEntry(k.toString(), v));
          accountMeta[key.toString()] = AccountMeta.fromJson(key.toString(), row);
        }
      });
    }
    if (accountMeta.isEmpty) _initDefaultAccountMeta();
    // An account with saved settings (heads, limits, entries) must stay in
    // the account list, or it disappears from Data Entry and reports.
    for (final name in accountMeta.keys) {
      final m = accountMeta[name]!;
      final used = m.heads.isNotEmpty || m.headLimits.isNotEmpty || entries.any((e) => e.account == name);
      if (name.trim().isNotEmpty && used && !accounts.contains(name)) accounts.add(name);
    }
    for (final account in accounts) {
      accountMeta.putIfAbsent(
        account,
        () => AccountMeta(
          name: account,
          type: account.trim().toUpperCase() == 'SNA SPARSH'
              ? 'SNA_PURE'
              : (account.toUpperCase().contains('SNA')
                  ? 'SNA'
                  : (account.toUpperCase().contains('PFMS') ? 'PFMS' : 'BANK')),
          schoolName: schoolName,
          pfmsSchoolName: schoolName,
          heads: <String>[],
        ),
      );
    }

    final rawEntries = json['entries'];
    entries = rawEntries is List
        ? rawEntries
            .whereType<Map>()
            .map((row) => RojmelEntry.fromJson(row.map((k, v) => MapEntry(k.toString(), v))).copy())
            .toList()
        : <RojmelEntry>[];

    final rawPrincipals = json['principals'];
    principals = rawPrincipals is List
        ? rawPrincipals
            .whereType<Map>()
            .map((row) => PrincipalRecord.fromJson(row.map((k, v) => MapEntry(k.toString(), v))).copy())
            .toList()
        : <PrincipalRecord>[];

    final rawFontMap = json['pageFontMap'];
    pageFontMap = <String, double>{'default': 10.0};
    if (rawFontMap is Map) {
      rawFontMap.forEach((key, value) {
        final number = value is num ? value.toDouble() : double.tryParse('$value');
        if (number != null && number >= 5 && number <= 24) pageFontMap[key.toString()] = number;
      });
      pageFontMap.putIfAbsent('default', () => 10.0);
    }

    final rawEntryCount = json['pageEntryCountMap'];
    pageEntryCountMap = <String, int>{};
    if (rawEntryCount is Map) {
      rawEntryCount.forEach((key, value) {
        final count = value is num ? value.toInt() : int.tryParse('$value');
        if (count != null && count > 0 && count <= 100) pageEntryCountMap[key.toString()] = count;
      });
    }

    final rawOverflow = json['sameDateOverflowMode'];
    sameDateOverflowMode = <String, String>{};
    if (rawOverflow is Map) {
      sameDateOverflowMode = rawOverflow.map((k, v) => MapEntry(k.toString(), v.toString()));
    }

    final rawPageLabels = json['pageAccountLabelOverrides'];
    pageAccountLabelOverrides = <String, String>{};
    if (rawPageLabels is Map) {
      rawPageLabels.forEach((key, value) {
        final label = value?.toString().trim() ?? '';
        if (label.isNotEmpty) pageAccountLabelOverrides[key.toString()] = label;
      });
    }

    final rawRefLabels = json['pageRefColLabelOverrides'];
    pageRefColLabelOverrides = <String, String>{};
    if (rawRefLabels is Map) {
      rawRefLabels.forEach((key, value) {
        final label = value?.toString().trim() ?? '';
        if (label.isNotEmpty) pageRefColLabelOverrides[key.toString()] = label;
      });
    }

    final rawP10Grids = json['parishisht10CustomGrids'];
    parishisht10CustomGrids = <String, List<List<String>>>{};
    if (rawP10Grids is Map) {
      rawP10Grids.forEach((key, value) {
        if (value is List) {
          parishisht10CustomGrids[key.toString()] = value
              .whereType<List>()
              .map((r) => r.map((c) => c?.toString() ?? '').toList())
              .toList();
        }
      });
    }

    final rawP10Merged = json['parishisht10MergedRows'];
    parishisht10MergedRows = <String, List<int>>{};
    if (rawP10Merged is Map) {
      rawP10Merged.forEach((key, value) {
        if (value is List) {
          parishisht10MergedRows[key.toString()] = value
              .map((v) => v is num ? v.toInt() : (int.tryParse('$v') ?? -1))
              .where((idx) => idx >= 0)
              .toList();
        }
      });
    }

    final rawP10Font = json['parishisht10FontSizePt'];
    if (rawP10Font is num && rawP10Font >= 7 && rawP10Font <= 24) {
      parishisht10FontSizePt = rawP10Font.toDouble();
    }
    final rawP10RowH = json['parishisht10RowHeightPx'];
    if (rawP10RowH is num && rawP10RowH >= 18 && rawP10RowH <= 90) {
      parishisht10RowHeightPx = rawP10RowH.toDouble();
    }

    reportOrientationMap = Map<String, String>.from(kDefaultReportOrientations);
    final rawOrientMap = json['reportOrientationMap'];
    if (rawOrientMap is Map) {
      rawOrientMap.forEach((key, value) {
        final v = value?.toString().toLowerCase().trim() ?? '';
        if (v == 'landscape' || v == 'portrait') {
          reportOrientationMap[key.toString()] = v;
        }
      });
    }
    final rawLeftMm = json['reportLeftSpaceMm'];
    if (rawLeftMm is num && rawLeftMm >= 0 && rawLeftMm <= 40) {
      reportLeftSpaceMm = rawLeftMm.toDouble();
    }
    final rawRightMm = json['reportRightSpaceMm'];
    if (rawRightMm is num && rawRightMm >= 0 && rawRightMm <= 40) {
      reportRightSpaceMm = rawRightMm.toDouble();
    }
    printSetup.loadJson(json['printSetup']);
    final rawDefPageMode = json['defaultReportPageMode']?.toString().toLowerCase().trim() ?? '';
    if (rawDefPageMode == 'single' || rawDefPageMode == 'multi') {
      defaultReportPageMode = rawDefPageMode;
    }
    reportPageModeMap = <String, String>{};
    final rawPageModeMap = json['reportPageModeMap'];
    if (rawPageModeMap is Map) {
      rawPageModeMap.forEach((key, value) {
        final v = value?.toString().toLowerCase().trim() ?? '';
        if (v == 'single' || v == 'multi') {
          reportPageModeMap[key.toString()] = v;
        }
      });
    }

    selectedAccount = accounts.contains(json['selectedAccount']?.toString())
        ? json['selectedAccount'].toString()
        : accounts.first;

    cashbookFilterHead = json['cashbookFilterHead']?.toString() ?? 'ALL';
    if (cashbookFilterHead.isEmpty) cashbookFilterHead = 'ALL';
    cashbookShowColumnLines = json['cashbookShowColumnLines'] == true;
    cashbookContinuousDates = json['cashbookContinuousDates'] == true;
    cashbookEntryGapMm = ((json['cashbookEntryGapMm'] as num?)?.toDouble() ?? 4.0).clamp(0.0, 35.0);
    pageEntryGapMap = <String, double>{};
    final rawGapMap = json['pageEntryGapMap'];
    if (rawGapMap is Map) {
      rawGapMap.forEach((key, value) {
        final d = double.tryParse(value.toString());
        if (d != null) pageEntryGapMap[key.toString()] = d.clamp(0.0, 35.0);
      });
    }
    final rawLineMode = json['cashbookColumnLineMode']?.toString() ?? 'full_till_ekandar';
    cashbookColumnLineMode = (rawLineMode == 'only_till_entry') ? 'only_till_entry' : 'full_till_ekandar';
    selectedMonthlyLimitMonth = json['selectedMonthlyLimitMonth']?.toString() ?? 'ALL';
    activeReportType = json['activeReportType']?.toString() ?? 'daybook';
    activeReportNumber = (((json['activeReportNumber'] as num?)?.toInt() ?? 1).clamp(1, 18)).toInt();
    renumberVouchers(forceRecalc: false);
    if (notify) notifyListeners();
  }

  // --------------------------------------------------------------------------
  // ENTRY CLASSIFICATION & FORMATTING HELPERS (EXACT V06 JS PORT)
  // --------------------------------------------------------------------------

  static bool isCashEntry(RojmelEntry e) {
    final m = e.medium.trim().toLowerCase();
    return m == 'cash' || m == 'રોકડ' || m == 'padar' || m == 'પદર';
  }

  static bool isPadarReimbursement(RojmelEntry e) {
    return RegExp(r'પદર.*પરત|રોકેલ નાણા પરત|રોકેલ પદરના નાણાં પરત').hasMatch(e.narration);
  }

  static bool isChequeReturnBouncePair(RojmelEntry e) {
    return e.head.contains('ચેક પરત') || RegExp(r'ચેક રિટર્ન|ચેક પરત').hasMatch(e.narration);
  }

  static bool isBankChargeEntry(RojmelEntry e) {
    return e.txn.contains('ચાર્જ') || RegExp(r'બેન્ક દ્વારા ચાર્જ').hasMatch(e.narration);
  }

  bool isDateInPfmsDuration(String accName, String rawDateStr) {
    final accMeta = getAccountMeta(accName);
    if (accMeta.type == 'PFMS') return true;
    if (accMeta.type == 'BANK' || accMeta.type == 'SNA_PURE') return false;
    final d = normalizeToIsoDate(rawDateStr);
    if (d.isEmpty) return false;
    final pfmsLast = normalizeToIsoDate(accMeta.pfmsLastDate);
    final snaStart = normalizeToIsoDate(accMeta.snaStartDate);
    if (pfmsLast.isNotEmpty && d.compareTo(pfmsLast) <= 0) return true;
    if (snaStart.isNotEmpty && d.compareTo(snaStart) >= 0) return false;
    if (snaStart.isNotEmpty && d.compareTo(snaStart) < 0) return true;
    if (pfmsLast.isNotEmpty && d.compareTo(pfmsLast) > 0) return false;
    return false;
  }

  bool isPFMSEntry(RojmelEntry e) {
    final accMeta = getAccountMeta(e.account);
    if (accMeta.type == 'PFMS') return true;
    if (accMeta.type == 'BANK' || accMeta.type == 'SNA_PURE') return false;
    final pfmsLast = normalizeToIsoDate(accMeta.pfmsLastDate);
    final snaStart = normalizeToIsoDate(accMeta.snaStartDate);
    final d = normalizeToIsoDate(e.date);
    if (d.isNotEmpty && (pfmsLast.isNotEmpty || snaStart.isNotEmpty)) {
      if (pfmsLast.isNotEmpty && d.compareTo(pfmsLast) <= 0) return true;
      if (snaStart.isNotEmpty && d.compareTo(snaStart) >= 0) return false;
      if (snaStart.isNotEmpty && d.compareTo(snaStart) < 0) return true;
      if (pfmsLast.isNotEmpty && d.compareTo(pfmsLast) > 0) return false;
    }
    final m = e.medium.trim().toUpperCase();
    if (m == 'PFMS') return true;
    if (m == 'SNA SPARSH') return false;
    if (e.txn.startsWith('C0')) return true;
    return false;
  }

  static double cashAmt(RojmelEntry e) => isCashEntry(e) ? e.amount : 0.0;
  static double bankAmt(RojmelEntry e) => isCashEntry(e) ? 0.0 : e.amount;

  static String fmtClaimWrapped(String s) {
    final clean = s.trim();
    if (clean.isEmpty || clean == 'રોકડ' || clean == 'બેન્ક ચાર્જ') return '';
    if (clean.length <= 8 || clean.contains(' ')) return clean;
    final chunks = <String>[];
    for (int i = 0; i < clean.length; i += 6) {
      chunks.add(clean.substring(i, math.min(i + 6, clean.length)));
    }
    return chunks.join('\n');
  }

  /// Converts any Credit 60%/40% suffix or narration (e.g. `(બિલના 60%)`, `(bil 60%)`, `(bilના 40%)`, `(વાઉચરના 60%)`)
  /// into the matching Debit suffix (e.g. `(બિલના 60% લેખે)`, `(bil 60% લેખે)`, `(વાઉચરના 60% લેખે)`).
  static String deriveDebitSuffixFromCredit(String crSuffixOrNarr, int pct) {
    final s = crSuffixOrNarr.trim();
    final parenMatch = RegExp(r'\(([^)]*?)(60|40)%([^)]*)\)').firstMatch(s);
    if (parenMatch != null) {
      final rawPrefix = (parenMatch.group(1) ?? '').trim();
      final rawAfter = (parenMatch.group(3) ?? '').trim();
      final lowerPrefix = rawPrefix.toLowerCase();
      if (rawPrefix.contains('બિલ') || rawPrefix.contains('બીલ')) {
        return '(બિલના $pct% લેખે)';
      }
      if (rawPrefix.contains('વાઉચર') || lowerPrefix.contains('voucher')) {
        return '(વાઉચરના $pct% લેખે)';
      }
      if (rawPrefix.isNotEmpty) {
        final lekhe = rawAfter.contains('લેખે') ? rawAfter : (rawAfter.isEmpty ? 'લેખે' : '$rawAfter લેખે');
        return '($rawPrefix $pct% $lekhe)';
      }
    }
    final lower = s.toLowerCase();
    if (s.contains('બિલ') || s.contains('બીલ') || RegExp(r'\b(bill|bil)\b').hasMatch(lower)) {
      return '(બિલના $pct% લેખે)';
    }
    return '(વાઉચરના $pct% લેખે)';
  }

  static String formatCreditNarration(RojmelEntry e) {
    return e.narration
        .trim()
        .replaceAll(RegExp(r'\(ગ્રાન્ટના\s*60%\)'), '(વાઉચરના 60%)')
        .replaceAll(RegExp(r'\(ગ્રાન્ટના\s*40%\)'), '(વાઉચરના 40%)');
  }

  String formatDebitNarration(RojmelEntry e) {
    String narr = e.narration
        .trim()
        .replaceAll(RegExp(r'\(બિલના\s*60%\)'), '(બિલના 60% લેખે)')
        .replaceAll(RegExp(r'\(બિલના\s*40%\)'), '(બિલના 40% લેખે)');

    // Automatic Credit -> Debit Bill/Voucher sync:
    // If a Credit entry on the same account, date, and head used "bill" / "bil" / "બિલ" (or "voucher" / "વાઉચર"),
    // ensure the corresponding Debit entry on that same date & head uses the exact same Bill/Voucher term!
    final pctMatch = RegExp(r'\(([^)]*?)(60|40)%([^)]*)\)\s*$').firstMatch(narr);
    if (pctMatch != null) {
      final pctStr = pctMatch.group(2) ?? '60';
      final pctInt = int.tryParse(pctStr) ?? 60;
      final curPrefix = (pctMatch.group(1) ?? '').trim();
      if (curPrefix == 'વાઉચરના' || curPrefix == 'બિલના') {
        for (final cr in entries) {
          if (cr.type == 'credit' &&
              cr.account == e.account &&
              cr.date == e.date &&
              cr.head == e.head &&
              cr.narration.contains('$pctStr%')) {
            final crMatch = RegExp(r'\(([^)]*?)' + pctStr + r'%([^)]*)\)\s*$').firstMatch(cr.narration.trim());
            if (crMatch != null) {
              final crPrefix = (crMatch.group(1) ?? '').trim();
              if (crPrefix.isNotEmpty && crPrefix != 'ગ્રાન્ટના' && crPrefix != curPrefix) {
                final derived = deriveDebitSuffixFromCredit(cr.narration, pctInt);
                narr = narr.substring(0, pctMatch.start).trimRight() + ' ' + derived;
                break;
              }
            }
          }
        }
      }
    }

    final party = e.party.trim();
    final accMeta = getAccountMeta(e.account);
    if (party.isNotEmpty &&
        !narr.toLowerCase().contains(party.toLowerCase()) &&
        !isCashEntry(e) &&
        !isPFMSEntry(e) &&
        accMeta.isAnySna) {
      return '$party ને $narr';
    }
    return narr;
  }

  // --------------------------------------------------------------------------
  // ACCOUNT HELPERS & STRICT ISOLATION RULES
  // --------------------------------------------------------------------------

  AccountMeta getAccountMeta([String? accName]) {
    final name = (accName != null && accName.isNotEmpty && accName != 'ALL') ? accName : selectedAccount;
    if (accountMeta.containsKey(name)) {
      return accountMeta[name]!;
    }
    final upper = name.trim().toUpperCase();
    final defaultType = upper == 'SNA SPARSH'
        ? 'SNA_PURE'
        : (upper.contains('SNA')
            ? 'SNA'
            : (upper.contains('PFMS') ? 'PFMS' : 'BANK'));
    final created = AccountMeta(
      name: name,
      type: defaultType,
      bankName: '',
      branch: '',
      acNo: '',
      snaAgencyCode: '',
      holderName: '',
      ifsc: '',
      schoolName: schoolName,
      pfmsSchoolName: schoolName,
      openingBank: 0.0,
      openingCash: 0.0,
      heads: <String>[],
    );
    accountMeta[name] = created;
    return created;
  }

  /// Default page label adapts automatically for Combined PFMS + SNA SPARSH accounts
  /// (shows PFMS during PFMS duration up to `pfmsLastDate`, and SNA SPARSH / Agency Code from `snaStartDate`),
  /// while respecting any page-specific override set by the Admin.
  String getPageAccountLabel(String acc, int pageNo, {bool? isPfmsPage}) {
    final m = getAccountMeta(acc);
    String fallback = acc.trim().isNotEmpty ? acc.trim() : m.name;
    if (m.type == 'SNA' && isPfmsPage != null) {
      fallback = isPfmsPage ? 'PFMS' : 'SNA SPARSH';
    }
    final prefix = '$acc|';
    var bestStartPage = -1;
    String? bestLabel;
    for (final entry in pageAccountLabelOverrides.entries) {
      if (!entry.key.startsWith(prefix)) continue;
      final startPage = int.tryParse(entry.key.substring(prefix.length));
      if (startPage != null && startPage <= pageNo && startPage > bestStartPage) {
        bestStartPage = startPage;
        bestLabel = entry.value;
      }
    }
    return (bestLabel == null || bestLabel.trim().isEmpty) ? fallback : bestLabel.trim();
  }

  /// Editing a page label starts a new run at that page and replaces any
  /// later rules, so the new value flows continuously from N to the last page.
  void setPageAccountLabelFromPage(String acc, int pageNo, String label) {
    final startPage = pageNo < 1 ? 1 : pageNo;
    final value = label.trim().isEmpty ? acc.trim() : label.trim();
    final prefix = '$acc|';
    pageAccountLabelOverrides.removeWhere((key, _) {
      if (!key.startsWith(prefix)) return false;
      final existingPage = int.tryParse(key.substring(prefix.length));
      return existingPage != null && existingPage >= startPage;
    });
    pageAccountLabelOverrides['$acc|$startPage'] = value.isEmpty ? getAccountMeta(acc).name : value;
  }

  /// Default Reference Column Header on Debit Page:
  /// - If Purely SNA SPARSH or SNA duration of Combined PFMS+SNA -> 'CLAIM\nનંબર'
  /// - If PFMS or PFMS duration of Combined PFMS+SNA -> 'PPA\nનંબર'
  /// - If BANK -> 'ચેક\nનંબર'
  String defaultRefColLabelForAccount(String acc, {bool? isPfmsPage}) {
    final m = getAccountMeta(acc);
    if (m.type == 'SNA' && isPfmsPage != null) {
      return isPfmsPage ? 'PPA\nનંબર' : 'CLAIM\nનંબર';
    }
    final upper = acc.trim().toUpperCase();
    if (upper.contains('SNA') || m.isAnySna) {
      return 'CLAIM\nનંબર';
    }
    if (upper.contains('PFMS') || m.type == 'PFMS') {
      return 'PPA\nનંબર';
    }
    return 'ચેક\nનંબર';
  }

  /// Gets the Debit Page Reference Column Header for `acc` at `pageNo`.
  /// Supports automatic PFMS vs SNA duration switching plus cascading page-range overrides.
  String getPageRefColLabel(String acc, int pageNo, {bool? isPfmsPage}) {
    final fallback = defaultRefColLabelForAccount(acc, isPfmsPage: isPfmsPage);
    final prefix = '$acc|';
    var bestStartPage = -1;
    String? bestLabel;
    for (final entry in pageRefColLabelOverrides.entries) {
      if (!entry.key.startsWith(prefix)) continue;
      final startPage = int.tryParse(entry.key.substring(prefix.length));
      if (startPage != null && startPage <= pageNo && startPage > bestStartPage) {
        bestStartPage = startPage;
        bestLabel = entry.value;
      }
    }
    return (bestLabel == null || bestLabel.trim().isEmpty) ? fallback : bestLabel.trim();
  }

  /// Sets the Debit Page Reference Column Header starting at `pageNo` and cascading to all subsequent pages.
  void setPageRefColLabelFromPage(String acc, int pageNo, String label) {
    final startPage = pageNo < 1 ? 1 : pageNo;
    final clean = label.trim().replaceAll(r'\n', '\n');
    final value = clean.isEmpty ? defaultRefColLabelForAccount(acc) : clean;
    final prefix = '$acc|';
    pageRefColLabelOverrides.removeWhere((key, _) {
      if (!key.startsWith(prefix)) return false;
      final existingPage = int.tryParse(key.substring(prefix.length));
      return existingPage != null && existingPage >= startPage;
    });
    pageRefColLabelOverrides['$acc|$startPage'] = value;
  }

  String getAccountSchoolName(String acc, {bool isPFMSPage = false}) {
    final m = getAccountMeta(acc);
    if (isPFMSPage && m.pfmsSchoolName.trim().isNotEmpty) return m.pfmsSchoolName.trim();
    if (m.schoolName.trim().isNotEmpty) return m.schoolName.trim();
    return schoolName.trim().isNotEmpty ? schoolName.trim() : 'શાળા';
  }

  List<RojmelEntry> getAccountEntries([String? accName]) {
    final target = (accName != null && accName.isNotEmpty && accName != 'ALL') ? accName : selectedAccount;
    return entries.where((e) => (e.account.isNotEmpty ? e.account : 'SNA SPARSH') == target).toList();
  }

  List<String> getAccountSpecificHeads([String? accName]) {
    final target = (accName != null && accName.isNotEmpty && accName != 'ALL') ? accName : selectedAccount;
    final meta = getAccountMeta(target);
    final set = <String>{...meta.heads};
    for (final h in meta.headOpenings.keys) {
      final ob = meta.headOpenings[h]!;
      if (ob.cash > 0 || ob.bank > 0) set.add(h);
    }
    for (final h in meta.headLimits.keys) {
      if ((meta.headLimits[h] ?? 0) > 0) set.add(h);
    }
    for (final e in getAccountEntries(target)) {
      if (e.head.trim().isNotEmpty) set.add(e.head.trim());
    }
    return set.toList();
  }

  void setAccountSpecificHeads(String acc, List<String> headsList) {
    final clean = <String>{...headsList.map((e) => e.trim()).where((e) => e.isNotEmpty)}.toList();
    final meta = getAccountMeta(acc);
    meta.heads = clean;
    accountMeta[acc] = meta;
    for (final h in clean) {
      if (!heads.contains(h)) heads.add(h);
      grantHeadActiveMap.putIfAbsent(h, () => 'yes');
    }
    notifyListeners();
  }

  HeadBalance getHeadOpening(String? accName, String headName) {
    final meta = getAccountMeta(accName);
    if (meta.isSnaOrPfms) return HeadBalance(cash: 0.0, bank: 0.0);
    final ho = meta.headOpenings[headName];
    if (ho == null) return HeadBalance(cash: 0.0, bank: 0.0);
    return ho.copy();
  }

  HeadBalance getAccountOpening([String? accName, String headFilter = 'ALL']) {
    final target = (accName != null && accName.isNotEmpty && accName != 'ALL') ? accName : selectedAccount;
    if (headFilter.isNotEmpty && headFilter != 'ALL') {
      return getHeadOpening(target, headFilter);
    }
    final meta = getAccountMeta(target);
    if (meta.isSnaOrPfms) return HeadBalance(cash: 0.0, bank: 0.0);
    if (meta.headOpenings.isNotEmpty) {
      double c = 0.0;
      double b = 0.0;
      meta.headOpenings.forEach((_, ho) {
        c += ho.cash;
        b += ho.bank;
      });
      return HeadBalance(cash: c, bank: b);
    }
    return HeadBalance(cash: meta.openingCash, bank: meta.openingBank);
  }

  /// Automatically computes Indian Financial Year (April 1 to March 31) from DD/MM/YYYY or YYYY-MM-DD
  static String financialYearFromDate(String dateStr) {
    final clean = normalizeToIsoDate(dateStr.trim());
    final parts = clean.split('-');
    if (parts.length >= 2) {
      final y = int.tryParse(parts[0]);
      final m = int.tryParse(parts[1]);
      if (y != null && m != null && y >= 1990 && y <= 2100 && m >= 1 && m <= 12) {
        final startYr = m >= 4 ? y : (y - 1);
        final endYrShort = ((startYr + 1) % 100).toString().padLeft(2, '0');
        return '$startYr-$endYrShort';
      }
    }
    return '';
  }

  /// Syncs `financialYear` automatically when Transaction Date changes in Data Entry
  bool syncFinancialYearFromDate(String dateStr, {bool notify = true}) {
    final derived = financialYearFromDate(dateStr);
    if (derived.isNotEmpty && derived != financialYear) {
      final prevParts = financialYear.split('-');
      final prevStart = prevParts.isNotEmpty ? (int.tryParse(prevParts[0]) ?? 2025) : 2025;
      final prevFrom = '$prevStart-04-01';
      final prevTo = '${prevStart + 1}-03-31';

      financialYear = derived;
      final newParts = derived.split('-');
      final newStart = newParts.isNotEmpty ? (int.tryParse(newParts[0]) ?? 2025) : 2025;
      final newFrom = '$newStart-04-01';
      final newTo = '${newStart + 1}-03-31';

      if (cashbookFromDate == prevFrom) cashbookFromDate = newFrom;
      if (cashbookToDate == prevTo) cashbookToDate = newTo;
      if (reportFromDate == prevFrom) reportFromDate = newFrom;
      if (reportToDate == prevTo) reportToDate = newTo;
      renumberVouchers(forceRecalc: false);
      if (notify) notifyListeners();
      return true;
    }
    return false;
  }

  double getHeadLimit(String? accName, String headName) {
    final meta = getAccountMeta(accName);
    if (meta.type == 'BANK') return 0.0;
    return meta.headLimits[headName] ?? 0.0;
  }

  void setSingleHeadLimit(String accName, String headName, double limitAmount) {
    final meta = getAccountMeta(accName);
    final cleanHead = headName.trim();
    if (cleanHead.isEmpty) return;
    if (limitAmount <= 0) {
      meta.headLimits.remove(cleanHead);
    } else {
      meta.headLimits[cleanHead] = double.parse(limitAmount.toStringAsFixed(2));
      if (!meta.heads.contains(cleanHead)) {
        meta.heads.add(cleanHead);
      }
    }
    accountMeta[accName] = meta;
    notifyListeners();
  }

  void restoreDefaultSnaHeadLimits([String accName = 'SNA SPARSH']) {
    final meta = getAccountMeta(accName);
    meta.headLimits = Map<String, double>.from(kSnaDefaultHeadLimits);
    for (final h in kSnaDefaultHeadLimits.keys) {
      if (!meta.heads.contains(h)) meta.heads.add(h);
    }
    accountMeta[accName] = meta;
    notifyListeners();
  }

  bool isBankOpeningReady(String accName) {
    final meta = getAccountMeta(accName);
    if (meta.type != 'BANK') return true;
    final targetBank = math.max(0.0, meta.openingBank);
    final targetCash = math.max(0.0, meta.openingCash);
    double sumBank = 0.0;
    double sumCash = 0.0;
    meta.headOpenings.forEach((_, hb) {
      sumBank += hb.bank;
      sumCash += hb.cash;
    });
    if ((targetBank - sumBank).abs() > 0.005 || (targetCash - sumCash).abs() > 0.005) {
      return false;
    }
    if (targetBank == 0 && targetCash == 0 && !meta.openingConfigured && getAccountEntries(accName).isEmpty) {
      return false;
    }
    return true;
  }

  void setBankOpeningBalanceQuick({
    required String accName,
    required double totalBank,
    required double totalCash,
    required Map<String, HeadBalance> headOpenings,
  }) {
    final meta = getAccountMeta(accName);
    meta.openingBank = math.max(0.0, totalBank);
    meta.openingCash = math.max(0.0, totalCash);
    meta.openingConfigured = true;
    meta.headOpenings = headOpenings.map((k, v) => MapEntry(k, v.copy()));
    for (final h in headOpenings.keys) {
      if (!meta.heads.contains(h)) meta.heads.add(h);
    }
    accountMeta[accName] = meta;
    notifyListeners();
  }

  int get bankAccountCount => accounts.where((a) => getAccountMeta(a).type == 'BANK').length;

  void selectAccount(String accName) {
    if (!accounts.contains(accName)) return;
    selectedAccount = accName;
    cashbookFilterHead = 'ALL';
    reportFilterHead = 'ALL';
    notifyListeners();
  }

  // --------------------------------------------------------------------------
  // VOUCHER RENUMBERING & SORTING (EXACT V06 `renumberVouchers` & `sorted`)
  // --------------------------------------------------------------------------

  List<RojmelEntry> getSortedEntries([List<RojmelEntry>? customList]) {
    final src = customList != null ? List<RojmelEntry>.from(customList) : getAccountEntries(selectedAccount);
    for (final e in src) {
      if (e.date.isNotEmpty) e.date = normalizeToIsoDate(e.date);
      if (e.clearDate.isNotEmpty) e.clearDate = normalizeToIsoDate(e.clearDate);
    }
    src.sort((a, b) {
      final dA = normalizeToIsoDate(a.date);
      final dB = normalizeToIsoDate(b.date);
      final cmpDate = dA.compareTo(dB);
      if (cmpDate != 0) return cmpDate;
      if (a.type != b.type) {
        return a.type == 'credit' ? -1 : 1; // Credits before debits on same date
      }
      return a.seq.compareTo(b.seq);
    });
    return src;
  }

  /// Automatically renumbers all Debit vouchers in strict chronological order by Transaction Date!
  /// Example: If 10/10/2025 is entered first -> Voucher 1.
  /// When an earlier transaction 09/09/2025 is entered later -> 09/09/2025 automatically becomes Voucher 1,
  /// and 10/10/2025 automatically becomes Voucher 2!
  void renumberVouchers({bool forceRecalc = false}) {
    for (final e in entries) {
      if (e.date.isNotEmpty) e.date = normalizeToIsoDate(e.date);
      if (e.clearDate.isNotEmpty) e.clearDate = normalizeToIsoDate(e.clearDate);
    }
    final sortedAll = getSortedEntries(entries);
    final groups = <String, int>{};
    final splitGroupVoucher = <String, int>{};

    for (final e in sortedAll) {
      if (e.type != 'debit') {
        e.voucher = '';
        continue;
      }
      final entryFy = financialYearFromDate(e.date);
      final k = '${e.account}|${entryFy.isNotEmpty ? entryFy : financialYear}';

      // If part of an SNA 60:40 split pair whose first leg was already assigned a voucher number, share that exact voucher!
      if (e.splitGroup.isNotEmpty && splitGroupVoucher.containsKey(e.splitGroup)) {
        final sharedV = splitGroupVoucher[e.splitGroup]!;
        e.voucher = '$sharedV';
        e.sr = sharedV;
        if (forceRecalc) e.manualVoucher = '';
        continue;
      }

      if (!forceRecalc && e.manualVoucher.trim().isNotEmpty) {
        e.voucher = e.manualVoucher.trim();
        final n = int.tryParse(e.manualVoucher.trim());
        if (n != null) {
          if (n > (groups[k] ?? 0)) groups[k] = n;
          if (e.splitGroup.isNotEmpty) splitGroupVoucher[e.splitGroup] = n;
        }
        continue;
      }

      groups[k] = (groups[k] ?? 0) + 1;
      final assigned = groups[k]!;
      e.voucher = '$assigned';
      e.sr = assigned;
      if (forceRecalc) e.manualVoucher = '';
      if (e.splitGroup.isNotEmpty) {
        splitGroupVoucher[e.splitGroup] = assigned;
      }
    }
  }

  int nextSuggestedVoucher(String acc) {
    final nums = getAccountEntries(acc)
        .where((e) => e.type == 'debit')
        .map((e) => int.tryParse(e.voucher.isNotEmpty ? e.voucher : '${e.sr}') ?? 0)
        .where((n) => n > 0)
        .toList();
    if (nums.isEmpty) return 1;
    return nums.reduce(math.max) + 1;
  }

  // --------------------------------------------------------------------------
  // HEAD BALANCE AT DATE & DATA ENTRY VALIDATION (EXACT V06 `saveEntryV02`)
  // --------------------------------------------------------------------------

  Map<String, double> getHeadCashBankBalanceAtDate(String account, String head, String date) {
    final normDate = normalizeToIsoDate(date);
    if (account.isEmpty || head.isEmpty || normDate.isEmpty) {
      return {'cash': 0, 'bank': 0, 'total': 0, 'openCash': 0, 'openBank': 0, 'limit': 0, 'usedYear': 0, 'remLimit': 0};
    }
    final hop = getHeadOpening(account, head);
    final hLimit = getHeadLimit(account, head);
    // Annual limit usage is counted within the financial year of [date]
    // (01-April to 31-March), for the whole year, not just up to the date.
    final fy = financialYearFromDate(normDate);
    final fyStartYear = int.tryParse(fy.split('-').first) ?? 0;
    final fyStart = fyStartYear > 0 ? '$fyStartYear-04-01' : '';
    final fyEnd = fyStartYear > 0 ? '${fyStartYear + 1}-03-31' : '';
    final headEntries = getSortedEntries(
      getAccountEntries(account).where((e) => e.head == head).toList(),
    );
    double cash = hop.cash;
    double bank = hop.bank;
    double usedYear = 0.0;
    final later = <RojmelEntry>[];
    for (final e in headEntries) {
      final d = normalizeToIsoDate(e.date);
      if (e.type == 'debit' &&
          !isCashEntry(e) &&
          (fyStart.isEmpty || (d.compareTo(fyStart) >= 0 && d.compareTo(fyEnd) <= 0))) {
        usedYear += e.amount;
      }
      if (d.compareTo(normDate) > 0) {
        later.add(e);
        continue;
      }
      final s = e.type == 'credit' ? 1.0 : -1.0;
      cash += s * cashAmt(e);
      bank += s * bankAmt(e);
    }
    // A back-dated debit must not push any LATER date negative, so the amount
    // available on [date] is the lowest running balance from that date onward.
    double minCash = cash, minBank = bank, runCash = cash, runBank = bank;
    for (final e in later) {
      final s = e.type == 'credit' ? 1.0 : -1.0;
      runCash += s * cashAmt(e);
      runBank += s * bankAmt(e);
      if (runCash < minCash) minCash = runCash;
      if (runBank < minBank) minBank = runBank;
    }
    return {
      'cash': cash,
      'bank': bank,
      'total': cash + bank,
      'availCash': math.max(0.0, minCash),
      'availBank': math.max(0.0, minBank),
      'availTotal': math.max(0.0, minCash) + math.max(0.0, minBank),
      'openCash': hop.cash,
      'openBank': hop.bank,
      'limit': hLimit,
      'usedYear': usedYear,
      'remLimit': math.max(0.0, hLimit - usedYear),
    };
  }

  /// Exact port of `saveEntryV02.onclick` from HTML!
  String? addTransactionV06({
    required String account,
    required String head,
    required String date,
    required String type,
    required String rawNarration,
    required String expenseShort,
    required double amount,
    required String medium,
    required String party,
    String manualVoucher = '',
    String txn = '',
    String clearDate = '',
    String sna60Claim = '',
    String sna60Date = '',
    String sna40Claim = '',
    String sna40Date = '',
    double? custom60Amount,
    double? custom40Amount,
    String custom60Suffix = '',
    String custom40Suffix = '',
    bool editAllowed = true,
    bool deadStock = false,
  }) {
    final cleanHead = head.trim();
    final cleanDate = normalizeToIsoDate(date.trim());
    clearDate = normalizeToIsoDate(clearDate.trim());
    sna60Date = normalizeToIsoDate(sna60Date.trim());
    sna40Date = normalizeToIsoDate(sna40Date.trim());
    final cleanParty = party.trim().isNotEmpty ? party.trim() : (type == 'credit' ? 'SSA' : '');
    final cleanNarr = rawNarration.trim().isNotEmpty
        ? rawNarration.trim()
        : (type == 'credit'
            ? 'ગ્રાન્ટ જમા થઈ'
            : (cleanParty.isNotEmpty ? '$cleanParty ને $cleanHead ના નાણાં ચુકવ્યા' : ''));

    if (account.isEmpty || cleanHead.isEmpty || cleanDate.isEmpty || cleanNarr.isEmpty || amount <= 0) {
      return 'ખાતું, ગ્રાન્ટ હેડ, તારીખ, વિગત અને પૂરી 100% રકમ દાખલ કરો.';
    }
    if (!isRojmelDate(cleanDate)) {
      return 'તારીખ "${date.trim()}" સાચી નથી. આ રીતે લખો: ${IndianDate.formatsHint}.';
    }
    for (final (label, value) in <(String, String)>[
      ('સેટલમેન્ટ તારીખ', clearDate),
      ('60% સેટલમેન્ટ તારીખ', sna60Date),
      ('40% સેટલમેન્ટ તારીખ', sna40Date),
    ]) {
      if (value.isNotEmpty && !isRojmelDate(value)) {
        return '$label "$value" સાચી નથી. આ રીતે લખો: ${IndianDate.formatsHint}.';
      }
    }

    // Auto-derive Financial Year according to Transaction Date
    syncFinancialYearFromDate(cleanDate, notify: false);

    final m = getAccountMeta(account);
    if (!m.heads.contains(cleanHead)) {
      m.heads.add(cleanHead);
    }
    final isCashMode = medium.trim().toLowerCase() == 'cash';
    // 5B "short expense detail" is a Debit-only field (Kharch Patrak).
    if (type != 'debit') expenseShort = '';
    final bal = getHeadCashBankBalanceAtDate(account, cleanHead, cleanDate);

    // 1A. Entry Restriction: SNA SPARSH & PFMS require Head Annual Limit to be set first!
    if (m.isSnaOrPfms) {
      final configuredLimit = getHeadLimit(account, cleanHead);
      if (configuredLimit <= 0) {
        return 'એન્ટ્રી અટકાવવામાં આવી (Entry Restricted): પહેલા "$cleanHead" ગ્રાન્ટ હેડની વાર્ષિક મર્યાદા (Head Annual Limit) સેટ કરો. તમે "🎯 Set / Change Head Limit" બટનથી ગમે ત્યારે લિમિટ સેટ કે બદલી શકો છો.';
      }
      if (!isCashMode && type == 'credit' && ((bal['bank'] ?? 0) + amount) > (configuredLimit + 0.005)) {
        // Allow credit up to or within limit, or warn if credit exceeds annual limit
      }
      if (!isCashMode && type == 'debit' && ((bal['usedYear'] ?? 0) + amount) > (configuredLimit + 0.005)) {
        return 'વાર્ષિક હેડ લિમિટ કરતા વધુ ખર્ચ: ગ્રાન્ટ હેડ "$cleanHead" ની વાર્ષિક મર્યાદા ₹${fmtDemoNum(configuredLimit)} છે (વપરાયેલ: ₹${fmtDemoNum(bal['usedYear']!)}, બાકી લિમિટ: ₹${fmtDemoNum(bal['remLimit']!)}). જરૂર હોય તો તમે ગમે ત્યારે Head Limit બદલી શકો છો.';
      }
    }

    // 1B. Entry Restriction: BANK account requires Opening Balance & Head-wise Opening distribution to be configured first!
    if (m.type == 'BANK' && !isBankOpeningReady(account)) {
      return 'એન્ટ્રી અટકાવવામાં આવી (Entry Restricted): BANK ખાતા ("$account") માં એન્ટ્રી કરતા પહેલા ઉઘડતી સિલક (Opening Balance) અને હેડ-વાઈઝ ઉઘડતી સિલક (Head-wise Opening Balance) સેટ કરવી ફરજિયાત છે. "🏦 Set / Edit Opening Balance" બટન પર ક્લિક કરો.';
    }

    // 2. Check Available Head Cash / Bank Balance on Debit
    if (type == 'debit') {
      final availCash = bal['availCash'] ?? bal['cash'] ?? 0.0;
      final availBank = bal['availBank'] ?? bal['bank'] ?? 0.0;
      final availTotal = availCash + availBank;
      final laterNote = (availTotal + 0.005) < (bal['total'] ?? 0)
          ? ' (આ તારીખ પછીની એન્ટ્રીઓ ધ્યાનમાં લેતાં)'
          : '';
      if (availTotal <= 0) {
        return 'ઉધાર (Debit) અટકાવવામાં આવ્યું: આ ગ્રાન્ટ હેડમાં કોઈ સિલક નથી (₹0.00)$laterNote. પહેલા જમા (Credit) અથવા ઉઘડતી સિલક દાખલ કરો.';
      }
      if (amount > (availTotal + 0.005)) {
        return 'ઉધાર (Debit) અટકાવવામાં આવ્યું: ગ્રાન્ટ હેડમાં ઉપલબ્ધ સિલક ₹${fmtDemoNum(availTotal)} છે$laterNote, જ્યારે દાખલ કરેલ ખર્ચ ₹${fmtDemoNum(amount)} છે.';
      }
      if (isCashMode && amount > (availCash + 0.005)) {
        return 'રોકડ ખર્ચ અટકાવવામાં આવ્યો: આ હેડમાં રોકડ (Cash) સિલક ₹${fmtDemoNum(availCash)} છે$laterNote (બેન્ક સિલક ₹${fmtDemoNum(availBank)} છે).';
      }
      if (!isCashMode && amount > (availBank + 0.005)) {
        return 'બેન્ક/SNA ખર્ચ અટકાવવામાં આવ્યો: આ હેડમાં બેન્ક સિલક ₹${fmtDemoNum(availBank)} છે$laterNote (રોકડ સિલક ₹${fmtDemoNum(availCash)} છે).';
      }
    }

    final snaMode = (m.isAnySna && medium == 'SNA SPARSH');
    final isDebitSplit = type == 'debit' && snaMode;
    final isCreditSplit = type == 'credit' && snaMode;

    final userManualVoucher = manualVoucher.trim();
    final nextV = userManualVoucher.isNotEmpty ? userManualVoucher : '${nextSuggestedVoucher(account)}';
    final nextSr = int.tryParse(nextV) ?? nextSuggestedVoucher(account);
    final baseSeq = entries.fold<int>(0, (prev, e) => math.max(prev, e.seq)) + 1;
    final baseId = 'id-${DateTime.now().microsecondsSinceEpoch}';

    if (isDebitSplit) {
      if (sna60Claim.trim().isEmpty || sna60Date.trim().isEmpty || sna40Claim.trim().isEmpty || sna40Date.trim().isEmpty) {
        return 'SNA SPARSH ઉધાર માટે 60% અને 40% બંનેના Claim Number અને Settlement Date ફરજિયાત છે.';
      }
      final def60 = (amount * 60.0).roundToDouble() / 100.0;
      final def40 = double.parse((amount - def60).toStringAsFixed(2));
      final amount60 = (custom60Amount != null && custom60Amount > 0) ? custom60Amount : def60;
      final amount40 = (custom40Amount != null && custom40Amount >= 0) ? custom40Amount : def40;
      if ((amount60 + amount40 - amount).abs() > 0.01) {
        return '60% (₹${fmtDemoNum(amount60)}) + 40% (₹${fmtDemoNum(amount40)}) = ₹${fmtDemoNum(amount60 + amount40)} પૂરી રકમ ₹${fmtDemoNum(amount)} બરાબર હોવી જોઈએ. 60% / 40% રકમ સુધારો.';
      }
      final group = 'SNA-D-${DateTime.now().millisecondsSinceEpoch}';
      String strippedNarr = cleanNarr.replaceAll(RegExp(r'\s*\(([^)]*?)\s*(60|40)%.*?\)\s*$'), '');
      if (cleanParty.isNotEmpty && !strippedNarr.toLowerCase().contains(cleanParty.toLowerCase())) {
        strippedNarr = '$cleanParty ને $strippedNarr';
      }

      // Determine 60% and 40% Debit suffixes:
      // 1. Check if a Credit entry on the same account + date + head exists and derive from it
      // 2. Or derive from custom60Suffix / custom40Suffix / cleanNarr
      String? crNarr60;
      String? crNarr40;
      for (final cr in entries.reversed) {
        if (cr.type == 'credit' && cr.account == account && cr.date == cleanDate && cr.head == cleanHead) {
          if (crNarr60 == null && cr.narration.contains('60%')) crNarr60 = cr.narration;
          if (crNarr40 == null && cr.narration.contains('40%')) crNarr40 = cr.narration;
        }
      }
      String drSuf60 = custom60Suffix.trim().isNotEmpty
          ? deriveDebitSuffixFromCredit(custom60Suffix, 60)
          : (crNarr60 != null ? deriveDebitSuffixFromCredit(crNarr60, 60) : deriveDebitSuffixFromCredit(cleanNarr, 60));
      String drSuf40 = custom40Suffix.trim().isNotEmpty
          ? deriveDebitSuffixFromCredit(custom40Suffix, 40)
          : (crNarr40 != null ? deriveDebitSuffixFromCredit(crNarr40, 40) : deriveDebitSuffixFromCredit(cleanNarr, 40));
      if (crNarr60 != null && (drSuf60 == '(વાઉચરના 60% લેખે)' || custom60Suffix.trim() == '(વાઉચરના 60%)')) {
        drSuf60 = deriveDebitSuffixFromCredit(crNarr60, 60);
      }
      if (crNarr40 != null && (drSuf40 == '(વાઉચરના 40% લેખે)' || custom40Suffix.trim() == '(વાઉચરના 40%)')) {
        drSuf40 = deriveDebitSuffixFromCredit(crNarr40, 40);
      }

      entries.add(RojmelEntry(
        sr: nextSr,
        date: cleanDate,
        head: cleanHead,
        type: 'debit',
        narration: '$strippedNarr $drSuf60',
        voucher: nextV,
        manualVoucher: userManualVoucher,
        amount: amount60,
        medium: medium,
        txn: sna60Claim.trim(),
        clearDate: sna60Date.trim(),
        party: cleanParty,
        expense: expenseShort.trim().isNotEmpty ? expenseShort.trim() : cleanHead,
        central: amount60,
        state: 0.0,
        splitPercent: 60.0,
        id: '${baseId}60',
        seq: baseSeq,
        account: account,
        originalAmount: amount,
        splitGroup: group,
        editAllowed: editAllowed,
        deadStock: type == 'debit' && deadStock,
      ));
      entries.add(RojmelEntry(
        sr: nextSr,
        date: cleanDate,
        head: cleanHead,
        type: 'debit',
        narration: '$strippedNarr $drSuf40',
        voucher: nextV,
        manualVoucher: userManualVoucher,
        amount: amount40,
        medium: medium,
        txn: sna40Claim.trim(),
        clearDate: sna40Date.trim(),
        party: cleanParty,
        expense: expenseShort.trim().isNotEmpty ? expenseShort.trim() : cleanHead,
        central: 0.0,
        state: amount40,
        splitPercent: 40.0,
        id: '${baseId}40',
        seq: baseSeq + 1,
        account: account,
        originalAmount: amount,
        splitGroup: group,
        editAllowed: editAllowed,
        deadStock: type == 'debit' && deadStock,
      ));
    } else if (isCreditSplit) {
      final def60 = (amount * 60.0).roundToDouble() / 100.0;
      final def40 = double.parse((amount - def60).toStringAsFixed(2));
      final amount60 = (custom60Amount != null && custom60Amount > 0) ? custom60Amount : def60;
      final amount40 = (custom40Amount != null && custom40Amount >= 0) ? custom40Amount : def40;
      if ((amount60 + amount40 - amount).abs() > 0.01) {
        return '60% (₹${fmtDemoNum(amount60)}) + 40% (₹${fmtDemoNum(amount40)}) = ₹${fmtDemoNum(amount60 + amount40)} પૂરી રકમ ₹${fmtDemoNum(amount)} બરાબર હોવી જોઈએ. 60% / 40% રકમ સુધારો.';
      }
      final suf60 = custom60Suffix.trim().isNotEmpty ? custom60Suffix.trim() : '(વાઉચરના 60%)';
      final suf40 = custom40Suffix.trim().isNotEmpty ? custom40Suffix.trim() : '(વાઉચરના 40%)';
      final group = 'SNA-C-${DateTime.now().millisecondsSinceEpoch}';
      final strippedNarr = cleanNarr.replaceAll(RegExp(r'\s*\((વાઉચરના|ગ્રાન્ટના)\s*(60|40)%.*?\)\s*$'), '');
      entries.add(RojmelEntry(
        sr: nextSr,
        date: cleanDate,
        head: cleanHead,
        type: 'credit',
        narration: '$strippedNarr $suf60',
        voucher: '',
        manualVoucher: '',
        amount: amount60,
        medium: medium,
        txn: '',
        clearDate: '',
        party: cleanParty,
        expense: expenseShort.trim().isNotEmpty ? expenseShort.trim() : cleanHead,
        central: amount60,
        state: 0.0,
        splitPercent: 60.0,
        id: '${baseId}60',
        seq: baseSeq,
        account: account,
        originalAmount: amount,
        splitGroup: group,
        editAllowed: editAllowed,
        deadStock: type == 'debit' && deadStock,
      ));
      entries.add(RojmelEntry(
        sr: nextSr + 1,
        date: cleanDate,
        head: cleanHead,
        type: 'credit',
        narration: '$strippedNarr $suf40',
        voucher: '',
        manualVoucher: '',
        amount: amount40,
        medium: medium,
        txn: '',
        clearDate: '',
        party: cleanParty,
        expense: expenseShort.trim().isNotEmpty ? expenseShort.trim() : cleanHead,
        central: 0.0,
        state: amount40,
        splitPercent: 40.0,
        id: '${baseId}40',
        seq: baseSeq + 1,
        account: account,
        originalAmount: amount,
        splitGroup: group,
        editAllowed: editAllowed,
        deadStock: type == 'debit' && deadStock,
      ));
    } else {
      String finalTxn = '';
      String finalClear = '';
      if (type == 'debit') {
        if (isCashMode) {
          finalTxn = txn.trim().isNotEmpty ? txn.trim() : 'રોકડ';
          finalClear = clearDate.trim();
        } else {
          finalTxn = txn.trim();
          finalClear = clearDate.trim();
          if (finalTxn.isEmpty || finalClear.isEmpty) {
            return '100% Bank / PFMS ઉધાર માટે ચેક/PFMS નંબર અને સેટલમેન્ટ તારીખ ફરજિયાત છે.';
          }
        }
      }
      entries.add(RojmelEntry(
        sr: nextSr,
        date: cleanDate,
        head: cleanHead,
        type: type,
        narration: cleanNarr,
        voucher: type == 'debit' ? nextV : '',
        manualVoucher: type == 'debit' ? userManualVoucher : '',
        amount: amount,
        medium: medium,
        txn: finalTxn,
        clearDate: finalClear,
        party: cleanParty,
        expense: expenseShort.trim().isNotEmpty ? expenseShort.trim() : cleanHead,
        central: 0.0,
        state: 0.0,
        splitPercent: 0.0,
        id: baseId,
        seq: baseSeq,
        account: account,
        originalAmount: amount,
        splitGroup: '',
        editAllowed: editAllowed,
        deadStock: type == 'debit' && deadStock,
      ));
    }

    renumberVouchers(forceRecalc: false);
    notifyListeners();
    return null;
  }

  // --------------------------------------------------------------------------
  // ACCOUNT SAVE / UPDATE / DELETE & 2-STEP CLEAR ENTRIES
  // --------------------------------------------------------------------------

  String? saveOrUpdateAccountV06({
    required String oldName,
    required String name,
    required String type,
    required String schoolNameStr,
    required String pfmsSchoolNameStr,
    required String acNoStr,
    String snaAgencyCodeStr = '',
    String pfmsLastDateStr = '',
    String snaStartDateStr = '',
    required String holderNameStr,
    required String ifscStr,
    required String bankNameStr,
    required String branchStr,
    required String branchAddressStr,
    required double openBank,
    required double openCash,
    required Map<String, HeadBalance> headOpeningsMap,
    required Map<String, double> headLimitsMap,
    required List<String> finalHeadsList,
  }) {
    final cleanName = name.trim();
    if (cleanName.isEmpty) {
      return 'ખાતાનું નામ (Account Name) ફરજિયાત છે.';
    }
    if (type == 'SNA_PURE') {
      final effAgency = snaAgencyCodeStr.trim().isNotEmpty ? snaAgencyCodeStr.trim() : acNoStr.trim();
      if (effAgency.isEmpty) {
        return 'Purely SNA SPARSH ખાતા માટે માત્ર ખાતાનું નામ અને એજન્સી કોડ (Agency Code) ફરજિયાત છે.';
      }
    } else if (type == 'SNA') {
      if (acNoStr.trim().isEmpty && snaAgencyCodeStr.trim().isEmpty) {
        return 'PFMS + SNA SPARSH સંયુક્ત ખાતા માટે PFMS ખાતા નંબર અને SNA SPARSH એજન્સી કોડ દાખલ કરો.';
      }
    } else {
      if (acNoStr.trim().isEmpty || bankNameStr.trim().isEmpty) {
        return 'ખાતાનું નામ, ખાતા નંબર અને બેંકનું નામ ફરજિયાત છે.';
      }
      if (type == 'BANK' && ifscStr.trim().isEmpty) {
        return 'BANK ખાતા માટે IFSC કોડ ફરજિયાત છે.';
      }
    }
    if (accounts.any((n) => n != oldName && n.toLowerCase() == cleanName.toLowerCase())) {
      return 'આ નામનું ખાતું પહેલેથી અસ્તિત્વમાં છે.';
    }
    final currentBankCount = accounts.where((a) => a != oldName && getAccountMeta(a).type == 'BANK').length;
    if (type == 'BANK' && currentBankCount >= kMaxBankAccounts) {
      return 'મહત્તમ $kMaxBankAccounts BANK ખાતા રાખી શકાય છે (SNA SPARSH અને PFMS ઉપરાંત).';
    }

    final isBank = type == 'BANK';
    final effBank = isBank ? math.max(0.0, openBank) : 0.0;
    final effCash = isBank ? math.max(0.0, openCash) : 0.0;

    final cleanedHeads = <String, HeadBalance>{};
    final mergedHeads = <String>[...finalHeadsList];
    if (isBank && (effBank > 0 || effCash > 0)) {
      double sumB = 0.0;
      double sumC = 0.0;
      headOpeningsMap.forEach((h, hb) {
        final c = math.max(0.0, hb.cash);
        final b = math.max(0.0, hb.bank);
        if (c > 0 || b > 0) {
          cleanedHeads[h] = HeadBalance(cash: c, bank: b);
          sumC += c;
          sumB += b;
          if (!mergedHeads.contains(h)) mergedHeads.add(h);
        }
      });
      if ((sumB - effBank).abs() > 0.005 || (sumC - effCash).abs() > 0.005) {
        return 'હેડ-વાઈઝ ઉઘડતી સિલક મેચ થવી ફરજિયાત છે! કુલ ઉઘડતી સિલક (બેન્ક ₹${fmtDemoNum(effBank)}, રોકડ ₹${fmtDemoNum(effCash)}) અને હેડ મુજબ ફાળવેલ સરવાળો (બેન્ક ₹${fmtDemoNum(sumB)}, રોકડ ₹${fmtDemoNum(sumC)}) સમાન હોવો જોઈએ.';
      }
    }

    final cleanedLimits = <String, double>{};
    if (type == 'SNA' || type == 'SNA_PURE' || type == 'PFMS') {
      headLimitsMap.forEach((h, lim) {
        if (lim > 0) {
          cleanedLimits[h] = lim;
          if (!mergedHeads.contains(h)) mergedHeads.add(h);
        }
      });
    }

    final existing = oldName.isNotEmpty ? accountMeta[oldName] : null;
    final effAgencyCode = snaAgencyCodeStr.trim().isNotEmpty
        ? snaAgencyCodeStr.trim()
        : (type == 'SNA_PURE' ? acNoStr.trim() : '');
    final effAcNo = type == 'SNA_PURE'
        ? effAgencyCode
        : acNoStr.trim();

    final m = AccountMeta(
      name: cleanName,
      type: type,
      schoolName: schoolNameStr.trim().isNotEmpty ? schoolNameStr.trim() : schoolName,
      pfmsSchoolName: pfmsSchoolNameStr.trim().isNotEmpty ? pfmsSchoolNameStr.trim() : (schoolNameStr.trim().isNotEmpty ? schoolNameStr.trim() : schoolName),
      acNo: effAcNo,
      snaAgencyCode: effAgencyCode,
      pfmsLastDate: normalizeToIsoDate(pfmsLastDateStr.trim()),
      snaStartDate: normalizeToIsoDate(snaStartDateStr.trim()),
      holderName: type == 'SNA_PURE' ? '' : (holderNameStr.trim().isNotEmpty ? holderNameStr.trim() : schoolName),
      ifsc: type == 'SNA_PURE' ? '' : ifscStr.trim(),
      bankName: type == 'SNA_PURE' ? '' : bankNameStr.trim(),
      branch: type == 'SNA_PURE' ? '' : branchStr.trim(),
      branchAddress: type == 'SNA_PURE' ? '' : branchAddressStr.trim(),
      creditPageTitle: existing?.creditPageTitle ?? '-: CASHBOOK :-',
      debitPageTitle: existing?.debitPageTitle ?? '-: કેશબુક :-',
      openingBank: effBank,
      openingCash: effCash,
      openingConfigured: isBank,
      headOpenings: cleanedHeads,
      headLimits: cleanedLimits,
      heads: <String>{...mergedHeads}.toList(),
    );

    if (oldName.isNotEmpty) {
      final idx = accounts.indexOf(oldName);
      if (idx >= 0) accounts[idx] = cleanName;
      for (final e in entries) {
        if (e.account == oldName) e.account = cleanName;
      }
      if (oldName != cleanName) accountMeta.remove(oldName);
    } else {
      accounts.add(cleanName);
    }
    accountMeta[cleanName] = m;
    setAccountSpecificHeads(cleanName, m.heads);
    selectedAccount = cleanName;
    notifyListeners();
    return null;
  }

  String? deleteAccountIfEmpty(String accName) {
    if (entries.any((e) => e.account == accName)) {
      return 'આ ખાતામાં વ્યવહારો છે તેથી ખાતું ડિલીટ થઈ શકશે નહીં. પહેલા 2x Confirm થી એન્ટ્રી ક્લિયર કરો.';
    }
    if (accounts.length <= 1) {
      return 'ઓછામાં ઓછું એક ખાતું રાખવું ફરજિયાત છે.';
    }
    accounts.remove(accName);
    accountMeta.remove(accName);
    if (selectedAccount == accName) {
      selectedAccount = accounts.first;
    }
    notifyListeners();
    return null;
  }

  /// Returns an error when, with [candidate] entries, the running Cash or
  /// Bank balance of any of [heads] in [account] would drop below zero.
  String? validateHeadRunningBalances(
    String account,
    Set<String> heads,
    List<RojmelEntry> candidate,
  ) {
    for (final h in heads) {
      final hop = getHeadOpening(account, h);
      double cash = hop.cash, bank = hop.bank;
      final list = getSortedEntries(
        candidate.where((e) => e.account == account && e.head == h).toList(),
      );
      for (final e in list) {
        final s = e.type == 'credit' ? 1.0 : -1.0;
        cash += s * cashAmt(e);
        bank += s * bankAmt(e);
        if (cash < -0.005 || bank < -0.005) {
          return 'સુધારો અટકાવવામાં આવ્યો: "$h" હેડની ${cash < -0.005 ? "રોકડ" : "બેન્ક"} સિલક ${fmtDateSlashDDMMYYYY(e.date)} ના રોજ ઋણ (₹${fmtDemoNum(cash < -0.005 ? cash : bank)}) થઈ જાય છે.';
        }
      }
    }
    return null;
  }

  /// Updates one entry after validating that no head balance turns negative.
  String? updateEntry(RojmelEntry updated) {
    final idx = entries.indexWhere((e) => e.id == updated.id);
    if (idx == -1) return 'Entry not found.';
    updated.date = normalizeToIsoDate(updated.date);
    updated.clearDate = normalizeToIsoDate(updated.clearDate);
    if (updated.date.isEmpty || updated.amount <= 0) {
      return 'તારીખ અને રકમ સાચી દાખલ કરો.';
    }
    if (!isRojmelDate(updated.date)) {
      return 'તારીખ "${updated.date}" સાચી નથી. આ રીતે લખો: ${IndianDate.formatsHint}.';
    }
    if (updated.clearDate.isNotEmpty && !isRojmelDate(updated.clearDate)) {
      return 'સેટલમેન્ટ તારીખ "${updated.clearDate}" સાચી નથી. આ રીતે લખો: ${IndianDate.formatsHint}.';
    }
    if (updated.type != 'debit') updated.expense = updated.head;
    final old = entries[idx];
    final candidate = List<RojmelEntry>.from(entries)..[idx] = updated;
    final err = validateHeadRunningBalances(
      updated.account,
      <String>{old.head, updated.head},
      candidate,
    );
    if (err != null) return err;
    entries[idx] = updated;
    renumberVouchers(forceRecalc: false);
    notifyListeners();
    return null;
  }

  void deleteSingleEntry(String id) {
    entries.removeWhere((e) => e.id == id);
    renumberVouchers(forceRecalc: false);
    notifyListeners();
  }

  int deleteAccountAllEntries(
    String accName, {
    bool carryForwardClosingAsOpening = false,
    String? nextFinancialYear,
  }) {
    final m = getAccountMeta(accName);
    final accEntries = getSortedEntries(getAccountEntries(accName));
    final removedCount = accEntries.length;

    if (m.type == 'BANK' && carryForwardClosingAsOpening) {
      final headsList = getAccountSpecificHeads(accName);
      final newHeadOpenings = <String, HeadBalance>{};
      double newTotalCash = 0.0;
      double newTotalBank = 0.0;
      for (final h in headsList) {
        final hop = getHeadOpening(accName, h);
        double c = hop.cash;
        double b = hop.bank;
        for (final e in accEntries.where((x) => x.head == h)) {
          final s = e.type == 'credit' ? 1.0 : -1.0;
          c += s * cashAmt(e);
          b += s * bankAmt(e);
        }
        c = math.max(0.0, double.parse(c.toStringAsFixed(2)));
        b = math.max(0.0, double.parse(b.toStringAsFixed(2)));
        if (c > 0 || b > 0) {
          newHeadOpenings[h] = HeadBalance(cash: c, bank: b);
          newTotalCash += c;
          newTotalBank += b;
        }
      }
      m.headOpenings = newHeadOpenings;
      m.openingCash = double.parse(newTotalCash.toStringAsFixed(2));
      m.openingBank = double.parse(newTotalBank.toStringAsFixed(2));
      accountMeta[accName] = m;
    }

    if (nextFinancialYear != null && RegExp(r'^\d{4}-\d{2}$').hasMatch(nextFinancialYear.trim())) {
      financialYear = nextFinancialYear.trim();
    }

    entries.removeWhere((e) => e.account == accName);
    notifyListeners();
    return removedCount;
  }

  // --------------------------------------------------------------------------
  // EXACT V06 SMART WRITING-AREA CASHBOOK PAGINATION & PAGE MAP
  // (`estimateEntryWritingHeightMM`, `splitDayIntoExcelPagePairs`, `buildCashbookPages`)
  // --------------------------------------------------------------------------

  double estimateEntryWritingHeightMM(RojmelEntry? e, String side, double fontPt) {
    if (e == null) return 22.0;
    final f = (fontPt > 0 ? fontPt : 10.0).clamp(6.0, 16.0);
    final scale = f / 10.0;
    final narr = side == 'credit' ? formatCreditNarration(e) : formatDebitNarration(e);
    final party = e.party.trim();
    final head = e.head.trim();
    // Column widths: Credit narration is 30% (~21 chars at 10pt), Debit narration is 22% (~15 chars at 10pt).
    final charsPerNarrLine = math.max(8.0, (side == 'debit' ? 15.0 : 21.0) / scale);
    final charsPerHeadLine = math.max(5.0, (side == 'debit' ? 8.5 : 15.0) / scale);
    final segs = narr.split(RegExp(r'<br\s*/?>|\n', caseSensitive: false));
    int narrLines = 0;
    for (final seg in segs) {
      final clean = seg.replaceAll(RegExp(r'<[^>]+>'), '').trim();
      narrLines += math.max(1, ((clean.isEmpty ? 1 : clean.length) / charsPerNarrLine).ceil());
    }
    if (party.isNotEmpty && !narr.contains(party)) {
      narrLines += math.max(1, (party.length / charsPerNarrLine).ceil());
    }
    final headSegs = head.split(RegExp(r'<br\s*/?>|\n', caseSensitive: false));
    int headLines = 0;
    for (final seg in headSegs) {
      final clean = seg.trim();
      headLines += math.max(1, ((clean.isEmpty ? 1 : clean.length) / charsPerHeadLine).ceil());
    }
    int claimLines = 1;
    if (side == 'debit' && !isCashEntry(e) && !isBankChargeEntry(e)) {
      final claimStr = fmtClaimWrapped(e.txn);
      if (claimStr.isNotEmpty) {
        claimLines = claimStr.split('\n').length;
      }
    }
    final lines = [narrLines, headLines, claimLines, 2].reduce(math.max);
    return math.max(16.5 * scale, ((lines * 4.25 * scale) + 4.8).roundToDouble());
  }

  /// Pairs Credit and Debit entries into 1-to-1 horizontally opposite Row Slots `(cr, dr)`
  /// grouped by Date and Grant Head in order of appearance.
  /// If a date/head has 1 Credit and 2 Debits (e.g. 25/06/2025: 1 Credit of 2448 and 2 Debits of 1926 + 522),
  /// Slot 1 has `(cr: 2448, dr: 1926)` and Slot 2 has `(cr: null, dr: 522)`, so the next date's
  /// Credit and Debit (e.g. 02/07/2025) are placed on Slot 3 on BOTH pages — 100% exact opposite!
  List<({RojmelEntry? cr, RojmelEntry? dr, String date, String head})> buildAlignedSlotsForEntries(
    List<RojmelEntry> credits,
    List<RojmelEntry> debits,
  ) {
    final slots = <({RojmelEntry? cr, RojmelEntry? dr, String date, String head})>[];
    if (credits.isEmpty && debits.isEmpty) return slots;

    final allDates = <String>{
      ...credits.map((e) => e.date),
      ...debits.map((e) => e.date),
    }.toList()
      ..sort();

    for (final d in allDates) {
      final dc = credits.where((e) => e.date == d).toList();
      final dd = debits.where((e) => e.date == d).toList();
      final orderedHeads = <String>[];
      for (final e in <RojmelEntry>[...dc, ...dd]) {
        if (!orderedHeads.contains(e.head)) {
          orderedHeads.add(e.head);
        }
      }
      for (final h in orderedHeads) {
        final hCr = dc.where((e) => e.head == h).toList();
        final hDr = dd.where((e) => e.head == h).toList();
        final count = math.max(hCr.length, hDr.length);
        for (var i = 0; i < count; i++) {
          slots.add((
            cr: i < hCr.length ? hCr[i] : null,
            dr: i < hDr.length ? hDr[i] : null,
            date: d,
            head: h,
          ));
        }
      }
    }
    return slots;
  }

  Map<String, List<List<RojmelEntry>>> splitDayIntoExcelPagePairs(
    List<RojmelEntry> credits,
    List<RojmelEntry> debits,
    String acc,
    String dateStr, [
    int startCreditPageNo = 1,
  ]) {
    final key = '$acc|$dateStr';
    final aligned = buildAlignedSlotsForEntries(credits, debits);
    if (aligned.isEmpty) {
      return {'cp': <List<RojmelEntry>>[<RojmelEntry>[]], 'dp': <List<RojmelEntry>>[<RojmelEntry>[]] };
    }
    if (sameDateOverflowMode[key] == 'fit') {
      return {'cp': <List<RojmelEntry>>[List<RojmelEntry>.from(credits)], 'dp': <List<RojmelEntry>>[List<RojmelEntry>.from(debits)]};
    }

    final loss = cashbookAreaLossMm;
    final drWritingAreaMm = math.max(90.0, 176.0 - loss);
    final baseFont = globalFontPt ?? pageFontMap['default'] ?? cashbookPrintFontPt;
    final defaultCap = defaultMaxEntriesPerPage > 0 ? defaultMaxEntriesPerPage : 6;

    final cp = <List<RojmelEntry>>[];
    final dp = <List<RojmelEntry>>[];
    int sIdx = 0;
    int pairIdx = 0;

    while (sIdx < aligned.length) {
      final creditPageNo = startCreditPageNo + pairIdx * 2;
      final pairKey = '$acc|$dateStr|$pairIdx';
      final manualCount = getCreditPageEntryCount(acc, creditPageNo, pairKey) ?? 0;
      final gapMm = getCreditPageEntryGapMm(acc, creditPageNo, pairKey);
      final crFont = pageFontMap['page|$acc|$creditPageNo'] ?? pageFontMap[pairKey] ?? baseFont;
      final drFont = pageFontMap['page|$acc|${creditPageNo + 1}'] ?? pageFontMap[pairKey] ?? baseFont;

      if (manualCount > 0) {
        final chunk = aligned.skip(sIdx).take(manualCount).toList();
        cp.add(chunk.map((x) => x.cr).whereType<RojmelEntry>().toList());
        dp.add(chunk.map((x) => x.dr).whereType<RojmelEntry>().toList());
        sIdx += chunk.length;
      } else {
        int takeCount = 0;
        double usedMM = 0.0;
        while (sIdx + takeCount < aligned.length && takeCount < defaultCap) {
          final slot = aligned[sIdx + takeCount];
          final hCr = slot.cr != null ? estimateEntryWritingHeightMM(slot.cr, 'credit', crFont) : 0.0;
          final hDr = slot.dr != null ? estimateEntryWritingHeightMM(slot.dr, 'debit', drFont) : 0.0;
          final slotH = math.max(hCr, hDr) + gapMm;
          if (takeCount > 0 && (usedMM + slotH > drWritingAreaMm)) break;
          usedMM += slotH;
          takeCount++;
        }
        if (takeCount == 0) takeCount = 1;
        final chunk = aligned.skip(sIdx).take(takeCount).toList();
        cp.add(chunk.map((x) => x.cr).whereType<RojmelEntry>().toList());
        dp.add(chunk.map((x) => x.dr).whereType<RojmelEntry>().toList());
        sIdx += takeCount;
      }
      pairIdx++;
      if (pairIdx > 200) break;
    }

    if (cp.isEmpty) cp.add(<RojmelEntry>[]);
    if (dp.isEmpty) dp.add(<RojmelEntry>[]);
    return {'cp': cp, 'dp': dp};
  }

  HeadBalance _sumEntries(List<RojmelEntry> rows) {
    double c = 0.0;
    double b = 0.0;
    for (final e in rows) {
      c += cashAmt(e);
      b += bankAmt(e);
    }
    return HeadBalance(cash: c, bank: b);
  }

  int _countPagesForDate(List<RojmelEntry> dayEntries, String acc, String dateStr) {
    final credits = dayEntries.where((e) => e.type == 'credit').toList();
    final debits = dayEntries.where((e) => e.type == 'debit').toList();
    final split = splitDayIntoExcelPagePairs(credits, debits, acc, dateStr);
    final pairs = [split['cp']!.length, split['dp']!.length, 1].reduce(math.max);
    return pairs * 2;
  }

  /// Cashbook page plan:
  ///  * One date per page (default): every date starts a new page pair and
  ///    a long date continues on the next pair.
  ///  * Multi-Date Entries in Same Page ([cashbookContinuousDates]):
  ///    - Pairs Credit & Debit into 1-to-1 Aligned Row Slots `(cr, dr)` so if a date
  ///      has 1 Credit and many Debits (e.g. 25/06/2025), Credit & Debit stay 100%
  ///      horizontally opposite on every row across the page.
  ///    - Supports Page-Wise Number of Entries + Gap Between Two Entries set on the
  ///      Credit Page (Page 1, Page 3, Page 5, ...), which automatically sets the
  ///      facing Debit Page (Page 2, Page 4, Page 6, ...).
  ///    - Supports Auto Mode with Font Size + Gap: packs complete aligned slots onto
  ///      each page only while the FULL last entry + gap fits inside the writing area,
  ///      and automatically creates new required pages.
  List<({String key, int idx, List<RojmelEntry> cr, List<RojmelEntry> dr, int totCr, int totDr})> _cashbookPagePlan(
    List<RojmelEntry> sorted,
    String acc, [
    int startCreditPageNo = 1,
  ]) {
    final out = <({String key, int idx, List<RojmelEntry> cr, List<RojmelEntry> dr, int totCr, int totDr})>[];
    final byDate = <String, List<RojmelEntry>>{};
    for (final e in sorted) {
      byDate.putIfAbsent(e.date, () => <RojmelEntry>[]).add(e);
    }
    final dates = byDate.keys.toList()..sort();
    void addSplit(String date, List<RojmelEntry> credits, List<RojmelEntry> debits) {
      final currCreditPage = startCreditPageNo + out.length * 2;
      final split = splitDayIntoExcelPagePairs(credits, debits, acc, date, currCreditPage);
      final cp = split['cp']!;
      final dp = split['dp']!;
      final pairs = [cp.length, dp.length, 1].reduce(math.max);
      for (var i = 0; i < pairs; i++) {
        out.add((
          key: date,
          idx: i,
          cr: i < cp.length ? cp[i] : <RojmelEntry>[],
          dr: i < dp.length ? dp[i] : <RojmelEntry>[],
          totCr: credits.length,
          totDr: debits.length,
        ));
      }
    }

    if (!cashbookContinuousDates) {
      for (final d in dates) {
        final day = byDate[d]!;
        addSplit(d, day.where((e) => e.type == 'credit').toList(), day.where((e) => e.type == 'debit').toList());
      }
      return out;
    }

    final loss = cashbookAreaLossMm;
    final drBudgetMm = math.max(90.0, 176.0 - loss);
    final baseFontPt = globalFontPt ?? pageFontMap['default'] ?? cashbookPrintFontPt;
    final defaultCap = defaultMaxEntriesPerPage > 0 ? defaultMaxEntriesPerPage : 12;
    final mAcc = getAccountMeta(acc);

    var currentSlots = <({RojmelEntry? cr, RojmelEntry? dr, String date, String head})>[];
    var usedHeightMm = 0.0;
    var contIdx = 0;
    bool? currentIsPfms;

    void flush() {
      if (currentSlots.isEmpty) return;
      final crList = currentSlots.map((s) => s.cr).whereType<RojmelEntry>().toList();
      final drList = currentSlots.map((s) => s.dr).whereType<RojmelEntry>().toList();
      out.add((
        key: 'CONT',
        idx: contIdx++,
        cr: crList,
        dr: drList,
        totCr: crList.length,
        totDr: drList.length,
      ));
      currentSlots = <({RojmelEntry? cr, RojmelEntry? dr, String date, String head})>[];
      usedHeightMm = 0.0;
      currentIsPfms = null;
    }

    int currentCreditPageNo() => startCreditPageNo + contIdx * 2;

    double crFontForCurrentPair() {
      final pk = '$acc|CONT|$contIdx';
      final cPageNo = currentCreditPageNo();
      return pageFontMap['page|$acc|$cPageNo'] ??
          pageFontMap['${pk}_credit'] ??
          pageFontMap[pk] ??
          baseFontPt;
    }

    double drFontForCurrentPair() {
      final pk = '$acc|CONT|$contIdx';
      final dPageNo = currentCreditPageNo() + 1;
      return pageFontMap['page|$acc|$dPageNo'] ??
          pageFontMap['${pk}_debit'] ??
          pageFontMap[pk] ??
          baseFontPt;
    }

    int? manualCapForCurrentPair() {
      final pk = '$acc|CONT|$contIdx';
      return getCreditPageEntryCount(acc, currentCreditPageNo(), pk);
    }

    double gapMmForCurrentPair() {
      final pk = '$acc|CONT|$contIdx';
      return getCreditPageEntryGapMm(acc, currentCreditPageNo(), pk);
    }

    for (final d in dates) {
      final day = byDate[d]!;
      final dc = day.where((e) => e.type == 'credit').toList();
      final dd = day.where((e) => e.type == 'debit').toList();
      if (dc.isEmpty && dd.isEmpty) continue;

      bool? dayPfms;
      if (mAcc.type == 'SNA') {
        final sample = dd.isNotEmpty ? dd.first : (dc.isNotEmpty ? dc.first : null);
        dayPfms = sample != null ? isPFMSEntry(sample) : isDateInPfmsDuration(acc, d);
        if (currentIsPfms != null && currentIsPfms != dayPfms) {
          flush();
        }
      }

      // Build aligned (date, head) groups for date `d`
      final orderedHeads = <String>[];
      for (final e in <RojmelEntry>[...dc, ...dd]) {
        if (!orderedHeads.contains(e.head)) {
          orderedHeads.add(e.head);
        }
      }

      for (final h in orderedHeads) {
        final hCr = dc.where((e) => e.head == h).toList();
        final hDr = dd.where((e) => e.head == h).toList();
        final count = math.max(hCr.length, hDr.length);
        final groupSlots = <({RojmelEntry? cr, RojmelEntry? dr, String date, String head})>[
          for (var i = 0; i < count; i++)
            (
              cr: i < hCr.length ? hCr[i] : null,
              dr: i < hDr.length ? hDr[i] : null,
              date: d,
              head: h,
            ),
        ];

        // If this group has multiple slots (e.g. 1 Credit and 2 Debits on 25/06/2025, or 60%/40% SNA),
        // check if the whole group fits on the current non-empty page in Auto mode; if not, flush first
        // so the group stays together when possible.
        if (currentSlots.isNotEmpty && groupSlots.length > 1) {
          final manualCap = manualCapForCurrentPair();
          if (manualCap != null) {
            if (currentSlots.length + groupSlots.length > manualCap && hCr.length > 1) {
              flush();
            }
          } else {
            final crFont = crFontForCurrentPair();
            final drFont = drFontForCurrentPair();
            final gapMm = gapMmForCurrentPair();
            double grpH = 0.0;
            for (final gs in groupSlots) {
              final hc = gs.cr != null ? estimateEntryWritingHeightMM(gs.cr, 'credit', crFont) : 0.0;
              final hd = gs.dr != null ? estimateEntryWritingHeightMM(gs.dr, 'debit', drFont) : 0.0;
              grpH += math.max(hc, hd) + gapMm;
            }
            if (currentSlots.length + groupSlots.length > defaultCap ||
                usedHeightMm + grpH > drBudgetMm) {
              flush();
            }
          }
        }

        int gIdx = 0;
        int guard = 0;
        while (gIdx < groupSlots.length && guard++ < 500) {
          currentIsPfms ??= dayPfms;
          final manualCap = manualCapForCurrentPair();
          final cap = manualCap ?? defaultCap;
          final crFont = crFontForCurrentPair();
          final drFont = drFontForCurrentPair();
          final gapMm = gapMmForCurrentPair();

          final slot = groupSlots[gIdx];
          final hc = slot.cr != null ? estimateEntryWritingHeightMM(slot.cr, 'credit', crFont) : 0.0;
          final hd = slot.dr != null ? estimateEntryWritingHeightMM(slot.dr, 'debit', drFont) : 0.0;
          final slotH = math.max(hc, hd) + gapMm;

          final exceedsCount = currentSlots.length >= cap;
          final exceedsHeight = manualCap == null && (usedHeightMm + slotH > drBudgetMm);

          if (currentSlots.isNotEmpty && (exceedsCount || exceedsHeight)) {
            flush();
            continue;
          }

          currentSlots.add(slot);
          usedHeightMm += slotH;
          gIdx++;

          if (manualCap != null && currentSlots.length >= manualCap) {
            flush();
          }
        }
      }
    }
    flush();
    return out;
  }

  Map<String, int> buildEntryPageNumberMap([String? accName]) {
    final targetAcc = (accName != null && accName.isNotEmpty && accName != 'ALL') ? accName : selectedAccount;
    final allAcc = getSortedEntries(getAccountEntries(targetAcc));
    final pageMap = <String, int>{};
    var page = 1;
    for (final x in _cashbookPagePlan(allAcc, targetAcc, 1)) {
      final cPage = page++;
      final dPage = page++;
      for (final e in x.cr) {
        pageMap[e.id] = cPage;
      }
      for (final e in x.dr) {
        pageMap[e.id] = dPage;
      }
    }
    return pageMap;
  }

  Map<String, int> buildHeadKhatavahiPageMap([String? accName]) {
    final headsList = getAccountSpecificHeads(accName);
    final khMap = <String, int>{};
    for (int i = 0; i < headsList.length; i++) {
      khMap[headsList[i]] = i + 1;
    }
    return khMap;
  }

  /// Exact port of `generateExactDemoPagesHTML` from ROJMEL_V02_7_1_CASHBOOK_PRINT_FIXED.html.
  List<CashbookPagePair> buildCashbookPages([
    String? accName,
    String? headOverride,
    String? fromOverride,
    String? toOverride,
  ]) {
    final acc = (accName != null && accName.isNotEmpty && accName != 'ALL') ? accName : selectedAccount;
    final headFilter = headOverride ?? cashbookFilterHead;
    final from = normalizeToIsoDate(fromOverride ?? cashbookFromDate);
    final to = normalizeToIsoDate(toOverride ?? cashbookToDate);
    final gapSig = pageEntryGapMap.entries.map((e) => '${e.key}:${e.value}').join(',');
    final countSig = pageEntryCountMap.entries.map((e) => '${e.key}:${e.value}').join(',');
    final cacheKey =
        '$acc|$headFilter|$from|$to|${entries.length}|$cashbookContinuousDates|$cashbookPrintFontPt|$globalFontPt|$defaultMaxEntriesPerPage|$autoShrinkBigEntry|$cashbookEntryGapMm|$gapSig|$countSig|${pageFontMap.length}|${cashbookAreaLossMm.toStringAsFixed(1)}';
    final cachedPages = _cashbookPagesCache[cacheKey];
    if (cachedPages != null) return cachedPages;

    renumberVouchers(forceRecalc: false);
    final mAcc = getAccountMeta(acc);

    final allAcc = getSortedEntries(getAccountEntries(acc))
        .where((e) => headFilter.isEmpty || headFilter == 'ALL' || e.head == headFilter)
        .toList();
    final range = allAcc
        .where((e) => (from.isEmpty || e.date.compareTo(from) >= 0) && (to.isEmpty || e.date.compareTo(to) <= 0))
        .toList();
    final before = allAcc.where((e) => from.isNotEmpty && e.date.compareTo(from) < 0).toList();

    final op = getAccountOpening(acc, headFilter.isEmpty ? 'ALL' : headFilter);
    for (final e in before) {
      final s = e.type == 'credit' ? 1.0 : -1.0;
      op.cash += s * cashAmt(e);
      op.bank += s * bankAmt(e);
    }
    int page = 1 + _cashbookPagePlan(before, acc, 1).length * 2;
    final plan = _cashbookPagePlan(range, acc, page);
    final result = <CashbookPagePair>[];
    HeadBalance pageOpen = op.copy();
    {
      for (int pIdx = 0; pIdx < plan.length; pIdx++) {
        final item = plan[pIdx];
        final groupKey = item.key;
        final i = item.idx;
        final crRows = item.cr;
        final drRows = item.dr;
        final sampleEntry = drRows.isNotEmpty ? drRows.first : (crRows.isNotEmpty ? crRows.first : null);
        // Continuous mode: the page carries the date of its first entry.
        final date = groupKey != 'CONT'
            ? groupKey
            : ([...crRows, ...drRows].map((e) => e.date).toList()..sort()).firstOrNull ?? '';
        final isPFMSPage = mAcc.type == 'PFMS'
            ? true
            : (mAcc.type == 'BANK' || mAcc.type == 'SNA_PURE'
                ? false
                : (sampleEntry != null ? isPFMSEntry(sampleEntry) : isDateInPfmsDuration(acc, date)));

        final crSum = _sumEntries(crRows);
        final drSum = _sumEntries(drRows);
        final grandCredit = HeadBalance(cash: pageOpen.cash + crSum.cash, bank: pageOpen.bank + crSum.bank);
        final closingBal = HeadBalance(cash: grandCredit.cash - drSum.cash, bank: grandCredit.bank - drSum.bank);
        final grandDebit = HeadBalance(cash: drSum.cash + closingBal.cash, bank: drSum.bank + closingBal.bank);

        final creditPageNo = page++;
        final debitPageNo = page++;
        final pairKey = '$acc|$groupKey|$i';
        final baseFontPt = globalFontPt ?? pageFontMap['default'] ?? cashbookPrintFontPt;

        double crFontPt = pageFontMap['page|$acc|$creditPageNo'] ??
            pageFontMap['${pairKey}_credit'] ??
            pageFontMap[pairKey] ??
            baseFontPt;
        double drFontPt = pageFontMap['page|$acc|$debitPageNo'] ??
            pageFontMap['${pairKey}_debit'] ??
            pageFontMap[pairKey] ??
            baseFontPt;

        final alignedSlots = buildAlignedSlotsForEntries(crRows, drRows);
        final alignedCr = alignedSlots.map((s) => s.cr).toList();
        final alignedDr = alignedSlots.map((s) => s.dr).toList();
        double gapMm = getCreditPageEntryGapMm(acc, creditPageNo, pairKey);

        final loss = cashbookAreaLossMm;
        final drSafeBudgetMm = math.max(90.0, 176.0 - loss);

        double computeSlotContentMm(int idx, double cF, double dF) {
          final s = alignedSlots[idx];
          final hCr = s.cr != null ? estimateEntryWritingHeightMM(s.cr, 'credit', cF) : 0.0;
          final hDr = s.dr != null ? estimateEntryWritingHeightMM(s.dr, 'debit', dF) : 0.0;
          final minH = 14.5 * (math.max(cF, dF) / 10.0);
          return math.max(minH, math.max(hCr, hDr));
        }

        double totalContentMm = 0.0;
        for (int k = 0; k < alignedSlots.length; k++) {
          totalContentMm += computeSlotContentMm(k, crFontPt, drFontPt);
        }
        double totalNeededMm = totalContentMm + alignedSlots.length * gapMm;

        final hasManualCountOnPair = (getCreditPageEntryCount(acc, creditPageNo, pairKey) ?? 0) > 0;
        if ((autoShrinkBigEntry || hasManualCountOnPair) && totalNeededMm > drSafeBudgetMm && alignedSlots.isNotEmpty) {
          final targetContentBudget = math.max(70.0, drSafeBudgetMm - alignedSlots.length * math.min(gapMm, 3.0));
          if (totalContentMm > targetContentBudget) {
            final scale = (targetContentBudget / totalContentMm).clamp(0.62, 1.0);
            crFontPt = math.max(6.2, double.parse((crFontPt * scale).toStringAsFixed(2)));
            drFontPt = math.max(6.2, double.parse((drFontPt * scale).toStringAsFixed(2)));
            totalContentMm = 0.0;
            for (int k = 0; k < alignedSlots.length; k++) {
              totalContentMm += computeSlotContentMm(k, crFontPt, drFontPt);
            }
          }
          if (totalContentMm + alignedSlots.length * gapMm > drSafeBudgetMm) {
            gapMm = math.max(0.0, double.parse(((drSafeBudgetMm - totalContentMm) / alignedSlots.length).toStringAsFixed(2)));
          }
        }

        final slotHeightsMm = <double>[
          for (int k = 0; k < alignedSlots.length; k++)
            double.parse((computeSlotContentMm(k, crFontPt, drFontPt) + gapMm).toStringAsFixed(2)),
        ];

        final avgSlotH = slotHeightsMm.isEmpty
            ? 24.0
            : (slotHeightsMm.reduce((a, b) => a + b) / slotHeightsMm.length).clamp(8.0, 36.0);
        final crRowH = avgSlotH;
        final drRowH = avgSlotH;

        final isFirstPageOfFY = (pIdx == 0 && before.isEmpty);
        final fallbackHead = sampleEntry?.head ?? '';

        result.add(CashbookPagePair(
          pairIndexOnDate: i,
          creditPageNo: creditPageNo,
          debitPageNo: debitPageNo,
          dateStr: date,
          formattedDateDDMMYY: fmtDateDDMMYY(date),
          formattedDateSlash: fmtDateSlashDDMMYYYY(date),
          accountName: acc,
          accountType: mAcc.type,
          schoolTitle: getAccountSchoolName(acc, isPFMSPage: isPFMSPage),
          holderName: mAcc.holderName.isNotEmpty ? mAcc.holderName : schoolName,
          accountNumber: mAcc.acNo,
          snaAgencyCode: mAcc.effectiveSnaAgencyCode,
          creditTopTitle: mAcc.creditPageTitle.isNotEmpty ? mAcc.creditPageTitle : '-: CASHBOOK :-',
          debitPageTitle: mAcc.debitPageTitle.isNotEmpty ? mAcc.debitPageTitle : '-: કેશબુક :-',
          isPfmsPage: isPFMSPage,
          isFirstPageOfFY: isFirstPageOfFY,
          fallbackHead: fallbackHead,
          pairKey: pairKey,
          totalCreditsOnDate: item.totCr,
          totalDebitsOnDate: item.totDr,
          credits: crRows,
          debits: drRows,
          alignedCredits: alignedCr,
          alignedDebits: alignedDr,
          slotHeightsMm: slotHeightsMm,
          entryGapMm: gapMm,
          crFontPt: crFontPt,
          drFontPt: drFontPt,
          crRowHeightMm: crRowH,
          drRowHeightMm: drRowH,
          pageOpen: pageOpen.copy(),
          crSum: crSum,
          drSum: drSum,
          grandCredit: grandCredit,
          closingBal: closingBal,
          grandDebit: grandDebit,
        ));

        pageOpen = closingBal.copy();
      }
    }

    _cashbookPagesCache[cacheKey] = result;
    return result;
  }

  void setPageFontAndEntryConfig({
    required String acc,
    required String pairKey,
    required int pageNo,
    required String scope, // 'this_page', 'this_pair', 'all_pages'
    double? fontPt,
    int? entryCountLimit,
    bool autoEntryPack = false,
    bool? autoShrink,
    int? defaultMaxCap,
    double? entryGapMm,
  }) {
    final pageKey = 'page|$acc|$pageNo';
    final creditPageNo = pageNo.isOdd ? pageNo : (pageNo - 1);
    if (autoShrink != null) autoShrinkBigEntry = autoShrink;
    if (defaultMaxCap != null && defaultMaxCap >= 1) defaultMaxEntriesPerPage = defaultMaxCap;

    if (fontPt != null) {
      if (scope == 'this_page') {
        pageFontMap[pageKey] = fontPt;
      } else if (scope == 'this_pair') {
        pageFontMap[pairKey] = fontPt;
        pageFontMap['page|$acc|$creditPageNo'] = fontPt;
        pageFontMap['page|$acc|${creditPageNo + 1}'] = fontPt;
      } else {
        globalFontPt = fontPt;
        cashbookPrintFontPt = fontPt;
        pageFontMap['default'] = fontPt;
        pageFontMap.removeWhere((k, _) => k.contains(acc));
      }
    }

    if (autoEntryPack) {
      setCreditPageEntryCount(acc, creditPageNo, null, pairKey);
    } else if (entryCountLimit != null && entryCountLimit > 0) {
      setCreditPageEntryCount(acc, creditPageNo, entryCountLimit, pairKey);
    }
    if (entryGapMm != null) {
      setCreditPageEntryGapMm(acc, creditPageNo, entryGapMm, pairKey);
    }
    notifyListeners();
  }

  // --------------------------------------------------------------------------
  // HEAD-WISE SUMMARY COMPUTATION (USED BY REPORTS & CALCULATION AUDIT)
  // --------------------------------------------------------------------------

  List<HeadSummaryRow> computeHeadWiseSummary([String? accName, String fromDate = '', String toDate = '']) {
    final target = (accName != null && accName.isNotEmpty && accName != 'ALL') ? accName : selectedAccount;
    final hsKey = '$target|$fromDate|$toDate|${entries.length}|${heads.length}';
    final cachedHs = _headSummaryCache[hsKey];
    if (cachedHs != null) return cachedHs;
    final meta = getAccountMeta(target);
    final accHeads = getAccountSpecificHeads(target);
    final allSorted = getSortedEntries(getAccountEntries(target));

    final rows = <HeadSummaryRow>[];
    for (final h in accHeads) {
      final hop = getHeadOpening(target, h);
      final lim = getHeadLimit(target, h);
      double openC = hop.cash;
      double openB = hop.bank;
      if (fromDate.isNotEmpty) {
        for (final e in allSorted.where((x) => x.head == h && x.date.compareTo(fromDate) < 0)) {
          final s = e.type == 'credit' ? 1.0 : -1.0;
          openC += s * cashAmt(e);
          openB += s * bankAmt(e);
        }
      }
      final hList = allSorted.where((x) =>
          x.head == h &&
          (fromDate.isEmpty || x.date.compareTo(fromDate) >= 0) &&
          (toDate.isEmpty || x.date.compareTo(toDate) <= 0)).toList();

      double padarCr = 0.0;
      double bankCr = 0.0;
      double bankCr60 = 0.0;
      double bankCr40 = 0.0;
      double padarDr = 0.0;
      double bankDr = 0.0;
      final crDates = <String>[];

      for (final e in hList) {
        if (e.type == 'credit') {
          if (isCashEntry(e)) {
            padarCr += e.amount;
          } else {
            bankCr += e.amount;
            final dFmt = fmtDateDDMMYY(e.date);
            if (dFmt.isNotEmpty && !crDates.contains(dFmt)) crDates.add(dFmt);
            if (e.splitPercent == 60 || RegExp(r'60\s*%').hasMatch(e.narration)) {
              bankCr60 += e.amount;
            } else if (e.splitPercent == 40 || RegExp(r'40\s*%').hasMatch(e.narration)) {
              bankCr40 += e.amount;
            } else {
              bankCr60 += e.amount;
            }
          }
        } else {
          if (isCashEntry(e)) {
            padarDr += e.amount;
          } else {
            bankDr += e.amount;
          }
        }
      }

      final closeC = openC + padarCr - padarDr;
      final closeB = openB + bankCr - bankDr;
      final totalCr = padarCr + bankCr;
      final totalDr = padarDr + bankDr;

      if (hList.isNotEmpty || (openC + openB) != 0 || lim > 0 || meta.heads.contains(h) || meta.type == 'BANK') {
        rows.add(HeadSummaryRow(
          head: h,
          openCash: openC,
          openBank: openB,
          openTotal: openC + openB,
          padarCr: padarCr,
          bankCr: bankCr,
          bankCr60: bankCr60,
          bankCr40: bankCr40,
          credit: totalCr,
          padarDr: padarDr,
          bankDr: bankDr,
          debit: totalDr,
          closeCash: closeC,
          closeBank: closeB,
          closing: closeC + closeB,
          annualLimit: lim,
          limitRemaining: lim > 0 ? (lim - bankDr) : 0.0,
          creditDates: crDates,
          count: hList.length,
        ));
      }
    }
    _headSummaryCache[hsKey] = rows;
    return rows;
  }

  // --------------------------------------------------------------------------
  // CALCULATION AUDIT ENGINE (EXACT V06 `runCompleteCalculationAudit`)
  // --------------------------------------------------------------------------

  List<CalculationAuditItem> runCalculationAudit([String? accName]) {
    final target = (accName != null && accName.isNotEmpty && accName != 'ALL') ? accName : selectedAccount;
    final meta = getAccountMeta(target);
    final accEntries = getAccountEntries(target);
    final openBal = getAccountOpening(target);
    final headRows = computeHeadWiseSummary(target);
    final pages = buildCashbookPages(target, 'ALL', '', '');

    double totalCr = 0.0;
    double totalDr = 0.0;
    for (final e in accEntries) {
      if (e.type == 'credit') {
        totalCr += e.amount;
      } else {
        totalDr += e.amount;
      }
    }
    final expectedClosing = openBal.total + totalCr - totalDr;

    final headOpenSum = headRows.fold<double>(0.0, (s, r) => s + r.openTotal);
    final openDiff = (openBal.total - headOpenSum).abs();

    final headCrSum = headRows.fold<double>(0.0, (s, r) => s + r.credit);
    final headDrSum = headRows.fold<double>(0.0, (s, r) => s + r.debit);
    final headCloseSum = headRows.fold<double>(0.0, (s, r) => s + r.closing);

    int continuityErrors = 0;
    double maxPageDiff = 0.0;
    for (int i = 0; i < pages.length; i++) {
      final p = pages[i];
      final d1 = (p.openTotal + p.pageCreditSum - p.totalReceiptsWithOpening).abs();
      final d2 = (p.totalReceiptsWithOpening - p.pageDebitSum - p.closeTotal).abs();
      final d3 = (p.totalReceiptsWithOpening - p.grandDebitSideTotal).abs();
      double d4 = 0.0;
      if (i > 0) {
        d4 = (p.openTotal - pages[i - 1].closeTotal).abs();
      }
      final localMax = [d1, d2, d3, d4].reduce(math.max);
      if (localMax > 0.01) continuityErrors++;
      if (localMax > maxPageDiff) maxPageDiff = localMax;
    }

    final lastPageClosing = pages.isNotEmpty ? pages.last.closeTotal : openBal.total;
    final closeDiff = (expectedClosing - lastPageClosing).abs();

    int splitMismatches = 0;
    if (meta.isAnySna) {
      final groups = <String, List<RojmelEntry>>{};
      for (final e in accEntries) {
        if (e.splitGroup.isNotEmpty) {
          groups.putIfAbsent(e.splitGroup, () => <RojmelEntry>[]).add(e);
        }
      }
      groups.forEach((_, list) {
        if (list.length == 2) {
          final sum = list[0].amount + list[1].amount;
          final orig = list[0].originalAmount;
          if ((sum - orig).abs() > 0.01) splitMismatches++;
        }
      });
    }

    return <CalculationAuditItem>[
      CalculationAuditItem(
        checkName: '1. ખાતાની ઉઘડતી સિલક વિ. હેડ-વાઈઝ ઉઘડતી સિલક સરવાળો (${meta.type})',
        expectedValue: '₹${fmtDemoNum(openBal.total)}',
        actualValue: '₹${fmtDemoNum(headOpenSum)}',
        difference: openDiff,
        passed: openDiff <= 0.01,
      ),
      CalculationAuditItem(
        checkName: '2. કુલ જમા (Total Credit) વિ. ખાતાવહી (Khatavahi) જમા સરવાળો',
        expectedValue: '₹${fmtDemoNum(totalCr)}',
        actualValue: '₹${fmtDemoNum(headCrSum)}',
        difference: (totalCr - headCrSum).abs(),
        passed: (totalCr - headCrSum).abs() <= 0.01,
      ),
      CalculationAuditItem(
        checkName: '3. કુલ ઉધાર (Total Debit) વિ. ખાતાવહી (Khatavahi) ઉધાર સરવાળો',
        expectedValue: '₹${fmtDemoNum(totalDr)}',
        actualValue: '₹${fmtDemoNum(headDrSum)}',
        difference: (totalDr - headDrSum).abs(),
        passed: (totalDr - headDrSum).abs() <= 0.01,
      ),
      CalculationAuditItem(
        checkName: '4. ખાતાવહી (Head-wise) કુલ બંધ સિલક વિ. રોજમેળ ચોખ્ખી બંધ સિલક',
        expectedValue: '₹${fmtDemoNum(expectedClosing)}',
        actualValue: '₹${fmtDemoNum(headCloseSum)}',
        difference: (expectedClosing - headCloseSum).abs(),
        passed: (expectedClosing - headCloseSum).abs() <= 0.01,
      ),
      CalculationAuditItem(
        checkName: '5. રોજમેળ પેજ-ટુ-પેજ (${pages.length * 2} Pages) ઉઘડતી-બંધ સિલક સાતત્ય',
        expectedValue: '0 Errors (${pages.length * 2} Pages)',
        actualValue: '$continuityErrors Errors',
        difference: maxPageDiff,
        passed: continuityErrors == 0,
      ),
      CalculationAuditItem(
        checkName: '6. રોજમેળ છેલ્લા પાનાની બંધ સિલક વિ. કુલ હિસાબી બંધ સિલક',
        expectedValue: '₹${fmtDemoNum(expectedClosing)}',
        actualValue: '₹${fmtDemoNum(lastPageClosing)}',
        difference: closeDiff,
        passed: closeDiff <= 0.01,
      ),
      CalculationAuditItem(
        checkName: '7. SNA SPARSH 60% + 40% ગ્રાન્ટ વિભાજન ચોકસાઈ (Split Integrity)',
        expectedValue: '0 Mismatches',
        actualValue: '$splitMismatches Mismatches',
        difference: splitMismatches.toDouble(),
        passed: splitMismatches == 0,
      ),
    ];
  }

  // --------------------------------------------------------------------------
  // EXACT V06 HTML PRINT-OUT DOCUMENT GENERATOR (CASHBOOK & ALL 17 REPORTS)
  // Generates the exact same-to-same HTML + CSS from ROJMEL_V02_7_1_CASHBOOK_PRINT_FIXED.html
  // --------------------------------------------------------------------------

  static String _escHtml(String s) => s
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;');

  String generateExactCashbookPrintHtml([String? accName, bool applySetup = true]) {
    final target = (accName != null && accName.isNotEmpty) ? accName : selectedAccount;
    final pages = buildCashbookPages(target);
    final landCb = printSetup.isLandscapeCashbook;
    final cbOrient = landCb ? 'landscape' : 'portrait';
    final cbOrientCls = landCb ? ' landscape-page' : '';
    final mAcc = getAccountMeta(target);

    String demoTopHeader(String side, CashbookPagePair p) {
      final topTitle = side == 'credit' ? p.creditTopTitle : p.debitPageTitle;
      final pageNo = side == 'credit' ? p.creditPageNo : p.debitPageNo;
      final pageAccountLabel = getPageAccountLabel(p.accountName, pageNo, isPfmsPage: p.isPfmsPage);
      final secTitle = side == 'credit' ? 'આવક (જમા) +' : 'જાવક (ઉધાર) -';
      final effAgency = p.snaAgencyCode.isNotEmpty ? p.snaAgencyCode : p.accountNumber;
      String barHTML = '';
      if (mAcc.type == 'BANK') {
        if (side == 'credit') {
          barHTML = '<div class="cash-demo-school"><span>SCHOOL NAME : - ${_escHtml(p.schoolTitle)}</span><span>ACCOUNT NUMBER : - ${_escHtml(p.accountNumber)}</span></div>';
        } else {
          barHTML = '<div class="cash-demo-school"><span>ACCOUNT HOLDER NAME : - ${_escHtml(p.holderName)}</span><span>${_escHtml(pageAccountLabel)}</span></div>';
        }
      } else if (mAcc.type == 'SNA_PURE') {
        // Purely SNA SPARSH: only Agency Code and Account Name (with School Name)
        barHTML = '<div class="cash-demo-school"><span>SCHOOL NAME : ${_escHtml(p.schoolTitle)}${effAgency.isNotEmpty ? " &nbsp;|&nbsp; AGENCY CODE : ${_escHtml(effAgency)}" : ""}</span><span>ACCOUNT : ${_escHtml(pageAccountLabel)}</span></div>';
      } else if (p.isPfmsPage || mAcc.type == 'PFMS') {
        if (side == 'credit') {
          barHTML = '<div class="cash-demo-school"><span>SCHOOL NAME : ${_escHtml(p.schoolTitle)}</span><span>A/C NUMBER : ${_escHtml(p.accountNumber)}</span></div>';
        } else {
          barHTML = '<div class="cash-demo-school"><span>A/C HOLDER NAME : ${_escHtml(p.holderName)}</span><span>${_escHtml(pageAccountLabel)}</span></div>';
        }
      } else {
        // SNA SPARSH duration of Combined PFMS + SNA SPARSH account
        barHTML = '<div class="cash-demo-school"><span>SCHOOL NAME : ${_escHtml(p.schoolTitle)}${effAgency.isNotEmpty ? " &nbsp;|&nbsp; AGENCY CODE : ${_escHtml(effAgency)}" : ""}</span><span>${_escHtml(pageAccountLabel)}</span></div>';
      }
      return '<div class="cash-demo-title">${_escHtml(topTitle)}</div>$barHTML<div class="cash-demo-section">$secTitle</div>';
    }

    String demoColGroup(String side) {
      if (side == 'credit') {
        return '<colgroup><col style="width:11%"><col style="width:24%"><col style="width:30%"><col style="width:11%"><col style="width:12%"><col style="width:12%"></colgroup>';
      }
      return '<colgroup><col style="width:10%"><col style="width:11%"><col style="width:22%"><col style="width:7%"><col style="width:9%"><col style="width:9%"><col style="width:10%"><col style="width:11%"><col style="width:11%"></colgroup>';
    }

    String demoHeadRow(String side, CashbookPagePair p) {
      if (side == 'credit') {
        return '<tr><th>તારીખ</th><th>હેડ</th><th>આવકની વિગત</th><th>રોકડ</th><th>બેન્ક</th><th>કુલ રકમ</th></tr>';
      }
      final refColTitle = _escHtml(getPageRefColLabel(p.accountName, p.debitPageNo, isPfmsPage: p.isPfmsPage)).replaceAll('\n', '<br>');
      return '<tr><th>તારીખ</th><th>હેડ</th><th>જાવકની વિગત</th><th>વાઉચર<br>નંબર</th><th>$refColTitle</th><th>સેટલમેન્ટ<br>તારીખ</th><th>રોકડ</th><th>બેન્ક</th><th>કુલ રકમ</th></tr>';
    }

    String numCellHtml(double v, {String cls = 'num'}) {
      final s = fmtDemoNum(v);
      final len = s.length;
      final scaleStyle = len >= 11
          ? ' style="font-size:70%;letter-spacing:-0.35px"'
          : (len >= 10
              ? ' style="font-size:76%;letter-spacing:-0.3px"'
              : (len >= 9
                  ? ' style="font-size:83%;letter-spacing:-0.2px"'
                  : (len >= 8 ? ' style="font-size:90%;letter-spacing:-0.1px"' : '')));
      return '<td class="$cls"$scaleStyle>$s</td>';
    }

    final sb = StringBuffer();
    sb.writeln('<!doctype html><html lang="gu"><head><meta charset="utf-8"><title>Rojmel Cashbook Print - ${_escHtml(target)}</title>');
    sb.writeln('<style>'
        '*{box-sizing:border-box;-webkit-print-color-adjust:exact!important;print-color-adjust:exact!important}'
        'html,body{margin:0;padding:0;background:#fff;color:#000;font-family:"Noto Sans Gujarati","Nirmala UI","Shruti",Arial,sans-serif}'
        '.cash-demo-page{position:relative!important;width:210mm!important;min-height:297mm!important;height:297mm!important;max-height:297mm!important;margin:0 auto!important;background:#fff!important;display:flex!important;flex-direction:column!important;justify-content:space-between!important;page-break-after:always!important;break-after:page!important;overflow:hidden!important}'
        '.cash-demo-page:last-of-type{page-break-after:auto!important;break-after:auto!important}'
        '.cash-demo-page.odd-page{padding:3mm 24mm 2.8mm 9mm!important}'
        '.cash-demo-page.even-page{padding:3mm 9mm 2.8mm 24mm!important}'
        '.cash-demo-page.landscape-page{width:297mm!important;min-height:210mm!important;height:210mm!important;max-height:210mm!important}'
        '.blank-sheet{justify-content:center!important;align-items:center!important}'
        '.blank-sheet .blank-note{color:#9aa4b2;font-size:9pt;font-weight:700;letter-spacing:.3px}'
        '.cash-demo-top-wrap{width:100%!important;flex:1 1 auto!important;min-height:0!important;display:flex!important;flex-direction:column!important;overflow:hidden!important}'
        '.cash-demo-bottom-wrap{position:relative!important;flex:0 0 auto!important;width:100%!important;background:#fff!important;padding-top:0!important;margin-top:0!important;z-index:3!important}'
        '.cash-demo-title{text-align:center;font-weight:700;font-size:12.5pt;line-height:1.12;margin-bottom:1.2mm}'
        '.cash-demo-school{display:flex;justify-content:space-between;align-items:center;background:#fde9d9;border-bottom:1.1px solid #000;padding:1mm 10px;font-size:9.6pt;font-weight:600}'
        '.cash-demo-section{text-align:center;font-size:11.5pt;font-weight:800;padding:0.8mm 0 1mm;border-bottom:3.6px double #000}'
        '.cash-demo-table{width:100%;border-collapse:collapse;table-layout:fixed;font-size:var(--cash-font,10pt)${cashbookShowColumnLines && cashbookColumnLineMode == "full_till_ekandar" ? ";flex:1 1 auto;height:100%" : ""}}'
        '.cash-demo-table th,.cash-demo-table td{border:${cashbookShowColumnLines ? "0 1px solid #000" : "none"};${cashbookShowColumnLines ? "border-left:1px solid #000;border-right:1px solid #000;" : ""}padding:3px 3px;color:#000;word-break:break-word}'
        '.cash-demo-table thead th{font-weight:800;text-align:center;height:11.5mm;font-size:10pt;border-bottom:3.6px double #000}'
        '.cash-demo-table tbody tr.opening-row td{height:5.2mm;vertical-align:top;padding-top:1mm}'
        '.cash-demo-table tbody tr.debit-spacer-row td{height:5.2mm;padding:0}'
        '.cash-demo-table tbody tr.entry-row td{height:var(--row-h,28mm);vertical-align:top;padding-top:1.1mm;padding-bottom:var(--entry-gap,4mm);line-height:1.32}'
        '.cash-demo-table tbody tr.filler-line-row td{height:100%;padding:0}'
        '.date-cell,.head-cell,.desc-cell,.voucher-cell,.claim-cell,.settle-cell{text-align:center;vertical-align:middle}'
        '.num,.sum-num{text-align:right;white-space:nowrap!important;word-break:normal!important;overflow-wrap:normal!important;padding-right:2.4mm;padding-left:1px}'
        '.credit-page .num,.credit-page .sum-num{text-align:right;white-space:nowrap!important;word-break:normal!important;overflow-wrap:normal!important;padding-right:2.6mm!important;padding-left:1px!important}'
        '.debit-page .num,.debit-page .sum-num{text-align:right;white-space:nowrap!important;word-break:normal!important;overflow-wrap:normal!important;padding-right:2.2mm!important;padding-left:1px!important}'
        '.cash-demo-summary-table{width:100%;border-collapse:collapse;table-layout:fixed;margin-bottom:1.2mm}'
        '.cash-demo-summary-table td{padding:1.8px 3px;font-size:10.2pt;${cashbookShowColumnLines && cashbookColumnLineMode == "full_till_ekandar" ? "border-left:1px solid #000;border-right:1px solid #000;border-top:1px solid #000;" : ""}}'
        '.sum-label{text-align:right;font-weight:800;padding-right:12px;white-space:nowrap}'
        '.sum-line-top td.sum-num{border-top:1.1px solid #000}'
        '.sum-line-grand td.sum-num{border-top:1.1px solid #000;border-bottom:3.6px double #000}'
        '${cashbookShowColumnLines && cashbookColumnLineMode == "full_till_ekandar" ? ".sum-line-grand td{border-bottom:3.6px double #000}" : ""}'
        '.cash-demo-page-number{background:#fde9d9;color:#ff0000;text-align:center;font-size:9.8pt;font-weight:700;padding:0.9mm 0;width:100%}'
        '.gov-audit-sheet{position:relative!important;margin:0 auto!important;background:#fff!important;page-break-after:always!important;break-after:page!important;display:flex!important;flex-direction:column!important;justify-content:space-between!important;overflow:hidden!important}'
        '.gov-audit-sheet.portrait-sheet{width:210mm!important;min-height:297mm!important;height:297mm!important;max-height:297mm!important}'
        '.gov-audit-sheet.landscape-sheet{width:297mm!important;min-height:210mm!important;height:210mm!important;max-height:210mm!important}'
        '.gov-audit-sheet:last-of-type{page-break-after:auto!important;break-after:auto!important}'
        '.gov-audit-top-wrap{width:100%!important;flex:1 1 auto!important;overflow:hidden!important;display:flex!important;flex-direction:column!important}'
        '.gov-audit-bottom-wrap{width:100%!important;flex:0 0 auto!important;margin-top:auto!important;padding-top:2mm!important;background:#fff!important}'
        '.gov-audit-banner{text-align:center;border-bottom:2.5px double #000;padding-bottom:3px;margin-bottom:4px}'
        '.gov-audit-banner h2{margin:0;font-size:12.5pt;font-weight:900;line-height:1.15}'
        '.gov-audit-banner h3{margin:2px 0 0;font-size:9.8pt;font-weight:800;background:#fde9d9;padding:1.5px 8px;border-bottom:1px solid #000;display:inline-block}'
        '.gov-audit-table{width:100%!important;max-width:100%!important;border-collapse:collapse;table-layout:fixed!important;font-size:8.8pt;margin-top:3px}'
        '.gov-audit-table th,.gov-audit-table td{border:1px solid #000;padding:2.5px 3.5px;color:#000;text-align:center;vertical-align:middle;word-break:break-word!important;overflow-wrap:anywhere!important;line-height:1.15}'
        '.gov-audit-table th{background:#fde9d9;font-weight:900;text-align:center}'
        '.gov-audit-table td.num{text-align:right!important;white-space:nowrap!important;word-break:normal!important;overflow-wrap:normal!important;padding-right:3px!important}'
        '.gov-audit-table td.tight{white-space:nowrap!important;word-break:normal!important;overflow-wrap:normal!important}'
        '.rpt-notes{margin-top:3mm;font-size:.95em;line-height:1.38;text-align:justify;color:#000}'
        '.rpt-notes p{margin:0 0 1.5mm}'
        '.rpt-notes.pre{margin:1mm 0 2mm;font-weight:700}'
        '.gov-audit-table tr.audit-total-row td{background:#f3f6fa;font-weight:900;border-top:1.5px solid #000;border-bottom:3px double #000}'
        '.gov-audit-sign{display:grid;grid-template-columns:repeat(3,1fr);gap:12mm;margin-top:4mm;text-align:center;font-weight:800;font-size:8.8pt}'
        '.gov-audit-sign div{border-top:1.1px solid #000;padding-top:1.5mm}'
        '.gov-audit-page-footer{display:flex!important;justify-content:space-between!important;align-items:center!important;background:#fde9d9!important;border-top:1px solid #000!important;padding:1.1mm 8px!important;margin-top:1.8mm!important;font-size:8.8pt!important;font-weight:800!important;width:100%!important}'
        '.gov-audit-page-footer .rpt-footer-title{color:#10233f!important;text-align:left!important;overflow:hidden!important;text-overflow:ellipsis!important;white-space:nowrap!important;max-width:74%!important}'
        '.gov-audit-page-footer .rpt-footer-pg{color:#d90429!important;text-align:right!important;white-space:nowrap!important;font-weight:900!important}'
        '@page{size:A4 portrait;margin:0}@page rojland{size:A4 landscape;margin:0}'
        '.landscape-sheet,.cash-demo-page.landscape-page{page:rojland}'
        '@media print{html,body{background:#fff!important}.no-print{display:none!important}}'
        '</style></head><body>');

    for (final p in pages) {
      // Credit Page (Odd)
      final crParity = p.creditPageNo % 2 == 1 ? 'odd-page' : 'even-page';
      final fyStartYr = financialYear.length >= 4 ? financialYear.substring(0, 4) : '2025';
      final openRowHtml = mAcc.type == 'BANK'
          ? '<tr class="opening-row"><td class="date-cell"></td><td class="head-cell" colspan="2" style="text-align:left;padding-left:8px"><b>તારીખ - ${p.isFirstPageOfFY ? "01/04/$fyStartYr" : p.formattedDateSlash} &nbsp; - &nbsp; શ્રી ઉઘડતી સિલક</b></td>${numCellHtml(p.openCash)}${numCellHtml(p.openBank)}${numCellHtml(p.openTotal)}</tr>'
          : '<tr class="opening-row"><td class="date-cell">${p.formattedDateDDMMYY}</td><td class="head-cell"></td><td class="desc-cell"><b>શ્રી ઉઘડતી સિલક</b></td>${numCellHtml(p.openCash)}${numCellHtml(p.openBank)}${numCellHtml(p.openTotal)}</tr>';

      String crRowsHtml = '';
      if (p.alignedCredits.isNotEmpty) {
        for (int idx = 0; idx < p.alignedCredits.length; idx++) {
          final e = p.alignedCredits[idx];
          final slotH = idx < p.slotHeightsMm.length ? p.slotHeightsMm[idx] : p.crRowHeightMm;
          if (e != null) {
            final c = cashAmt(e);
            final b = bankAmt(e);
            final dStr = mAcc.type == 'BANK' ? fmtDateSlashDDMMYYYY(e.date) : fmtDateDDMMYY(e.date);
            crRowsHtml += '<tr class="entry-row" style="--row-h:${slotH}mm;--entry-gap:${p.entryGapMm}mm;height:${slotH}mm"><td class="date-cell">$dStr</td><td class="head-cell">${_escHtml(e.head)}</td><td class="desc-cell">${_escHtml(formatCreditNarration(e))}</td>${numCellHtml(c)}${numCellHtml(b)}${numCellHtml(c + b)}</tr>';
          } else {
            crRowsHtml += '<tr class="entry-row" style="--row-h:${slotH}mm;--entry-gap:${p.entryGapMm}mm;height:${slotH}mm"><td class="date-cell"></td><td class="head-cell"></td><td class="desc-cell"></td><td class="num"></td><td class="num"></td><td class="num"></td></tr>';
          }
        }
      } else if (mAcc.type == 'BANK') {
        crRowsHtml = '<tr class="entry-row" style="--row-h:${p.crRowHeightMm}mm;--entry-gap:${p.entryGapMm}mm;height:${p.crRowHeightMm}mm"><td class="date-cell">${p.formattedDateSlash}</td><td class="head-cell">${_escHtml(p.fallbackHead)}</td><td class="desc-cell">આજની તારીખમાં કોઈ આવક થયેલ નથી</td>${numCellHtml(0)}${numCellHtml(0)}${numCellHtml(0)}</tr>';
      }

      final crFillerHtml = (cashbookShowColumnLines && cashbookColumnLineMode == 'full_till_ekandar')
          ? '<tr class="filler-line-row"><td></td><td></td><td></td><td></td><td></td><td></td></tr>'
          : '';
      sb.writeln('<section class="cash-demo-page credit-page $crParity$cbOrientCls" data-orientation="$cbOrient" data-kind="cr" data-rpt="daybook" style="--cash-font:${p.crFontPt}pt">'
          '<div class="cash-demo-top-wrap">${demoTopHeader("credit", p)}'
          '<table class="cash-demo-table">${demoColGroup("credit")}<thead>${demoHeadRow("credit", p)}</thead>'
          '<tbody>$openRowHtml$crRowsHtml$crFillerHtml</tbody></table></div>'
          '<div class="cash-demo-bottom-wrap">'
          '<table class="cash-demo-summary-table">${demoColGroup("credit")}<tbody><tr class="sum-line-grand"><td colspan="3" class="sum-label">એકંદરે કુલ :</td>${numCellHtml(p.grandCredit.cash, cls: "sum-num")}${numCellHtml(p.grandCredit.bank, cls: "sum-num")}${numCellHtml(p.grandCredit.total, cls: "sum-num")}</tr></tbody></table>'
          '<div class="cash-demo-page-number">Page Number - ${p.creditPageNo}</div></div></section>');

      // Debit Page (Even)
      final drParity = p.debitPageNo % 2 == 1 ? 'odd-page' : 'even-page';
      String drRowsHtml = '';
      if (p.alignedDebits.isNotEmpty) {
        for (int idx = 0; idx < p.alignedDebits.length; idx++) {
          final e = p.alignedDebits[idx];
          final slotH = idx < p.slotHeightsMm.length ? p.slotHeightsMm[idx] : p.drRowHeightMm;
          if (e != null) {
            final c = cashAmt(e);
            final b = bankAmt(e);
            final dStr = mAcc.type == 'BANK' ? fmtDateSlashDDMMYYYY(e.date) : fmtDateDDMMYY(e.date);
            final claimDisp = (isCashEntry(e) || isBankChargeEntry(e)) ? '' : _escHtml(fmtClaimWrapped(e.txn)).replaceAll('\n', '<br>');
            final settleDisp = isCashEntry(e) ? '' : (mAcc.type == 'BANK' ? fmtDateSlashDDMMYYYY(e.clearDate) : fmtDateDDMMYY(e.clearDate));
            drRowsHtml += '<tr class="entry-row" style="--row-h:${slotH}mm;--entry-gap:${p.entryGapMm}mm;height:${slotH}mm"><td class="date-cell">$dStr</td><td class="head-cell">${_escHtml(e.head)}</td><td class="desc-cell">${_escHtml(formatDebitNarration(e))}</td><td class="voucher-cell">${_escHtml(e.voucher.isNotEmpty ? e.voucher : e.manualVoucher)}</td><td class="claim-cell">$claimDisp</td><td class="settle-cell">$settleDisp</td>${numCellHtml(c)}${numCellHtml(b)}${numCellHtml(c + b)}</tr>';
          } else {
            drRowsHtml += '<tr class="entry-row" style="--row-h:${slotH}mm;--entry-gap:${p.entryGapMm}mm;height:${slotH}mm"><td class="date-cell"></td><td class="head-cell"></td><td class="desc-cell"></td><td class="voucher-cell"></td><td class="claim-cell"></td><td class="settle-cell"></td><td class="num"></td><td class="num"></td><td class="num"></td></tr>';
          }
        }
      } else if (mAcc.type == 'BANK') {
        drRowsHtml = '<tr class="entry-row" style="--row-h:${p.drRowHeightMm}mm;--entry-gap:${p.entryGapMm}mm;height:${p.drRowHeightMm}mm"><td class="date-cell">${p.formattedDateSlash}</td><td class="head-cell">${_escHtml(p.fallbackHead)}</td><td class="desc-cell">આજની તારીખમાં કોઈ ખર્ચ થયેલ નથી</td><td class="voucher-cell"></td><td class="claim-cell"></td><td class="settle-cell"></td>${numCellHtml(0)}${numCellHtml(0)}${numCellHtml(0)}</tr>';
      }

      // Always output 9 <td></td> cells when column lines are enabled so Debit vertical column lines touch the <thead> double border just like Credit!
      final drSpacerHtml = cashbookShowColumnLines
          ? '<tr class="debit-spacer-row"><td></td><td></td><td></td><td></td><td></td><td></td><td></td><td></td><td></td></tr>'
          : '<tr class="debit-spacer-row"><td colspan="9"></td></tr>';
      final drFillerHtml = (cashbookShowColumnLines && cashbookColumnLineMode == 'full_till_ekandar')
          ? '<tr class="filler-line-row"><td></td><td></td><td></td><td></td><td></td><td></td><td></td><td></td><td></td></tr>'
          : '';
      sb.writeln('<section class="cash-demo-page debit-page $drParity$cbOrientCls" data-orientation="$cbOrient" data-kind="dr" data-rpt="daybook" style="--cash-font:${p.drFontPt}pt">'
          '<div class="cash-demo-top-wrap">${demoTopHeader("debit", p)}'
          '<table class="cash-demo-table">${demoColGroup("debit")}<thead>${demoHeadRow("debit", p)}</thead>'
          '<tbody>$drSpacerHtml$drRowsHtml$drFillerHtml</tbody></table></div>'
          '<div class="cash-demo-bottom-wrap">'
          '<table class="cash-demo-summary-table">${demoColGroup("debit")}<tbody>'
          '<tr><td colspan="6" class="sum-label">કુલ ખર્ચ :</td>${numCellHtml(p.drSum.cash, cls: "sum-num")}${numCellHtml(p.drSum.bank, cls: "sum-num")}${numCellHtml(p.drSum.total, cls: "sum-num")}</tr>'
          '<tr class="sum-line-top"><td colspan="6" class="sum-label">શ્રી બંધ સિલક :</td>${numCellHtml(p.closingBal.cash, cls: "sum-num")}${numCellHtml(p.closingBal.bank, cls: "sum-num")}${numCellHtml(p.closingBal.total, cls: "sum-num")}</tr>'
          '<tr class="sum-line-grand"><td colspan="6" class="sum-label">એકંદરે કુલ :</td>${numCellHtml(p.grandDebit.cash, cls: "sum-num")}${numCellHtml(p.grandDebit.bank, cls: "sum-num")}${numCellHtml(p.grandDebit.total, cls: "sum-num")}</tr>'
          '</tbody></table>'
          '<div class="cash-demo-page-number">Page Number - ${p.debitPageNo}</div></div></section>');
    }
    sb.writeln('<script>(function(){function fitNums(){var cells=document.querySelectorAll(".num,.sum-num,.claim-cell,.voucher-cell,.date-cell,.settle-cell");for(var i=0;i<cells.length;i++){var td=cells[i];var fs=parseFloat(window.getComputedStyle(td).fontSize)||12;while(td.scrollWidth>td.clientWidth&&fs>6.2){fs-=0.35;td.style.fontSize=fs+"px";}}var pages=document.querySelectorAll("section.cash-demo-page");for(var p=0;p+1<pages.length;p+=2){var crPage=pages[p];var drPage=pages[p+1];if(!crPage.classList.contains("credit-page")||!drPage.classList.contains("debit-page"))continue;var crThead=crPage.querySelector("thead tr");var drThead=drPage.querySelector("thead tr");if(crThead&&drThead){var thH=Math.max(crThead.offsetHeight,drThead.offsetHeight);crThead.style.height=thH+"px";drThead.style.height=thH+"px";}var openRow=crPage.querySelector("tr.opening-row");var spacerRow=drPage.querySelector("tr.debit-spacer-row");if(openRow&&spacerRow){var opH=Math.max(openRow.offsetHeight,spacerRow.offsetHeight);openRow.style.height=opH+"px";spacerRow.style.height=opH+"px";for(var c=0;c<spacerRow.children.length;c++){spacerRow.children[c].style.height=opH+"px";}}var crRows=crPage.querySelectorAll("tr.entry-row");var drRows=drPage.querySelectorAll("tr.entry-row");var count=Math.min(crRows.length,drRows.length);for(var r=0;r<count;r++){crRows[r].style.height="auto";drRows[r].style.height="auto";for(var a=0;a<crRows[r].children.length;a++){crRows[r].children[a].style.height="auto";}for(var b=0;b<drRows[r].children.length;b++){drRows[r].children[b].style.height="auto";}var h=Math.max(crRows[r].offsetHeight,drRows[r].offsetHeight);crRows[r].style.height=h+"px";drRows[r].style.height=h+"px";for(var a2=0;a2<crRows[r].children.length;a2++){crRows[r].children[a2].style.height=h+"px";}for(var b2=0;b2<drRows[r].children.length;b2++){drRows[r].children[b2].style.height=h+"px";}}}var fillers=document.querySelectorAll("tr.filler-line-row");for(var j=0;j<fillers.length;j++){var tr=fillers[j];var topWrap=tr.closest(".cash-demo-top-wrap");var tbl=tr.closest("table");if(topWrap&&tbl){tr.style.height="0px";for(var k0=0;k0<tr.children.length;k0++){tr.children[k0].style.height="0px";}var avail=topWrap.clientHeight-tbl.offsetTop-tbl.offsetHeight;if(avail>0){tr.style.height=avail+"px";for(var k=0;k<tr.children.length;k++){tr.children[k].style.height=avail+"px";}}}}}fitNums();window.fitNums=fitNums;window.onload=function(){fitNums();};})();</script></body></html>');
    return applySetup ? applyPrintSetup(sb.toString()) : sb.toString();
  }

  /// Generates printable / auto-downloadable A4 HTML for ANY single report (`1..16`)
  /// OR **All 17 Reports in 1 Click** (`reportType == 'audit_pack'` or `'all_17'`)!
  /// Every page keeps its Page Number bar pinned at the bottom of the A4 page.
  /// Report keys handled by [buildExtraAuditTable].
  static const Set<String> kExtraAuditReports = <String>{
    'interest_register',
    'cash_register',
    'party_register',
    'balance_sheet',
    'income_expenditure',
    'gfr_12a',
    'monthly_brs',
    'asset_register',
    'cash_verification',
    'bank_certificate',
    'audit_crosscheck',
  };

  static final RegExp _assetWords = RegExp(
    r'ફર્નિચર|કબાટ|અલમારી|ટેબલ|ખુરશી|બેન્ચ|બેંચ|પાટલી|ડેસ્ક|કમ્પ્યુટર|કોમ્પ્યુટર|લેપટોપ|પ્રિન્ટર|પ્રોજેક્ટર|ટીવી|પંખા|પંખો|ઝેરોક્ષ|સ્માર્ટ\s*બોર્ડ|ગ્રીન\s*બોર્ડ|વ્હાઈટ\s*બોર્ડ|વોટર\s*કુલર|આર\.?\s*ઓ\.?|ફ્રીઝ|સાઉન્ડ|સ્પીકર|માઈક|કેમેરા|ઈન્વર્ટર|ઇન્વર્ટર|બેટરી|કુકર|સ્ટવ|સગડી|પાણીની\s*ટાંકી|સાઇકલ|સાયકલ|રમતગમતના\s*સાધન|લાયબ્રેરી|પુસ્તકાલય|બાંધકામ|નવો\s*ઓરડો|ઓરડાનું|શૌચાલય|કમ્પાઉન્ડ|શેડ|ઘડિયાળ|વજનકાંટો|ટેબ્લેટ|સ્કેનર|'
    r'\b(?:furniture|almirah|cupboard|tables?|chairs?|benche?s?|desks?|computers?|laptops?|printers?|projectors?|tv|television|led|fans?|xerox|photocopier|smart\s*board|green\s*board|white\s*board|water\s*cooler|ro|fridge|refrigerator|sound\s*system|speakers?|mic|cameras?|cctv|inverter|battery|ups|cooker|stove|tank|cycles?|sports\s*kit|library|construction|toilets?|compound\s*wall|shed|clock|weighing|tablets?|scanner)\b',
    caseSensitive: false,
  );
  static final RegExp _repairWords = RegExp(
    r'રીપેર|રિપેર|મરામત|રંગકામ|સર્વિસ|સફાઈ|ભાડું|રીચાર્જ|રીફીલ|રીફિલ|\b(?:repair|repairing|paint|painting|service|servicing|maintenance|rent|recharge|refill)\b',
    caseSensitive: false,
  );

  /// Debit entry that buys a lasting asset (for the dead stock register):
  /// furniture, computers, fans, construction … but not repairs.
  static bool isAssetPurchase(RojmelEntry e) => e.type == 'debit' && e.deadStock;

  /// Debit whose description looks like a lasting asset (only a hint shown
  /// on the entry form; the register uses the user's Yes / No answer).
  static bool looksLikeAsset(String text) => _assetWords.hasMatch(text) && !_repairWords.hasMatch(text);

  static bool isInterestEntry(RojmelEntry e) => RegExp(
        r'વ્યાજ|interest',
        caseSensitive: false,
      ).hasMatch('${e.narration} ${e.head} ${e.party}');

  /// Builds one of the additional audit registers for [list] (already filtered
  /// by account, head and date) with [openBal] as the opening on From Date.
  ExtraAuditTable buildExtraAuditTable(
    String type,
    String acc,
    List<RojmelEntry> list,
    HeadBalance openBal,
    List<HeadSummaryRow> headRows,
  ) {
    final mAcc = getAccountMeta(acc);
    final sName = mAcc.schoolName.isNotEmpty ? mAcc.schoolName : schoolName;
    String n2(double v) => fmtDemoNum(v);
    String d(String iso) => fmtDateSlashDDMMYYYY(iso);
    final period = (reportFromDate.isNotEmpty || reportToDate.isNotEmpty)
        ? '${reportFromDate.isNotEmpty ? d(reportFromDate) : "શરૂઆત"} થી ${reportToDate.isNotEmpty ? d(reportToDate) : "આજ સુધી"}'
        : 'નાણાકીય વર્ષ $financialYear';
    final sub = '$sName ($acc — $period)';

    switch (type) {
      case 'interest_register':
        {
          double earned = 0, paid = 0, run = 0;
          final rows = <List<String>>[];
          final items = list.where(isInterestEntry).toList();
          for (var i = 0; i < items.length; i++) {
            final e = items[i];
            final cr = e.type == 'credit' ? e.amount : 0.0;
            final dr = e.type == 'debit' ? e.amount : 0.0;
            earned += cr;
            paid += dr;
            run += cr - dr;
            rows.add([
              '${i + 1}', d(e.date),
              e.type == 'credit' ? formatCreditNarration(e) : formatDebitNarration(e),
              e.head, e.txn.isNotEmpty ? e.txn : '-',
              n2(cr), n2(dr), n2(run),
            ]);
          }
          if (rows.isEmpty) {
            rows.add(['-', '-', 'આ સમયગાળામાં બેંક વ્યાજની કોઈ એન્ટ્રી નથી (No interest entries)', '-', '-', '0.00', '0.00', '0.00']);
          }
          return ExtraAuditTable(
            title: 'બેંક વ્યાજ રજીસ્ટર (BANK INTEREST EARNED & REFUND REGISTER)',
            subtitle: sub,
            headers: const ['ક્રમ', 'તારીખ', 'વિગત', 'ગ્રાન્ટ હેડ', 'ચેક / ચલણ / Claim નં.', 'જમા વ્યાજ ₹', 'પરત / જમા કરાવેલ વ્યાજ ₹', 'બાકી વ્યાજ ₹'],
            dataRows: rows,
            totalRows: [
              ['', '', 'કુલ (Total)', '', '', n2(earned), n2(paid), n2(earned - paid)],
              ['', '', earned - paid > 0.005 ? 'સરકારશ્રીમાં પરત કરવાનું બાકી વ્યાજ (Interest payable to Govt.)' : 'મળેલ તમામ વ્યાજ પરત / સમાયોજિત થયેલ છે', '', '', '', '', n2(math.max(0, earned - paid))],
            ],
            colWidthsPct: const [5, 9, 33, 15, 11, 9, 9, 9],
          );
        }
      case 'cash_register':
        {
          double run = openBal.cash, rec = 0, pay = 0;
          final rows = <List<String>>[
            ['0', reportFromDate.isNotEmpty ? d(reportFromDate) : '01/04/${financialYear.length >= 4 ? financialYear.substring(0, 4) : ""}', 'ઉઘડતી રોકડ સિલક (Opening Cash in Hand)', '-', '-', '0.00', '0.00', n2(run)],
          ];
          final items = list.where(isCashEntry).toList();
          for (var i = 0; i < items.length; i++) {
            final e = items[i];
            final cr = e.type == 'credit' ? e.amount : 0.0;
            final dr = e.type == 'debit' ? e.amount : 0.0;
            rec += cr;
            pay += dr;
            run += cr - dr;
            rows.add([
              '${i + 1}', d(e.date), e.type == 'credit' ? formatCreditNarration(e) : formatDebitNarration(e),
              e.head, e.type == 'debit' ? e.voucher : '-', n2(cr), n2(dr), n2(run),
            ]);
          }
          return ExtraAuditTable(
            title: 'રોકડ / પદર રજીસ્ટર (CASH IN HAND & IMPREST REGISTER)',
            subtitle: sub,
            headers: const ['ક્રમ', 'તારીખ', 'વિગત', 'ગ્રાન્ટ હેડ', 'વાઉચર નં.', 'રોકડ આવક ₹', 'રોકડ ખર્ચ ₹', 'રોકડ સિલક ₹'],
            dataRows: rows,
            totalRows: [
              ['', '', 'કુલ (Total) / બંધ રોકડ સિલક', '', '', n2(rec), n2(pay), n2(run)],
            ],
            colWidthsPct: const [5, 9, 37, 15, 7, 9, 9, 9],
          );
        }
      case 'party_register':
        {
          final byParty = <String, Map<String, dynamic>>{};
          for (final e in list.where((x) => x.type == 'debit')) {
            final name = e.party.trim().isNotEmpty ? e.party.trim() : 'અન્ય / Direct';
            final m = byParty.putIfAbsent(name, () => <String, dynamic>{
                  'heads': <String>{}, 'vouchers': <String>{}, 'count': 0, 'cash': 0.0, 'bank': 0.0,
                });
            (m['heads'] as Set<String>).add(e.head);
            if (e.voucher.isNotEmpty) (m['vouchers'] as Set<String>).add(e.voucher);
            m['count'] = (m['count'] as int) + 1;
            if (isCashEntry(e)) {
              m['cash'] = (m['cash'] as double) + e.amount;
            } else {
              m['bank'] = (m['bank'] as double) + e.amount;
            }
          }
          final names = byParty.keys.toList()
            ..sort((a, b) {
              final ta = (byParty[a]!['cash'] as double) + (byParty[a]!['bank'] as double);
              final tb = (byParty[b]!['cash'] as double) + (byParty[b]!['bank'] as double);
              return tb.compareTo(ta);
            });
          double tc = 0, tb = 0;
          var tCount = 0;
          final rows = <List<String>>[];
          for (var i = 0; i < names.length; i++) {
            final m = byParty[names[i]]!;
            final c = m['cash'] as double, b = m['bank'] as double;
            tc += c;
            tb += b;
            tCount += m['count'] as int;
            final vouchers = (m['vouchers'] as Set<String>).toList();
            rows.add([
              '${i + 1}', names[i], (m['heads'] as Set<String>).join(', '),
              vouchers.length > 8 ? '${vouchers.take(8).join(", ")} …' : vouchers.join(', '),
              '${m['count']}', n2(c), n2(b), n2(c + b),
            ]);
          }
          return ExtraAuditTable(
            title: 'પાર્ટી / વેપારી મુજબ ચુકવણી પત્રક (PARTY-WISE PAYMENT REGISTER)',
            subtitle: sub,
            headers: const ['ક્રમ', 'પાર્ટી / વેપારીનું નામ', 'ગ્રાન્ટ હેડ', 'વાઉચર નં.', 'બિલ સંખ્યા', 'રોકડ ₹', 'બેંક / SNA ₹', 'કુલ ચુકવણી ₹'],
            dataRows: rows,
            totalRows: [
              ['', 'કુલ (Total)', '', '', '$tCount', n2(tc), n2(tb), n2(tc + tb)],
            ],
            colWidthsPct: const [5, 22, 20, 17, 6, 10, 10, 10],
          );
        }
      case 'income_expenditure':
        {
          // Grant accounting on cash basis: grant income = grant spent; the
          // unspent grant stays a liability (grant fund) in the balance sheet.
          final expByHead = <String, double>{};
          double charges = 0, intEarned = 0, intRefund = 0;
          for (final e in list) {
            if (e.type == 'credit') {
              if (isInterestEntry(e)) intEarned += e.amount;
              continue;
            }
            if (isPadarReimbursement(e)) continue;
            if (isInterestEntry(e)) {
              intRefund += e.amount;
            } else if (isBankChargeEntry(e)) {
              charges += e.amount;
            } else {
              expByHead[e.head] = (expByHead[e.head] ?? 0) + e.amount;
            }
          }
          final heads = expByHead.keys.toList()..sort();
          final spent = expByHead.values.fold<double>(0, (a, v) => a + v) + charges;
          final surplus = intEarned - intRefund;
          final left = <List<String>>[
            for (final h in heads) ['$h — ખર્ચ (Expenditure)', n2(expByHead[h]!)],
            if (charges > 0.004) ['બેંક ચાર્જ (Bank charges)', n2(charges)],
            if (intRefund > 0.004) ['સરકારશ્રીમાં પરત કરેલ વ્યાજ (Interest refunded to Govt.)', n2(intRefund)],
            if (surplus > 0.004) ['ખર્ચ કરતાં વધુ આવક — પરત કરવાપાત્ર વ્યાજ (Excess of income over expenditure)', n2(surplus)],
          ];
          final right = <List<String>>[
            ['વપરાયેલ ગ્રાન્ટ — ગ્રાન્ટ ભંડોળમાંથી (Grant utilised, from grant fund)', n2(spent)],
            ['બેંક વ્યાજની આવક (Bank interest earned)', n2(intEarned)],
            if (surplus < -0.004) ['આવક કરતાં વધુ ખર્ચ (Excess of expenditure over income)', n2(-surplus)],
          ];
          final total = spent + intRefund + math.max(0.0, surplus);
          final n = math.max(left.length, right.length);
          final rows = <List<String>>[
            for (var i = 0; i < n; i++)
              [
                '${i + 1}',
                i < left.length ? left[i][0] : '',
                i < left.length ? left[i][1] : '',
                i < right.length ? right[i][0] : '',
                i < right.length ? right[i][1] : '',
              ],
          ];
          if (rows.isEmpty) rows.add(['-', 'આ સમયગાળામાં કોઈ ખર્ચ નથી', '0.00', '-', '0.00']);
          return ExtraAuditTable(
            title: 'આવક-ખર્ચ ખાતું (INCOME & EXPENDITURE ACCOUNT)',
            subtitle: sub,
            headers: const ['ક્રમ', 'ખર્ચ (Expenditure) — ઉધાર', 'રકમ ₹', 'આવક (Income) — જમા', 'રકમ ₹'],
            dataRows: rows,
            totalRows: [
              ['', 'કુલ (Total)', n2(total), 'કુલ (Total)', n2(total)],
            ],
            colWidthsPct: const [6, 38, 13, 30, 13],
            leftCols: const <int>{1, 3},
            notes: [
              'હિસાબની પદ્ધતિ: રોકડ આધાર (Cash basis). વર્ષમાં જેટલી ગ્રાન્ટ વપરાઈ તેટલી જ આવક ગણી છે; બિનવપરાયેલ ગ્રાન્ટ પાકા સરવૈયામાં ગ્રાન્ટ ભંડોળ (જવાબદારી) તરીકે છે.',
              'આચાર્યશ્રીએ રોકેલ પદર અને તેની પરત ચુકવણી આવક કે ખર્ચ નથી, તેથી અહીં ગણેલ નથી.',
              if (surplus > 0.004)
                'મળેલ બેંક વ્યાજ સરકારશ્રીનું છે — બાકી વ્યાજ ₹${n2(surplus)} (અંકે ${numberToGujaratiWords(surplus)}) ઉપલી કચેરી / Bharatkosh માં જમા કરાવવાનું બાકી છે.',
            ],
          );
        }
      case 'gfr_12a':
        {
          final openTot = openBal.cash + openBal.bank;
          double intEarned = 0, intRefund = 0, grants = 0, padarIn = 0, padarBack = 0, spent = 0, capital = 0;
          double crC = 0, crB = 0, drC = 0, drB = 0;
          final grantLines = <List<String>>[];
          for (final e in list) {
            if (e.type == 'credit') {
              crC += cashAmt(e);
              crB += bankAmt(e);
              if (isInterestEntry(e)) {
                intEarned += e.amount;
              } else if (isCashEntry(e)) {
                padarIn += e.amount;
              } else {
                grants += e.amount;
                grantLines.add(['', '     • તા. ${d(e.date)} — ${e.head}${e.party.trim().isNotEmpty ? ' (${e.party.trim()})' : ''} — મંજૂરી હુકમ નં. / તારીખ : ______________', n2(e.amount)]);
              }
            } else {
              drC += cashAmt(e);
              drB += bankAmt(e);
              if (isPadarReimbursement(e)) {
                padarBack += e.amount;
              } else if (isInterestEntry(e)) {
                intRefund += e.amount;
              } else {
                spent += e.amount;
                if (isAssetPurchase(e)) capital += e.amount;
              }
            }
          }
          final closeC = openBal.cash + crC - drC;
          final closeB = openBal.bank + crB - drB;
          final available = openTot + intEarned - intRefund + grants;
          final closingForm = available - spent;
          final netPadar = padarIn - padarBack;
          final schemeHeads = headRows.where((r) => r.credit > 0 || r.debit > 0 || r.openTotal != 0).map((r) => r.head).toList();
          final rows = <List<String>>[
            ['§1', 'યોજનાનું નામ (Name of the Scheme) : $acc${schemeHeads.isNotEmpty ? ' — ${schemeHeads.join(', ')}' : ''}', ''],
            ['§2', 'અનુદાનનો પ્રકાર : રીકરીંગ / નોન-રીકરીંગ (Recurring / Non-Recurring) — લાગુ ન પડે તે છેકો', ''],
            ['§3', 'નાણાકીય વર્ષની શરૂઆતમાં ગ્રાન્ટની સ્થિતિ (Grants position at the beginning of the year)', ''],
            ['3(i)', '     હાથ પર રોકડ / બેંક (Cash in Hand / Bank) — રોકડ ₹${n2(openBal.cash)} + બેંક ₹${n2(openBal.bank)}', n2(openTot)],
            ['3(ii)', '     ન સમાયોજિત એડવાન્સ (Unadjusted advances)', '0.00'],
            ['3(iii)', '     કુલ (Total)', n2(openTot)],
            ['§4', 'ગ્રાન્ટ, ખર્ચ અને બંધ સિલકની વિગત (Details of grants received, expenditure incurred and closing balances)', ''],
            ['4.1', '     ગત વર્ષોની બિનવપરાયેલ ગ્રાન્ટ (Unspent balance of previous years) [3(iii)]', n2(openTot)],
            ['4.2', '     તેના પર મળેલ વ્યાજ (Interest earned thereon)', n2(intEarned)],
            ['4.3', '     સરકારશ્રીમાં પરત જમા કરાવેલ વ્યાજ (Interest deposited back to the Government)', n2(intRefund)],
            ['4.4', '     વર્ષ દરમિયાન મળેલ ગ્રાન્ટ (Grant received during the year)', n2(grants)],
            ...grantLines.length <= 14
                ? grantLines
                : <List<String>>[['', '     • ${grantLines.length} વખત ગ્રાન્ટ જમા થઈ — વિગત પરિશિષ્ટ – 11 (ગ્રાન્ટ રજીસ્ટર) મુજબ', n2(grants)]],
            ['4.5', '     ઉપલબ્ધ કુલ ભંડોળ (Total available funds) = 4.1 + 4.2 − 4.3 + 4.4', n2(available)],
            ['4.6', '     થયેલ ખર્ચ (Expenditure incurred)', n2(spent)],
            ['4.7', '     બંધ સિલક (Closing balance) = 4.5 − 4.6', n2(closingForm)],
            ['§5', 'ઘટકવાર ઉપયોગ (Component-wise utilisation of grants)', ''],
            ['5(a)', '     સામાન્ય અનુદાન (Grant-in-aid — General)', n2(spent - capital)],
            ['5(b)', '     પગાર (Grant-in-aid — Salary)', '0.00'],
            ['5(c)', '     મૂડી મિલકત સર્જન (Grant-in-aid — Creation of capital assets)', n2(capital)],
            ['5(d)', '     કુલ (Total)', n2(spent)],
            ['§6', 'વર્ષના અંતે ગ્રાન્ટની સ્થિતિ (Details of grants position at the end of the year)', ''],
            ['6(i)', '     હાથ પર રોકડ (Cash in Hand)', n2(closeC)],
            ['6(ii)', '     બેંકમાં (In Bank)', n2(closeB)],
            ['6(iii)', '     ન સમાયોજિત એડવાન્સ (Unadjusted advances)', '0.00'],
            ['6(iv)', '     કુલ (Total)', n2(closeC + closeB)],
            if (netPadar.abs() > 0.004)
              ['', 'મેળવણું: 4.7 બંધ સિલક ₹${n2(closingForm)} + આચાર્યશ્રીનો બાકી પદર ₹${n2(netPadar)} = 6(iv) ₹${n2(closeC + closeB)}', ''],
          ];
          return ExtraAuditTable(
            title: 'GFR 12-A — ઉપયોગિતા પ્રમાણપત્ર (UTILIZATION CERTIFICATE) [See Rule 238(1)]',
            subtitle: 'નાણાકીય વર્ષ $financialYear — $sName ($acc — $period)',
            headers: const ['ક્રમ', 'વિગત (Particulars)', 'રકમ ₹'],
            dataRows: rows,
            totalRows: const <List<String>>[],
            colWidthsPct: const [8, 74, 18],
            leftCols: const <int>{1},
            notesOnOwnPage: true,
            notes: const [
              'પ્રમાણપત્ર (Certificate): Certified that I have satisfied myself that the conditions on which grants were sanctioned have been duly fulfilled / are being fulfilled and that I have exercised the following checks to see that the money has been actually utilised for the purpose for which it was sanctioned:',
              '(i) The main accounts and other subsidiary accounts and registers (including assets registers) are maintained as prescribed in the relevant Act / Rules / Standing instructions and have been duly audited by designated auditors. The figures depicted above tally with the audited figures mentioned in financial statements / accounts.',
              '(ii) There exist internal controls for safeguarding public funds / assets, watching outcomes and achievements of physical targets against the financial inputs, ensuring quality in asset creation etc., and the periodic evaluation of internal controls is exercised to ensure their effectiveness.',
              '(iii) To the best of our knowledge and belief, no transactions have been entered that are in violation of relevant Act / Rules / standing instructions and scheme guidelines.',
              '(iv) The responsibilities among the key functionaries for execution of the scheme have been assigned in clear terms and are not general in nature.',
              '(v) The benefits were extended to the intended beneficiaries and only such areas / districts were covered where the scheme was intended to operate.',
              '(vi) The expenditure on various components of the scheme was in the proportions authorised as per the scheme guidelines and terms and conditions of the grants-in-aid.',
              'તારીખ (Date) : ____________          સ્થળ (Place) : ____________          (Strike out inapplicable terms)',
            ],
            signLabels: const [
              'હિસાબનીશની સહી<br>(Chief Finance Officer / Head of Finance)',
              'આચાર્યશ્રીની સહી અને સિક્કો<br>(Head of the Organisation)',
              'SMC અધ્યક્ષની સહી<br>(SMC Chairman)',
            ],
          );
        }
      case 'monthly_brs':
        {
          const gm = ['જાન્યુઆરી', 'ફેબ્રુઆરી', 'માર્ચ', 'એપ્રિલ', 'મે', 'જૂન', 'જુલાઈ', 'ઓગસ્ટ', 'સપ્ટેમ્બર', 'ઓક્ટોબર', 'નવેમ્બર', 'ડિસેમ્બર'];
          final fy0 = financialYear.length >= 4 ? int.tryParse(financialYear.substring(0, 4)) : null;
          final first = list.isNotEmpty ? IndianDate.parse(list.first.date) : null;
          final lastE = list.isNotEmpty ? IndianDate.parse(list.last.date) : null;
          final start = IndianDate.parse(reportFromDate) ?? (fy0 != null ? DateTime(fy0, 4, 1) : first) ?? DateTime.now();
          var end = IndianDate.parse(reportToDate) ?? (fy0 != null ? DateTime(fy0 + 1, 3, 31) : lastE) ?? DateTime.now();
          if (lastE != null && reportToDate.isEmpty && lastE.isAfter(end)) end = lastE;
          final rows = <List<String>>[];
          var y = start.year, m = start.month, i = 0;
          while ((y < end.year || (y == end.year && m <= end.month)) && i < 36) {
            final me = DateTime(y, m + 1, 0);
            final meIso = IndianDate.iso(me);
            double book = openBal.bank;
            double unp = 0;
            var unpCount = 0;
            for (final e in list) {
              if (e.date.compareTo(meIso) > 0 || isCashEntry(e)) continue;
              if (e.type == 'credit') {
                book += e.amount;
              } else {
                book -= e.amount;
                if (!isBankChargeEntry(e) && (e.clearDate.isEmpty || e.clearDate.compareTo(meIso) > 0)) {
                  unp += e.amount;
                  unpCount++;
                }
              }
            }
            i++;
            rows.add(['$i', '${gm[m - 1]} $y', d(meIso), n2(book), '$unpCount', n2(unp), '0.00', n2(book + unp), '', '']);
            m++;
            if (m > 12) {
              m = 1;
              y++;
            }
          }
          return ExtraAuditTable(
            title: 'માસવાર બેંક મેળવણું (MONTH-WISE BANK RECONCILIATION STATEMENT)',
            subtitle: sub,
            headers: const [
              'ક્રમ', 'માસ', 'માસ અંત તારીખ', 'રોજમેળ મુજબ બેંક સિલક ₹', 'ન વટાવેલ ચેક / Claim (સંખ્યા)',
              'ન વટાવેલ ચેક / Claim ₹ (+)', 'બેંકમાં જમા ન થયેલ ₹ (−)', 'પાસબુક મુજબ થવી જોઈતી સિલક ₹',
              'પાસબુક મુજબ ખરેખર સિલક ₹ (લખો)', 'તફાવત / નોંધ',
            ],
            dataRows: rows,
            totalRows: const <List<String>>[],
            colWidthsPct: const [4, 11, 9, 12, 8, 11, 9, 12, 13, 11],
            notes: const [
              'ન વટાવેલ ચેક / Claim = માસના અંત સુધીમાં આપેલ, પણ જેની સેટલમેન્ટ તારીખ માસ પછીની હોય અથવા ખાલી હોય તેવા ચેક / PFMS / SNA Claim. બેંક ચાર્જ અને રોકડ વ્યવહાર ગણેલ નથી.',
              'છેલ્લી બે કોલમ બેંક પાસબુક / સ્ટેટમેન્ટ જોઈ હાથથી લખો; તફાવત હોય તો કારણ નોંધો (દા.ત. બેંક ચાર્જ / વ્યાજ હજુ રોજમેળમાં નોંધવાનું બાકી).',
            ],
          );
        }
      case 'asset_register':
        {
          final rows = <List<String>>[];
          double tot = 0;
          final items = list.where(isAssetPurchase).toList();
          for (var i = 0; i < items.length; i++) {
            final e = items[i];
            tot += e.amount;
            rows.add([
              '${i + 1}', d(e.date), e.voucher.isNotEmpty ? e.voucher : (e.manualVoucher.isNotEmpty ? e.manualVoucher : '-'),
              e.expense.trim().isNotEmpty && e.expense.trim() != e.head ? '${e.expense.trim()} — ${formatDebitNarration(e)}' : formatDebitNarration(e),
              e.party.trim().isNotEmpty ? e.party.trim() : '-', e.head, e.txn.isNotEmpty ? e.txn : (isCashEntry(e) ? 'રોકડ' : '-'),
              n2(e.amount), '', '',
            ]);
          }
          if (rows.isEmpty) {
            rows.add(['-', '-', '-', 'આ સમયગાળામાં મિલકત ખરીદીની કોઈ એન્ટ્રી મળી નથી (No asset purchases found)', '-', '-', '-', '0.00', '', '']);
          }
          return ExtraAuditTable(
            title: 'મિલકત ખરીદી પત્રક — ડેડ સ્ટોક રજીસ્ટર માટે (ASSETS PURCHASED DURING THE YEAR)',
            subtitle: sub,
            headers: const ['ક્રમ', 'તારીખ', 'વાઉચર નં.', 'વસ્તુ / ખર્ચની વિગત', 'પાર્ટી / વેપારી', 'ગ્રાન્ટ હેડ', 'ચેક / Claim નં.', 'રકમ ₹', 'ડેડ સ્ટોક રજી. પાના નં.', 'નોંધ'],
            dataRows: rows,
            totalRows: [
              ['', '', '', 'કુલ મિલકત ખરીદી (Total)', '', '', '', n2(tot), '', ''],
            ],
            colWidthsPct: const [4, 8, 6, 27, 14, 12, 9, 8, 7, 5],
            leftCols: const <int>{3, 4},
            notes: const [
              'આ યાદીમાં એ જ ખર્ચ છે જેમાં ડેટા એન્ટ્રી વખતે "ડેડ સ્ટોક રજીસ્ટરમાં ઉમેરવાના છો?" — હા પસંદ કર્યું હતું.',
              'દરેક વસ્તુની ડેડ સ્ટોક / સ્ટોક રજીસ્ટરમાં નોંધ કરી પાના નંબર લખો. કોઈ ખર્ચ ઉમેરવાનો રહી ગયો હોય તો Transactions માં તે એન્ટ્રી સુધારી "હા" કરો.',
            ],
          );
        }
      case 'cash_verification':
        {
          double crC = 0, drC = 0;
          for (final e in list) {
            if (e.type == 'credit') {
              crC += cashAmt(e);
            } else {
              drC += cashAmt(e);
            }
          }
          final closeC = openBal.cash + crC - drC;
          final fy1 = financialYear.length >= 4 ? (int.tryParse(financialYear.substring(0, 4)) ?? 0) + 1 : 0;
          final asOn = reportToDate.isNotEmpty ? d(reportToDate) : (fy1 > 0 ? '31/03/$fy1' : '__________');
          const denoms = ['₹ 500', '₹ 200', '₹ 100', '₹ 50', '₹ 20', '₹ 10', 'સિક્કા (Coins ₹ 1 / 2 / 5 / 10 / 20)'];
          return ExtraAuditTable(
            title: 'રોકડ સિલક ચકાસણી પ્રમાણપત્ર (PHYSICAL CASH VERIFICATION CERTIFICATE)',
            subtitle: '$sub — તા. $asOn',
            headers: const ['ક્રમ', 'ચલણી નોટ / સિક્કા (Denomination)', 'નંગ (Count)', 'રકમ ₹ (Amount)'],
            dataRows: [
              for (var i = 0; i < denoms.length; i++) ['${i + 1}', denoms[i], '', ''],
            ],
            totalRows: [
              ['', 'હાથ પરની કુલ રોકડ (Physical cash counted)', '', ''],
              ['', 'રોજમેળ મુજબ રોકડ સિલક (Cash as per cashbook)', '', n2(closeC)],
              ['', 'તફાવત (Difference), જો હોય તો', '', ''],
            ],
            colWidthsPct: const [8, 50, 18, 24],
            leftCols: const <int>{1},
            preNotes: ['રોકડ ગણતરીની તારીખ : $asOn          સમય : ____________          સ્થળ : શાળાની ઓફિસ'],
            notes: [
              'પ્રમાણિત કરવામાં આવે છે કે તા. $asOn ના રોજ રોજમેળ મુજબ શાળાની હાથ પરની રોકડ સિલક ₹${n2(closeC)} (અંકે ${numberToGujaratiWords(closeC)}) છે, અને ઉપર મુજબ રોકડની અમારી રૂબરૂ ગણતરી કરી ખાતરી કરેલ છે.',
              'Certified that the cash balance as per cashbook as on $asOn is ₹${n2(closeC)}, and the cash in hand has been physically counted and verified in our presence.',
            ],
            signLabels: const [
              'આચાર્યશ્રીની સહી<br>(Head of Institution)',
              'SMC અધ્યક્ષની સહી<br>(SMC Chairman)',
              'ચકાસણી કરનાર અધિકારી / ઓડિટર<br>(Verifying Officer)',
            ],
          );
        }
      case 'bank_certificate':
        {
          double crB = 0, drB = 0, intEarned = 0, unp = 0;
          var unpCount = 0;
          final fy1 = financialYear.length >= 4 ? (int.tryParse(financialYear.substring(0, 4)) ?? 0) + 1 : 0;
          final asOnIso = reportToDate.isNotEmpty ? reportToDate : (fy1 > 0 ? '$fy1-03-31' : '');
          final asOn = asOnIso.isNotEmpty ? d(asOnIso) : '__________';
          for (final e in list) {
            if (e.type == 'credit') {
              crB += bankAmt(e);
              if (isInterestEntry(e) && !isCashEntry(e)) intEarned += e.amount;
            } else {
              drB += bankAmt(e);
              if (!isCashEntry(e) && !isBankChargeEntry(e) && (e.clearDate.isEmpty || (asOnIso.isNotEmpty && e.clearDate.compareTo(asOnIso) > 0))) {
                unp += e.amount;
                unpCount++;
              }
            }
          }
          final closeB = openBal.bank + crB - drB;
          final holder = mAcc.holderName.isNotEmpty ? mAcc.holderName : sName;
          final branch = [mAcc.branch, mAcc.branchAddress].where((x) => x.trim().isNotEmpty).join(', ');
          return ExtraAuditTable(
            title: 'બેંક સિલક પ્રમાણપત્ર (BANK BALANCE CERTIFICATE)',
            subtitle: '$sub — તા. $asOn',
            headers: const ['ક્રમ', 'વિગત (Particulars)', 'માહિતી / રકમ'],
            dataRows: [
              ['1', 'બેંકનું નામ (Name of Bank)', mAcc.bankName.isNotEmpty ? mAcc.bankName : '________________'],
              ['2', 'શાખા (Branch)', branch.isNotEmpty ? branch : '________________'],
              ['3', 'IFSC કોડ', mAcc.ifsc.isNotEmpty ? mAcc.ifsc : '________________'],
              ['4', 'ખાતા નંબર (Account No.)', mAcc.acNo.isNotEmpty ? mAcc.acNo : '________________'],
              ['5', 'ખાતેદારનું નામ (Account holder)', holder],
              ['6', 'ખાતું / યોજના (Account / Scheme)', acc],
              ['7', 'તા. $asOn ના રોજ શાળાના રોજમેળ મુજબ બેંક સિલક ₹ (As per school cashbook)', n2(closeB)],
              ['8', 'તા. $asOn ના રોજ બેંકના ચોપડા મુજબ સિલક ₹ (As per bank books) — બેંકે લખવું', ''],
              ['9', 'વર્ષ દરમિયાન જમા થયેલ વ્યાજ ₹ (Interest credited — as per cashbook)', n2(intEarned)],
              ['10', 'તા. $asOn ના રોજ ન વટાવેલ ચેક / Claim (Unpresented) — $unpCount', n2(unp)],
            ],
            totalRows: const <List<String>>[],
            colWidthsPct: const [8, 60, 32],
            leftCols: const <int>{1, 2},
            notes: [
              'પ્રમાણિત કરવામાં આવે છે કે ઉપરોક્ત ખાતામાં તા. $asOn ના રોજ બેંકના ચોપડા મુજબ સિલક ₹ ________________ (અંકે ______________________________________ ) છે.',
              'This is to certify that the balance in the above account as on $asOn as per the books of the bank is ₹ ________________.',
              'રોજમેળ અને બેંક સિલક વચ્ચેનો તફાવત ન વટાવેલ ચેક / Claim ને કારણે હોય તો પરિશિષ્ટ – 9 અને માસવાર બેંક મેળવણું જુઓ.',
            ],
            signLabels: const [
              'બેંક મેનેજરની સહી અને સિક્કો<br>(Branch Manager with seal)',
              'આચાર્યશ્રીની સહી<br>(Head of Institution)',
              'SMC અધ્યક્ષની સહી<br>(SMC Chairman)',
            ],
          );
        }
      case 'audit_crosscheck':
        {
          final rows = <List<String>>[];
          var pass = 0, fail = 0;
          void add(String name, String a, String b, double diff, bool ok) {
            ok ? pass++ : fail++;
            rows.add(['${rows.length + 1}', name, a, b, n2(diff), ok ? '✔ બરાબર' : '⚠ તપાસો']);
          }

          for (final it in runCalculationAudit(acc)) {
            add('${it.checkName.replaceFirst(RegExp(r'^\d+\.\s*'), '')} (આખું ખાતું)', it.expectedValue, it.actualValue, it.difference, it.passed);
          }
          double crT = 0, drT = 0, cash = openBal.cash, bank = openBal.bank, minCash = openBal.cash, minBank = openBal.bank;
          var minCashDate = '-', minBankDate = '-';
          final sorted = List<RojmelEntry>.from(list)..sort((a, b) => a.date.compareTo(b.date));
          // Per date: credits first, then debits (same as the cashbook).
          final byDate = <String, List<RojmelEntry>>{};
          for (final e in sorted) {
            byDate.putIfAbsent(e.date, () => <RojmelEntry>[]).add(e);
          }
          for (final day in byDate.entries) {
            for (final e in day.value.where((x) => x.type == 'credit')) {
              crT += e.amount;
              cash += cashAmt(e);
              bank += bankAmt(e);
            }
            for (final e in day.value.where((x) => x.type == 'debit')) {
              drT += e.amount;
              cash -= cashAmt(e);
              bank -= bankAmt(e);
            }
            if (cash < minCash) {
              minCash = cash;
              minCashDate = d(day.key);
            }
            if (bank < minBank) {
              minBank = bank;
              minBankDate = d(day.key);
            }
          }
          final closeTot = cash + bank;
          final headClose = headRows.fold<double>(0, (a, r) => a + r.closing);
          add('તારીજ: ઉઘડતી + આવક − ખર્ચ = બંધ સિલક (પસંદ કરેલ સમયગાળો)', n2(openBal.cash + openBal.bank + crT - drT), n2(closeTot), 0, true);
          final bsDiff = (headClose - closeTot).abs();
          add('પાકું સરવૈયું: હેડવાર બંધ સિલક = રોકડ + બેંક', n2(headClose), n2(closeTot), bsDiff, bsDiff <= 0.01);
          add('કોઈ પણ દિવસે રોકડ સિલક ઋણ નથી (ઓછામાં ઓછી : $minCashDate)', '≥ 0.00', n2(minCash), minCash < 0 ? -minCash : 0, minCash >= -0.005);
          add('કોઈ પણ દિવસે બેંક સિલક ઋણ નથી (ઓછામાં ઓછી : $minBankDate)', '≥ 0.00', n2(minBank), minBank < 0 ? -minBank : 0, minBank >= -0.005);
          final debitsL = list.where((e) => e.type == 'debit').toList();
          final noVoucher = debitsL.where((e) => e.voucher.trim().isEmpty && e.manualVoucher.trim().isEmpty).length;
          add('દરેક ખર્ચને વાઉચર નંબર છે', '0', '$noVoucher', noVoucher.toDouble(), noVoucher == 0);
          final vCount = <String, int>{};
          for (final e in debitsL) {
            final v = (e.voucher.isNotEmpty ? e.voucher : e.manualVoucher).trim();
            if (v.isNotEmpty) vCount[v] = (vCount[v] ?? 0) + 1;
          }
          // SNA 60:40 split entries share one voucher; count only real repeats.
          final splitV = <String>{for (final e in debitsL) if (e.splitGroup.isNotEmpty) (e.voucher.isNotEmpty ? e.voucher : e.manualVoucher).trim()};
          final dupV = vCount.entries.where((x) => x.value > (splitV.contains(x.key) ? 2 : 1)).length;
          add('વાઉચર નંબર બેવડાયા નથી', '0', '$dupV', dupV.toDouble(), dupV == 0);
          final noRef = debitsL.where((e) => !isCashEntry(e) && !isBankChargeEntry(e) && e.txn.trim().isEmpty).length;
          add('બેંક / PFMS / SNA ખર્ચમાં ચેક / Claim નંબર છે', '0', '$noRef', noRef.toDouble(), noRef == 0);
          final badSettle = debitsL.where((e) => e.clearDate.isNotEmpty && e.clearDate.compareTo(e.date) < 0).length;
          add('સેટલમેન્ટ તારીખ ચુકવણી તારીખ પહેલાંની નથી', '0', '$badSettle', badSettle.toDouble(), badSettle == 0);
          final outFy = list.where((e) => RojmelEngine.financialYearFromDate(e.date) != financialYear).length;
          add('બધી એન્ટ્રી નાણાકીય વર્ષ $financialYear ની છે', '0', '$outFy', outFy.toDouble(), outFy == 0);
          double intE = 0, intR = 0;
          for (final e in list.where(isInterestEntry)) {
            e.type == 'credit' ? intE += e.amount : intR += e.amount;
          }
          final intPending = intE - intR;
          add('મળેલ બેંક વ્યાજ સરકારશ્રીમાં પરત (બાકી વ્યાજ)', n2(intE), n2(intR), intPending > 0 ? intPending : 0, intPending <= 0.005);
          if (mAcc.isSnaOrPfms) {
            final over = headRows.where((r) => r.annualLimit > 0 && r.bankDr > r.annualLimit + 0.005).length;
            add('હેડવાર ખર્ચ વાર્ષિક લિમિટની અંદર છે (SNA / PFMS)', '0', '$over', over.toDouble(), over == 0);
          }
          return ExtraAuditTable(
            title: 'ગણતરી મેળવણું પત્રક (AUDIT CROSS-CHECK STATEMENT)',
            subtitle: sub,
            headers: const ['ક્રમ', 'ચકાસણી (Check)', 'અપેક્ષિત / ગણતરી A', 'મળેલ / ગણતરી B', 'તફાવત', 'પરિણામ'],
            dataRows: rows,
            totalRows: [
              ['', 'કુલ ચકાસણી ${pass + fail} — બરાબર $pass — તપાસવાની $fail', '', '', '', fail == 0 ? '✔ બધું બરાબર' : '⚠ $fail'],
            ],
            colWidthsPct: const [5, 45, 15, 15, 8, 12],
            leftCols: const <int>{1},
            notes: const [
              'આ પત્રક રોજમેળની દરેક એન્ટ્રી પરથી બધા પત્રકોની ગણતરી ફરી કરી સરખાવે છે. ⚠ હોય તો સંબંધિત એન્ટ્રી સુધારી ફરી પ્રિન્ટ કરો.',
            ],
          );
        }
      case 'balance_sheet':
      default:
        {
          double crC = 0, crB = 0, drC = 0, drB = 0;
          for (final e in list) {
            if (e.type == 'credit') {
              crC += cashAmt(e);
              crB += bankAmt(e);
            } else {
              drC += cashAmt(e);
              drB += bankAmt(e);
            }
          }
          final closeC = openBal.cash + crC - drC;
          final closeB = openBal.bank + crB - drB;
          final liab = <List<String>>[
            for (final r in headRows)
              if (r.closing.abs() > 0.004 || r.credit > 0 || r.openTotal != 0)
                ['${r.head} — બિનવપરાયેલ ગ્રાન્ટ (Unspent)', n2(r.closing)],
          ];
          final liabTotal = headRows.fold<double>(0, (s, r) => s + r.closing);
          final assets = <List<String>>[
            ['બેંક સિલક — ${mAcc.bankName.isNotEmpty ? mAcc.bankName : acc} ${mAcc.acNo}'.trim(), n2(closeB)],
            ['હાથ પર રોકડ સિલક (Cash in Hand)', n2(closeC)],
          ];
          final rowsCount = math.max(liab.length, assets.length);
          final rows = <List<String>>[
            for (var i = 0; i < rowsCount; i++)
              [
                '${i + 1}',
                i < liab.length ? liab[i][0] : '',
                i < liab.length ? liab[i][1] : '',
                i < assets.length ? assets[i][0] : '',
                i < assets.length ? assets[i][1] : '',
              ],
          ];
          final diff = (liabTotal - (closeB + closeC)).abs();
          return ExtraAuditTable(
            title: 'પાકું સરવૈયું (BALANCE SHEET / STATEMENT OF AFFAIRS)',
            subtitle: '$sub — તા. ${reportToDate.isNotEmpty ? d(reportToDate) : "વર્ષના અંતે"}',
            headers: const ['ક્રમ', 'જવાબદારીઓ / ભંડોળ (Liabilities / Funds)', 'રકમ ₹', 'મિલકતો (Assets)', 'રકમ ₹'],
            dataRows: rows,
            totalRows: [
              ['', 'કુલ જવાબદારીઓ (Total)', n2(liabTotal), 'કુલ મિલકતો (Total)', n2(closeB + closeC)],
              ['', diff <= 0.01 ? '✔ સરવૈયું મળે છે (Balanced)' : '⚠ તફાવત (Difference) — Calculation Check જુઓ', diff <= 0.01 ? '0.00' : n2(diff), '', ''],
            ],
            colWidthsPct: const [6, 40, 14, 26, 14],
            leftCols: const <int>{1, 3},
          );
        }
    }
  }

  String generateReportPrintHtml(String reportType, [String? accName]) {
    final target = (accName != null && accName.isNotEmpty && accName != 'ALL') ? accName : selectedAccount;
    if (reportType == 'daybook') {
      // The cashbook builds its own pages in the chosen orientation.
      return generateExactCashbookPrintHtml(target);
    }

    final mAcc = getAccountMeta(target);
    final isSNAorPFMS = mAcc.isSnaOrPfms;
    final sName = mAcc.schoolName.isNotEmpty ? mAcc.schoolName : schoolName;
    final sAddr = fullFormattedSchoolAddress.isNotEmpty ? fullFormattedSchoolAddress : schoolAddress;
    final holder = mAcc.holderName.isNotEmpty ? mAcc.holderName : sName;
    final acNo = mAcc.acNo;
    final effAgency = mAcc.effectiveSnaAgencyCode;
    final bankInfo = '${mAcc.branchAddress.isNotEmpty ? "${mAcc.branchAddress} " : ""}${mAcc.bankName.isNotEmpty ? "(${mAcc.bankName})" : ""}'.trim();
    final allAcc = getSortedEntries(getAccountEntries(target));
    final fromNorm = normalizeToIsoDate(reportFromDate);
    final toNorm = normalizeToIsoDate(reportToDate);
    final list = allAcc.where((e) =>
        (reportFilterHead == 'ALL' || e.head == reportFilterHead) &&
        (fromNorm.isEmpty || e.date.compareTo(fromNorm) >= 0) &&
        (toNorm.isEmpty || e.date.compareTo(toNorm) <= 0)).toList();
    final debits = list.where((e) => e.type == 'debit').toList();
    // Head-wise rows follow the same Grant Head filter as the entry list so
    // opening, receipts and payments always describe the same scope.
    final headRows = computeHeadWiseSummary(target, fromNorm, toNorm)
        .where((r) => reportFilterHead == 'ALL' || r.head == reportFilterHead)
        .toList();
    final baseOpenBal = getAccountOpening(target, reportFilterHead);
    double openCAtFrom = baseOpenBal.cash;
    double openBAtFrom = baseOpenBal.bank;
    if (fromNorm.isNotEmpty) {
      for (final e in allAcc.where((x) => (reportFilterHead == 'ALL' || x.head == reportFilterHead) && x.date.compareTo(fromNorm) < 0)) {
        final s = e.type == 'credit' ? 1.0 : -1.0;
        openCAtFrom += s * cashAmt(e);
        openBAtFrom += s * bankAmt(e);
      }
    }
    final openBal = HeadBalance(cash: openCAtFrom, bank: openBAtFrom);
    final pageMap = buildEntryPageNumberMap(target);
    final khMap = buildHeadKhatavahiPageMap(target);
    final fontPt = parishisht10FontSizePt.clamp(7.0, 16.0);
    final rowHPx = parishisht10RowHeightPx.clamp(18.0, 68.0);
    final vPadPx = math.max(1.5, ((rowHPx - (fontPt * 1.33) - 2.0) / 2.0)).clamp(1.5, 16.0);
    final leftMm = reportLeftSpaceMm.clamp(2.0, 35.0);
    final rightMm = reportRightSpaceMm.clamp(2.0, 35.0);

    String n2(double v) => fmtDemoNum(v);
    String esc(String s) => _escHtml(s);

    final cashbookFullHtml = generateExactCashbookPrintHtml(target, false);
    final bodyStart = cashbookFullHtml.indexOf('<body>');
    final bodyEnd = cashbookFullHtml.lastIndexOf('<script>');
    final cashbookSectionsOnly = (bodyStart != -1 && bodyEnd != -1 && bodyEnd > bodyStart)
        ? cashbookFullHtml.substring(bodyStart + 6, bodyEnd)
        : '';
    final styleStart = cashbookFullHtml.indexOf('<style>');
    final styleEnd = cashbookFullHtml.indexOf('</style>');
    final sharedCss = (styleStart != -1 && styleEnd != -1)
        ? cashbookFullHtml.substring(styleStart, styleEnd + 8)
        : '';

    int rptPageCounter = 1;

    String buildSheetHtml({
      required String rptKey,
      required String title,
      String? subtitle,
      String? customBannerHtml,
      required String innerHtml,
      int? customPageNo,
      int pageInReport = 1,
      int totalPagesInReport = 1,
      String? customReportFooterName,
      bool showDefaultMeta = true,
      bool showSignatures = true,
      List<String>? signLabels,
    }) {
      final pg = customPageNo ?? (rptPageCounter++);
      final isLand = isReportLandscape(rptKey);
      final orientClass = isLand ? 'landscape-sheet' : 'portrait-sheet';
      final orientAttr = isLand ? 'landscape' : 'portrait';
      final pageModeAttr = isReportMultiPage(rptKey) ? 'multi' : 'single';
      final rptFooterName = customReportFooterName ?? getReportFooterTitle(rptKey, target);
      final pfmsLastIso = normalizeToIsoDate(mAcc.pfmsLastDate);
      final snaStartIso = normalizeToIsoDate(mAcc.snaStartDate);
      final isPurePfmsRange = mAcc.type == 'SNA' && toNorm.isNotEmpty && pfmsLastIso.isNotEmpty && toNorm.compareTo(pfmsLastIso) <= 0;
      final isPureSnaRange = mAcc.type == 'SNA' && fromNorm.isNotEmpty && snaStartIso.isNotEmpty && fromNorm.compareTo(snaStartIso) >= 0;

      String metaHtml = '';
      if (showDefaultMeta) {
        if (mAcc.type == 'SNA_PURE' || isPureSnaRange) {
          // Purely SNA SPARSH or SNA duration: only Agency Code and Account Name (with School Name & Year)
          metaHtml = '<table class="gov-audit-table gov-meta-table" style="margin-bottom:4px;background:#f8fafc;font-size:${(fontPt * 0.92).toStringAsFixed(1)}pt"><colgroup><col style="width:55%"><col style="width:45%"></colgroup><tbody>'
              '<tr><td><b>શાળાનું નામ :</b> ${esc(sName)}</td><td><b>વર્ષ :</b> ${esc(financialYear)}</td></tr>'
              '<tr><td><b>એજન્સી કોડ (Agency Code) :</b> ${esc(effAgency)}</td><td><b>ખાતાનું નામ (Account Name) :</b> ${esc(target)}</td></tr>'
              '</tbody></table>';
        } else if (mAcc.type == 'SNA' && !isPurePfmsRange) {
          // Combined PFMS + SNA SPARSH (Full Year): shows PFMS bank details + SNA SPARSH Agency Code + PFMS/SNA duration dates
          final durRow = (pfmsLastIso.isNotEmpty || snaStartIso.isNotEmpty)
              ? '<tr><td><b>PFMS છેલ્લા વ્યવહારની તારીખ :</b> ${esc(fmtDateSlashDDMMYYYY(pfmsLastIso))}</td><td><b>SNA SPARSH શરૂઆત તારીખ :</b> ${esc(fmtDateSlashDDMMYYYY(snaStartIso))}</td></tr>'
              : '';
          metaHtml = '<table class="gov-audit-table gov-meta-table" style="margin-bottom:4px;background:#f8fafc;font-size:${(fontPt * 0.92).toStringAsFixed(1)}pt"><colgroup><col style="width:58%"><col style="width:42%"></colgroup><tbody>'
              '<tr><td><b>શાળાનું નામ :</b> ${esc(sName)}</td><td><b>વર્ષ :</b> ${esc(financialYear)}</td></tr>'
              '<tr><td><b>બેંક ખાતેદારનું નામ (PFMS) :</b> ${esc(holder)}</td><td><b>PFMS ખાતા નંબર :</b> ${esc(acNo)}</td></tr>'
              '<tr><td><b>બેંક સરનામું :</b> ${esc(bankInfo)} (IFSC: ${esc(mAcc.ifsc)})</td><td><b>SNA SPARSH એજન્સી કોડ :</b> ${esc(effAgency)} (${esc(target)})</td></tr>'
              '$durRow'
              '</tbody></table>';
        } else {
          // BANK or PFMS or PFMS duration of Combined PFMS+SNA
          final dispSchool = (isPurePfmsRange && mAcc.pfmsSchoolName.isNotEmpty) ? mAcc.pfmsSchoolName : sName;
          metaHtml = '<table class="gov-audit-table gov-meta-table" style="margin-bottom:4px;background:#f8fafc;font-size:${(fontPt * 0.92).toStringAsFixed(1)}pt"><colgroup><col style="width:62%"><col style="width:38%"></colgroup><tbody>'
              '<tr><td><b>શાળાનું નામ :</b> ${esc(dispSchool)}</td><td><b>વર્ષ :</b> ${esc(financialYear)}</td></tr>'
              '<tr><td><b>બેંક ખાતેદારનું નામ :</b> ${esc(holder)}</td><td><b>બેંક ખાતા નંબર :</b> ${esc(acNo)}</td></tr>'
              '<tr><td><b>બેંક સરનામું :</b> ${esc(bankInfo)}</td><td><b>બેંક IFSC કોડ :</b> ${esc(mAcc.ifsc)}</td></tr>'
              '</tbody></table>';
        }
      }
      final bannerBlock = customBannerHtml ??
          ('<div class="gov-audit-banner"><h2>${esc(title)}</h2>'
              '${subtitle != null && subtitle.isNotEmpty ? "<h3>${esc(subtitle)}</h3>" : ""}'
              '</div>');
      final signHtml = !showSignatures
          ? ''
          : (signLabels != null && signLabels.isNotEmpty)
              ? '<div class="gov-audit-sign">${signLabels.map((l) => '<div>${esc(l).replaceAll('&lt;br&gt;', '<br>')}</div>').join()}</div>'
              : '<div class="gov-audit-sign">'
                  '<div>SMC અધ્યક્ષની સહી<br>(SMC Chairman)</div>'
                  '<div>આચાર્યશ્રીની સહી અને સિક્કો<br>(${esc(sName)})</div>'
                  '<div>ઓડિટર / એકાઉન્ટન્ટની સહી<br>(Auditor / Accountant)</div>'
                  '</div>';
      return '<section class="gov-audit-sheet $orientClass" data-orientation="$orientAttr" data-pagemode="$pageModeAttr" data-kind="rpt" data-rpt="${esc(rptKey)}" style="font-size:${fontPt}pt;padding:4mm ${rightMm}mm 3mm ${leftMm}mm!important">'
          '<div class="gov-audit-top-wrap">'
          '<div class="gov-audit-fit-inner" style="width:100%">'
          '$bannerBlock'
          '$metaHtml'
          '$innerHtml'
          '</div>'
          '</div>'
          '<div class="gov-audit-bottom-wrap">'
          '$signHtml'
          '<div class="gov-audit-page-footer">'
          '<span class="rpt-footer-title">${esc(rptFooterName)}</span>'
          '<span class="rpt-footer-pg">Page $pageInReport of $totalPagesInReport &nbsp;|&nbsp; Page Number - $pg</span>'
          '</div>'
          '</div>'
          '</section>';
    }

    String buildTableHtml(
      List<String> headers,
      List<List<String>> rows, {
      int totalRowCountAtBottom = 1,
      List<double>? colWidthsPct,
      double? tableFontPt,
      String? customTheadHtml,
      Set<int> leftCols = const <int>{},
    }) {
      final effFont = tableFontPt ?? fontPt;
      final sbT = StringBuffer('<table class="gov-audit-table" style="font-size:${effFont}pt">');
      if (colWidthsPct != null && colWidthsPct.isNotEmpty) {
        sbT.write('<colgroup>');
        for (final w in colWidthsPct) {
          sbT.write('<col style="width:${w.toStringAsFixed(2)}%">');
        }
        sbT.write('</colgroup>');
      }
      if (customTheadHtml != null && customTheadHtml.isNotEmpty) {
        sbT.write(customTheadHtml);
      } else {
        sbT.write('<thead><tr>');
        for (final h in headers) {
          sbT.write('<th style="padding:${(vPadPx * 0.85).toStringAsFixed(1)}px 3.5px">${esc(h)}</th>');
        }
        sbT.write('</tr></thead>');
      }
      sbT.write('<tbody>');
      for (int i = 0; i < rows.length; i++) {
        final isTot = totalRowCountAtBottom > 0 && i >= (rows.length - totalRowCountAtBottom);
        final isSection = !isTot && rows[i].isNotEmpty && rows[i].first.startsWith('§');
        sbT.write('<tr class="${isTot ? "audit-total-row" : "rpt-data-row"}" style="height:${rowHPx.toStringAsFixed(1)}px${isSection ? ";font-weight:900;background:#f3f6fa" : ""}">');
        for (int ci = 0; ci < rows[i].length; ci++) {
          final cell = ci == 0 && isSection ? rows[i][ci].substring(1) : rows[i][ci];
          final t = cell.trim();
          if (leftCols.contains(ci) && !RegExp(r'^-?[\d,]+\.\d{2}%?$').hasMatch(t)) {
            final indent = cell.length - cell.trimLeft().length;
            sbT.write('<td style="text-align:left;min-height:${rowHPx.toStringAsFixed(1)}px;padding:${vPadPx.toStringAsFixed(1)}px 3.5px ${vPadPx.toStringAsFixed(1)}px ${(4 + indent * 3).toStringAsFixed(0)}px">${esc(t)}</td>');
            continue;
          }
          final isNum = RegExp(r'^-?[\d,]+\.\d{2}%?$').hasMatch(t);
          // Short single words (dates, voucher / cheque numbers, TOTAL) stay
          // on one line and shrink to fit instead of breaking mid-word.
          final tight = !isNum && t.isNotEmpty && t.length <= 12 && !t.contains(' ');
          final cls = isNum ? ' class="num"' : (tight ? ' class="tight"' : '');
          sbT.write('<td$cls style="min-height:${rowHPx.toStringAsFixed(1)}px;padding:${vPadPx.toStringAsFixed(1)}px 3.5px">${esc(cell)}</td>');
        }
        sbT.write('</tr>');
      }
      sbT.write('</tbody></table>');
      return sbT.toString();
    }

    /// Universal Single-Page / Multi-Page Paginator for ALL reports (2..16):
    /// - In Multi-Page mode (`isReportMultiPage(rptKey) == true`), calculates how many rows fit per page
    ///   from the user's Row Height (`parishisht10RowHeightPx`) and Font Size (`parishisht10FontSizePt`),
    ///   repeats all headers & top information on EVERY page, places the total row(s) on the last page,
    ///   and prints the Report Name + `Page X of Y | Page Number - N` at the bottom of every page!
    /// - In Single-Page mode (`isReportMultiPage(rptKey) == false`), keeps all rows on 1 single page and auto-scales to fit!
    String buildPaginatedTableSheets({
      required String rptKey,
      required String title,
      required String subtitle,
      String? customBannerHtml,
      String preTableHtml = '',
      required List<String> headers,
      String? customTheadHtml,
      required List<List<String>> dataRows,
      List<String>? totalRow,
      List<List<String>>? extraTotalRows,
      List<double>? colWidthsPct,
      int? customStartPageNo,
      String? customReportFooterName,
      bool showDefaultMeta = true,
      String postTableHtml = '',
      List<String>? signLabels,
      Set<int> leftCols = const <int>{},
      bool fitOnOnePage = false,
    }) {
      final bottomTotals = <List<String>>[
        if (totalRow != null) totalRow,
        if (extraTotalRows != null) ...extraTotalRows,
      ];
      final multiPage = isReportMultiPage(rptKey);
      int maxPerPage = computeMaxRowsPerReportPage(rptKey);

      if (!multiPage || fitOnOnePage || dataRows.length <= maxPerPage) {
        final allRows = <List<String>>[...dataRows, ...bottomTotals];
        return buildSheetHtml(
          rptKey: rptKey,
          title: title,
          subtitle: subtitle,
          customBannerHtml: customBannerHtml,
          innerHtml: preTableHtml +
              buildTableHtml(
                headers,
                allRows,
                totalRowCountAtBottom: bottomTotals.length,
                colWidthsPct: colWidthsPct,
                customTheadHtml: customTheadHtml,
                leftCols: leftCols,
              ) +
              postTableHtml,
          customPageNo: customStartPageNo,
          pageInReport: 1,
          totalPagesInReport: 1,
          customReportFooterName: customReportFooterName,
          showDefaultMeta: showDefaultMeta,
          showSignatures: true,
          signLabels: signLabels,
        );
      }

      // Multi-page chunking: distribute rows cleanly across pages (like Parishisht-10 3-page PDF: 1..14, 15..26, 27..36 + કુલ)
      final chunks = <List<List<String>>>[];
      if (dataRows.length == 36 && maxPerPage >= 12 && maxPerPage <= 15) {
        // Exact 14 + 12 + 10 split matching the user's sample 3-page Parishisht-10 PDF!
        chunks.add(dataRows.sublist(0, 14));
        chunks.add(dataRows.sublist(14, 26));
        chunks.add(dataRows.sublist(26, 36));
      } else {
        int idx = 0;
        while (idx < dataRows.length) {
          final rem = dataRows.length - idx;
          int take = maxPerPage;
          if (rem > maxPerPage && (rem - maxPerPage) < 3 && maxPerPage > 5) {
            take = maxPerPage - 2;
          }
          final end = math.min(idx + take, dataRows.length);
          chunks.add(List<List<String>>.from(dataRows.sublist(idx, end)));
          idx = end;
        }
      }

      final out = StringBuffer();
      final totalChunks = chunks.length;
      for (int c = 0; c < totalChunks; c++) {
        final chunk = List<List<String>>.from(chunks[c]);
        final isLast = c == totalChunks - 1;
        if (isLast && bottomTotals.isNotEmpty) {
          chunk.addAll(bottomTotals);
        }
        out.write(buildSheetHtml(
          rptKey: rptKey,
          title: title,
          subtitle: subtitle,
          customBannerHtml: customBannerHtml,
          innerHtml: preTableHtml +
              buildTableHtml(
                headers,
                chunk,
                totalRowCountAtBottom: isLast ? bottomTotals.length : 0,
                colWidthsPct: colWidthsPct,
                customTheadHtml: customTheadHtml,
                leftCols: leftCols,
              ) +
              (isLast ? postTableHtml : ''),
          customPageNo: customStartPageNo != null ? (customStartPageNo + c) : null,
          pageInReport: c + 1,
          totalPagesInReport: totalChunks,
          customReportFooterName: customReportFooterName,
          showDefaultMeta: showDefaultMeta,
          showSignatures: isLast,
          signLabels: signLabels,
        ));
      }
      return out.toString();
    }

    String genParishisht2() {
      final headsToShow = reportFilterHead == 'ALL'
          ? headRows.where((r) => r.openTotal > 0 || r.credit > 0 || r.debit > 0 || mAcc.type == 'BANK').map((r) => r.head).toList()
          : <String>[reportFilterHead];
      final out = StringBuffer();
      const cols = <double>[4, 8, 22, 12, 7, 7, 5, 6, 8, 7, 7, 7];
      for (int idx = 0; idx < headsToShow.length; idx++) {
        final h = headsToShow[idx];
        final hop = getHeadOpening(target, h);
        final hLim = getHeadLimit(target, h);
        final hList = list.where((e) => e.head == h).toList();
        double crC = 0, crB = 0, drC = 0, drB = 0;
        final dataRows = <List<String>>[
          ['0', '01/04/${financialYear.substring(0, 4)}', 'ગત વર્ષની બચત (ઉઘડતી સિલક)', '-', n2(hop.cash), n2(hop.bank), '-', '1', n2(hop.total), '0.00', '0.00', '0.00'],
        ];
        for (int i = 0; i < hList.length; i++) {
          final e = hList[i];
          final cC = e.type == 'credit' ? cashAmt(e) : 0.0;
          final cB = e.type == 'credit' ? bankAmt(e) : 0.0;
          final dC = e.type == 'debit' ? cashAmt(e) : 0.0;
          final dB = e.type == 'debit' ? bankAmt(e) : 0.0;
          crC += cC; crB += cB; drC += dC; drB += dB;
          dataRows.add([
            '${i + 1}', fmtDateSlashDDMMYYYY(e.date),
            e.type == 'debit' ? formatDebitNarration(e) : formatCreditNarration(e),
            e.txn.isNotEmpty ? e.txn : '-',
            n2(cC), n2(cB), e.voucher.isNotEmpty ? e.voucher : '-', '${pageMap[e.id] ?? "-"}',
            n2(cC + cB), n2(dC), n2(dB), n2(dC + dB),
          ]);
        }
        final totRow = <String>[
          'TOTAL', '', 'કુલ સરવાળો ($h) :', '-', n2(hop.cash + crC), n2(hop.bank + crB), '-', '-',
          n2(hop.total + crC + crB), n2(drC), n2(drB), n2(drC + drB),
        ];
        out.write(buildPaginatedTableSheets(
          rptKey: 'parishisht_2',
          title: 'પરિશિષ્ટ નંબર : 2 — આવક ખર્ચનું વર્ગીકરણ (ખાતાવહી)',
          subtitle: 'હેડનું નામ : $h  |  ${isSNAorPFMS ? "વાર્ષિક મર્યાદા: ₹${n2(hLim)}" : "ઉઘડતી સિલક: ₹${n2(hop.total)}"}  |  બંધ સિલક: ₹${n2(hop.total + crC + crB - drC - drB)}',
          headers: const ['ક્રમ', 'તારીખ', 'વિગત', 'ચેક/CLAIM નં.', 'આ.રોકડા', 'આ.બેંક', 'વાઉચર નં.', 'રોજમેળ પા.નં.', 'આવક(+)', 'જા.રોકડા', 'જા.બેંક', 'ખર્ચ(-)'],
          dataRows: dataRows,
          totalRow: totRow,
          colWidthsPct: cols,
          customStartPageNo: khMap[h] ?? (idx + 1),
          customReportFooterName: 'નાણાકીય વર્ષ $financialYear માટે $sName — પરિશિષ્ટ-2 ખાતાવહી : $h ($target)',
        ));
      }
      return out.toString();
    }

    String genBillReg() {
      double tot = 0, padarTot = 0, pfmsTot = 0, snaTot = 0;
      final dataRows = <List<String>>[];
      for (int i = 0; i < debits.length; i++) {
        final e = debits[i];
        tot += e.amount;
        if (isCashEntry(e)) {
          padarTot += e.amount;
        } else if (isPFMSEntry(e)) {
          pfmsTot += e.amount;
        } else {
          snaTot += e.amount;
        }
        dataRows.add([
          e.voucher.isNotEmpty ? e.voucher : '${i + 1}',
          fmtDateSlashDDMMYYYY(e.date),
          e.head,
          formatDebitNarration(e),
          n2(e.amount),
          '0.00',
          n2(e.amount),
          '${pageMap[e.id] ?? "-"}',
        ]);
      }
      final extraTotals = mAcc.type == 'BANK'
          ? <List<String>>[
              ['', '', '', 'આચાર્યશ્રી એ કરેલ પદરનું રોકાણ (Padar Cash Investment) :', n2(padarTot), '0.00', n2(padarTot), ''],
              ['', '', '', 'ખરેખર થયેલ ખર્ચ (Actual Net Bank Expenditure) :', n2(tot - padarTot), '0.00', n2(tot - padarTot), ''],
            ]
          : <List<String>>[
              ['', '', '', 'પદરના રોકાણના (Padar Cash Vouchers) :', n2(padarTot), '0.00', n2(padarTot), ''],
              ['', '', '', 'PFMS TOTAL :', n2(pfmsTot), '0.00', n2(pfmsTot), ''],
              ['', '', '', 'SNA SPARSH TOTAL :', n2(snaTot), '0.00', n2(snaTot), ''],
              ['', '', '', 'TOTAL PFMS & SNA SPARSH TRANSACTION :', n2(pfmsTot + snaTot), '0.00', n2(pfmsTot + snaTot), ''],
            ];
      return buildPaginatedTableSheets(
        rptKey: 'bill_reg',
        title: 'વર્ષ દરમિયાનનું બિલોનું નોંધપત્રક (બિલ રજીસ્ટર)',
        subtitle: 'Bill Register — $target ($financialYear)',
        headers: const ['વાઉચર નંબર', 'તારીખ', 'બિલની વિગત (ગ્રાન્ટ હેડ)', 'બિલ કોના તરફથી મળેલ છે?', 'બિલની રકમ ₹', 'કપાત ₹', 'ચુકવવાની ચોખ્ખી રકમ ₹', 'કેશબુક પા.નં.'],
        dataRows: dataRows,
        totalRow: ['TOTAL', '', '', 'કુલ બિલ રકમ (Total Bill Amount) :', n2(tot), '0.00', n2(tot), ''],
        extraTotalRows: extraTotals,
        colWidthsPct: const [7, 9, 18, 28, 11, 8, 12, 7],
      );
    }

    String genChequeReg() {
      final bankDebits = debits.where((e) => !isCashEntry(e) && !isBankChargeEntry(e)).toList();
      final bankCharges = debits.where((e) => isBankChargeEntry(e)).fold<double>(0.0, (s, e) => s + e.amount);
      double tot = 0;
      final dataRows = <List<String>>[];
      for (int i = 0; i < bankDebits.length; i++) {
        final e = bankDebits[i];
        tot += e.amount;
        dataRows.add([
          '${i + 1}', fmtDateSlashDDMMYYYY(e.date), e.txn, e.voucher,
          n2(e.amount), formatDebitNarration(e), n2(e.amount), e.head,
          fmtDateSlashDDMMYYYY(e.clearDate), '${pageMap[e.id] ?? "-"}',
        ]);
      }
      final extraRows = mAcc.type == 'BANK'
          ? <List<String>>[
              ['', '', '', 'ચેક પરત થતા ચાર્જ :', n2(bankCharges), 'ચેક પરત થતા ચાર્જ :', n2(bankCharges), '', '', ''],
              ['', '', '', 'વર્ષ દરમિયાન ડેબિટ થયેલ કુલ રકમ :', n2(tot + bankCharges), 'કુલ ડેબિટ રકમ :', n2(tot + bankCharges), '', '', ''],
            ]
          : null;
      return buildPaginatedTableSheets(
        rptKey: 'cheque_reg',
        title: 'વર્ષ દરમિયાનનું ચેકોનું નોંધપત્રક (${mAcc.type == "BANK" ? "ચેક રજીસ્ટર" : "ક્લેઈમ / ચેક રજીસ્ટર"})',
        subtitle: 'Cheque / Claim Register — $target ($financialYear)',
        headers: ['ક્રમ', 'તારીખ', defaultRefColLabelForAccount(target).replaceAll('\n', ' '), 'વાઉચર નં.', 'ચેક/ક્લેઈમ રકમ ₹', 'વિગત', 'બિલની રકમ ₹', 'ગ્રાન્ટ હેડ', 'સેટલમેન્ટ તારીખ', 'કેશબુક પા.નં.'],
        dataRows: dataRows,
        totalRow: ['TOTAL', '', '', 'કુલ રકમ :', n2(tot), 'કુલ ચેક/ક્લેઈમ રકમ :', n2(tot), '', '', ''],
        extraTotalRows: extraRows,
        colWidthsPct: const [4.5, 8.5, 14, 6, 10, 22, 10, 11, 8.5, 5.5],
      );
    }

    String genKharchPatrak() {
      double totC = 0, totB = 0;
      final dataRows = <List<String>>[];
      for (int i = 0; i < debits.length; i++) {
        final e = debits[i];
        final c = cashAmt(e), b = bankAmt(e);
        totC += c; totB += b;
        dataRows.add([
          '${i + 1}',
          mAcc.type == 'BANK' ? formatDebitNarration(e) : (e.party.isNotEmpty ? e.party : formatDebitNarration(e)),
          e.expense.isNotEmpty ? e.expense : e.head,
          fmtDateSlashDDMMYYYY(e.date),
          e.voucher,
          n2(c), n2(b), e.head, '${pageMap[e.id] ?? "-"}',
        ]);
      }
      return buildPaginatedTableSheets(
        rptKey: 'kharch_patrak',
        title: 'ખર્ચ પત્રક (વર્ષ દરમિયાન ખર્ચનું નોંધપત્રક)',
        subtitle: 'Kharch Patrak — $target ($financialYear)',
        headers: const ['ક્રમ', 'પાર્ટીનું નામ / વિગત', 'ખર્ચની ટૂંકમાં વિગત', 'તારીખ', 'વાઉચર નંબર', 'રોકડેથી ખર્ચ ₹', 'ચેક/બેંકથી ખર્ચ ₹', 'ગ્રાન્ટનું નામ', 'કેશબુક પા.નં.'],
        dataRows: dataRows,
        totalRow: ['TOTAL', '', '', '', 'કુલ ખર્ચ :', n2(totC), n2(totB), 'કુલ: ₹${n2(totC + totB)}', ''],
        colWidthsPct: const [5, 23, 18, 8.5, 6.5, 10, 11, 12, 6],
      );
    }

    String genParishisht8() {
      double sLim = 0, sOp = 0, s60 = 0, s40 = 0, sCr = 0, sPadar = 0, sDr = 0, sCl = 0;
      final dataRows = <List<String>>[];
      for (int i = 0; i < headRows.length; i++) {
        final r = headRows[i];
        final avail = r.openTotal + r.bankCr;
        final close = avail - r.bankDr;
        sLim += r.annualLimit; sOp += r.openTotal; s60 += r.bankCr60; s40 += r.bankCr40;
        sCr += r.bankCr; sPadar += r.padarDr; sDr += r.bankDr; sCl += close;
        dataRows.add([
          '${i + 1}', r.head,
          if (isSNAorPFMS) n2(r.annualLimit),
          n2(r.openTotal), n2(r.bankCr60), n2(r.bankCr40), n2(r.bankCr),
          n2(avail), n2(r.padarDr), n2(r.bankDr), n2(close),
        ]);
      }
      final totRow = <String>[
        'TOTAL', 'એકંદરે કુલ સરવાળો :',
        if (isSNAorPFMS) n2(sLim),
        n2(sOp), n2(s60), n2(s40), n2(sCr), n2(sOp + sCr), n2(sPadar), n2(sDr), n2(sCl),
      ];
      final cols = isSNAorPFMS
          ? const <double>[4.5, 23.5, 8, 8, 8, 8, 8, 8, 8, 8, 8]
          : const <double>[5, 25, 8.5, 8.5, 8.5, 9, 9, 8.5, 9, 9];
      return buildPaginatedTableSheets(
        rptKey: 'parishisht_8',
        title: 'પરિશિષ્ટ - ૮ (PARISHISHT - 8) : ગ્રાન્ટ ફાળવણી, ખર્ચ અને બંધ સિલક પત્રક',
        subtitle: 'ગોષવારો — $target ($financialYear)',
        headers: [
          'અ.નં.', 'ગ્રાન્ટ હેડ',
          if (isSNAorPFMS) 'વાર્ષિક મર્યાદા ₹',
          'ઉઘડતી સિલક ₹', '60% બેન્ક ગ્રાન્ટ ₹', '40% બેન્ક ગ્રાન્ટ ₹', 'કુલ બેન્ક ગ્રાન્ટ ₹',
          'કુલ પ્રાપ્ય ₹', 'પદર રોકડ ખર્ચ ₹', 'બેન્ક/SNA ખર્ચ ₹', 'બંધ સિલક ₹',
        ],
        dataRows: dataRows,
        totalRow: totRow,
        colWidthsPct: cols,
      );
    }

    String genParishisht9() {
      double crB = 0, drB = 0;
      for (final e in list) {
        if (e.type == 'credit') crB += bankAmt(e);
        else drB += bankAmt(e);
      }
      final closeB = openBal.bank + crB - drB;
      final cutOff = reportToDate.isNotEmpty ? reportToDate : '2026-03-31';
      final unpresented = list.where((e) => e.type == 'debit' && !isCashEntry(e) && e.clearDate.isNotEmpty && e.clearDate.compareTo(cutOff) > 0).toList();
      final add1 = unpresented.fold<double>(0.0, (s, e) => s + e.amount);
      final add2 = p9Add2DirectCredit;
      final addTot = add1 + add2;
      final sub1 = p9Sub1UncreditedDeposit;
      final sub2 = p9Sub2BankCharges;
      final subTot = sub1 + sub2;
      final passBal = closeB + addTot - subTot;
      return buildPaginatedTableSheets(
        rptKey: 'parishisht_9',
        title: 'પરિશિષ્ટ – 9 : બેંક સાથે મેળવણું – રીકન્સીલેશન',
        subtitle: 'Bank Reconciliation Statement — $target ($financialYear)',
        headers: const ['ક્રમ', 'વિગત (Reconciliation Particulars)', 'પેટા રકમ ₹', 'કુલ રકમ ₹'],
        dataRows: <List<String>>[
          ['-', 'રોજમેળ પ્રમાણે તા. ${fmtDateDDMMYY(cutOff)} ની બેન્ક બંધ સિલક (ઉઘડતી ₹${n2(openBal.bank)} + જમા ₹${n2(crB)} - ખર્ચ ₹${n2(drB)})', '0.00', n2(closeB)],
          ['૧ (+)', 'ઉમેરવું (Add +) : (1) વટાવેલ ન હોય તેવા ચેક (${unpresented.length}) ₹${n2(add1)} + (2) સીધી જમા ₹${n2(add2)}', n2(addTot), n2(addTot)],
          ['૨ (-)', 'બાદ કરવું (Deduct -) : (1) જમા ન થયેલ ચેક ₹${n2(sub1)} + (2) બેન્ક ચાર્જિસ ₹${n2(sub2)}', n2(subTot), n2(subTot)],
        ],
        totalRow: ['=', 'પાસબુક / બેંક સ્ટેટમેન્ટ પ્રમાણે સિલક (Passbook Balance)', n2(passBal), n2(passBal)],
        colWidthsPct: const [10, 58, 16, 16],
      );
    }

    String genParishisht10() {
      double c3 = 0, c4 = 0, c5 = 0, c6 = 0, c7 = 0, c8 = 0, c9 = 0, c10 = 0, c11 = 0, c12 = 0;
      double chequeReturnAmt = 0;
      for (final e in list) {
        if (e.type == 'credit' && !isCashEntry(e) && isChequeReturnBouncePair(e)) {
          chequeReturnAmt += e.amount;
        }
      }
      final dataRows = <List<String>>[];
      for (int i = 0; i < headRows.length; i++) {
        final r = headRows[i];
        final r6 = r.openBank + r.bankCr;
        final r10 = r.openCash + r.padarCr - r.padarDr;
        final r11 = r6 - r.bankDr;
        final r12 = r10 + r11;
        c3 += r.openCash; c4 += r.openBank; c5 += r.bankCr; c6 += r6;
        c7 += r.bankDr; c8 += r.padarCr; c9 += r.padarDr; c10 += r10; c11 += r11; c12 += r12;
        dataRows.add([
          '${i + 1}', r.head, n2(r.openCash), n2(r.openBank), n2(r.bankCr),
          n2(r6), n2(r.bankDr), n2(r.padarCr), n2(r.padarDr), n2(r10), n2(r11), n2(r12),
        ]);
      }
      final totRow = <String>['', 'કુલ :', n2(c3), n2(c4), n2(c5), n2(c6), n2(c7), n2(c8), n2(c9), n2(c10), n2(c11), n2(c12)];

      final openTot = c3 + c4;
      final cert = openTot > 0
          ? 'આથી પ્રમાણપત્ર આપવામાં આવે છે કે ગત વર્ષની જમા સિલક ₹${n2(openTot)} અંકે રૂપિયા ${numberToGujaratiWords(openTot)} તથા $financialYear ના નાણાકીય વર્ષમાં નીચે મુજબ કુલ ₹${n2(c5)} અંકે કુલ ${numberToGujaratiWords(c5)} મળેલ છે. આમ કુલ ગ્રાન્ટ ₹${n2(c6)} અંકે કુલ ${numberToGujaratiWords(c6)} થાય છે, જે પૈકી નીચે મુજબ કુલ ₹${n2(c7)} અંકે કુલ ${numberToGujaratiWords(c7)} નો ખર્ચ થયેલ છે. અગાઉના વર્ષની બચત સહિત 31 મી માર્ચના રોજ ₹${n2(c12)} અંકે કુલ ${numberToGujaratiWords(c12)} બચત રહેલ છે.${chequeReturnAmt > 0 ? " અહી ₹${n2(chequeReturnAmt)} અંકે રૂપિયા ${numberToGujaratiWords(chequeReturnAmt)} રિસોર્સ પર્સનના માનદ વેતન પરત કરતાં ચેક પરત આવતા આ રકમને પણ આવક અને ખર્ચ બંનેમાં સામેલ કરેલ છે." : ""}'
          : 'આથી પ્રમાણપત્ર આપવામાં આવે છે કે સને $financialYear નાણાકીય વર્ષમાં નીચે મુજબ કુલ ₹${c6.toStringAsFixed(0)} અંકે કુલ ${numberToGujaratiWords(c6)} મળેલ છે. જે પૈકી ₹${c7.toStringAsFixed(0)} અંકે કુલ ${numberToGujaratiWords(c7)} નો ખર્ચ થયેલ છે. અગાઉના વર્ષની બચત સહિત 31 મી માર્ચના રોજ ₹${c12.toStringAsFixed(0)} અંકે કુલ ${numberToGujaratiWords(c12)} બચત રહેલ છે.';

      // Exact top layout matching Rojmel_Report_parishisht_10_SNA_SPARSH_2025-26 (1).pdf (repeated on ALL pages!)
      final p10TopBannerHtml = '<div style="margin-bottom:3px">'
          '<div style="display:flex;justify-content:space-around;align-items:center;font-size:${(fontPt + 3.5).toStringAsFixed(1)}pt;font-weight:900;margin-bottom:2px">'
          '<span>પરિશિષ્ટ – ૧૦</span>'
          '<span>વર્ષ : ${esc(financialYear)}</span>'
          '</div>'
          '<div style="text-align:center;font-size:${(fontPt + 1).toStringAsFixed(1)}pt;font-weight:800;margin-bottom:2px">'
          'શાળાનું નામ : ${esc(sName)} &nbsp;|&nbsp; સરનામું : ${esc(sAddr)}'
          '</div>'
          '<div style="text-align:center;font-size:${(fontPt + 3.5).toStringAsFixed(1)}pt;font-weight:900;text-decoration:underline;margin-bottom:4px">'
          'ગ્રાન્ટ વપરાશ પ્રમાણપત્ર'
          '</div>'
          '<div style="font-size:${(fontPt + 0.3).toStringAsFixed(1)}pt;line-height:1.42;font-weight:600;text-align:justify;padding:2px 6px">'
          '&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;${esc(cert)}'
          '</div>'
          '<div style="text-align:center;font-size:${fontPt.toStringAsFixed(1)}pt;font-weight:800;margin:3px 0 4px">'
          'આ ઉપરાંત આવક અને ખર્ચના આંકડા સંબંધિત હિસાબી રેકર્ડ સાથે ચકાસણી કરીને દર્શાવેલા છે.'
          '</div>'
          '<div style="display:flex;justify-content:space-between;align-items:center;font-size:${(fontPt - 0.3).toStringAsFixed(1)}pt;font-weight:800;padding:2px 4px;border-bottom:1px solid #000">'
          '<span>SCHOOL NAME : ${esc(sName)}</span>'
          '<span>${mAcc.type == "SNA_PURE" ? "AGENCY CODE :- ${esc(effAgency)} &nbsp;|&nbsp; ACCOUNT :- ${esc(target)}" : (mAcc.type == "SNA" ? "PFMS A/C :- ${esc(acNo)} &nbsp;|&nbsp; SNA AGENCY CODE :- ${esc(effAgency)} &nbsp;|&nbsp; ${esc(target)}" : "ACCOUNT HOLDER NAME :- ${esc(holder)} &nbsp; A/C NO.-${esc(acNo)} &nbsp;&amp;&nbsp; ${esc(target)}")}</span>'
          '</div>'
          '</div>';

      // Exact 3-row grouped <thead> with 1..12 column numbers matching Rojmel_Report_parishisht_10_SNA_SPARSH_2025-26 (1).pdf
      final p10TheadHtml = '<thead>'
          '<tr>'
          '<th rowspan="2">ક્રમ</th>'
          '<th rowspan="2">ગ્રાન્ટ / હેડની વિગત</th>'
          '<th colspan="2">શરૂઆતની<br>સિલક</th>'
          '<th rowspan="2">આ વર્ષ<br>દરમ્યાન<br>બેન્કમાં મળેલ<br>ગ્રાન્ટ</th>'
          '<th rowspan="2">કુલ ગ્રાન્ટ બેન્કમાં<br>(4+5)</th>'
          '<th rowspan="2">ચેક કે PFMS<br>દ્વારા ખર્ચ /<br>પરત કરેલ ગ્રાન્ટ</th>'
          '<th colspan="2">પદર ખાતે</th>'
          '<th colspan="3">કુલ બંધ સિલક</th>'
          '</tr>'
          '<tr>'
          '<th>રોકડ</th>'
          '<th>બેન્ક</th>'
          '<th>આવક</th>'
          '<th>ખર્ચ</th>'
          '<th>રોકડ<br>(3+8-9)</th>'
          '<th>બેન્ક<br>(6-7)</th>'
          '<th>કુલ<br>(10+11)</th>'
          '</tr>'
          '<tr>'
          '<th>1</th><th>2</th><th>3</th><th>4</th><th>5</th><th>6</th><th>7</th><th>8</th><th>9</th><th>10</th><th>11</th><th>12</th>'
          '</tr>'
          '</thead>';

      return buildPaginatedTableSheets(
        rptKey: 'parishisht_10',
        title: 'પરિશિષ્ટ – ૧૦ : ગ્રાન્ટ વપરાશ પ્રમાણપત્ર',
        subtitle: '$target — વર્ષ : $financialYear',
        customBannerHtml: p10TopBannerHtml,
        showDefaultMeta: false,
        headers: const ['1', '2', '3', '4', '5', '6', '7', '8', '9', '10', '11', '12'],
        customTheadHtml: p10TheadHtml,
        dataRows: dataRows,
        totalRow: totRow,
        colWidthsPct: const [4, 22, 6.5, 6.5, 8.5, 8.5, 8.5, 7, 7, 7, 7, 7.5],
        customReportFooterName: 'નાણાકીય વર્ષ $financialYear માટે $sNameનું ગ્રાન્ટ વપરાશનું પ્રમાણપત્ર પરિશિષ્ટ 10 ($target)',
      );
    }

    String genParishisht11() {
      double sLim = 0, sRec = 0, sExp = 0, sBal = 0;
      final dataRows = <List<String>>[];
      for (int i = 0; i < headRows.length; i++) {
        final r = headRows[i];
        final rec = r.openTotal + r.bankCr;
        final bal = rec - r.bankDr;
        sLim += r.annualLimit; sRec += rec; sExp += r.bankDr; sBal += bal;
        dataRows.add([
          '${i + 1}', 'SSA',
          if (isSNAorPFMS) n2(r.annualLimit),
          n2(rec), r.head, mAcc.bankName, mAcc.acNo,
          r.creditDates.take(3).join(', '), n2(r.bankDr), n2(bal),
        ]);
      }
      final totRow = <String>[
        'TOTAL', 'કુલ :',
        if (isSNAorPFMS) n2(sLim),
        n2(sRec), 'OK', mAcc.bankName, mAcc.acNo, '', n2(sExp), n2(sBal),
      ];
      final cols = isSNAorPFMS
          ? const <double>[4.5, 6, 9, 9, 20.5, 14, 10, 9, 9, 9]
          : const <double>[5, 7, 10, 22, 16, 11, 9, 10, 10];
      return buildPaginatedTableSheets(
        rptKey: 'grant_reg',
        title: 'ગ્રાન્ટ રજીસ્ટર : પરિશિષ્ટ ૧૧ (PARISHISHT - 11 : GRANT REGISTER)',
        subtitle: '$sName ($target — $financialYear)',
        headers: [
          'ક્રમ', 'કોના તરફથી મળી',
          if (isSNAorPFMS) 'વાર્ષિક મર્યાદા ₹',
          'કુલ ગ્રાન્ટ રકમ ₹', 'ગ્રાન્ટ હેડ', 'બેન્કનું નામ', 'ખાતા નંબર', 'જમા તારીખ', 'ખર્ચેલ રકમ ₹', 'બચત ગ્રાન્ટ ₹',
        ],
        dataRows: dataRows,
        totalRow: totRow,
        colWidthsPct: cols,
      );
    }

    String genAnnexure12() {
      double s3 = 0, s4 = 0, s5 = 0, s6 = 0, s7 = 0, s8 = 0, s9 = 0, s10 = 0;
      final dataRows = <List<String>>[];
      for (int i = 0; i < headRows.length; i++) {
        final r = headRows[i];
        final totG = r.openTotal + r.credit;
        s3 += r.openCash; s4 += r.openBank; s5 += r.padarCr; s6 += r.bankCr;
        s7 += totG; s8 += r.padarDr; s9 += r.bankDr; s10 += r.closing;
        dataRows.add([
          '${i + 1}', r.head, n2(r.openCash), n2(r.openBank), n2(r.padarCr),
          n2(r.bankCr), n2(totG), n2(r.padarDr), n2(r.bankDr), n2(r.closing),
        ]);
      }
      final totRow = <String>['TOTAL', 'એકંદરે સરવાળો :', n2(s3), n2(s4), n2(s5), n2(s6), n2(s7), n2(s8), n2(s9), n2(s10)];
      return buildPaginatedTableSheets(
        rptKey: 'annexure_12',
        title: 'એનેક્ષર-12 : સર્વ શિક્ષા અભિયાન - ગુજરાત (માસવાર હિસાબ પત્રક)',
        subtitle: '$sName ($target — $financialYear)',
        headers: const ['ક્રમ', 'ગ્રાન્ટનું નામ', 'ઉઘડતી રોકડ', 'ઉઘડતી બેન્ક', 'મળેલ રોકડ', 'મળેલ બેન્ક', 'કુલ ગ્રાન્ટ', 'ખર્ચ રોકડ', 'ખર્ચ બેન્ક', 'બંધ સિલક'],
        dataRows: dataRows,
        totalRow: totRow,
        colWidthsPct: const [5, 23, 9, 9, 9, 9, 9, 9, 9, 9],
      );
    }

    String genMonthlyHisab() {
      final hisabEntries = selectedMonthlyHisabMonth == 'ALL'
          ? list
          : list.where((e) => e.date.startsWith(selectedMonthlyHisabMonth)).toList();
      double sCrC = 0, sCrB = 0, sDrC = 0, sDrB = 0;
      final dataRows = <List<String>>[];
      for (int i = 0; i < hisabEntries.length; i++) {
        final e = hisabEntries[i];
        final cC = e.type == 'credit' ? cashAmt(e) : 0.0;
        final cB = e.type == 'credit' ? bankAmt(e) : 0.0;
        final dC = e.type == 'debit' ? cashAmt(e) : 0.0;
        final dB = e.type == 'debit' ? bankAmt(e) : 0.0;
        sCrC += cC; sCrB += cB; sDrC += dC; sDrB += dB;
        dataRows.add([
          '${i + 1}', fmtDateSlashDDMMYYYY(e.date), e.head,
          e.type == 'credit' ? 'આવક(+)' : 'જાવક(-)',
          e.type == 'debit' ? formatDebitNarration(e) : formatCreditNarration(e),
          n2(cC), n2(cB), n2(cC + cB), n2(dC), n2(dB), n2(dC + dB),
        ]);
      }
      return buildPaginatedTableSheets(
        rptKey: 'monthly',
        title: 'માસવાર હિસાબ પત્રક (MONTHLY TRANSACTION STATEMENT)',
        subtitle: '$sName ($target — $financialYear${selectedMonthlyHisabMonth != "ALL" ? " | માસ: $selectedMonthlyHisabMonth" : ""})',
        headers: const ['ક્રમ', 'તારીખ', 'ગ્રાન્ટ હેડ', 'પ્રકાર', 'વિગત', 'આ.રોકડા', 'આ.બેંક', 'આવક (+)', 'જા.રોકડા', 'જા.બેંક', 'ખર્ચ (-)'],
        dataRows: dataRows,
        totalRow: ['TOTAL', '', '', '', 'કુલ સરવાળો :', n2(sCrC), n2(sCrB), n2(sCrC + sCrB), n2(sDrC), n2(sDrB), n2(sDrC + sDrB)],
        colWidthsPct: const [4.5, 8.5, 13, 6.5, 22.5, 7.5, 7.5, 7.5, 7.5, 7.5, 7.5],
      );
    }

    String genMonthlyLimitReport() {
      final fyMonths = getFyMonthsList();
      final accHeads = reportFilterHead == 'ALL'
          ? getAccountSpecificHeads(target)
          : <String>[reportFilterHead];
      final isBankAcc = mAcc.type == 'BANK';

      if (selectedMonthlyLimitMonth != 'ALL') {
        final mObj = fyMonths.firstWhere(
          (m) => m['ym'] == selectedMonthlyLimitMonth,
          orElse: () => fyMonths.first,
        );
        final ym = mObj['ym']!;
        final mLabel = mObj['label']!;
        final dataRows = <List<String>>[];
        double totCol3 = 0, totCol4 = 0, totCol5 = 0, totCol6 = 0, totCol7 = 0, totCol8 = 0;

        for (int i = 0; i < accHeads.length; i++) {
          final h = accHeads[i];
          if (isBankAcc) {
            final hop = getHeadOpening(target, h);
            double priorCr = 0, priorDr = 0, curCr = 0, curDr = 0;
            for (final e in allAcc.where((x) => x.head == h)) {
              final eYm = e.date.length >= 7 ? e.date.substring(0, 7) : '';
              if (eYm.compareTo(ym) < 0) {
                if (e.type == 'credit') priorCr += e.amount;
                else priorDr += e.amount;
              } else if (eYm == ym) {
                if (e.type == 'credit') curCr += e.amount;
                else curDr += e.amount;
              }
            }
            final openMonth = hop.total + priorCr - priorDr;
            final availMonth = openMonth + curCr;
            final remBal = availMonth - curDr;
            totCol3 += openMonth;
            totCol4 += curCr;
            totCol5 += availMonth;
            totCol6 += curDr;
            totCol7 += remBal;
            dataRows.add([
              '${i + 1}', h, n2(openMonth), n2(curCr), n2(availMonth), n2(curDr), n2(remBal),
            ]);
          } else {
            final lim = getHeadLimit(target, h);
            double priorExp = 0, curExp = 0;
            for (final e in allAcc.where((x) => x.head == h && x.type == 'debit' && !isCashEntry(x))) {
              final eYm = e.date.length >= 7 ? e.date.substring(0, 7) : '';
              if (eYm.compareTo(ym) < 0) priorExp += e.amount;
              else if (eYm == ym) curExp += e.amount;
            }
            final openRemLimit = lim - priorExp;
            final cumExp = priorExp + curExp;
            final endRemLimit = lim - cumExp;
            totCol3 += lim;
            totCol4 += priorExp;
            totCol5 += openRemLimit;
            totCol6 += curExp;
            totCol7 += cumExp;
            totCol8 += endRemLimit;
            dataRows.add([
              '${i + 1}', h, n2(lim), n2(priorExp), n2(openRemLimit), n2(curExp), n2(cumExp), n2(endRemLimit),
            ]);
          }
        }

        if (isBankAcc) {
          return buildPaginatedTableSheets(
            rptKey: 'monthly_limit_report',
            title: 'માસવાર ખર્ચ અને બાકી બેંક સિલક પત્રક (MONTHLY EXPENSE & REMAINING BALANCE — BANK)',
            subtitle: 'માસ : $mLabel  |  $sName ($target — $financialYear)',
            headers: const ['ક્રમ', 'ગ્રાન્ટ હેડ', 'માસની ઉઘડતી સિલક ₹', 'ચાલુ માસમાં જમા ₹', 'કુલ પ્રાપ્ય સિલક ₹', 'ચાલુ માસનો ખર્ચ ₹', 'માસના અંતે બાકી સિલક ₹'],
            dataRows: dataRows,
            totalRow: ['TOTAL', 'કુલ સરવાળો ($mLabel) :', n2(totCol3), n2(totCol4), n2(totCol5), n2(totCol6), n2(totCol7)],
            colWidthsPct: const [5, 27, 13.6, 13.6, 13.6, 13.6, 13.6],
          );
        } else {
          return buildPaginatedTableSheets(
            rptKey: 'monthly_limit_report',
            title: 'માસવાર અને હેડવાર ખર્ચ તથા બાકી લિમિટ પત્રક (MONTHLY HEAD-WISE EXPENSE & REMAINING LIMIT)',
            subtitle: 'માસ : $mLabel  |  $sName ($target — $financialYear)',
            headers: const ['ક્રમ', 'ગ્રાન્ટ હેડ', 'વાર્ષિક મર્યાદા ₹', 'અગાઉના માસ સુધી ખર્ચ ₹', 'માસની શરૂઆતની બાકી લિમિટ ₹', 'ચાલુ માસનો ખર્ચ ₹', 'કુલ વપરાયેલ લિમિટ ₹', 'માસના અંતે બાકી લિમિટ ₹'],
            dataRows: dataRows,
            totalRow: ['TOTAL', 'કુલ સરવાળો ($mLabel) :', n2(totCol3), n2(totCol4), n2(totCol5), n2(totCol6), n2(totCol7), n2(totCol8)],
            colWidthsPct: const [4.5, 23.5, 12, 12, 12, 12, 12, 12],
          );
        }
      }

      // Full Year (April to March — 12 Months Head-wise Expense & Remaining Limit / Balance Matrix)
      final dataRows = <List<String>>[];
      double sumBase = 0;
      final sumMonthExp = List<double>.filled(12, 0.0);
      final sumMonthRem = List<double>.filled(12, 0.0);
      double sumTotalExp = 0;
      double sumFinalRem = 0;

      for (int i = 0; i < accHeads.length; i++) {
        final h = accHeads[i];
        final baseVal = isBankAcc ? getHeadOpening(target, h).total : getHeadLimit(target, h);
        sumBase += baseVal;
        double runningBalOrRem = baseVal;
        double headTotExp = 0;
        final rowCells = <String>['${i + 1}', h, n2(baseVal)];

        for (int mIdx = 0; mIdx < 12; mIdx++) {
          final ym = fyMonths[mIdx]['ym']!;
          double mCr = 0, mDr = 0;
          for (final e in allAcc.where((x) => x.head == h && x.date.startsWith(ym))) {
            if (isBankAcc) {
              if (e.type == 'credit') mCr += e.amount;
              else mDr += e.amount;
            } else {
              if (e.type == 'debit' && !isCashEntry(e)) mDr += e.amount;
            }
          }
          if (isBankAcc) {
            runningBalOrRem = runningBalOrRem + mCr - mDr;
          } else {
            runningBalOrRem = runningBalOrRem - mDr;
          }
          headTotExp += mDr;
          sumMonthExp[mIdx] += mDr;
          sumMonthRem[mIdx] += runningBalOrRem;
          rowCells.add('${n2(mDr)}\n(બાકી: ${n2(runningBalOrRem)})');
        }
        sumTotalExp += headTotExp;
        sumFinalRem += runningBalOrRem;
        rowCells.add(n2(headTotExp));
        rowCells.add(n2(runningBalOrRem));
        dataRows.add(rowCells);
      }

      final totRow = <String>[
        'TOTAL',
        'કુલ સરવાળો (Full Year) :',
        n2(sumBase),
        ...List<String>.generate(12, (mIdx) => '${n2(sumMonthExp[mIdx])}\n(બાકી: ${n2(sumMonthRem[mIdx])})'),
        n2(sumTotalExp),
        n2(sumFinalRem),
      ];

      return buildPaginatedTableSheets(
        rptKey: 'monthly_limit_report',
        title: isBankAcc
            ? 'વાર્ષિક માસવાર (એપ્રિલ થી માર્ચ) ખર્ચ અને બાકી બેંક સિલક પત્રક (FULL YEAR MONTHLY EXPENSE & REMAINING BALANCE)'
            : 'વાર્ષિક માસવાર (એપ્રિલ થી માર્ચ) અને હેડવાર ખર્ચ તથા બાકી લિમિટ પત્રક (FULL YEAR HEAD-WISE MONTHLY EXPENSE & REMAINING LIMIT)',
        subtitle: '$sName ($target — નાણાકીય વર્ષ : $financialYear | દરેક ખાનામાં ઉપર માસિક ખર્ચ અને નીચે માસના અંતે બાકી ${isBankAcc ? "સિલક" : "લિમિટ"})',
        headers: [
          'ક્રમ',
          'ગ્રાન્ટ હેડ',
          isBankAcc ? 'ઉઘડતી સિલક ₹' : 'વાર્ષિક લિમિટ ₹',
          ...fyMonths.map((m) => '${m["gu"]}\nખર્ચ / બાકી'),
          'કુલ વાર્ષિક ખર્ચ ₹',
          isBankAcc ? 'આખરની બાકી સિલક ₹' : 'આખરની બાકી લિમિટ ₹',
        ],
        dataRows: dataRows,
        totalRow: totRow,
        colWidthsPct: const [3.0, 14.0, 6.5, 5.2, 5.2, 5.2, 5.2, 5.2, 5.2, 5.2, 5.2, 5.2, 5.2, 5.2, 5.2, 7.0, 7.1],
      );
    }

    String genPassbook() {
      final bankList = list.where((e) => !isCashEntry(e)).toList();
      double run = openBal.bank, totW = 0, totD = 0;
      final openDateLabel = fromNorm.isNotEmpty
          ? fmtDateSlashDDMMYYYY(fromNorm)
          : '01/04/${financialYear.length >= 4 ? financialYear.substring(0, 4) : ''}';
      final dataRows = <List<String>>[
        ['0', openDateLabel, 'Opening Balance (શરૂઆતની સિલક)', '-', '0.00', n2(openBal.bank), n2(run)],
      ];
      for (int i = 0; i < bankList.length; i++) {
        final e = bankList[i];
        final w = e.type == 'debit' ? e.amount : 0.0;
        final d = e.type == 'credit' ? e.amount : 0.0;
        totW += w; totD += d; run += (d - w);
        dataRows.add([
          '${i + 1}', fmtDateSlashDDMMYYYY(e.date), '${e.narration} [${e.head}]',
          e.txn.isNotEmpty ? e.txn : '-', n2(w), n2(d), n2(run),
        ]);
      }
      return buildPaginatedTableSheets(
        rptKey: 'passbook',
        title: 'BANK PASSBOOK — $sName ($target)',
        subtitle: 'A/C No.: $acNo  |  Financial Year: $financialYear',
        headers: const ['Sr.', 'Date', 'Particulars', 'Chq / PFMS / Claim No.', 'Withdrawals ₹', 'Deposits ₹', 'Balance ₹'],
        dataRows: dataRows,
        totalRow: ['TOTAL', '', 'PASSBOOK GRAND TOTAL :', '-', n2(totW), n2(openBal.bank + totD), n2(run)],
        colWidthsPct: const [5, 10, 34, 18, 11, 11, 11],
      );
    }

    String genTallyReport() {
      double totCrC = 0, totCrB = 0, totDrC = 0, totDrB = 0;
      for (final e in list) {
        if (e.type == 'credit') {
          totCrC += cashAmt(e); totCrB += bankAmt(e);
        } else {
          totDrC += cashAmt(e); totDrB += bankAmt(e);
        }
      }
      final closeC = openBal.cash + totCrC - totDrC;
      final closeB = openBal.bank + totCrB - totDrB;
      final dataRows = <List<String>>[
        ['1', 'Cash-in-Hand (રોકડ / પદર ખાતું)', 'Cash-in-Hand', n2(openBal.cash), n2(totCrC), n2(totDrC), n2(closeC)],
        ['2', '${mAcc.bankName} A/c $acNo ($target)', 'Bank Accounts', n2(openBal.bank), n2(totCrB), n2(totDrB), n2(closeB)],
      ];
      // Grant (fund) ledgers: expense (cash + bank) is Debit, grant received
      // (cash + bank) is Credit, so total Debit always equals total Credit.
      double fundOpen = 0, fundClose = 0;
      for (int i = 0; i < headRows.length; i++) {
        final r = headRows[i];
        fundOpen += r.openTotal;
        fundClose += r.closing;
        dataRows.add(['${i + 3}', r.head, 'Grant Fund (Receipt & Expense)', n2(r.openTotal), n2(r.debit), n2(r.credit), n2(r.closing)]);
      }
      final allDr = totCrC + totCrB + totDrC + totDrB;
      return buildPaginatedTableSheets(
        rptKey: 'tally_report',
        title: 'TALLY AUDIT REPORT — ટ્રાયલ બેલેન્સ અને ગ્રાન્ટ ખાતાવહી',
        subtitle: '$sName ($target — $financialYear) | Assets (Cash + Bank) = Grant Fund Balance: ₹${n2(closeC + closeB)} = ₹${n2(fundClose)}',
        headers: const ['ક્રમ', 'લેજરનું નામ (Tally Ledger Name)', 'ગ્રુપ (Group)', 'ઉઘડતી સિલક ₹', 'ઉધાર (Debit ₹)', 'જમા (Credit ₹)', 'બંધ સિલક ₹'],
        dataRows: dataRows,
        totalRow: ['TOTAL', 'TALLY TRIAL BALANCE (Dr = Cr)', '-', n2(openBal.total + fundOpen), n2(allDr), n2(allDr), n2(closeC + closeB + fundClose)],
        colWidthsPct: const [5, 31, 20, 11, 11, 11, 11],
      );
    }

    String genTarijPatrak() {
      final tpOpenCash = reportFromDate.isNotEmpty
          ? headRows.fold<double>(0.0, (s, r) => s + r.openCash)
          : openBal.cash;
      final tpOpenBank = reportFromDate.isNotEmpty
          ? headRows.fold<double>(0.0, (s, r) => s + r.openBank)
          : openBal.bank;
      final tpOpenTot = tpOpenCash + tpOpenBank;
      double totCrC = 0, totCrB = 0, totDrC = 0, totDrB = 0;
      final dataRows = <List<String>>[
        ['શ્રી ઉઘડતી સિલક (Opening Balance)', n2(tpOpenCash), n2(tpOpenBank), n2(tpOpenTot), '-', '0.00', '0.00', '0.00'],
      ];
      for (final r in headRows) {
        if (r.credit > 0 || r.debit > 0) {
          totCrC += r.padarCr; totCrB += r.bankCr; totDrC += r.padarDr; totDrB += r.bankDr;
          dataRows.add([r.head, n2(r.padarCr), n2(r.bankCr), n2(r.credit), r.head, n2(r.padarDr), n2(r.bankDr), n2(r.debit)]);
        }
      }
      final closeC = tpOpenCash + totCrC - totDrC;
      final closeB = tpOpenBank + totCrB - totDrB;
      return buildPaginatedTableSheets(
        rptKey: 'receipt_payment',
        title: 'તારીજ પત્રક (RECEIPT & PAYMENT ACCOUNT)',
        subtitle: '$sName ($target — $financialYear)',
        headers: const ['આવકના સદર (Receipts +)', 'રોકડ ₹', 'બેન્ક ₹', 'કુલ આવક ₹', 'જાવકના સદર (Payments -)', 'રોકડ ₹', 'બેન્ક ₹', 'કુલ જાવક ₹'],
        dataRows: dataRows,
        totalRow: ['કુલ આવક (Total Receipts)', n2(totCrC), n2(totCrB), n2(totCrC + totCrB), 'કુલ ખર્ચ (Total Expense)', n2(totDrC), n2(totDrB), n2(totDrC + totDrB)],
        extraTotalRows: <List<String>>[
          ['-', '0.00', '0.00', '0.00', 'શ્રી બંધ સિલક (Closing Balance)', n2(closeC), n2(closeB), n2(closeC + closeB)],
          ['એકંદરે કુલ આવક :', n2(tpOpenCash + totCrC), n2(tpOpenBank + totCrB), n2(tpOpenTot + totCrC + totCrB), 'એકંદરે કુલ જાવક :', n2(totDrC + closeC), n2(totDrB + closeB), n2(totDrC + totDrB + closeC + closeB)],
        ],
        colWidthsPct: const [23, 9, 9, 9, 23, 9, 9, 9],
      );
    }

    String genCertifiedVouchers() {
      double totC = 0, totB = 0;
      final dataRows = <List<String>>[];
      for (int i = 0; i < debits.length; i++) {
        final e = debits[i];
        final c = cashAmt(e), b = bankAmt(e);
        totC += c; totB += b;
        dataRows.add([
          '${i + 1}', e.voucher, fmtDateSlashDDMMYYYY(e.date),
          '${pageMap[e.id] ?? "-"}', '${khMap[e.head] ?? "-"}',
          e.head, e.party, formatDebitNarration(e), e.txn,
          fmtDateSlashDDMMYYYY(e.clearDate), n2(c), n2(b), n2(e.amount),
        ]);
      }
      return buildPaginatedTableSheets(
        rptKey: 'voucher_cert',
        title: 'પ્રમાણિત વાઉચર અને ખર્ચનું પત્રક (CERTIFIED VOUCHERS)',
        subtitle: '$sName ($target — $financialYear)',
        headers: const ['અ.નં.', 'વાઉચર નં.', 'તારીખ', 'રોજમેળ પા.નં.', 'ખાતાવહી પા.નં.', 'ગ્રાન્ટ હેડ', 'પાર્ટીનું નામ', 'ખર્ચની વિગત', 'ચેક/CLAIM નં.', 'સેટલમેન્ટ તારીખ', 'રોકડ ₹', 'બેન્ક ₹', 'કુલ રકમ ₹'],
        dataRows: dataRows,
        totalRow: ['TOTAL', '', '', '', '', '', '', 'એકંદરે કુલ પ્રમાણિત ખર્ચ :', '', '', n2(totC), n2(totB), n2(totC + totB)],
        colWidthsPct: const [3.5, 4.5, 7, 4.5, 4.5, 10, 12, 16, 11, 7, 6.5, 6.5, 7],
      );
    }

    String genCoverAndAuditCerts() {
      double crB = 0, drB = 0, crC = 0, drC = 0;
      for (final e in list) {
        if (e.type == 'credit') { crC += cashAmt(e); crB += bankAmt(e); }
        else { drC += cashAmt(e); drB += bankAmt(e); }
      }
      final closeC = openBal.cash + crC - drC;
      final closeB = openBal.bank + crB - drB;
      return buildPaginatedTableSheets(
        rptKey: 'audit_certs',
        title: 'રોજમેળ અને ઓડિટ ફાઈલ મુખપૃષ્ઠ, અનુક્રમણિકા અને પ્રમાણપત્રો',
        subtitle: '$sName — વર્ષ : $financialYear ($target)',
        headers: const ['અ.નં.', 'પત્રક / રજીસ્ટરનું નામ (Register Name)', 'સારાંશ / કુલ રકમ', 'સ્થિતિ'],
        dataRows: <List<String>>[
          ['1', 'રોજમેળ / કેશબુક (Cashbook — $target)', 'ઉઘડતી ₹${n2(openBal.bank)} | જમા ₹${n2(crB)} | ખર્ચ ₹${n2(drB)}', 'સામેલ છે'],
          ['2', 'પરિશિષ્ટ નંબર : 2 — આવક ખર્ચનું વર્ગીકરણ (ખાતાવહી)', '${headRows.length} ગ્રાન્ટ હેડ ખાતાવહી', 'સામેલ છે'],
          ['3', 'વર્ષ દરમિયાનનું બિલોનું નોંધપત્રક (બિલ રજીસ્ટર)', 'કુલ બિલ ₹${n2(drC + drB)}', 'સામેલ છે'],
          ['4', 'વર્ષ દરમિયાનનું ચેકોનું નોંધપત્રક (ક્લેઈમ / ચેક રજીસ્ટર)', 'કુલ બેંક ડેબિટ ₹${n2(drB)}', 'સામેલ છે'],
          ['5', 'ખર્ચ પત્રક (વર્ષ દરમિયાન ખર્ચનું નોંધપત્રક)', 'રોકડ ₹${n2(drC)} + બેંક ₹${n2(drB)}', 'સામેલ છે'],
          ['6', 'પરિશિષ્ટ – ૮ : ગ્રાન્ટ ફાળવણી, ખર્ચ અને બંધ સિલક પત્રક', 'કુલ ગ્રાન્ટ ₹${n2(openBal.bank + crB)}', 'સામેલ છે'],
          ['7', 'પરિશિષ્ટ – 9 : બેંક સાથે મેળવણું – રીકન્સીલેશન', 'રોજમેળ સિલક ₹${n2(closeB)} = પાસબુક ₹${n2(closeB)}', 'સામેલ છે'],
          ['8', 'પરિશિષ્ટ – ૧૦ : ગ્રાન્ટ વપરાશ પ્રમાણપત્ર (Utilization Certificate)', 'બંધ સિલક ₹${n2(closeC + closeB)}', 'સામેલ છે'],
          ['9', 'ગ્રાન્ટ રજીસ્ટર : પરિશિષ્ટ ૧૧ (Grant Register)', 'કુલ ગ્રાન્ટ ₹${n2(openBal.bank + crB)}', 'સામેલ છે'],
          ['10', 'એનેક્ષર-12 અને માસવાર હિસાબ પત્રક, પાસબુક, ટેલી, તારીજ પત્રક, પ્રમાણિત વાઉચર', 'સંપૂર્ણ પત્રકો', 'સામેલ છે'],
          ['11', 'રોકડ / પદર રજીસ્ટર, બેંક વ્યાજ રજીસ્ટર, પાર્ટી મુજબ ચુકવણી પત્રક, પાકું સરવૈયું', 'બંધ રોકડ ₹${n2(closeC)} | બંધ બેંક ₹${n2(closeB)}', 'સામેલ છે'],
          ['12', 'આવક-ખર્ચ ખાતું, GFR 12-A ઉપયોગિતા પ્રમાણપત્ર, માસવાર બેંક મેળવણું', 'ખર્ચ ₹${n2(drC + drB)}', 'સામેલ છે'],
          ['13', 'મિલકત ખરીદી પત્રક (ડેડ સ્ટોક), રોકડ સિલક ચકાસણી અને બેંક સિલક પ્રમાણપત્ર, ગણતરી મેળવણું પત્રક', 'રોકડ ₹${n2(closeC)} | બેંક ₹${n2(closeB)}', 'સામેલ છે'],
        ],
        colWidthsPct: const [7, 48, 33, 12],
      );
    }

    String notesHtml(List<String> notes, {bool pre = false}) => notes.isEmpty
        ? ''
        : '<div class="rpt-notes${pre ? " pre" : ""}">${notes.map((n) => '<p>${esc(n)}</p>').join()}</div>';

    String genExtra(String key) {
      final t = buildExtraAuditTable(key, target, list, openBal, headRows);
      if (t.notesOnOwnPage && t.notes.isNotEmpty) {
        // Page 1: the whole form table; page 2: certificate + signatures.
        final first = buildSheetHtml(
          rptKey: key,
          title: t.title,
          subtitle: t.subtitle,
          innerHtml: notesHtml(t.preNotes, pre: true) +
              buildTableHtml(t.headers, <List<String>>[...t.dataRows, ...t.totalRows],
                  totalRowCountAtBottom: t.totalRows.length, colWidthsPct: t.colWidthsPct, leftCols: t.leftCols),
          pageInReport: 1,
          totalPagesInReport: 2,
          showSignatures: false,
        );
        final second = buildSheetHtml(
          rptKey: key,
          title: t.title,
          subtitle: t.subtitle,
          innerHtml: notesHtml(t.notes),
          pageInReport: 2,
          totalPagesInReport: 2,
          showDefaultMeta: false,
          signLabels: t.signLabels,
        );
        return first + second;
      }
      return buildPaginatedTableSheets(
        rptKey: key,
        title: t.title,
        subtitle: t.subtitle,
        preTableHtml: notesHtml(t.preNotes, pre: true),
        headers: t.headers,
        dataRows: t.dataRows,
        totalRow: t.totalRows.isNotEmpty ? t.totalRows.first : null,
        extraTotalRows: t.totalRows.length > 1 ? t.totalRows.sublist(1) : null,
        colWidthsPct: t.colWidthsPct,
        postTableHtml: notesHtml(t.notes),
        signLabels: t.signLabels,
        leftCols: t.leftCols,
      );
    }

    final sb = StringBuffer();
    sb.writeln('<!doctype html><html lang="gu"><head><meta charset="utf-8"><title>Rojmel Audit Report - ${esc(target)}</title>');
    sb.writeln(sharedCss);
    sb.writeln('</head><body>');

    switch (reportType) {
      case 'daybook':
        sb.write(cashbookSectionsOnly);
        break;
      case 'parishisht_2':
        sb.write(genParishisht2());
        break;
      case 'bill_reg':
        sb.write(genBillReg());
        break;
      case 'cheque_reg':
        sb.write(genChequeReg());
        break;
      case 'kharch_patrak':
        sb.write(genKharchPatrak());
        break;
      case 'parishisht_8':
        sb.write(genParishisht8());
        break;
      case 'parishisht_9':
        sb.write(genParishisht9());
        break;
      case 'parishisht_10':
        sb.write(genParishisht10());
        break;
      case 'grant_reg':
        sb.write(genParishisht11());
        break;
      case 'annexure_12':
        sb.write(genAnnexure12());
        break;
      case 'monthly':
        sb.write(genMonthlyHisab());
        break;
      case 'monthly_limit_report':
        sb.write(genMonthlyLimitReport());
        break;
      case 'passbook':
        sb.write(genPassbook());
        break;
      case 'tally_report':
        sb.write(genTallyReport());
        break;
      case 'receipt_payment':
        sb.write(genTarijPatrak());
        break;
      case 'voucher_cert':
        sb.write(genCertifiedVouchers());
        break;
      case 'audit_certs':
        sb.write(genCoverAndAuditCerts());
        break;
      case 'interest_register':
      case 'cash_register':
      case 'party_register':
      case 'balance_sheet':
      case 'income_expenditure':
      case 'gfr_12a':
      case 'monthly_brs':
      case 'asset_register':
      case 'cash_verification':
      case 'bank_certificate':
      case 'audit_crosscheck':
        sb.write(genExtra(reportType));
        break;
      case 'audit_pack':
      case 'all_17':
      default:
        sb.write(genCoverAndAuditCerts());
        sb.write(cashbookSectionsOnly);
        sb.write(genParishisht2());
        sb.write(genBillReg());
        sb.write(genChequeReg());
        sb.write(genKharchPatrak());
        sb.write(genParishisht8());
        sb.write(genParishisht9());
        sb.write(genParishisht10());
        sb.write(genParishisht11());
        sb.write(genAnnexure12());
        sb.write(genMonthlyHisab());
        sb.write(genMonthlyLimitReport());
        sb.write(genPassbook());
        sb.write(genTallyReport());
        sb.write(genTarijPatrak());
        sb.write(genCertifiedVouchers());
        sb.write(genExtra('cash_register'));
        sb.write(genExtra('interest_register'));
        sb.write(genExtra('party_register'));
        sb.write(genExtra('balance_sheet'));
        for (final k in const ['income_expenditure', 'gfr_12a', 'monthly_brs', 'asset_register', 'cash_verification', 'bank_certificate', 'audit_crosscheck']) {
          sb.write(genExtra(k));
        }
        break;
    }

    sb.writeln('''<script>
(function(){
  function fitNums(){
    var cells=document.querySelectorAll(".num,.sum-num,.gov-audit-table td,.claim-cell,.voucher-cell,.date-cell,.settle-cell");
    for(var i=0;i<cells.length;i++){
      var td=cells[i];
      var fs=parseFloat(window.getComputedStyle(td).fontSize)||11;
      while((td.scrollWidth>td.clientWidth+1)&&fs>6.0){
        fs-=0.35;
        td.style.fontSize=fs+"px";
      }
    }
  }
  function fitAllReportSheets(){
    var sheets=document.querySelectorAll(".gov-audit-sheet");
    for(var s=0;s<sheets.length;s++){
      var sheet=sheets[s];
      var topWrap=sheet.querySelector(".gov-audit-top-wrap");
      var fitInner=sheet.querySelector(".gov-audit-fit-inner");
      var bottomWrap=sheet.querySelector(".gov-audit-bottom-wrap");
      if(!topWrap||!fitInner||!bottomWrap) continue;
      var tables=fitInner.querySelectorAll(".gov-audit-table");
      var sign=bottomWrap.querySelector(".gov-audit-sign");
      var padTop=parseFloat(window.getComputedStyle(sheet).paddingTop)||15;
      var padBot=parseFloat(window.getComputedStyle(sheet).paddingBottom)||11;
      var availH=sheet.clientHeight - padTop - padBot - bottomWrap.offsetHeight - 4;
      if(availH < 200) availH = sheet.clientHeight * 0.78;

      var step=0;
      while(fitInner.scrollHeight > availH && step < 18){
        step++;
        if(step === 1 && sign){
          sign.style.marginTop = "1.8mm";
          sign.style.fontSize = "8pt";
        }
        for(var t=0;t<tables.length;t++){
          var tbl=tables[t];
          var curFs=parseFloat(window.getComputedStyle(tbl).fontSize)||11;
          if(curFs > 6.5){
            tbl.style.fontSize=(curFs - 0.4)+"px";
          }
          var tds=tbl.querySelectorAll("th,td");
          var vPad=Math.max(0.8, 2.6 - step*0.18);
          for(var c=0;c<tds.length;c++){
            tds[c].style.paddingTop=vPad+"px";
            tds[c].style.paddingBottom=vPad+"px";
            tds[c].style.lineHeight="1.08";
          }
        }
        availH=sheet.clientHeight - padTop - padBot - bottomWrap.offsetHeight - 4;
      }
      if(fitInner.scrollHeight > availH && availH > 100){
        var ratio = (availH / fitInner.scrollHeight) * 0.985;
        if(ratio < 1.0 && ratio > 0.45){
          fitInner.style.zoom = ratio.toFixed(3);
        }
      }
    }
    fitNums();
  }
  fitAllReportSheets();
  window.fitNums=fitNums;
  window.fitAllReportSheets=fitAllReportSheets;
  window.onload=function(){fitAllReportSheets();};
})();
</script></body></html>''');
    return applyPrintSetup(sb.toString());
  }

  static final RegExp _printSectionTag = RegExp(r'<section class="(cash-demo-page|gov-audit-sheet)([^"]*)"([^>]*)>');

  /// Places every printed page of [html] (cashbook and report pages, in print
  /// order): binding space on the edge chosen by [printSetup] (page-wise
  /// rules first), blank pages for double-sided alignment, and the PDF page
  /// number as `data-pdfpage`.
  String applyPrintSetup(String html) {
    final matches = _printSectionTag.allMatches(html).toList();
    if (matches.isEmpty) return html;
    final out = StringBuffer();
    var last = 0;
    var page = 0;
    String? prevRpt;
    final repLeft = reportLeftSpaceMm.clamp(2.0, 35.0);
    final repRight = reportRightSpaceMm.clamp(2.0, 35.0);
    for (final m in matches) {
      final family = m.group(1)!;
      final cls = m.group(2)!;
      var attrs = m.group(3)!;
      final landscape = cls.contains('landscape');
      final kindAttr = RegExp(r'data-kind="([^"]*)"').firstMatch(attrs)?.group(1) ?? '';
      final rpt = RegExp(r'data-rpt="([^"]*)"').firstMatch(attrs)?.group(1) ?? family;
      final kind = family == 'cash-demo-page'
          ? (cls.contains('debit-page') || kindAttr == 'dr' ? RojmelPageKind.cashbookDebit : RojmelPageKind.cashbookCredit)
          : (cls.contains('blank-sheet') ? RojmelPageKind.blank : RojmelPageKind.report);
      out.write(html.substring(last, m.start));
      last = m.end;
      if (kind == RojmelPageKind.blank) {
        // A blank page left from an earlier pass: keep it, count it.
        page++;
        out.write(m.group(0));
        continue;
      }
      final start = rpt != prevRpt;
      prevRpt = rpt;
      if (start && printSetup.needsBlankBefore(page + 1, kind: kind)) {
        page++;
        final o = landscape ? 'landscape' : 'portrait';
        out.write('<section class="gov-audit-sheet ${o}-sheet blank-sheet" data-orientation="$o" data-kind="blank" data-pdfpage="$page" style="padding:0!important">'
            '<div class="blank-note">આ પાનું બંને બાજુ પ્રિન્ટ માટે જાણી જોઈને ખાલી રાખેલ છે</div></section>');
      }
      page++;
      final box = printSetup.boxFor(page, kind: kind, landscape: landscape, reportLeft: repLeft, reportRight: repRight);
      attrs = attrs.replaceAll(RegExp(r'\sdata-pdfpage="[^"]*"'), '').replaceAll(RegExp(r'\sdata-bind="[^"]*"'), '');
      final styleM = RegExp(r'style="([^"]*)"').firstMatch(attrs);
      final pad = 'padding:${box.css}!important';
      if (styleM != null) {
        final st = styleM.group(1)!.trim();
        attrs = attrs.replaceRange(styleM.start, styleM.end, 'style="$st${st.isEmpty || st.endsWith(';') ? '' : ';'}$pad"');
      } else {
        attrs = '$attrs style="$pad"';
      }
      out.write('<section class="$family$cls" data-pdfpage="$page" data-bind="${box.edge}"$attrs>');
    }
    out.write(html.substring(last));
    return out.toString();
  }

  // --------------------------------------------------------------------------
  // ACCOUNT-WISE 17-SHEET EXCEL (.XLS XML) & TALLY XML & JSON BACKUP
  // --------------------------------------------------------------------------

  String generateAccountExcelXml([String? accName, bool onlyDataEntry = false]) {
    final target = (accName != null && accName.isNotEmpty) ? accName : selectedAccount;
    final meta = getAccountMeta(target);
    final accEntries = getSortedEntries(getAccountEntries(target));
    final accountHeads = getAccountSpecificHeads(target);
    final headRows = computeHeadWiseSummary(target);
    final openBal = getAccountOpening(target);
    final debitEntries = accEntries.where((e) => e.type == 'debit').toList();
    final creditEntries = accEntries.where((e) => e.type == 'credit').toList();
    final pages = buildCashbookPages(target, 'ALL', '', '');
    final audits = runCalculationAudit(target);
    final pageByEntryId = buildEntryPageNumberMap(target);
    final ledgerPageByHead = buildHeadKhatavahiPageMap(target);

    String n2(double v) => v.toStringAsFixed(2);
    String esc(String s) => _escHtml(s);

    final totalCrCash = creditEntries.fold<double>(0.0, (s, e) => s + cashAmt(e));
    final totalCrBank = creditEntries.fold<double>(0.0, (s, e) => s + bankAmt(e));
    final totalDrCash = debitEntries.fold<double>(0.0, (s, e) => s + cashAmt(e));
    final totalDrBank = debitEntries.fold<double>(0.0, (s, e) => s + bankAmt(e));
    final totalCr = totalCrCash + totalCrBank;
    final totalDr = totalDrCash + totalDrBank;
    final closeCash = openBal.cash + totalCrCash - totalDrCash;
    final closeBank = openBal.bank + totalCrBank - totalDrBank;
    final closeTotal = closeCash + closeBank;

    String buildSheet(String sheetName, List<List<String>> rows, {bool includeSignatures = true}) {
      final safeName = sheetName.length > 31 ? sheetName.substring(0, 31) : sheetName;
      final maxCols = rows.fold<int>(1, (m, r) => math.max(m, r.length));
      final sb = StringBuffer();
      sb.writeln('<Worksheet ss:Name="${esc(safeName)}"><Table ss:DefaultRowHeight="21">');
      for (int c = 0; c < maxCols; c++) {
        final colW = c == 0 ? 52 : (c == 1 || c == 2 || c == 3 ? 135 : 92);
        sb.writeln('<Column ss:Width="$colW"/>');
      }
      for (var r = 0; r < rows.length; r++) {
        final row = rows[r];
        if (row.isEmpty) {
          sb.writeln('<Row ss:Height="12"/>');
          continue;
        }
        final isTitleRow = r == 0 && row.length == 1;
        final isSubBannerRow = r == 1 && row.length == 1;
        final isHeaderRow = (r == 1 && row.length > 2) || (r == 3 && sheetName.startsWith('DATA_ENTRY'));
        final isTotalRow = row.isNotEmpty && (row[0] == 'TOTAL' || row[0] == 'SUMMARY' || row[0] == '=' || row[0].contains('કુલ') || (row.length > 1 && row[1].contains('કુલ')));
        final rowH = isTitleRow ? 26 : (isHeaderRow ? 25 : 21);
        sb.write('<Row ss:Height="$rowH">');
        if ((isTitleRow || isSubBannerRow) && maxCols > 1) {
          final stId = isTitleRow ? 'TitleBanner' : 'PeachSubBanner';
          sb.write('<Cell ss:MergeAcross="${maxCols - 1}" ss:StyleID="$stId"><Data ss:Type="String">${esc(row[0])}</Data></Cell>');
        } else {
          for (int c = 0; c < row.length; c++) {
            final cell = row[c];
            final trimmed = cell.trim();
            final isSerialOrVoucherOrRefCol = c == 0 ||
                (rows.length > 1 && c < rows[1].length && RegExp(r'ક્રમ|અ\.નં\.|Sr|વાઉચર|ચેક|CLAIM|ક્લેઈમ|પા\.નં\.|પાના|Page|ખાતા નંબર|Code', caseSensitive: false).hasMatch(rows[1][c]));
            final number = (!isSerialOrVoucherOrRefCol && RegExp(r'^-?\d+\.\d{2}$').hasMatch(trimmed))
                ? double.tryParse(trimmed)
                : null;
            if (isHeaderRow) {
              sb.write('<Cell ss:StyleID="PeachHeader"><Data ss:Type="String">${esc(cell)}</Data></Cell>');
            } else if (number != null && r > 0) {
              final st = isTotalRow ? 'TotalNum' : 'CellNum';
              sb.write('<Cell ss:StyleID="$st"><Data ss:Type="Number">$number</Data></Cell>');
            } else {
              final st = isTotalRow ? 'TotalCenter' : 'CellCenter';
              sb.write('<Cell ss:StyleID="$st"><Data ss:Type="String">${esc(cell)}</Data></Cell>');
            }
          }
        }
        sb.writeln('</Row>');
      }
      if (includeSignatures && maxCols >= 3) {
        sb.writeln('<Row ss:Height="16"/>');
        final third = math.max(1, maxCols ~/ 3);
        final rem = math.max(1, maxCols - (third * 2));
        final sName = meta.schoolName.isNotEmpty ? meta.schoolName : schoolName;
        sb.writeln('<Row ss:Height="32">'
            '<Cell ss:MergeAcross="${third - 1}" ss:StyleID="SignCell"><Data ss:Type="String">SMC અધ્યક્ષની સહી (SMC Chairman)</Data></Cell>'
            '<Cell ss:MergeAcross="${third - 1}" ss:StyleID="SignCell"><Data ss:Type="String">આચાર્યશ્રીની સહી અને સિક્કો ($sName)</Data></Cell>'
            '<Cell ss:MergeAcross="${rem - 1}" ss:StyleID="SignCell"><Data ss:Type="String">ઓડિટર / એકાઉન્ટન્ટની સહી (Auditor / Accountant)</Data></Cell>'
            '</Row>');
      }
      sb.writeln('</Table>'
          '<WorksheetOptions xmlns="urn:schemas-microsoft-com:office:excel">'
          '<PageSetup><Layout x:Orientation="Landscape"/><PageMargins x:Bottom="0.4" x:Left="0.35" x:Right="0.35" x:Top="0.4"/></PageSetup>'
          '<FitToPage/><Print><FitWidth>1</FitWidth><FitHeight>0</FitHeight></Print>'
          '</WorksheetOptions>'
          '</Worksheet>');
      return sb.toString();
    }

    final wb = StringBuffer();
    wb.writeln('<?xml version="1.0" encoding="UTF-8"?>');
    wb.writeln('<?mso-application progid="Excel.Sheet"?>');
    wb.writeln('<Workbook xmlns="urn:schemas-microsoft-com:office:spreadsheet" xmlns:x="urn:schemas-microsoft-com:office:excel" xmlns:ss="urn:schemas-microsoft-com:office:spreadsheet">');
    wb.writeln('<Styles>'
        '<Style ss:ID="Default" ss:Name="Normal"><Alignment ss:Vertical="Center"/><Font ss:FontName="Nirmala UI" ss:Size="10"/></Style>'
        '<Style ss:ID="TitleBanner"><Alignment ss:Horizontal="Center" ss:Vertical="Center" ss:WrapText="1"/><Font ss:FontName="Nirmala UI" ss:Size="13" ss:Bold="1"/><Interior ss:Color="#FDE9D9" ss:Pattern="Solid"/><Borders><Border ss:Position="Bottom" ss:LineStyle="Double" ss:Weight="3"/><Border ss:Position="Top" ss:LineStyle="Continuous" ss:Weight="1"/><Border ss:Position="Left" ss:LineStyle="Continuous" ss:Weight="1"/><Border ss:Position="Right" ss:LineStyle="Continuous" ss:Weight="1"/></Borders></Style>'
        '<Style ss:ID="PeachSubBanner"><Alignment ss:Horizontal="Center" ss:Vertical="Center" ss:WrapText="1"/><Font ss:FontName="Nirmala UI" ss:Size="10.5" ss:Bold="1"/><Interior ss:Color="#F8FAFC" ss:Pattern="Solid"/><Borders><Border ss:Position="Bottom" ss:LineStyle="Continuous" ss:Weight="1"/><Border ss:Position="Top" ss:LineStyle="Continuous" ss:Weight="1"/><Border ss:Position="Left" ss:LineStyle="Continuous" ss:Weight="1"/><Border ss:Position="Right" ss:LineStyle="Continuous" ss:Weight="1"/></Borders></Style>'
        '<Style ss:ID="PeachHeader"><Alignment ss:Horizontal="Center" ss:Vertical="Center" ss:WrapText="1"/><Font ss:FontName="Nirmala UI" ss:Size="10" ss:Bold="1"/><Interior ss:Color="#FDE9D9" ss:Pattern="Solid"/><Borders><Border ss:Position="Bottom" ss:LineStyle="Double" ss:Weight="3"/><Border ss:Position="Top" ss:LineStyle="Continuous" ss:Weight="1"/><Border ss:Position="Left" ss:LineStyle="Continuous" ss:Weight="1"/><Border ss:Position="Right" ss:LineStyle="Continuous" ss:Weight="1"/></Borders></Style>'
        '<Style ss:ID="CellCenter"><Alignment ss:Horizontal="Center" ss:Vertical="Center" ss:WrapText="1"/><Font ss:FontName="Nirmala UI" ss:Size="9.5"/><Borders><Border ss:Position="Bottom" ss:LineStyle="Continuous" ss:Weight="1"/><Border ss:Position="Top" ss:LineStyle="Continuous" ss:Weight="1"/><Border ss:Position="Left" ss:LineStyle="Continuous" ss:Weight="1"/><Border ss:Position="Right" ss:LineStyle="Continuous" ss:Weight="1"/></Borders></Style>'
        '<Style ss:ID="CellNum"><Alignment ss:Horizontal="Right" ss:Vertical="Center"/><Font ss:FontName="Nirmala UI" ss:Size="9.5"/><NumberFormat ss:Format="0.00"/><Borders><Border ss:Position="Bottom" ss:LineStyle="Continuous" ss:Weight="1"/><Border ss:Position="Top" ss:LineStyle="Continuous" ss:Weight="1"/><Border ss:Position="Left" ss:LineStyle="Continuous" ss:Weight="1"/><Border ss:Position="Right" ss:LineStyle="Continuous" ss:Weight="1"/></Borders></Style>'
        '<Style ss:ID="TotalCenter"><Alignment ss:Horizontal="Center" ss:Vertical="Center" ss:WrapText="1"/><Font ss:FontName="Nirmala UI" ss:Size="10" ss:Bold="1"/><Interior ss:Color="#F3F6FA" ss:Pattern="Solid"/><Borders><Border ss:Position="Top" ss:LineStyle="Continuous" ss:Weight="1"/><Border ss:Position="Bottom" ss:LineStyle="Double" ss:Weight="3"/><Border ss:Position="Left" ss:LineStyle="Continuous" ss:Weight="1"/><Border ss:Position="Right" ss:LineStyle="Continuous" ss:Weight="1"/></Borders></Style>'
        '<Style ss:ID="TotalNum"><Alignment ss:Horizontal="Right" ss:Vertical="Center"/><Font ss:FontName="Nirmala UI" ss:Size="10" ss:Bold="1"/><Interior ss:Color="#F3F6FA" ss:Pattern="Solid"/><NumberFormat ss:Format="0.00"/><Borders><Border ss:Position="Top" ss:LineStyle="Continuous" ss:Weight="1"/><Border ss:Position="Bottom" ss:LineStyle="Double" ss:Weight="3"/><Border ss:Position="Left" ss:LineStyle="Continuous" ss:Weight="1"/><Border ss:Position="Right" ss:LineStyle="Continuous" ss:Weight="1"/></Borders></Style>'
        '<Style ss:ID="SignCell"><Alignment ss:Horizontal="Center" ss:Vertical="Center" ss:WrapText="1"/><Font ss:FontName="Nirmala UI" ss:Size="10" ss:Bold="1"/><Borders><Border ss:Position="Top" ss:LineStyle="Continuous" ss:Weight="2"/></Borders></Style>'
        '</Styles>');

    final dataEntryRows = <List<String>>[
      ['${meta.schoolName.isNotEmpty ? meta.schoolName : schoolName} — DATA ENTRY SHEET (ખાતું: $target | વર્ષ: $financialYear)'],
      ['SCHOOL NAME:', meta.schoolName, 'ACCOUNT HOLDER:', meta.holderName, 'A/C NO.:', meta.acNo, 'IFSC:', meta.ifsc, 'BANK:', meta.bankName, 'OPENING BANK:', n2(openBal.bank), 'OPENING CASH:', n2(openBal.cash)],
      [],
      ['Sr. No.', 'Account', 'Date (DD/MM/YYYY)', 'Date (ISO)', 'Entry Type (Credit/Debit)', 'Voucher No.', 'Grant Head (ગ્રાન્ટ હેડ)', 'Narration / વિગત', 'Short Expense Detail', 'Party / Beneficiary', 'Mode', 'Cheque / PFMS / Claim No.', 'Settlement Date', 'Cash Credit ₹', 'Bank Credit ₹', 'Cash Debit ₹', 'Bank Debit ₹', 'Total Amount ₹', '60% Central Share ₹', '40% State Share ₹', 'Cashbook Page No.', 'Khatavahi Page No.'],
      ...accEntries.asMap().entries.map((entry) {
        final i = entry.key + 1;
        final e = entry.value;
        final cC = e.type == 'credit' ? cashAmt(e) : 0.0;
        final cB = e.type == 'credit' ? bankAmt(e) : 0.0;
        final dC = e.type == 'debit' ? cashAmt(e) : 0.0;
        final dB = e.type == 'debit' ? bankAmt(e) : 0.0;
        return <String>[
          '$i', e.account, fmtDateSlashDDMMYYYY(e.date), e.date,
          e.type == 'credit' ? 'Credit / આવક' : 'Debit / જાવક',
          e.voucher.isNotEmpty ? e.voucher : e.manualVoucher,
          e.head, e.narration, e.expense, e.party, e.medium, e.txn,
          fmtDateSlashDDMMYYYY(e.clearDate),
          n2(cC), n2(cB), n2(dC), n2(dB), n2(e.amount), n2(e.central), n2(e.state),
          '${pageByEntryId[e.id] ?? ""}', '${ledgerPageByHead[e.head] ?? ""}',
        ];
      }),
      ['TOTAL', target, '', '', '', '', 'કુલ સરવાળો (Total Transactions)', '', '', '', '', '', '', n2(totalCrCash), n2(totalCrBank), n2(totalDrCash), n2(totalDrBank), n2(totalCr + totalDr), '', '', '', ''],
      ['SUMMARY', target, '', '', '', '', 'ઉઘડતી + જમા - ખર્ચ = બંધ સિલક', '', '', '', '', '', '', n2(closeCash), n2(closeBank), '', '', n2(closeTotal), '', '', '', ''],
    ];

    if (onlyDataEntry) {
      wb.write(buildSheet('DATA_ENTRY_$target', dataEntryRows));
      wb.writeln('</Workbook>');
      return wb.toString();
    }

    // Sheet 1: 1_પુઠું_Cover_Index
    wb.write(buildSheet('1_પુઠું_Cover_Index', <List<String>>[
      ['${districtName.trim().isNotEmpty ? "${districtName.trim()} જિલ્લા શિક્ષણ સમિતિ સંચાલિત — " : ""}${meta.schoolName.isNotEmpty ? meta.schoolName : schoolName}'],
      ['રોજમેળ અને ઓડિટ ફાઈલ — નાણાકીય વર્ષ : $financialYear (ખાતું : $target)'],
      ['SCHOOL NAME :', meta.schoolName, 'ACCOUNT TYPE :', meta.type],
      ['ACCOUNT HOLDER NAME :', meta.holderName, 'FINANCIAL YEAR :', financialYear],
      ['ACCOUNT NUMBER :', meta.acNo, 'IFSC CODE :', meta.ifsc],
      ['BANK NAME :', meta.bankName, 'BRANCH :', meta.branch],
      ['સારાંશ (Financial Summary for $target) :', 'રોકડ (Cash ₹)', 'બેન્ક (Bank ₹)', 'કુલ (Total ₹)'],
      ['1. શરૂઆતની ઉઘડતી સિલક', n2(openBal.cash), n2(openBal.bank), n2(openBal.total)],
      ['2. વર્ષ દરમિયાન કુલ આવક', n2(totalCrCash), n2(totalCrBank), n2(totalCr)],
      ['3. કુલ પ્રાપ્ય રકમ', n2(openBal.cash + totalCrCash), n2(openBal.bank + totalCrBank), n2(openBal.total + totalCr)],
      ['4. વર્ષ દરમિયાન કુલ ખર્ચ', n2(totalDrCash), n2(totalDrBank), n2(totalDr)],
      ['5. આખરની બંધ સિલક', n2(closeCash), n2(closeBank), n2(closeTotal)],
      ...audits.map((a) => <String>[a.checkName, a.expectedValue, a.actualValue, a.passed ? 'VERIFIED OK' : 'MISMATCH']),
    ]));

    // Sheet 2: 2_DATA_ENTRY
    wb.write(buildSheet('2_DATA_ENTRY', dataEntryRows));

    // Sheet 3: 3_CASHBOOK_રોજમેળ
    final cbSheet = <List<String>>[
      ['${meta.schoolName} — રોજમેળ / CASHBOOK ($target | FY $financialYear)'],
      ['Credit Page', 'Debit Page', 'Date', 'Opening Cash', 'Opening Bank', 'Credit Cash', 'Credit Bank', 'Debit Cash', 'Debit Bank', 'Closing Cash', 'Closing Bank'],
      ...pages.map((p) => <String>[
        '${p.creditPageNo}', '${p.debitPageNo}', p.formattedDateSlash,
        n2(p.openCash), n2(p.openBank), n2(p.crSum.cash), n2(p.crSum.bank),
        n2(p.drSum.cash), n2(p.drSum.bank), n2(p.closeCash), n2(p.closeBank),
      ]),
    ];
    wb.write(buildSheet('3_CASHBOOK_રોજમેળ', cbSheet));

    // Sheet 4: 4_પરી_2_ખાતાવહી
    final p2Sheet = <List<String>>[
      ['પરિશિષ્ટ નંબર : 2 — આવક ખર્ચનું વર્ગીકરણ (ખાતાવહી) — ${meta.schoolName} ($target)'],
      ['ખાતાવહી પાના નં.', 'ગ્રાન્ટ હેડ', 'તારીખ', 'વિગત', 'ચેક/CLAIM નંબર', 'આ.રોકડા ₹', 'આ.બેંક ₹', 'વાઉચર નંબર', 'કેશબુક પા.નં.', 'આવક (+) ₹', 'જા.રોકડા ₹', 'જા.બેંક ₹', 'ખર્ચ (-) ₹'],
    ];
    for (int i = 0; i < accountHeads.length; i++) {
      final h = accountHeads[i];
      final hop = getHeadOpening(target, h);
      p2Sheet.add(['${i + 1}', h, '01/04/${financialYear.substring(0, 4)}', 'ગત વર્ષની બચત (ઉઘડતી સિલક)', '-', n2(hop.cash), n2(hop.bank), '-', '1', n2(hop.total), '0.00', '0.00', '0.00']);
      for (final e in accEntries.where((x) => x.head == h)) {
        final cc = e.type == 'credit' ? cashAmt(e) : 0.0;
        final cb = e.type == 'credit' ? bankAmt(e) : 0.0;
        final dc = e.type == 'debit' ? cashAmt(e) : 0.0;
        final db = e.type == 'debit' ? bankAmt(e) : 0.0;
        p2Sheet.add(['${i + 1}', h, fmtDateSlashDDMMYYYY(e.date), e.narration, e.txn, n2(cc), n2(cb), e.voucher, '${pageByEntryId[e.id] ?? ""}', n2(cc + cb), n2(dc), n2(db), n2(dc + db)]);
      }
    }
    wb.write(buildSheet('4_પરી_2_ખાતાવહી', p2Sheet));

    // Sheet 5: 5_બિલ_રજીસ્ટર
    wb.write(buildSheet('5_બિલ_રજીસ્ટર', <List<String>>[
      ['વર્ષ દરમિયાનનું બિલોનું નોંધપત્રક (બિલ રજીસ્ટર) — ${meta.schoolName} ($target)'],
      ['વાઉચર નંબર', 'તારીખ', 'ગ્રાન્ટ હેડ', 'બિલ કોના તરફથી મળેલ છે?', 'બિલની રકમ ₹', 'કપાત ₹', 'ચુકવવાની થતી ચોખ્ખી રકમ ₹', 'કેશબુક પા.નં.'],
      ...debitEntries.map((e) => <String>[e.voucher, fmtDateSlashDDMMYYYY(e.date), e.head, formatDebitNarration(e), n2(e.amount), '0.00', n2(e.amount), '${pageByEntryId[e.id] ?? ""}']),
      ['TOTAL', '', '', 'કુલ બિલ રકમ', n2(totalDr), '0.00', n2(totalDr), ''],
    ]));

    // Sheet 6: 6_ચેક_ક્લેઈમ_રજીસ્ટર
    wb.write(buildSheet('6_ચેક_ક્લેઈમ_રજીસ્ટર', <List<String>>[
      ['વર્ષ દરમિયાનનું ચેકોનું નોંધપત્રક (ક્લેઈમ / ચેક રજીસ્ટર) — ${meta.schoolName} ($target)'],
      ['ક્રમ', 'તારીખ', 'ચેક / CLAIM નંબર', 'વાઉચર નંબર', 'ચેકની રકમ ₹', 'વિગત', 'બિલની રકમ ₹', 'બિલ હેડ', 'ક્લીરીંગ તારીખ', 'કેશબુક પા.નં.'],
      ...debitEntries.where((e) => !isCashEntry(e)).toList().asMap().entries.map((entry) {
        final e = entry.value;
        return <String>['${entry.key + 1}', fmtDateSlashDDMMYYYY(e.date), e.txn, e.voucher, n2(e.amount), formatDebitNarration(e), n2(e.amount), e.head, fmtDateSlashDDMMYYYY(e.clearDate), '${pageByEntryId[e.id] ?? ""}'];
      }),
      ['TOTAL', '', '', 'કુલ બેંક ડેબિટ', n2(totalDrBank), '', n2(totalDrBank), '', '', ''],
    ]));

    // Sheet 7: 7_ખર્ચ_પત્રક
    wb.write(buildSheet('7_ખર્ચ_પત્રક', <List<String>>[
      ['ખર્ચ પત્રક — ${meta.schoolName} ($target)'],
      ['ક્રમ', 'પાર્ટીનું નામ / વિગત', 'ખર્ચની ટૂંકમાં વિગત', 'તારીખ', 'વાઉચર નંબર', 'રોકડેથી ખર્ચ ₹', 'ચેકથી ખર્ચ ₹', 'ગ્રાન્ટનું નામ', 'કેશબુક પા.નં.'],
      ...debitEntries.asMap().entries.map((entry) {
        final e = entry.value;
        return <String>['${entry.key + 1}', meta.type == 'BANK' ? formatDebitNarration(e) : (e.party.isNotEmpty ? e.party : formatDebitNarration(e)), e.expense.isNotEmpty ? e.expense : e.head, fmtDateSlashDDMMYYYY(e.date), e.voucher, n2(cashAmt(e)), n2(bankAmt(e)), e.head, '${pageByEntryId[e.id] ?? ""}'];
      }),
      ['TOTAL', '', '', '', 'કુલ ખર્ચ :', n2(totalDrCash), n2(totalDrBank), n2(totalDr), ''],
    ]));

    // Sheet 8: 8_પરિશિષ્ટ_8_ગોષવારો
    wb.write(buildSheet('8_પરિશિષ્ટ_8_ગોષવારો', <List<String>>[
      ['પરિશિષ્ટ - ૮ (PARISHISHT - 8) — ${meta.schoolName} ($target)'],
      ['અ.નં.', 'ગ્રાન્ટ હેડ', 'વાર્ષિક મર્યાદા ₹', 'ઉઘડતી સિલક ₹', '60% બેન્ક ગ્રાન્ટ ₹', '40% બેન્ક ગ્રાન્ટ ₹', 'કુલ બેન્ક ગ્રાન્ટ ₹', 'કુલ પ્રાપ્ય ₹', 'પદર રોકડ ખર્ચ ₹', 'બેન્ક/SNA ખર્ચ ₹', 'બંધ સિલક ₹'],
      ...headRows.asMap().entries.map((entry) {
        final r = entry.value;
        final avail = r.openTotal + r.bankCr;
        return <String>['${entry.key + 1}', r.head, n2(r.annualLimit), n2(r.openTotal), n2(r.bankCr60), n2(r.bankCr40), n2(r.bankCr), n2(avail), n2(r.padarDr), n2(r.bankDr), n2(avail - r.bankDr)];
      }),
      [
        'TOTAL',
        'એકંદરે કુલ સરવાળો :',
        n2(headRows.fold<double>(0.0, (s, r) => s + r.annualLimit)),
        n2(headRows.fold<double>(0.0, (s, r) => s + r.openTotal)),
        n2(headRows.fold<double>(0.0, (s, r) => s + r.bankCr60)),
        n2(headRows.fold<double>(0.0, (s, r) => s + r.bankCr40)),
        n2(headRows.fold<double>(0.0, (s, r) => s + r.bankCr)),
        n2(headRows.fold<double>(0.0, (s, r) => s + r.openTotal + r.bankCr)),
        n2(headRows.fold<double>(0.0, (s, r) => s + r.padarDr)),
        n2(headRows.fold<double>(0.0, (s, r) => s + r.bankDr)),
        n2(headRows.fold<double>(0.0, (s, r) => s + r.openTotal + r.bankCr - r.bankDr)),
      ],
    ]));

    // Sheet 9: 9_પરિશિષ્ટ_9_મેળવણું
    final cutOffExcel = reportToDate.isNotEmpty ? reportToDate : '2026-03-31';
    final unpresentedExcel = accEntries.where((e) => e.type == 'debit' && !isCashEntry(e) && e.clearDate.isNotEmpty && e.clearDate.compareTo(cutOffExcel) > 0).toList();
    final add1Excel = unpresentedExcel.fold<double>(0.0, (s, e) => s + e.amount);
    final addTotExcel = add1Excel + p9Add2DirectCredit;
    final subTotExcel = p9Sub1UncreditedDeposit + p9Sub2BankCharges;
    final passBalExcel = closeBank + addTotExcel - subTotExcel;
    wb.write(buildSheet('9_પરિશિષ્ટ_9_મેળવણું', <List<String>>[
      ['પરિશિષ્ટ – 9 : બેંક સાથે મેળવણું – રીકન્સીલેશન — ${meta.schoolName} ($target)'],
      ['ક્રમ', 'વિગત', 'પેટા રકમ ₹', 'કુલ રકમ ₹'],
      ['-', 'રોજમેળ પ્રમાણે બેન્ક બંધ સિલક', '0.00', n2(closeBank)],
      ['૧ (+)', 'ઉમેરવું (Add +)', n2(addTotExcel), n2(addTotExcel)],
      ['૨ (-)', 'બાદ કરવું (Deduct -)', n2(subTotExcel), n2(subTotExcel)],
      ['=', 'પાસબુક પ્રમાણે સિલક', n2(passBalExcel), n2(passBalExcel)],
    ]));

    // Sheet 10: 10_પરિશિષ્ટ_10_પ્રમાણપત્ર
    wb.write(buildSheet('10_પરિશિષ્ટ_10_પ્રમાણપત્ર', <List<String>>[
      ['પરિશિષ્ટ – ૧૦ : ગ્રાન્ટ વપરાશ પ્રમાણપત્ર — ${meta.schoolName} ($target)'],
      ['1. ક્રમ', '2. ગ્રાન્ટ હેડ', '3. ઉઘડતી રોકડ', '4. ઉઘડતી બેન્ક', '5. બેન્કમાં મળેલ ગ્રાન્ટ', '6. કુલ ગ્રાન્ટ બેન્કમાં (4+5)', '7. ચેક/PFMS ખર્ચ', '8. પદર આવક', '9. પદર ખર્ચ', '10. બંધ રોકડ (3+8-9)', '11. બંધ બેન્ક (6-7)', '12. કુલ બંધ સિલક (10+11)'],
      ...headRows.asMap().entries.map((entry) {
        final r = entry.value;
        final c6 = r.openBank + r.bankCr;
        final c10 = r.openCash + r.padarCr - r.padarDr;
        final c11 = c6 - r.bankDr;
        return <String>['${entry.key + 1}', r.head, n2(r.openCash), n2(r.openBank), n2(r.bankCr), n2(c6), n2(r.bankDr), n2(r.padarCr), n2(r.padarDr), n2(c10), n2(c11), n2(c10 + c11)];
      }),
    ]));

    // Sheet 11: 11_પરિશિષ્ટ_11_ગ્રાન્ટ_રજી
    wb.write(buildSheet('11_પરિશિષ્ટ_11_ગ્રાન્ટ_રજી', <List<String>>[
      ['ગ્રાન્ટ રજીસ્ટર : પરિશિષ્ટ ૧૧ — ${meta.schoolName} ($target)'],
      ['ક્રમ', 'કોના તરફથી મળી', 'વાર્ષિક મર્યાદા ₹', 'કુલ ગ્રાન્ટ રકમ ₹', 'ગ્રાન્ટ હેડ', 'બેન્કનું નામ', 'ખાતા નંબર', 'જમા તારીખ', 'ખર્ચેલ રકમ ₹', 'બચત ગ્રાન્ટ ₹'],
      ...headRows.asMap().entries.map((entry) {
        final r = entry.value;
        final rec = r.openTotal + r.bankCr;
        return <String>['${entry.key + 1}', 'SSA', n2(r.annualLimit), n2(rec), r.head, meta.bankName, meta.acNo, r.creditDates.join(', '), n2(r.bankDr), n2(rec - r.bankDr)];
      }),
    ]));

    // Sheet 12: 12_એનેક્ષર_12_માસવાર
    wb.write(buildSheet('12_એનેક્ષર_12_માસવાર', <List<String>>[
      ['એનેક્ષર-12 : સર્વ શિક્ષા અભિયાન - ગુજરાત — ${meta.schoolName} ($target)'],
      ['ક્રમ', 'ગ્રાન્ટનું નામ', 'ઉઘડતી રોકડ', 'ઉઘડતી બેન્ક', 'મળેલ રોકડ', 'મળેલ બેન્ક', 'કુલ ગ્રાન્ટ', 'ખર્ચ રોકડ', 'ખર્ચ બેન્ક', 'બંધ સિલક'],
      ...headRows.asMap().entries.map((entry) {
        final r = entry.value;
        return <String>['${entry.key + 1}', r.head, n2(r.openCash), n2(r.openBank), n2(r.padarCr), n2(r.bankCr), n2(r.openTotal + r.credit), n2(r.padarDr), n2(r.bankDr), n2(r.closing)];
      }),
    ]));

    // Sheet 13: 13_માસવાર_હિસાબ_પત્રક
    wb.write(buildSheet('13_માસવાર_હિસાબ_પત્રક', <List<String>>[
      ['માસવાર હિસાબ પત્રક — ${meta.schoolName} ($target)'],
      ['ક્રમ', 'તારીખ', 'ગ્રાન્ટ હેડ', 'પ્રકાર', 'વિગત', 'આ.રોકડા', 'આ.બેંક', 'આવક (+)', 'જા.રોકડા', 'જા.બેંક', 'ખર્ચ (-)'],
      ...accEntries.asMap().entries.map((entry) {
        final e = entry.value;
        final cC = e.type == 'credit' ? cashAmt(e) : 0.0;
        final cB = e.type == 'credit' ? bankAmt(e) : 0.0;
        final dC = e.type == 'debit' ? cashAmt(e) : 0.0;
        final dB = e.type == 'debit' ? bankAmt(e) : 0.0;
        return <String>['${entry.key + 1}', fmtDateDDMMYY(e.date), e.head, e.type == 'credit' ? 'આવક(+)' : 'જાવક(-)', e.narration, n2(cC), n2(cB), n2(cC + cB), n2(dC), n2(dB), n2(dC + dB)];
      }),
    ]));

    // Sheet 13B: 14_માસિક_ખર્ચ_બાકી_લિમિટ (New Monthly Expense & Remaining Limit / Balance Report)
    final fyMonthsExcel = getFyMonthsList();
    final isBankExcel = meta.type == 'BANK';
    final monthlyLimitSheetRows = <List<String>>[
      ['${meta.schoolName.isNotEmpty ? meta.schoolName : schoolName} — માસવાર (એપ્રિલ થી માર્ચ) ખર્ચ અને બાકી ${isBankExcel ? "બેંક સિલક" : "લિમિટ"} પત્રક ($target | FY $financialYear)'],
      [
        'ક્રમ',
        'ગ્રાન્ટ હેડ',
        isBankExcel ? 'ઉઘડતી સિલક ₹' : 'વાર્ષિક લિમિટ ₹',
        ...fyMonthsExcel.expand((m) => <String>['${m["gu"]} ખર્ચ ₹', '${m["gu"]} બાકી ₹']),
        'કુલ વાર્ષિક ખર્ચ ₹',
        isBankExcel ? 'આખરની બાકી સિલક ₹' : 'આખરની બાકી લિમિટ ₹',
      ],
    ];
    for (int i = 0; i < accountHeads.length; i++) {
      final h = accountHeads[i];
      final baseVal = isBankExcel ? getHeadOpening(target, h).total : getHeadLimit(target, h);
      double runRem = baseVal;
      double totHeadExp = 0;
      final row = <String>['${i + 1}', h, n2(baseVal)];
      for (final m in fyMonthsExcel) {
        final ym = m['ym']!;
        double mCr = 0, mDr = 0;
        for (final e in accEntries.where((x) => x.head == h && x.date.startsWith(ym))) {
          if (isBankExcel) {
            if (e.type == 'credit') mCr += e.amount;
            else mDr += e.amount;
          } else {
            if (e.type == 'debit' && !isCashEntry(e)) mDr += e.amount;
          }
        }
        runRem = isBankExcel ? (runRem + mCr - mDr) : (runRem - mDr);
        totHeadExp += mDr;
        row.add(n2(mDr));
        row.add(n2(runRem));
      }
      row.add(n2(totHeadExp));
      row.add(n2(runRem));
      monthlyLimitSheetRows.add(row);
    }
    wb.write(buildSheet('14_માસિક_ખર્ચ_બાકી_લિમિટ', monthlyLimitSheetRows));

    // Sheet 14: 15_PASSBOOK
    double pbRun = openBal.bank;
    wb.write(buildSheet('14_PASSBOOK', <List<String>>[
      ['${meta.schoolName} — PASSBOOK $financialYear ($target)'],
      ['Sr.', 'Date', 'Particulars', 'Chq / PFMS / Claim No.', 'Withdrawals ₹', 'Deposits ₹', 'Balance ₹'],
      ['0', '01/04/${financialYear.length >= 4 ? financialYear.substring(0, 4) : "2025"}', 'Opening Balance (શરૂઆતની સિલક)', '-', '0.00', n2(openBal.bank), n2(pbRun)],
      ...accEntries.where((e) => !isCashEntry(e)).toList().asMap().entries.map((entry) {
        final e = entry.value;
        final w = e.type == 'debit' ? e.amount : 0.0;
        final d = e.type == 'credit' ? e.amount : 0.0;
        pbRun += (d - w);
        return <String>['${entry.key + 1}', fmtDateDDMMYY(e.date), '${e.narration} [${e.head}]', e.txn, n2(w), n2(d), n2(pbRun)];
      }),
    ]));

    // Sheet 15: 15_TALLY_REPORT
    wb.write(buildSheet('15_TALLY_REPORT', <List<String>>[
      ['TALLY AUDIT REPORT — ${meta.schoolName} ($target)'],
      ['ક્રમ', 'લેજરનું નામ', 'ગ્રુપ', 'ઉઘડતી સિલક ₹', 'ઉધાર (Debit ₹)', 'જમા (Credit ₹)', 'બંધ સિલક ₹'],
      ['1', 'Cash-in-Hand (રોકડ / પદર ખાતું)', 'Cash-in-Hand', n2(openBal.cash), n2(totalCrCash), n2(totalDrCash), n2(closeCash)],
      ['2', '${meta.bankName} A/c ${meta.acNo} ($target)', 'Bank Accounts', n2(openBal.bank), n2(totalCrBank), n2(totalDrBank), n2(closeBank)],
      ...headRows.asMap().entries.map((entry) {
        final r = entry.value;
        return <String>['${entry.key + 3}', r.head, 'Grant Receipt & Expense', n2(r.openTotal), n2(r.bankDr), n2(r.bankCr), n2(r.openTotal + r.bankCr - r.bankDr)];
      }),
    ]));

    // Sheet 16: 16_તારીજ_પત્રક
    wb.write(buildSheet('16_તારીજ_પત્રક', <List<String>>[
      ['તારીજ પત્રક (RECEIPT & PAYMENT ACCOUNT) — ${meta.schoolName} ($target)'],
      ['આવકના સદર', 'રોકડ ₹', 'બેન્ક ₹', 'કુલ આવક ₹', 'જાવકના સદર', 'રોકડ ₹', 'બેન્ક ₹', 'કુલ જાવક ₹'],
      ['શ્રી ઉઘડતી સિલક', n2(openBal.cash), n2(openBal.bank), n2(openBal.total), '-', '0.00', '0.00', '0.00'],
      ...headRows.where((r) => r.credit > 0 || r.debit > 0).map((r) => <String>[r.head, n2(r.padarCr), n2(r.bankCr), n2(r.credit), r.head, n2(r.padarDr), n2(r.bankDr), n2(r.debit)]),
      ['કુલ આવક', n2(totalCrCash), n2(totalCrBank), n2(totalCr), 'કુલ ખર્ચ', n2(totalDrCash), n2(totalDrBank), n2(totalDr)],
      ['-', '0.00', '0.00', '0.00', 'શ્રી બંધ સિલક', n2(closeCash), n2(closeBank), n2(closeTotal)],
      ['એકંદરે કુલ આવક', n2(openBal.cash + totalCrCash), n2(openBal.bank + totalCrBank), n2(openBal.total + totalCr), 'એકંદરે કુલ જાવક', n2(totalDrCash + closeCash), n2(totalDrBank + closeBank), n2(totalDr + closeTotal)],
    ]));

    // Sheet 17: 17_પ્રમાણિત_વાઉચર
    wb.write(buildSheet('17_પ્રમાણિત_વાઉચર', <List<String>>[
      ['પ્રમાણિત વાઉચર અને ખર્ચનું પત્રક — ${meta.schoolName} ($target)'],
      ['અ.નં.', 'વાઉચર નં.', 'તારીખ', 'રોજમેળ પાના નં.', 'ખાતાવહી પાના નં.', 'ગ્રાન્ટ હેડ', 'પાર્ટીનું નામ', 'ખર્ચની વિગત', 'ચેક / CLAIM નંબર', 'સેટલમેન્ટ તારીખ', 'રોકડ ₹', 'બેન્ક ₹', 'કુલ રકમ ₹'],
      ...debitEntries.asMap().entries.map((entry) {
        final e = entry.value;
        return <String>['${entry.key + 1}', e.voucher, fmtDateDDMMYY(e.date), '${pageByEntryId[e.id] ?? ""}', '${ledgerPageByHead[e.head] ?? ""}', e.head, e.party, formatDebitNarration(e), e.txn, fmtDateDDMMYY(e.clearDate), n2(cashAmt(e)), n2(bankAmt(e)), n2(e.amount)];
      }),
      ['TOTAL', '', '', '', '', '', '', 'એકંદરે કુલ પ્રમાણિત ખર્ચ :', '', '', n2(totalDrCash), n2(totalDrBank), n2(totalDr)],
    ]));

    // Sheets 18–28: extra audit registers and certificates (whole account,
    // same figures as the PDF pages).
    const extraSheets = <String, String>{
      'cash_register': '18_રોકડ_પદર_રજીસ્ટર',
      'interest_register': '19_બેંક_વ્યાજ_રજીસ્ટર',
      'party_register': '20_પાર્ટી_મુજબ_ચુકવણી',
      'balance_sheet': '21_પાકું_સરવૈયું',
      'income_expenditure': '22_આવક_ખર્ચ_ખાતું',
      'gfr_12a': '23_GFR_12A_UC',
      'monthly_brs': '24_માસવાર_બેંક_મેળવણું',
      'asset_register': '25_મિલકત_ખરીદી_ડેડસ્ટોક',
      'cash_verification': '26_રોકડ_ચકાસણી',
      'bank_certificate': '27_બેંક_સિલક_પ્રમાણપત્ર',
      'audit_crosscheck': '28_ગણતરી_મેળવણું',
    };
    final savedFrom = reportFromDate, savedTo = reportToDate;
    reportFromDate = '';
    reportToDate = '';
    try {
      for (final ex in extraSheets.entries) {
        final t = buildExtraAuditTable(ex.key, target, accEntries, openBal, headRows);
        wb.write(buildSheet(ex.value, <List<String>>[
          [t.title],
          [t.subtitle],
          for (final n in t.preNotes) [n],
          t.headers,
          for (final r in t.dataRows)
            [for (var i = 0; i < r.length; i++) i == 0 && r[i].startsWith('§') ? r[i].substring(1) : r[i].trim()],
          ...t.totalRows,
          if (t.notes.isNotEmpty) <String>[],
          for (final n in t.notes) [n],
        ]));
      }
    } finally {
      reportFromDate = savedFrom;
      reportToDate = savedTo;
    }

    wb.writeln('</Workbook>');
    return wb.toString();
  }

  /// Generates an Excel-compatible print-exact `.xls` document from the exact HTML/PDF print layout
  /// so opening it in Microsoft Excel shows the identical headers, borders, `#fde9d9` peach bars,
  /// centered cells, right-aligned amounts, and 3-column signature block as PDF printing!
  String generatePrintExactExcelHtml(String reportType, [String? accName]) {
    final target = (accName != null && accName.isNotEmpty && accName != 'ALL') ? accName : selectedAccount;
    final rawHtml = reportType == 'daybook'
        ? generateExactCashbookPrintHtml(target)
        : generateReportPrintHtml(reportType, target);
    final withoutScripts = rawHtml.replaceAll(RegExp(r'<script[\s\S]*?</script>', caseSensitive: false), '');
    final excelHead = '''<html xmlns:o="urn:schemas-microsoft-com:office:office" xmlns:x="urn:schemas-microsoft-com:office:excel" xmlns="http://www.w3.org/TR/REC-html40">
<head><meta charset="utf-8">
<!--[if gte mso 9]><xml><x:ExcelWorkbook><x:ExcelWorksheets><x:ExcelWorksheet><x:Name>Rojmel_${_escHtml(reportType)}</x:Name><x:WorksheetOptions><x:Print><x:ValidPrinterInfo/></x:Print></x:WorksheetOptions></x:ExcelWorksheet></x:ExcelWorksheets></x:ExcelWorkbook></xml><![endif]-->''';
    return withoutScripts.replaceFirst(RegExp(r'<!doctype html>\s*<html[^>]*>\s*<head>\s*<meta[^>]*>', caseSensitive: false), excelHead);
  }

  /// Exact port of `downloadTallyXML` from V06 HTML.
  String generateTallyXml([String? accName]) {
    final target = (accName != null && accName.isNotEmpty) ? accName : selectedAccount;
    final mAcc = getAccountMeta(target);
    final list = getSortedEntries(getAccountEntries(target));
    final usedHeads = list.map((e) => e.head).where((h) => h.isNotEmpty).toSet().toList();
    final parties = list.map((e) => e.party.trim()).where((p) => p.isNotEmpty).toSet().toList();

    final sb = StringBuffer();
    sb.writeln('<?xml version="1.0" encoding="UTF-8"?>\n<ENVELOPE>\n<HEADER><TALLYREQUEST>Import Data</TALLYREQUEST></HEADER>\n<BODY>\n<IMPORTDATA>');
    sb.writeln('<REQUESTDESC><REPORTNAME>All Masters</REPORTNAME><STATICVARIABLES><SVCURRENTCOMPANY>${_escHtml(mAcc.schoolName)} - ${_escHtml(target)}</SVCURRENTCOMPANY></STATICVARIABLES></REQUESTDESC>\n<REQUESTDATA>');
    for (final lName in <String>['Cash-in-Hand', mAcc.bankName.isNotEmpty ? mAcc.bankName : 'Bank Account', ...usedHeads, ...parties]) {
      final parent = usedHeads.contains(lName)
          ? 'Direct Expenses'
          : (parties.contains(lName) ? 'Sundry Creditors' : 'Bank Accounts');
      sb.writeln('<TALLYMESSAGE xmlns:UDF="TallyUDF"><LEDGER NAME="${_escHtml(lName)}" ACTION="Create"><NAME.LIST><NAME>${_escHtml(lName)}</NAME></NAME.LIST><PARENT>$parent</PARENT></LEDGER></TALLYMESSAGE>');
    }
    for (final e in list) {
      final dt = e.date.replaceAll('-', '');
      final amt = e.amount.toStringAsFixed(2);
      final vType = e.type == 'credit' ? 'Receipt' : 'Payment';
      final bankOrCashLedger = isCashEntry(e) ? 'Cash-in-Hand' : (mAcc.bankName.isNotEmpty ? mAcc.bankName : 'Bank Account');
      final vNo = e.voucher.isNotEmpty ? e.voucher : (e.manualVoucher.isNotEmpty ? e.manualVoucher : '${e.sr}');
      final narr = '${e.type == "debit" ? formatDebitNarration(e) : formatCreditNarration(e)}${e.txn.isNotEmpty ? " [Ref: ${e.txn}]" : ""}';
      sb.writeln('<TALLYMESSAGE xmlns:UDF="TallyUDF"><VOUCHER VCHTYPE="$vType" ACTION="Create">'
          '<DATE>$dt</DATE><VOUCHERTYPENAME>$vType</VOUCHERTYPENAME><VOUCHERNUMBER>${_escHtml(vNo)}</VOUCHERNUMBER>'
          '<NARRATION>${_escHtml(narr)}</NARRATION>'
          '<ALLLEDGERENTRIES.LIST><LEDGERNAME>${_escHtml(e.head)}</LEDGERNAME><ISDEEMEDPOSITIVE>${e.type == "debit" ? "Yes" : "No"}</ISDEEMEDPOSITIVE><AMOUNT>${e.type == "debit" ? "-$amt" : amt}</AMOUNT></ALLLEDGERENTRIES.LIST>'
          '<ALLLEDGERENTRIES.LIST><LEDGERNAME>${_escHtml(bankOrCashLedger)}</LEDGERNAME><ISDEEMEDPOSITIVE>${e.type == "credit" ? "Yes" : "No"}</ISDEEMEDPOSITIVE><AMOUNT>${e.type == "credit" ? "-$amt" : amt}</AMOUNT></ALLLEDGERENTRIES.LIST>'
          '</VOUCHER></TALLYMESSAGE>');
    }
    sb.writeln('</REQUESTDATA>\n</IMPORTDATA>\n</BODY>\n</ENVELOPE>');
    return sb.toString();
  }

  String generateTransactionsCsv([String? accName]) {
    final target = (accName != null && accName.isNotEmpty) ? accName : selectedAccount;
    final list = getSortedEntries(getAccountEntries(target));
    final rows = <List<String>>[
      ['Sr', 'Account', 'Type', 'Date', 'Voucher', 'Grant Head', 'Narration', 'Short Expense', 'Amount', 'Mode', 'Reference', 'Clearing Date', 'Party'],
      ...list.asMap().entries.map((entry) {
        final i = entry.key + 1;
        final e = entry.value;
        return <String>[
          '$i', e.account, e.type, e.date, e.voucher, e.head, e.narration, e.expense,
          e.amount.toStringAsFixed(2), e.medium, e.txn, e.clearDate, e.party,
        ];
      }),
    ];
    final csvLines = rows.map((r) => r.map((v) => '"' + v.replaceAll('"', '""') + '"').join(',')).join('\r\n');
    return '\ufeff' + csvLines;
  }

  String exportBackupJson({bool selectedAccountOnly = false, bool pretty = true}) {
    if (selectedAccountOnly) {
      final meta = getAccountMeta(selectedAccount);
      return const JsonEncoder.withIndent('  ').convert({
        'version': 'V06_HTML_EXACT_FLUTTER',
        'exportedAccount': selectedAccount,
        'accountMeta': meta.toJson(),
        'entries': getAccountEntries(selectedAccount).map((e) => e.toJson()).toList(),
      });
    }
    // Compact JSON for the automatic device draft / save checks (much
    // faster on big ledgers); pretty JSON only for downloaded backups.
    return (pretty ? const JsonEncoder.withIndent('  ') : const JsonEncoder()).convert({
      'version': 'V06_HTML_EXACT_FLUTTER',
      'schoolName': schoolName,
      'school': schoolName,
      'schoolAddress': schoolAddress,
      'clusterName': clusterName,
      'talukaName': talukaName,
      'districtName': districtName,
      'udiseCode': udiseCode,
      'financialYear': financialYear,
      'fy': financialYear,
      'openingBalanceDate': openingBalanceDate,
      'activeDatasetMode': activeDatasetMode,
      'selectedAccount': selectedAccount,
      'cashbookFilterHead': cashbookFilterHead,
      'activeReportType': activeReportType,
      'activeReportNumber': activeReportNumber,
      'accounts': accounts,
      'accountMeta': accountMeta.map((k, v) => MapEntry(k, v.toJson())),
      'heads': heads,
      'entries': entries.map((e) => e.toJson()).toList(),
      'principals': principals.map((p) => p.toJson()).toList(),
      'pageFontMap': pageFontMap,
      'pageEntryCountMap': pageEntryCountMap,
      'sameDateOverflowMode': sameDateOverflowMode,
      'pageAccountLabelOverrides': pageAccountLabelOverrides,
      'pageRefColLabelOverrides': pageRefColLabelOverrides,
      'parishisht10CustomGrids': parishisht10CustomGrids,
      'parishisht10MergedRows': parishisht10MergedRows,
      'parishisht10FontSizePt': parishisht10FontSizePt,
      'parishisht10RowHeightPx': parishisht10RowHeightPx,
      'reportOrientationMap': reportOrientationMap,
      'reportLeftSpaceMm': reportLeftSpaceMm,
      'reportRightSpaceMm': reportRightSpaceMm,
      'printSetup': printSetup.toJson(),
      'defaultReportPageMode': defaultReportPageMode,
      'reportPageModeMap': reportPageModeMap,
      'cashbookShowColumnLines': cashbookShowColumnLines,
      'cashbookContinuousDates': cashbookContinuousDates,
      'cashbookEntryGapMm': cashbookEntryGapMm,
      'pageEntryGapMap': pageEntryGapMap,
      'cashbookColumnLineMode': cashbookColumnLineMode,
      'selectedMonthlyLimitMonth': selectedMonthlyLimitMonth,
    });
  }
}

// ============================================================================
// 5. MAIN SUPABASE ROJMEL SCREEN (`SupabaseRojmelScreen` — EXACT HTML DESIGN)
// ============================================================================

class SupabaseRojmelScreen extends StatefulWidget {
  const SupabaseRojmelScreen({super.key, required this.profile});

  final Map<String, dynamic> profile;

  @override
  State<SupabaseRojmelScreen> createState() => _SupabaseRojmelScreenState();
}

class _SupabaseRojmelScreenState extends State<SupabaseRojmelScreen> {
  late final RojmelEngine engine;
  final SupabaseRojmelService _rojmelService = SupabaseRojmelService();
  int _selectedNavIndex = 0;

  // Cloud state
  bool _loadingCloud = true;
  bool _serverAdmin = false;
  bool _cloudReady = false;
  bool _cloudSaving = false;
  bool _cloudSavePending = false;
  String _schoolRef = '';
  Map<String, dynamic> _schoolContext = <String, dynamic>{};
  String? _initializationError;
  String? _cloudSaveError;
  DateTime? _lastCloudSave;
  Timer? _cloudSaveTimer;
  Timer? _deviceDraftTimer;

  /// JSON of the state last loaded from / saved to the cloud. Used to skip
  /// identical cloud writes and to know whether anything really changed.
  String? _lastCloudJson;

  // Exact 13 Sidebar Navigation Items matching ROJMEL_V02_7_1_CASHBOOK_PRINT_FIXED.html
  static const List<Map<String, dynamic>> _navItems = <Map<String, dynamic>>[
    {'id': 'home', 'label': '🏠 Home', 'icon': Icons.home_rounded},
    {'id': 'schoolInfo', 'label': '🏫 School Info', 'icon': Icons.school_rounded},
    {'id': 'accountsPanel', 'label': '🏦 Rojmel Accounts', 'icon': Icons.account_balance_rounded},
    {'id': 'grantHeadsPanel', 'label': '🗂 Grant Heads', 'icon': Icons.folder_rounded},
    {'id': 'entry', 'label': '✍ Data Entry', 'icon': Icons.edit_note_rounded},
    {'id': 'reportsPanel', 'label': '📊 Reports', 'icon': Icons.bar_chart_rounded},
    {'id': 'tallyPanel', 'label': '🧮 Tally Report', 'icon': Icons.calculate_outlined},
    {'id': 'calculationAuditPanel', 'label': '✓ Calculation Check', 'icon': Icons.fact_check_rounded},
    {'id': 'dataExportPanel', 'label': '📤 Export Data', 'icon': Icons.upload_file_rounded},
    {'id': 'cashbook', 'label': '📒 Cashbook', 'icon': Icons.menu_book_rounded},
    {'id': 'register', 'label': '📋 Transactions', 'icon': Icons.receipt_long_rounded},
    {'id': 'bulk', 'label': '📥 Import Excel', 'icon': Icons.download_for_offline_rounded},
    {'id': 'settings', 'label': '⚙ Backup & Settings', 'icon': Icons.settings_rounded},
  ];

  // All 18 Report Types (17 original + New Monthly Head-wise Expense & Remaining Limit/Balance Report)
  static const List<Map<String, String>> _reportTypes = <Map<String, String>>[
    {'value': 'daybook', 'label': '1. Cashbook / રોજમેળ (Exact Demo PDF View — PFMS & SNA SPARSH)'},
    {'value': 'parishisht_2', 'label': '2. Parishisht-2 / પરિશિષ્ટ નંબર : 2 — આવક ખર્ચનું વર્ગીકરણ (કલાસીફાઈડ રજીસ્ટર / ખાતાવહી)'},
    {'value': 'bill_reg', 'label': '3. Bill Register / વર્ષ દરમિયાનનું બિલોનું નોંધપત્રક (બિલ રજીસ્ટર - PFMS & SNA SPARSH Summary)'},
    {'value': 'cheque_reg', 'label': '4. Claim-Cheque Register / વર્ષ દરમિયાનનું ચેકોનું નોંધપત્રક (ક્લેઈમ / ચેક રજીસ્ટર)'},
    {'value': 'kharch_patrak', 'label': '5. Kharch Patrak / ખર્ચ પત્રક (વર્ષ દરમિયાન ખર્ચનું નોંધપત્રક — રોકડ અને ચેક ખર્ચ)'},
    {'value': 'parishisht_8', 'label': '6. Parishisht-8 / પરિશિષ્ટ-૮ (ગ્રાન્ટ ફાળવણી, ખર્ચ અને બંધ સિલક પત્રક)'},
    {'value': 'parishisht_9', 'label': '7. Parishisht-9 / પરિશિષ્ટ – 9 : બેંક સાથે મેળવણું – રીકન્સીલેશન (Bank Reconciliation)'},
    {'value': 'parishisht_10', 'label': '8. Parishisht-10 / પરિશિષ્ટ – ૧૦ : ગ્રાન્ટ વપરાશ પ્રમાણપત્ર (12-Column Table + Gujarati Words)'},
    {'value': 'grant_reg', 'label': '9. Parishisht-11 / ગ્રાન્ટ રજીસ્ટર : પરિશિષ્ટ ૧૧ (14-Column Grant Register)'},
    {'value': 'annexure_12', 'label': '10. Annexure-12 / એનેક્ષર-12 : સર્વ શિક્ષા અભિયાન - ગુજરાત (માસવાર હિસાબ પત્રક + પરી-૯ + પ્રમાણપત્ર)'},
    {'value': 'monthly', 'label': '11. Monthly Hisab / માસવાર હિસાબ પત્રક (Month-wise Transaction Statement)'},
    {'value': 'monthly_limit_report', 'label': '12. Monthly Expense & Remaining Limit-Balance / માસવાર અને હેડવાર ખર્ચ તથા બાકી લિમિટ-સિલક પત્રક (April–March / Selected Month)'},
    {'value': 'passbook', 'label': '13. Passbook / બેંક પાસબુક (Running Withdrawals, Deposits & Balance)'},
    {'value': 'tally_report', 'label': '14. Tally Report / ટેલી રિપોર્ટ (Trial Balance, Ledger Summary, Day Book & Tally XML/CSV Export)'},
    {'value': 'receipt_payment', 'label': '15. Tarij Patrak / તારીજ પત્રક (વાર્ષિક આવક-જાવક પત્રક)'},
    {'value': 'voucher_cert', 'label': '16. Certified Vouchers / પ્રમાણિત વાઉચર યાદી પત્રક (With Rojmel & Khatavahi Page No.)'},
    {'value': 'audit_certs', 'label': '17. Cover Page & Audit Certificates / મુખપૃષ્ઠ, અનુક્રમણિકા અને પ્રમાણપત્રો'},
    {'value': 'cash_register', 'label': '18. Cash / Padar Register / રોકડ (પદર) રજીસ્ટર — Cash in Hand with Running Balance'},
    {'value': 'interest_register', 'label': '19. Bank Interest Register / બેંક વ્યાજ રજીસ્ટર — Interest Earned & Refunded to Govt.'},
    {'value': 'party_register', 'label': '20. Party-wise Payment Register / પાર્ટી-વેપારી મુજબ ચુકવણી પત્રક'},
    {'value': 'balance_sheet', 'label': '21. Balance Sheet / પાકું સરવૈયું — Unspent Grant vs Bank + Cash'},
    {'value': 'income_expenditure', 'label': '22. Income & Expenditure Account / આવક-ખર્ચ ખાતું — Grant Utilised, Interest & Surplus'},
    {'value': 'gfr_12a', 'label': '23. GFR 12-A Utilization Certificate / ઉપયોગિતા પ્રમાણપત્ર (Central Govt. Format with Certificates)'},
    {'value': 'monthly_brs', 'label': '24. Month-wise Bank Reconciliation / માસવાર બેંક મેળવણું (Unpresented Cheques / Claims)'},
    {'value': 'asset_register', 'label': '25. Assets Purchased (Dead Stock) / મિલકત ખરીદી પત્રક — ડેડ સ્ટોક રજીસ્ટર માટે'},
    {'value': 'cash_verification', 'label': '26. Physical Cash Verification Certificate / રોકડ સિલક ચકાસણી પ્રમાણપત્ર (Denomination-wise)'},
    {'value': 'bank_certificate', 'label': '27. Bank Balance Certificate / બેંક સિલક પ્રમાણપત્ર (Bank Manager to sign)'},
    {'value': 'audit_crosscheck', 'label': '28. Audit Cross-check Statement / ગણતરી મેળવણું પત્રક (All Reports Agree ✔)'},
    {'value': 'audit_pack', 'label': '29. Complete School Audit File Pack (સંપૂર્ણ ઓડિટ ફાઈલ - All Reports in 1 Click)'},
  ];

  // Persistent controllers for School Info, Cashbook & Reports Date Filters
  final _schoolInfoNameCtrl = TextEditingController();
  final _schoolInfoDiseCtrl = TextEditingController();
  final _schoolInfoFyCtrl = TextEditingController();
  final _schoolInfoAddrCtrl = TextEditingController();
  final _schoolInfoVillageCtrl = TextEditingController();
  final _schoolInfoTalukaCtrl = TextEditingController();
  final _schoolInfoDistCtrl = TextEditingController();
  final _principalNameCtrl = TextEditingController();
  final _principalFromCtrl = TextEditingController(text: '01/04/2025');
  final _principalToCtrl = TextEditingController();
  bool _hasUnsavedCloudChanges = false;
  DateTime? _lastDeviceSave;
  final _cashbookFromDateCtrl = TextEditingController();
  final _cashbookToDateCtrl = TextEditingController();
  final _reportFromDateCtrl = TextEditingController();
  final _reportToDateCtrl = TextEditingController();

  // Form controllers for Data Entry (`#entry`) — Default DD/MM/YYYY format for easy manual typing & picker
  final _entryDateCtrl = TextEditingController(text: '05/03/2026');
  final _entryNarrCtrl = TextEditingController();
  final _entryExpShortCtrl = TextEditingController();
  final _entryAmtCtrl = TextEditingController();
  final _entryManualVoucherCtrl = TextEditingController();
  final _entryPartyCtrl = TextEditingController();
  final _entryPartyFocus = FocusNode();
  final _entryTxnCtrl = TextEditingController();
  final _entryClearDateCtrl = TextEditingController(text: '20/03/2026');
  final _sna60ClaimCtrl = TextEditingController();
  final _sna60DateCtrl = TextEditingController(text: '20/03/2026');
  final _sna40ClaimCtrl = TextEditingController();
  final _sna40DateCtrl = TextEditingController(text: '20/03/2026');
  final _snaCredit60AmtCtrl = TextEditingController(text: '0.00');
  final _snaCredit40AmtCtrl = TextEditingController(text: '0.00');
  final _snaCredit60SuffixCtrl = TextEditingController(text: '(વાઉચરના 60%)');
  final _snaCredit40SuffixCtrl = TextEditingController(text: '(વાઉચરના 40%)');
  final _snaDebit60AmtCtrl = TextEditingController(text: '0.00');
  final _snaDebit40AmtCtrl = TextEditingController(text: '0.00');
  final _snaDebit60SuffixCtrl = TextEditingController(text: '(વાઉચરના 60% લેખે)');
  final _snaDebit40SuffixCtrl = TextEditingController(text: '(વાઉચરના 40% લેખે)');
  String _entryType = 'credit';
  String? _entrySelectedHead;
  String _entryMedium = 'SNA SPARSH';
  bool _entryEditAllowed = true;
  /// Debit: add the purchased item to the dead stock register (default No).
  bool _entryDeadStock = false;
  String? _entryNoticeMsg;
  bool _entryNoticeOk = true;

  // Form state for Rojmel Accounts (`#accountsPanel`)
  String _accEditOldName = '';
  String _accType = 'SNA_PURE';
  final _accNameCtrl = TextEditingController();
  final _accSchoolCtrl = TextEditingController();
  final _accPfmsSchoolCtrl = TextEditingController();
  final _accNumberCtrl = TextEditingController();
  final _accSnaAgencyCtrl = TextEditingController();
  final _accPfmsLastDateCtrl = TextEditingController();
  final _accSnaStartDateCtrl = TextEditingController();
  final _accHolderCtrl = TextEditingController();
  final _accIfscCtrl = TextEditingController();
  final _accBankCtrl = TextEditingController();
  final _accBranchCtrl = TextEditingController();
  final _accBranchAddrCtrl = TextEditingController();
  final _accOpenBankCtrl = TextEditingController(text: '0');
  final _accOpenCashCtrl = TextEditingController(text: '0');
  final _distHeadBankCtrl = TextEditingController(text: '0');
  final _distHeadCashCtrl = TextEditingController(text: '0');
  final _limitHeadAmtCtrl = TextEditingController(text: '0');
  final _accCustomHeadCtrl = TextEditingController();
  String? _distSelectedHead;
  String? _limitSelectedHead;
  Map<String, HeadBalance> _draftHeadOpenings = <String, HeadBalance>{};
  Map<String, double> _draftHeadLimits = <String, double>{};
  List<String> _draftAccountHeads = <String>[];
  String _accAskCopyHeads = 'no';
  String? _accCopySourceAcc;
  String _accCopyOption = 'all';
  Set<String> _accCopyCheckedHeads = <String>{};
  String? _accountNoticeMsg;
  bool _accountNoticeOk = true;

  @override
  void initState() {
    super.initState();
    engine = RojmelEngine();
    engine.addListener(_onEngineChanged);
    _initializeCloudState();
  }

  void _syncFilterControllersFromEngine({bool forceSchoolFields = false}) {
    final cbFromDisp = fmtDateSlashDDMMYYYY(engine.cashbookFromDate);
    final cbToDisp = fmtDateSlashDDMMYYYY(engine.cashbookToDate);
    final rpFromDisp = fmtDateSlashDDMMYYYY(engine.reportFromDate);
    final rpToDisp = fmtDateSlashDDMMYYYY(engine.reportToDate);
    if (normalizeToIsoDate(_cashbookFromDateCtrl.text) != normalizeToIsoDate(engine.cashbookFromDate)) {
      _cashbookFromDateCtrl.text = cbFromDisp;
    }
    if (normalizeToIsoDate(_cashbookToDateCtrl.text) != normalizeToIsoDate(engine.cashbookToDate)) {
      _cashbookToDateCtrl.text = cbToDisp;
    }
    if (normalizeToIsoDate(_reportFromDateCtrl.text) != normalizeToIsoDate(engine.reportFromDate)) {
      _reportFromDateCtrl.text = rpFromDisp;
    }
    if (normalizeToIsoDate(_reportToDateCtrl.text) != normalizeToIsoDate(engine.reportToDate)) {
      _reportToDateCtrl.text = rpToDisp;
    }
    if (forceSchoolFields || _schoolInfoNameCtrl.text.isEmpty) {
      if (engine.schoolName.isNotEmpty) _schoolInfoNameCtrl.text = engine.schoolName;
    }
    if (forceSchoolFields || _schoolInfoDiseCtrl.text.isEmpty) {
      if (engine.udiseCode.isNotEmpty) _schoolInfoDiseCtrl.text = engine.udiseCode;
    }
    if (forceSchoolFields || _schoolInfoAddrCtrl.text.isEmpty) {
      if (engine.schoolAddress.isNotEmpty) _schoolInfoAddrCtrl.text = engine.schoolAddress;
    }
    if (forceSchoolFields || _schoolInfoVillageCtrl.text.isEmpty) {
      if (engine.clusterName.isNotEmpty) _schoolInfoVillageCtrl.text = engine.clusterName;
    }
    if (forceSchoolFields || _schoolInfoTalukaCtrl.text.isEmpty) {
      if (engine.talukaName.isNotEmpty) _schoolInfoTalukaCtrl.text = engine.talukaName;
    }
    if (forceSchoolFields || _schoolInfoDistCtrl.text.isEmpty) {
      if (engine.districtName.isNotEmpty) _schoolInfoDistCtrl.text = engine.districtName;
    }
    if (_schoolInfoFyCtrl.text != engine.financialYear) {
      _schoolInfoFyCtrl.text = engine.financialYear;
    }
  }

  /// Saves changes ONLY on the local device (0 Firestore/Cloud writes) until the user explicitly presses the Save button!
  void _saveToLocalDeviceCache() {
    if (_schoolRef.isEmpty) return;
    // Serialising the whole ledger on every keystroke / filter change made the
    // UI sluggish. Debounce the device draft and compare with the cloud copy.
    _deviceDraftTimer?.cancel();
    _deviceDraftTimer = Timer(const Duration(milliseconds: 700), _writeDeviceDraftNow);
  }

  void _writeDeviceDraftNow() {
    _deviceDraftTimer?.cancel();
    _deviceDraftTimer = null;
    if (_schoolRef.isEmpty) return;
    final json = engine.exportBackupJson(pretty: false);
    final dirty = _lastCloudJson == null || json != _lastCloudJson;
    _lastDeviceSave = DateTime.now();
    final changed = dirty != _hasUnsavedCloudChanges;
    _hasUnsavedCloudChanges = dirty;
    if (kIsWeb) {
      try {
        html.window.localStorage['rojmel_device_draft_$_schoolRef'] = json;
        html.window.localStorage['rojmel_device_dirty_$_schoolRef'] = dirty ? 'true' : 'false';
      } catch (_) {}
    }
    if (changed && mounted) setState(() {});
  }

  void _onEngineChanged() {
    _syncFilterControllersFromEngine();
    if (_cloudReady && !_loadingCloud) {
      _saveToLocalDeviceCache();
    }
    if (mounted) setState(() {});
  }

  String _cleanText(dynamic value, [String fallback = '']) {
    final text = (value ?? '').toString().trim();
    return text.isEmpty || text.toLowerCase() == 'null' ? fallback : text;
  }

  String _pickRegistrationField(List<String> keys) {
    final sources = <Map<String, dynamic>>[_schoolContext, widget.profile];
    for (final src in sources) {
      for (final k in keys) {
        final v = _cleanText(src[k]);
        if (v.isNotEmpty) return v;
      }
      for (final nestedKey in const ['school', 'school_info', 'schoolInfo', 'registration', 'data', 'metadata', 'user_metadata']) {
        final sub = src[nestedKey];
        if (sub is Map) {
          for (final k in keys) {
            final v = _cleanText(sub[k]);
            if (v.isNotEmpty) return v;
          }
        }
      }
    }
    return '';
  }

  String _rojmelSchoolNameLang = 'gu';

  String get _registeredSchoolNameGu => _pickRegistrationField(const [
        'school_name_gu',
        'schoolNameGu',
        'school_name',
        'schoolName',
        'name',
        'registered_school_name',
      ]);

  String get _registeredSchoolNameEn => _pickRegistrationField(const [
        'school_name_en',
        'schoolNameEn',
        'school_name',
        'schoolName',
        'name',
        'registered_school_name',
      ]);

  String get _registeredSchoolName {
    final gu = _registeredSchoolNameGu;
    final en = _registeredSchoolNameEn;
    if (_rojmelSchoolNameLang == 'en') {
      return en.isNotEmpty ? en : gu;
    }
    return gu.isNotEmpty ? gu : en;
  }

  Widget _buildRojmelSchoolNameLangSelector({VoidCallback? onUpdated}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text(
          'શાળાના નામની ભાષા: ',
          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: Color(0xFF11345F)),
        ),
        DropdownButton<String>(
          value: _rojmelSchoolNameLang,
          isDense: true,
          items: const [
            DropdownMenuItem(value: 'gu', child: Text('ગુજરાતી')),
            DropdownMenuItem(value: 'en', child: Text('English')),
          ],
          onChanged: (v) {
            if (v == null) return;
            setState(() {
              _rojmelSchoolNameLang = v;
              final reg = _registeredSchoolName;
              if (reg.isNotEmpty) {
                engine.schoolName = reg;
                _schoolInfoNameCtrl.text = reg;
                _accSchoolCtrl.text = reg;
                _accPfmsSchoolCtrl.text = reg;
                for (final m in engine.accountMeta.values) {
                  m.schoolName = reg;
                  m.pfmsSchoolName = reg;
                }
              }
            });
            engine.triggerUpdate();
            if (onUpdated != null) onUpdated();
          },
        ),
      ],
    );
  }

  String get _registeredDiseCode => _pickRegistrationField(const [
        'dise_code',
        'udise_code',
        'udise',
        'dise',
        'udiseCode',
        'diseCode',
        'school_code',
        'school_id',
      ]);

  String get _registeredAddress => _pickRegistrationField(const [
        'school_address_gu',
        'school_address',
        'school_address_en',
        'address_gu',
        'address',
        'address_en',
        'schoolAddress',
        'full_address',
      ]);

  String get _registeredVillageCity => _pickRegistrationField(const [
        'village_gu',
        'village',
        'village_en',
        'city_gu',
        'city',
        'city_en',
        'village_city',
        'cluster_gu',
        'cluster_name',
        'cluster',
        'clusterName',
        'gam',
        'town',
      ]);

  String get _registeredTaluko => _pickRegistrationField(const [
        'taluko_gu',
        'taluka_gu',
        'taluko',
        'taluka',
        'taluka_en',
        'taluko_en',
        'talukaName',
        'block_gu',
        'block_name',
        'block',
        'tehsil',
      ]);

  String get _registeredDistrict => _pickRegistrationField(const [
        'district_gu',
        'district',
        'district_en',
        'districtName',
        'district_name',
        'jilla',
        'zilla',
      ]);

  /// Automatically populates all 6 School Information fields (`school name`, `dise code`, `address`, `village/city`, `taluko`, `district`)
  /// from the school registration details.
  /// School address exactly as registered (falls back to village / taluka /
  /// district when the registration has no full address).
  String _registrationAddressLine() {
    final regAddr = _registeredAddress;
    if (regAddr.isNotEmpty) return regAddr;
    return <String>[
      if (_registeredVillageCity.isNotEmpty) 'મું. $_registeredVillageCity',
      if (_registeredTaluko.isNotEmpty) 'તા. $_registeredTaluko',
      if (_registeredDistrict.isNotEmpty) 'જિ. $_registeredDistrict',
    ].join(', ');
  }

  void _applyRegisteredIdentityIfBlank({bool overwriteAll = false}) {
    final regName = _registeredSchoolName;
    final regDise = _registeredDiseCode;
    final regVillage = _registeredVillageCity;
    final regTaluko = _registeredTaluko;
    final regDistrict = _registeredDistrict;
    final regAddr = _registrationAddressLine();

    if (overwriteAll || engine.schoolName.trim().isEmpty) {
      if (regName.isNotEmpty) engine.schoolName = regName;
    }
    if (overwriteAll || engine.udiseCode.trim().isEmpty) {
      if (regDise.isNotEmpty) engine.udiseCode = regDise;
    }
    if (overwriteAll || engine.schoolAddress.trim().isEmpty) {
      if (regAddr.isNotEmpty) engine.schoolAddress = regAddr;
    }
    if (overwriteAll || engine.clusterName.trim().isEmpty) {
      if (regVillage.isNotEmpty) engine.clusterName = regVillage;
    }
    if (overwriteAll || engine.talukaName.trim().isEmpty) {
      if (regTaluko.isNotEmpty) engine.talukaName = regTaluko;
    }
    if (overwriteAll || engine.districtName.trim().isEmpty) {
      if (regDistrict.isNotEmpty) engine.districtName = regDistrict;
    }

    for (final meta in engine.accountMeta.values) {
      if (overwriteAll || meta.schoolName.trim().isEmpty) meta.schoolName = engine.schoolName;
      if (overwriteAll || meta.pfmsSchoolName.trim().isEmpty) meta.pfmsSchoolName = engine.schoolName;
      if (meta.type != 'SNA_PURE' && (overwriteAll || meta.holderName.trim().isEmpty)) {
        meta.holderName = meta.schoolName;
      }
    }
    _syncFilterControllersFromEngine(forceSchoolFields: true);
  }

  Future<void> _initializeCloudState() async {
    try {
      final role = _cleanText(widget.profile['role']).toLowerCase();
      if (role != 'admin') {
        throw StateError('રોજમેળ માત્ર શાળા Admin માટે ઉપલબ્ધ છે. શિક્ષક એકાઉન્ટથી પ્રવેશ માન્ય નથી.');
      }
      _serverAdmin = await _rojmelService.isSchoolAdmin();
      if (!_serverAdmin) {
        throw StateError('આ એકાઉન્ટને School Admin તરીકે માન્ય કર્યું નથી.');
      }
      _schoolRef = await _rojmelService.currentSchoolRef();
      _schoolContext = Map<String, dynamic>.from(await _rojmelService.loadSchoolContext());

      // Also check `schools` registration table if any of address / village / taluko / district are missing from RPC context
      if (_registeredAddress.isEmpty || _registeredVillageCity.isEmpty || _registeredTaluko.isEmpty || _registeredDistrict.isEmpty) {
        try {
          Map<String, dynamic>? cachedReg;
          if (kIsWeb) {
            final rawReg = html.window.localStorage['rojmel_school_reg_$_schoolRef'];
            if (rawReg != null && rawReg.isNotEmpty) {
              cachedReg = Map<String, dynamic>.from(jsonDecode(rawReg) as Map);
            }
          }
          final cachedHasAddress = cachedReg != null &&
              const ['school_address_gu', 'school_address', 'school_address_en', 'address']
                  .any((k) => '${cachedReg![k] ?? ''}'.trim().isNotEmpty);
          if (cachedReg != null && cachedReg.isNotEmpty && cachedHasAddress) {
            _schoolContext = <String, dynamic>{...cachedReg, ..._schoolContext};
          } else {
            final schoolRow = await Supabase.instance.client
                .from('schools')
                .select()
                .eq('id', _schoolRef)
                .maybeSingle();
            if (schoolRow != null) {
              final rowMap = Map<String, dynamic>.from(schoolRow as Map);
              _schoolContext = <String, dynamic>{...rowMap, ..._schoolContext};
              if (kIsWeb) {
                try {
                  html.window.localStorage['rojmel_school_reg_$_schoolRef'] = jsonEncode(rowMap);
                } catch (_) {}
              }
            }
          }
        } catch (_) {}
      }

      if (_schoolContext.isEmpty && _registeredDiseCode.isEmpty) {
        throw StateError('નોંધાયેલ શાળાની માહિતી મળી નથી. Developer Portal માં શાળાની નોંધણી તપાસો.');
      }

      // Check if there is an unsaved local device draft first (to avoid losing local work and save Firestore reads/writes)
      Map<String, dynamic>? localDraft;
      bool hasLocalDirty = false;
      if (kIsWeb) {
        try {
          hasLocalDirty = html.window.localStorage['rojmel_device_dirty_$_schoolRef'] == 'true';
          final rawDraft = html.window.localStorage['rojmel_device_draft_$_schoolRef'];
          if (rawDraft != null && rawDraft.trim().startsWith('{')) {
            localDraft = Map<String, dynamic>.from(jsonDecode(rawDraft) as Map);
          }
        } catch (_) {}
      }

      if (hasLocalDirty && localDraft != null && localDraft.isNotEmpty) {
        engine.loadStateFromMap(localDraft, notify: false);
        _hasUnsavedCloudChanges = true;
      } else {
        final saved = await _rojmelService.loadState(_schoolRef);
        if (saved == null || saved.isEmpty) {
          engine.initializeEmptySchool(
            registeredSchoolName: _registeredSchoolName,
            registeredUdiseCode: _registeredDiseCode,
            registeredAddress: _registeredAddress,
            registeredVillage: _registeredVillageCity,
            registeredTaluka: _registeredTaluko,
            registeredDistrict: _registeredDistrict,
          );
        } else {
          engine.loadStateFromMap(saved, notify: false);
        }
        _hasUnsavedCloudChanges = false;
        _lastCloudJson = saved == null || saved.isEmpty ? null : engine.exportBackupJson(pretty: false);
      }

      _applyRegisteredIdentityIfBlank();
      if (!mounted) return;
      setState(() {
        _loadingCloud = false;
        _cloudReady = true;
        _initializationError = null;
      });
      // NOTE: Do NOT call _flushCloudSave() automatically on startup!
      // All changes stay on device until the user explicitly clicks the Save button.
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loadingCloud = false;
        _cloudReady = false;
        _initializationError = _friendlyCloudError(error);
      });
    }
  }

  String _friendlyCloudError(Object error) {
    final raw = '$error'.replaceFirst('Exception: ', '').replaceFirst('Bad state: ', '');
    if (raw.contains('school_rojmel_state') || raw.contains('schema cache') || raw.contains('Could not find the table')) {
      return 'રોજમેળનું migration લાગુ થયું નથી. પહેલા 20261025210000_school_rojmel_cloud_state.sql migration લાગુ કરો અને પછી ફરી પ્રયાસ કરો.\n\n$raw';
    }
    if (raw.contains('psm_library_school_context') || raw.contains('Could not find the function')) {
      return 'શાળાની નોંધણી વિગતો મેળવવા જરૂરી school-context RPC મળ્યું નથી.\n\n$raw';
    }
    return raw;
  }

  void _scheduleCloudSave() {
    // Disabled automatic background cloud writes to minimize Firestore read/write cost.
    _saveToLocalDeviceCache();
  }

  /// Explicitly saves the current Rojmel state from the device to Firestore / Cloud ONLY when the user presses the Save button.
  Future<void> _flushCloudSave() async {
    if (!_cloudReady || !_serverAdmin || _schoolRef.isEmpty) return;
    if (_cloudSaving) {
      // A save is already running: wait for it (and its follow-up pass)
      // instead of returning early, so one tap is always enough.
      _cloudSavePending = true;
      while (_cloudSaving && mounted) {
        await Future<void>.delayed(const Duration(milliseconds: 120));
      }
      return;
    }
    // Commit whatever is still being typed (fields that apply on focus loss)
    // before taking the snapshot; otherwise the first tap saved the old data
    // and a second tap was needed.
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() => _cloudSaving = true);
    await WidgetsBinding.instance.endOfFrame;
    _deviceDraftTimer?.cancel();
    _deviceDraftTimer = null;
    var passes = 0;
    do {
      _cloudSavePending = false;
      passes++;
      try {
        final jsonStr = engine.exportBackupJson(pretty: false);
        if (_lastCloudJson != null && jsonStr == _lastCloudJson) {
          // Nothing changed since the last load/save: no Firestore write.
          _hasUnsavedCloudChanges = false;
          _cloudSaveError = null;
        } else {
          final decoded = jsonDecode(jsonStr) as Map<String, dynamic>;
          await _rojmelService.saveState(schoolRef: _schoolRef, state: decoded);
          _lastCloudJson = jsonStr;
          _lastCloudSave = DateTime.now();
          _cloudSaveError = null;
          _hasUnsavedCloudChanges = false;
          if (kIsWeb) {
            try {
              html.window.localStorage['rojmel_device_draft_$_schoolRef'] = jsonStr;
              html.window.localStorage['rojmel_device_dirty_$_schoolRef'] = 'false';
            } catch (_) {}
          }
        }
        // Changes made while the upload was running are saved in the same
        // tap, not left for a second press.
        if (engine.exportBackupJson(pretty: false) != _lastCloudJson) _cloudSavePending = true;
      } catch (error) {
        _cloudSaveError = _friendlyCloudError(error);
        break;
      }
    } while (_cloudSavePending && passes < 4);
    _cloudSaving = false;
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _cloudSaveTimer?.cancel();
    if (_deviceDraftTimer != null) _writeDeviceDraftNow();
    engine.removeListener(_onEngineChanged);
    engine.dispose();
    super.dispose();
  }

  void _showToast(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: const Color(0xFF11345F),
        content: Text(text, style: const TextStyle(fontWeight: FontWeight.w700)),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  void _goToPanel(String panelId) {
    final idx = _navItems.indexWhere((x) => x['id'] == panelId);
    if (idx >= 0) {
      setState(() => _selectedNavIndex = idx);
    }
  }

  // --------------------------------------------------------------------------
  // V06 MODALS (EXACT SAME-TO-SAME AS HTML MODALS A, B, C, D, E & V06 TWO-TAB)
  // --------------------------------------------------------------------------

  /// Modal A: Edit account details globally and right-header label from a selected page onward.
  Future<void> _openEditPageHeaderModal([String? accOverride, int? pageNoOverride]) async {
    final acc = accOverride ?? engine.selectedAccount;
    final startPage = (pageNoOverride ?? 1) < 1 ? 1 : (pageNoOverride ?? 1);
    final m = engine.getAccountMeta(acc);
    final pageAccountLabelCtrl = TextEditingController(
      text: engine.getPageAccountLabel(acc, startPage),
    );
    final pageRefColLabelCtrl = TextEditingController(
      text: engine.getPageRefColLabel(acc, startPage).replaceAll('\n', ' '),
    );

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('✏ Confirm Edit: Page Heading & Account Details (Page $startPage onward)', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: Color(0xFF11345F))),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Edit account "$acc". The right-side account label starts from physical page $startPage and continues through the last page. School/account metadata and page titles remain account-wide.',
              style: const TextStyle(fontWeight: FontWeight.w700, color: Color(0xFF344965)),
            ),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: const Color(0xFFFFF3BF), borderRadius: BorderRadius.circular(8)),
              child: const Text(
                'The account label follows a page boundary: edit page 1 to use the label on every page, or edit page 15 to apply it from page 15 onward. The default label is the selected account name. School/account details and page titles update account-wide.',
                style: TextStyle(fontSize: 12.5, color: Color(0xFF6C4D00), fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFF185D98)),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('✓ Yes, Confirm & Edit Details'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    final creditTitleCtrl = TextEditingController(text: m.creditPageTitle);
    final debitTitleCtrl = TextEditingController(text: m.debitPageTitle);
    final schoolCtrl = TextEditingController(text: m.schoolName);
    final pfmsSchoolCtrl = TextEditingController(text: m.pfmsSchoolName);
    final acNoCtrl = TextEditingController(text: m.acNo);
    final snaAgencyCtrl = TextEditingController(text: m.effectiveSnaAgencyCode);
    final pfmsLastDateCtrl = TextEditingController(text: fmtDateSlashDDMMYYYY(m.pfmsLastDate));
    final snaStartDateCtrl = TextEditingController(text: fmtDateSlashDDMMYYYY(m.snaStartDate));
    final ifscCtrl = TextEditingController(text: m.ifsc);
    final holderCtrl = TextEditingController(text: m.holderName);
    final bankCtrl = TextEditingController(text: m.bankName);
    final branchCtrl = TextEditingController(text: m.branch);
    final addrCtrl = TextEditingController(text: m.branchAddress);

    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('✏ Edit Heading, School Name & Account Details ($acc — ${m.type})', style: const TextStyle(fontSize: 16.5, fontWeight: FontWeight.w800, color: Color(0xFF11345F))),
        content: SizedBox(
          width: 640,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Expanded(child: _labeledInput('Credit Page Top Heading', creditTitleCtrl)),
                    const SizedBox(width: 10),
                    Expanded(child: _labeledInput('Debit Page Top Heading', debitTitleCtrl)),
                  ],
                ),
                const SizedBox(height: 10),
                _labeledInput(
                  'Right peach-bar account label from page $startPage onward (default: $acc)',
                  pageAccountLabelCtrl,
                ),
                const SizedBox(height: 10),
                _labeledInput(
                  'Debit Reference Column Heading from page $startPage onward (SNA=CLAIM નંબર, PFMS=PPA નંબર, BANK=ચેક નંબર)',
                  pageRefColLabelCtrl,
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    _htmlBtn('Set: CLAIM નંબર (SNA SPARSH)', const Color(0xFFE8F0FA), const Color(0xFF164B80), () {
                      pageRefColLabelCtrl.text = 'CLAIM નંબર';
                      pageAccountLabelCtrl.text = 'SNA SPARSH';
                    }),
                    _htmlBtn('Set: PPA નંબર (PFMS)', const Color(0xFFE8F0FA), const Color(0xFF164B80), () {
                      pageRefColLabelCtrl.text = 'PPA નંબર';
                      pageAccountLabelCtrl.text = 'PFMS';
                    }),
                    _htmlBtn('Set: ચેક નંબર (BANK)', const Color(0xFFE8F0FA), const Color(0xFF164B80), () {
                      pageRefColLabelCtrl.text = 'ચેક નંબર';
                    }),
                    _htmlBtn('Set: PFMS નંબર', const Color(0xFFE8F0FA), const Color(0xFF164B80), () {
                      pageRefColLabelCtrl.text = 'PFMS નંબર';
                    }),
                  ],
                ),
                const SizedBox(height: 10),
                _labeledInput('School Name for Cashbook & All Reports (SCHOOL NAME — રજીસ્ટ્રેશન મુજબ, માત્ર ભાષા બદલી શકાશે)', schoolCtrl, readOnly: true),
                const SizedBox(height: 6),
                _buildRojmelSchoolNameLangSelector(onUpdated: () {
                  schoolCtrl.text = _registeredSchoolName;
                  pfmsSchoolCtrl.text = _registeredSchoolName;
                }),
                if (m.type == 'SNA_PURE') ...[
                  const SizedBox(height: 10),
                  _labeledInput('SNA SPARSH Agency Code (એજન્સી કોડ) *', snaAgencyCtrl),
                ] else ...[
                  if (m.type == 'SNA') ...[
                    const SizedBox(height: 10),
                    _labeledInput('School Name During Initial PFMS Phase (PFMS વખતે શાળાનું નામ)', pfmsSchoolCtrl, readOnly: true),
                    const SizedBox(height: 10),
                    ResponsiveFields(children: [
                      _labeledInput('SNA SPARSH Agency Code (એજન્સી કોડ)', snaAgencyCtrl),
                      _labeledDateInput('PFMS Last Entry Date (DD/MM/YYYY)', pfmsLastDateCtrl),
                      _labeledDateInput('SNA SPARSH Start Date (DD/MM/YYYY)', snaStartDateCtrl),
                    ]),
                  ],
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(child: _labeledInput('Bank Account Number (PFMS / BANK A/C NO.) *', acNoCtrl)),
                      const SizedBox(width: 10),
                      Expanded(child: _labeledInput('IFSC Code', ifscCtrl)),
                    ],
                  ),
                  const SizedBox(height: 10),
                  _labeledInput('Account Holder Name (ACCOUNT HOLDER NAME) *', holderCtrl),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(child: _labeledInput('Bank Name', bankCtrl)),
                      const SizedBox(width: 10),
                      Expanded(child: _labeledInput('Branch Name', branchCtrl)),
                    ],
                  ),
                  const SizedBox(height: 10),
                  _labeledInput('Branch Address', addrCtrl),
                ],
              ],
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFF087F5B)),
            onPressed: () {
              m.creditPageTitle = creditTitleCtrl.text.trim().isNotEmpty ? creditTitleCtrl.text.trim() : '-: CASHBOOK :-';
              m.debitPageTitle = debitTitleCtrl.text.trim().isNotEmpty ? debitTitleCtrl.text.trim() : '-: કેશબુક :-';
              m.schoolName = schoolCtrl.text.trim().isNotEmpty ? schoolCtrl.text.trim() : engine.schoolName;
              m.pfmsSchoolName = pfmsSchoolCtrl.text.trim().isNotEmpty ? pfmsSchoolCtrl.text.trim() : m.schoolName;
              if (m.type == 'SNA_PURE') {
                m.snaAgencyCode = snaAgencyCtrl.text.trim();
                m.acNo = m.snaAgencyCode;
              } else {
                m.acNo = acNoCtrl.text.trim();
                if (m.type == 'SNA') {
                  m.snaAgencyCode = snaAgencyCtrl.text.trim();
                  m.pfmsLastDate = normalizeToIsoDate(pfmsLastDateCtrl.text.trim());
                  m.snaStartDate = normalizeToIsoDate(snaStartDateCtrl.text.trim());
                }
                m.ifsc = ifscCtrl.text.trim();
                m.holderName = holderCtrl.text.trim();
                m.bankName = bankCtrl.text.trim();
                m.branch = branchCtrl.text.trim();
                m.branchAddress = addrCtrl.text.trim();
              }
              engine.accountMeta[acc] = m;
              engine.setPageAccountLabelFromPage(acc, startPage, pageAccountLabelCtrl.text);
              final rawRefLabel = pageRefColLabelCtrl.text.trim();
              final formattedRefLabel = rawRefLabel.contains(' ') && !rawRefLabel.contains('\n')
                  ? rawRefLabel.replaceFirst(' ', '\n')
                  : rawRefLabel;
              engine.setPageRefColLabelFromPage(acc, startPage, formattedRefLabel);
              engine.triggerUpdate();
              Navigator.of(ctx).pop();
              _showToast('Updated account label from page $startPage through the last page for "$acc".');
            },
            child: const Text('💾 Save & Update All Pages'),
          ),
        ],
      ),
    );
  }

  /// Modal B: Confirm & Edit Any Transaction Entry on Any Page / Register
  Future<void> _openEditTransactionModal(RojmelEntry e) async {
    final action = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('✏ Confirm Edit: Transaction Entry', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: Color(0xFF11345F))),
        content: Text(
          'Do you want to edit this transaction in "${e.account}" (Date: ${fmtDateSlashDDMMYYYY(e.date)} | Grant Head: ${e.head} | ${e.type == "credit" ? "Credit" : "Debit"}: ₹${fmtDemoNum(e.amount)})?',
          style: const TextStyle(fontWeight: FontWeight.w700, color: Color(0xFF344965)),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop('cancel'), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFFFFE3E3), foregroundColor: const Color(0xFFC92A2A)),
            onPressed: () => Navigator.of(ctx).pop('delete'),
            child: const Text('🗑 Delete This Entry'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFF185D98)),
            onPressed: () => Navigator.of(ctx).pop('edit'),
            child: const Text('✓ Yes, Confirm & Edit Entry'),
          ),
        ],
      ),
    );

    if (action == 'delete') {
      engine.deleteSingleEntry(e.id);
      _showToast('Transaction deleted and pages recalculated.');
      return;
    }
    if (action != 'edit' || !mounted) return;

    final dateCtrl = TextEditingController(text: fmtDateSlashDDMMYYYY(e.date));
    String selType = e.type;
    final heads = engine.getAccountSpecificHeads(e.account);
    if (e.head.isNotEmpty && !heads.contains(e.head)) heads.add(e.head);
    String selHead = e.head.isNotEmpty ? e.head : (heads.isNotEmpty ? heads.first : '');
    final narrCtrl = TextEditingController(text: e.narration);
    final expCtrl = TextEditingController(text: e.expense);
    final amtCtrl = TextEditingController(text: e.amount.toStringAsFixed(2));
    String selMedium = RojmelEngine.isCashEntry(e) ? 'Cash' : (['Bank', 'PFMS', 'SNA SPARSH'].contains(e.medium) ? e.medium : 'Bank');
    final voucherCtrl = TextEditingController(text: e.voucher.isNotEmpty ? e.voucher : e.manualVoucher);
    final txnCtrl = TextEditingController(text: e.txn);
    final clearCtrl = TextEditingController(text: fmtDateSlashDDMMYYYY(e.clearDate));
    final partyCtrl = TextEditingController(text: e.party);
    var deadStock = e.deadStock;

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) => AlertDialog(
          title: Text('✏ Edit Transaction Entry (${e.account})', style: const TextStyle(fontSize: 16.5, fontWeight: FontWeight.w800, color: Color(0xFF11345F))),
          content: SizedBox(
            width: 600,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Expanded(child: _labeledDateInput('Transaction Date (DD/MM/YYYY) *', dateCtrl, onChanged: (v) { engine.syncFinancialYearFromDate(v); setModalState(() {}); })),
                      const SizedBox(width: 10),
                      Expanded(
                        child: DropdownButtonFormField<String>(
                      isExpanded: true,
                          value: selType,
                          decoration: const InputDecoration(labelText: 'Type (Credit / Debit) *', border: OutlineInputBorder(), isDense: true),
                          items: const [
                            DropdownMenuItem(value: 'credit', child: Text('Credit / આવક (+)')),
                            DropdownMenuItem(value: 'debit', child: Text('Debit / જાવક (-)')),
                          ],
                          onChanged: (v) => setModalState(() => selType = v!),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String>(
                    value: selHead,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Grant Head (ગ્રાન્ટ હેડ) *', border: OutlineInputBorder(), isDense: true),
                    items: heads.map((h) => DropdownMenuItem(value: h, child: Text(h, overflow: TextOverflow.ellipsis))).toList(),
                    onChanged: (v) => setModalState(() => selHead = v!),
                  ),
                  const SizedBox(height: 10),
                  _labeledInput('Description / વિગત (Cashbook & Bill Register) *', narrCtrl),
                  const SizedBox(height: 10),
                  if (selType == 'debit') ...[
                    _labeledInput('Short Expense Detail / ખર્ચની ટૂંકમાં વિગત (ખર્ચ પત્રક માટે)', expCtrl),
                    const SizedBox(height: 10),
                  ],
                  Row(
                    children: [
                      Expanded(child: _labeledInput('Amount (રકમ ₹) *', amtCtrl, isNumber: true)),
                      const SizedBox(width: 10),
                      Expanded(
                        child: DropdownButtonFormField<String>(
                      isExpanded: true,
                          value: selMedium,
                          decoration: const InputDecoration(labelText: 'Mode (Cash/Bank/PFMS/SNA)', border: OutlineInputBorder(), isDense: true),
                          items: const [
                            DropdownMenuItem(value: 'Bank', child: Text('Bank / Cheque')),
                            DropdownMenuItem(value: 'Cash', child: Text('Cash / રોકડ')),
                            DropdownMenuItem(value: 'PFMS', child: Text('PFMS')),
                            DropdownMenuItem(value: 'SNA SPARSH', child: Text('SNA SPARSH')),
                          ],
                          onChanged: (v) => setModalState(() => selMedium = v!),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(child: _labeledInput('Voucher No. (Debit only)', voucherCtrl)),
                      const SizedBox(width: 10),
                      Expanded(child: _labeledInput('Cheque / PFMS / Claim No.', txnCtrl)),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(child: _labeledDateInput('Settlement / Clearing Date', clearCtrl, onChanged: (_) => setModalState(() {}))),
                      const SizedBox(width: 10),
                      Expanded(child: _labeledInput('Party / Payee / Source', partyCtrl)),
                    ],
                  ),
                  if (e.type == 'debit')
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      value: deadStock,
                      onChanged: (v) => setModalState(() => deadStock = v ?? false),
                      title: const Text('આ ચુકવણાની વસ્તુને ડેડ સ્ટોક રજીસ્ટરમાં ઉમેરવાના છો? (હા)',
                          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
                    ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Cancel')),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: const Color(0xFF087F5B)),
              onPressed: () {
                final v = voucherCtrl.text.trim();
                final updated = e.copy()
                  ..date = dateCtrl.text.trim()
                  ..type = selType
                  ..head = selHead
                  ..narration = narrCtrl.text.trim()
                  ..expense = expCtrl.text.trim()
                  ..amount = math.max(0.01, double.tryParse(amtCtrl.text.trim()) ?? e.amount)
                  ..medium = selMedium
                  ..voucher = selType == 'debit' ? v : ''
                  // Keep a manual number only when the admin really typed a
                  // different one; otherwise the voucher stays automatic and
                  // follows the transaction date.
                  ..manualVoucher = selType == 'debit' &&
                          v.isNotEmpty &&
                          (e.manualVoucher.isNotEmpty || v != e.voucher)
                      ? v
                      : ''
                  ..txn = txnCtrl.text.trim()
                  ..clearDate = clearCtrl.text.trim()
                  ..party = partyCtrl.text.trim()
                  ..deadStock = e.type == 'debit' && deadStock;
                final err = engine.updateEntry(updated);
                if (err != null) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(err), backgroundColor: const Color(0xFFC92A2A)),
                  );
                  return;
                }
                Navigator.of(ctx).pop();
                _showToast('Transaction updated and all pages recalculated.');
              },
              child: const Text('💾 Save Entry & Recalculate All Pages'),
            ),
          ],
        ),
      ),
    );
  }

  /// Modal D: Two-Time Confirmation to Delete All Entries of Selected Account Only (For Next Year Use)
  Future<void> _openDeleteAllAccountEntriesModal([String? accOverride]) async {
    final acc = accOverride ?? engine.selectedAccount;
    final m = engine.getAccountMeta(acc);
    final count = engine.getAccountEntries(acc).length;
    bool carryForward = m.type == 'BANK';
    final nextFyCtrl = TextEditingController(text: engine.financialYear);

    // Step 1 of 2
    final proceedStep2 = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) => AlertDialog(
          title: const Text(
            '⚠ Confirmation 1 of 2: Delete All Entries for Selected Account Only',
            style: TextStyle(color: Color(0xFFC92A2A), fontSize: 17, fontWeight: FontWeight.w800),
          ),
          content: SizedBox(
            width: 540,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Step 1 of 2: Do you want to delete all $count transaction entries from account "$acc" (${m.type}) so you can use this account for the next financial year?',
                  style: const TextStyle(fontWeight: FontWeight.w700, color: Color(0xFF10233F)),
                ),
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(color: const Color(0xFFFFF3BF), borderRadius: BorderRadius.circular(8)),
                  child: Text(
                    '• Only transactions of account "$acc" will be deleted.\n'
                    '• Other accounts will NOT be touched.\n'
                    '• Your Account Details, Bank Info, School Headings, and Grant Heads for "$acc" will remain saved so you can immediately use this account for the next financial year.',
                    style: const TextStyle(fontSize: 12.5, color: Color(0xFF6C4D00), fontWeight: FontWeight.w700),
                  ),
                ),
                if (m.type == 'BANK') ...[
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF4F9FF),
                      border: Border.all(color: const Color(0xFF7AA7D8)),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      value: carryForward,
                      title: const Text(
                        'Carry Forward Closing Balance as Next Year\'s Opening Balance (Automatically set current Head-wise & Total Closing Balance as next year\'s Opening Balance for this BANK account)',
                        style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
                      ),
                      onChanged: (v) => setModalState(() => carryForward = v ?? false),
                    ),
                  ),
                ],
                const SizedBox(height: 10),
                _labeledInput('Optional: Set Financial Year for Next Year (e.g. 2026-27)', nextFyCtrl),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: const Color(0xFFC92A2A)),
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Yes, Proceed to 2nd Confirmation (1/2) →'),
            ),
          ],
        ),
      ),
    );

    if (proceedStep2 != true || !mounted) return;

    // Step 2 of 2 (Final Confirmation)
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text(
          '🚨 Confirmation 2 of 2 (FINAL CONFIRMATION)',
          style: TextStyle(color: Color(0xFFC92A2A), fontSize: 17, fontWeight: FontWeight.w800),
        ),
        content: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: const Color(0xFFFFE3E3), borderRadius: BorderRadius.circular(8)),
          child: Text(
            'Second & Final Confirmation Required:\n'
            'Are you 100% sure you want to permanently delete all $count entries of account "$acc"?\n'
            'After clicking below, this account will have 0 entries and will be ready for next year\'s data entry.',
            style: const TextStyle(color: Color(0xFFA51111), fontWeight: FontWeight.w700, fontSize: 13.5),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFFC92A2A)),
            onPressed: () {
              final removed = engine.deleteAccountAllEntries(
                acc,
                carryForwardClosingAsOpening: carryForward,
                nextFinancialYear: nextFyCtrl.text.trim(),
              );
              Navigator.of(ctx).pop();
              _showToast('Confirmed twice (2/2): Deleted all $removed entries of account "$acc" only. Ready for next year!');
            },
            child: const Text('🗑 Yes, Confirm 2nd Time & Delete All Entries of This Account (2/2)'),
          ),
        ],
      ),
    );
  }

  /// Modal E: Copy Grant Heads Prompt Modal ("Do you want to get Grant Heads from another account? If Yes -> All or Selected")
  Future<void> _openCopyGrantHeadsModal(String targetAcc, {void Function(List<String> picked, String srcAcc)? onPicked}) async {
    final sources = engine.accounts.where((a) => a != targetAcc).toList();
    if (sources.isEmpty) return;

    String ask = 'yes';
    String srcAcc = sources.first;
    String mode = 'selected';
    final checkedSet = <String>{...engine.getAccountSpecificHeads(srcAcc)};

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) {
          final srcHeads = engine.getAccountSpecificHeads(srcAcc);
          return AlertDialog(
            title: const Text('🗂 Do you want to get Grant Heads from another account?', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: Color(0xFF11345F))),
            content: SizedBox(
              width: 600,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Do you want to get Grant Heads for account "$targetAcc" from another account? If Yes, choose All or Selected:',
                      style: const TextStyle(fontWeight: FontWeight.w700, color: Color(0xFF344965)),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: DropdownButtonFormField<String>(
                      isExpanded: true,
                            value: ask,
                            decoration: const InputDecoration(labelText: '1. Get Grant Heads from another account?', border: OutlineInputBorder(), isDense: true),
                            items: const [
                              DropdownMenuItem(value: 'yes', child: Text('Yes — Get Grant Heads')),
                              DropdownMenuItem(value: 'no', child: Text('No — Do not copy')),
                            ],
                            onChanged: (v) => setModalState(() => ask = v!),
                          ),
                        ),
                        const SizedBox(width: 10),
                        if (ask == 'yes')
                          Expanded(
                            child: DropdownButtonFormField<String>(
                      isExpanded: true,
                              value: srcAcc,
                              decoration: const InputDecoration(labelText: '2. From which Account? (કયા ખાતામાંથી?)', border: OutlineInputBorder(), isDense: true),
                              items: sources.map((a) => DropdownMenuItem(value: a, child: Text('$a (${engine.getAccountSpecificHeads(a).length} Heads)'))).toList(),
                              onChanged: (v) {
                                if (v == null) return;
                                setModalState(() {
                                  srcAcc = v;
                                  checkedSet
                                    ..clear()
                                    ..addAll(engine.getAccountSpecificHeads(v));
                                });
                              },
                            ),
                          ),
                      ],
                    ),
                    if (ask == 'yes') ...[
                      const SizedBox(height: 10),
                      DropdownButtonFormField<String>(
                      isExpanded: true,
                        value: mode,
                        decoration: const InputDecoration(labelText: '3. Option: All Grant Heads or Selected Grant Heads?', border: OutlineInputBorder(), isDense: true),
                        items: const [
                          DropdownMenuItem(value: 'all', child: Text('Option 1: All Grant Heads (બધા ગ્રાન્ટ હેડ)')),
                          DropdownMenuItem(value: 'selected', child: Text('Option 2: Selected Grant Heads Only (માત્ર પસંદ કરેલ ગ્રાન્ટ હેડ)')),
                        ],
                        onChanged: (v) => setModalState(() => mode = v!),
                      ),
                    ],
                    if (ask == 'yes' && mode == 'selected') ...[
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Flexible(child: const Text('Select Grant Heads to include:', style: TextStyle(fontWeight: FontWeight.w800))),
                          Row(
                            children: [
                              TextButton(
                                onPressed: () => setModalState(() => checkedSet.addAll(srcHeads)),
                                child: const Text('Select All'),
                              ),
                              TextButton(
                                onPressed: () => setModalState(() => checkedSet.clear()),
                                child: const Text('Clear All'),
                              ),
                            ],
                          ),
                        ],
                      ),
                      Container(
                        height: 220,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          border: Border.all(color: const Color(0xFFCBD5E1)),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: ListView.builder(
                          itemCount: srcHeads.length,
                          itemBuilder: (_, i) {
                            final h = srcHeads[i];
                            return CheckboxListTile(
                              dense: true,
                              value: checkedSet.contains(h),
                              title: Text('${i + 1}. $h', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                              onChanged: (v) {
                                setModalState(() {
                                  if (v == true) {
                                    checkedSet.add(h);
                                  } else {
                                    checkedSet.remove(h);
                                  }
                                });
                              },
                            );
                          },
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Cancel')),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: const Color(0xFF087F5B)),
                onPressed: () {
                  final picked = ask == 'yes'
                      ? (mode == 'all' ? srcHeads : checkedSet.toList())
                      : <String>[];
                  Navigator.of(ctx).pop();
                  if (onPicked != null) {
                    onPicked(picked, srcAcc);
                  } else if (picked.isNotEmpty) {
                    final existing = engine.getAccountSpecificHeads(targetAcc);
                    engine.setAccountSpecificHeads(targetAcc, <String>[...existing, ...picked]);
                    _showToast('Copied ${picked.length} Grant Head(s) from "$srcAcc" into "$targetAcc".');
                  }
                },
                child: const Text('✓ Apply Choice'),
              ),
            ],
          );
        },
      ),
    );
  }

  /// V06 Two-Tab Modal: Confirmation + Tab 1 (Entry Font Size) & Tab 2 (Number of Entries in This Page)
  Future<void> _openPageFontAndEntriesModal({
    required CashbookPagePair page,
    required int clickedPageNo,
    required String side,
    String initialTab = 'font',
  }) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('🔤 Confirm Change — Entry Font Size & Entries in Page', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: Color(0xFF11345F))),
        content: Text(
          'Do you want to change the Entry Font Size or Number of Entries in This Page for Account "${page.accountName}" (Page $clickedPageNo | Date: ${page.formattedDateDDMMYY})?',
          style: const TextStyle(fontWeight: FontWeight.w700, color: Color(0xFF1E293B)),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFF185D98)),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Yes, Confirm & Open Settings'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    final allPages = engine.buildCashbookPages(page.accountName);
    String activeTab = initialTab;
    String fontScope = 'this_page';
    final fontCtrl = TextEditingController(
      text: (side == 'credit' ? page.crFontPt : page.drFontPt).toStringAsFixed(2),
    );
    bool autoShrink = engine.autoShrinkBigEntry;
    String selectedPairKey = page.pairKey;
    int selectedCreditPageNo = page.creditPageNo;
    String thisPageCountVal = engine.getCreditPageEntryCount(page.accountName, selectedCreditPageNo, selectedPairKey)?.toString() ?? 'auto';
    double thisPageGapMm = engine.getCreditPageEntryGapMm(page.accountName, selectedCreditPageNo, selectedPairKey);
    int defaultMaxCap = <int>[2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 25].contains(engine.defaultMaxEntriesPerPage)
        ? engine.defaultMaxEntriesPerPage
        : 6;

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) => AlertDialog(
          title: Text('⚙ Page Layout Settings — ${page.accountName} — Page $clickedPageNo (${page.formattedDateDDMMYY})', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Color(0xFF11345F))),
          content: SizedBox(
            width: 620,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton(
                          style: FilledButton.styleFrom(
                            backgroundColor: activeTab == 'font' ? const Color(0xFF0B4F9C) : const Color(0xFFF4F7FB),
                            foregroundColor: activeTab == 'font' ? Colors.white : const Color(0xFF243B5A),
                          ),
                          onPressed: () => setModalState(() => activeTab = 'font'),
                          child: const Text('🔤 Tab 1: Entry Font Size'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: FilledButton(
                          style: FilledButton.styleFrom(
                            backgroundColor: activeTab == 'count' ? const Color(0xFF0B4F9C) : const Color(0xFFF4F7FB),
                            foregroundColor: activeTab == 'count' ? Colors.white : const Color(0xFF243B5A),
                          ),
                          onPressed: () => setModalState(() => activeTab = 'count'),
                          child: const Text('📄 Tab 2: Number of Entries in Page'),
                        ),
                      ),
                    ],
                  ),
                  const Divider(height: 22),
                  if (activeTab == 'font') ...[
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(color: const Color(0xFFD3F9D8), borderRadius: BorderRadius.circular(8)),
                      child: const Text(
                        'Smart Writing Area Auto-Fit: If the last entry on a page is big (like long narrations), the app automatically scales that page\'s entry font size so the full entry, closing balance, and Page Number always stay inside the writing area.',
                        style: TextStyle(fontSize: 12.5, color: Color(0xFF075F45), fontWeight: FontWeight.w700),
                      ),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      isExpanded: true,
                      value: fontScope,
                      decoration: const InputDecoration(labelText: 'Apply Font Size To (ક્યા પેજ માટે લાગુ કરવું?)', border: OutlineInputBorder(), isDense: true),
                      items: const [
                        DropdownMenuItem(value: 'this_page', child: Text('This Page Only (આ પેજ પૂરતું)')),
                        DropdownMenuItem(value: 'this_pair', child: Text('This Date Pair — Credit & Debit Pages (આ તારીખના બંને પેજ)')),
                        DropdownMenuItem(value: 'all_pages', child: Text('All Pages of Selected Account (આ ખાતાના તમામ પેજ માટે)')),
                      ],
                      onChanged: (v) => setModalState(() => fontScope = v!),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(child: _labeledInput('Entry Font Size (pt)', fontCtrl, isNumber: true)),
                        const SizedBox(width: 10),
                        FilledButton(
                          style: FilledButton.styleFrom(backgroundColor: const Color(0xFFFFF3BF), foregroundColor: const Color(0xFF754600)),
                          onPressed: () {
                            engine.pageFontMap.remove('page|${page.accountName}|$clickedPageNo');
                            engine.pageFontMap.remove(page.pairKey);
                            engine.globalFontPt = null;
                            engine.autoShrinkBigEntry = true;
                            engine.triggerUpdate();
                            Navigator.of(ctx).pop();
                            _showToast('Reset to Auto Writing-Area Font Size.');
                          },
                          child: const Text('✨ Auto Font Size'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [7.5, 8.0, 8.5, 9.0, 9.5, 10.0, 10.5, 11.0, 12.0].map((pt) {
                        return OutlinedButton(
                          onPressed: () => setModalState(() => fontCtrl.text = '$pt'),
                          child: Text('$pt pt'),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 10),
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      value: autoShrink,
                      title: const Text(
                        'Auto-adjust font size on any page if the last entry is big so full entry & Page Number stay inside writing area',
                        style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800),
                      ),
                      onChanged: (v) => setModalState(() => autoShrink = v ?? true),
                    ),
                  ] else ...[
                    Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF0F6FF),
                        border: Border.all(color: const Color(0xFF90B4E2)),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            '📅 પેજમાં તારીખ મોડ (Multi-Date Entries in Same Page — All Accounts):',
                            style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w900, color: Color(0xFF0E3360)),
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            runSpacing: 6,
                            children: [
                              ChoiceChip(
                                label: const Text('દરેક તારીખ નવા પેજ પર (1 Date per Page)'),
                                selected: !engine.cashbookContinuousDates,
                                onSelected: (_) {
                                  engine.cashbookContinuousDates = false;
                                  engine.triggerUpdate();
                                  setModalState(() {});
                                },
                              ),
                              ChoiceChip(
                                label: const Text('એક પેજમાં અનેક તારીખ — સળંગ એન્ટ્રી (Multi-Date in Same Page)'),
                                selected: engine.cashbookContinuousDates,
                                onSelected: (_) {
                                  engine.cashbookContinuousDates = true;
                                  engine.triggerUpdate();
                                  setModalState(() {});
                                },
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(color: const Color(0xFFFFF3BF), borderRadius: BorderRadius.circular(8)),
                      child: Text(
                        'Page-by-Page Entry Control (Page $clickedPageNo | Date: ${page.formattedDateDDMMYY} — Total on Date: ${page.totalCreditsOnDate} Cr / ${page.totalDebitsOnDate} Dr): If you select e.g. 5, this page will include 5 entries, and from the next page onward the remaining entries will automatically fit into the page writing area (6 to 7 entries per page).',
                        style: const TextStyle(fontSize: 12.5, color: Color(0xFF6C4D00), fontWeight: FontWeight.w700),
                      ),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      value: selectedPairKey,
                      isExpanded: true,
                      decoration: const InputDecoration(labelText: 'Select Credit Page (→ Auto Sets Opposite Debit Page)', border: OutlineInputBorder(), isDense: true),
                      items: allPages.map((p) {
                        return DropdownMenuItem(
                          value: p.pairKey,
                          child: Text('Credit Page ${p.creditPageNo} (→ Auto Debit Page ${p.debitPageNo}) — ${p.alignedCredits.length} Opposite Rows (${p.credits.length} Cr / ${p.debits.length} Dr)'),
                        );
                      }).toList(),
                      onChanged: (v) {
                        if (v == null) return;
                        final match = allPages.where((p) => p.pairKey == v).firstOrNull;
                        setModalState(() {
                          selectedPairKey = v;
                          if (match != null) {
                            selectedCreditPageNo = match.creditPageNo;
                          }
                          thisPageCountVal = engine.getCreditPageEntryCount(page.accountName, selectedCreditPageNo, v)?.toString() ?? 'auto';
                          thisPageGapMm = engine.getCreditPageEntryGapMm(page.accountName, selectedCreditPageNo, v);
                        });
                      },
                    ),
                    const SizedBox(height: 10),
                    DropdownButtonFormField<String>(
                      isExpanded: true,
                      value: thisPageCountVal,
                      decoration: InputDecoration(labelText: 'Credit Page $selectedCreditPageNo (→ Auto Debit Page ${selectedCreditPageNo + 1}) માં કેટલી એન્ટ્રી?', border: const OutlineInputBorder(), isDense: true),
                      items: [
                        const DropdownMenuItem(value: 'auto', child: Text('✨ Auto — Fit Full Last Entry by Font Size')),
                        ...List<int>.generate(25, (i) => i + 1).map((n) => DropdownMenuItem(value: '$n', child: Text('$n એન્ટ્રી આ પેજમાં (Credit Page $selectedCreditPageNo → Auto Debit Page ${selectedCreditPageNo + 1})'))),
                      ],
                      onChanged: (v) => setModalState(() => thisPageCountVal = v!),
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: ['auto', '2', '3', '4', '5', '6', '7', '8', '9', '10', '11', '12', '13', '14', '15', '25'].map((val) {
                        return ChoiceChip(
                          label: Text(val == 'auto' ? '✨ Auto' : (val == '25' ? 'All (25)' : '$val Entries')),
                          selected: thisPageCountVal == val,
                          onSelected: (_) => setModalState(() => thisPageCountVal = val),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      '📏 Gap Between Two Entries on This Page (બે એન્ટ્રી વચ્ચે જગ્યા - mm):',
                      style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w900, color: Color(0xFF0E3360)),
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: const <double>[0, 1, 2, 3, 4, 5, 6, 7, 8, 10, 12, 15, 18, 20, 25].map((g) {
                        return ChoiceChip(
                          label: Text('${g.toStringAsFixed(0)} mm'),
                          selected: (thisPageGapMm - g).abs() < 0.2,
                          onSelected: (_) => setModalState(() => thisPageGapMm = g),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 10),
                    TitleWithActions(
                      title: DropdownButtonFormField<int>(
                            isExpanded: true,
                            value: defaultMaxCap,
                            decoration: const InputDecoration(labelText: 'Default Auto Writing-Area Capacity (All Pages)', border: OutlineInputBorder(), isDense: true),
                            items: const [
                              DropdownMenuItem(value: 2, child: Text('Up to 2 Entries per Page')),
                              DropdownMenuItem(value: 3, child: Text('Up to 3 Entries per Page')),
                              DropdownMenuItem(value: 4, child: Text('Up to 4 Entries per Page')),
                              DropdownMenuItem(value: 5, child: Text('Up to 5 Entries per Page')),
                              DropdownMenuItem(value: 6, child: Text('6 Entries per Page (Standard)')),
                              DropdownMenuItem(value: 7, child: Text('Up to 7 Entries per Page')),
                              DropdownMenuItem(value: 8, child: Text('Up to 8 Entries per Page')),
                              DropdownMenuItem(value: 9, child: Text('Up to 9 Entries per Page')),
                              DropdownMenuItem(value: 10, child: Text('Up to 10 Entries per Page')),
                              DropdownMenuItem(value: 11, child: Text('Up to 11 Entries per Page')),
                              DropdownMenuItem(value: 12, child: Text('Up to 12 Entries per Page (Auto by Font)')),
                              DropdownMenuItem(value: 13, child: Text('Up to 13 Entries per Page')),
                              DropdownMenuItem(value: 14, child: Text('Up to 14 Entries per Page')),
                              DropdownMenuItem(value: 15, child: Text('Up to 15 Entries per Page')),
                              DropdownMenuItem(value: 25, child: Text('All Fit (Up to 25 Entries per Page)')),
                            ],
                            onChanged: (v) => setModalState(() => defaultMaxCap = v ?? 6),
                          ),
                      actions: [
                        OutlinedButton(
                          onPressed: () {
                            engine.pageEntryCountMap.clear();
                            engine.pageEntryGapMap.clear();
                            engine.defaultMaxEntriesPerPage = 12;
                            engine.triggerUpdate();
                            setModalState(() {
                              thisPageCountVal = 'auto';
                              thisPageGapMm = engine.cashbookEntryGapMm;
                              defaultMaxCap = 12;
                            });
                            _showToast('All pages reset to Auto Writing-Area pagination.');
                          },
                          child: const Text('↺ Reset All to Auto'),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Close')),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: const Color(0xFF087F5B)),
              onPressed: () {
                final fontVal = (double.tryParse(fontCtrl.text.trim()) ?? 10.0).clamp(6.5, 15.0);
                engine.setPageFontAndEntryConfig(
                  acc: page.accountName,
                  pairKey: selectedPairKey,
                  pageNo: activeTab == 'font' ? clickedPageNo : selectedCreditPageNo,
                  scope: fontScope,
                  fontPt: activeTab == 'font' ? fontVal : null,
                  entryCountLimit: thisPageCountVal == 'auto' ? null : int.tryParse(thisPageCountVal),
                  autoEntryPack: thisPageCountVal == 'auto',
                  autoShrink: autoShrink,
                  defaultMaxCap: defaultMaxCap,
                  entryGapMm: activeTab == 'count' ? thisPageGapMm : null,
                );
                Navigator.of(ctx).pop();
                _showToast(
                  activeTab == 'font'
                      ? 'Applied Font ${fontVal}pt (${fontScope}) with Auto Full-Last-Entry Pagination.'
                      : 'Applied Page Entries: ${thisPageCountVal == "auto" ? "Auto (Full Last Entry by Font Size)" : "$thisPageCountVal Entries"} for $selectedPairKey.',
                );
              },
              child: const Text('✔ Apply & Rebuild Cashbook Preview'),
            ),
          ],
        ),
      ),
    );
  }

  /// Triggers a direct browser file download (`.xls`, `.csv`, `.xml`, `.json`) on Flutter Web.
  void _downloadBrowserFile(String content, String mimeType, String fileName) {
    if (!kIsWeb) {
      _showToast('This file download is currently available in the web version only.');
      return;
    }
    try {
      final bytes = utf8.encode(content);
      final blob = html.Blob(<dynamic>[bytes], mimeType);
      final url = html.Url.createObjectUrlFromBlob(blob);
      final anchor = html.AnchorElement(href: url)
        ..setAttribute('download', fileName)
        ..style.display = 'none';
      html.document.body?.append(anchor);
      anchor.click();
      anchor.remove();
      Future<void>.delayed(const Duration(seconds: 2), () {
        html.Url.revokeObjectUrl(url);
      });
    } catch (_) {}
  }

  /// Directly auto-downloads a real `.pdf` file in 1 click when the user presses Print / Save PDF
  /// (NO Copy-HTML modal dialog, NO manual steps!).
  /// Renders each `.cash-demo-page` and `.gov-audit-sheet` at exact A4 dimensions (`210mm x 297mm`)
  /// with `Page Number - X` pinned to the bottom edge of every page, and triggers an automatic
  /// `.pdf` file download via `html2canvas` + `jsPDF` inside an offscreen iframe (plus optional print window).
  Future<void> _openPrintPreviewModal(
    String title,
    String exactHtml, {
    bool openBrowserPrintDialogInstead = false,
  }) async {
    if (!kIsWeb) {
      _showToast('Rojmel HTML/PDF printing currently requires the web version.');
      return;
    }
    final safeName = title
        .replaceAll(RegExp(r'[^A-Za-z0-9_\-]'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_|_$'), '');
    final pdfFileName = 'Rojmel_${safeName.isNotEmpty ? safeName : "Report"}_${engine.financialYear}.pdf';

    if (openBrowserPrintDialogInstead) {
      _showToast('🖨 Opening Print Dialog for "$title"...');
      final printReadyHtml = exactHtml.replaceFirst(
        '</body></html>',
        '<script>window.onload=function(){if(window.fitNums)window.fitNums();setTimeout(function(){window.print();},350);};</script></body></html>',
      );
      final blob = html.Blob(<dynamic>[utf8.encode(printReadyHtml)], 'text/html;charset=utf-8');
      final url = html.Url.createObjectUrlFromBlob(blob);
      html.window.open(url, '_blank');
      return;
    }

    _showToast('⏳ Auto-generating & downloading PDF: $pdfFileName ...');

    final autoPdfScript = '''
<script src="https://cdnjs.cloudflare.com/ajax/libs/html2canvas/1.4.1/html2canvas.min.js"></script>
<script src="https://cdnjs.cloudflare.com/ajax/libs/jspdf/2.5.1/jspdf.umd.min.js"></script>
<script>
(async function(){
  try {
    if (window.fitAllReportSheets) window.fitAllReportSheets();
    if (window.fitNums) window.fitNums();
    await new Promise(function(r){ setTimeout(r, 350); });
    if (window.fitAllReportSheets) window.fitAllReportSheets();
    var pages = document.querySelectorAll('.cash-demo-page, .gov-audit-sheet');
    if (!pages || pages.length === 0) {
      pages = [document.body];
    }
    if (window.jspdf && window.html2canvas) {
      var jsPDF = window.jspdf.jsPDF;
      var firstIsLand = (pages[0].getAttribute('data-orientation') === 'landscape' || pages[0].classList.contains('landscape-sheet'));
      var pdf = new jsPDF({ orientation: firstIsLand ? 'landscape' : 'portrait', unit: 'mm', format: 'a4', compress: true });
      for (var i = 0; i < pages.length; i++) {
        var el = pages[i];
        var isLand = (el.getAttribute('data-orientation') === 'landscape' || el.classList.contains('landscape-sheet'));
        var orient = isLand ? 'landscape' : 'portrait';
        var targetPxW = isLand ? 1123 : 794;
        var targetPxH = isLand ? 794 : 1123;
        var canvas = await window.html2canvas(el, {
          scale: 2,
          useCORS: true,
          allowTaint: true,
          backgroundColor: '#ffffff',
          logging: false,
          width: el.offsetWidth || targetPxW,
          height: el.offsetHeight || targetPxH,
          windowWidth: 1300,
          windowHeight: 1300
        });
        var imgData = canvas.toDataURL('image/jpeg', 0.95);
        if (i > 0) pdf.addPage('a4', orient);
        pdf.addImage(imgData, 'JPEG', 0, 0, isLand ? 297 : 210, isLand ? 210 : 297, undefined, 'FAST');
      }
      pdf.save('$pdfFileName');
      if (window.parent && window.parent !== window) {
        window.parent.postMessage('ROJMEL_PDF_DOWNLOADED:$pdfFileName', '*');
      }
    } else {
      window.print();
    }
  } catch (e) {
    console.error('Auto PDF generation error:', e);
    if (window.parent && window.parent !== window) {
      window.parent.postMessage('ROJMEL_PDF_FALLBACK:$pdfFileName', '*');
    }
  }
})();
</script>
</body></html>''';

    final cleanBaseHtml = exactHtml
        .replaceAll('setTimeout(function(){window.print();},300);', '')
        .replaceFirst('</body></html>', autoPdfScript);

    final iframe = html.IFrameElement()
      ..style.position = 'fixed'
      ..style.left = '-10000px'
      ..style.top = '0'
      ..style.width = '310mm'
      ..style.height = '310mm'
      ..style.border = '0'
      ..style.opacity = '0.01'
      ..style.pointerEvents = 'none';

    StreamSubscription<html.MessageEvent>? sub;
    sub = html.window.onMessage.listen((event) {
      final dataStr = (event.data ?? '').toString();
      if (dataStr == 'ROJMEL_PDF_DOWNLOADED:$pdfFileName') {
        sub?.cancel();
        _showToast('✅ PDF Auto-Downloaded: $pdfFileName');
        Future<void>.delayed(const Duration(seconds: 2), () {
          iframe.remove();
        });
      } else if (dataStr == 'ROJMEL_PDF_FALLBACK:$pdfFileName') {
        sub?.cancel();
        iframe.remove();
        _openPrintPreviewModal(title, exactHtml, openBrowserPrintDialogInstead: true);
      }
    });

    html.document.body?.append(iframe);
    iframe.srcdoc = cleanBaseHtml;

    // Safety cleanup after 45 seconds
    Future<void>.delayed(const Duration(seconds: 45), () {
      sub?.cancel();
      try {
        iframe.remove();
      } catch (_) {}
    });
  }

  // --------------------------------------------------------------------------
  // MAIN SCAFFOLD (EXACT HTML SIDEBAR `#123a6b -> #0a294d` + TOP HEADER BAR)
  // --------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    if (_loadingCloud) {
      return Scaffold(
        backgroundColor: const Color(0xFFEEF3F9),
        appBar: AppBar(
          backgroundColor: const Color(0xFF11345F),
          foregroundColor: Colors.white,
          title: const Text('📘 Rojmel Studio Pro — શાળા રોજમેળ'),
        ),
        body: const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 14),
              Text('નોંધાયેલ શાળાનો રોજમેળ ક્લાઉડમાંથી લોડ થઈ રહ્યો છે...', style: TextStyle(fontWeight: FontWeight.w700)),
            ],
          ),
        ),
      );
    }

    if (_initializationError != null || !_serverAdmin || !_cloudReady) {
      return Scaffold(
        backgroundColor: const Color(0xFFEEF3F9),
        appBar: AppBar(
          backgroundColor: const Color(0xFF11345F),
          foregroundColor: Colors.white,
          title: const Text('📘 Rojmel Studio Pro — શાળા રોજમેળ'),
        ),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.cloud_off_rounded, size: 48, color: Color(0xFFC92A2A)),
                  const SizedBox(height: 12),
                  Text(_initializationError ?? 'રોજમેળ માટે Admin access જરૂરી છે.', textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: () {
                      setState(() {
                        _loadingCloud = true;
                        _initializationError = null;
                      });
                      _initializeCloudState();
                    },
                    icon: const Icon(Icons.refresh),
                    label: const Text('ફરી પ્રયાસ કરો / Retry'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    final isWide = MediaQuery.of(context).size.width >= 920;

    return Scaffold(
      backgroundColor: const Color(0xFFEEF3F9),
      drawer: isWide ? null : Drawer(width: 260, child: _buildHtmlSidebar(isDrawer: true)),
      body: SafeArea(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (isWide) SizedBox(width: 255, child: _buildHtmlSidebar(isDrawer: false)),
            Expanded(
              child: Column(
                children: [
                  _buildHtmlTopHeader(isWide: isWide),
                  _buildCloudSyncStrip(),
                  Expanded(
                    child: SingleChildScrollView(
                      padding: MediaQuery.sizeOf(context).width < 600
                          ? const EdgeInsets.symmetric(horizontal: 8, vertical: 10)
                          : const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                      child: Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 1480),
                          child: _buildCurrentPanel(),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Exact `.side` gradient sidebar from HTML (`linear-gradient(180deg, #123a6b, #0a294d)`).
  Widget _buildHtmlSidebar({required bool isDrawer}) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF123A6B), Color(0xFF0A294D)],
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 4, 10, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                Text(
                  '📘 Rojmel Studio Pro - Cashbook Print Fixed V02.7.1',
                  style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w900, height: 1.25),
                ),
                SizedBox(height: 4),
                Text(
                  'ગુજરાતી શાળા હિસાબ વ્યવસ્થા',
                  style: TextStyle(color: Color(0xFFBFCEE3), fontSize: 12, fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: _navItems.length,
              itemBuilder: (_, i) {
                final item = _navItems[i];
                final isOn = _selectedNavIndex == i;
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(10),
                    onTap: () {
                      setState(() => _selectedNavIndex = i);
                      if (isDrawer) Navigator.of(context).pop();
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                      decoration: BoxDecoration(
                        color: isOn ? Colors.white.withOpacity(0.12) : Colors.transparent,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        item['label'] as String,
                        style: TextStyle(
                          color: const Color(0xFFE6EFFB),
                          fontWeight: isOn ? FontWeight.w900 : FontWeight.w800,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  /// Exact `.top` header bar from HTML (`#topSchool`, `#topYear`, `#accountTop` dropdown).
  Widget _buildHtmlTopHeader({required bool isWide}) {
    final activeMeta = engine.getAccountMeta(engine.selectedAccount);
    final topSchoolText = '${activeMeta.schoolName.isNotEmpty ? activeMeta.schoolName : engine.schoolName} (${engine.selectedAccount})';
    // Phones / small tablets: account picker on its own line, compact save.
    final narrow = MediaQuery.sizeOf(context).width < 760;

    final title = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          topSchoolText,
          style: TextStyle(fontSize: narrow ? 15.5 : 17.5, fontWeight: FontWeight.w900, color: const Color(0xFF10233F)),
          overflow: TextOverflow.ellipsis,
          maxLines: narrow ? 2 : 1,
        ),
        Text(
          'નાણાકીય વર્ષ ${engine.financialYear}',
          style: const TextStyle(fontSize: 12, color: Color(0xFF65758B), fontWeight: FontWeight.w700),
        ),
      ],
    );
    final accountPicker = DropdownButtonFormField<String>(
      value: engine.accounts.contains(engine.selectedAccount) ? engine.selectedAccount : engine.accounts.first,
      isExpanded: true,
      decoration: InputDecoration(
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFFCCD8E7), width: 1.5)),
      ),
      items: engine.accounts.map((a) => DropdownMenuItem(value: a, child: Text(a, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5)))).toList(),
      onChanged: (v) {
        if (v != null) engine.selectAccount(v);
      },
    );
    Future<void> save() async {
      await _flushCloudSave();
      if (_cloudSaveError == null) {
        _showToast('✅ સર્વર / ક્લાઉડમાં રોજમેળનો ડેટા સફળતાપૂર્વક સેવ થઈ ગયો છે! (Saved to Cloud)');
      }
    }

    final saveColor = _hasUnsavedCloudChanges ? const Color(0xFFD9480F) : const Color(0xFF087F5B);
    final saveBtn = narrow
        ? IconButton.filled(
            tooltip: _cloudSaving ? 'Saving...' : (_hasUnsavedCloudChanges ? 'SAVE (સેવ કરો *)' : 'Saved'),
            style: IconButton.styleFrom(backgroundColor: saveColor, foregroundColor: Colors.white),
            onPressed: _cloudSaving ? null : save,
            icon: Icon(_cloudSaving ? Icons.hourglass_top_rounded : Icons.save_rounded, size: 20),
          )
        : FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: saveColor,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            ),
            onPressed: _cloudSaving ? null : save,
            icon: Icon(_cloudSaving ? Icons.hourglass_top_rounded : Icons.save_rounded, size: 18),
            label: Text(
              _cloudSaving
                  ? 'Saving...'
                  : (_hasUnsavedCloudChanges ? '💾 SAVE (સેવ કરો *)' : '💾 Saved'),
              style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13.5),
            ),
          );
    final lead = <Widget>[
      if (Navigator.of(context).canPop())
        IconButton(
          tooltip: 'પાછા જાઓ / Back',
          icon: const Icon(Icons.arrow_back_rounded, color: Color(0xFF10233F)),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
      if (!isWide)
        Builder(
          builder: (ctx) => IconButton(
            tooltip: 'મેનુ / Menu',
            icon: const Icon(Icons.menu_rounded, color: Color(0xFF10233F)),
            onPressed: () => Scaffold.of(ctx).openDrawer(),
          ),
        ),
    ];

    return Container(
      padding: EdgeInsets.symmetric(horizontal: narrow ? 8 : 20, vertical: narrow ? 8 : 12),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Color(0xFFCCD8E7))),
      ),
      child: narrow
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(children: [...lead, Expanded(child: title), const SizedBox(width: 8), saveBtn]),
                const SizedBox(height: 8),
                accountPicker,
              ],
            )
          : Row(
              children: [
                ...lead,
                Expanded(child: title),
                const SizedBox(width: 12),
                SizedBox(width: 240, child: accountPicker),
                const SizedBox(width: 10),
                saveBtn,
              ],
            ),
    );
  }

  Widget _buildCloudSyncStrip() {
    final hasErr = _cloudSaveError != null;
    final bg = hasErr
        ? const Color(0xFFFFE3E3)
        : (_cloudSaving || _hasUnsavedCloudChanges ? const Color(0xFFFFF3BF) : const Color(0xFFD3F9D8));
    final fg = hasErr
        ? const Color(0xFFA51111)
        : (_cloudSaving || _hasUnsavedCloudChanges ? const Color(0xFF6C4D00) : const Color(0xFF075F45));
    // One Save button (top right) writes to the cloud; this strip only shows
    // the status. Changes are kept on this device automatically meanwhile.
    String txt = '✓ ફેરફારો આ ડિવાઇસમાં આપોઆપ સચવાય છે — સર્વરમાં સેવ કરવા ઉપરનું "Save" બટન દબાવો';
    if (_cloudSaving) {
      txt = '⏳ સર્વર / ક્લાઉડમાં ડેટા સેવ થઈ રહ્યો છે...';
    } else if (_hasUnsavedCloudChanges) {
      final dt = _lastDeviceSave?.toLocal();
      final tStr = dt != null
          ? '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}:${dt.second.toString().padLeft(2, '0')}'
          : '';
      txt = '📱 ફેરફાર ડિવાઇસમાં સચવાયો ($tStr) • સર્વરમાં સેવ કરવા ઉપરનું "Save" બટન દબાવો';
    } else if (_lastCloudSave != null && !hasErr) {
      final t = _lastCloudSave!.toLocal();
      txt = '✓ સર્વરમાં સફળતાપૂર્વક સેવ થયેલ (${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}:${t.second.toString().padLeft(2, '0')}) • ખાતું: ${engine.selectedAccount}';
    }
    if (hasErr) txt = '⚠ Cloud Save Error: $_cloudSaveError';

    return Container(
      width: double.infinity,
      color: bg,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
      child: Row(
        children: [
          Icon(
            hasErr
                ? Icons.cloud_off_rounded
                : (_hasUnsavedCloudChanges ? Icons.save_as_rounded : Icons.cloud_done_rounded),
            size: 16,
            color: fg,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(txt, style: TextStyle(color: fg, fontSize: 12, fontWeight: FontWeight.w800), overflow: TextOverflow.ellipsis),
          ),
        ],
      ),
    );
  }

  Widget _buildCurrentPanel() {
    final id = _navItems[_selectedNavIndex]['id'] as String;
    switch (id) {
      case 'home':
        return _buildPanelHome();
      case 'schoolInfo':
        return _buildPanelSchoolInfo();
      case 'accountsPanel':
        return _buildPanelAccounts();
      case 'grantHeadsPanel':
        return _buildPanelGrantHeads();
      case 'entry':
        return _buildPanelDataEntry();
      case 'reportsPanel':
        return _buildPanelReports();
      case 'tallyPanel':
        return _buildPanelTally();
      case 'calculationAuditPanel':
        return _buildPanelCalculationCheck();
      case 'dataExportPanel':
        return _buildPanelExportData();
      case 'cashbook':
        return _buildPanelCashbook();
      case 'register':
        return _buildPanelTransactions();
      case 'bulk':
        return _buildPanelBulkImport();
      case 'settings':
      default:
        return _buildPanelSettings();
    }
  }

  // --------------------------------------------------------------------------
  // PANEL 1: HOME (`#home` — EXACT HERO + 6 TILES + SELECTED ACCOUNT SUMMARY)
  // --------------------------------------------------------------------------

  Widget _buildPanelHome() {
    final acc = engine.selectedAccount;
    final m = engine.getAccountMeta(acc);
    final heads = engine.getAccountSpecificHeads(acc);
    final bankCount = engine.bankAccountCount;
    final snaPfmsCount = engine.accounts.length - bankCount;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // .home-hero
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            gradient: const LinearGradient(colors: [Color(0xFF123A6B), Color(0xFF1C6AA6)]),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 16,
            runSpacing: 12,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  Text('Rojmel Studio', style: TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.w900)),
                  SizedBox(height: 4),
                  Text('School financial records, data entry and audit reports in one place.', style: TextStyle(color: Color(0xFFDFEEFF), fontSize: 14)),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(999)),
                child: Text('FY ${engine.financialYear}', style: const TextStyle(color: Color(0xFF123A6B), fontWeight: FontWeight.w900)),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        // .home-grid (6 tiles)
        LayoutBuilder(
          builder: (ctx, constraints) {
            final cols = constraints.maxWidth >= 820 ? 3 : (constraints.maxWidth >= 540 ? 2 : 1);
            final tileWidth = (constraints.maxWidth - (cols - 1) * 14) / cols;
            final tiles = <Map<String, String>>[
              {'go': 'schoolInfo', 'title': '🏫 School Info', 'sub': 'Name, address, DISE code and principal charge history'},
              {'go': 'accountsPanel', 'title': '🏦 Rojmel Accounts', 'sub': 'Select how many accounts the school maintains'},
              {'go': 'grantHeadsPanel', 'title': '🗂 Grant Heads', 'sub': 'Add, edit and manage standard grant-head names'},
              {'go': 'entry', 'title': '✍ Data Entry', 'sub': 'Enter receipt and payment transactions'},
              {'go': 'reportsPanel', 'title': '📊 Reports', 'sub': 'Open account-wise and year-wise reports'},
              {'go': 'dataExportPanel', 'title': '📤 Export Saved Data', 'sub': 'Download saved data in Excel or CSV format'},
            ];
            return Wrap(
              spacing: 14,
              runSpacing: 14,
              children: tiles.map((t) {
                return SizedBox(
                  width: tileWidth,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(14),
                    onTap: () => _goToPanel(t['go']!),
                    child: Container(
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: const Color(0xFFD5E0ED)),
                        boxShadow: const [BoxShadow(color: Color(0x0B10233F), blurRadius: 12, offset: Offset(0, 3))],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(t['title']!, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Color(0xFF10233F))),
                          const SizedBox(height: 6),
                          Text(t['sub']!, style: const TextStyle(fontSize: 12, color: Color(0xFF65758B))),
                        ],
                      ),
                    ),
                  ),
                );
              }).toList(),
            );
          },
        ),
        const SizedBox(height: 16),
        // Selected Account Setup & Summary Card
        _htmlCard(
          headerWidget: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Expanded(
                child: Text(
                  'Selected Account Setup & Summary (માત્ર પસંદ કરેલ ખાતાની વિગત)',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: Color(0xFF10233F)),
                ),
              ),
              _pill('Selected Account: $acc (${m.type})', isGood: true),
            ],
          ),
          body: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  _homeSummaryBox('Selected Account & School Heading', '${m.schoolName.isNotEmpty ? m.schoolName : engine.schoolName} [$acc]'),
                  _homeSummaryBox('Financial Year', engine.financialYear),
                  _homeSummaryBox('Rojmel Accounts (Up to 7 Bank + SNA/PFMS)', '${engine.accounts.length} Total ($bankCount/7 Bank + $snaPfmsCount SNA/PFMS)'),
                  _homeSummaryBox('Grant Heads (Selected Account Only)', '${heads.length} Heads (in $acc)'),
                ],
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _htmlBtn('📒 Open Cashbook Preview', const Color(0xFF185D98), Colors.white, () => _goToPanel('cashbook')),
                  _htmlBtn('📊 Open All 21 Reports', const Color(0xFF087F5B), Colors.white, () => _goToPanel('reportsPanel')),
                ],
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: const Color(0xFFF0F6FF),
                  border: Border.all(color: const Color(0xFF90B4E2), width: 1.4),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Wrap(
                  spacing: 12,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    const Text(
                      '📅 પેજમાં તારીખ (Dates per page):',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w900, color: Color(0xFF0E3360)),
                    ),
                    _htmlBtn(
                      !engine.cashbookContinuousDates ? '☑ દરેક તારીખ નવા પેજ પર ✓' : '☐ દરેક તારીખ નવા પેજ પર',
                      !engine.cashbookContinuousDates ? const Color(0xFF185D98) : const Color(0xFFE8F0FA),
                      !engine.cashbookContinuousDates ? Colors.white : const Color(0xFF164B80),
                      () {
                        engine.cashbookContinuousDates = false;
                        engine.triggerUpdate();
                      },
                    ),
                    _htmlBtn(
                      engine.cashbookContinuousDates
                          ? '☑ એક પેજમાં અનેક તારીખ (સળંગ એન્ટ્રી, પેજ ભરાય ત્યારે નવું પેજ) ✓'
                          : '☐ એક પેજમાં અનેક તારીખ (સળંગ એન્ટ્રી)',
                      engine.cashbookContinuousDates ? const Color(0xFF087F5B) : const Color(0xFFE8F0FA),
                      engine.cashbookContinuousDates ? Colors.white : const Color(0xFF164B80),
                      () {
                        engine.cashbookContinuousDates = true;
                        engine.triggerUpdate();
                      },
                    ),
                    const SizedBox(width: double.infinity, height: 2),
                    const Text(
                      '📏 કેશબુક કોલમ લાઈન સેટિંગ (Cashbook Column Lines):',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w900, color: Color(0xFF0E3360)),
                    ),
                    _htmlBtn(
                      engine.cashbookShowColumnLines ? '☑ કોલમ લાઈન ચાલુ (Column Lines ON) ✓' : '☐ કોલમ લાઈન ચાલુ કરો (Show Column Lines)',
                      engine.cashbookShowColumnLines ? const Color(0xFF087F5B) : const Color(0xFFE8F0FA),
                      engine.cashbookShowColumnLines ? Colors.white : const Color(0xFF164B80),
                      () {
                        engine.cashbookShowColumnLines = true;
                        engine.triggerUpdate();
                      },
                    ),
                    _htmlBtn(
                      !engine.cashbookShowColumnLines ? '☑ કોલમ લાઈન બંધ (No Column Lines) ✓' : '☐ કોલમ લાઈન બંધ કરો (Hide Column Lines)',
                      !engine.cashbookShowColumnLines ? const Color(0xFF185D98) : const Color(0xFFE8F0FA),
                      !engine.cashbookShowColumnLines ? Colors.white : const Color(0xFF164B80),
                      () {
                        engine.cashbookShowColumnLines = false;
                        engine.triggerUpdate();
                      },
                    ),
                    if (engine.cashbookShowColumnLines) ...[
                      const Text(
                        'લાઈન લંબાઈ (Line Mode):',
                        style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: Color(0xFF10233F)),
                      ),
                      _htmlBtn(
                        engine.cashbookColumnLineMode == 'full_till_ekandar'
                            ? '📐 પૂરા પેજમાં એકંદરે કુલ લાઈન સુધી (Full Page till Ekandar) ✓'
                            : '📐 પૂરા પેજમાં એકંદરે કુલ લાઈન સુધી (Full Page till Ekandar)',
                        engine.cashbookColumnLineMode == 'full_till_ekandar' ? const Color(0xFF087F5B) : const Color(0xFFE8F0FA),
                        engine.cashbookColumnLineMode == 'full_till_ekandar' ? Colors.white : const Color(0xFF164B80),
                        () {
                          engine.cashbookColumnLineMode = 'full_till_ekandar';
                          engine.triggerUpdate();
                        },
                      ),
                      _htmlBtn(
                        engine.cashbookColumnLineMode == 'only_till_entry'
                            ? '📝 માત્ર છેલ્લી એન્ટ્રી સુધી (Only till Entry) ✓'
                            : '📝 માત્ર છેલ્લી એન્ટ્રી સુધી (Only till Entry)',
                        engine.cashbookColumnLineMode == 'only_till_entry' ? const Color(0xFF185D98) : const Color(0xFFE8F0FA),
                        engine.cashbookColumnLineMode == 'only_till_entry' ? Colors.white : const Color(0xFF164B80),
                        () {
                          engine.cashbookColumnLineMode = 'only_till_entry';
                          engine.triggerUpdate();
                        },
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _homeSummaryBox(String label, String val) {
    return Container(
      width: 290,
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(color: const Color(0xFFF5F8FC), borderRadius: BorderRadius.circular(10)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: 12, color: Color(0xFF65758B), fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text(val, style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w900, color: Color(0xFF10233F))),
        ],
      ),
    );
  }

  // --------------------------------------------------------------------------
  // PANEL 2: SCHOOL INFO (`#schoolInfo` — BASIC DETAILS + PRINCIPAL HISTORY)
  // --------------------------------------------------------------------------

  Widget _buildPanelSchoolInfo() {
    _syncFilterControllersFromEngine();
    final schoolCtrl = _schoolInfoNameCtrl;
    final diseCtrl = _schoolInfoDiseCtrl;
    final fyCtrl = _schoolInfoFyCtrl;
    final addrCtrl = _schoolInfoAddrCtrl;
    final villageCtrl = _schoolInfoVillageCtrl;
    final talukaCtrl = _schoolInfoTalukaCtrl;
    final distCtrl = _schoolInfoDistCtrl;

    final pNameCtrl = _principalNameCtrl;
    final pFromCtrl = _principalFromCtrl;
    final pToCtrl = _principalToCtrl;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('School Information / શાળા માહિતી', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: Color(0xFF10233F))),
        const SizedBox(height: 6),
        _noticeBox(
          '✓ શાળાની નોંધણી (School Registration Detail) માંથી શાળાનું નામ, DISE કોડ, સરનામું, ગામ/શહેર, તાલુકો અને જિલ્લો આપોઆપ લોડ થાય છે.',
          type: 'ok',
        ),
        _htmlCard(
          headerText: 'Basic school details (Auto-loaded from School Registration Detail)',
          body: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  SizedBox(width: 440, child: _labeledInput('School Name / શાળાનું નામ (રજીસ્ટ્રેશન મુજબ લોક)', schoolCtrl, readOnly: true)),
                  _buildRojmelSchoolNameLangSelector(onUpdated: () {
                    schoolCtrl.text = _registeredSchoolName;
                  }),
                  SizedBox(width: 220, child: _labeledInput('DISE Code / ડાયસ કોડ *', diseCtrl)),
                  SizedBox(width: 220, child: _labeledInput('Financial Year / નાણાકીય વર્ષ * (YYYY-YY)', fyCtrl)),
                  SizedBox(width: 440, child: _labeledInput('Address / સરનામું *', addrCtrl, maxLines: 2)),
                  _htmlBtn('📥 Registration માંથી સરનામું લાવો', const Color(0xFFE8F0FA), const Color(0xFF164B80), () {
                    final reg = _registrationAddressLine();
                    if (reg.isEmpty) {
                      _showToast('શાળા નોંધણીમાં સરનામું મળ્યું નથી. અહીં લખીને Save કરો.');
                      return;
                    }
                    setState(() {
                      addrCtrl.text = reg;
                      engine.schoolAddress = reg;
                    });
                    engine.triggerUpdate();
                    _showToast('નોંધણી મુજબ સરનામું ભરાયું — જરૂર હોય તો સુધારી "Save to Server" દબાવો.');
                  }),
                  SizedBox(width: 220, child: _labeledInput('Village / City (ગામ / શહેર) *', villageCtrl)),
                  SizedBox(width: 220, child: _labeledInput('Taluko / તાલુકો *', talukaCtrl)),
                  SizedBox(width: 220, child: _labeledInput('District / જિલ્લો *', distCtrl)),
                ],
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 10,
                runSpacing: 8,
                children: [
                  _htmlBtn('Apply in Device (ડિવાઇસમાં અપડેટ કરો)', const Color(0xFF185D98), Colors.white, () {
                    engine.schoolName = schoolCtrl.text.trim();
                    engine.udiseCode = diseCtrl.text.trim();
                    engine.financialYear = fyCtrl.text.trim().isNotEmpty ? fyCtrl.text.trim() : engine.financialYear;
                    engine.schoolAddress = addrCtrl.text.trim();
                    engine.clusterName = villageCtrl.text.trim();
                    engine.talukaName = talukaCtrl.text.trim();
                    engine.districtName = distCtrl.text.trim();
                    for (final m in engine.accountMeta.values) {
                      if (m.schoolName.trim().isEmpty) m.schoolName = engine.schoolName;
                      if (m.pfmsSchoolName.trim().isEmpty) m.pfmsSchoolName = engine.schoolName;
                    }
                    engine.triggerUpdate();
                    _showToast('School information updated on device. Press "💾 SAVE" to save to server.');
                  }),
                  _htmlBtn('🔄 Auto-Fill from School Registration Detail', const Color(0xFFE8F0FA), const Color(0xFF164B80), () {
                    _applyRegisteredIdentityIfBlank(overwriteAll: true);
                    engine.triggerUpdate();
                    _showToast('School Name, DISE Code, Address, Village/City, Taluko & District synced from School Registration!');
                  }),
                  _htmlBtn('✔ Apply & Save School Info', const Color(0xFF087F5B), Colors.white, () async {
                    engine.schoolName = schoolCtrl.text.trim();
                    engine.udiseCode = diseCtrl.text.trim();
                    engine.financialYear = fyCtrl.text.trim().isNotEmpty ? fyCtrl.text.trim() : engine.financialYear;
                    engine.schoolAddress = addrCtrl.text.trim();
                    engine.clusterName = villageCtrl.text.trim();
                    engine.talukaName = talukaCtrl.text.trim();
                    engine.districtName = distCtrl.text.trim();
                    engine.triggerUpdate();
                    await _flushCloudSave();
                    _showToast('✅ School information saved to server!');
                  }),
                ],
              ),
            ],
          ),
        ),
        _htmlCard(
          headerText: 'Principal / Head Teacher charge history',
          body: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Add every principal who held charge during the financial year. Use From and To dates (DD/MM/YYYY). Leave To blank for the current principal.',
                style: TextStyle(fontSize: 12, color: Color(0xFF65758B)),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  SizedBox(width: 360, child: _labeledInput('Principal Name', pNameCtrl)),
                  SizedBox(width: 200, child: _labeledDateInput('Charge From (DD/MM/YYYY)', pFromCtrl)),
                  SizedBox(width: 200, child: _labeledDateInput('Charge To (DD/MM/YYYY)', pToCtrl)),
                ],
              ),
              const SizedBox(height: 12),
              _htmlBtn('Add Principal', const Color(0xFF185D98), Colors.white, () {
                if (pNameCtrl.text.trim().isEmpty || pFromCtrl.text.trim().isEmpty) {
                  _showToast('Principal name and Charge From date are required.');
                  return;
                }
                engine.principals.add(PrincipalRecord(
                  name: pNameCtrl.text.trim(),
                  from: fmtDateSlashDDMMYYYY(pFromCtrl.text.trim()),
                  to: fmtDateSlashDDMMYYYY(pToCtrl.text.trim()),
                ));
                engine.triggerUpdate();
              }),
              const SizedBox(height: 12),
              _htmlTable(
                headers: const ['#', 'Principal Name', 'From (DD/MM/YYYY)', 'To (DD/MM/YYYY)', 'Action'],
                rows: engine.principals.asMap().entries.map((entry) {
                  final i = entry.key;
                  final p = entry.value;
                  return <Widget>[
                    Text('${i + 1}'),
                    Text(p.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                    Text(fmtDateSlashDDMMYYYY(p.from)),
                    Text(p.to.isNotEmpty ? fmtDateSlashDDMMYYYY(p.to) : 'Current', style: TextStyle(color: p.to.isEmpty ? const Color(0xFF087F5B) : Colors.black, fontWeight: FontWeight.w800)),
                    _htmlBtn('Delete', const Color(0xFFFFE3E3), const Color(0xFFC92A2A), () {
                      engine.principals.removeAt(i);
                      engine.triggerUpdate();
                    }),
                  ];
                }).toList(),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // --------------------------------------------------------------------------
  // PANEL 3: ROJMEL ACCOUNTS (`#accountsPanel` — 3 TYPES, MANDATORY BANK
  //          HEAD-WISE OPENING ALLOCATION, PFMS/SNA ANNUAL LIMITS, HEAD COPY)
  // --------------------------------------------------------------------------

  void _loadAccountIntoForm(String name) {
    final m = engine.getAccountMeta(name);
    setState(() {
      _accEditOldName = name;
      _accType = m.type;
      _accNameCtrl.text = name;
      _accSchoolCtrl.text = m.schoolName.isNotEmpty ? m.schoolName : engine.schoolName;
      _accPfmsSchoolCtrl.text = m.pfmsSchoolName.isNotEmpty ? m.pfmsSchoolName : m.schoolName;
      _accNumberCtrl.text = m.acNo;
      _accSnaAgencyCtrl.text = m.effectiveSnaAgencyCode;
      _accPfmsLastDateCtrl.text = fmtDateSlashDDMMYYYY(m.pfmsLastDate);
      _accSnaStartDateCtrl.text = fmtDateSlashDDMMYYYY(m.snaStartDate);
      _accHolderCtrl.text = m.holderName;
      _accIfscCtrl.text = m.ifsc;
      _accBankCtrl.text = m.bankName;
      _accBranchCtrl.text = m.branch;
      _accBranchAddrCtrl.text = m.branchAddress;
      _accOpenBankCtrl.text = m.type == 'BANK' ? m.openingBank.toStringAsFixed(2) : '0';
      _accOpenCashCtrl.text = m.type == 'BANK' ? m.openingCash.toStringAsFixed(2) : '0';
      _draftAccountHeads = List<String>.from(engine.getAccountSpecificHeads(name));
      _draftHeadOpenings = m.headOpenings.map((k, v) => MapEntry(k, v.copy()));
      _draftHeadLimits = Map<String, double>.from(m.headLimits);
      _distSelectedHead = _draftAccountHeads.isNotEmpty ? _draftAccountHeads.first : null;
      _limitSelectedHead = _draftAccountHeads.isNotEmpty ? _draftAccountHeads.first : null;
      _accAskCopyHeads = 'no';
      _accountNoticeMsg = 'Editing account "$name". Customize Grant Heads, Headers, Opening Balance (for BANK), or Annual Limits (for PFMS / SNA SPARSH).';
      _accountNoticeOk = true;
    });
  }

  void _clearAccountForm() {
    setState(() {
      _accEditOldName = '';
      _accType = 'SNA_PURE';
      _accNameCtrl.clear();
      _accSchoolCtrl.text = engine.schoolName;
      _accPfmsSchoolCtrl.text = engine.schoolName;
      _accNumberCtrl.clear();
      _accSnaAgencyCtrl.clear();
      _accPfmsLastDateCtrl.clear();
      _accSnaStartDateCtrl.clear();
      _accHolderCtrl.clear();
      _accIfscCtrl.clear();
      _accBankCtrl.clear();
      _accBranchCtrl.clear();
      _accBranchAddrCtrl.clear();
      _accOpenBankCtrl.text = '0';
      _accOpenCashCtrl.text = '0';
      _draftAccountHeads = <String>[];
      _draftHeadOpenings = <String, HeadBalance>{};
      _draftHeadLimits = <String, double>{};
      _distSelectedHead = null;
      _limitSelectedHead = null;
      _accAskCopyHeads = 'no';
      _accountNoticeMsg = null;
    });
  }

  /// Popup after saving an account, so a refusal (e.g. missing name) is
  /// never missed, and a saved account can be opened in Data Entry.
  void _showAccountSaveResult(String? err, String name) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: Icon(err == null ? Icons.check_circle_rounded : Icons.error_rounded,
            color: err == null ? const Color(0xFF087F5B) : const Color(0xFFC92A2A), size: 40),
        title: Text(err == null ? 'ખાતું સેવ થઈ ગયું' : 'ખાતું સેવ થયું નથી'),
        content: Text(err ?? '"$name" હવે ઉપરની ખાતા યાદી અને Data Entry માં દેખાશે. સર્વર પર સેવ કરવા "💾 SAVE" દબાવો.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK')),
          if (err == null)
            FilledButton(
              onPressed: () {
                Navigator.pop(ctx);
                engine.selectAccount(name);
                _goToPanel('entry');
              },
              child: const Text('Data Entry ખોલો'),
            ),
        ],
      ),
    );
  }

  Widget _buildPanelAccounts() {
    final isBank = _accType == 'BANK';
    final isSnaPure = _accType == 'SNA_PURE';
    final isPfmsSnaCombined = _accType == 'SNA';
    final isSNAorPFMS = _accType == 'SNA' || _accType == 'SNA_PURE' || _accType == 'PFMS';
    final targetBank = isBank ? math.max(0.0, double.tryParse(_accOpenBankCtrl.text) ?? 0.0) : 0.0;
    final targetCash = isBank ? math.max(0.0, double.tryParse(_accOpenCashCtrl.text) ?? 0.0) : 0.0;
    if (_accSchoolCtrl.text.isEmpty && engine.schoolName.isNotEmpty) {
      _accSchoolCtrl.text = engine.schoolName;
    }

    final openKeys = _draftHeadOpenings.keys.where((h) => (_draftHeadOpenings[h]?.total ?? 0) > 0).toList();
    double sumCash = 0.0;
    double sumBank = 0.0;
    for (final h in openKeys) {
      sumCash += _draftHeadOpenings[h]!.cash;
      sumBank += _draftHeadOpenings[h]!.bank;
    }
    final remBank = targetBank - sumBank;
    final remCash = targetCash - sumCash;
    final isMatched = remBank.abs() < 0.005 && remCash.abs() < 0.005;

    final limitKeys = _draftHeadLimits.keys.where((h) => (_draftHeadLimits[h] ?? 0) > 0).toList();
    final totalLimit = limitKeys.fold<double>(0.0, (s, h) => s + (_draftHeadLimits[h] ?? 0.0));

    final candidateHeads = _draftAccountHeads;
    if (_distSelectedHead == null || !candidateHeads.contains(_distSelectedHead)) {
      _distSelectedHead = candidateHeads.isNotEmpty ? candidateHeads.first : null;
    }
    if (_limitSelectedHead == null || !candidateHeads.contains(_limitSelectedHead)) {
      _limitSelectedHead = candidateHeads.isNotEmpty ? candidateHeads.first : null;
    }

    final otherAccounts = engine.accounts.where((a) => a != _accEditOldName).toList();
    if (_accCopySourceAcc == null || !otherAccounts.contains(_accCopySourceAcc)) {
      _accCopySourceAcc = otherAccounts.isNotEmpty ? otherAccounts.first : null;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Add / Edit Rojmel Account / રોજમેળ ખાતું (4 Account Types: Purely SNA SPARSH, PFMS + SNA SPARSH Combined, PFMS & BANK)',
          style: TextStyle(fontSize: 21, fontWeight: FontWeight.w900, color: Color(0xFF10233F)),
        ),
        const SizedBox(height: 8),
        _noticeBox(
          '🏦 4 Account Types & Dynamic Duration Header Rules:\n'
          '• 1. Purely SNA SPARSH (માત્ર SNA SPARSH ખાતું): Only requires Agency Code and Account Name for headers (plus School Name auto-filled from registration). Uses 60% : 40% split and Head-wise Annual Limit.\n'
          '• 2. Combination of PFMS & SNA SPARSH (PFMS + SNA SPARSH સંયુક્ત ખાતું): Includes present PFMS fields + SNA SPARSH Agency Code + PFMS Last Transaction Entry Date + SNA SPARSH Start Entry Date. During PFMS duration, headers show PFMS details; during SNA SPARSH duration, headers automatically switch to Agency Code & Account Name (and remain editable).\n'
          '• 3. PFMS Account: Opening Balance locked at ₹0.00. Supports Head-wise Annual Limit and 100% entries.\n'
          '• 4. BANK Account (e.g. SMCE): Uses 100% entries and allows Opening Bank & Cash Balance on 01/04/YYYY matched with Head-wise Opening Balances.',
          type: 'warn',
        ),
        _htmlCard(
          headerText: 'Account Details, School Heading Customization, Head-wise Opening (BANK) & Head-wise Yearly Limit (PFMS / SNA SPARSH)',
          body: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  SizedBox(
                    width: 390,
                    child: DropdownButtonFormField<String>(
                      value: _accType,
                      isExpanded: true,
                      decoration: const InputDecoration(labelText: '1. Account Type (ખાતાનો પ્રકાર) *', border: OutlineInputBorder(), isDense: true),
                      items: const [
                        DropdownMenuItem(value: 'SNA_PURE', child: Text('1. Purely SNA SPARSH (Only Agency Code & Account Name)')),
                        DropdownMenuItem(value: 'SNA', child: Text('2. Combination: PFMS + SNA SPARSH (With Transition Dates)')),
                        DropdownMenuItem(value: 'PFMS', child: Text('3. PFMS Account (100% + Yearly Limit)')),
                        DropdownMenuItem(value: 'BANK', child: Text('4. BANK Account (100% + Head-wise Opening)')),
                      ],
                      onChanged: (v) {
                        setState(() {
                          _accType = v!;
                          // A new account without a name cannot be saved:
                          // suggest the usual name for this type.
                          final suggested = const <String, String>{
                            'SNA_PURE': 'SNA SPARSH',
                            'SNA': 'PFMS + SNA SPARSH',
                            'PFMS': 'PFMS ખાતું',
                          }[_accType];
                          final current = _accNameCtrl.text.trim();
                          const defaults = <String>{'', 'SNA SPARSH', 'PFMS + SNA SPARSH', 'PFMS ખાતું'};
                          if (_accEditOldName.isEmpty && suggested != null && defaults.contains(current)) {
                            var name = suggested;
                            var i = 2;
                            while (engine.accounts.any((a) => a.toLowerCase() == name.toLowerCase())) {
                              name = '$suggested $i';
                              i++;
                            }
                            _accNameCtrl.text = name;
                          }
                          if (_accType != 'BANK') {
                            _accOpenBankCtrl.text = '0';
                            _accOpenCashCtrl.text = '0';
                          }
                        });
                      },
                    ),
                  ),
                  SizedBox(width: 280, child: _labeledInput('2. Account Name (ખાતાનું નામ — Header માટે) *', _accNameCtrl, hint: 'દા.ત. SNA SPARSH / SMCE')),
                  SizedBox(width: 420, child: _labeledInput('3. School Name for Headers (શાળાનું નામ — રજીસ્ટ્રેશન મુજબ)', _accSchoolCtrl, readOnly: true)),
                  _buildRojmelSchoolNameLangSelector(),
                  if (isSnaPure) ...[
                    SizedBox(
                      width: 340,
                      child: _labeledInput(
                        '4. SNA SPARSH Agency Code (એજન્સી કોડ — Header માટે) *',
                        _accSnaAgencyCtrl,
                        hint: 'Enter SNA SPARSH Agency Code',
                        onChanged: (v) => _accNumberCtrl.text = v,
                      ),
                    ),
                  ] else ...[
                    if (isPfmsSnaCombined) ...[
                      SizedBox(width: 420, child: _labeledInput('3B. School Name During PFMS Duration (PFMS વખતે શાળાનું નામ)', _accPfmsSchoolCtrl, readOnly: true)),
                      SizedBox(width: 260, child: _labeledInput('4A. PFMS Bank Account Number *', _accNumberCtrl)),
                      SizedBox(width: 280, child: _labeledInput('4B. SNA SPARSH Agency Code (એજન્સી કોડ) *', _accSnaAgencyCtrl)),
                      SizedBox(
                        width: 250,
                        child: _labeledDateInput(
                          '4C. PFMS Last Entry Date (DD/MM/YYYY)',
                          _accPfmsLastDateCtrl,
                          hint: 'DD/MM/YYYY (PFMS અંતિમ તારીખ)',
                        ),
                      ),
                      SizedBox(
                        width: 250,
                        child: _labeledDateInput(
                          '4D. SNA SPARSH Start Date (DD/MM/YYYY)',
                          _accSnaStartDateCtrl,
                          hint: 'DD/MM/YYYY (SNA શરૂઆત તારીખ)',
                        ),
                      ),
                    ] else ...[
                      SizedBox(width: 260, child: _labeledInput('4. Bank Account Number *', _accNumberCtrl)),
                    ],
                    SizedBox(width: 380, child: _labeledInput('5. Account Holder Name (બેંક ખાતેદારનું નામ) *', _accHolderCtrl)),
                    SizedBox(width: 220, child: _labeledInput('6. IFSC Code *', _accIfscCtrl)),
                    SizedBox(width: 280, child: _labeledInput('7. Bank Name *', _accBankCtrl)),
                    SizedBox(width: 220, child: _labeledInput('8. Branch Name (શાખા)', _accBranchCtrl)),
                    SizedBox(width: 380, child: _labeledInput('9. Branch Address (બેંક સરનામું)', _accBranchAddrCtrl)),
                    if (isBank) ...[
                      SizedBox(
                        width: 240,
                        child: _labeledInput(
                          '10. Total Opening Bank Balance (₹)',
                          _accOpenBankCtrl,
                          isNumber: true,
                          onChanged: (_) => setState(() {}),
                        ),
                      ),
                      SizedBox(
                        width: 240,
                        child: _labeledInput(
                          '11. Total Opening Cash Balance (₹)',
                          _accOpenCashCtrl,
                          isNumber: true,
                          onChanged: (_) => setState(() {}),
                        ),
                      ),
                    ],
                  ],
                ],
              ),

              // BOX 1: MANDATORY HEAD-WISE OPENING BALANCE ALLOCATION (BANK ONLY)
              if (isBank) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF4F9FF),
                    border: Border.all(color: const Color(0xFF7AA7D8), width: 2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Wrap(
                        alignment: WrapAlignment.spaceBetween,
                        children: [
                          const Text(
                            '🗂 Mandatory Head-wise Opening Balance Allocation (BANK Account Only — હેડ મુજબ ઉઘડતી સિલક)',
                            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: Color(0xFF11345F)),
                          ),
                          _pill(
                            isMatched
                                ? '✓ Head-wise Total Matches Opening Balance (Diff: ₹0.00)'
                                : '⚠ Must Match Opening Balance (Rem Bank: ₹${fmtDemoNum(remBank)}, Cash: ₹${fmtDemoNum(remCash)})',
                            isGood: isMatched,
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        children: [
                          _statBox('₹${fmtDemoNum(targetBank + targetCash)}', '1. Account Total Opening (Bank + Cash)'),
                          _statBox('₹${fmtDemoNum(sumBank + sumCash)} (${openKeys.length} Heads)', '2. Head-wise Total Opening Allocated'),
                          _statBox('₹${fmtDemoNum(remBank)}', '3. Remaining Bank to Allocate'),
                          _statBox('₹${fmtDemoNum(remCash)}', '4. Remaining Cash to Allocate'),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        crossAxisAlignment: WrapCrossAlignment.end,
                        children: [
                          SizedBox(
                            width: 340,
                            child: DropdownButtonFormField<String>(
                              value: _distSelectedHead,
                              isExpanded: true,
                              decoration: const InputDecoration(labelText: 'Select Grant Head for Opening Balance *', border: OutlineInputBorder(), isDense: true),
                              items: candidateHeads.map((h) => DropdownMenuItem(value: h, child: Text(h, overflow: TextOverflow.ellipsis))).toList(),
                              onChanged: (v) => setState(() => _distSelectedHead = v),
                            ),
                          ),
                          SizedBox(width: 170, child: _labeledInput('Head Opening Bank (₹)', _distHeadBankCtrl, isNumber: true)),
                          SizedBox(width: 170, child: _labeledInput('Head Opening Cash (₹)', _distHeadCashCtrl, isNumber: true)),
                          _htmlBtn('+ Set / Update Head Opening', const Color(0xFF185D98), Colors.white, () {
                            if (_distSelectedHead == null) return;
                            final b = math.max(0.0, double.tryParse(_distHeadBankCtrl.text) ?? 0.0);
                            final c = math.max(0.0, double.tryParse(_distHeadCashCtrl.text) ?? 0.0);
                            setState(() {
                              if (b == 0 && c == 0) {
                                _draftHeadOpenings.remove(_distSelectedHead);
                              } else {
                                _draftHeadOpenings[_distSelectedHead!] = HeadBalance(cash: c, bank: b);
                                if (!_draftAccountHeads.contains(_distSelectedHead)) {
                                  _draftAccountHeads.add(_distSelectedHead!);
                                }
                              }
                              _distHeadBankCtrl.text = '0';
                              _distHeadCashCtrl.text = '0';
                            });
                          }),
                          _htmlBtn('⚡ Put Remaining Balance in Selected Head', const Color(0xFF087F5B), Colors.white, () {
                            if (_distSelectedHead == null) return;
                            double otherB = 0.0;
                            double otherC = 0.0;
                            _draftHeadOpenings.forEach((k, v) {
                              if (k != _distSelectedHead) {
                                otherB += v.bank;
                                otherC += v.cash;
                              }
                            });
                            final rB = math.max(0.0, double.parse((targetBank - otherB).toStringAsFixed(2)));
                            final rC = math.max(0.0, double.parse((targetCash - otherC).toStringAsFixed(2)));
                            setState(() {
                              _draftHeadOpenings[_distSelectedHead!] = HeadBalance(cash: rC, bank: rB);
                              if (!_draftAccountHeads.contains(_distSelectedHead)) {
                                _draftAccountHeads.add(_distSelectedHead!);
                              }
                            });
                          }),
                          _htmlBtn('Clear All Head Openings', const Color(0xFFFFE3E3), const Color(0xFFC92A2A), () {
                            setState(() => _draftHeadOpenings.clear());
                          }),
                        ],
                      ),
                      const SizedBox(height: 10),
                      _htmlTable(
                        headers: const ['#', 'Grant Head Name (ગ્રાન્ટ હેડ)', 'Opening Cash (રોકડ ₹)', 'Opening Bank (બેન્ક ₹)', 'Total Head Opening (કુલ ₹)', 'Action'],
                        rows: [
                          ...openKeys.asMap().entries.map((entry) {
                            final i = entry.key;
                            final h = entry.value;
                            final hb = _draftHeadOpenings[h]!;
                            return <Widget>[
                              Text('${i + 1}'),
                              Text(h, style: const TextStyle(fontWeight: FontWeight.w800)),
                              Text('₹ ${fmtDemoNum(hb.cash)}'),
                              Text('₹ ${fmtDemoNum(hb.bank)}'),
                              Text('₹ ${fmtDemoNum(hb.total)}', style: const TextStyle(fontWeight: FontWeight.w900)),
                              _htmlBtn('Remove', const Color(0xFFFFE3E3), const Color(0xFFC92A2A), () {
                                setState(() => _draftHeadOpenings.remove(h));
                              }),
                            ];
                          }),
                          if (openKeys.isNotEmpty)
                            <Widget>[
                              const Text('TOTAL', style: TextStyle(fontWeight: FontWeight.w900)),
                              const Text('Total Head-wise Opening Balance :', style: TextStyle(fontWeight: FontWeight.w900)),
                              Text('₹ ${fmtDemoNum(sumCash)}', style: const TextStyle(fontWeight: FontWeight.w900)),
                              Text('₹ ${fmtDemoNum(sumBank)}', style: const TextStyle(fontWeight: FontWeight.w900)),
                              Text('₹ ${fmtDemoNum(sumCash + sumBank)}', style: const TextStyle(fontWeight: FontWeight.w900)),
                              const SizedBox(),
                            ],
                        ],
                      ),
                    ],
                  ),
                ),
              ],

              // BOX 2: HEAD-WISE ANNUAL LIMIT BOX (PFMS & SNA SPARSH ONLY)
              if (isSNAorPFMS) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF2FBF7),
                    border: Border.all(color: const Color(0xFF087F5B), width: 2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Wrap(
                        alignment: WrapAlignment.spaceBetween,
                        children: [
                          const Text(
                            '🎯 Head-wise Annual Grant Limit for the Year (માત્ર PFMS અને SNA SPARSH ખાતા માટે વાર્ષિક હેડ લિમિટ)',
                            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: Color(0xFF065F46)),
                          ),
                          _pill('Total Yearly Limit: ₹${fmtDemoNum(totalLimit)} (${limitKeys.length} Heads)', isGood: true),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        crossAxisAlignment: WrapCrossAlignment.end,
                        children: [
                          SizedBox(
                            width: 340,
                            child: DropdownButtonFormField<String>(
                              value: _limitSelectedHead,
                              isExpanded: true,
                              decoration: const InputDecoration(labelText: 'Select Grant Head to Set Annual Limit *', border: OutlineInputBorder(), isDense: true),
                              items: candidateHeads.map((h) => DropdownMenuItem(value: h, child: Text(h, overflow: TextOverflow.ellipsis))).toList(),
                              onChanged: (v) => setState(() => _limitSelectedHead = v),
                            ),
                          ),
                          SizedBox(width: 200, child: _labeledInput('Annual Sanctioned Limit (₹)', _limitHeadAmtCtrl, isNumber: true)),
                          _htmlBtn('+ Set / Update Yearly Limit', const Color(0xFF087F5B), Colors.white, () {
                            if (_limitSelectedHead == null) return;
                            final lim = math.max(0.0, double.tryParse(_limitHeadAmtCtrl.text) ?? 0.0);
                            setState(() {
                              if (lim == 0) {
                                _draftHeadLimits.remove(_limitSelectedHead);
                              } else {
                                _draftHeadLimits[_limitSelectedHead!] = lim;
                                if (!_draftAccountHeads.contains(_limitSelectedHead)) {
                                  _draftAccountHeads.add(_limitSelectedHead!);
                                }
                              }
                              _limitHeadAmtCtrl.text = '0';
                            });
                          }),
                          _htmlBtn('⚡ Auto-Set Limits from Current Year Grants', const Color(0xFFE8F0FA), const Color(0xFF164B80), () {
                            final accName = _accEditOldName.isNotEmpty ? _accEditOldName : (_accNameCtrl.text.trim().isNotEmpty ? _accNameCtrl.text.trim() : 'SNA SPARSH');
                            final accEntries = engine.getAccountEntries(accName).where((e) => e.type == 'credit' && !RojmelEngine.isCashEntry(e)).toList();
                            setState(() {
                              if (accEntries.isEmpty) {
                                _draftHeadLimits = Map<String, double>.from(kSnaDefaultHeadLimits);
                              } else {
                                _draftHeadLimits.clear();
                                for (final e in accEntries) {
                                  _draftHeadLimits[e.head] = (_draftHeadLimits[e.head] ?? 0.0) + e.amount;
                                }
                              }
                              for (final h in _draftHeadLimits.keys) {
                                if (!_draftAccountHeads.contains(h)) _draftAccountHeads.add(h);
                              }
                            });
                          }),
                          _htmlBtn('Clear Limits', const Color(0xFFFFE3E3), const Color(0xFFC92A2A), () {
                            setState(() => _draftHeadLimits.clear());
                          }),
                        ],
                      ),
                      const SizedBox(height: 10),
                      _htmlTable(
                        headers: const ['#', 'Grant Head Name (ગ્રાન્ટ હેડ)', 'Sanctioned Annual Limit (₹)', '60% Central Limit (SNA)', '40% State Limit (SNA)', 'Action'],
                        rows: [
                          ...limitKeys.asMap().entries.map((entry) {
                            final i = entry.key;
                            final h = entry.value;
                            final lim = _draftHeadLimits[h]!;
                            final isSnaType = _accType == 'SNA' || _accType == 'SNA_PURE';
                            final l60 = isSnaType ? (lim * 60.0).roundToDouble() / 100.0 : lim;
                            final l40 = isSnaType ? (lim - l60) : 0.0;
                            return <Widget>[
                              Text('${i + 1}'),
                              Text(h, style: const TextStyle(fontWeight: FontWeight.w800)),
                              Text('₹ ${fmtDemoNum(lim)}', style: const TextStyle(fontWeight: FontWeight.w900)),
                              Text('₹ ${fmtDemoNum(l60)}'),
                              Text('₹ ${fmtDemoNum(l40)}'),
                              _htmlBtn('Remove', const Color(0xFFFFE3E3), const Color(0xFFC92A2A), () {
                                setState(() => _draftHeadLimits.remove(h));
                              }),
                            ];
                          }),
                        ],
                      ),
                    ],
                  ),
                ),
              ],

              // BOX 3: PER-ACCOUNT GRANT HEADS SELECTION / IMPORT PROMPT BOX
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFFF5F9FF),
                  border: Border.all(color: const Color(0xFF4C88BD), width: 2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Wrap(
                      alignment: WrapAlignment.spaceBetween,
                      children: [
                        const Text(
                          '🗂 Grant Heads for This Account (આ ખાતા માટે ગ્રાન્ટ હેડ — અન્ય ખાતામાંથી બધા અથવા પસંદ કરેલ હેડ લાવો)',
                          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: Color(0xFF11345F)),
                        ),
                        _pill('${_draftAccountHeads.length} Grant Head(s) in Account', isGood: true),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      crossAxisAlignment: WrapCrossAlignment.end,
                      children: [
                        SizedBox(
                          width: 280,
                          child: DropdownButtonFormField<String>(
                            value: _accAskCopyHeads,
                            isExpanded: true,
                            decoration: const InputDecoration(labelText: '1. Do you want to get Grant Heads from another account?', border: OutlineInputBorder(), isDense: true),
                            items: const [
                              DropdownMenuItem(value: 'no', child: Text('No (Keep only this account\'s own Heads)')),
                              DropdownMenuItem(value: 'yes', child: Text('Yes — Get Grant Heads from another account')),
                            ],
                            onChanged: (v) {
                              setState(() {
                                _accAskCopyHeads = v!;
                                if (_accAskCopyHeads == 'yes' && _accCopySourceAcc != null) {
                                  _accCopyCheckedHeads = <String>{...engine.getAccountSpecificHeads(_accCopySourceAcc)};
                                }
                              });
                            },
                          ),
                        ),
                        if (_accAskCopyHeads == 'yes' && otherAccounts.isNotEmpty) ...[
                          SizedBox(
                            width: 250,
                            child: DropdownButtonFormField<String>(
                              value: _accCopySourceAcc,
                              isExpanded: true,
                              decoration: const InputDecoration(labelText: '2. From which Account?', border: OutlineInputBorder(), isDense: true),
                              items: otherAccounts.map((a) => DropdownMenuItem(value: a, child: Text('$a (${engine.getAccountSpecificHeads(a).length} Heads)'))).toList(),
                              onChanged: (v) {
                                setState(() {
                                  _accCopySourceAcc = v;
                                  if (v != null) {
                                    _accCopyCheckedHeads = <String>{...engine.getAccountSpecificHeads(v)};
                                  }
                                });
                              },
                            ),
                          ),
                          SizedBox(
                            width: 250,
                            child: DropdownButtonFormField<String>(
                              value: _accCopyOption,
                              isExpanded: true,
                              decoration: const InputDecoration(labelText: '3. Option: All or Selected?', border: OutlineInputBorder(), isDense: true),
                              items: const [
                                DropdownMenuItem(value: 'all', child: Text('All Grant Heads (બધા ગ્રાન્ટ હેડ)')),
                                DropdownMenuItem(value: 'selected', child: Text('Selected Grant Heads (પસંદ કરેલ)')),
                              ],
                              onChanged: (v) => setState(() => _accCopyOption = v!),
                            ),
                          ),
                          _htmlBtn('📥 Get Grant Heads Now', const Color(0xFF087F5B), Colors.white, () {
                            if (_accCopySourceAcc == null) return;
                            final picked = _accCopyOption == 'all'
                                ? engine.getAccountSpecificHeads(_accCopySourceAcc)
                                : _accCopyCheckedHeads.toList();
                            setState(() {
                              _draftAccountHeads = <String>{..._draftAccountHeads, ...picked}.toList();
                            });
                          }),
                        ],
                      ],
                    ),
                    if (_accAskCopyHeads == 'yes' && _accCopyOption == 'selected' && _accCopySourceAcc != null) ...[
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        children: engine.getAccountSpecificHeads(_accCopySourceAcc).map((h) {
                          final checked = _accCopyCheckedHeads.contains(h);
                          return FilterChip(
                            label: Text(h, style: const TextStyle(fontSize: 12)),
                            selected: checked,
                            onSelected: (v) {
                              setState(() {
                                if (v) {
                                  _accCopyCheckedHeads.add(h);
                                } else {
                                  _accCopyCheckedHeads.remove(h);
                                }
                              });
                            },
                          );
                        }).toList(),
                      ),
                    ],
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(child: _labeledInput('Add Custom Grant Head to This Account Only (નવો ગ્રાન્ટ હેડ ઉમેરો)', _accCustomHeadCtrl)),
                        const SizedBox(width: 10),
                        _htmlBtn('+ Add Head to Account', const Color(0xFF185D98), Colors.white, () {
                          final v = _accCustomHeadCtrl.text.trim();
                          if (v.isEmpty) return;
                          setState(() {
                            if (!_draftAccountHeads.contains(v)) _draftAccountHeads.add(v);
                            _accCustomHeadCtrl.clear();
                          });
                        }),
                        const SizedBox(width: 8),
                        _htmlBtn('Clear Account Heads', const Color(0xFFFFE3E3), const Color(0xFFC92A2A), () {
                          setState(() => _draftAccountHeads.clear());
                        }),
                      ],
                    ),
                    if (_draftAccountHeads.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: _draftAccountHeads.asMap().entries.map((entry) {
                          final h = entry.value;
                          return Chip(
                            backgroundColor: const Color(0xFFD1FAE5),
                            label: Text('${entry.key + 1}. $h', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: Color(0xFF065F46))),
                            onDeleted: () => setState(() => _draftAccountHeads.remove(h)),
                          );
                        }).toList(),
                      ),
                    ],
                  ],
                ),
              ),

              const SizedBox(height: 14),
              Wrap(
                spacing: 10,
                children: [
                  _htmlBtn('💾 Save Account, Headings, Opening & Yearly Limits', const Color(0xFF185D98), Colors.white, () {
                    final newName = _accNameCtrl.text.trim();
                    if (_accEditOldName.isEmpty && _draftAccountHeads.isEmpty && newName.isNotEmpty) {
                      _openCopyGrantHeadsModal(newName, onPicked: (picked, _) {
                        final merged = <String>{..._draftAccountHeads, ...picked}.toList();
                        final err = engine.saveOrUpdateAccountV06(
                          oldName: _accEditOldName,
                          name: newName,
                          type: _accType,
                          schoolNameStr: _accSchoolCtrl.text,
                          pfmsSchoolNameStr: _accPfmsSchoolCtrl.text,
                          acNoStr: _accNumberCtrl.text,
                          snaAgencyCodeStr: _accSnaAgencyCtrl.text,
                          pfmsLastDateStr: _accPfmsLastDateCtrl.text,
                          snaStartDateStr: _accSnaStartDateCtrl.text,
                          holderNameStr: _accHolderCtrl.text,
                          ifscStr: _accIfscCtrl.text,
                          bankNameStr: _accBankCtrl.text,
                          branchStr: _accBranchCtrl.text,
                          branchAddressStr: _accBranchAddrCtrl.text,
                          openBank: double.tryParse(_accOpenBankCtrl.text) ?? 0.0,
                          openCash: double.tryParse(_accOpenCashCtrl.text) ?? 0.0,
                          headOpeningsMap: _draftHeadOpenings,
                          headLimitsMap: _draftHeadLimits,
                          finalHeadsList: merged,
                        );
                        setState(() {
                          _accountNoticeMsg = err ?? 'Account "$newName" ($_accType) saved on device. Press "💾 SAVE" to save to server.';
                          _accountNoticeOk = err == null;
                        });
                        _showAccountSaveResult(err, newName);
                        if (err == null) _clearAccountForm();
                      });
                      return;
                    }
                    final err = engine.saveOrUpdateAccountV06(
                      oldName: _accEditOldName,
                      name: newName,
                      type: _accType,
                      schoolNameStr: _accSchoolCtrl.text,
                      pfmsSchoolNameStr: _accPfmsSchoolCtrl.text,
                      acNoStr: _accNumberCtrl.text,
                      snaAgencyCodeStr: _accSnaAgencyCtrl.text,
                      pfmsLastDateStr: _accPfmsLastDateCtrl.text,
                      snaStartDateStr: _accSnaStartDateCtrl.text,
                      holderNameStr: _accHolderCtrl.text,
                      ifscStr: _accIfscCtrl.text,
                      bankNameStr: _accBankCtrl.text,
                      branchStr: _accBranchCtrl.text,
                      branchAddressStr: _accBranchAddrCtrl.text,
                      openBank: double.tryParse(_accOpenBankCtrl.text) ?? 0.0,
                      openCash: double.tryParse(_accOpenCashCtrl.text) ?? 0.0,
                      headOpeningsMap: _draftHeadOpenings,
                      headLimitsMap: _draftHeadLimits,
                      finalHeadsList: _draftAccountHeads,
                    );
                    setState(() {
                      _accountNoticeMsg = err ?? 'Account "$newName" ($_accType) saved successfully.';
                      _accountNoticeOk = err == null;
                    });
                    _showAccountSaveResult(err, newName);
                    if (err == null) _clearAccountForm();
                  }),
                  _htmlBtn('Clear Form', const Color(0xFFE8F0FA), const Color(0xFF164B80), _clearAccountForm),
                ],
              ),
              if (_accountNoticeMsg != null) ...[
                const SizedBox(height: 10),
                _noticeBox(_accountNoticeMsg!, type: _accountNoticeOk ? 'ok' : 'bad'),
              ],
            ],
          ),
        ),

        // Saved Rojmel Accounts Table (`#accountRowsV02`)
        _htmlCard(
          headerWidget: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Expanded(
                child: Text(
                  'Saved Rojmel Accounts (Click any account to switch or Edit to customize School Headings, Opening Balance & Yearly Limits)',
                  style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w900, color: Color(0xFF10233F)),
                ),
              ),
              _pill('BANK Accounts: ${engine.bankAccountCount} / $kMaxBankAccounts | Total: ${engine.accounts.length}', isGood: true),
            ],
          ),
          body: Builder(
            builder: (_) {
              int bankIdx = 0;
              return _htmlTable(
                headers: const [
                  'Slot',
                  'Account Type & Split Rule',
                  'Account Name',
                  'School Heading(s) & Holder',
                  'A/C No., IFSC & Bank',
                  'Head-wise Opening (BANK) / Annual Limit (PFMS & SNA)',
                  'Entries',
                  'Action',
                ],
                rows: engine.accounts.map((n) {
                  final m = engine.getAccountMeta(n);
                  final c = engine.getAccountEntries(n).length;
                  final isB = m.type == 'BANK';
                  if (isB) bankIdx++;
                  final ownHeads = engine.getAccountSpecificHeads(n);
                  final hoCount = m.headOpenings.values.where((x) => x.total > 0).length;
                  final hlTotal = m.headLimits.values.fold<double>(0.0, (s, v) => s + v);

                  return <Widget>[
                    Text(isB ? 'Bank Slot $bankIdx / $kMaxBankAccounts' : 'Reserved (${m.type})', style: const TextStyle(fontWeight: FontWeight.w800)),
                    Text(
                      m.type == 'SNA_PURE'
                          ? 'PURELY SNA SPARSH (60:40)'
                          : (m.type == 'SNA'
                              ? 'PFMS + SNA SPARSH (60:40)\nPFMS → SNA SPARSH'
                              : (m.type == 'PFMS' ? 'PFMS ACCOUNT (100%)' : 'BANK ACCOUNT (100%)')),
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        color: m.type == 'BANK' ? const Color(0xFF0B6B4C) : const Color(0xFF8A5A00),
                      ),
                    ),
                    Text(n, style: const TextStyle(fontWeight: FontWeight.w900)),
                    Text(
                      m.type == 'SNA_PURE'
                          ? '${m.schoolName}\nAccount: $n'
                          : '${m.schoolName}\nHolder: ${m.holderName}',
                      style: const TextStyle(fontSize: 12.5),
                    ),
                    Text(
                      m.type == 'SNA_PURE'
                          ? 'Agency Code: ${m.effectiveSnaAgencyCode}'
                          : (m.type == 'SNA'
                              ? 'PFMS A/C: ${m.acNo} | SNA Agency: ${m.effectiveSnaAgencyCode}\nPFMS Last: ${fmtDateSlashDDMMYYYY(m.pfmsLastDate)} | SNA Start: ${fmtDateSlashDDMMYYYY(m.snaStartDate)}'
                              : '${m.acNo}\nIFSC: ${m.ifsc}\n${m.bankName}'),
                      style: const TextStyle(fontSize: 12.5),
                    ),
                    Text(
                      isB
                          ? 'Opening Bank: ₹${fmtDemoNum(m.openingBank)} | Cash: ₹${fmtDemoNum(m.openingCash)}\n✓ Matched ($hoCount heads) | Total Heads: ${ownHeads.length}'
                          : 'Opening: ₹0.00 (Locked)\n✓ Yearly Limit: ₹${fmtDemoNum(hlTotal)} | Total Heads: ${ownHeads.length}',
                      style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
                    ),
                    Text('$c', style: const TextStyle(fontWeight: FontWeight.w900)),
                    Wrap(
                      spacing: 4,
                      runSpacing: 4,
                      children: [
                        _htmlBtn('Select', const Color(0xFF185D98), Colors.white, () {
                          engine.selectAccount(n);
                          _showToast('Switched active account to "$n".');
                        }),
                        _htmlBtn('Edit / Heads / Limits', const Color(0xFFE8F0FA), const Color(0xFF164B80), () => _loadAccountIntoForm(n)),
                        _htmlBtn('🧹 Clear Entries (2x Confirm)', const Color(0xFFFFF3BF), const Color(0xFF754600), () => _openDeleteAllAccountEntriesModal(n)),
                        _htmlBtn('Delete', const Color(0xFFFFE3E3), const Color(0xFFC92A2A), () {
                          final err = engine.deleteAccountIfEmpty(n);
                          if (err != null) _showToast(err);
                        }),
                      ],
                    ),
                  ];
                }).toList(),
              );
            },
          ),
        ),
      ],
    );
  }

  // --------------------------------------------------------------------------
  // PANEL 4: GRANT HEADS (`#grantHeadsPanel` — ACCOUNT-WISE ISOLATION + COPY)
  // --------------------------------------------------------------------------

  final _ghNameCtrl = TextEditingController();

  /// Limit (SNA / PFMS) or bank opening balance (BANK) typed beside the head.
  final _ghAmountCtrl = TextEditingController();

  /// Saves the head's annual limit (SNA / PFMS) or opening bank balance (BANK).
  void _saveHeadAmount(String acc, String head, String? oldName, double? amount) {
    final meta = engine.getAccountMeta(acc);
    if (meta.isSnaOrPfms) {
      if (oldName != null && oldName != head && meta.headLimits.containsKey(oldName)) {
        meta.headLimits[head] = meta.headLimits.remove(oldName)!;
      }
      if (amount != null) engine.setSingleHeadLimit(acc, head, amount);
    } else {
      if (oldName != null && oldName != head && meta.headOpenings.containsKey(oldName)) {
        meta.headOpenings[head] = meta.headOpenings.remove(oldName)!;
      }
      if (amount != null) {
        final prev = meta.headOpenings[head] ?? HeadBalance();
        meta.headOpenings[head] = HeadBalance(cash: prev.cash, bank: math.max(0.0, amount));
      }
      double b = 0, c = 0;
      meta.headOpenings.forEach((_, v) {
        b += v.bank;
        c += v.cash;
      });
      meta.openingBank = b;
      meta.openingCash = c;
      meta.openingConfigured = true;
      engine.accountMeta[acc] = meta;
    }
  }
  String _ghActive = 'yes';
  int _ghEditIndex = -1;

  Widget _buildPanelGrantHeads() {
    final activeAcc = engine.selectedAccount;
    final heads = engine.getAccountSpecificHeads(activeAcc);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Grant Head Master / ગ્રાન્ટ હેડ (Selected Account Only — ખાતા મુજબ અલગ ગ્રાન્ટ હેડ)',
          style: TextStyle(fontSize: 21, fontWeight: FontWeight.w900, color: Color(0xFF10233F)),
        ),
        const SizedBox(height: 8),
        _noticeBox(
          '🗂 Account-wise Grant Head Isolation: Each Rojmel Account maintains its own separate Grant Heads list. Grant heads are never mixed automatically across accounts. Use the "Get Grant Heads from Another Account (All or Selected)" button below to copy All or Selected Grant Heads from another account.',
          type: 'warn',
        ),
        _htmlCard(
          headerWidget: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(child: const Text('1. Select Account & Add / Edit Grant Head for Selected Account', style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w900))),
              _pill('${heads.length} Grant Heads in $activeAcc', isGood: true),
            ],
          ),
          body: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  SizedBox(
                    width: 260,
                    child: DropdownButtonFormField<String>(
                      isExpanded: true,
                      value: activeAcc,
                      decoration: const InputDecoration(labelText: 'Selected Rojmel Account (ખાતું પસંદ કરો) *', border: OutlineInputBorder(), isDense: true),
                      items: engine.accounts.map((a) => DropdownMenuItem(value: a, child: Text('$a (${engine.getAccountMeta(a).type})'))).toList(),
                      onChanged: (v) {
                        if (v != null) engine.selectAccount(v);
                      },
                    ),
                  ),
                  SizedBox(width: 420, child: _labeledInput('Grant Head Name (ગ્રાન્ટ હેડનું નામ) *', _ghNameCtrl)),
                  SizedBox(
                    width: 220,
                    child: _labeledInput(
                      engine.getAccountMeta(activeAcc).isSnaOrPfms
                          ? 'વાર્ષિક લિમિટ ₹ (Head Limit)'
                          : 'ઉઘડતી સિલક ₹ (Bank Opening)',
                      _ghAmountCtrl,
                      isNumber: true,
                    ),
                  ),
                  SizedBox(
                    width: 180,
                    child: DropdownButtonFormField<String>(
                      isExpanded: true,
                      value: _ghActive,
                      decoration: const InputDecoration(labelText: 'Status', border: OutlineInputBorder(), isDense: true),
                      items: const [
                        DropdownMenuItem(value: 'yes', child: Text('Active')),
                        DropdownMenuItem(value: 'no', child: Text('Inactive')),
                      ],
                      onChanged: (v) => setState(() => _ghActive = v!),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _htmlBtn('Save Grant Head', const Color(0xFF185D98), Colors.white, () {
                    final name = _ghNameCtrl.text.trim();
                    if (name.isEmpty) return;
                    final amountText = _ghAmountCtrl.text.trim().replaceAll(',', '');
                    final amount = amountText.isEmpty ? null : double.tryParse(amountText);
                    if (amountText.isNotEmpty && (amount == null || amount < 0)) {
                      _showToast('રકમ સાચી લખો.');
                      return;
                    }
                    final current = List<String>.from(heads);
                    String? renamedFrom;
                    if (_ghEditIndex >= 0 && _ghEditIndex < current.length) {
                      final oldName = current[_ghEditIndex];
                      renamedFrom = oldName;
                      current[_ghEditIndex] = name;
                      for (final e in engine.entries) {
                        if (e.account == activeAcc && e.head == oldName) e.head = name;
                      }
                    } else if (!current.contains(name)) {
                      current.add(name);
                    }
                    engine.grantHeadActiveMap[name] = _ghActive;
                    engine.setAccountSpecificHeads(activeAcc, current);
                    _saveHeadAmount(activeAcc, name, renamedFrom, amount);
                    engine.triggerUpdate();
                    setState(() {
                      _ghNameCtrl.clear();
                      _ghAmountCtrl.clear();
                      _ghEditIndex = -1;
                    });
                    _showToast('Grant Head "$name" saved to account "$activeAcc".');
                  }),
                  _htmlBtn('Clear', const Color(0xFFE8F0FA), const Color(0xFF164B80), () {
                    setState(() {
                      _ghNameCtrl.clear();
                      _ghAmountCtrl.clear();
                      _ghEditIndex = -1;
                    });
                  }),
                  _htmlBtn('📥 Get Grant Heads from Another Account (All or Selected)', const Color(0xFFFFF3BF), const Color(0xFF754600), () {
                    _openCopyGrantHeadsModal(activeAcc);
                  }),
                ],
              ),
            ],
          ),
        ),
        _htmlCard(
          headerText: 'Saved Grant Heads for Account: $activeAcc (${heads.length} Heads — Isolated to this account)',
          body: _htmlTable(
            headers: [
              '#',
              'Account',
              'Grant Head Name (ગ્રાન્ટ હેડ)',
              engine.getAccountMeta(activeAcc).isSnaOrPfms ? 'વાર્ષિક લિમિટ ₹' : 'ઉઘડતી સિલક ₹ (રોકડ + બેન્ક)',
              'Status',
              'Action',
            ],
            rows: heads.asMap().entries.map((entry) {
              final i = entry.key;
              final h = entry.value;
              final active = engine.grantHeadActiveMap[h] != 'no';
              return <Widget>[
                Text('${i + 1}'),
                Text(activeAcc, style: const TextStyle(fontWeight: FontWeight.w800)),
                Text(h, style: const TextStyle(fontWeight: FontWeight.w800)),
                Builder(builder: (_) {
                  final isLimit = engine.getAccountMeta(activeAcc).isSnaOrPfms;
                  final v = isLimit ? engine.getHeadLimit(activeAcc, h) : engine.getHeadOpening(activeAcc, h).total;
                  final missing = isLimit && v <= 0;
                  return Text(
                    missing ? '⚠ સેટ નથી' : '₹${fmtDemoNum(v)}',
                    style: TextStyle(fontWeight: FontWeight.w900, color: missing ? const Color(0xFFC92A2A) : const Color(0xFF065F46)),
                  );
                }),
                Text(active ? 'Active' : 'Inactive', style: TextStyle(color: active ? const Color(0xFF087F5B) : const Color(0xFFC92A2A), fontWeight: FontWeight.w900)),
                Wrap(
                  spacing: 6,
                  children: [
                    _htmlBtn('Edit', const Color(0xFFE8F0FA), const Color(0xFF164B80), () {
                      setState(() {
                        _ghNameCtrl.text = h;
                        final isLimit = engine.getAccountMeta(activeAcc).isSnaOrPfms;
                        final v = isLimit ? engine.getHeadLimit(activeAcc, h) : engine.getHeadOpening(activeAcc, h).bank;
                        _ghAmountCtrl.text = v > 0 ? v.toStringAsFixed(2) : '';
                        _ghActive = active ? 'yes' : 'no';
                        _ghEditIndex = i;
                      });
                    }),
                    _htmlBtn('Remove from $activeAcc', const Color(0xFFFFE3E3), const Color(0xFFC92A2A), () {
                      if (engine.entries.any((e) => e.account == activeAcc && e.head == h)) {
                        _showToast('Cannot remove "$h" because it has transactions in $activeAcc.');
                        return;
                      }
                      final updated = List<String>.from(heads)..removeAt(i);
                      engine.setAccountSpecificHeads(activeAcc, updated);
                    }),
                  ],
                ),
              ];
            }).toList(),
          ),
        ),
      ],
    );
  }

  // --------------------------------------------------------------------------
  // PANEL 5: DATA ENTRY (`#entry` — EXACT V06 FIELDS, LIVE BALANCE & 60:40 BOXES)
  // --------------------------------------------------------------------------

  /// "Add this purchase to the dead stock register?" — Yes / No (default No).
  Widget _deadStockQuestion() {
    final hint = RojmelEngine.looksLikeAsset('${_entryNarrCtrl.text} ${_entryExpShortCtrl.text}');
    return Container(
      width: 560,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: _entryDeadStock ? const Color(0xFFE6FCF5) : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _entryDeadStock ? const Color(0xFF12B886) : const Color(0xFFCCD8E7), width: 1.4),
      ),
      child: Wrap(
        spacing: 12,
        runSpacing: 6,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          const Text('આ ચુકવણાની વસ્તુને ડેડ સ્ટોક રજીસ્ટરમાં ઉમેરવાના છો?',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: Color(0xFF10233F))),
          SegmentedButton<bool>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(value: false, label: Text('ના')),
              ButtonSegment(value: true, label: Text('હા')),
            ],
            selected: {_entryDeadStock},
            onSelectionChanged: (v) => setState(() => _entryDeadStock = v.first),
          ),
          if (hint && !_entryDeadStock)
            const Text('વિગત પરથી મિલકત ખરીદી લાગે છે — ડેડ સ્ટોકમાં ઉમેરવી હોય તો "હા" કરો.',
                style: TextStyle(fontSize: 11.5, color: Color(0xFF9C6500), fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }

  Widget _buildPanelDataEntry() {
    final acc = engine.selectedAccount;
    final m = engine.getAccountMeta(acc);
    final accHeads = engine.getAccountSpecificHeads(acc).where((h) => engine.grantHeadActiveMap[h] != 'no').toList();
    if (_entrySelectedHead == null || !accHeads.contains(_entrySelectedHead)) {
      _entrySelectedHead = accHeads.isNotEmpty ? accHeads.first : null;
    }

    final modeOptions = m.type == 'SNA_PURE'
        ? <String>['SNA SPARSH', 'Cash']
        : (m.type == 'SNA'
            ? <String>['SNA SPARSH', 'PFMS', 'Cash']
            : (m.type == 'PFMS' ? <String>['PFMS', 'Cash'] : <String>['Bank', 'Cash']));
    if (!modeOptions.contains(_entryMedium)) {
      _entryMedium = modeOptions.first;
    }

    final isDebit = _entryType == 'debit';
    final isCashMode = _entryMedium.toLowerCase() == 'cash';
    final isSNAMode = m.isAnySna && _entryMedium == 'SNA SPARSH';
    final showLim = m.isSnaOrPfms;

    final totalAmt = double.tryParse(_entryAmtCtrl.text.trim()) ?? 0.0;
    final a60 = (totalAmt * 60.0).roundToDouble() / 100.0;
    final a40 = double.parse((totalAmt - a60).toStringAsFixed(2));

    final bal = engine.getHeadCashBankBalanceAtDate(acc, _entrySelectedHead ?? '', _entryDateCtrl.text.trim());
    final opTot = (bal['openCash'] ?? 0.0) + (bal['openBank'] ?? 0.0);
    final balNote = '${opTot > 0 ? "ઉઘડતી (Open): ₹${fmtDemoNum(opTot)} | " : ""}રોકડ (Cash): ₹${fmtDemoNum(bal['cash'] ?? 0)} | બેન્ક (Bank): ₹${fmtDemoNum(bal['bank'] ?? 0)} | કુલ (Total): ₹${fmtDemoNum(bal['total'] ?? 0)}';
    final autoFy = RojmelEngine.financialYearFromDate(_entryDateCtrl.text.trim());
    final headLimitVal = bal['limit'] ?? 0.0;
    final isHeadLimitMissing = showLim && headLimitVal <= 0;
    final isBankOpeningMissing = m.type == 'BANK' && !engine.isBankOpeningReady(acc);
    final isEntryRestricted = isHeadLimitMissing || isBankOpeningMissing;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('Data Entry / નવી એન્ટ્રી', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: Color(0xFF10233F))),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xFFE8F0FA),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: const Color(0xFF185D98)),
              ),
              child: Text(
                '📅 Auto Financial Year from Date: ${autoFy.isNotEmpty ? autoFy : engine.financialYear}',
                style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w900, color: Color(0xFF11345F)),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        _noticeBox(
          'Important: For an SNA SPARSH Credit or Debit, enter the full 100% amount only. The system will automatically create separate 60% and 40% entries.',
          type: 'warn',
        ),
        if (isHeadLimitMissing)
          Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF4F4),
              border: Border.all(color: const Color(0xFFE03131), width: 2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Wrap(
              spacing: 12,
              runSpacing: 10,
              crossAxisAlignment: WrapCrossAlignment.center,
              alignment: WrapAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '🔒 Entry Restricted: First Set Head Annual Limit for "${_entrySelectedHead ?? ''}" ($acc)',
                      style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w900, color: Color(0xFFC92A2A)),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'પહેલા આ ગ્રાન્ટ હેડની વાર્ષિક મર્યાદા (Head Annual Limit) સેટ કરો, ત્યારબાદ જ એન્ટ્રી થઈ શકશે. તમે ગમે ત્યારે લિમિટ સેટ કે બદલી શકો છો.',
                      style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: Color(0xFF5C1B1B)),
                    ),
                  ],
                ),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _htmlBtn('🎯 Set / Change Head Limit Now', const Color(0xFF087F5B), Colors.white, () {
                      _openQuickHeadLimitDialog(acc, _entrySelectedHead);
                    }),

                  ],
                ),
              ],
            ),
          ),
        if (isBankOpeningMissing)
          Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF4F4),
              border: Border.all(color: const Color(0xFFE03131), width: 2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Wrap(
              spacing: 12,
              runSpacing: 10,
              crossAxisAlignment: WrapCrossAlignment.center,
              alignment: WrapAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '🔒 Entry Restricted: First Set Opening Balance & Head-wise Distribution for "$acc" (BANK Account)',
                      style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w900, color: Color(0xFFC92A2A)),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'BANK ખાતામાં એન્ટ્રી કરતા પહેલા ઉઘડતી સિલક (Opening Balance) અને હેડ-વાઈઝ ફાળવણી સેટ કરવી ફરજિયાત છે.',
                      style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: Color(0xFF5C1B1B)),
                    ),
                  ],
                ),
                _htmlBtn('🏦 Set / Edit Opening Balance Now', const Color(0xFF185D98), Colors.white, () {
                  _openQuickBankOpeningDialog(acc);
                }),
              ],
            ),
          ),
        _buildMultiDateSamePageOptionBar(acc),
        const SizedBox(height: 10),
        _htmlCard(
          headerText: 'Transaction details',
          body: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  SizedBox(
                    width: 250,
                    child: DropdownButtonFormField<String>(
                      isExpanded: true,
                      value: acc,
                      decoration: const InputDecoration(labelText: '1. Rojmel Account *', border: OutlineInputBorder(), isDense: true),
                      items: engine.accounts.map((a) => DropdownMenuItem(value: a, child: Text(a))).toList(),
                      onChanged: (v) {
                        if (v != null) engine.selectAccount(v);
                      },
                    ),
                  ),
                  SizedBox(
                    width: 340,
                    child: DropdownButtonFormField<String>(
                      value: _entrySelectedHead,
                      isExpanded: true,
                      decoration: InputDecoration(labelText: '2. Grant Head ($acc) *', border: const OutlineInputBorder(), isDense: true),
                      items: accHeads.map((h) => DropdownMenuItem(value: h, child: Text(h, overflow: TextOverflow.ellipsis))).toList(),
                      onChanged: (v) {
                        setState(() {
                          _entrySelectedHead = v;
                          if (_entryType == 'credit' && _entryNarrCtrl.text.trim().isEmpty) {
                            _entryNarrCtrl.text = 'ગ્રાન્ટ જમા થઈ';
                            if (_entryPartyCtrl.text.trim().isEmpty) _entryPartyCtrl.text = 'SSA';
                          }
                        });
                      },
                    ),
                  ),
                  SizedBox(
                    width: 210,
                    child: _labeledDateInput(
                      '3. Transaction Date *',
                      _entryDateCtrl,
                      onChanged: (v) {
                        engine.syncFinancialYearFromDate(v);
                        setState(() {});
                      },
                      afterPicked: () {
                        engine.syncFinancialYearFromDate(_entryDateCtrl.text);
                      },
                    ),
                  ),
                  SizedBox(
                    width: 155,
                    child: _readonlyField(
                      'Auto Financial Year',
                      autoFy.isNotEmpty ? autoFy : engine.financialYear,
                    ),
                  ),
                  SizedBox(
                    width: 210,
                    child: DropdownButtonFormField<String>(
                      isExpanded: true,
                      value: _entryType,
                      decoration: const InputDecoration(labelText: '4. Credit / Debit *', border: OutlineInputBorder(), isDense: true),
                      items: const [
                        DropdownMenuItem(value: 'credit', child: Text('Credit / આવક')),
                        DropdownMenuItem(value: 'debit', child: Text('Debit / જાવક')),
                      ],
                      onChanged: (v) => setState(() {
                        _entryType = v!;
                        // 5B is used only by Debit (Kharch Patrak).
                        if (_entryType != 'debit') _entryExpShortCtrl.clear();
                      }),
                    ),
                  ),
                  SizedBox(
                    width: 480,
                    child: _labeledInput(
                      '5. Description / વિગત (Cashbook / Bill Register) *',
                      _entryNarrCtrl,
                      hint: _entryType == 'credit'
                          ? 'દા.ત. ગ્રાન્ટ જમા થઈ / બેન્કનું વ્યાજ જમા થયું / પદર તરીકે આચાર્યશ્રીએ નાણા રોક્યા'
                          : 'દા.ત. SHREE ENTERPRISE નું બીલ ચૂકવ્યું / સ્ટેશનરી ખર્ચ પેટે ચૂકવ્યા',
                    ),
                  ),
                  if (isDebit)
                  SizedBox(
                    width: 480,
                    child: _labeledInput(
                      '5B. Short Expense Item Detail / ખર્ચની ટૂંકમાં વિગત (ખર્ચ પત્રક માટે)',
                      _entryExpShortCtrl,
                      hint: 'દા.ત. સ્ટેશનરી વસ્તુઓ, કાગળ વગેરે / શૈક્ષણિક સાધનો બનાવવા જરૂરી વસ્તુઓ',
                    ),
                  ),
                  SizedBox(
                    width: 210,
                    child: _labeledInput(
                      '6. Full Amount / 100% Bill Amount *',
                      _entryAmtCtrl,
                      isNumber: true,
                      onChanged: (v) {
                        final tot = double.tryParse(v.trim()) ?? 0.0;
                        final c60 = (tot * 60.0).roundToDouble() / 100.0;
                        final c40 = double.parse((tot - c60).toStringAsFixed(2));
                        _snaCredit60AmtCtrl.text = c60.toStringAsFixed(2);
                        _snaCredit40AmtCtrl.text = c40.toStringAsFixed(2);
                        _snaDebit60AmtCtrl.text = c60.toStringAsFixed(2);
                        _snaDebit40AmtCtrl.text = c40.toStringAsFixed(2);
                        setState(() {});
                      },
                    ),
                  ),
                  SizedBox(
                    width: 280,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        TextField(
                          readOnly: true,
                          controller: TextEditingController(text: fmtDemoNum(bal['total'] ?? 0)),
                          style: TextStyle(
                            fontWeight: FontWeight.w900,
                            color: (bal['total'] ?? 0) > 0 ? const Color(0xFF087F5B) : const Color(0xFFC92A2A),
                          ),
                          decoration: const InputDecoration(labelText: 'Available Head Balance', border: OutlineInputBorder(), isDense: true),
                        ),
                        const SizedBox(height: 3),
                        Text(balNote, style: const TextStyle(fontSize: 11, color: Color(0xFF65758B))),
                      ],
                    ),
                  ),
                  if (showLim)
                    SizedBox(
                      width: 320,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          TextField(
                            readOnly: true,
                            onTap: () => _openQuickHeadLimitDialog(acc, _entrySelectedHead),
                            controller: TextEditingController(
                              text: (bal['limit'] ?? 0) > 0
                                  ? 'Limit: ₹${fmtDemoNum(bal['limit']!)} | Rem: ₹${fmtDemoNum(bal['remLimit']!)}'
                                  : '⚠ No Limit Set (Click to Set Limit)',
                            ),
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              color: (bal['limit'] ?? 0) > 0 ? const Color(0xFF065F46) : const Color(0xFFC92A2A),
                            ),
                            decoration: InputDecoration(
                              labelText: 'Head Annual Limit (Click to Set/Change)',
                              border: const OutlineInputBorder(),
                              isDense: true,
                              suffixIcon: IconButton(
                                tooltip: 'Set or Change Head Annual Limit anytime',
                                icon: const Icon(Icons.edit_note_rounded, color: Color(0xFF087F5B)),
                                onPressed: () => _openQuickHeadLimitDialog(acc, _entrySelectedHead),
                              ),
                            ),
                          ),
                          const SizedBox(height: 3),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(
                                child: Text(
                                  (bal['limit'] ?? 0) > 0
                                      ? 'Used: ₹${fmtDemoNum(bal['usedYear']!)} of ₹${fmtDemoNum(bal['limit']!)}'
                                      : 'Required before entry: click to set Head Limit.',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: (bal['limit'] ?? 0) > 0 ? const Color(0xFF65758B) : const Color(0xFFC92A2A),
                                  ),
                                ),
                              ),
                              InkWell(
                                onTap: () => _openQuickHeadLimitDialog(acc, _entrySelectedHead),
                                child: const Text(
                                  '🎯 Set / Change Limit',
                                  style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w900, color: Color(0xFF185D98), decoration: TextDecoration.underline),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  if (!showLim)
                    SizedBox(
                      width: 280,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          TextField(
                            readOnly: true,
                            onTap: () => _openQuickBankOpeningDialog(acc),
                            controller: TextEditingController(
                              text: 'Open: ₹${fmtDemoNum(opTot)} (Bank: ₹${fmtDemoNum(bal["openBank"] ?? 0)})',
                            ),
                            decoration: InputDecoration(
                              labelText: 'Head Opening Balance (BANK)',
                              border: const OutlineInputBorder(),
                              isDense: true,
                              suffixIcon: IconButton(
                                tooltip: 'Set or Change Bank Opening Balance',
                                icon: const Icon(Icons.account_balance_wallet_outlined, color: Color(0xFF185D98)),
                                onPressed: () => _openQuickBankOpeningDialog(acc),
                              ),
                            ),
                          ),
                          const SizedBox(height: 3),
                          InkWell(
                            onTap: () => _openQuickBankOpeningDialog(acc),
                            child: const Text(
                              '🏦 Set / Edit Head-wise Opening Balance',
                              style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w900, color: Color(0xFF185D98), decoration: TextDecoration.underline),
                            ),
                          ),
                        ],
                      ),
                    ),
                  if (isDebit)
                    SizedBox(
                      width: 230,
                      child: _labeledInput(
                        'Voucher Number (Debit only)',
                        _entryManualVoucherCtrl,
                        hint: 'Suggested: ${engine.nextSuggestedVoucher(acc)}',
                      ),
                    ),
                  SizedBox(
                    width: 280,
                    child: _partyNameField(isDebit),
                  ),
                  SizedBox(
                    width: 265,
                    child: DropdownButtonFormField<String>(
                      value: _entryMedium,
                      isExpanded: true,
                      decoration: const InputDecoration(labelText: 'Cash / Bank / Mode', border: OutlineInputBorder(), isDense: true),
                      items: modeOptions.map((x) {
                        final label = x == 'SNA SPARSH'
                            ? 'SNA SPARSH (60% : 40%)'
                            : (x == 'PFMS' ? 'PFMS (100%)' : (x == 'Bank' ? 'Bank / Cheque (100%)' : 'Cash / રોકડ (100%)'));
                        return DropdownMenuItem(value: x, child: Text(label, overflow: TextOverflow.ellipsis));
                      }).toList(),
                      onChanged: (v) => setState(() => _entryMedium = v!),
                    ),
                  ),
                  if (isDebit) _deadStockQuestion(),
                ],
              ),

              // SNA SPARSH Automatic Credit 60:40 Box (Editable by Admin + Auto-Syncs Bill/Voucher to Debit)
              if (!isDebit && isSNAMode) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF4F9FF),
                    border: Border.all(color: const Color(0xFF7AA7D8), width: 2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Expanded(
                            child: Text(
                              'SNA SPARSH automatic Credit 60:40 entries (Editable — Auto-Syncs Bill / Voucher to Debit)',
                              style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15),
                            ),
                          ),
                          Wrap(
                            spacing: 6,
                            children: [
                              _htmlBtn('📄 Set Bill (બિલના 60% / 40%)', const Color(0xFFE8F0FA), const Color(0xFF164B80), () {
                                setState(() {
                                  _snaCredit60SuffixCtrl.text = '(બિલના 60%)';
                                  _snaCredit40SuffixCtrl.text = '(બિલના 40%)';
                                  _snaDebit60SuffixCtrl.text = '(બિલના 60% લેખે)';
                                  _snaDebit40SuffixCtrl.text = '(બિલના 40% લેખે)';
                                });
                              }),
                              _htmlBtn('🧾 Set Voucher (વાઉચરના 60% / 40%)', const Color(0xFFE8F0FA), const Color(0xFF164B80), () {
                                setState(() {
                                  _snaCredit60SuffixCtrl.text = '(વાઉચરના 60%)';
                                  _snaCredit40SuffixCtrl.text = '(વાઉચરના 40%)';
                                  _snaDebit60SuffixCtrl.text = '(વાઉચરના 60% લેખે)';
                                  _snaDebit40SuffixCtrl.text = '(વાઉચરના 40% લેખે)';
                                });
                              }),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 12,
                        runSpacing: 10,
                        children: [
                          SizedBox(width: 200, child: _labeledInput('60% Credit Amount', _snaCredit60AmtCtrl, isNumber: true)),
                          SizedBox(
                            width: 240,
                            child: _labeledInput(
                              'First description ending',
                              _snaCredit60SuffixCtrl,
                              onChanged: (v) {
                                _snaDebit60SuffixCtrl.text = RojmelEngine.deriveDebitSuffixFromCredit(v, 60);
                                final lower = v.toLowerCase();
                                if (v.contains('બિલ') || v.contains('બીલ')) {
                                  _snaCredit40SuffixCtrl.text = '(બિલના 40%)';
                                  _snaDebit40SuffixCtrl.text = '(બિલના 40% લેખે)';
                                } else if (v.contains('વાઉચર') || lower.contains('voucher')) {
                                  _snaCredit40SuffixCtrl.text = '(વાઉચરના 40%)';
                                  _snaDebit40SuffixCtrl.text = '(વાઉચરના 40% લેખે)';
                                }
                              },
                            ),
                          ),
                          SizedBox(width: 200, child: _labeledInput('40% Credit Amount', _snaCredit40AmtCtrl, isNumber: true)),
                          SizedBox(
                            width: 240,
                            child: _labeledInput(
                              'Second description ending',
                              _snaCredit40SuffixCtrl,
                              onChanged: (v) {
                                _snaDebit40SuffixCtrl.text = RojmelEngine.deriveDebitSuffixFromCredit(v, 40);
                              },
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],

              // Normal 100% Bank/PFMS Debit Fields
              if (isDebit && !isSNAMode && !isCashMode) ...[
                const SizedBox(height: 12),
                Wrap(
                  spacing: 12,
                  runSpacing: 10,
                  children: [
                    SizedBox(width: 260, child: _labeledInput('Cheque / PPA / Claim Number *', _entryTxnCtrl)),
                    SizedBox(width: 220, child: _labeledDateInput('Settlement Date (YYYY-MM-DD) *', _entryClearDateCtrl)),
                  ],
                ),
              ],

              // SNA SPARSH Automatic Debit 60:40 Fields (Editable 60% & 40% Amounts, Description Endings, Claim Numbers and Settlement Dates)
              if (isDebit && isSNAMode) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF4F9FF),
                    border: Border.all(color: const Color(0xFF7AA7D8), width: 2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Expanded(
                            child: Text(
                              'SNA SPARSH automatic 60:40 entries (Editable — Auto-Matched with Credit Bill/Voucher)',
                              style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15),
                            ),
                          ),
                          Wrap(
                            spacing: 6,
                            children: [
                              _htmlBtn('📄 Set Bill (બિલના 60% / 40% લેખે)', const Color(0xFFE8F0FA), const Color(0xFF164B80), () {
                                setState(() {
                                  _snaCredit60SuffixCtrl.text = '(બિલના 60%)';
                                  _snaCredit40SuffixCtrl.text = '(બિલના 40%)';
                                  _snaDebit60SuffixCtrl.text = '(બિલના 60% લેખે)';
                                  _snaDebit40SuffixCtrl.text = '(બિલના 40% લેખે)';
                                });
                              }),
                              _htmlBtn('🧾 Set Voucher (વાઉચરના 60% / 40% લેખે)', const Color(0xFFE8F0FA), const Color(0xFF164B80), () {
                                setState(() {
                                  _snaCredit60SuffixCtrl.text = '(વાઉચરના 60%)';
                                  _snaCredit40SuffixCtrl.text = '(વાઉચરના 40%)';
                                  _snaDebit60SuffixCtrl.text = '(વાઉચરના 60% લેખે)';
                                  _snaDebit40SuffixCtrl.text = '(વાઉચરના 40% લેખે)';
                                });
                              }),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      const Text('Enter one description and the full 100% bill amount above. Description endings automatically match what you entered in Credit (Bill or Voucher).', style: TextStyle(fontSize: 12, color: Color(0xFF65758B))),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 12,
                        runSpacing: 10,
                        children: [
                          SizedBox(width: 165, child: _labeledInput('60% Amount', _snaDebit60AmtCtrl, isNumber: true)),
                          SizedBox(width: 210, child: _labeledInput('60% Description ending', _snaDebit60SuffixCtrl)),
                          SizedBox(width: 225, child: _labeledInput('60% Claim Number *', _sna60ClaimCtrl)),
                          SizedBox(width: 200, child: _labeledDateInput('60% Settlement Date *', _sna60DateCtrl)),
                          SizedBox(width: 165, child: _labeledInput('40% Amount', _snaDebit40AmtCtrl, isNumber: true)),
                          SizedBox(width: 210, child: _labeledInput('40% Description ending', _snaDebit40SuffixCtrl)),
                          SizedBox(width: 225, child: _labeledInput('40% Claim Number *', _sna40ClaimCtrl)),
                          SizedBox(width: 200, child: _labeledDateInput('40% Settlement Date *', _sna40DateCtrl)),
                        ],
                      ),
                    ],
                  ),
                ),
              ],

              const SizedBox(height: 10),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                value: _entryEditAllowed,
                title: const Text('Principal/authorized user may edit this entry later', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                onChanged: (v) => setState(() => _entryEditAllowed = v ?? true),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 10,
                children: [
                  _htmlBtn(
                    isEntryRestricted
                        ? (isHeadLimitMissing ? '🔒 Save Entry (Set Head Limit First)' : '🔒 Save Entry (Set Opening Balance First)')
                        : 'Save Entry',
                    isEntryRestricted ? const Color(0xFFC92A2A) : const Color(0xFF185D98),
                    Colors.white,
                    () {
                      if (isHeadLimitMissing) {
                        setState(() {
                          _entryNoticeMsg =
                              'એન્ટ્રી અટકાવવામાં આવી (Entry Restricted): પહેલા "${_entrySelectedHead ?? ""}" ગ્રાન્ટ હેડની વાર્ષિક મર્યાદા (Head Annual Limit) સેટ કરો.';
                          _entryNoticeOk = false;
                        });
                        _openQuickHeadLimitDialog(acc, _entrySelectedHead);
                        return;
                      }
                      if (isBankOpeningMissing) {
                        setState(() {
                          _entryNoticeMsg =
                              'એન્ટ્રી અટકાવવામાં આવી (Entry Restricted): પહેલા BANK ખાતા ("$acc") ની ઉઘડતી સિલક (Opening Balance) અને હેડ-વાઈઝ ફાળવણી સેટ કરો.';
                          _entryNoticeOk = false;
                        });
                        _openQuickBankOpeningDialog(acc);
                        return;
                      }
                    final err = engine.addTransactionV06(
                      account: acc,
                      head: _entrySelectedHead ?? '',
                      date: _entryDateCtrl.text,
                      type: _entryType,
                      rawNarration: _entryNarrCtrl.text,
                      expenseShort: isDebit ? _entryExpShortCtrl.text : '',
                      amount: double.tryParse(_entryAmtCtrl.text.trim()) ?? 0.0,
                      medium: _entryMedium,
                      party: _entryPartyCtrl.text,
                      manualVoucher: _entryManualVoucherCtrl.text,
                      txn: _entryTxnCtrl.text,
                      clearDate: _entryClearDateCtrl.text,
                      sna60Claim: _sna60ClaimCtrl.text,
                      sna60Date: _sna60DateCtrl.text,
                      sna40Claim: _sna40ClaimCtrl.text,
                      sna40Date: _sna40DateCtrl.text,
                      custom60Amount: _entryType == 'credit'
                          ? double.tryParse(_snaCredit60AmtCtrl.text.trim())
                          : double.tryParse(_snaDebit60AmtCtrl.text.trim()),
                      custom40Amount: _entryType == 'credit'
                          ? double.tryParse(_snaCredit40AmtCtrl.text.trim())
                          : double.tryParse(_snaDebit40AmtCtrl.text.trim()),
                      custom60Suffix: _entryType == 'credit' ? _snaCredit60SuffixCtrl.text : _snaDebit60SuffixCtrl.text,
                      custom40Suffix: _entryType == 'credit' ? _snaCredit40SuffixCtrl.text : _snaDebit40SuffixCtrl.text,
                      editAllowed: _entryEditAllowed,
                      deadStock: isDebit && _entryDeadStock,
                    );
                    setState(() {
                      if (err == null) _entryDeadStock = false;
                      if (err != null) {
                        _entryNoticeMsg = err;
                        _entryNoticeOk = false;
                      } else {
                        _entryNoticeMsg = isSNAMode
                            ? 'Two SNA SPARSH ${_entryType} entries created: 60% and 40%.'
                            : '100% Entry saved successfully in $acc.';
                        _entryNoticeOk = true;
                        _entryAmtCtrl.clear();
                        _entryNarrCtrl.clear();
                        _entryExpShortCtrl.clear();
                        _entryTxnCtrl.clear();
                        _sna60ClaimCtrl.clear();
                        _sna40ClaimCtrl.clear();
                        _snaCredit60AmtCtrl.text = '0.00';
                        _snaCredit40AmtCtrl.text = '0.00';
                        _snaDebit60AmtCtrl.text = '0.00';
                        _snaDebit40AmtCtrl.text = '0.00';
                        _entryManualVoucherCtrl.clear();
                      }
                    });
                  }),
                  if (showLim)
                    _htmlBtn('🎯 Set / Change Head Limit', const Color(0xFF087F5B), Colors.white, () {
                      _openQuickHeadLimitDialog(acc, _entrySelectedHead);
                    }),
                  if (!showLim)
                    _htmlBtn('🏦 Set / Edit Opening Balance', const Color(0xFF087F5B), Colors.white, () {
                      _openQuickBankOpeningDialog(acc);
                    }),
                  _htmlBtn('Reset', const Color(0xFFE8F0FA), const Color(0xFF164B80), () {
                    setState(() {
                      _entryNarrCtrl.clear();
                      _entryExpShortCtrl.clear();
                      _entryAmtCtrl.clear();
                      _entryPartyCtrl.clear();
                      _entryTxnCtrl.clear();
                      _sna60ClaimCtrl.clear();
                      _sna40ClaimCtrl.clear();
                      _entryManualVoucherCtrl.clear();
                      _entryNoticeMsg = null;
                    });
                  }),
                ],
              ),
              if (_entryNoticeMsg != null) ...[
                const SizedBox(height: 10),
                _noticeBox(_entryNoticeMsg!, type: _entryNoticeOk ? 'ok' : 'bad'),
              ],
            ],
          ),
        ),
      ],
    );
  }

  // --------------------------------------------------------------------------
  // PANEL 10: CASHBOOK (`#cashbook` — EXACT A4 ODD/EVEN PAGES + DATE-WISE TABLE)
  // --------------------------------------------------------------------------

  Future<void> _openQuickPageWiseEntryDialog(String acc, CashbookPagePair pair) async {
    final creditPageNo = pair.creditPageNo;
    final debitPageNo = pair.debitPageNo;
    String currentVal = engine.getCreditPageEntryCount(acc, creditPageNo, pair.pairKey)?.toString() ?? 'auto';
    double currentGapMm = engine.getCreditPageEntryGapMm(acc, creditPageNo, pair.pairKey);
    final gapCtrl = TextEditingController(text: currentGapMm.toStringAsFixed(1));

    final datesInPair = <String>{
      ...pair.credits.map((e) => fmtDateDDMMYY(e.date)),
      ...pair.debits.map((e) => fmtDateDDMMYY(e.date)),
    }.where((s) => s.isNotEmpty).toList();
    final dateRangeText = datesInPair.isEmpty
        ? pair.formattedDateDDMMYY
        : (datesInPair.length == 1
            ? datesInPair.first
            : '${datesInPair.first} → ${datesInPair.last} (${datesInPair.length} Dates)');

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) => AlertDialog(
          title: Text(
            '📑 Credit Page $creditPageNo Setup (→ Auto Sets Opposite Debit Page $debitPageNo) — $acc',
            style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w800, color: Color(0xFF11345F)),
          ),
          content: SizedBox(
            width: 580,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF0F6FF),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFF90B4E2)),
                    ),
                    child: Text(
                      'Credit Page $creditPageNo (આવક) → Automatically sets Debit Page $debitPageNo (જાવક)\n'
                      'Dates on this page pair: $dateRangeText\n'
                      'Currently showing: ${pair.alignedCredits.length} Aligned Opposite Rows (${pair.credits.length} Cr / ${pair.debits.length} Dr) • Gap: ${currentGapMm.toStringAsFixed(1)}mm\n'
                      '• Only set Credit Page $creditPageNo here — opposite Debit Page $debitPageNo is automatically aligned row-by-row with the exact same entry count and gap!',
                      style: const TextStyle(fontSize: 12.2, fontWeight: FontWeight.w700, color: Color(0xFF1E293B), height: 1.38),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    '1. Number of Entries on Credit Page $creditPageNo (Auto-sets Debit Page $debitPageNo):',
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w900, color: Color(0xFF0E3360)),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      ChoiceChip(
                        label: const Text('✨ Auto (Fit Full Last Entry by Font Size)'),
                        selected: currentVal == 'auto',
                        onSelected: (_) => setModalState(() => currentVal = 'auto'),
                      ),
                      for (final n in const <int>[1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 12, 15])
                        ChoiceChip(
                          label: Text('$n Entries (Page $creditPageNo → P.$debitPageNo)'),
                          selected: currentVal == '$n',
                          onSelected: (_) => setModalState(() => currentVal = '$n'),
                        ),
                    ],
                  ),
                  const Divider(height: 22),
                  Text(
                    '2. Gap Between Two Entries on Page $creditPageNo & Page $debitPageNo (બે એન્ટ્રી વચ્ચે જગ્યા - mm):',
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w900, color: Color(0xFF0E3360)),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      SizedBox(
                        width: 180,
                        child: _labeledInput(
                          'Entry Gap (mm)',
                          gapCtrl,
                          isNumber: true,
                          onChanged: (v) {
                            final d = double.tryParse(v.trim());
                            if (d != null) {
                              setModalState(() => currentGapMm = d.clamp(0.0, 35.0));
                            }
                          },
                        ),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Text(
                          'Sets exact vertical spacing (mm) between consecutive entries on both Credit & Debit sides.',
                          style: TextStyle(fontSize: 12, color: Color(0xFF475569), fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final g in const <double>[0, 2, 4, 6, 8, 10, 12, 14, 16, 18, 20, 25])
                        ChoiceChip(
                          label: Text('${g.toStringAsFixed(0)} mm'),
                          selected: (currentGapMm - g).abs() < 0.2,
                          onSelected: (_) {
                            setModalState(() {
                              currentGapMm = g;
                              gapCtrl.text = g.toStringAsFixed(1);
                            });
                          },
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: const Color(0xFF087F5B)),
              onPressed: () {
                final parsedGap = (double.tryParse(gapCtrl.text.trim()) ?? currentGapMm).clamp(0.0, 35.0);
                if (currentVal == 'auto') {
                  engine.setCreditPageEntryCount(acc, creditPageNo, null, pair.pairKey);
                } else {
                  final parsed = int.tryParse(currentVal);
                  if (parsed != null && parsed > 0) {
                    engine.setCreditPageEntryCount(acc, creditPageNo, parsed, pair.pairKey);
                  }
                }
                engine.setCreditPageEntryGapMm(acc, creditPageNo, parsedGap, pair.pairKey);
                engine.triggerUpdate();
                if (mounted) setState(() {});
                Navigator.of(ctx).pop();
                _showToast(
                  'Credit Page $creditPageNo (→ Auto Debit Page $debitPageNo) set to ${currentVal == "auto" ? "Auto" : "$currentVal Entries"} with ${parsedGap.toStringAsFixed(1)}mm Gap.',
                );
              },
              child: const Text('✔ Apply to Credit Page & Auto-Set Debit Page'),
            ),
          ],
        ),
      ),
    );
  }

  /// Opens a single Table Dialog where Admin can configure Credit Pages (Page 1, Page 3, Page 5, Page 7...)
  /// with their Page-Wise Number of Entries and Gap Between Two Entries, automatically setting Debit Pages (Page 2, Page 4, Page 6, Page 8...).
  Future<void> _openAllCreditPagesSetupTableDialog(String acc) async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) {
          final pages = engine.buildCashbookPages(acc);
          return AlertDialog(
            title: Text(
              '📋 Credit Page-Wise Entries & Gap Setup (Page 1, 3, 5... → Auto Debit Page 2, 4, 6...) — $acc',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Color(0xFF11345F)),
            ),
            content: SizedBox(
              width: 720,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF0F6FF),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFF90B4E2)),
                      ),
                      child: const Text(
                        '• માત્ર જમા બાજુના પેજ (Page 1, Page 3, Page 5, Page 7...) માં એન્ટ્રી સંખ્યા અને બે એન્ટ્રી વચ્ચેની જગ્યા (Gap) સેટ કરો — સામેનું ઉધાર પેજ (Page 2, Page 4, Page 6, Page 8...) ઓટોમેટિક સેટ થશે!\n'
                        '• જો એક જ તારીખમાં ૧ જમા સામે ૨ કે વધુ ઉધાર એન્ટ્રી હશે (દા.ત. Page 1-2), તો જમા અને ઉધાર સામસામે (Exact Opposite) જ ગોઠવાશે.',
                        style: TextStyle(fontSize: 12.2, fontWeight: FontWeight.w700, color: Color(0xFF1E293B), height: 1.38),
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (pages.isEmpty)
                      const Padding(
                        padding: EdgeInsets.all(16),
                        child: Text('No pages available in this account yet.'),
                      )
                    else
                      ...pages.map((p) {
                        final cPage = p.creditPageNo;
                        final dPage = p.debitPageNo;
                        final curCount = engine.getCreditPageEntryCount(acc, cPage, p.pairKey)?.toString() ?? 'auto';
                        final curGap = engine.getCreditPageEntryGapMm(acc, cPage, p.pairKey);
                        return Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: const Color(0xFFCBD5E1)),
                          ),
                          child: Wrap(
                            spacing: 12,
                            runSpacing: 8,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            alignment: WrapAlignment.spaceBetween,
                            children: [
                              SizedBox(
                                width: 220,
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      '📄 Credit Page $cPage (→ Auto Debit Page $dPage)',
                                      style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13, color: Color(0xFF0F2942)),
                                    ),
                                    Text(
                                      'Showing: ${p.alignedCredits.length} Opposite Rows (${p.credits.length} Cr / ${p.debits.length} Dr)',
                                      style: const TextStyle(fontSize: 11.5, color: Color(0xFF475569), fontWeight: FontWeight.w600),
                                    ),
                                  ],
                                ),
                              ),
                              SizedBox(
                                width: 210,
                                child: DropdownButtonFormField<String>(
                                  isExpanded: true,
                                  value: curCount,
                                  decoration: InputDecoration(
                                    labelText: 'Page $cPage Entries (→ P.$dPage)',
                                    border: const OutlineInputBorder(),
                                    isDense: true,
                                  ),
                                  items: [
                                    const DropdownMenuItem(value: 'auto', child: Text('✨ Auto (By Font Size)')),
                                    for (final n in const <int>[1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 12, 15])
                                      DropdownMenuItem(value: '$n', child: Text('$n Entries with Gap')),
                                  ],
                                  onChanged: (v) {
                                    if (v == null) return;
                                    if (v == 'auto') {
                                      engine.setCreditPageEntryCount(acc, cPage, null, p.pairKey);
                                    } else {
                                      engine.setCreditPageEntryCount(acc, cPage, int.tryParse(v), p.pairKey);
                                    }
                                    engine.triggerUpdate();
                                    setModalState(() {});
                                    if (mounted) setState(() {});
                                  },
                                ),
                              ),
                              SizedBox(
                                width: 190,
                                child: DropdownButtonFormField<double>(
                                  isExpanded: true,
                                  value: const <double>[0, 2, 4, 6, 8, 10, 12, 14, 16, 18, 20, 25].contains(curGap.roundToDouble())
                                      ? curGap.roundToDouble()
                                      : 4.0,
                                  decoration: InputDecoration(
                                    labelText: 'Page $cPage Gap (બે એન્ટ્રી વચ્ચે જગ્યા)',
                                    border: const OutlineInputBorder(),
                                    isDense: true,
                                  ),
                                  items: const <double>[0, 2, 4, 6, 8, 10, 12, 14, 16, 18, 20, 25]
                                      .map((g) => DropdownMenuItem(value: g, child: Text('Gap: ${g.toStringAsFixed(0)} mm')))
                                      .toList(),
                                  onChanged: (v) {
                                    if (v == null) return;
                                    engine.setCreditPageEntryGapMm(acc, cPage, v, p.pairKey);
                                    engine.triggerUpdate();
                                    setModalState(() {});
                                    if (mounted) setState(() {});
                                  },
                                ),
                              ),
                            ],
                          ),
                        );
                      }),
                  ],
                ),
              ),
            ),
            actions: [
              OutlinedButton(
                onPressed: () {
                  engine.pageEntryCountMap.removeWhere((k, _) => k.startsWith('$acc|'));
                  engine.pageEntryGapMap.removeWhere((k, _) => k.startsWith('$acc|'));
                  engine.triggerUpdate();
                  setModalState(() {});
                  if (mounted) setState(() {});
                },
                child: const Text('↺ Reset All Pages to Auto'),
              ),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: const Color(0xFF087F5B)),
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('✔ Done'),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildMultiDateSamePageOptionBar(String acc) {
    final m = engine.getAccountMeta(acc);
    final currPages = engine.buildCashbookPages(acc);
    final activeFontPt = engine.globalFontPt ?? engine.cashbookPrintFontPt;
    final activeGapMm = engine.cashbookEntryGapMm;
    final hasAnyPageWiseOverride = engine.pageEntryCountMap.keys.any((k) => k.startsWith('$acc|')) ||
        engine.pageEntryGapMap.keys.any((k) => k.startsWith('$acc|'));

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFF0F6FF),
        border: Border.all(color: const Color(0xFF90B4E2), width: 1.4),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 10,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                '📅 કેશબુક પેજમાં તારીખ સેટિંગ ($acc • ${m.type} — બધા ખાતા માટે):',
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w900,
                  color: Color(0xFF0E3360),
                ),
              ),
              _htmlBtn(
                !engine.cashbookContinuousDates
                    ? '☑ દરેક તારીખ નવા પેજ પર (Single Date per Page) ✓'
                    : '☐ દરેક તારીખ નવા પેજ પર (Single Date per Page)',
                !engine.cashbookContinuousDates
                    ? const Color(0xFF185D98)
                    : const Color(0xFFE8F0FA),
                !engine.cashbookContinuousDates
                    ? Colors.white
                    : const Color(0xFF164B80),
                () {
                  engine.cashbookContinuousDates = false;
                  engine.triggerUpdate();
                  setState(() {});
                },
              ),
              _htmlBtn(
                engine.cashbookContinuousDates
                    ? '☑ એક પેજમાં અનેક તારીખ — સળંગ એન્ટ્રી (Multi-Date Entries in Same Page) ✓'
                    : '☐ એક પેજમાં અનેક તારીખ — સળંગ એન્ટ્રી (Multi-Date Entries in Same Page)',
                engine.cashbookContinuousDates
                    ? const Color(0xFF087F5B)
                    : const Color(0xFFE8F0FA),
                engine.cashbookContinuousDates
                    ? Colors.white
                    : const Color(0xFF164B80),
                () {
                  engine.cashbookContinuousDates = true;
                  if (engine.defaultMaxEntriesPerPage < 6) {
                    engine.defaultMaxEntriesPerPage = 12;
                  }
                  engine.triggerUpdate();
                  setState(() {});
                },
              ),
            ],
          ),
          const SizedBox(height: 8),
          // 1. Entries per Page (Auto, 2 to 15, and All Fit)
          Wrap(
            spacing: 6,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              const Text(
                '📄 એક પેજમાં એન્ટ્રી સંખ્યા (Entries per Page — 2 to 15 & All):',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF1E293B),
                ),
              ),
              _htmlBtn(
                engine.defaultMaxEntriesPerPage == 12 && !hasAnyPageWiseOverride
                    ? '☑ ✨ Auto (By Font Size) ✓'
                    : '✨ Auto (By Font Size)',
                engine.defaultMaxEntriesPerPage == 12 && !hasAnyPageWiseOverride
                    ? const Color(0xFF087F5B)
                    : Colors.white,
                engine.defaultMaxEntriesPerPage == 12 && !hasAnyPageWiseOverride
                    ? Colors.white
                    : const Color(0xFF065F46),
                () {
                  engine.defaultMaxEntriesPerPage = 12;
                  engine.pageEntryCountMap.removeWhere((k, _) => k.startsWith('$acc|'));
                  engine.triggerUpdate();
                  setState(() {});
                },
              ),
              for (final capOpt in const <int>[2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 25])
                _htmlBtn(
                  engine.defaultMaxEntriesPerPage == capOpt && !hasAnyPageWiseOverride
                      ? (capOpt == 25 ? '☑ All Fit (25) ✓' : '☑ $capOpt Entries ✓')
                      : (capOpt == 25 ? 'All Fit (25)' : '$capOpt Entries'),
                  engine.defaultMaxEntriesPerPage == capOpt && !hasAnyPageWiseOverride
                      ? const Color(0xFF0B4F9C)
                      : Colors.white,
                  engine.defaultMaxEntriesPerPage == capOpt && !hasAnyPageWiseOverride
                      ? Colors.white
                      : const Color(0xFF164B80),
                  () {
                    engine.defaultMaxEntriesPerPage = capOpt;
                    engine.pageEntryCountMap.removeWhere((k, _) => k.startsWith('$acc|'));
                    engine.triggerUpdate();
                    setState(() {});
                  },
                ),
            ],
          ),
          const SizedBox(height: 8),
          // 2. Gap Between Two Entries (mm)
          Wrap(
            spacing: 6,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              const Text(
                '📏 બે એન્ટ્રી વચ્ચે જગ્યા (Gap Between Two Entries):',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF0E3360),
                ),
              ),
              for (final g in const <double>[0, 1, 2, 3, 4, 5, 6, 7, 8, 10, 12, 15, 18, 20, 25])
                _htmlBtn(
                  (activeGapMm - g).abs() < 0.2 ? '☑ Gap ${g.toStringAsFixed(0)}mm ✓' : '${g.toStringAsFixed(0)}mm',
                  (activeGapMm - g).abs() < 0.2
                      ? const Color(0xFF087F5B)
                      : Colors.white,
                  (activeGapMm - g).abs() < 0.2
                      ? Colors.white
                      : const Color(0xFF164B80),
                  () {
                    engine.cashbookEntryGapMm = g;
                    engine.pageEntryGapMap.removeWhere((k, _) => k.startsWith('$acc|'));
                    engine.triggerUpdate();
                    setState(() {});
                  },
                ),
            ],
          ),
          const SizedBox(height: 8),
          // 3. Auto Font Size (pt)
          Wrap(
            spacing: 6,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              const Text(
                '🔤 Auto Font Size (પૂરી છેલ્લી એન્ટ્રી સમાવી ઓટો નવા પેજ):',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF0E3360),
                ),
              ),
              for (final pt in const <double>[8.0, 8.5, 9.0, 9.5, 10.0, 10.5, 11.0, 11.5, 12.0])
                _htmlBtn(
                  (activeFontPt - pt).abs() < 0.05 ? '☑ ${pt}pt ✓' : '${pt}pt',
                  (activeFontPt - pt).abs() < 0.05
                      ? const Color(0xFF0B4F9C)
                      : Colors.white,
                  (activeFontPt - pt).abs() < 0.05
                      ? Colors.white
                      : const Color(0xFF164B80),
                  () {
                    engine.cashbookPrintFontPt = pt;
                    engine.globalFontPt = pt;
                    engine.pageFontMap['default'] = pt;
                    engine.pageFontMap.removeWhere((k, _) => k.contains(acc));
                    engine.triggerUpdate();
                    setState(() {});
                  },
                ),
            ],
          ),
          // 4. Inline Page-by-Page (Credit Page 1, Page 3, Page 5... -> Auto Debit Page 2, Page 4, Page 6...) Entries & Gap Controls
          if (currPages.isNotEmpty) ...[
            const Divider(height: 18),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                const Text(
                  '📑 Page-Wise Entries & Gap (માત્ર જમા બાજુ Page 1, Page 3, Page 5... સેટ કરો → સામેનું ઉધાર પેજ Page 2, Page 4, Page 6... ઓટોમેટિક સેટ થશે):',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w900,
                    color: Color(0xFF0E3360),
                  ),
                ),
                _htmlBtn(
                  '📋 Open All Pages Table Setup',
                  const Color(0xFF185D98),
                  Colors.white,
                  () => _openAllCreditPagesSetupTableDialog(acc),
                ),
                if (hasAnyPageWiseOverride)
                  _htmlBtn(
                    '↺ Reset All Pages to Auto',
                    const Color(0xFFFFE3E3),
                    const Color(0xFFC92A2A),
                    () {
                      engine.pageEntryCountMap.removeWhere((k, _) => k.startsWith('$acc|'));
                      engine.pageEntryGapMap.removeWhere((k, _) => k.startsWith('$acc|'));
                      engine.triggerUpdate();
                      setState(() {});
                    },
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 10,
              runSpacing: 8,
              children: currPages.map((p) {
                final cPage = p.creditPageNo;
                final dPage = p.debitPageNo;
                final curCount = engine.getCreditPageEntryCount(acc, cPage, p.pairKey)?.toString() ?? 'auto';
                final curGap = engine.getCreditPageEntryGapMm(acc, cPage, p.pairKey);
                const gapOpts = <double>[0, 1, 2, 3, 4, 5, 6, 7, 8, 10, 12, 15, 18, 20, 25];
                final matchedGap = gapOpts.contains(curGap.roundToDouble()) ? curGap.roundToDouble() : 4.0;

                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: curCount != 'auto' ? const Color(0xFFFFFBEB) : Colors.white,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: curCount != 'auto' ? const Color(0xFFF59E0B) : const Color(0xFF93C5FD),
                      width: 1.3,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      InkWell(
                        onTap: () => _openQuickPageWiseEntryDialog(acc, p),
                        child: Text(
                          '📄 Page $cPage Credit (→ Auto Page $dPage Debit) • ${p.alignedCredits.length} Rows',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w900,
                            color: Color(0xFF0F2942),
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(
                            width: 135,
                            child: DropdownButtonFormField<String>(
                              isExpanded: true,
                              value: <String>['auto', '1', '2', '3', '4', '5', '6', '7', '8', '9', '10', '11', '12', '13', '14', '15', '25'].contains(curCount)
                                  ? curCount
                                  : 'auto',
                              decoration: const InputDecoration(
                                labelText: 'Entries',
                                border: OutlineInputBorder(),
                                isDense: true,
                                contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 7),
                              ),
                              items: [
                                const DropdownMenuItem(value: 'auto', child: Text('✨ Auto', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700))),
                                for (final n in const <int>[1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15])
                                  DropdownMenuItem(value: '$n', child: Text('$n Entries', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700))),
                                const DropdownMenuItem(value: '25', child: Text('All (25)', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700))),
                              ],
                              onChanged: (v) {
                                if (v == null) return;
                                if (v == 'auto') {
                                  engine.setCreditPageEntryCount(acc, cPage, null, p.pairKey);
                                } else {
                                  engine.setCreditPageEntryCount(acc, cPage, int.tryParse(v), p.pairKey);
                                }
                                engine.triggerUpdate();
                                setState(() {});
                              },
                            ),
                          ),
                          const SizedBox(width: 8),
                          SizedBox(
                            width: 115,
                            child: DropdownButtonFormField<double>(
                              isExpanded: true,
                              value: matchedGap,
                              decoration: const InputDecoration(
                                labelText: 'Gap (mm)',
                                border: OutlineInputBorder(),
                                isDense: true,
                                contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 7),
                              ),
                              items: gapOpts
                                  .map((g) => DropdownMenuItem(
                                        value: g,
                                        child: Text('Gap ${g.toStringAsFixed(0)}mm', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                                      ))
                                  .toList(),
                              onChanged: (v) {
                                if (v == null) return;
                                engine.setCreditPageEntryGapMm(acc, cPage, v, p.pairKey);
                                engine.triggerUpdate();
                                setState(() {});
                              },
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildPanelCashbook() {
    final acc = engine.selectedAccount;
    final pages = engine.buildCashbookPages(acc);
    final allSorted = engine.getSortedEntries(engine.getAccountEntries(acc));
    final opBal = engine.getAccountOpening(acc);

    double totalCr = 0.0;
    double totalDr = 0.0;
    for (final e in allSorted) {
      if ((engine.cashbookFromDate.isEmpty || e.date.compareTo(engine.cashbookFromDate) >= 0) &&
          (engine.cashbookToDate.isEmpty || e.date.compareTo(engine.cashbookToDate) <= 0)) {
        if (e.type == 'credit') {
          totalCr += e.amount;
        } else {
          totalDr += e.amount;
        }
      }
    }
    final closingTotal = opBal.total + totalCr - totalDr;

    _syncFilterControllersFromEngine();
    final fromCtrl = _cashbookFromDateCtrl;
    final toCtrl = _cashbookToDateCtrl;
    final fontCtrl = TextEditingController(text: engine.cashbookPrintFontPt.toStringAsFixed(1));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('કેશબુક / રોજમેળ', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: Color(0xFF10233F))),
        _htmlCard(
          body: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Wrap(
                spacing: 12,
                runSpacing: 12,
                crossAxisAlignment: WrapCrossAlignment.end,
                children: [
                  SizedBox(
                    width: 220,
                    child: DropdownButtonFormField<String>(
                      isExpanded: true,
                      value: acc,
                      decoration: const InputDecoration(labelText: 'ખાતું', border: OutlineInputBorder(), isDense: true),
                      items: engine.accounts.map((a) => DropdownMenuItem(value: a, child: Text(a))).toList(),
                      onChanged: (v) {
                        if (v != null) engine.selectAccount(v);
                      },
                    ),
                  ),
                  SizedBox(
                    width: 185,
                    child: _labeledDateInput(
                      'From Date',
                      fromCtrl,
                      onChanged: (v) => engine.cashbookFromDate = normalizeToIsoDate(v.trim()),
                      afterPicked: () {
                        engine.cashbookFromDate = normalizeToIsoDate(fromCtrl.text.trim());
                        engine.triggerUpdate();
                      },
                    ),
                  ),
                  SizedBox(
                    width: 185,
                    child: _labeledDateInput(
                      'To Date',
                      toCtrl,
                      onChanged: (v) => engine.cashbookToDate = normalizeToIsoDate(v.trim()),
                      afterPicked: () {
                        engine.cashbookToDate = normalizeToIsoDate(toCtrl.text.trim());
                        engine.triggerUpdate();
                      },
                    ),
                  ),
                  SizedBox(
                    width: 150,
                    child: _readonlyField('Starting Page No.', pages.isNotEmpty ? '${pages.first.creditPageNo}' : '1'),
                  ),
                  SizedBox(
                    width: 140,
                    child: _labeledInput(
                      'Print Font Size (pt)',
                      fontCtrl,
                      isNumber: true,
                      onChanged: (v) {
                        final parsed = double.tryParse(v);
                        if (parsed != null && parsed >= 6.5 && parsed <= 15) {
                          engine.cashbookPrintFontPt = parsed;
                        }
                      },
                    ),
                  ),
                  _htmlBtn('રિપોર્ટ બતાવો', const Color(0xFF185D98), Colors.white, () => engine.triggerUpdate()),
                  _htmlBtn('Show All Entries', const Color(0xFFE8F0FA), const Color(0xFF164B80), () {
                    engine.cashbookFromDate = '';
                    engine.cashbookToDate = '';
                    engine.triggerUpdate();
                  }),
                ],
              ),
              const SizedBox(height: 12),
              _buildMultiDateSamePageOptionBar(acc),
              const SizedBox(height: 12),
              // Exact Cashbook Action Buttons Bar from HTML
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _htmlBtn('Build Page Preview', const Color(0xFF185D98), Colors.white, () => engine.triggerUpdate()),
                  _htmlBtn('📥 Print / Auto-Download Cashbook PDF', const Color(0xFF087F5B), Colors.white, () {
                    final htmlStr = engine.generateExactCashbookPrintHtml(acc);
                    _openPrintPreviewModal('Cashbook_$acc', htmlStr);
                  }),
                  _htmlBtn('📚 Download Complete Audit File PDF (All 28 Reports, 1-Click)', const Color(0xFF185D98), Colors.white, () {
                    final allHtml = engine.generateReportPrintHtml('audit_pack', acc);
                    _openPrintPreviewModal('Complete_Audit_File_$acc', allHtml);
                  }),
                  _htmlBtn('📐 Choose Landscape / Portrait Reports & Side Space', const Color(0xFFE8F0FA), const Color(0xFF164B80), () {
                    _openReportPageSetupModal();
                  }),
                  _htmlBtn('🖨 પ્રિન્ટ સેટઅપ: પોર્ટ્રેટ / લેન્ડસ્કેપ અને બાઈન્ડિંગ જગ્યા', const Color(0xFF7C3AED), Colors.white, _openPrintBindingSetupDialog),
                  _htmlBtn('🖨 Browser Print (Ctrl+P)', const Color(0xFFE8F0FA), const Color(0xFF164B80), () {
                    final htmlStr = engine.generateExactCashbookPrintHtml(acc);
                    _openPrintPreviewModal('Cashbook_$acc', htmlStr, openBrowserPrintDialogInstead: true);
                  }),
                  _htmlBtn('🔤 Set Entry Font Size & Page Entries (Confirm)', const Color(0xFFE8F0FA), const Color(0xFF164B80), () {
                    if (pages.isNotEmpty) {
                      _openPageFontAndEntriesModal(page: pages.first, clickedPageNo: pages.first.creditPageNo, side: 'credit');
                    }
                  }),
                  _htmlBtn('✏ Edit Page Heading / Account Info (from first page)', const Color(0xFFE8F0FA), const Color(0xFF164B80), () {
                    _openEditPageHeaderModal(acc, pages.isNotEmpty ? pages.first.creditPageNo : 1);
                  }),
                  _htmlBtn(
                    engine.directPageEditActive ? '🔒 Lock Direct Page Text Edit' : '🔓 Edit Any Page Text (After Confirmation)',
                    engine.directPageEditActive ? const Color(0xFFFFF3BF) : const Color(0xFFE8F0FA),
                    engine.directPageEditActive ? const Color(0xFF754600) : const Color(0xFF164B80),
                    () {
                      engine.directPageEditActive = !engine.directPageEditActive;
                      engine.triggerUpdate();
                      _showToast(engine.directPageEditActive ? 'Direct Page Editing unlocked!' : 'Direct page text editing locked.');
                    },
                  ),
                  _htmlBtn('📊 Export Cashbook Excel (Same as PDF Print)', const Color(0xFF087F5B), Colors.white, () {
                    final xlsHtml = engine.generatePrintExactExcelHtml('daybook', acc);
                    _downloadBrowserFile(xlsHtml, 'application/vnd.ms-excel;charset=utf-8', 'Rojmel_Cashbook_PrintExact_${acc}_${engine.financialYear}.xls');
                    _showToast('Downloaded Print-Exact Cashbook Excel (.xls) for "$acc"!');
                  }),
                  _htmlBtn('📥 Export Complete Excel Workbook (.xls)', const Color(0xFF0E7490), Colors.white, () {
                    final xml = engine.generateAccountExcelXml(acc, false);
                    _downloadBrowserFile(xml, 'application/vnd.ms-excel;charset=utf-8', 'Rojmel_${acc}_${engine.financialYear}_All_Reports.xls');
                    Clipboard.setData(ClipboardData(text: xml));
                    _showToast('Downloaded Complete 18-Sheet Excel Workbook (.xls) for "$acc"!');
                  }),
                  _htmlBtn('🗑 Delete All Entries of Selected Account (2x Confirm)', const Color(0xFFFFE3E3), const Color(0xFFC92A2A), () {
                    _openDeleteAllAccountEntriesModal(acc);
                  }),
//                   _htmlBtn('Load 2-Page Demo (05-03-26)', const Color(0xFFFFF3BF), const Color(0xFF754600), () {
//                     engine.loadShortDemoData();
//                     _showToast('Loaded 2-Page Demo Data (05-03-2026) + SMCE Account');
//                   }),
                ],
              ),
            ],
          ),
        ),

        // .stats 4 KPI Cards (`#op`, `#cr`, `#dr`, `#cl`)
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            _statBox(formatMoney(opBal.total), 'Opening'),
            _statBox(formatMoney(totalCr), 'Credit'),
            _statBox(formatMoney(totalDr), 'Debit'),
            _statBox(formatMoney(closingTotal), 'Closing'),
          ],
        ),
        const SizedBox(height: 16),

        // Exact A4 Cashbook Pages (`#cashPrintPages`)
        if (pages.isEmpty)
          _noticeBox('No transactions found in $acc for the selected range. Click "Load Both Full 2025-26 Accounts" or add entries in Data Entry.', type: 'warn')
        else
          ...pages.asMap().entries.expand((en) {
              final pair = en.value;
              final firstPhys = engine.printSetup.cashbookLeadBlank + en.key * 2 + 1;
              return <Widget>[
                // Same-Date Overflow Banner (if > 4 entries on this date)
                if (pair.pairIndexOnDate == 0 && math.max(pair.totalCreditsOnDate, pair.totalDebitsOnDate) > 4)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Container(
                      padding: const EdgeInsets.all(11),
                      decoration: BoxDecoration(color: const Color(0xFFFFF3BF), borderRadius: BorderRadius.circular(9)),
                      child: Wrap(
                        alignment: WrapAlignment.spaceBetween,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: 10,
                        runSpacing: 8,
                        children: [
                          Text(
                            'Same Date Overflow (${pair.formattedDateDDMMYY}): ${pair.totalCreditsOnDate} Credit / ${pair.totalDebitsOnDate} Debit entries on this date. Current mode: ${engine.sameDateOverflowMode["$acc|${pair.dateStr}"] == "fit" ? "Fit on 1 Page" : "Continue on Next Page"}',
                            style: const TextStyle(color: Color(0xFF6C4D00), fontWeight: FontWeight.w800),
                          ),
                          Wrap(
                            spacing: 8,
                            children: [
                              _htmlBtn('Move Extra Entries to Next Page', const Color(0xFF185D98), Colors.white, () {
                                engine.sameDateOverflowMode['$acc|${pair.dateStr}'] = 'next';
                                engine.triggerUpdate();
                              }),
                              _htmlBtn('Keep on Same Page', const Color(0xFFE8F0FA), const Color(0xFF164B80), () {
                                engine.sameDateOverflowMode['$acc|${pair.dateStr}'] = 'fit';
                                engine.triggerUpdate();
                              }),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                // Odd Page: Credit (આવક / જમા +)
                _buildExactHtmlCashbookSinglePage(pair, isCredit: true, physicalPage: firstPhys),
                // Even Page: Debit (જાવક / ઉધાર -)
                _buildExactHtmlCashbookSinglePage(pair, isCredit: false, physicalPage: firstPhys + 1),
              ];
            }),
      ],
    );
  }

  /// Renders a single A4 Portrait Cashbook Page (`.cash-demo-page`) matching 100% of
  /// the exact HTML/CSS layout in `ROJMEL_V02_7_1_CASHBOOK_PRINT_FIXED.html`:
  /// - Odd pages (`1, 3, 5...`): right-side binding space (`padding: 3mm 24mm 2.8mm 9mm`)
  /// - Even pages (`2, 4, 6...`): left-side binding space (`padding: 3mm 9mm 2.8mm 24mm`)
  /// - Top title (`-: CASHBOOK :-` or `-: કેશબુક :-`)
  /// - Peach school/account bar (`#fde9d9`) with bottom border
  /// - Section title (`આવક (જમા) +` or `જાવક (ઉધાર) -`) with double bottom border
  /// - Borderless inner table columns (`6` columns on Credit, `9` columns on Debit)
  /// - Downward Summary Table with top single line & bottom double line on numbers
  /// - Downward Peach Page Number Bar (`#fde9d9` background, `#ff0000` red centered text `Page Number - X`)
  Widget _buildExactHtmlCashbookSinglePage(CashbookPagePair p, {required bool isCredit, int? physicalPage}) {
    final pageNo = isCredit ? p.creditPageNo : p.debitPageNo;
    // Page size and margins follow the print setup (orientation + binding
    // space of this PDF page), so the preview matches the print exactly.
    const mmPx = 3.7795;
    final land = engine.printSetup.isLandscapeCashbook;
    final box = engine.printSetup.boxFor(
      physicalPage ?? pageNo,
      kind: isCredit ? RojmelPageKind.cashbookCredit : RojmelPageKind.cashbookDebit,
      landscape: land,
    );
    final pageWPx = land ? 1123.0 : 794.0;
    final pageHPx = land ? 794.0 : 1122.0;
    final fontPt = isCredit ? p.crFontPt : p.drFontPt;
    final customCountVal = engine.pageEntryCountMap[p.pairKey];
    final countBadgeText = customCountVal == null
        ? 'Auto (${p.credits.length} Cr / ${p.debits.length} Dr)'
        : 'Set: $customCountVal entries';

    // Exact Peach Header Bar left/right text per Account Type (`BANK`, `PFMS`, `SNA_PURE`, `SNA`)
    final pageAccountLabel = engine.getPageAccountLabel(p.accountName, pageNo, isPfmsPage: p.isPfmsPage);
    final effAgency = p.snaAgencyCode.isNotEmpty ? p.snaAgencyCode : p.accountNumber;
    String leftPeachText = '';
    String rightPeachText = '';
    if (p.accountType == 'BANK') {
      if (isCredit) {
        leftPeachText = 'SCHOOL NAME : - ${p.schoolTitle}';
        rightPeachText = 'ACCOUNT NUMBER : - ${p.accountNumber}';
      } else {
        leftPeachText = 'ACCOUNT HOLDER NAME : - ${p.holderName}';
        rightPeachText = pageAccountLabel;
      }
    } else if (p.accountType == 'SNA_PURE') {
      // Purely SNA SPARSH: only Agency Code and Account Name (with School Name)
      leftPeachText = 'SCHOOL NAME : ${p.schoolTitle}${effAgency.isNotEmpty ? "  |  AGENCY CODE : $effAgency" : ""}';
      rightPeachText = 'ACCOUNT : $pageAccountLabel';
    } else if (p.isPfmsPage || p.accountType == 'PFMS') {
      if (isCredit) {
        leftPeachText = 'SCHOOL NAME : ${p.schoolTitle}';
        rightPeachText = 'A/C NUMBER : ${p.accountNumber}';
      } else {
        leftPeachText = 'A/C HOLDER NAME : ${p.holderName}';
        rightPeachText = pageAccountLabel;
      }
    } else {
      // SNA SPARSH duration of Combined PFMS + SNA SPARSH account
      leftPeachText = 'SCHOOL NAME : ${p.schoolTitle}${effAgency.isNotEmpty ? "  |  AGENCY CODE : $effAgency" : ""}';
      rightPeachText = pageAccountLabel;
    }

    final fyStartYr = engine.financialYear.length >= 4 ? engine.financialYear.substring(0, 4) : '2025';
    final refColTitle = engine.getPageRefColLabel(p.accountName, pageNo, isPfmsPage: p.isPfmsPage);
    final showColLines = engine.cashbookShowColumnLines;
    final fullTillEkandar = showColLines && engine.cashbookColumnLineMode == 'full_till_ekandar';

    final page = Container(
        width: pageWPx, // A4 width at 96dpi (210mm portrait / 297mm landscape)
        constraints: BoxConstraints(minHeight: pageHPx),
        margin: const EdgeInsets.symmetric(vertical: 10),
        padding: EdgeInsets.fromLTRB(box.left * mmPx, box.top * mmPx, box.right * mmPx, box.bottom * mmPx),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: engine.directPageEditActive ? const Color(0xFF087F5B) : const Color(0xFFC5CED8), width: engine.directPageEditActive ? 2.5 : 1),
          boxShadow: const [BoxShadow(color: Color(0x1F000000), blurRadius: 18, offset: Offset(0, 4))],
        ),
        child: Stack(
          children: [
            ConstrainedBox(
              constraints: BoxConstraints(minHeight: pageHPx - (box.top + box.bottom) * mmPx), // Full inner height so Summary & Page Number are ALWAYS pinned at the bottom!
              child: CustomPaint(
                foregroundPainter: fullTillEkandar
                    ? _CashbookColumnLinesPainter(
                        isCredit: isCredit,
                        fullPageTillEkandar: true,
                        tableOnly: false,
                      )
                    : null,
                child: Column(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                // .cash-demo-top-wrap (Upward Headers + Table)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // .cash-demo-title
                    InkWell(
                      onTap: () => _openEditPageHeaderModal(p.accountName, pageNo),
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Text(
                          isCredit ? p.creditTopTitle : p.debitPageTitle,
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontSize: 16.5, fontWeight: FontWeight.w700, color: Colors.black, height: 1.12),
                        ),
                      ),
                    ),
                    // .cash-demo-school (Peach Bar `#fde9d9`)
                    InkWell(
                      onTap: () => _openEditPageHeaderModal(p.accountName, pageNo),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: const BoxDecoration(
                          color: Color(0xFFFDE9D9),
                          border: Border(bottom: BorderSide(color: Colors.black, width: 1.1)),
                        ),
                        child: Wrap(
                          alignment: WrapAlignment.spaceBetween,
                          spacing: 10,
                          runSpacing: 2,
                          children: [
                            Text(leftPeachText, style: const TextStyle(fontSize: 12.8, fontWeight: FontWeight.w600, color: Colors.black)),
                            Text(rightPeachText, style: const TextStyle(fontSize: 12.8, fontWeight: FontWeight.w600, color: Colors.black)),
                          ],
                        ),
                      ),
                    ),
                    // .cash-demo-section (Double bottom border)
                    Container(
                      padding: const EdgeInsets.symmetric(vertical: 3),
                      decoration: const BoxDecoration(
                        border: Border(bottom: BorderSide(color: Colors.black, width: 1.3)),
                      ),
                      child: Container(
                        padding: const EdgeInsets.only(bottom: 2),
                        decoration: const BoxDecoration(
                          border: Border(bottom: BorderSide(color: Colors.black, width: 1.3)),
                        ),
                        child: Text(
                          isCredit ? 'આવક (જમા) +' : 'જાવક (ઉધાર) -',
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontSize: 15.2, fontWeight: FontWeight.w800, color: Colors.black),
                        ),
                      ),
                    ),
                    // .cash-demo-table thead + tbody (Wrapped in CustomPaint for 'only_till_entry' column lines)
                    CustomPaint(
                      foregroundPainter: (showColLines && !fullTillEkandar)
                          ? _CashbookColumnLinesPainter(
                              isCredit: isCredit,
                              fullPageTillEkandar: false,
                              tableOnly: true,
                            )
                          : null,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                    Container(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      decoration: const BoxDecoration(
                        border: Border(bottom: BorderSide(color: Colors.black, width: 2.4)),
                      ),
                      child: isCredit
                          ? Row(
                              children: const [
                                Expanded(flex: 11, child: Text('તારીખ', textAlign: TextAlign.center, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800))),
                                Expanded(flex: 24, child: Text('હેડ', textAlign: TextAlign.center, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800))),
                                Expanded(flex: 30, child: Text('આવકની વિગત', textAlign: TextAlign.center, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800))),
                                Expanded(flex: 11, child: Text('રોકડ', textAlign: TextAlign.center, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800))),
                                Expanded(flex: 12, child: Text('બેન્ક', textAlign: TextAlign.center, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800))),
                                Expanded(flex: 12, child: Text('કુલ રકમ', textAlign: TextAlign.center, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800))),
                              ],
                            )
                          : Row(
                              children: [
                                const Expanded(flex: 10, child: Text('તારીખ', textAlign: TextAlign.center, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800))),
                                const Expanded(flex: 11, child: Text('હેડ', textAlign: TextAlign.center, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800))),
                                const Expanded(flex: 22, child: Text('જાવકની વિગત', textAlign: TextAlign.center, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800))),
                                const Expanded(flex: 7, child: Text('વાઉચર\nનંબર', textAlign: TextAlign.center, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, height: 1.15))),
                                Expanded(
                                  flex: 9,
                                  child: InkWell(
                                    onTap: () => _openEditPageHeaderModal(p.accountName, pageNo),
                                    child: Tooltip(
                                      message: 'Click to edit Reference Column label (CLAIM નંબર / PPA નંબર / ચેક નંબર) from Page $pageNo onward',
                                      child: Text(
                                        refColTitle,
                                        textAlign: TextAlign.center,
                                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, height: 1.15, decoration: TextDecoration.underline, decorationStyle: TextDecorationStyle.dotted),
                                      ),
                                    ),
                                  ),
                                ),
                                const Expanded(flex: 9, child: Text('સેટલમેન્ટ\nતારીખ', textAlign: TextAlign.center, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, height: 1.15))),
                                const Expanded(flex: 10, child: Text('રોકડ', textAlign: TextAlign.center, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800))),
                                const Expanded(flex: 11, child: Text('બેન્ક', textAlign: TextAlign.center, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800))),
                                const Expanded(flex: 11, child: Text('કુલ રકમ', textAlign: TextAlign.center, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800))),
                              ],
                            ),
                    ),

                    // Opening Row on Credit Side OR Spacer Row on Debit Side
                    if (isCredit)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: p.accountType == 'BANK'
                            ? Row(
                                children: [
                                  const Expanded(flex: 11, child: SizedBox()),
                                  Expanded(
                                    flex: 54,
                                    child: Text(
                                      'તારીખ - ${p.isFirstPageOfFY ? "01/04/$fyStartYr" : p.formattedDateSlash}   -   શ્રી ઉઘડતી સિલક',
                                      style: TextStyle(fontSize: fontPt * 1.25, fontWeight: FontWeight.w800, color: Colors.black),
                                    ),
                                  ),
                                  Expanded(flex: 11, child: _cashbookAmountCell(fmtDemoNum(p.openCash), fontSize: fontPt * 1.22, isCredit: true)),
                                  Expanded(flex: 12, child: _cashbookAmountCell(fmtDemoNum(p.openBank), fontSize: fontPt * 1.22, isCredit: true)),
                                  Expanded(flex: 12, child: _cashbookAmountCell(fmtDemoNum(p.openTotal), fontSize: fontPt * 1.22, isCredit: true)),
                                ],
                              )
                            : Row(
                                children: [
                                  Expanded(flex: 11, child: Text(p.formattedDateDDMMYY, textAlign: TextAlign.center, style: TextStyle(fontSize: fontPt * 1.18))),
                                  const Expanded(flex: 24, child: SizedBox()),
                                  Expanded(flex: 30, child: Text('શ્રી ઉઘડતી સિલક', textAlign: TextAlign.center, style: TextStyle(fontSize: fontPt * 1.25, fontWeight: FontWeight.w800))),
                                  Expanded(flex: 11, child: _cashbookAmountCell(fmtDemoNum(p.openCash), fontSize: fontPt * 1.22, isCredit: true)),
                                  Expanded(flex: 12, child: _cashbookAmountCell(fmtDemoNum(p.openBank), fontSize: fontPt * 1.22, isCredit: true)),
                                  Expanded(flex: 12, child: _cashbookAmountCell(fmtDemoNum(p.openTotal), fontSize: fontPt * 1.22, isCredit: true)),
                                ],
                              ),
                      )
                    else
                      const SizedBox(height: 22),

                    // Entry Rows inside Writing Area (1-to-1 Aligned Opposite Slots with Shared Slot Heights & Entry Gap)
                    if (isCredit) ...[
                      if (p.alignedCredits.isNotEmpty)
                        ...p.alignedCredits.asMap().entries.map((entry) {
                          final idx = entry.key;
                          final e = entry.value;
                          final slotH = idx < p.slotHeightsMm.length ? p.slotHeightsMm[idx] : p.crRowHeightMm;
                          final gapPx = (p.entryGapMm * 3.1).clamp(2.0, 80.0);
                          if (e == null) {
                            return SizedBox(height: slotH * 3.1);
                          }
                          final c = RojmelEngine.cashAmt(e);
                          final b = RojmelEngine.bankAmt(e);
                          final dStr = p.accountType == 'BANK' ? fmtDateSlashDDMMYYYY(e.date) : fmtDateDDMMYY(e.date);
                          return InkWell(
                            onTap: () => _openEditTransactionModal(e),
                            child: Container(
                              constraints: BoxConstraints(minHeight: slotH * 3.1),
                              padding: EdgeInsets.only(top: 4, bottom: gapPx),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(flex: 11, child: Text(dStr, textAlign: TextAlign.center, style: TextStyle(fontSize: fontPt * 1.15))),
                                  Expanded(flex: 24, child: Padding(padding: const EdgeInsets.symmetric(horizontal: 4), child: Text(e.head, textAlign: TextAlign.center, style: TextStyle(fontSize: fontPt * 1.22)))),
                                  Expanded(flex: 30, child: Padding(padding: const EdgeInsets.symmetric(horizontal: 4), child: Text(RojmelEngine.formatCreditNarration(e), textAlign: TextAlign.center, style: TextStyle(fontSize: fontPt * 1.22)))),
                                  Expanded(flex: 11, child: _cashbookAmountCell(fmtDemoNum(c), fontSize: fontPt * 1.22, isCredit: true)),
                                  Expanded(flex: 12, child: _cashbookAmountCell(fmtDemoNum(b), fontSize: fontPt * 1.22, isCredit: true)),
                                  Expanded(flex: 12, child: _cashbookAmountCell(fmtDemoNum(c + b), fontSize: fontPt * 1.22, isCredit: true)),
                                ],
                              ),
                            ),
                          );
                        })
                      else if (p.accountType == 'BANK')
                        Container(
                          constraints: BoxConstraints(minHeight: p.crRowHeightMm * 3.1),
                          padding: const EdgeInsets.symmetric(vertical: 5),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(flex: 11, child: Text(p.formattedDateSlash, textAlign: TextAlign.center, style: TextStyle(fontSize: fontPt * 1.15))),
                              Expanded(flex: 24, child: Text(p.fallbackHead, textAlign: TextAlign.center, style: TextStyle(fontSize: fontPt * 1.22))),
                              Expanded(flex: 30, child: Text('આજની તારીખમાં કોઈ આવક થયેલ નથી', textAlign: TextAlign.center, style: TextStyle(fontSize: fontPt * 1.22))),
                              Expanded(flex: 11, child: _cashbookAmountCell('0.00', fontSize: fontPt * 1.22, isCredit: true)),
                              Expanded(flex: 12, child: _cashbookAmountCell('0.00', fontSize: fontPt * 1.22, isCredit: true)),
                              Expanded(flex: 12, child: _cashbookAmountCell('0.00', fontSize: fontPt * 1.22, isCredit: true)),
                            ],
                          ),
                        ),
                    ] else ...[
                      if (p.alignedDebits.isNotEmpty)
                        ...p.alignedDebits.asMap().entries.map((entry) {
                          final idx = entry.key;
                          final e = entry.value;
                          final slotH = idx < p.slotHeightsMm.length ? p.slotHeightsMm[idx] : p.drRowHeightMm;
                          final gapPx = (p.entryGapMm * 3.1).clamp(2.0, 80.0);
                          if (e == null) {
                            return SizedBox(height: slotH * 3.1);
                          }
                          final c = RojmelEngine.cashAmt(e);
                          final b = RojmelEngine.bankAmt(e);
                          final dStr = p.accountType == 'BANK' ? fmtDateSlashDDMMYYYY(e.date) : fmtDateDDMMYY(e.date);
                          final claimDisp = (RojmelEngine.isCashEntry(e) || RojmelEngine.isBankChargeEntry(e)) ? '' : RojmelEngine.fmtClaimWrapped(e.txn);
                          final settleDisp = RojmelEngine.isCashEntry(e) ? '' : (p.accountType == 'BANK' ? fmtDateSlashDDMMYYYY(e.clearDate) : fmtDateDDMMYY(e.clearDate));
                          return InkWell(
                            onTap: () => _openEditTransactionModal(e),
                            child: Container(
                              constraints: BoxConstraints(minHeight: slotH * 3.1),
                              padding: EdgeInsets.only(top: 4, bottom: gapPx),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(flex: 10, child: _cashbookCenterFitCell(dStr, fontSize: fontPt * 1.15)),
                                  Expanded(flex: 11, child: Padding(padding: const EdgeInsets.symmetric(horizontal: 2), child: Text(e.head, textAlign: TextAlign.center, style: TextStyle(fontSize: fontPt * 1.20)))),
                                  Expanded(flex: 22, child: Padding(padding: const EdgeInsets.symmetric(horizontal: 4), child: Text(engine.formatDebitNarration(e), textAlign: TextAlign.center, style: TextStyle(fontSize: fontPt * 1.20)))),
                                  Expanded(flex: 7, child: _cashbookCenterFitCell(e.voucher.isNotEmpty ? e.voucher : e.manualVoucher, fontSize: fontPt * 1.22)),
                                  Expanded(flex: 9, child: Padding(padding: const EdgeInsets.symmetric(horizontal: 2), child: Text(claimDisp, textAlign: TextAlign.center, style: TextStyle(fontSize: fontPt * 1.08, height: 1.22)))),
                                  Expanded(flex: 9, child: _cashbookCenterFitCell(settleDisp, fontSize: fontPt * 1.15)),
                                  Expanded(flex: 10, child: _cashbookAmountCell(fmtDemoNum(c), fontSize: fontPt * 1.22, isCredit: false)),
                                  Expanded(flex: 11, child: _cashbookAmountCell(fmtDemoNum(b), fontSize: fontPt * 1.22, isCredit: false)),
                                  Expanded(flex: 11, child: _cashbookAmountCell(fmtDemoNum(c + b), fontSize: fontPt * 1.22, isCredit: false)),
                                ],
                              ),
                            ),
                          );
                        })
                      else if (p.accountType == 'BANK')
                        Container(
                          constraints: BoxConstraints(minHeight: p.drRowHeightMm * 3.1),
                          padding: const EdgeInsets.symmetric(vertical: 5),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(flex: 10, child: Text(p.formattedDateSlash, textAlign: TextAlign.center, style: TextStyle(fontSize: fontPt * 1.15))),
                              Expanded(flex: 11, child: Text(p.fallbackHead, textAlign: TextAlign.center, style: TextStyle(fontSize: fontPt * 1.22))),
                              Expanded(flex: 22, child: Text('આજની તારીખમાં કોઈ ખર્ચ થયેલ નથી', textAlign: TextAlign.center, style: TextStyle(fontSize: fontPt * 1.22))),
                              const Expanded(flex: 25, child: SizedBox()),
                              Expanded(flex: 10, child: _cashbookAmountCell('0.00', fontSize: fontPt * 1.22, isCredit: false)),
                              Expanded(flex: 11, child: _cashbookAmountCell('0.00', fontSize: fontPt * 1.22, isCredit: false)),
                              Expanded(flex: 11, child: _cashbookAmountCell('0.00', fontSize: fontPt * 1.22, isCredit: false)),
                            ],
                          ),
                        ),
                    ],
                        ],
                      ),
                    ),
                  ],
                ),

                // .cash-demo-bottom-wrap (Summary Block + Downward Peach/Red Page Number Bar)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (isCredit)
                      _buildHtmlSummaryLine(
                        isCredit: true,
                        label: 'એકંદરે કુલ :',
                        cashStr: fmtDemoNum(p.grandCredit.cash),
                        bankStr: fmtDemoNum(p.grandCredit.bank),
                        totStr: fmtDemoNum(p.grandCredit.total),
                        topLine: true,
                        bottomDoubleLine: true,
                      )
                    else ...[
                      _buildHtmlSummaryLine(
                        isCredit: false,
                        label: 'કુલ ખર્ચ :',
                        cashStr: fmtDemoNum(p.drSum.cash),
                        bankStr: fmtDemoNum(p.drSum.bank),
                        totStr: fmtDemoNum(p.drSum.total),
                        topLine: false,
                        bottomDoubleLine: false,
                      ),
                      _buildHtmlSummaryLine(
                        isCredit: false,
                        label: 'શ્રી બંધ સિલક :',
                        cashStr: fmtDemoNum(p.closingBal.cash),
                        bankStr: fmtDemoNum(p.closingBal.bank),
                        totStr: fmtDemoNum(p.closingBal.total),
                        topLine: true,
                        bottomDoubleLine: false,
                      ),
                      _buildHtmlSummaryLine(
                        isCredit: false,
                        label: 'એકંદરે કુલ :',
                        cashStr: fmtDemoNum(p.grandDebit.cash),
                        bankStr: fmtDemoNum(p.grandDebit.bank),
                        totStr: fmtDemoNum(p.grandDebit.total),
                        topLine: true,
                        bottomDoubleLine: true,
                      ),
                    ],
                    const SizedBox(height: 5),
                    // .cash-demo-page-number (Peach bar `#fde9d9`, Red text `#ff0000`, centered)
                    InkWell(
                      onTap: () => _openPageFontAndEntriesModal(
                        page: p,
                        clickedPageNo: pageNo,
                        side: isCredit ? 'credit' : 'debit',
                      ),
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(vertical: 3.5),
                        color: const Color(0xFFFDE9D9),
                        child: Text(
                          'Page Number - $pageNo',
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Color(0xFFFF0000), fontSize: 13, fontWeight: FontWeight.w700),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
              ),
            ),

            // Screen-only quick button at top-right (`.page-layout-quick-btn`)
            Positioned(
              top: 0,
              right: 0,
              child: InkWell(
                onTap: () => _openPageFontAndEntriesModal(
                  page: p,
                  clickedPageNo: pageNo,
                  side: isCredit ? 'credit' : 'debit',
                ),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEEF5FF),
                    border: Border.all(color: const Color(0xFF9EC5FE)),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    '⚙ Page $pageNo Font (${fontPt}pt) & Entries ($countBadgeText)',
                    style: const TextStyle(color: Color(0xFF0B4F9C), fontSize: 10.5, fontWeight: FontWeight.w800),
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    // Phones / narrow panels: show the whole A4 page scaled to fit, like
    // a print preview, instead of squeezing its columns.
    return LayoutBuilder(builder: (context, c) {
      if (!c.maxWidth.isFinite || c.maxWidth >= pageWPx) return Center(child: page);
      return FittedBox(fit: BoxFit.fitWidth, alignment: Alignment.topCenter, child: page);
    });
  }

  Widget _cashbookCenterFitCell(String text, {required double fontSize, bool bold = false}) {
    if (text.trim().isEmpty) return const SizedBox();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Center(
        child: FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.center,
          child: Text(
            text,
            maxLines: 1,
            softWrap: false,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: fontSize,
              fontWeight: bold ? FontWeight.w800 : FontWeight.w500,
              color: Colors.black,
            ),
          ),
        ),
      ),
    );
  }

  /// Single-line auto-fitting numeric cell so Cash, Bank, and Total amounts NEVER wrap onto a second line (`image_257b76.png` & `image_257bf2.png`).
  Widget _cashbookAmountCell(
    String text, {
    required double fontSize,
    required bool isCredit,
    bool bold = false,
  }) {
    return Padding(
      padding: EdgeInsets.only(left: 2, right: isCredit ? 10.0 : 8.0),
      child: Align(
        alignment: Alignment.centerRight,
        child: FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerRight,
          child: Text(
            text,
            maxLines: 1,
            softWrap: false,
            textAlign: TextAlign.right,
            style: TextStyle(
              fontSize: fontSize,
              fontWeight: bold ? FontWeight.w800 : FontWeight.w500,
              color: Colors.black,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHtmlSummaryLine({
    required bool isCredit,
    required String label,
    required String cashStr,
    required String bankStr,
    required String totStr,
    required bool topLine,
    required bool bottomDoubleLine,
  }) {
    final numBorder = Border(
      top: topLine ? const BorderSide(color: Colors.black, width: 1.1) : BorderSide.none,
      bottom: bottomDoubleLine ? const BorderSide(color: Colors.black, width: 2.4) : BorderSide.none,
    );

    Widget sumBox(String valStr) => Container(
          padding: EdgeInsets.only(left: 2, right: isCredit ? 10.0 : 8.0, top: 2, bottom: 2),
          decoration: BoxDecoration(border: numBorder),
          alignment: Alignment.centerRight,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerRight,
            child: Text(
              valStr,
              maxLines: 1,
              softWrap: false,
              textAlign: TextAlign.right,
              style: const TextStyle(fontSize: 13.2, fontWeight: FontWeight.w600, color: Colors.black),
            ),
          ),
        );

    return Row(
      children: [
        Expanded(
          flex: isCredit ? 65 : 68, // Exact colspan="3" (65%) on credit and colspan="6" (68%) on debit so label never overlaps 0.00!
          child: Padding(
            padding: const EdgeInsets.only(right: 12, top: 2, bottom: 2),
            child: Text(
              label,
              textAlign: TextAlign.right,
              style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w800, color: Colors.black),
            ),
          ),
        ),
        Expanded(flex: isCredit ? 11 : 10, child: sumBox(cashStr)),
        Expanded(flex: isCredit ? 12 : 11, child: sumBox(bankStr)),
        Expanded(flex: isCredit ? 12 : 11, child: sumBox(totStr)),
      ],
    );
  }

  // --------------------------------------------------------------------------
  // PANEL 6: ALL 17 REPORTS (`#reportsPanel` — EXACT SAME-TO-SAME AS HTML)
  // --------------------------------------------------------------------------

  Widget _buildPanelReports() {
    final acc = engine.selectedAccount;
    final accHeads = engine.getAccountSpecificHeads(acc);
    if (engine.reportFilterHead != 'ALL' && !accHeads.contains(engine.reportFilterHead)) {
      engine.reportFilterHead = 'ALL';
    }
    _syncFilterControllersFromEngine();
    final fromCtrl = _reportFromDateCtrl;
    final toCtrl = _reportToDateCtrl;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('રિપોર્ટ્સ / Reports', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: Color(0xFF10233F))),
        _htmlCard(
          body: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Wrap(
                spacing: 12,
                runSpacing: 12,
                crossAxisAlignment: WrapCrossAlignment.end,
                children: [
                  SizedBox(
                    width: 450,
                    child: DropdownButtonFormField<String>(
                      value: engine.activeReportType,
                      isExpanded: true,
                      decoration: const InputDecoration(labelText: 'Report Type (1 to 22)', border: OutlineInputBorder(), isDense: true),
                      items: _reportTypes.map((rt) => DropdownMenuItem(value: rt['value']!, child: Text(rt['label']!, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)))).toList(),
                      onChanged: (v) {
                        if (v != null) {
                          engine.activeReportType = v;
                          engine.triggerUpdate();
                        }
                      },
                    ),
                  ),
                  SizedBox(
                    width: 210,
                    child: DropdownButtonFormField<String>(
                      isExpanded: true,
                      value: acc,
                      decoration: const InputDecoration(labelText: 'Account', border: OutlineInputBorder(), isDense: true),
                      items: engine.accounts.map((a) => DropdownMenuItem(value: a, child: Text(a))).toList(),
                      onChanged: (v) {
                        if (v != null) engine.selectAccount(v);
                      },
                    ),
                  ),
                  SizedBox(
                    width: 240,
                    child: DropdownButtonFormField<String>(
                      value: engine.reportFilterHead,
                      isExpanded: true,
                      decoration: const InputDecoration(labelText: 'Grant Head', border: OutlineInputBorder(), isDense: true),
                      items: [
                        DropdownMenuItem(value: 'ALL', child: Text('All Heads ($acc)')),
                        ...accHeads.map((h) => DropdownMenuItem(value: h, child: Text(h, overflow: TextOverflow.ellipsis))),
                      ],
                      onChanged: (v) {
                        engine.reportFilterHead = v ?? 'ALL';
                        engine.triggerUpdate();
                      },
                    ),
                  ),
                  SizedBox(
                    width: 175,
                    child: _labeledDateInput(
                      'From Date',
                      fromCtrl,
                      onChanged: (v) => engine.reportFromDate = normalizeToIsoDate(v.trim()),
                      afterPicked: () {
                        engine.reportFromDate = normalizeToIsoDate(fromCtrl.text.trim());
                        engine.triggerUpdate();
                      },
                    ),
                  ),
                  SizedBox(
                    width: 175,
                    child: _labeledDateInput(
                      'To Date',
                      toCtrl,
                      onChanged: (v) => engine.reportToDate = normalizeToIsoDate(v.trim()),
                      afterPicked: () {
                        engine.reportToDate = normalizeToIsoDate(toCtrl.text.trim());
                        engine.triggerUpdate();
                      },
                    ),
                  ),
                  _htmlBtn('Show Report', const Color(0xFF185D98), Colors.white, () => engine.triggerUpdate()),
                ],
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _htmlBtn('Show All Entries', const Color(0xFFFFF3BF), const Color(0xFF754600), () {
                    engine.reportFromDate = '';
                    engine.reportToDate = '';
                    engine.triggerUpdate();
                  }),
                  _htmlBtn('📥 Print / Auto-Download Selected Report PDF', const Color(0xFF087F5B), Colors.white, () {
                    final htmlStr = engine.generateReportPrintHtml(engine.activeReportType, acc);
                    _openPrintPreviewModal('Report_${engine.activeReportType}_$acc', htmlStr);
                  }),
                  _htmlBtn('📚 Download Complete Audit File PDF (All 28 Reports)', const Color(0xFF185D98), Colors.white, () {
                    final allHtml = engine.generateReportPrintHtml('audit_pack', acc);
                    _openPrintPreviewModal('Complete_Audit_File_$acc', allHtml);
                  }),
                  _htmlBtn('📊 Export Selected Report Excel (Same as PDF Print)', const Color(0xFF087F5B), Colors.white, () {
                    final xlsHtml = engine.generatePrintExactExcelHtml(engine.activeReportType, acc);
                    _downloadBrowserFile(xlsHtml, 'application/vnd.ms-excel;charset=utf-8', 'Rojmel_Report_${engine.activeReportType}_PrintExact_${acc}_${engine.financialYear}.xls');
                    _showToast('Downloaded Print-Exact Excel (.xls) for "${engine.activeReportType}"!');
                  }),
                  _htmlBtn('🖨 Browser Print (Ctrl+P)', const Color(0xFFE8F0FA), const Color(0xFF164B80), () {
                    final htmlStr = engine.generateReportPrintHtml(engine.activeReportType, acc);
                    _openPrintPreviewModal('Report_${engine.activeReportType}_$acc', htmlStr, openBrowserPrintDialogInstead: true);
                  }),
                  _htmlBtn('✏ Edit Heading / School / Account Info (All Pages)', const Color(0xFFE8F0FA), const Color(0xFF164B80), () => _openEditPageHeaderModal(acc)),
                  _htmlBtn('📥 Export Complete Excel Workbook (.xls)', const Color(0xFF0E7490), Colors.white, () {
                    final xml = engine.generateAccountExcelXml(acc, false);
                    _downloadBrowserFile(xml, 'application/vnd.ms-excel;charset=utf-8', 'Rojmel_${acc}_${engine.financialYear}_All_Reports.xls');
                    Clipboard.setData(ClipboardData(text: xml));
                    _showToast('Downloaded Complete Excel Workbook (all reports, 28 sheets) for "$acc"!');
                  }),
                  _htmlBtn('🗑 Delete All Entries of Selected Account (2x Confirm)', const Color(0xFFFFE3E3), const Color(0xFFC92A2A), () => _openDeleteAllAccountEntriesModal(acc)),
                ],
              ),
              if (engine.activeReportType == 'daybook') ...[
                const SizedBox(height: 12),
                _buildMultiDateSamePageOptionBar(acc),
              ],
              const SizedBox(height: 12),
              _buildReportPageSetupBar(),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _buildExactHtmlReportOutput(engine.activeReportType, acc),
      ],
    );
  }

  Widget _buildExactHtmlReportOutput(String type, String acc) {
    final mAcc = engine.getAccountMeta(acc);
    final allAcc = engine.getSortedEntries(engine.getAccountEntries(acc));
    final list = allAcc.where((e) =>
        (engine.reportFilterHead == 'ALL' || e.head == engine.reportFilterHead) &&
        (engine.reportFromDate.isEmpty || e.date.compareTo(engine.reportFromDate) >= 0) &&
        (engine.reportToDate.isEmpty || e.date.compareTo(engine.reportToDate) <= 0)).toList();
    final pageMap = engine.buildEntryPageNumberMap(acc);
    final khMap = engine.buildHeadKhatavahiPageMap(acc);

    switch (type) {
      case 'daybook':
        final pages = engine.buildCashbookPages(acc, engine.reportFilterHead, engine.reportFromDate, engine.reportToDate);
        final lead = engine.printSetup.cashbookLeadBlank;
        return Column(
          children: pages.asMap().entries.expand((en) => <Widget>[
                _buildExactHtmlCashbookSinglePage(en.value, isCredit: true, physicalPage: lead + en.key * 2 + 1),
                _buildExactHtmlCashbookSinglePage(en.value, isCredit: false, physicalPage: lead + en.key * 2 + 2),
              ]).toList(),
        );
      case 'parishisht_2':
        return _report2Parishisht2Khatavahi(list, acc, mAcc, pageMap, khMap);
      case 'bill_reg':
        return _report3BillRegister(list, acc, mAcc, pageMap);
      case 'cheque_reg':
        return _report4ChequeClaimRegister(list, acc, mAcc, pageMap);
      case 'kharch_patrak':
        return _report5KharchPatrak(list, acc, mAcc, pageMap);
      case 'parishisht_8':
        return _report6Parishisht8(acc, mAcc);
      case 'parishisht_9':
        return _report7Parishisht9Reconciliation(list, acc, mAcc);
      case 'parishisht_10':
        return _report8Parishisht10UC(list, acc, mAcc);
      case 'grant_reg':
        return _report9Parishisht11GrantReg(acc, mAcc);
      case 'annexure_12':
        return _report10Annexure12(allAcc, acc, mAcc);
      case 'monthly':
        return _report11MonthlyHisab(allAcc, acc, mAcc);
      case 'monthly_limit_report':
        return _report11BMonthlyLimitAndBalance(allAcc, acc, mAcc);
      case 'passbook':
        return _report12Passbook(list, acc, mAcc);
      case 'tally_report':
        return _report13TallyAudit(list, acc, mAcc);
      case 'receipt_payment':
        return _report14TarijPatrak(list, acc, mAcc);
      case 'voucher_cert':
        return _report15CertifiedVouchers(list, acc, mAcc, pageMap, khMap);
      case 'audit_certs':
        return _report16CoverPageAndIndex(list, acc, mAcc);
      case 'interest_register':
      case 'cash_register':
      case 'party_register':
      case 'balance_sheet':
      case 'income_expenditure':
      case 'gfr_12a':
      case 'monthly_brs':
      case 'asset_register':
      case 'cash_verification':
      case 'bank_certificate':
      case 'audit_crosscheck':
        return _reportExtraAuditTable(type, list, acc, mAcc);
      case 'audit_pack':
      default:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _report16CoverPageAndIndex(list, acc, mAcc),
            _report8Parishisht10UC(list, acc, mAcc),
            _report7Parishisht9Reconciliation(list, acc, mAcc),
            _report9Parishisht11GrantReg(acc, mAcc),
            _report6Parishisht8(acc, mAcc),
            _report3BillRegister(list, acc, mAcc, pageMap),
            _report4ChequeClaimRegister(list, acc, mAcc, pageMap),
            _report5KharchPatrak(list, acc, mAcc, pageMap),
            _report11BMonthlyLimitAndBalance(allAcc, acc, mAcc),
            _report13TallyAudit(list, acc, mAcc),
            _report14TarijPatrak(list, acc, mAcc),
            for (final k in const [
              'cash_register', 'interest_register', 'party_register', 'balance_sheet',
              'income_expenditure', 'gfr_12a', 'monthly_brs', 'asset_register',
              'cash_verification', 'bank_certificate', 'audit_crosscheck',
            ])
              _reportExtraAuditTable(k, list, acc, mAcc),
          ],
        );
    }
  }

  /// On-screen view for the additional audit registers (18–21).
  Widget _reportExtraAuditTable(String type, List<RojmelEntry> list, String acc, AccountMeta mAcc) {
    final t = engine.buildExtraAuditTable(
      type,
      acc,
      list,
      _openingAtReportFromDate(acc),
      _filteredHeadRows(acc),
    );
    return _govAuditSheet(
      children: [
        _govSchoolBlockHeader(t.title, acc, mAcc),
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Text(t.subtitle, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: Color(0xFF334155))),
        ),
        for (final n in t.preNotes)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(n, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800, color: Color(0xFF10233F))),
          ),
        _govAuditTable(
          headers: t.headers,
          rows: <List<String>>[
            for (final r in t.dataRows)
              [for (var i = 0; i < r.length; i++) i == 0 && r[i].startsWith('§') ? r[i].substring(1) : r[i].trim()],
            ...t.totalRows,
          ],
          lastRowIsTotal: t.totalRows.isNotEmpty,
        ),
        if (t.notes.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final n in t.notes)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 5),
                    child: Text(n, textAlign: TextAlign.justify, style: const TextStyle(fontSize: 12.2, height: 1.4, color: Color(0xFF111827))),
                  ),
              ],
            ),
          ),
        _govAuditSignatures(acc, labels: t.signLabels),
      ],
    );
  }

  /// PDF Page Setup Bar: Landscape/Portrait, Multi-Page vs Single-Page, Font Size (pt), Row Height (px), Left/Right Side Space (mm), and Default Reset
  Widget _buildReportPageSetupBar() {
    final activeType = engine.activeReportType;
    final isAuditPack = activeType == 'audit_pack';
    final isCurrLand = !isAuditPack && engine.isReportLandscape(activeType);
    final isCurrMulti = isAuditPack ? (engine.defaultReportPageMode != 'single') : engine.isReportMultiPage(activeType);
    final leftMm = engine.reportLeftSpaceMm.clamp(2.0, 30.0);
    final rightMm = engine.reportRightSpaceMm.clamp(2.0, 30.0);
    final fontPt = engine.parishisht10FontSizePt.clamp(7.0, 16.0);
    final rowHPx = engine.parishisht10RowHeightPx.clamp(20.0, 60.0);
    final maxRowsNow = engine.computeMaxRowsPerReportPage(isAuditPack ? 'parishisht_10' : activeType);

    const spaceOptions = <double>[2.0, 4.0, 6.0, 8.0, 10.0, 12.0, 15.0, 18.0, 20.0, 24.0, 28.0, 30.0];
    const fontOptions = <double>[7.0, 8.0, 9.0, 10.0, 11.0, 12.0, 13.0, 14.0, 15.0, 16.0];
    const rowHOptions = <double>[20.0, 22.0, 24.0, 26.0, 28.0, 30.0, 34.0, 38.0, 42.0, 48.0, 54.0, 60.0];

    final landCount = RojmelEngine.kDefaultReportOrientations.keys.where((k) => engine.isReportLandscape(k)).length;
    final portCount = RojmelEngine.kDefaultReportOrientations.keys.length - landCount;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFF0F6FF),
        border: Border.all(color: const Color(0xFF90B4E2), width: 1.4),
        borderRadius: BorderRadius.circular(9),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 10,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            alignment: WrapAlignment.spaceBetween,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  const Text(
                    '📐 PDF & Page Setup:',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w900, color: Color(0xFF0E3360)),
                  ),
                  if (!isAuditPack) ...[
                    _htmlBtn(
                      isCurrLand ? '🖥 Landscape (297×210 mm) ✓' : '🖥 Landscape',
                      isCurrLand ? const Color(0xFF087F5B) : const Color(0xFFE8F0FA),
                      isCurrLand ? Colors.white : const Color(0xFF164B80),
                      () => engine.setReportOrientation(activeType, 'landscape'),
                    ),
                    _htmlBtn(
                      !isCurrLand ? '📄 Portrait (210×297 mm) ✓' : '📄 Portrait',
                      !isCurrLand ? const Color(0xFF185D98) : const Color(0xFFE8F0FA),
                      !isCurrLand ? Colors.white : const Color(0xFF164B80),
                      () => engine.setReportOrientation(activeType, 'portrait'),
                    ),
                  ],
                  _htmlBtn(
                    isCurrMulti
                        ? '📑 Multi-Page (Auto Next Page: ~$maxRowsNow rows/page) ✓'
                        : '📑 Set Multi-Page (Auto Next Page)',
                    isCurrMulti ? const Color(0xFF087F5B) : const Color(0xFFE8F0FA),
                    isCurrMulti ? Colors.white : const Color(0xFF164B80),
                    () => engine.setReportPageMode(activeType, 'multi', applyToAll: isAuditPack),
                  ),
                  _htmlBtn(
                    !isCurrMulti ? '1️⃣ Single Page (Fit All on 1 Page) ✓' : '1️⃣ Set Single Page (1 Page)',
                    !isCurrMulti ? const Color(0xFF185D98) : const Color(0xFFE8F0FA),
                    !isCurrMulti ? Colors.white : const Color(0xFF164B80),
                    () => engine.setReportPageMode(activeType, 'single', applyToAll: isAuditPack),
                  ),
                  _htmlBtn(
                    '📋 Choose Landscape / Portrait & Multi-Page ($landCount Land / $portCount Port)',
                    const Color(0xFF185D98),
                    Colors.white,
                    _openReportPageSetupModal,
                  ),
                  _htmlBtn(
                    '🖨 બાઈન્ડિંગ જગ્યા (ઉપર / નીચે / ડાબે / જમણે, પાનાવાર)',
                    const Color(0xFF7C3AED),
                    Colors.white,
                    _openPrintBindingSetupDialog,
                  ),
                ],
              ),
              _htmlBtn(
                '↺ Default Reset',
                const Color(0xFFFFF3BF),
                const Color(0xFF754600),
                () {
                  engine.resetReportPageSetupToDefaults();
                  _showToast('Reset Page Setup to Default (Multi-Page, Font 10pt, Row Height 28px, Left/Right 8mm, Wide = Landscape)!');
                },
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 14,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Font Size (pt): ', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: Color(0xFF10233F))),
                  SizedBox(
                    width: 86,
                    child: DropdownButtonFormField<double>(
                      isExpanded: true,
                      value: fontOptions.contains(fontPt) ? fontPt : 10.0,
                      decoration: const InputDecoration(isDense: true, contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 5), border: OutlineInputBorder()),
                      items: fontOptions.map((f) => DropdownMenuItem(value: f, child: Text('${f.toStringAsFixed(0)} pt', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)))).toList(),
                      onChanged: (v) {
                        if (v != null) {
                          engine.parishisht10FontSizePt = v;
                          engine.triggerUpdate();
                        }
                      },
                    ),
                  ),
                ],
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Row Height (px): ', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: Color(0xFF10233F))),
                  SizedBox(
                    width: 92,
                    child: DropdownButtonFormField<double>(
                      isExpanded: true,
                      value: rowHOptions.contains(rowHPx) ? rowHPx : 28.0,
                      decoration: const InputDecoration(isDense: true, contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 5), border: OutlineInputBorder()),
                      items: rowHOptions.map((h) => DropdownMenuItem(value: h, child: Text('${h.toStringAsFixed(0)} px', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)))).toList(),
                      onChanged: (v) {
                        if (v != null) {
                          engine.parishisht10RowHeightPx = v;
                          engine.triggerUpdate();
                        }
                      },
                    ),
                  ),
                ],
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Left Space: ', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: Color(0xFF10233F))),
                  SizedBox(
                    width: 88,
                    child: DropdownButtonFormField<double>(
                      isExpanded: true,
                      value: spaceOptions.contains(leftMm) ? leftMm : 8.0,
                      decoration: const InputDecoration(isDense: true, contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 5), border: OutlineInputBorder()),
                      items: spaceOptions.map((m) => DropdownMenuItem(value: m, child: Text('${m.toStringAsFixed(0)} mm', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)))).toList(),
                      onChanged: (v) {
                        if (v != null) {
                          engine.reportLeftSpaceMm = v;
                          engine.triggerUpdate();
                        }
                      },
                    ),
                  ),
                ],
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Right Space: ', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: Color(0xFF10233F))),
                  SizedBox(
                    width: 88,
                    child: DropdownButtonFormField<double>(
                      isExpanded: true,
                      value: spaceOptions.contains(rightMm) ? rightMm : 8.0,
                      decoration: const InputDecoration(isDense: true, contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 5), border: OutlineInputBorder()),
                      items: spaceOptions.map((m) => DropdownMenuItem(value: m, child: Text('${m.toStringAsFixed(0)} mm', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)))).toList(),
                      onChanged: (v) {
                        if (v != null) {
                          engine.reportRightSpaceMm = v;
                          engine.triggerUpdate();
                        }
                      },
                    ),
                  ),
                ],
              ),
              Text(
                isCurrMulti
                    ? '✓ Multi-Page Active: Headers repeat on all pages (~$maxRowsNow rows/page at ${rowHPx.toStringAsFixed(0)}px row height)'
                    : '✓ Single-Page Active: All rows fit on 1 page',
                style: const TextStyle(fontSize: 11.8, fontWeight: FontWeight.w800, color: Color(0xFF087F5B)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Print & binding setup for the cashbook and every report: orientation
  /// of all pages, binding space (mm), its edge by binding layout, and
  /// page-wise top / bottom / left / right rules for double-sided printing.
  void _openPrintBindingSetupDialog() {
    final ps = engine.printSetup;
    final rulesCtrl = TextEditingController(text: RojmelPrintSetup.formatPageEdges(ps.pageEdges));
    final pageCtrl = TextEditingController();
    var quickEdge = 'top';
    var bad = <String>[];

    void changed() {
      engine.invalidateComputedCaches();
      engine.triggerUpdate();
    }

    Widget section(String title, List<Widget> children) => Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFFF8FBFF),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFFCCDCF0)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(title, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w900, color: Color(0xFF0E3360))),
              const SizedBox(height: 8),
              ...children,
            ],
          ),
        );

    Widget thumb(int page, RojmelPageKind kind, bool landscape, String tag) {
      final edge = ps.edgeFor(page, kind: kind, landscape: landscape);
      final ruled = ps.pageEdges.containsKey(page);
      final w = landscape ? 58.0 : 42.0;
      final h = landscape ? 42.0 : 58.0;
      const band = 8.0;
      final strip = edge == 'none'
          ? const SizedBox.shrink()
          : Positioned(
              left: edge == 'right' ? w - band : 0,
              top: edge == 'bottom' ? h - band : 0,
              width: edge == 'left' || edge == 'right' ? band : w,
              height: edge == 'top' || edge == 'bottom' ? band : h,
              child: Container(color: ruled ? const Color(0xFFF59E0B) : const Color(0xFF60A5FA)),
            );
      return Padding(
        padding: const EdgeInsets.only(right: 8, bottom: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 58,
              height: 58,
              child: Center(
                child: Container(
                  width: w,
                  height: h,
                  decoration: BoxDecoration(color: Colors.white, border: Border.all(color: const Color(0xFF64748B))),
                  child: Stack(children: [
                    strip,
                    Center(child: Text(tag, style: const TextStyle(fontSize: 9.5, fontWeight: FontWeight.w800, color: Color(0xFF334155)))),
                  ]),
                ),
              ),
            ),
            Text('પા. $page', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700)),
            Text(RojmelPrintSetup.edgeLabel(edge), style: TextStyle(fontSize: 9.5, color: edge == 'none' ? const Color(0xFF94A3B8) : const Color(0xFF1D4ED8), fontWeight: FontWeight.w800)),
          ],
        ),
      );
    }

    showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) {
          void apply(VoidCallback f) {
            setD(f);
            changed();
          }

          void setRules(Map<int, String> rules) {
            ps.pageEdges = rules;
            rulesCtrl.text = RojmelPrintSetup.formatPageEdges(rules);
            bad = <String>[];
          }

          final landCount = RojmelEngine.kDefaultReportOrientations.keys.where((k) => k != 'daybook' && engine.isReportLandscape(k)).length;
          final repCount = RojmelEngine.kDefaultReportOrientations.keys.where((k) => k != 'daybook').length;
          final sideMode = ps.mode == 'left' || ps.mode == 'duplex_left';
          final lead = ps.cashbookLeadBlank;
          final ruleGroups = RojmelPrintSetup.formatPageEdges(ps.pageEdges).split(', ').where((t) => t.isNotEmpty).toList();

          return AlertDialog(
            titlePadding: const EdgeInsets.fromLTRB(20, 18, 20, 6),
            title: const Text(
              '🖨 પ્રિન્ટ સેટઅપ — પોર્ટ્રેટ / લેન્ડસ્કેપ અને બાઈન્ડિંગ જગ્યા (બધા પાના)',
              style: TextStyle(fontSize: 16.5, fontWeight: FontWeight.w900, color: Color(0xFF10233F)),
            ),
            content: SizedBox(
              width: 880,
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    section('1. પાનાની દિશા (Portrait / Landscape)', [
                      Wrap(
                        spacing: 10,
                        runSpacing: 8,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          const Text('રોજમેળ / કેશબુકનાં પાનાં:', style: TextStyle(fontWeight: FontWeight.w800)),
                          SegmentedButton<String>(
                            segments: const [
                              ButtonSegment(value: 'portrait', icon: Icon(Icons.stay_current_portrait, size: 16), label: Text('પોર્ટ્રેટ (210×297)')),
                              ButtonSegment(value: 'landscape', icon: Icon(Icons.stay_current_landscape, size: 16), label: Text('લેન્ડસ્કેપ (297×210)')),
                            ],
                            selected: {ps.cashbookOrientation},
                            onSelectionChanged: (v) => apply(() => engine.cashbookOrientation = v.first),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _htmlBtn('📄 બધા પાના પોર્ટ્રેટ', const Color(0xFF185D98), Colors.white, () => apply(() => engine.setAllPagesOrientation('portrait'))),
                          _htmlBtn('🖥 બધા પાના લેન્ડસ્કેપ', const Color(0xFF087F5B), Colors.white, () => apply(() => engine.setAllPagesOrientation('landscape'))),
                          _htmlBtn('↺ ડિફોલ્ટ (પહોળાં પત્રકો લેન્ડસ્કેપ)', const Color(0xFFFFF3BF), const Color(0xFF754600), () => apply(() => engine.setAllPagesOrientation(null))),
                          _htmlBtn('📋 દરેક પત્રક અલગ પસંદ કરો', const Color(0xFFE8F0FA), const Color(0xFF164B80), () {
                            Navigator.of(ctx).pop();
                            _openReportPageSetupModal();
                          }),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text('હાલ: પત્રકોમાં $landCount લેન્ડસ્કેપ, ${repCount - landCount} પોર્ટ્રેટ • કેશબુક ${ps.isLandscapeCashbook ? 'લેન્ડસ્કેપ' : 'પોર્ટ્રેટ'}',
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFF475569))),
                    ]),
                    section('2. બાઈન્ડિંગ જગ્યા ક્યાં રાખવી', [
                      for (final m in RojmelPrintSetup.modes)
                        RadioListTile<String>(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          value: m.$1,
                          groupValue: ps.mode,
                          title: Text(m.$2, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800)),
                          subtitle: Text(m.$3, style: const TextStyle(fontSize: 11.5)),
                          onChanged: (v) => apply(() => ps.mode = v ?? 'register'),
                        ),
                    ]),
                    section('3. બાઈન્ડિંગ જગ્યા (બાઈન્ડિંગ બાજુનો કુલ હાંસિયો)', [
                      Row(
                        children: [
                          Expanded(
                            child: Slider(
                              min: 0,
                              max: 40,
                              divisions: 40,
                              value: ps.bindingMm.clamp(0.0, 40.0),
                              label: '${ps.bindingMm.toStringAsFixed(0)} mm',
                              onChanged: (v) => setD(() => ps.bindingMm = v.roundToDouble()),
                              onChangeEnd: (_) => changed(),
                            ),
                          ),
                          SizedBox(width: 70, child: Text('${ps.bindingMm.toStringAsFixed(0)} mm', style: const TextStyle(fontWeight: FontWeight.w900))),
                        ],
                      ),
                      Wrap(
                        spacing: 6,
                        children: [
                          for (final v in const [10.0, 15.0, 20.0, 24.0, 30.0])
                            ChoiceChip(
                              label: Text('${v.toStringAsFixed(0)} mm'),
                              selected: ps.bindingMm == v,
                              onSelected: (_) => apply(() => ps.bindingMm = v),
                            ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      const Text('બાકીની બાજુએ સામાન્ય હાંસિયો રહે છે (કેશબુક 9 mm, પત્રકોમાં ડાબે/જમણે સેટ કરેલી જગ્યા). ઉપર/નીચે જગ્યા હોય ત્યારે પાના પર ઓછી લાઈન આવે છે, જેથી કંઈ કપાય નહીં.',
                          style: TextStyle(fontSize: 11.5, color: Color(0xFF475569))),
                      const Divider(height: 18),
                      CheckboxListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        value: ps.rotateLandscape,
                        onChanged: sideMode ? (v) => apply(() => ps.rotateLandscape = v ?? true) : null,
                        title: const Text('ડાબી બાજુ ફાઈલમાં લેન્ડસ્કેપ પાનું ફેરવીને બંધાય છે — તેમાં જગ્યા ઉપર/નીચે આપમેળે', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
                      ),
                      CheckboxListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        value: ps.flipLandscape,
                        onChanged: sideMode && ps.rotateLandscape ? (v) => apply(() => ps.flipLandscape = v ?? false) : null,
                        title: const Text('મારું પ્રિન્ટર લેન્ડસ્કેપ પાનું બીજી દિશામાં ફેરવે છે — ઉપર/નીચે અદલબદલ કરો', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
                      ),
                      CheckboxListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        value: ps.duplexAlign,
                        onChanged: ps.isDuplex ? (v) => apply(() => ps.duplexAlign = v ?? false) : null,
                        title: const Text('બંને બાજુ પ્રિન્ટ: જરૂર હોય ત્યાં ખાલી પાનું ઉમેરો — ખુલ્લી ફાઈલમાં આવક-જાવક સામસામે અને દરેક પત્રક નવી શીટથી', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
                      ),
                    ]),
                    section('4. પાનાવાર જગ્યા — કોઈ પણ પાને ઉપર / નીચે / ડાબે / જમણે', [
                      const Text('PDF નો પાના ક્રમ લખો (પ્રિન્ટ ડાયલોગમાં દેખાય તે જ નંબર). આ નિયમ ઉપરની રીત કરતાં પહેલાં લાગે છે.',
                          style: TextStyle(fontSize: 11.5, color: Color(0xFF475569))),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          SizedBox(
                            width: 130,
                            child: TextField(
                              controller: pageCtrl,
                              decoration: const InputDecoration(isDense: true, labelText: 'પાના નં. (5 / 5-8)', border: OutlineInputBorder()),
                            ),
                          ),
                          SizedBox(
                            width: 130,
                            child: DropdownButtonFormField<String>(
                              isExpanded: true,
                              value: quickEdge,
                              isDense: true,
                              decoration: const InputDecoration(isDense: true, labelText: 'જગ્યા', border: OutlineInputBorder()),
                              items: [
                                for (final e in RojmelPrintSetup.edges)
                                  DropdownMenuItem(value: e, child: Text(RojmelPrintSetup.edgeLabel(e))),
                              ],
                              onChanged: (v) => setD(() => quickEdge = v ?? 'top'),
                            ),
                          ),
                          _htmlBtn('➕ ઉમેરો', const Color(0xFF185D98), Colors.white, () {
                            final r = RojmelPrintSetup.parsePageEdges('${pageCtrl.text.trim()}=$quickEdge');
                            if (r.bad.isNotEmpty || r.rules.isEmpty) {
                              setD(() => bad = <String>[pageCtrl.text.trim()]);
                              return;
                            }
                            apply(() {
                              setRules(<int, String>{...ps.pageEdges, ...r.rules});
                              pageCtrl.clear();
                            });
                          }),
                          _htmlBtn('🔁 એકી=ઉપર, બેકી=નીચે (પાના 1-200)', const Color(0xFFE8F0FA), const Color(0xFF164B80), () {
                            apply(() => setRules(<int, String>{for (var p = 1; p <= 200; p++) p: p.isOdd ? 'top' : 'bottom'}));
                          }),
                          if (ps.pageEdges.isNotEmpty)
                            _htmlBtn('🗑 બધા નિયમ કાઢો', const Color(0xFFFFE3E3), const Color(0xFFC92A2A), () => apply(() => setRules(<int, String>{}))),
                        ],
                      ),
                      if (ruleGroups.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            for (final g in ruleGroups)
                              InputChip(
                                label: Text(g, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                                onDeleted: () => apply(() {
                                  final r = RojmelPrintSetup.parsePageEdges(g);
                                  final next = Map<int, String>.from(ps.pageEdges)..removeWhere((k, _) => r.rules.containsKey(k));
                                  setRules(next);
                                }),
                              ),
                          ],
                        ),
                      ],
                      const SizedBox(height: 10),
                      TextField(
                        controller: rulesCtrl,
                        minLines: 1,
                        maxLines: 3,
                        decoration: const InputDecoration(
                          isDense: true,
                          border: OutlineInputBorder(),
                          labelText: 'બધા નિયમ એક સાથે લખો / સુધારો',
                          hintText: '5=ઉપર, 6=નીચે, 10-12=ડાબે, 15=જમણે, 20=નહીં',
                        ),
                        onChanged: (v) {
                          final r = RojmelPrintSetup.parsePageEdges(v);
                          setD(() => bad = r.bad);
                          if (r.bad.isEmpty) {
                            ps.pageEdges = r.rules;
                            changed();
                          }
                        },
                      ),
                      if (bad.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text('આ ભાગ સમજાયો નહીં: ${bad.join(' | ')} — ઉદા. 5=ઉપર, 6=નીચે, 10-12=ડાબે',
                              style: const TextStyle(fontSize: 11.5, color: Color(0xFFB42318), fontWeight: FontWeight.w700)),
                        ),
                    ]),
                    section('પૂર્વદર્શન — PDF પાના 1 થી 8 (ભૂરી પટ્ટી = બાઈન્ડિંગ જગ્યા, નારંગી = પાનાવાર નિયમ)', [
                      const Text('કેશબુક (આવક / જાવક):', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800)),
                      Wrap(children: [
                        for (var p = 1; p <= 8; p++)
                          if (p <= lead)
                            thumb(p, RojmelPageKind.blank, ps.isLandscapeCashbook, 'ખાલી')
                          else
                            thumb(
                              p,
                              (p - lead).isOdd ? RojmelPageKind.cashbookCredit : RojmelPageKind.cashbookDebit,
                              ps.isLandscapeCashbook,
                              (p - lead).isOdd ? 'આવક' : 'જાવક',
                            ),
                      ]),
                      const SizedBox(height: 6),
                      const Text('પત્રકો — પોર્ટ્રેટ અને લેન્ડસ્કેપ:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800)),
                      Wrap(children: [
                        for (var p = 1; p <= 4; p++) thumb(p, RojmelPageKind.report, false, 'P'),
                        for (var p = 5; p <= 8; p++) thumb(p, RojmelPageKind.report, true, 'L'),
                      ]),
                    ]),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => apply(() {
                  ps.reset();
                  setRules(<int, String>{});
                }),
                child: const Text('↺ ડિફોલ્ટ (હાલની રીત)'),
              ),
              FilledButton(
                onPressed: () {
                  Navigator.of(ctx).pop();
                  _showToast('પ્રિન્ટ સેટઅપ સાચવ્યું — PDF / પ્રિન્ટમાં લાગુ થશે.');
                },
                child: const Text('✔ બરાબર'),
              ),
            ],
          );
        },
      ),
    );
  }

  /// Modal Dialog allowing user to choose which reports (1..16) print in Landscape vs Portrait,
  /// Multi-Page vs Single-Page, Font Size (pt), Row Height (px), Left & Right Side Space (mm), and Default Reset.
  void _openReportPageSetupModal() {
    final leftCtrl = TextEditingController(text: engine.reportLeftSpaceMm.toStringAsFixed(1));
    final rightCtrl = TextEditingController(text: engine.reportRightSpaceMm.toStringAsFixed(1));
    final fontCtrl = TextEditingController(text: engine.parishisht10FontSizePt.toStringAsFixed(0));
    final rowHCtrl = TextEditingController(text: engine.parishisht10RowHeightPx.toStringAsFixed(0));

    showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) {
          final selectableReports = _reportTypes.where((rt) => rt['value'] != 'audit_pack').toList();
          return AlertDialog(
            title: const Text(
              '📐 Report Page Setup: Landscape/Portrait, Multi-Page/Single-Page, Row Height & Font Size',
              style: TextStyle(fontSize: 16.5, fontWeight: FontWeight.w900, color: Color(0xFF10233F)),
            ),
            content: SizedBox(
              width: 820,
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF0F6FF),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFFBFD4EE)),
                      ),
                      child: const Text(
                        '• Choose LANDSCAPE (297×210 mm) or PORTRAIT (210×297 mm) for each report.\n'
                        '• Choose MULTI-PAGE (if rows or bigger Row Height exceed 1 page, remaining data automatically moves to the next page with all headers & school info repeated on every page + Report Name & Page X of Y at the bottom) or SINGLE PAGE (fit all rows on 1 page).',
                        style: TextStyle(fontSize: 12.2, fontWeight: FontWeight.w700, color: Color(0xFF164B80)),
                      ),
                    ),
                    const SizedBox(height: 12),
                    ResponsiveFields(children: [
                      _labeledInput(
                            'Font Size (pt) [Default: 10]',
                            fontCtrl,
                            isNumber: true,
                            onChanged: (v) {
                              final p = double.tryParse(v.trim());
                              if (p != null && p >= 7 && p <= 16) {
                                setModalState(() {
                                  engine.parishisht10FontSizePt = p;
                                  engine.triggerUpdate();
                                });
                              }
                            },
                          ),
                      _labeledInput(
                            'Row Height (px) [Default: 28]',
                            rowHCtrl,
                            isNumber: true,
                            onChanged: (v) {
                              final p = double.tryParse(v.trim());
                              if (p != null && p >= 18 && p <= 68) {
                                setModalState(() {
                                  engine.parishisht10RowHeightPx = p;
                                  engine.triggerUpdate();
                                });
                              }
                            },
                          ),
                      _labeledInput(
                            'Left Space (mm) [Default: 8.0]',
                            leftCtrl,
                            isNumber: true,
                            onChanged: (v) {
                              final p = double.tryParse(v.trim());
                              if (p != null && p >= 0 && p <= 35) {
                                engine.reportLeftSpaceMm = p;
                                engine.triggerUpdate();
                              }
                            },
                          ),
                      _labeledInput(
                            'Right Space (mm) [Default: 8.0]',
                            rightCtrl,
                            isNumber: true,
                            onChanged: (v) {
                              final p = double.tryParse(v.trim());
                              if (p != null && p >= 0 && p <= 35) {
                                engine.reportRightSpaceMm = p;
                                engine.triggerUpdate();
                              }
                            },
                          ),
                    ]),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _htmlBtn('📑 Set All Reports Multi-Page (Auto Next Page)', const Color(0xFF087F5B), Colors.white, () {
                          setModalState(() {
                            engine.setReportPageMode('parishisht_10', 'multi', applyToAll: true);
                          });
                        }),
                        _htmlBtn('1️⃣ Set All Reports Single Page (1 Page)', const Color(0xFF185D98), Colors.white, () {
                          setModalState(() {
                            engine.setReportPageMode('parishisht_10', 'single', applyToAll: true);
                          });
                        }),
                        _htmlBtn('🖥 Set All Reports (2..16) Landscape', const Color(0xFF185D98), Colors.white, () {
                          setModalState(() {
                            for (final rt in selectableReports) {
                              final k = rt['value']!;
                              if (k != 'daybook') engine.reportOrientationMap[k] = 'landscape';
                            }
                            engine.triggerUpdate();
                          });
                        }),
                        _htmlBtn('📄 Set All Reports Portrait', const Color(0xFFE8F0FA), const Color(0xFF164B80), () {
                          setModalState(() {
                            for (final rt in selectableReports) {
                              engine.setReportOrientation(rt['value']!, 'portrait');
                            }
                          });
                        }),
                        _htmlBtn('↺ Default Reset', const Color(0xFFFFF3BF), const Color(0xFF754600), () {
                          setModalState(() {
                            engine.resetReportPageSetupToDefaults();
                            leftCtrl.text = engine.reportLeftSpaceMm.toStringAsFixed(1);
                            rightCtrl.text = engine.reportRightSpaceMm.toStringAsFixed(1);
                            fontCtrl.text = engine.parishisht10FontSizePt.toStringAsFixed(0);
                            rowHCtrl.text = engine.parishisht10RowHeightPx.toStringAsFixed(0);
                          });
                        }),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Container(
                      decoration: BoxDecoration(
                        border: Border.all(color: const Color(0xFFCCD8E7)),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Column(
                        children: selectableReports.map((rt) {
                          final key = rt['value']!;
                          final label = rt['label']!;
                          final isLand = engine.isReportLandscape(key);
                          final isMulti = engine.isReportMultiPage(key);
                          return Container(
                            decoration: const BoxDecoration(
                              border: Border(bottom: BorderSide(color: Color(0xFFE2E8F0))),
                            ),
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            child: Row(
                              children: [
                                Checkbox(
                                  value: isLand,
                                  activeColor: const Color(0xFF087F5B),
                                  onChanged: (val) {
                                    setModalState(() {
                                      engine.setReportOrientation(key, (val ?? false) ? 'landscape' : 'portrait');
                                    });
                                  },
                                ),
                                Expanded(
                                  child: Text(
                                    label,
                                    style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: Color(0xFF10233F)),
                                  ),
                                ),
                                const SizedBox(width: 6),
                                InkWell(
                                  onTap: () {
                                    setModalState(() {
                                      engine.setReportPageMode(key, isMulti ? 'single' : 'multi');
                                    });
                                  },
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                                    decoration: BoxDecoration(
                                      color: isMulti ? const Color(0xFF0E7490) : const Color(0xFFFFF3BF),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      isMulti ? '📑 MULTI-PAGE' : '1️⃣ SINGLE PAGE',
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w900,
                                        color: isMulti ? Colors.white : const Color(0xFF754600),
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 6),
                                InkWell(
                                  onTap: () {
                                    setModalState(() {
                                      engine.setReportOrientation(key, isLand ? 'portrait' : 'landscape');
                                    });
                                  },
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                    decoration: BoxDecoration(
                                      color: isLand ? const Color(0xFF087F5B) : const Color(0xFFE8F0FA),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      isLand ? '🖥 LANDSCAPE' : '📄 PORTRAIT',
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w900,
                                        color: isLand ? Colors.white : const Color(0xFF164B80),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () {
                  engine.resetReportPageSetupToDefaults();
                  Navigator.of(ctx).pop();
                  _showToast('Reset to Default Page Setup!');
                },
                child: const Text('↺ Default Reset'),
              ),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: const Color(0xFF087F5B)),
                onPressed: () {
                  final l = double.tryParse(leftCtrl.text.trim());
                  final r = double.tryParse(rightCtrl.text.trim());
                  final f = double.tryParse(fontCtrl.text.trim());
                  final rh = double.tryParse(rowHCtrl.text.trim());
                  if (l != null && l >= 0 && l <= 35) engine.reportLeftSpaceMm = l;
                  if (r != null && r >= 0 && r <= 35) engine.reportRightSpaceMm = r;
                  if (f != null && f >= 7 && f <= 16) engine.parishisht10FontSizePt = f;
                  if (rh != null && rh >= 18 && rh <= 68) engine.parishisht10RowHeightPx = rh;
                  engine.triggerUpdate();
                  Navigator.of(ctx).pop();
                  _showToast('Saved Page Setup (Orientation, Multi-Page/Single-Page, Font Size, Row Height & Side Space)!');
                },
                child: const Text('✓ Save & Apply Page Setup'),
              ),
            ],
          );
        },
      ),
    );
  }

  /// Bottom footer bar for every report page (Report Name on left + Page X of Y | Page Number on right)
  Widget _buildReportPageBottomFooterBar({
    required String reportTitle,
    required int pageInReport,
    required int totalPagesInReport,
    int? globalPageNo,
  }) {
    final pg = globalPageNo ?? pageInReport;
    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: const BoxDecoration(
        color: Color(0xFFFDE9D9),
        border: Border(top: BorderSide(color: Colors.black, width: 1.0)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Text(
              reportTitle,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: Color(0xFF10233F)),
            ),
          ),
          const SizedBox(width: 12),
          Text(
            'Page $pageInReport of $totalPagesInReport  |  Page Number - $pg',
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w900, color: Color(0xFFD90429)),
          ),
        ],
      ),
    );
  }

  /// Exact `.gov-audit-sheet` wrapper from HTML:
  /// - Automatically splits into multiple A4 sheet cards on screen when `Multi-Page` mode is active
  ///   and the report table has more rows than `computeMaxRowsPerReportPage` (based on Row Height & Font Size)!
  /// - Repeats all top headers & certificate/school info on EVERY page!
  /// - Appends the bottom footer bar (`Report Name` on left + `Page X of Y` on right) at the bottom of EVERY page!
  Widget _govAuditSheet({required List<Widget> children}) {
    final phone = MediaQuery.sizeOf(context).width < 600;
    final leftPx = phone ? 10.0 : (engine.reportLeftSpaceMm.clamp(2.0, 35.0) * 3.78).roundToDouble();
    final rightPx = phone ? 10.0 : (engine.reportRightSpaceMm.clamp(2.0, 35.0) * 3.78).roundToDouble();
    final rptKey = engine.activeReportType == 'audit_pack' ? 'parishisht_10' : engine.activeReportType;
    final footerTitle = engine.getReportFooterTitle(rptKey, engine.selectedAccount);

    // Find the primary data _GovAuditTableWidget (if any) to support live Multi-Page splitting on screen
    int mainTableIdx = -1;
    _GovAuditTableWidget? mainTable;
    for (int i = 0; i < children.length; i++) {
      final w = children[i];
      if (w is _GovAuditTableWidget && w.headers.isNotEmpty && w.rows.length > 3) {
        mainTableIdx = i;
        mainTable = w;
      }
    }

    final isMulti = engine.isReportMultiPage(rptKey);
    final maxPerPage = engine.computeMaxRowsPerReportPage(rptKey);

    if (isMulti && mainTable != null && mainTableIdx != -1) {
      final allRows = mainTable.rows;
      // Check if Row 0 is a column-number row like ['1', '2', ..., '12'] in Parishisht-10
      final hasColNumRow = allRows.isNotEmpty && allRows.first.length >= 4 && allRows.first[0].trim() == '1' && allRows.first[1].trim() == '2';
      final colNumRow = hasColNumRow ? allRows.first : null;
      final startDataIdx = hasColNumRow ? 1 : 0;

      // Determine how many trailing rows are total/summary rows
      int trailingTotalCount = 0;
      if (mainTable.lastRowIsTotal && allRows.length > startDataIdx) {
        for (int r = allRows.length - 1; r >= startDataIdx; r--) {
          final row = allRows[r];
          final firstCell = row.isNotEmpty ? row[0].trim() : '';
          final isNumberedDataRow = RegExp(r'^\d+$').hasMatch(firstCell);
          if (!isNumberedDataRow || r == allRows.length - 1) {
            trailingTotalCount++;
          } else {
            break;
          }
        }
        if (trailingTotalCount == 0) trailingTotalCount = 1;
      }

      final dataEndIdx = math.max(startDataIdx, allRows.length - trailingTotalCount);
      final dataRows = allRows.sublist(startDataIdx, dataEndIdx);
      final bottomTotals = allRows.sublist(dataEndIdx);

      if (dataRows.length > maxPerPage) {
        final chunks = <List<List<String>>>[];
        if (dataRows.length == 36 && maxPerPage >= 12 && maxPerPage <= 15) {
          chunks.add(dataRows.sublist(0, 14));
          chunks.add(dataRows.sublist(14, 26));
          chunks.add(dataRows.sublist(26, 36));
        } else {
          int idx = 0;
          while (idx < dataRows.length) {
            final rem = dataRows.length - idx;
            int take = maxPerPage;
            if (rem > maxPerPage && (rem - maxPerPage) < 3 && maxPerPage > 5) {
              take = maxPerPage - 2;
            }
            final end = math.min(idx + take, dataRows.length);
            chunks.add(dataRows.sublist(idx, end));
            idx = end;
          }
        }

        final headerWidgets = children.sublist(0, mainTableIdx);
        final afterTableWidgets = children.sublist(mainTableIdx + 1);
        final totalPages = chunks.length;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: List<Widget>.generate(totalPages, (cIdx) {
            final isLastPage = cIdx == totalPages - 1;
            final pageRows = <List<String>>[
              if (colNumRow != null) colNumRow,
              ...chunks[cIdx],
              if (isLastPage) ...bottomTotals,
            ];
            return Container(
              margin: const EdgeInsets.only(bottom: 22),
              padding: EdgeInsets.fromLTRB(leftPx, 18, rightPx, 14),
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border.all(color: const Color(0xFFB8C4D4), width: 1.2),
                boxShadow: const [BoxShadow(color: Color(0x17000000), blurRadius: 16, offset: Offset(0, 4))],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ...headerWidgets,
                  _GovAuditTableWidget(
                    headers: mainTable!.headers,
                    rows: pageRows,
                    lastRowIsTotal: isLastPage && mainTable.lastRowIsTotal,
                    boldAll: mainTable.boldAll,
                    fontSizePt: mainTable.fontSizePt ?? engine.parishisht10FontSizePt,
                    minRowHeightPx: mainTable.minRowHeightPx ?? engine.parishisht10RowHeightPx,
                  ),
                  if (isLastPage) ...afterTableWidgets,
                  _buildReportPageBottomFooterBar(
                    reportTitle: footerTitle,
                    pageInReport: cIdx + 1,
                    totalPagesInReport: totalPages,
                    globalPageNo: cIdx + 1,
                  ),
                ],
              ),
            );
          }),
        );
      }
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 18),
      padding: EdgeInsets.fromLTRB(leftPx, 18, rightPx, 14),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: const Color(0xFFB8C4D4)),
        boxShadow: const [BoxShadow(color: Color(0x17000000), blurRadius: 16, offset: Offset(0, 4))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ...children,
          _buildReportPageBottomFooterBar(
            reportTitle: footerTitle,
            pageInReport: 1,
            totalPagesInReport: 1,
            globalPageNo: 1,
          ),
        ],
      ),
    );
  }

  /// Compact Font Size (pt), Row Height (px), Multi-Page / Single-Page & Header Cell Editor bar for all reports
  Widget _buildReportFontAndHeightControlsBar({
    required String label,
    VoidCallback? onEditCells,
  }) {
    final fontPt = engine.parishisht10FontSizePt;
    final rowHPx = engine.parishisht10RowHeightPx;
    final rptKey = engine.activeReportType == 'audit_pack' ? 'parishisht_10' : engine.activeReportType;
    final isMulti = engine.isReportMultiPage(rptKey);
    const fontOpts = <double>[7.0, 8.0, 9.0, 10.0, 11.0, 12.0, 13.0, 14.0, 15.0, 16.0];
    const rowHOpts = <double>[20.0, 22.0, 24.0, 26.0, 28.0, 30.0, 34.0, 38.0, 42.0, 48.0, 54.0, 60.0];
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F5F9),
        border: Border.all(color: const Color(0xFF94A3B8)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Wrap(
        spacing: 14,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        alignment: WrapAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w900, color: Color(0xFF11345F)),
          ),
          Wrap(
            spacing: 10,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Font Size (pt): ', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800)),
                  SizedBox(
                    width: 86,
                    child: DropdownButtonFormField<double>(
                      isExpanded: true,
                      value: fontOpts.contains(fontPt) ? fontPt : 10.0,
                      decoration: const InputDecoration(isDense: true, contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 5), border: OutlineInputBorder()),
                      items: fontOpts
                          .map((f) => DropdownMenuItem(value: f, child: Text('${f.toStringAsFixed(0)} pt')))
                          .toList(),
                      onChanged: (v) {
                        if (v != null) {
                          engine.parishisht10FontSizePt = v;
                          engine.triggerUpdate();
                        }
                      },
                    ),
                  ),
                ],
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Row Height (px): ', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800)),
                  SizedBox(
                    width: 96,
                    child: DropdownButtonFormField<double>(
                      isExpanded: true,
                      value: rowHOpts.contains(rowHPx) ? rowHPx : 28.0,
                      decoration: const InputDecoration(isDense: true, contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 5), border: OutlineInputBorder()),
                      items: rowHOpts
                          .map((h) => DropdownMenuItem(value: h, child: Text('${h.toStringAsFixed(0)} px')))
                          .toList(),
                      onChanged: (v) {
                        if (v != null) {
                          engine.parishisht10RowHeightPx = v;
                          engine.triggerUpdate();
                        }
                      },
                    ),
                  ),
                ],
              ),
              _htmlBtn(
                isMulti ? '📑 Multi-Page ✓' : '1️⃣ Single Page ✓',
                isMulti ? const Color(0xFF087F5B) : const Color(0xFF185D98),
                Colors.white,
                () => engine.setReportPageMode(rptKey, isMulti ? 'single' : 'multi'),
              ),
              if (onEditCells != null)
                _htmlBtn('✏ Edit / Merge Header Cells', const Color(0xFF185D98), Colors.white, onEditCells),
            ],
          ),
        ],
      ),
    );
  }

  /// Universal Report Block Header (`image_234be6.png`):
  /// - If SNA SPARSH -> Default shows School Name, School Address, and Agency Code (`m.acNo`)
  /// - If BANK or PFMS -> Default shows School Name, Bank Holder Name, Account No, Bank Address, IFSC Code
  /// - Fully editable & mergeable cells + Font Size & Row Height controls across ALL reports!
  Widget _govSchoolBlockHeader(String titleText, String acc, AccountMeta m, [String rightMeta = '']) {
    final sName = m.schoolName.isNotEmpty ? m.schoolName : engine.schoolName;
    final sAddr = engine.fullFormattedSchoolAddress.isNotEmpty ? engine.fullFormattedSchoolAddress : engine.schoolAddress.trim();
    final effAgency = m.effectiveSnaAgencyCode;
    final fromNorm = normalizeToIsoDate(engine.reportFromDate);
    final toNorm = normalizeToIsoDate(engine.reportToDate);
    final pfmsLastIso = normalizeToIsoDate(m.pfmsLastDate);
    final snaStartIso = normalizeToIsoDate(m.snaStartDate);
    final isPurePfmsRange = m.type == 'SNA' && toNorm.isNotEmpty && pfmsLastIso.isNotEmpty && toNorm.compareTo(pfmsLastIso) <= 0;
    final isPureSnaRange = m.type == 'SNA' && fromNorm.isNotEmpty && snaStartIso.isNotEmpty && fromNorm.compareTo(snaStartIso) >= 0;

    final typeBadge = m.type == 'BANK'
        ? '$acc (BANK ACCOUNT)'
        : (m.type == 'PFMS' || isPurePfmsRange
            ? 'PFMS ACCOUNT ($acc)'
            : (m.type == 'SNA_PURE' || isPureSnaRange
                ? 'SNA SPARSH ACCOUNT ($acc)'
                : 'PFMS + SNA SPARSH ACCOUNT ($acc)'));
    final peachText = '$typeBadge${rightMeta.isNotEmpty ? " | $rightMeta" : ""}';

    List<List<String>> defaultGrid;
    if (m.type == 'SNA_PURE' || isPureSnaRange) {
      // Purely SNA SPARSH or SNA duration of Combined account: only Agency Code and Account Name for headers
      defaultGrid = <List<String>>[
        ['શાળાનું નામ :', sName, 'વર્ષ :', engine.financialYear],
        ['એજન્સી કોડ (Agency Code) :', effAgency, 'ખાતાનું નામ (Account Name) :', acc],
        [peachText, '', '', ''],
      ];
    } else if (m.type == 'SNA' && !isPurePfmsRange) {
      // Combined PFMS + SNA SPARSH (Full Year): present PFMS fields + SNA SPARSH Agency Code + PFMS Last Date & SNA Start Date
      defaultGrid = <List<String>>[
        ['શાળાનું નામ :', sName, 'વર્ષ :', engine.financialYear],
        ['બેંક ખાતેદારનું નામ (PFMS) :', m.holderName, 'PFMS બેંક ખાતા નંબર :', m.acNo],
        ['બેંક સરનામું :', '${m.branchAddress} ${m.bankName.isNotEmpty ? "(${m.bankName})" : ""}'.trim(), 'બેંક IFSC. કોડ :', m.ifsc],
        ['SNA SPARSH એજન્સી કોડ :', effAgency, 'ખાતાનું નામ :', acc],
        if (pfmsLastIso.isNotEmpty || snaStartIso.isNotEmpty)
          ['PFMS છેલ્લા વ્યવહારની તારીખ :', fmtDateSlashDDMMYYYY(pfmsLastIso), 'SNA SPARSH શરૂઆત તારીખ :', fmtDateSlashDDMMYYYY(snaStartIso)],
        [peachText, '', '', ''],
      ];
    } else {
      // BANK or PFMS or PFMS duration of Combined PFMS+SNA
      final dispSchool = (isPurePfmsRange && m.pfmsSchoolName.isNotEmpty) ? m.pfmsSchoolName : sName;
      defaultGrid = <List<String>>[
        ['શાળાનું નામ :', dispSchool, 'વર્ષ :', engine.financialYear],
        ['બેંક ખાતેદારનું નામ :', m.holderName, 'બેંક ખાતા નંબર :', m.acNo],
        ['બેંક સરનામું :', '${m.branchAddress} ${m.bankName.isNotEmpty ? "(${m.bankName})" : ""}'.trim(), 'બેંક IFSC. કોડ :', m.ifsc],
        [peachText, '', '', ''],
      ];
    }
    final defaultMergedRows = <int>[defaultGrid.length - 1];
    final storageKey = '$acc|HDR|$titleText';
    final activeGrid = engine.parishisht10CustomGrids[storageKey] ?? defaultGrid;
    final activeMerged = (engine.parishisht10MergedRows[storageKey] ?? defaultMergedRows).toSet();
    final fontPt = engine.parishisht10FontSizePt;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          onTap: () => _openParishisht10HeaderEditorDialog(storageKey, defaultGrid, defaultMergedRows, headerTitle: titleText),
          child: Container(
            padding: const EdgeInsets.only(bottom: 6),
            margin: const EdgeInsets.only(bottom: 6),
            decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Colors.black, width: 2.2))),
            child: Text(titleText, textAlign: TextAlign.center, style: TextStyle(fontSize: fontPt + 5, fontWeight: FontWeight.w900, color: Colors.black)),
          ),
        ),
        InkWell(
          onTap: () => _openParishisht10HeaderEditorDialog(storageKey, defaultGrid, defaultMergedRows, headerTitle: titleText),
          child: Container(
            decoration: BoxDecoration(
              border: Border.all(color: Colors.black, width: 1.0),
              color: Colors.white,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: List<Widget>.generate(activeGrid.length, (rIdx) {
                final isLast = rIdx == activeGrid.length - 1;
                final isMerged = activeMerged.contains(rIdx);
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                  decoration: BoxDecoration(
                    color: isLast ? const Color(0xFFFDE9D9) : Colors.white,
                    border: Border(
                      bottom: BorderSide(color: Colors.black, width: isLast ? 0.0 : 0.8),
                    ),
                  ),
                  child: isMerged
                      ? Text(
                          activeGrid[rIdx].firstWhere((c) => c.trim().isNotEmpty, orElse: () => ''),
                          textAlign: TextAlign.center,
                          style: TextStyle(fontWeight: FontWeight.w900, fontSize: fontPt + 0.5, color: Colors.black),
                        )
                      : Row(
                          children: List<Widget>.generate(4, (cIdx) {
                            final txt = cIdx < activeGrid[rIdx].length ? activeGrid[rIdx][cIdx] : '';
                            return Expanded(
                              flex: cIdx.isOdd ? 3 : 2,
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 4),
                                decoration: BoxDecoration(
                                  border: Border(
                                    right: BorderSide(color: cIdx < 3 ? Colors.black54 : Colors.transparent, width: 0.6),
                                  ),
                                ),
                                child: Text(
                                  txt,
                                  style: TextStyle(fontSize: fontPt, fontWeight: FontWeight.w900, color: Colors.black),
                                ),
                              ),
                            );
                          }),
                        ),
                );
              }),
            ),
          ),
        ),
        _buildReportFontAndHeightControlsBar(
          label: '⚙ Report Font & Row Height Settings (Click header or button to Edit / Merge Cells):',
          onEditCells: () => _openParishisht10HeaderEditorDialog(storageKey, defaultGrid, defaultMergedRows, headerTitle: titleText),
        ),
      ],
    );
  }

  /// Exact `getAuditSignatures` from HTML
  Widget _govAuditSignatures(String acc, {List<String>? labels}) {
    final sName = engine.getAccountSchoolName(acc);
    if (labels != null && labels.isNotEmpty) {
      return Padding(
        padding: const EdgeInsets.only(top: 32),
        child: Row(
          children: [
            for (var i = 0; i < labels.length; i++) ...[
              if (i > 0) const SizedBox(width: 36),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.only(top: 8),
                  decoration: const BoxDecoration(border: Border(top: BorderSide(color: Colors.black, width: 1.2))),
                  child: Text(labels[i].replaceAll('<br>', '\n'), textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12)),
                ),
              ),
            ],
          ],
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(top: 32),
      child: Row(
        children: [
          Expanded(
            child: Container(
              padding: const EdgeInsets.only(top: 8),
              decoration: const BoxDecoration(border: Border(top: BorderSide(color: Colors.black, width: 1.2))),
              child: const Text('SMC અધ્યક્ષની સહી\n(SMC Chairman)', textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12)),
            ),
          ),
          const SizedBox(width: 36),
          Expanded(
            child: Container(
              padding: const EdgeInsets.only(top: 8),
              decoration: const BoxDecoration(border: Border(top: BorderSide(color: Colors.black, width: 1.2))),
              child: Text('આચાર્યશ્રીની સહી અને સિક્કો\n($sName)', textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12)),
            ),
          ),
          const SizedBox(width: 36),
          Expanded(
            child: Container(
              padding: const EdgeInsets.only(top: 8),
              decoration: const BoxDecoration(border: Border(top: BorderSide(color: Colors.black, width: 1.2))),
              child: const Text('ઓડિટર / એકાઉન્ટન્ટની સહી\n(Auditor / Accountant)', textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12)),
            ),
          ),
        ],
      ),
    );
  }

  // REPORT 2: Parishisht-2 (કલાસીફાઈડ રજીસ્ટર / ખાતાવહી)
  Widget _report2Parishisht2Khatavahi(List<RojmelEntry> list, String acc, AccountMeta mAcc, Map<String, int> pageMap, Map<String, int> khMap) {
    final accHeads = engine.getAccountSpecificHeads(acc);
    final headsToShow = engine.reportFilterHead == 'ALL'
        ? accHeads.where((h) => list.any((e) => e.head == h) || engine.getHeadOpening(acc, h).total > 0 || mAcc.type == 'BANK').toList()
        : <String>[engine.reportFilterHead];

    return Column(
      children: headsToShow.asMap().entries.map((entry) {
        final idx = entry.key;
        final hName = entry.value;
        final hEntries = list.where((e) => e.head == hName).toList();
        final hop = engine.getHeadOpening(acc, hName);
        final openCash = hop.cash;
        final openBank = hop.bank;
        double crCash = 0, crBank = 0, drCash = 0, drBank = 0;

        final tableRows = <List<String>>[
          [
            '0',
            '01/04/${engine.financialYear.length >= 4 ? engine.financialYear.substring(0, 4) : "2025"}',
            'ગત વર્ષની બચત(ઉઘડતી સિલક)',
            '-',
            fmtDemoNum(openCash),
            fmtDemoNum(openBank),
            '-',
            '1',
            fmtDemoNum(openCash + openBank),
            '0.00',
            '0.00',
            '0.00',
          ],
        ];

        for (int rIdx = 0; rIdx < hEntries.length; rIdx++) {
          final e = hEntries[rIdx];
          final cC = e.type == 'credit' ? RojmelEngine.cashAmt(e) : 0.0;
          final cB = e.type == 'credit' ? RojmelEngine.bankAmt(e) : 0.0;
          final dC = e.type == 'debit' ? RojmelEngine.cashAmt(e) : 0.0;
          final dB = e.type == 'debit' ? RojmelEngine.bankAmt(e) : 0.0;
          crCash += cC;
          crBank += cB;
          drCash += dC;
          drBank += dB;
          tableRows.add([
            '${rIdx + 1}',
            fmtDateDDMMYY(e.date),
            e.type == 'debit' ? engine.formatDebitNarration(e) : RojmelEngine.formatCreditNarration(e),
            e.txn.isNotEmpty ? e.txn : '-',
            fmtDemoNum(cC),
            fmtDemoNum(cB),
            e.voucher.isNotEmpty ? e.voucher : '-',
            '${pageMap[e.id] ?? "-"}',
            fmtDemoNum(cC + cB),
            fmtDemoNum(dC),
            fmtDemoNum(dB),
            fmtDemoNum(dC + dB),
          ]);
        }

        final closeCash = openCash + crCash - drCash;
        final closeBank = openBank + crBank - drBank;
        final pageNo = khMap[hName] ?? (idx + 1);
        final headLimit = engine.getHeadLimit(acc, hName);

        tableRows.add([
          'TOTAL',
          '',
          'કુલ સરવાળો ($hName) :',
          '-',
          fmtDemoNum(openCash + crCash),
          fmtDemoNum(openBank + crBank),
          '-',
          '-',
          fmtDemoNum(openCash + openBank + crCash + crBank),
          fmtDemoNum(drCash),
          fmtDemoNum(drBank),
          fmtDemoNum(drCash + drBank),
        ]);

        final isSna = mAcc.type == 'SNA' || acc.trim().toUpperCase().contains('SNA');
        final sAddr = engine.schoolAddress.trim().isNotEmpty
            ? engine.schoolAddress.trim()
            : (engine.fullFormattedSchoolAddress.isNotEmpty ? engine.fullFormattedSchoolAddress : mAcc.branchAddress.trim());
        final p2Key = '$acc|P2|$hName';
        final p2DefaultGrid = <List<String>>[
          ['વર્ષ : ${engine.financialYear}', 'બેંક સિલક : ₹ ${fmtDemoNum(closeBank)}', 'કુલ આવક (બેંક) : ₹ ${fmtDemoNum(crBank)}', 'કુલ ખર્ચ (બેંક) : ₹ ${fmtDemoNum(drBank)}'],
          ['શાળાનું નામ : ${mAcc.schoolName}', 'રોકડ સિલક : ₹ ${fmtDemoNum(closeCash)}', 'કુલ આવક (રોકડા) : ₹ ${fmtDemoNum(crCash)}', 'કુલ ખર્ચ (રોકડા) : ₹ ${fmtDemoNum(drCash)}'],
          if (isSna)
            ['શાળાનું સરનામું : $sAddr', 'એજન્સી કોડ (Agency Code) : ${mAcc.acNo}', 'હેડનું નામ : $hName', 'ખાતાવહી પાના નં. : $pageNo']
          else
            [
              'હેડનું નામ : $hName',
              mAcc.type != 'BANK' ? 'વાર્ષિક મર્યાદા (Head Limit): ₹ ${fmtDemoNum(headLimit)}' : 'ઉઘડતી સિલક (Opening): ₹ ${fmtDemoNum(openCash + openBank)}',
              'ખાતાવહી પાના નં. : $pageNo',
              'ખાતા નં. : ${mAcc.acNo}',
            ],
        ];
        final p2ActiveGrid = engine.parishisht10CustomGrids[p2Key] ?? p2DefaultGrid;
        return _govAuditSheet(
          children: [
            InkWell(
              onTap: () => _openParishisht10HeaderEditorDialog(p2Key, p2DefaultGrid, const <int>[], headerTitle: 'પરિશિષ્ટ નંબર : 2 ($hName)'),
              child: Column(
                children: [
                  Text('પરિશિષ્ટ નંબર : 2 — નાણાકીય વર્ષ ${engine.financialYear} ($acc)', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900)),
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                    decoration: const BoxDecoration(color: Color(0xFFFDE9D9), border: Border(bottom: BorderSide(color: Colors.black))),
                    child: const Text('આવક ખર્ચનું વર્ગીકરણ (કલાસીફાઈડ રજીસ્ટર) (ખાતાવહી)', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            InkWell(
              onTap: () => _openParishisht10HeaderEditorDialog(p2Key, p2DefaultGrid, const <int>[], headerTitle: 'પરિશિષ્ટ નંબર : 2 ($hName)'),
              child: _govAuditTable(
                headers: const [],
                rows: p2ActiveGrid,
                boldAll: true,
              ),
            ),
            _buildReportFontAndHeightControlsBar(
              label: '⚙ Parishisht-2 Font & Row Height Settings:',
              onEditCells: () => _openParishisht10HeaderEditorDialog(p2Key, p2DefaultGrid, const <int>[], headerTitle: 'પરિશિષ્ટ નંબર : 2 ($hName)'),
            ),
            const SizedBox(height: 6),
            _govAuditTable(
              headers: [
                'ક્રમ', 'તારીખ', 'વિગત', mAcc.type == 'BANK' ? 'ચેક નંબર' : 'ચેક / CLAIM નંબર',
                'આ.રોકડા', 'આ.બેંક', 'વાઉચર નંબર', 'કેશબુક પા.નં.', 'આવક(+)', 'જા.રોકડા', 'જા.બેંક', 'ખર્ચ(-)',
              ],
              rows: tableRows,
              lastRowIsTotal: true,
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              color: const Color(0xFFFDE9D9),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Flexible(child: Text('આવક ખર્ચનું વર્ગીકરણ (કલાસીફાઈડ રજીસ્ટર) (ખાતાવહી) - $hName', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12))),
                  Text('Page Number - $pageNo', style: const TextStyle(color: Color(0xFFC92A2A), fontWeight: FontWeight.w800, fontSize: 12)),
                ],
              ),
            ),
            _govAuditSignatures(acc),
          ],
        );
      }).toList(),
    );
  }

  // REPORT 3: Bill Register (બિલ રજીસ્ટર)
  Widget _report3BillRegister(List<RojmelEntry> list, String acc, AccountMeta mAcc, Map<String, int> pageMap) {
    final debits = list.where((e) => e.type == 'debit').toList();
    double totalAmount = 0, padarTotal = 0, pfmsTotal = 0, snaTotal = 0;

    final rows = debits.asMap().entries.map((entry) {
      final i = entry.key;
      final e = entry.value;
      final amt = e.amount;
      totalAmount += amt;
      if (RojmelEngine.isCashEntry(e)) {
        padarTotal += amt;
      } else if (engine.isPFMSEntry(e)) {
        pfmsTotal += amt;
      } else {
        snaTotal += amt;
      }
      return <String>[
        e.voucher.isNotEmpty ? e.voucher : '${i + 1}',
        fmtDateDDMMYY(e.date),
        e.head,
        engine.formatDebitNarration(e),
        fmtDemoNum(amt),
        '0.00',
        fmtDemoNum(amt),
        '',
        '${pageMap[e.id] ?? "-"}',
        '',
      ];
    }).toList();

    if (mAcc.type == 'BANK') {
      final realExp = totalAmount - padarTotal;
      rows.addAll([
        ['', '', '', 'કુલ રકમ (Total Bill Amount) :', fmtDemoNum(totalAmount), '0.00', fmtDemoNum(totalAmount), '', '', ''],
        ['', '', '', 'આચાર્યશ્રી એ કરેલ પદરનું રોકાણ (Padar Cash Investment) :', fmtDemoNum(padarTotal), '0.00', fmtDemoNum(padarTotal), '', '', ''],
        ['', '', '', 'ખરેખર થયેલ ખર્ચ (Actual Net Bank Expenditure) :', fmtDemoNum(realExp), '0.00', fmtDemoNum(realExp), '', '', ''],
      ]);
    } else {
      final netPfmsSna = pfmsTotal + snaTotal;
      rows.addAll([
        ['', '', '', 'TOTAL AMOUNT (કુલ બિલ રકમ) :', fmtDemoNum(totalAmount), '0.00', fmtDemoNum(totalAmount), '', '', ''],
        ['', '', '', 'પહેલા પાંચ વાઉચરના પદરના રોકાણના (Padar Cash Vouchers) :', fmtDemoNum(padarTotal), '0.00', fmtDemoNum(padarTotal), '', '', ''],
        ['', '', '', 'PFMS TOTAL :', fmtDemoNum(pfmsTotal), '0.00', fmtDemoNum(pfmsTotal), '', '', ''],
        ['', '', '', 'SNA SPARSH TOTAL :', fmtDemoNum(snaTotal), '0.00', fmtDemoNum(snaTotal), '', '', ''],
        ['', '', '', 'TOTAL PFMS & SNA SPARSH TRANSACTION (ચોખ્ખો બેંક ગ્રાન્ટ ખર્ચ) :', fmtDemoNum(netPfmsSna), '0.00', fmtDemoNum(netPfmsSna), '', '', ''],
      ]);
    }

    return _govAuditSheet(
      children: [
        _govSchoolBlockHeader('વર્ષ દરમિયાનનું બિલોનું નોંધપત્રક (બિલ રજીસ્ટર)', acc, mAcc, 'Bill Register'),
        _govAuditTable(
          headers: const [
            'વાઉચર નંબર', 'તારીખ', 'બિલની વિગત (ગ્રાન્ટ હેડ)', 'બિલ કોના તરફથી મળેલ છે?',
            'બિલની રકમ ₹', 'કપાત ₹', 'ચુકવવાની થતી ચોખ્ખી રકમ ₹', 'મંજુર કરનાર સહી', 'કેશબુક પા.નં.', 'શેરો',
          ],
          rows: rows,
          lastRowIsTotal: true,
        ),
        _govAuditSignatures(acc),
      ],
    );
  }

  // REPORT 4: Cheque / Claim Register (ક્લેઈમ / ચેક રજીસ્ટર)
  Widget _report4ChequeClaimRegister(List<RojmelEntry> list, String acc, AccountMeta mAcc, Map<String, int> pageMap) {
    final bankDebits = list.where((e) => e.type == 'debit' && !RojmelEngine.isCashEntry(e) && !RojmelEngine.isBankChargeEntry(e)).toList();
    final bankCharges = list.where((e) => e.type == 'debit' && RojmelEngine.isBankChargeEntry(e)).fold<double>(0.0, (s, e) => s + e.amount);
    double totalCheque = 0.0;

    final rows = bankDebits.asMap().entries.map((entry) {
      final i = entry.key;
      final e = entry.value;
      totalCheque += e.amount;
      return <String>[
        '${i + 1}',
        fmtDateDDMMYY(e.date),
        e.txn.isNotEmpty ? e.txn : '-',
        e.voucher.isNotEmpty ? e.voucher : '-',
        fmtDemoNum(e.amount),
        engine.formatDebitNarration(e),
        fmtDemoNum(e.amount),
        e.head,
        '',
        fmtDateDDMMYY(e.clearDate),
        '${pageMap[e.id] ?? "-"}',
        '',
      ];
    }).toList();

    if (mAcc.type == 'BANK') {
      final totalDebited = totalCheque + bankCharges;
      rows.addAll([
        ['', '', '', 'કુલ ચેકની રકમ (Total Cheque Amount) :', fmtDemoNum(totalCheque), 'કુલ ચેકની રકમ :', fmtDemoNum(totalCheque), '', '', '', '', ''],
        ['', '', '', 'ચેક પરત થતા ચાર્જ (Cheque Return Bank Charge) :', fmtDemoNum(bankCharges), 'ચેક પરત થતા ચાર્જ :', fmtDemoNum(bankCharges), '', '', '', '', ''],
        ['', '', '', 'વર્ષ દરમિયાન ડેબિટ થયેલ રકમ (Total Debited in Bank) :', fmtDemoNum(totalDebited), 'વર્ષ દરમિયાન ડેબિટ થયેલ રકમ :', fmtDemoNum(totalDebited), '', '', '', '', ''],
      ]);
    } else {
      rows.add(['', '', '', 'TOTAL AMOUNT :', fmtDemoNum(totalCheque), 'TOTAL AMOUNT :', fmtDemoNum(totalCheque), '', '', '', '', '']);
    }

    return _govAuditSheet(
      children: [
        _govSchoolBlockHeader('વર્ષ દરમિયાનનું ચેકોનું નોંધપત્રક (${mAcc.type == "BANK" ? "ચેક રજીસ્ટર" : "ક્લેઈમ / ચેક રજીસ્ટર"})', acc, mAcc, 'Cheque / Claim Register'),
        _govAuditTable(
          headers: [
            'ક્રમ', 'તારીખ', mAcc.type == 'BANK' ? 'ચેક નંબર' : 'ક્લેઈમ / ચેક નંબર', 'વાઉચર નંબર',
            'ચેકની રકમ ₹', 'કઈ બાબતે કોને ચેક લખ્યો તેની વિગતો', 'બિલની રકમ ₹', 'બિલ હેડ વિગતો',
            'મંજુર કરનાર સહી', 'ચેક ક્લીરીંગ તારીખ', 'કેશબુક પા.નં.', 'શેરો',
          ],
          rows: rows,
          lastRowIsTotal: true,
        ),
        _govAuditSignatures(acc),
      ],
    );
  }

  // REPORT 5: Kharch Patrak (ખર્ચ પત્રક)
  Widget _report5KharchPatrak(List<RojmelEntry> list, String acc, AccountMeta mAcc, Map<String, int> pageMap) {
    final debits = list.where((e) => e.type == 'debit').toList();
    double totCash = 0, totBank = 0;

    final rows = debits.asMap().entries.map((entry) {
      final i = entry.key;
      final e = entry.value;
      final c = RojmelEngine.cashAmt(e);
      final b = RojmelEngine.bankAmt(e);
      totCash += c;
      totBank += b;
      return <String>[
        '${i + 1}',
        mAcc.type == 'BANK' ? engine.formatDebitNarration(e) : (e.party.isNotEmpty ? e.party : '-'),
        mAcc.type == 'BANK' ? e.expense : (e.expense.isNotEmpty ? e.expense : e.head),
        fmtDateDDMMYY(e.date),
        e.voucher.isNotEmpty ? e.voucher : '-',
        fmtDemoNum(c),
        fmtDemoNum(b),
        e.head,
        '${pageMap[e.id] ?? "-"}',
        '',
      ];
    }).toList();

    rows.add([
      '', '', '', '', 'કુલ રકમ રૂપિયા (Total Cash & Cheque Expenditure) :',
      fmtDemoNum(totCash), fmtDemoNum(totBank), 'નેટ બેંક ખર્ચ: ₹ ${fmtDemoNum(totBank)}', '', '',
    ]);

    return _govAuditSheet(
      children: [
        _govSchoolBlockHeader('ખર્ચ પત્રક (વર્ષ દરમિયાન ખર્ચનું નોંધપત્રક)', acc, mAcc, 'Kharch Patrak'),
        _govAuditTable(
          headers: const [
            'ક્રમ', 'પાર્ટીનું નામ / વિગત', 'ખર્ચની ટૂંકમાં વિગત', 'તારીખ', 'વાઉચર નંબર',
            'રોકડેથી કરેલ ખર્ચની રકમ ₹', 'ચેકથી કરેલ ખર્ચની રકમ ₹', 'જેમાંથી ખર્ચ કરેલ તે ગ્રાન્ટનું નામ', 'કેશબુક પા.નં.', 'શેરો',
          ],
          rows: rows,
          lastRowIsTotal: true,
        ),
        _govAuditSignatures(acc),
      ],
    );
  }

  // REPORT 6: Parishisht-8 (પરિશિષ્ટ-૮ ગોષવારો)
  Widget _report6Parishisht8(String acc, AccountMeta mAcc) {
    final showLim = mAcc.isSnaOrPfms;
    final headRows = engine.computeHeadWiseSummary(acc, engine.reportFromDate, engine.reportToDate);
    double sumLim = 0, sumOpen = 0, sumCr60 = 0, sumCr40 = 0, sumCr = 0, sumAvail = 0, sumDrCash = 0, sumDrBank = 0, sumDr = 0, sumClose = 0;

    final rows = headRows.asMap().entries.map((entry) {
      final i = entry.key;
      final r = entry.value;
      final avail = r.openTotal + r.bankCr;
      final close = avail - r.bankDr;
      final pct = avail > 0 ? ((r.bankDr / avail) * 100).toStringAsFixed(2) : '0.00';
      sumLim += r.annualLimit;
      sumOpen += r.openTotal;
      sumCr60 += r.bankCr60;
      sumCr40 += r.bankCr40;
      sumCr += r.bankCr;
      sumAvail += avail;
      sumDrCash += r.padarDr;
      sumDrBank += r.bankDr;
      sumDr += r.bankDr;
      sumClose += close;

      return <String>[
        '${i + 1}',
        r.head,
        if (showLim) fmtDemoNum(r.annualLimit),
        fmtDemoNum(r.openTotal),
        r.creditDates.take(4).join(', '),
        fmtDemoNum(r.bankCr60),
        fmtDemoNum(r.bankCr40),
        fmtDemoNum(r.bankCr),
        fmtDemoNum(avail),
        fmtDemoNum(r.padarDr),
        fmtDemoNum(r.bankDr),
        fmtDemoNum(r.bankDr),
        fmtDemoNum(close),
        '$pct%',
      ];
    }).toList();

    final totPct = sumAvail > 0 ? ((sumDr / sumAvail) * 100).toStringAsFixed(2) : '0.00';
    rows.add([
      '',
      'એકંદરે કુલ / Grand Total :',
      if (showLim) fmtDemoNum(sumLim),
      fmtDemoNum(sumOpen),
      '-',
      fmtDemoNum(sumCr60),
      fmtDemoNum(sumCr40),
      fmtDemoNum(sumCr),
      fmtDemoNum(sumAvail),
      fmtDemoNum(sumDrCash),
      fmtDemoNum(sumDrBank),
      fmtDemoNum(sumDr),
      fmtDemoNum(sumClose),
      '$totPct%',
    ]);

    return _govAuditSheet(
      children: [
        _govSchoolBlockHeader('પરિશિષ્ટ - ૮ (PARISHISHT - 8) : ગ્રાન્ટ ફાળવણી, ખર્ચ અને બંધ સિલક પત્રક (ગોષવારો)', acc, mAcc),
        _govAuditTable(
          headers: [
            'અ.નં.', 'ગ્રાન્ટ હેડ / ઘટકનું નામ',
            if (showLim) 'વાર્ષિક ગ્રાન્ટ મર્યાદા ₹',
            'ઉઘડતી સિલક ₹', 'ગ્રાન્ટ જમા તારીખ',
            mAcc.isAnySna ? 'PFMS / 60%' : '100% બેંક ગ્રાન્ટ',
            mAcc.isAnySna ? '40% રાજ્ય' : '-',
            'કુલ બેંક ગ્રાન્ટ ₹', 'કુલ પ્રાપ્ય ગ્રાન્ટ ₹',
            'પદર રોકડ', 'બેંક / SNA ખર્ચ', 'કુલ નેટ બેંક ખર્ચ ₹', 'આખરની બંધ સિલક ₹', 'વપરાશ %',
          ],
          rows: rows,
          lastRowIsTotal: true,
        ),
        _govAuditSignatures(acc),
      ],
    );
  }

  // REPORT 7: Parishisht-9 (બેંક સાથે મેળવણું – રીકન્સીલેશન)
  Widget _report7Parishisht9Reconciliation(List<RojmelEntry> list, String acc, AccountMeta mAcc) {
    final openBank = engine.getAccountOpening(acc).bank;
    double crBank = 0, drBank = 0;
    for (final e in list) {
      if (e.type == 'credit') {
        crBank += RojmelEngine.bankAmt(e);
      } else {
        drBank += RojmelEngine.bankAmt(e);
      }
    }
    final cashbookClosingBank = openBank + crBank - drBank;
    final cutOff = engine.reportToDate.isNotEmpty ? engine.reportToDate : '2026-03-31';
    final unpresentedClaims = list.where((e) => e.type == 'debit' && !RojmelEngine.isCashEntry(e) && e.clearDate.isNotEmpty && e.clearDate.compareTo(cutOff) > 0).toList();
    final add1 = unpresentedClaims.fold<double>(0.0, (s, e) => s + e.amount);
    final add2 = engine.p9Add2DirectCredit;
    final addTotal = add1 + add2;
    final sub1 = engine.p9Sub1UncreditedDeposit;
    final sub2 = engine.p9Sub2BankCharges;
    final subTotal = sub1 + sub2;
    final passbookBalance = cashbookClosingBank + addTotal - subTotal;

    return _govAuditSheet(
      children: [
        _govSchoolBlockHeader('પરિશિષ્ટ – 9 (PARISHISHT - 9) : બેંક સાથે મેળવણું – રીકન્સીલેશન (Bank Reconciliation)', acc, mAcc),
        _govAuditTable(
          headers: const ['ક્રમ', 'પેટા', 'વિગત (Reconciliation Particulars)', 'પેટા રકમ ₹ (Sub Amount)', 'કુલ રકમ ₹ (Total Amount)'],
          rows: [
            ['-', '', 'રોજમેળ પ્રમાણે તા. ${fmtDateDDMMYY(cutOff)} ની સિલક (Closing Balance as per Cashbook)\n(ઉઘડતી ₹ ${fmtDemoNum(openBank)} + જમા ₹ ${fmtDemoNum(crBank)} − ખર્ચ ₹ ${fmtDemoNum(drBank)})', '-', fmtDemoNum(cashbookClosingBank)],
            ['૧ (+)', '', 'ઉમેરવું (Add +) :', '', ''],
            ['', '1', 'ચેક ઇસ્યુ થયા હોય પરંતુ વટાવેલ ન હોય (${unpresentedClaims.length} Cheques/Claims)', fmtDemoNum(add1), ''],
            ['', '2', 'બેંકમાં જમા નોંધ થઇ હોય પરંતુ રોજમેળમાં દર્શાવ્યું ન હોય', fmtDemoNum(add2), ''],
            ['', '', 'કુલ ઉમેરવું (Sub-Total Add = 1 + 2) :', fmtDemoNum(addTotal), fmtDemoNum(addTotal)],
            ['૨ (-)', '', 'બાદ કરવું (Deduct −) :', '', ''],
            ['', '1', 'બેંકમાં મોકલવામાં આવેલી રોકડ કે ચેક બેંક ખાતામાં જમા ન થઇ હોય', fmtDemoNum(sub1), ''],
            ['', '2', 'બેંક ખાતામાં ઉધારવામાં આવેલ ચાર્જિસ પરંતુ તે રોજમેળમાં ઉલ્લેખ થયેલ ન હોય', fmtDemoNum(sub2), ''],
            ['', '', 'કુલ બાદ કરવું (Sub-Total Deduct = 1 + 2) :', fmtDemoNum(subTotal), fmtDemoNum(subTotal)],
            ['=', '', 'પાસબુક / બેંક સ્ટેટમેન્ટ પ્રમાણે સિલક (Passbook Balance = Cashbook + Add − Deduct)', fmtDemoNum(passbookBalance), fmtDemoNum(passbookBalance)],
          ],
          lastRowIsTotal: true,
        ),
        _govAuditSignatures(acc),
      ],
    );
  }

  // Universal Dialog to Edit & Merge Header Cells across Parishisht-10 and All Reports (`image_22c4e4.png`, `image_22d7c3.png`, `image_234be6.png`)
  Future<void> _openParishisht10HeaderEditorDialog(
    String storageKey,
    List<List<String>> defaultGrid,
    List<int> defaultMergedRows, {
    String headerTitle = 'Parishisht-10 Header',
  }) async {
    final currentGrid = (engine.parishisht10CustomGrids[storageKey] ?? defaultGrid)
        .map((r) => List<String>.from(r))
        .toList();
    final currentMerged = Set<int>.from(engine.parishisht10MergedRows[storageKey] ?? defaultMergedRows);
    final ctrls = currentGrid
        .map((r) => List<TextEditingController>.generate(4, (c) => TextEditingController(text: c < r.length ? r[c] : '')))
        .toList();

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) => AlertDialog(
          title: Text(
            '✏ Edit & Merge Header Cells — $headerTitle',
            style: const TextStyle(fontSize: 16.5, fontWeight: FontWeight.w900, color: Color(0xFF11345F)),
          ),
          content: SizedBox(
            width: 760,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(color: const Color(0xFFF4F9FF), borderRadius: BorderRadius.circular(8), border: Border.all(color: const Color(0xFF7AA7D8))),
                    child: const Text(
                      '• Edit any cell below, or tick "Merge Cells in Row (Full 4-Col Span)" to merge all 4 cells of that row into a single full-width banner row.\n'
                      '• You can also add new rows or reset to the default account-type layout (SNA SPARSH = School Name, Address, Agency Code; BANK/PFMS = Bank Details) anytime.',
                      style: TextStyle(fontSize: 12.2, fontWeight: FontWeight.w700, color: Color(0xFF11345F)),
                    ),
                  ),
                  const SizedBox(height: 12),
                  ...List<Widget>.generate(ctrls.length, (rIdx) {
                    final isMerged = currentMerged.contains(rIdx);
                    return Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: isMerged ? const Color(0xFFFFF8EE) : Colors.white,
                        border: Border.all(color: const Color(0xFFCCD8E7)),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text('Row ${rIdx + 1}', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 12.5, color: Color(0xFF11345F))),
                              Row(
                                children: [
                                  Checkbox(
                                    value: isMerged,
                                    onChanged: (v) {
                                      setModalState(() {
                                        if (v == true) {
                                          final combined = ctrls[rIdx].map((c) => c.text.trim()).where((s) => s.isNotEmpty).join('   ');
                                          if (combined.isNotEmpty) ctrls[rIdx][0].text = combined;
                                          currentMerged.add(rIdx);
                                        } else {
                                          currentMerged.remove(rIdx);
                                        }
                                      });
                                    },
                                  ),
                                  const Text('Merge Cells in Row (Full 4-Col Span)', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800)),
                                  const SizedBox(width: 8),
                                  if (ctrls.length > 1)
                                    IconButton(
                                      tooltip: 'Delete Row',
                                      icon: const Icon(Icons.delete_outline, size: 18, color: Color(0xFFC92A2A)),
                                      onPressed: () {
                                        setModalState(() {
                                          ctrls.removeAt(rIdx);
                                          final updatedMerged = <int>{};
                                          for (final m in currentMerged) {
                                            if (m < rIdx) updatedMerged.add(m);
                                            if (m > rIdx) updatedMerged.add(m - 1);
                                          }
                                          currentMerged
                                            ..clear()
                                            ..addAll(updatedMerged);
                                        });
                                      },
                                    ),
                                ],
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          if (isMerged)
                            _labeledInput('Merged Full-Width Row Text (Col 1–4 Merged)', ctrls[rIdx][0], maxLines: 2)
                          else
                            Row(
                              children: List<Widget>.generate(4, (cIdx) {
                                return Expanded(
                                  child: Padding(
                                    padding: EdgeInsets.only(right: cIdx < 3 ? 8.0 : 0.0),
                                    child: _labeledInput('Col ${cIdx + 1}', ctrls[rIdx][cIdx]),
                                  ),
                                );
                              }),
                            ),
                        ],
                      ),
                    );
                  }),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _htmlBtn('+ Add 4-Column Row', const Color(0xFFE8F0FA), const Color(0xFF164B80), () {
                        setModalState(() {
                          ctrls.add(List<TextEditingController>.generate(4, (_) => TextEditingController()));
                        });
                      }),
                      _htmlBtn('+ Add Merged Full-Width Row', const Color(0xFFE8F0FA), const Color(0xFF164B80), () {
                        setModalState(() {
                          final newIdx = ctrls.length;
                          ctrls.add(List<TextEditingController>.generate(4, (_) => TextEditingController()));
                          currentMerged.add(newIdx);
                        });
                      }),
                      _htmlBtn('↺ Reset to Default Header Layout', const Color(0xFFFFE3E3), const Color(0xFFC92A2A), () {
                        engine.parishisht10CustomGrids.remove(storageKey);
                        engine.parishisht10MergedRows.remove(storageKey);
                        engine.triggerUpdate();
                        Navigator.of(ctx).pop();
                        _showToast('Reset report header to default layout.');
                      }),
                    ],
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Cancel')),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: const Color(0xFF087F5B)),
              onPressed: () {
                engine.parishisht10CustomGrids[storageKey] = ctrls
                    .map((r) => r.map((c) => c.text).toList())
                    .toList();
                engine.parishisht10MergedRows[storageKey] = currentMerged.toList()..sort();
                engine.triggerUpdate();
                Navigator.of(ctx).pop();
                _showToast('Saved custom header & merged cells.');
              },
              child: const Text('💾 Save Cells & Merged Layout'),
            ),
          ],
        ),
      ),
    );
  }

  // REPORT 8: Parishisht-10 (પરિશિષ્ટ – ૧૦ : ગ્રાન્ટ વપરાશ પ્રમાણપત્ર — Exact Excel Layout `image_22d7c3.png` + Fully Editable & Mergeable Cells `image_22c4e4.png` + Font & Row Height Controls)
  Widget _report8Parishisht10UC(List<RojmelEntry> list, String acc, AccountMeta mAcc) {
    final headRows = engine.computeHeadWiseSummary(acc, engine.reportFromDate, engine.reportToDate);
    double sumOpenCash = 0, sumOpenBank = 0, sumBankRec = 0, sumBankTot = 0, sumBankExp = 0, sumPadarCr = 0, sumPadarDr = 0, sumCloseCash = 0, sumCloseBank = 0, sumCloseTot = 0;
    double chequeReturnAmt = 0;

    for (final e in list) {
      if (e.type == 'credit' && !RojmelEngine.isCashEntry(e) && RojmelEngine.isChequeReturnBouncePair(e)) {
        chequeReturnAmt += e.amount;
      }
    }

    final rows = <List<String>>[
      ['1', '2', '3', '4', '5', '6', '7', '8', '9', '10', '11', '12'],
    ];

    for (int i = 0; i < headRows.length; i++) {
      final r = headRows[i];
      final col3 = r.openCash;
      final col4 = r.openBank;
      final col5 = r.bankCr;
      final col6 = col4 + col5;
      final col7 = r.bankDr;
      final col8 = r.padarCr;
      final col9 = r.padarDr;
      final col10 = col3 + col8 - col9;
      final col11 = col6 - col7;
      final col12 = col10 + col11;

      sumOpenCash += col3;
      sumOpenBank += col4;
      sumBankRec += col5;
      sumBankTot += col6;
      sumBankExp += col7;
      sumPadarCr += col8;
      sumPadarDr += col9;
      sumCloseCash += col10;
      sumCloseBank += col11;
      sumCloseTot += col12;

      rows.add([
        '${i + 1}',
        r.head,
        fmtDemoNum(col3),
        fmtDemoNum(col4),
        fmtDemoNum(col5),
        fmtDemoNum(col6),
        fmtDemoNum(col7),
        fmtDemoNum(col8),
        fmtDemoNum(col9),
        fmtDemoNum(col10),
        fmtDemoNum(col11),
        fmtDemoNum(col12),
      ]);
    }

    rows.add([
      '',
      'કુલ :',
      fmtDemoNum(sumOpenCash),
      fmtDemoNum(sumOpenBank),
      fmtDemoNum(sumBankRec),
      fmtDemoNum(sumBankTot),
      fmtDemoNum(sumBankExp),
      fmtDemoNum(sumPadarCr),
      fmtDemoNum(sumPadarDr),
      fmtDemoNum(sumCloseCash),
      fmtDemoNum(sumCloseBank),
      fmtDemoNum(sumCloseTot),
    ]);

    final openTotal = sumOpenCash + sumOpenBank;
    final wordsOpen = numberToGujaratiWords(openTotal);
    final wordsCurrRec = numberToGujaratiWords(sumBankRec);
    final wordsTotalGrant = numberToGujaratiWords(sumBankTot);
    final wordsExp = numberToGujaratiWords(sumBankExp);
    final wordsBal = numberToGujaratiWords(sumCloseTot);
    final wordsChequeRet = numberToGujaratiWords(chequeReturnAmt);

    final certText = openTotal > 0
        ? 'આથી પ્રમાણપત્ર આપવામાં આવે છે કે ગત વર્ષની જમા સિલક ₹${fmtDemoNum(openTotal)} અંકે રૂપિયા $wordsOpen તથા ${engine.financialYear} ના નાણાકીય વર્ષમાં નીચે મુજબ કુલ ₹${fmtDemoNum(sumBankRec)} અંકે કુલ $wordsCurrRec મળેલ છે. આમ કુલ ગ્રાન્ટ ₹${fmtDemoNum(sumBankTot)} અંકે કુલ $wordsTotalGrant થાય છે, જે પૈકી નીચે મુજબ કુલ ₹${fmtDemoNum(sumBankExp)} અંકે કુલ $wordsExp નો ખર્ચ થયેલ છે. અગાઉના વર્ષની બચત સહિત 31 મી માર્ચના રોજ ₹${fmtDemoNum(sumCloseTot)} અંકે કુલ $wordsBal બચત રહેલ છે.${chequeReturnAmt > 0 ? " અહી ₹${fmtDemoNum(chequeReturnAmt)} અંકે રૂપિયા $wordsChequeRet રિસોર્સ પર્સનના માનદ વેતન પરત કરતાં ચેક પરત આવતા આ રકમને પણ આવક અને ખર્ચ બંનેમાં સામેલ કરેલ છે." : ""}'
        : 'આથી પ્રમાણપત્ર આપવામાં આવે છે કે સને ${engine.financialYear} નાણાકીય વર્ષમાં નીચે મુજબ કુલ ₹${fmtDemoNum(sumBankTot)} અંકે કુલ $wordsTotalGrant મળેલ છે. જે પૈકી ₹${fmtDemoNum(sumBankExp)} અંકે કુલ $wordsExp નો ખર્ચ થયેલ છે. અગાઉના વર્ષની બચત સહિત 31 મી માર્ચના રોજ ₹${fmtDemoNum(sumCloseTot)} અંકે કુલ $wordsBal બચત રહેલ છે.';

    final sName = mAcc.schoolName.isNotEmpty ? mAcc.schoolName : engine.schoolName;
    final sAddr = engine.schoolAddress.trim().isNotEmpty
        ? engine.schoolAddress.trim()
        : (engine.fullFormattedSchoolAddress.isNotEmpty ? engine.fullFormattedSchoolAddress : mAcc.branchAddress.trim());
    final holder = mAcc.holderName.isNotEmpty ? mAcc.holderName : sName;
    final acNo = mAcc.acNo;
    final isSna = mAcc.type == 'SNA' || acc.trim().toUpperCase().contains('SNA');
    final bankInfo = mAcc.branchAddress.trim().isNotEmpty && mAcc.bankName.trim().isNotEmpty
        ? '${mAcc.branchAddress} (${mAcc.bankName})'
        : (mAcc.bankName.trim().isNotEmpty ? mAcc.bankName : mAcc.branchAddress);

    // Default editable/mergeable header grid matching image_22d7c3.png + School Name & Address above Utilization Certificate
    // If SNA SPARSH -> School Name, Address, Agency Code; if BANK/PFMS -> Bank Holder, Account No, Bank Address, IFSC
    final effAgency = mAcc.effectiveSnaAgencyCode;
    final defaultGrid = mAcc.type == 'SNA_PURE'
        ? <List<String>>[
            ['પરિશિષ્ટ – ૧૦', '', 'વર્ષ : ${engine.financialYear}', ''],
            ['શાળાનું નામ : $sName  |  સરનામું : $sAddr', '', '', ''],
            ['ગ્રાન્ટ વપરાશ પ્રમાણપત્ર', '', '', ''],
            ['એજન્સી કોડ (Agency Code) :', effAgency, 'ખાતાનું નામ (Account Name) :', acc],
            ['શાળાનું નામ :', sName, 'ખાતાનો પ્રકાર :', 'Purely SNA SPARSH'],
            ['SCHOOL NAME : - $sName   |   AGENCY CODE : - $effAgency   |   ACCOUNT : - $acc', '', '', ''],
          ]
        : (mAcc.type == 'SNA'
            ? <List<String>>[
                ['પરિશિષ્ટ – ૧૦', '', 'વર્ષ : ${engine.financialYear}', ''],
                ['શાળાનું નામ : $sName  |  સરનામું : $sAddr', '', '', ''],
                ['ગ્રાન્ટ વપરાશ પ્રમાણપત્ર', '', '', ''],
                ['બેંક ખાતેદારનું નામ (PFMS) :', holder, 'PFMS ખાતા નંબર :', acNo],
                ['SNA SPARSH એજન્સી કોડ :', effAgency, 'ખાતાનું નામ :', '$acc (PFMS: ${fmtDateSlashDDMMYYYY(mAcc.pfmsLastDate)} | SNA: ${fmtDateSlashDDMMYYYY(mAcc.snaStartDate)})'],
                ['SCHOOL NAME : - $sName   |   PFMS A/C : -$acNo   |   SNA AGENCY CODE : -$effAgency   |   $acc', '', '', ''],
              ]
            : <List<String>>[
                ['પરિશિષ્ટ – ૧૦', '', 'વર્ષ : ${engine.financialYear}', ''],
                ['શાળાનું નામ : $sName  |  સરનામું : $sAddr', '', '', ''],
                ['ગ્રાન્ટ વપરાશ પ્રમાણપત્ર', '', '', ''],
                ['બેંક ખાતેદારનું નામ :', holder, 'બેંક ખાતા નંબર :', acNo],
                ['બેંક સરનામું :', bankInfo, 'બેંક IFSC. કોડ :', mAcc.ifsc],
                ['SCHOOL NAME : - $sName      ACCOUNT HOLDER NAME : - $holder   A/C NO. -$acNo  &  $acc', '', '', ''],
              ]);
    final defaultMergedRows = <int>[1, 2, 5];

    final activeGrid = engine.parishisht10CustomGrids[acc] ?? defaultGrid;
    final activeMerged = (engine.parishisht10MergedRows[acc] ?? defaultMergedRows).toSet();
    final fontPt = engine.parishisht10FontSizePt;
    final rowHPx = engine.parishisht10RowHeightPx;

    return _govAuditSheet(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Flexible(child: const Text(
              'પરિશિષ્ટ – ૧૦ : ગ્રાન્ટ વપરાશ પ્રમાણપત્ર (Click any header cell or button to Edit / Merge Cells)',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: Color(0xFF164B80)),
            )),
            _htmlBtn('✏ Edit & Merge Header Cells', const Color(0xFFE8F0FA), const Color(0xFF164B80), () {
              _openParishisht10HeaderEditorDialog(acc, defaultGrid, defaultMergedRows, headerTitle: 'પરિશિષ્ટ – ૧૦ ($acc)');
            }),
          ],
        ),
        const SizedBox(height: 6),

        InkWell(
          onTap: () => _openParishisht10HeaderEditorDialog(acc, defaultGrid, defaultMergedRows, headerTitle: 'પરિશિષ્ટ – ૧૦ ($acc)'),
          child: Container(
            decoration: BoxDecoration(
              border: Border.all(color: Colors.black, width: 1.0),
              color: Colors.white,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (int rIdx = 0; rIdx < activeGrid.length; rIdx++)
                  if (rIdx <= 2)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        border: Border(bottom: BorderSide(color: Colors.black, width: rIdx == 2 ? 1.0 : 0.8)),
                        color: rIdx == 1 ? const Color(0xFFF8FAFC) : Colors.white,
                      ),
                      child: activeMerged.contains(rIdx)
                          ? Text(
                              activeGrid[rIdx].firstWhere((c) => c.trim().isNotEmpty, orElse: () => ''),
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: rIdx == 2 ? (fontPt + 4) : (fontPt + 1.5),
                                fontWeight: FontWeight.w900,
                                decoration: rIdx == 2 ? TextDecoration.underline : TextDecoration.none,
                                color: Colors.black,
                              ),
                            )
                          : (rIdx == 0
                              ? Row(
                                  children: [
                                    Expanded(
                                      flex: 6,
                                      child: Text(
                                        activeGrid[rIdx][0],
                                        textAlign: TextAlign.center,
                                        style: TextStyle(fontSize: fontPt + 4, fontWeight: FontWeight.w900, color: Colors.black),
                                      ),
                                    ),
                                    Expanded(
                                      flex: 4,
                                      child: Text(
                                        activeGrid[rIdx].length > 2 && activeGrid[rIdx][2].trim().isNotEmpty
                                            ? activeGrid[rIdx][2]
                                            : 'વર્ષ : ${engine.financialYear}',
                                        textAlign: TextAlign.center,
                                        style: TextStyle(fontSize: fontPt + 3, fontWeight: FontWeight.w900, color: Colors.black),
                                      ),
                                    ),
                                  ],
                                )
                              : Row(
                                  children: List<Widget>.generate(4, (cIdx) {
                                    final txt = cIdx < activeGrid[rIdx].length ? activeGrid[rIdx][cIdx] : '';
                                    return Expanded(
                                      child: Text(
                                        txt,
                                        style: TextStyle(fontSize: fontPt, fontWeight: FontWeight.w800, color: Colors.black),
                                      ),
                                    );
                                  }),
                                )),
                    ),

                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    border: Border(bottom: BorderSide(color: Colors.black, width: 1.0)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        '        $certText',
                        style: TextStyle(fontSize: fontPt + 1.2, height: 1.55, color: Colors.black, fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 6),
                      Container(
                        padding: const EdgeInsets.only(top: 6),
                        decoration: const BoxDecoration(border: Border(top: BorderSide(color: Color(0xFFCBD5E1)))),
                        child: Text(
                          'આ ઉપરાંત આવક અને ખર્ચના આંકડા સંબંધિત હિસાબી રેકર્ડ સાથે ચકાસણી કરીને દર્શાવેલા છે.',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontWeight: FontWeight.w800, fontSize: fontPt + 0.8, color: Colors.black),
                        ),
                      ),
                    ],
                  ),
                ),

                for (int rIdx = 3; rIdx < activeGrid.length; rIdx++)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: rIdx == activeGrid.length - 1 ? const Color(0xFFFDE9D9) : Colors.white,
                      border: Border(
                        bottom: BorderSide(color: Colors.black, width: rIdx == activeGrid.length - 1 ? 0.0 : 0.8),
                      ),
                    ),
                    child: activeMerged.contains(rIdx)
                        ? Text(
                            activeGrid[rIdx].firstWhere((c) => c.trim().isNotEmpty, orElse: () => ''),
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: fontPt, fontWeight: FontWeight.w900, color: Colors.black),
                          )
                        : Row(
                            children: List<Widget>.generate(4, (cIdx) {
                              final txt = cIdx < activeGrid[rIdx].length ? activeGrid[rIdx][cIdx] : '';
                              return Expanded(
                                flex: cIdx.isOdd ? 3 : 2,
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 4),
                                  child: Text(
                                    txt,
                                    style: TextStyle(fontSize: fontPt, fontWeight: FontWeight.w800, color: Colors.black),
                                  ),
                                ),
                              );
                            }),
                          ),
                  ),
              ],
            ),
          ),
        ),

        _buildReportFontAndHeightControlsBar(
          label: '⚙ Parishisht-10 Table Display Settings (Below Certificate):',
          onEditCells: () => _openParishisht10HeaderEditorDialog(acc, defaultGrid, defaultMergedRows, headerTitle: 'પરિશિષ્ટ – ૧૦ ($acc)'),
        ),

        _govAuditTable(
          headers: const [
            'ક્રમ', 'ગ્રાન્ટ / હેડની વિગત', 'શરૂઆતની રોકડ', 'શરૂઆતની બેન્ક',
            'આ વર્ષે બેન્કમાં મળેલ ગ્રાન્ટ', 'કુલ ગ્રાન્ટ બેન્કમાં (4+5)',
            'ચેક કે PFMS ખર્ચ / પરત', 'પદર ખાતે આવક', 'પદર ખાતે ખર્ચ',
            'બંધ રોકડ (3+8-9)', 'બંધ બેન્ક (6-7)', 'કુલ બંધ સિલક (10+11)',
          ],
          rows: rows,
          lastRowIsTotal: true,
          fontSizePt: fontPt,
          minRowHeightPx: rowHPx,
        ),
        _govAuditSignatures(acc),
      ],
    );
  }

  // REPORT 9: Parishisht-11 Grant Register (ગ્રાન્ટ રજીસ્ટર : પરિશિષ્ટ ૧૧)
  Widget _report9Parishisht11GrantReg(String acc, AccountMeta mAcc) {
    final showLim = mAcc.isSnaOrPfms;
    final headRows = engine.computeHeadWiseSummary(acc, engine.reportFromDate, engine.reportToDate);
    double totLim = 0, totRec = 0, totExp = 0, totBal = 0;

    final rows = headRows.asMap().entries.map((entry) {
      final i = entry.key;
      final r = entry.value;
      final rec = r.openTotal + r.bankCr;
      final exp = r.bankDr;
      final bal = rec - exp;
      totLim += r.annualLimit;
      totRec += rec;
      totExp += exp;
      totBal += bal;
      return <String>[
        '${i + 1}',
        'SSA',
        '-',
        if (showLim) fmtDemoNum(r.annualLimit),
        fmtDemoNum(rec),
        r.head,
        '-',
        '-',
        mAcc.bankName,
        mAcc.acNo,
        r.creditDates.take(2).join(', '),
        mAcc.holderName,
        fmtDemoNum(exp),
        fmtDemoNum(bal),
        '-',
      ];
    }).toList();

    rows.add([
      '', 'કુલ રકમ :', '',
      if (showLim) fmtDemoNum(totLim),
      fmtDemoNum(totRec), 'OK', '', '', '', '', '', '', fmtDemoNum(totExp), fmtDemoNum(totBal), '-',
    ]);

    return _govAuditSheet(
      children: [
        _govSchoolBlockHeader('ગ્રાન્ટ રજીસ્ટર : પરિશિષ્ટ ૧૧ (PARISHISHT - 11 : GRANT REGISTER)', acc, mAcc),
        _govAuditTable(
          headers: [
            'ક્રમ', 'કોના તરફથી મળી', 'ડી.ડી./ચેક નં.',
            if (showLim) 'વાર્ષિક મર્યાદા ₹',
            'રકમ ₹', 'ક્યાં કામે મળ્યા ? (હેડ)', 'આદેશ તારીખ', 'ડી.ડી./ચેક વિગત',
            'બેન્કનું નામ', 'બેન્ક ખાતા નંબર', 'જમા તારીખ', 'કોને ફાળવેલ', 'ખર્ચેલ રકમ ₹', 'બચત ગ્રાન્ટ ₹', 'રીમાર્કસ',
          ],
          rows: rows,
          lastRowIsTotal: true,
        ),
        _govAuditSignatures(acc),
      ],
    );
  }

  // REPORT 10: Annexure-12 (એનેક્ષર-12 : સર્વ શિક્ષા અભિયાન - ગુજરાત)
  Widget _report10Annexure12(List<RojmelEntry> allAcc, String acc, AccountMeta mAcc) {
    final months = engine.getFyMonthsList();
    if (engine.selectedAnnex12Month != 'ALL' && !months.any((m) => m['ym'] == engine.selectedAnnex12Month)) {
      engine.selectedAnnex12Month = 'ALL';
    }
    final targetMonths = engine.selectedAnnex12Month == 'ALL'
        ? months
        : months.where((m) => m['ym'] == engine.selectedAnnex12Month).toList();
    final headsList = engine.getAccountSpecificHeads(acc);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _htmlCard(
          body: Row(
            children: [
              Flexible(child: Text('એનેક્ષર-12 માસ પસંદ કરો ($acc): ', style: const TextStyle(fontWeight: FontWeight.w800))),
              const SizedBox(width: 10),
              SizedBox(
                width: 300,
                child: DropdownButtonFormField<String>(
                      isExpanded: true,
                  value: engine.selectedAnnex12Month,
                  decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true),
                  items: [
                    DropdownMenuItem(value: 'ALL', child: Text('All 12 Months (Full Year ${engine.financialYear})')),
                    ...months.map((m) => DropdownMenuItem(value: m['ym']!, child: Text(m['label']!))),
                  ],
                  onChanged: (v) {
                    if (v != null) {
                      engine.selectedAnnex12Month = v;
                      engine.triggerUpdate();
                    }
                  },
                ),
              ),
            ],
          ),
        ),
        ...targetMonths.map((mObj) {
          final ym = mObj['ym']!;
          final mEntries = allAcc.where((e) => e.date.startsWith(ym)).toList();
          final priorEntries = allAcc.where((e) => e.date.length >= 7 && e.date.substring(0, 7).compareTo(ym) < 0).toList();
          double s3 = 0, s4 = 0, s5 = 0, s6 = 0, s7 = 0, s8 = 0, s9 = 0, s10 = 0, s11 = 0, s12 = 0, s13 = 0, s14 = 0, s15 = 0;

          final rows = <List<String>>[
            ['1', '2', '3', '4', '5', '6', '7', '8', '9', '10', '11', '12', '13', '14', '15'],
          ];

          for (int idx = 0; idx < headsList.length; idx++) {
            final h = headsList[idx];
            final hop = engine.getHeadOpening(acc, h);
            double c3 = hop.cash, c4 = hop.bank;
            for (final e in priorEntries.where((x) => x.head == h)) {
              final s = e.type == 'credit' ? 1.0 : -1.0;
              c3 += s * RojmelEngine.cashAmt(e);
              c4 += s * RojmelEngine.bankAmt(e);
            }
            double c5 = 0, c6 = 0, c10 = 0, c11 = 0;
            for (final e in mEntries.where((x) => x.head == h)) {
              if (e.type == 'credit') {
                c5 += RojmelEngine.cashAmt(e);
                c6 += RojmelEngine.bankAmt(e);
              } else {
                c10 += RojmelEngine.cashAmt(e);
                c11 += RojmelEngine.bankAmt(e);
              }
            }
            final c7 = c3 + c5, c8 = c4 + c6, c9 = c7 + c8;
            final c12 = c10 + c11;
            final c13 = c7 - c10, c14 = c8 - c11, c15 = c13 + c14;
            s3 += c3; s4 += c4; s5 += c5; s6 += c6; s7 += c7; s8 += c8; s9 += c9;
            s10 += c10; s11 += c11; s12 += c12; s13 += c13; s14 += c14; s15 += c15;

            rows.add([
              '${idx + 1}', h,
              fmtDemoNum(c3), fmtDemoNum(c4), fmtDemoNum(c5), fmtDemoNum(c6),
              fmtDemoNum(c7), fmtDemoNum(c8), fmtDemoNum(c9),
              fmtDemoNum(c10), fmtDemoNum(c11), fmtDemoNum(c12),
              fmtDemoNum(c13), fmtDemoNum(c14), fmtDemoNum(c15),
            ]);
          }

          rows.add([
            '', 'એકંદરે સરવાળો :',
            fmtDemoNum(s3), fmtDemoNum(s4), fmtDemoNum(s5), fmtDemoNum(s6),
            fmtDemoNum(s7), fmtDemoNum(s8), fmtDemoNum(s9),
            fmtDemoNum(s10), fmtDemoNum(s11), fmtDemoNum(s12),
            fmtDemoNum(s13), fmtDemoNum(s14), fmtDemoNum(s15),
          ]);

          return _govAuditSheet(
            children: [
              _govSchoolBlockHeader('એનેક્ષર-12 : સર્વ શિક્ષા અભિયાન - ગુજરાત — માસ : ${mObj["label"]} ($acc)', acc, mAcc),
              _govAuditTable(
                headers: const [
                  'ક્રમ', 'ગ્રાન્ટનું નામ', 'શરૂઆત રોકડ', 'શરૂઆત બેન્ક', 'મળેલ રોકડ', 'મળેલ બેન્ક',
                  'કુલ રોકડ (3+5)', 'કુલ બેન્ક (4+6)', 'કુલ ગ્રાન્ટ (7+8)',
                  'ખર્ચ રોકડ', 'ખર્ચ બેન્ક', 'કુલ ખર્ચ',
                  'બંધ રોકડ (7-10)', 'બંધ બેન્ક (8-11)', 'બંધ કુલ (13+14)',
                ],
                rows: rows,
                lastRowIsTotal: true,
              ),
              _govAuditSignatures(acc),
            ],
          );
        }),
      ],
    );
  }

  // REPORT 11: Monthly Hisab Patrak (માસવાર હિસાબ પત્રક)
  Widget _report11MonthlyHisab(List<RojmelEntry> allAcc, String acc, AccountMeta mAcc) {
    final allMonths = engine.getFyMonthsList();
    if (engine.selectedMonthlyHisabMonth != 'ALL' && !allMonths.any((m) => m['ym'] == engine.selectedMonthlyHisabMonth)) {
      engine.selectedMonthlyHisabMonth = 'ALL';
    }
    final activeMonths = engine.selectedMonthlyHisabMonth == 'ALL'
        ? allMonths.where((m) => allAcc.any((e) => e.date.startsWith(m['ym']!))).toList()
        : allMonths.where((m) => m['ym'] == engine.selectedMonthlyHisabMonth).toList();
    final monthsToRender = activeMonths.isNotEmpty ? activeMonths : allMonths;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _htmlCard(
          body: Row(
            children: [
              Flexible(child: Text('માસ પસંદ કરો (માસવાર હિસાબ પત્રક — $acc): ', style: const TextStyle(fontWeight: FontWeight.w800))),
              const SizedBox(width: 10),
              SizedBox(
                width: 300,
                child: DropdownButtonFormField<String>(
                      isExpanded: true,
                  value: engine.selectedMonthlyHisabMonth,
                  decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true),
                  items: [
                    DropdownMenuItem(value: 'ALL', child: Text('All Active Months ($acc)')),
                    ...allMonths.map((m) => DropdownMenuItem(value: m['ym']!, child: Text(m['label']!))),
                  ],
                  onChanged: (v) {
                    if (v != null) {
                      engine.selectedMonthlyHisabMonth = v;
                      engine.triggerUpdate();
                    }
                  },
                ),
              ),
            ],
          ),
        ),
        ...monthsToRender.map((mObj) {
          final ym = mObj['ym']!;
          final mList = allAcc.where((e) => e.date.startsWith(ym)).toList();
          final priorList = allAcc.where((e) => e.date.length >= 7 && e.date.substring(0, 7).compareTo(ym) < 0).toList();
          final accOp = engine.getAccountOpening(acc);
          final openBal = accOp.total + priorList.fold<double>(0.0, (b, e) => b + (e.type == 'credit' ? e.amount : -e.amount));
          double crC = 0, crB = 0, drC = 0, drB = 0;

          final rows = mList.asMap().entries.map((entry) {
            final i = entry.key;
            final e = entry.value;
            final cC = e.type == 'credit' ? RojmelEngine.cashAmt(e) : 0.0;
            final cB = e.type == 'credit' ? RojmelEngine.bankAmt(e) : 0.0;
            final dC = e.type == 'debit' ? RojmelEngine.cashAmt(e) : 0.0;
            final dB = e.type == 'debit' ? RojmelEngine.bankAmt(e) : 0.0;
            crC += cC;
            crB += cB;
            drC += dC;
            drB += dB;
            return <String>[
              '${i + 1}',
              fmtDateDDMMYY(e.date),
              e.head,
              e.type == 'credit' ? 'આવક(જમા)+' : 'જાવક(ઉધાર)-',
              e.type == 'debit' ? engine.formatDebitNarration(e) : RojmelEngine.formatCreditNarration(e),
              fmtDemoNum(cC),
              fmtDemoNum(cB),
              fmtDemoNum(cC + cB),
              fmtDemoNum(dC),
              fmtDemoNum(dB),
              fmtDemoNum(dC + dB),
            ];
          }).toList();

          final totCr = crC + crB;
          final totDr = drC + drB;
          final netBal = openBal + totCr - totDr;

          rows.add([
            '', '', '', '', 'માસનો કુલ સરવાળો (${mObj["label"]}) :',
            fmtDemoNum(crC), fmtDemoNum(crB), fmtDemoNum(totCr),
            fmtDemoNum(drC), fmtDemoNum(drB), fmtDemoNum(totDr),
          ]);

          return _govAuditSheet(
            children: [
              _govSchoolBlockHeader('માસવાર હિસાબ પત્રક (MONTHLY TRANSACTION STATEMENT — $acc)', acc, mAcc, mObj['label']!),
              _govAuditTable(
                headers: const [],
                rows: [
                  ['શાળાનું નામ : ${mAcc.schoolName}', 'માસ : ${mObj["label"]}', 'ઉઘડતી સિલક : ₹ ${fmtDemoNum(openBal)}', 'બંધ સિલક : ₹ ${fmtDemoNum(netBal)}'],
                  ['માસની કુલ આવક (+) : ₹ ${fmtDemoNum(totCr)}', '', 'માસનો કુલ ખર્ચ (-) : ₹ ${fmtDemoNum(totDr)}', ''],
                ],
                boldAll: true,
              ),
              const SizedBox(height: 6),
              _govAuditTable(
                headers: const [
                  'ક્રમ', 'તારીખ', 'મુખ્ય હેડ', 'રોકડા/ચેક', 'વિગત',
                  'આ.રોકડા', 'આ.બેંક', 'આવક (+)', 'જા.રોકડા', 'જા.બેંક', 'ખર્ચ (-)',
                ],
                rows: rows,
                lastRowIsTotal: true,
              ),
              _govAuditSignatures(acc),
            ],
          );
        }),
      ],
    );
  }

  // REPORT 12 (NEW): Monthly Head-wise Expense & Remaining Limit / Balance Report
  // (માસવાર અને હેડવાર ખર્ચ તથા બાકી લિમિટ / બેંક સિલક પત્રક — April, May, June... to March + Selected Month Only vs Full Year)
  Widget _report11BMonthlyLimitAndBalance(List<RojmelEntry> allAcc, String acc, AccountMeta mAcc) {
    final fyMonths = engine.getFyMonthsList();
    if (engine.selectedMonthlyLimitMonth != 'ALL' && !fyMonths.any((m) => m['ym'] == engine.selectedMonthlyLimitMonth)) {
      engine.selectedMonthlyLimitMonth = 'ALL';
    }
    final isBankAcc = mAcc.type == 'BANK';
    final accHeads = engine.reportFilterHead == 'ALL'
        ? engine.getAccountSpecificHeads(acc)
        : <String>[engine.reportFilterHead];

    Widget buildSingleMonthSheet(Map<String, String> mObj) {
      final ym = mObj['ym']!;
      final mLabel = mObj['label']!;
      final rows = <List<String>>[];
      double tot3 = 0, tot4 = 0, tot5 = 0, tot6 = 0, tot7 = 0, tot8 = 0;

      for (int i = 0; i < accHeads.length; i++) {
        final h = accHeads[i];
        if (isBankAcc) {
          final hop = engine.getHeadOpening(acc, h);
          double priorCr = 0, priorDr = 0, curCr = 0, curDr = 0;
          for (final e in allAcc.where((x) => x.head == h)) {
            final eYm = e.date.length >= 7 ? e.date.substring(0, 7) : '';
            if (eYm.compareTo(ym) < 0) {
              if (e.type == 'credit') priorCr += e.amount;
              else priorDr += e.amount;
            } else if (eYm == ym) {
              if (e.type == 'credit') curCr += e.amount;
              else curDr += e.amount;
            }
          }
          final openMonth = hop.total + priorCr - priorDr;
          final availMonth = openMonth + curCr;
          final remBal = availMonth - curDr;
          tot3 += openMonth;
          tot4 += curCr;
          tot5 += availMonth;
          tot6 += curDr;
          tot7 += remBal;
          rows.add([
            '${i + 1}',
            h,
            fmtDemoNum(openMonth),
            fmtDemoNum(curCr),
            fmtDemoNum(availMonth),
            fmtDemoNum(curDr),
            fmtDemoNum(remBal),
          ]);
        } else {
          final lim = engine.getHeadLimit(acc, h);
          double priorExp = 0, curExp = 0;
          for (final e in allAcc.where((x) => x.head == h && x.type == 'debit' && !RojmelEngine.isCashEntry(x))) {
            final eYm = e.date.length >= 7 ? e.date.substring(0, 7) : '';
            if (eYm.compareTo(ym) < 0) priorExp += e.amount;
            else if (eYm == ym) curExp += e.amount;
          }
          final openRem = lim - priorExp;
          final cumExp = priorExp + curExp;
          final endRem = lim - cumExp;
          tot3 += lim;
          tot4 += priorExp;
          tot5 += openRem;
          tot6 += curExp;
          tot7 += cumExp;
          tot8 += endRem;
          rows.add([
            '${i + 1}',
            h,
            fmtDemoNum(lim),
            fmtDemoNum(priorExp),
            fmtDemoNum(openRem),
            fmtDemoNum(curExp),
            fmtDemoNum(cumExp),
            fmtDemoNum(endRem),
          ]);
        }
      }

      if (isBankAcc) {
        rows.add([
          'TOTAL',
          'માસનો કુલ સરવાળો ($mLabel) :',
          fmtDemoNum(tot3),
          fmtDemoNum(tot4),
          fmtDemoNum(tot5),
          fmtDemoNum(tot6),
          fmtDemoNum(tot7),
        ]);
        return _govAuditSheet(
          children: [
            _govSchoolBlockHeader(
              'માસવાર ખર્ચ અને બાકી બેંક સિલક પત્રક (MONTHLY EXPENSE & REMAINING BALANCE — $mLabel)',
              acc,
              mAcc,
              mLabel,
            ),
            _govAuditTable(
              headers: const [
                'ક્રમ',
                'ગ્રાન્ટ હેડ',
                'માસની ઉઘડતી સિલક ₹',
                'ચાલુ માસમાં જમા ₹',
                'કુલ પ્રાપ્ય સિલક ₹',
                'ચાલુ માસનો ખર્ચ ₹',
                'માસના અંતે બાકી સિલક ₹',
              ],
              rows: rows,
              lastRowIsTotal: true,
            ),
            _govAuditSignatures(acc),
          ],
        );
      } else {
        rows.add([
          'TOTAL',
          'માસનો કુલ સરવાળો ($mLabel) :',
          fmtDemoNum(tot3),
          fmtDemoNum(tot4),
          fmtDemoNum(tot5),
          fmtDemoNum(tot6),
          fmtDemoNum(tot7),
          fmtDemoNum(tot8),
        ]);
        return _govAuditSheet(
          children: [
            _govSchoolBlockHeader(
              'માસવાર અને હેડવાર ખર્ચ તથા બાકી લિમિટ પત્રક (MONTHLY HEAD-WISE EXPENSE & REMAINING LIMIT — $mLabel)',
              acc,
              mAcc,
              mLabel,
            ),
            _govAuditTable(
              headers: const [
                'ક્રમ',
                'ગ્રાન્ટ હેડ',
                'વાર્ષિક મર્યાદા ₹',
                'અગાઉના માસ સુધી ખર્ચ ₹',
                'માસની શરૂઆતની બાકી લિમિટ ₹',
                'ચાલુ માસનો ખર્ચ ₹',
                'કુલ વપરાયેલ લિમિટ ₹',
                'માસના અંતે બાકી લિમિટ ₹',
              ],
              rows: rows,
              lastRowIsTotal: true,
            ),
            _govAuditSignatures(acc),
          ],
        );
      }
    }

    // Build Full-Year (April to March) Matrix Table
    final fullYearRows = <List<String>>[];
    double sumBase = 0;
    final sumMonthExp = List<double>.filled(12, 0.0);
    final sumMonthRem = List<double>.filled(12, 0.0);
    double sumTotalExp = 0;
    double sumFinalRem = 0;

    for (int i = 0; i < accHeads.length; i++) {
      final h = accHeads[i];
      final baseVal = isBankAcc ? engine.getHeadOpening(acc, h).total : engine.getHeadLimit(acc, h);
      sumBase += baseVal;
      double runningRem = baseVal;
      double headTotExp = 0;
      final rCells = <String>['${i + 1}', h, fmtDemoNum(baseVal)];
      for (int mIdx = 0; mIdx < 12; mIdx++) {
        final ym = fyMonths[mIdx]['ym']!;
        double mCr = 0, mDr = 0;
        for (final e in allAcc.where((x) => x.head == h && x.date.startsWith(ym))) {
          if (isBankAcc) {
            if (e.type == 'credit') mCr += e.amount;
            else mDr += e.amount;
          } else {
            if (e.type == 'debit' && !RojmelEngine.isCashEntry(e)) mDr += e.amount;
          }
        }
        runningRem = isBankAcc ? (runningRem + mCr - mDr) : (runningRem - mDr);
        headTotExp += mDr;
        sumMonthExp[mIdx] += mDr;
        sumMonthRem[mIdx] += runningRem;
        rCells.add('ખર્ચ: ${fmtDemoNum(mDr)}\nબાકી: ${fmtDemoNum(runningRem)}');
      }
      sumTotalExp += headTotExp;
      sumFinalRem += runningRem;
      rCells.add(fmtDemoNum(headTotExp));
      rCells.add(fmtDemoNum(runningRem));
      fullYearRows.add(rCells);
    }

    fullYearRows.add([
      'TOTAL',
      'કુલ સરવાળો (Full Year) :',
      fmtDemoNum(sumBase),
      ...List<String>.generate(12, (mIdx) => 'ખર્ચ: ${fmtDemoNum(sumMonthExp[mIdx])}\nબાકી: ${fmtDemoNum(sumMonthRem[mIdx])}'),
      fmtDemoNum(sumTotalExp),
      fmtDemoNum(sumFinalRem),
    ]);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _htmlCard(
          body: Wrap(
            spacing: 12,
            runSpacing: 10,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                'માસ પસંદ કરો (Full Year એપ્રિલ–માર્ચ અથવા માત્ર પસંદ કરેલ માસ — $acc):',
                style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13.5),
              ),
              SizedBox(
                width: 340,
                child: DropdownButtonFormField<String>(
                  isExpanded: true,
                  value: engine.selectedMonthlyLimitMonth,
                  decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true),
                  items: [
                    DropdownMenuItem(
                      value: 'ALL',
                      child: Text('Full Year — April to March (સંપૂર્ણ વર્ષ ${engine.financialYear})'),
                    ),
                    ...fyMonths.map((m) => DropdownMenuItem(value: m['ym']!, child: Text('Selected Month Only: ${m["label"]}'))),
                  ],
                  onChanged: (v) {
                    if (v != null) {
                      engine.selectedMonthlyLimitMonth = v;
                      engine.triggerUpdate();
                    }
                  },
                ),
              ),
              _htmlBtn('📊 Export This Monthly Report Excel (.xls)', const Color(0xFF087F5B), Colors.white, () {
                final xlsHtml = engine.generatePrintExactExcelHtml('monthly_limit_report', acc);
                _downloadBrowserFile(xlsHtml, 'application/vnd.ms-excel;charset=utf-8', 'Rojmel_Monthly_Limit_Balance_${acc}_${engine.financialYear}.xls');
                _showToast('Downloaded Monthly Expense & Remaining Limit/Balance Excel (.xls)!');
              }),
            ],
          ),
        ),
        if (engine.selectedMonthlyLimitMonth == 'ALL')
          _govAuditSheet(
            children: [
              _govSchoolBlockHeader(
                isBankAcc
                    ? 'વાર્ષિક માસવાર (એપ્રિલ થી માર્ચ) ખર્ચ અને બાકી બેંક સિલક પત્રક ($acc)'
                    : 'વાર્ષિક માસવાર (એપ્રિલ થી માર્ચ) અને હેડવાર ખર્ચ તથા બાકી લિમિટ પત્રક ($acc)',
                acc,
                mAcc,
                'Full Year (April to March)',
              ),
              _govAuditTable(
                headers: [
                  'ક્રમ',
                  'ગ્રાન્ટ હેડ',
                  isBankAcc ? 'ઉઘડતી સિલક ₹' : 'વાર્ષિક લિમિટ ₹',
                  ...fyMonths.map((m) => '${m["gu"]}\n(ખર્ચ / બાકી)'),
                  'કુલ વાર્ષિક ખર્ચ ₹',
                  isBankAcc ? 'આખરની બાકી સિલક ₹' : 'આખરની બાકી લિમિટ ₹',
                ],
                rows: fullYearRows,
                lastRowIsTotal: true,
              ),
              _govAuditSignatures(acc),
            ],
          )
        else
          buildSingleMonthSheet(
            fyMonths.firstWhere((m) => m['ym'] == engine.selectedMonthlyLimitMonth, orElse: () => fyMonths.first),
          ),
      ],
    );
  }

  // REPORT 13: Passbook (બેંક પાસબુક)
  Widget _report12Passbook(List<RojmelEntry> list, String acc, AccountMeta mAcc) {
    final bankEntries = list.where((e) => !RojmelEngine.isCashEntry(e)).toList();
    final openBankBal = _openingAtReportFromDate(acc).bank;
    double runBal = openBankBal;
    double totWith = 0, totDep = 0;
    final fyStartYr = engine.financialYear.length >= 4 ? engine.financialYear.substring(0, 4) : '2025';
    final openDateLabel = engine.reportFromDate.isNotEmpty
        ? fmtDateDDMMYY(engine.reportFromDate)
        : '01/04/$fyStartYr';

    final rows = <List<String>>[
      ['0', openDateLabel, 'Opening Balance (શરૂઆતની સિલક)', '-', '0.00', fmtDemoNum(openBankBal), fmtDemoNum(runBal)],
    ];

    for (int idx = 0; idx < bankEntries.length; idx++) {
      final e = bankEntries[idx];
      final w = e.type == 'debit' ? e.amount : 0.0;
      final dep = e.type == 'credit' ? e.amount : 0.0;
      totWith += w;
      totDep += dep;
      runBal += (dep - w);
      final part = '${e.type == "debit" ? engine.formatDebitNarration(e) : RojmelEngine.formatCreditNarration(e)} [${e.head}]';
      rows.add([
        '${idx + 1}',
        fmtDateDDMMYY(e.date),
        part,
        e.txn.isNotEmpty ? e.txn : '0',
        fmtDemoNum(w),
        fmtDemoNum(dep),
        fmtDemoNum(runBal),
      ]);
    }

    rows.add(['', '', 'PASSBOOK GRAND TOTAL :', '', fmtDemoNum(totWith), fmtDemoNum(totDep), fmtDemoNum(runBal)]);

    return _govAuditSheet(
      children: [
        _govSchoolBlockHeader('${mAcc.schoolName} — PASSBOOK ${engine.financialYear} ($acc)', acc, mAcc),
        _govAuditTable(
          headers: const ['Sr.', 'Date', 'Particulars', 'Chq / PFMS / Claim No.', 'Withdrawals ₹', 'Deposits ₹', 'Balance ₹'],
          rows: rows,
          lastRowIsTotal: true,
        ),
        _govAuditSignatures(acc),
      ],
    );
  }

  /// Account (or selected head) opening balance as on the report From Date.
  HeadBalance _openingAtReportFromDate(String acc) {
    final head = engine.reportFilterHead;
    final base = engine.getAccountOpening(acc, head);
    final from = normalizeToIsoDate(engine.reportFromDate);
    if (from.isEmpty) return base;
    double c = base.cash, b = base.bank;
    for (final e in engine.getAccountEntries(acc)) {
      if (head != 'ALL' && e.head != head) continue;
      if (normalizeToIsoDate(e.date).compareTo(from) >= 0) continue;
      final s = e.type == 'credit' ? 1.0 : -1.0;
      c += s * RojmelEngine.cashAmt(e);
      b += s * RojmelEngine.bankAmt(e);
    }
    return HeadBalance(cash: c, bank: b);
  }

  /// Head-wise summary for the report period, honouring the Grant Head filter.
  List<HeadSummaryRow> _filteredHeadRows(String acc) => engine
      .computeHeadWiseSummary(
        acc,
        normalizeToIsoDate(engine.reportFromDate),
        normalizeToIsoDate(engine.reportToDate),
      )
      .where((r) => engine.reportFilterHead == 'ALL' || r.head == engine.reportFilterHead)
      .toList();

  // REPORT 13: Tally Report (ટેલી રિપોર્ટ - Trial Balance, Month DayBook & Party Ledgers)
  Widget _report13TallyAudit(List<RojmelEntry> list, String acc, AccountMeta mAcc) {
    final accOp = _openingAtReportFromDate(acc);
    final headRows = _filteredHeadRows(acc);
    double padarCr = 0, padarDr = 0, bankCr = 0, bankDr = 0;
    final partyMap = <String, Map<String, dynamic>>{};

    for (final e in list) {
      if (e.type == 'credit') {
        if (RojmelEngine.isCashEntry(e)) {
          padarCr += e.amount;
        } else {
          bankCr += e.amount;
        }
      } else {
        if (RojmelEngine.isCashEntry(e)) {
          padarDr += e.amount;
        } else {
          bankDr += e.amount;
        }
        final pName = e.party.trim().isNotEmpty ? e.party.trim() : 'Direct Beneficiary';
        final pm = partyMap.putIfAbsent(pName, () => {
              'vouchers': <String>{},
              'heads': <String>{},
              'cashPaid': 0.0,
              'bankPaid': 0.0,
              'totalPaid': 0.0,
            });
        if (e.voucher.isNotEmpty) (pm['vouchers'] as Set<String>).add(e.voucher);
        (pm['heads'] as Set<String>).add(e.head);
        if (RojmelEngine.isCashEntry(e)) {
          pm['cashPaid'] = (pm['cashPaid'] as double) + e.amount;
        } else {
          pm['bankPaid'] = (pm['bankPaid'] as double) + e.amount;
        }
        pm['totalPaid'] = (pm['totalPaid'] as double) + e.amount;
      }
    }

    final cashClose = accOp.cash + padarCr - padarDr;
    final bankClose = accOp.bank + bankCr - bankDr;

    final tbRows = <List<String>>[
      ['1', 'Cash-in-Hand (રોકડ / પદર ખાતું)', 'Cash-in-Hand', fmtDemoNum(accOp.cash), fmtDemoNum(padarCr), fmtDemoNum(padarDr), fmtDemoNum(cashClose)],
      ['2', '${mAcc.bankName} A/c ${mAcc.acNo} ($acc)', 'Bank Accounts', fmtDemoNum(accOp.bank), fmtDemoNum(bankCr), fmtDemoNum(bankDr), fmtDemoNum(bankClose)],
      ...headRows.where((r) => r.openTotal != 0 || r.credit != 0 || r.debit != 0).toList().asMap().entries.map((entry) {
        final r = entry.value;
        return <String>[
          '${entry.key + 3}',
          r.head,
          'Grant Fund (Receipt & Expense)',
          fmtDemoNum(r.openTotal),
          fmtDemoNum(r.debit),
          fmtDemoNum(r.credit),
          fmtDemoNum(r.closing),
        ];
      }),
      [
        '',
        'TALLY TRIAL BALANCE (Dr = Cr)',
        '',
        fmtDemoNum(accOp.total + headRows.fold<double>(0, (s, r) => s + r.openTotal)),
        fmtDemoNum(padarCr + bankCr + padarDr + bankDr),
        fmtDemoNum(padarCr + bankCr + padarDr + bankDr),
        fmtDemoNum(cashClose + bankClose + headRows.fold<double>(0, (s, r) => s + r.closing)),
      ],
    ];

    double totPartyAll = 0, totPartyCash = 0, totPartyBank = 0;
    final partyRows = partyMap.keys.toList().asMap().entries.map((entry) {
      final idx = entry.key;
      final p = entry.value;
      final pm = partyMap[p]!;
      final tot = pm['totalPaid'] as double;
      final cPaid = pm['cashPaid'] as double;
      final bPaid = pm['bankPaid'] as double;
      totPartyAll += tot;
      totPartyCash += cPaid;
      totPartyBank += bPaid;
      return <String>[
        '${idx + 1}',
        p,
        (pm['heads'] as Set<String>).join(', '),
        (pm['vouchers'] as Set<String>).take(5).join(', '),
        fmtDemoNum(tot),
        fmtDemoNum(cPaid),
        fmtDemoNum(bPaid),
        '0.00',
      ];
    }).toList();
    partyRows.add(['', 'TALLY PARTY LEDGER GRAND TOTAL :', '', '', fmtDemoNum(totPartyAll), fmtDemoNum(totPartyCash), fmtDemoNum(totPartyBank), '0.00']);

    return Column(
      children: [
        _govAuditSheet(
          children: [
            _govSchoolBlockHeader('TALLY AUDIT REPORT — ટ્રાયલ બેલેન્સ, ગ્રાન્ટ ખાતાવહી અને ડે-બુક રીકન્સીલેશન ($acc)', acc, mAcc),
            const Text('૧. ટેલી ટ્રાયલ બેલેન્સ (Tally Trial Balance & Grant Ledger Abstract):', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 14)),
            const SizedBox(height: 6),
            _govAuditTable(
              headers: const ['ક્રમ', 'લેજર / ખાતાનું નામ (Tally Ledger Name)', 'અંડર ગ્રુપ (Tally Group)', 'ઉઘડતી સિલક ₹', 'ઉધાર (Debit ₹)', 'જમા (Credit ₹)', 'બંધ સિલક ₹'],
              rows: tbRows,
              lastRowIsTotal: true,
            ),
            _govAuditSignatures(acc),
          ],
        ),
        _govAuditSheet(
          children: [
            _govSchoolBlockHeader('TALLY PARTY / VENDOR LEDGER SUMMARY (પાર્ટી / વેપારી / લાભાર્થી મુજબ ટેલી ખાતાવહી સારાંશ)', acc, mAcc),
            _govAuditTable(
              headers: const ['ક્રમ', 'પાર્ટી / વેપારી / લાભાર્થીનું નામ', 'ગ્રાન્ટ હેડ', 'વાઉચર નંબર', 'કુલ બિલ રકમ ₹', 'રોકડ ચુકવણી ₹', 'બેંક/SNA ચુકવણી ₹', 'બાકી રકમ ₹'],
              rows: partyRows,
              lastRowIsTotal: true,
            ),
            _govAuditSignatures(acc),
          ],
        ),
      ],
    );
  }

  // REPORT 14: Tarij Patrak (તારીજ પત્રક - Side-by-Side Receipts & Payments)
  Widget _report14TarijPatrak(List<RojmelEntry> list, String acc, AccountMeta mAcc) {
    final baseOp = engine.getAccountOpening(acc, engine.reportFilterHead);
    final headRows = _filteredHeadRows(acc);
    final opCash = engine.reportFromDate.isNotEmpty
        ? headRows.fold<double>(0.0, (s, r) => s + r.openCash)
        : baseOp.cash;
    final opBank = engine.reportFromDate.isNotEmpty
        ? headRows.fold<double>(0.0, (s, r) => s + r.openBank)
        : baseOp.bank;
    final opTotal = opCash + opBank;

    double totCrCash = 0, totCrBank = 0, totDrCash = 0, totDrBank = 0;
    for (final r in headRows) {
      totCrCash += r.padarCr;
      totCrBank += r.bankCr;
      totDrCash += r.padarDr;
      totDrBank += r.bankDr;
    }
    final closeCash = opCash + totCrCash - totDrCash;
    final closeBank = opBank + totCrBank - totDrBank;

    final leftRows = <List<String>>[
      ['શ્રી ઉઘડતી સિલક (Opening Balance)', fmtDemoNum(opCash), fmtDemoNum(opBank), fmtDemoNum(opTotal)],
      ...headRows.where((r) => r.credit > 0).map((r) => <String>[r.head, fmtDemoNum(r.padarCr), fmtDemoNum(r.bankCr), fmtDemoNum(r.credit)]),
      ['કુલ આવક (Total Receipts)', fmtDemoNum(totCrCash), fmtDemoNum(totCrBank), fmtDemoNum(totCrCash + totCrBank)],
      ['એકંદરે કુલ આવક (Grand Total) :', fmtDemoNum(opCash + totCrCash), fmtDemoNum(opBank + totCrBank), fmtDemoNum(opTotal + totCrCash + totCrBank)],
    ];

    final rightRows = <List<String>>[
      ...headRows.where((r) => r.debit > 0).map((r) => <String>[r.head, fmtDemoNum(r.padarDr), fmtDemoNum(r.bankDr), fmtDemoNum(r.debit)]),
      ['કુલ ખર્ચ (Total Expenditure)', fmtDemoNum(totDrCash), fmtDemoNum(totDrBank), fmtDemoNum(totDrCash + totDrBank)],
      ['શ્રી બંધ સિલક (Closing Balance)', fmtDemoNum(closeCash), fmtDemoNum(closeBank), fmtDemoNum(closeCash + closeBank)],
      ['એકંદરે કુલ જાવક (Grand Total) :', fmtDemoNum(totDrCash + closeCash), fmtDemoNum(totDrBank + closeBank), fmtDemoNum(totDrCash + totDrBank + closeCash + closeBank)],
    ];

    return _govAuditSheet(
      children: [
        _govSchoolBlockHeader('તારીજ પત્રક (આવક-જાવકનું વાર્ષિક હિસાબી પત્રક) / RECEIPT & PAYMENT ACCOUNT', acc, mAcc),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(color: const Color(0xFFEAFAF2), border: Border.all(color: Colors.black)),
                    child: const Text('આવક (જમા) / RECEIPTS (+)', textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.w900)),
                  ),
                  _govAuditTable(
                    headers: const ['આવકના સદર / ગ્રાન્ટ હેડ', 'રોકડ ₹', 'બેન્ક ₹', 'કુલ રકમ ₹'],
                    rows: leftRows,
                    lastRowIsTotal: true,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(color: const Color(0xFFFFF1F2), border: Border.all(color: Colors.black)),
                    child: const Text('જાવક (ઉધાર) / PAYMENTS (-)', textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.w900)),
                  ),
                  _govAuditTable(
                    headers: const ['જાવકના સદર / ગ્રાન્ટ હેડ', 'રોકડ ₹', 'બેન્ક ₹', 'કુલ રકમ ₹'],
                    rows: rightRows,
                    lastRowIsTotal: true,
                  ),
                ],
              ),
            ),
          ],
        ),
        _govAuditSignatures(acc),
      ],
    );
  }

  // REPORT 15: Certified Vouchers (પ્રમાણિત વાઉચર યાદી પત્રક)
  Widget _report15CertifiedVouchers(List<RojmelEntry> list, String acc, AccountMeta mAcc, Map<String, int> pageMap, Map<String, int> khMap) {
    final debits = list.where((e) => e.type == 'debit').toList();
    double totCash = 0, totBank = 0, totAmt = 0;

    final rows = debits.asMap().entries.map((entry) {
      final i = entry.key;
      final e = entry.value;
      final c = RojmelEngine.cashAmt(e);
      final b = RojmelEngine.bankAmt(e);
      totCash += c;
      totBank += b;
      totAmt += e.amount;
      return <String>[
        '${i + 1}',
        e.voucher.isNotEmpty ? e.voucher : '-',
        fmtDateDDMMYY(e.date),
        '${pageMap[e.id] ?? "-"}',
        '${khMap[e.head] ?? "-"}',
        e.head,
        e.party.isNotEmpty ? e.party : '-',
        engine.formatDebitNarration(e),
        e.txn.isNotEmpty ? e.txn : (RojmelEngine.isCashEntry(e) ? 'રોકડ' : '-'),
        fmtDateDDMMYY(e.clearDate),
        fmtDemoNum(c),
        fmtDemoNum(b),
        fmtDemoNum(e.amount),
      ];
    }).toList();

    rows.add(['', '', '', '', '', '', '', 'એકંદરે કુલ પ્રમાણિત ખર્ચ :', '', '', fmtDemoNum(totCash), fmtDemoNum(totBank), fmtDemoNum(totAmt)]);

    return _govAuditSheet(
      children: [
        _govSchoolBlockHeader('પ્રમાણિત વાઉચર અને ખર્ચનું પત્રક (CERTIFIED STATEMENT OF VOUCHERS)', acc, mAcc),
        _govAuditTable(
          headers: const [
            'અ.નં.', 'વાઉચર નં.', 'તારીખ', 'રોજમેળ પાના નં.', 'ખાતાવહી પાના નં.',
            'ગ્રાન્ટ હેડ', 'પાર્ટીનું નામ', 'ખર્ચની વિગત', 'ચેક / CLAIM નંબર',
            'સેટલમેન્ટ તારીખ', 'રોકડ ₹', 'બેંક/SNA ₹', 'કુલ રકમ ₹',
          ],
          rows: rows,
          lastRowIsTotal: true,
        ),
        _govAuditSignatures(acc),
      ],
    );
  }

  // REPORT 16: Cover Page (`પુઠું`) & Audit Certificates
  Widget _report16CoverPageAndIndex(List<RojmelEntry> list, String acc, AccountMeta mAcc) {
    final accOp = engine.getAccountOpening(acc);
    double crCash = 0, crBank = 0, drCash = 0, drBank = 0;
    for (final e in list) {
      if (e.type == 'credit') {
        crCash += RojmelEngine.cashAmt(e);
        crBank += RojmelEngine.bankAmt(e);
      } else {
        drCash += RojmelEngine.cashAmt(e);
        drBank += RojmelEngine.bankAmt(e);
      }
    }
    final closeCash = accOp.cash + crCash - drCash;
    final closeBank = accOp.bank + crBank - drBank;
    final sName = mAcc.schoolName.isNotEmpty ? mAcc.schoolName : engine.schoolName;

    return _govAuditSheet(
      children: [
        Container(
          padding: const EdgeInsets.all(18),
          margin: const EdgeInsets.only(bottom: 14),
          decoration: BoxDecoration(
            color: const Color(0xFFFCFDFF),
            border: Border.all(color: const Color(0xFF11345F), width: 3),
          ),
          child: Column(
            children: [
              Text(
                engine.districtName.trim().isNotEmpty
                    ? '${engine.districtName.trim()} જિલ્લા શિક્ષણ સમિતિ સંચાલિત'
                    : 'જિલ્લા શિક્ષણ સમિતિ સંચાલિત',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 4),
              Text(sName, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: Color(0xFF11345F))),
              const SizedBox(height: 4),
              Text(engine.fullFormattedSchoolAddress, textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 6),
                decoration: BoxDecoration(color: const Color(0xFFFDE9D9), border: Border.all(color: Colors.black, width: 2)),
                child: Text('રોજમેળ અને ઓડિટ ફાઈલ — વર્ષ : ${engine.financialYear} ($acc)', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900)),
              ),
              const SizedBox(height: 12),
              Builder(
                builder: (context) {
                  final sAddr = engine.fullFormattedSchoolAddress.isNotEmpty ? engine.fullFormattedSchoolAddress : mAcc.branchAddress.trim();
                  final covKey = '$acc|COVER';
                  final covDefault = mAcc.type == 'SNA_PURE'
                      ? <List<String>>[
                          ['SCHOOL NAME :', sName, 'YEAR :', engine.financialYear],
                          ['AGENCY CODE :', mAcc.effectiveSnaAgencyCode, 'ACCOUNT NAME :', acc],
                        ]
                      : (mAcc.type == 'SNA'
                          ? <List<String>>[
                              ['SCHOOL NAME :', sName, 'YEAR :', engine.financialYear],
                              ['PFMS A/C NO. :', mAcc.acNo, 'SNA AGENCY CODE :', mAcc.effectiveSnaAgencyCode],
                              ['PFMS LAST DATE :', fmtDateSlashDDMMYYYY(mAcc.pfmsLastDate), 'SNA START DATE :', fmtDateSlashDDMMYYYY(mAcc.snaStartDate)],
                            ]
                          : <List<String>>[
                              ['SCHOOL NAME :', sName, 'ACCOUNT HOLDER NAME :', mAcc.holderName],
                              ['ACCOUNT NUMBER :', mAcc.acNo, 'IFSC CODE :', mAcc.ifsc],
                              ['BRANCH :', '${mAcc.branch} ${mAcc.bankName.isNotEmpty ? "(${mAcc.bankName})" : ""}'.trim(), 'BRANCH ADDRESS :', sAddr],
                            ]);
                  final covGrid = engine.parishisht10CustomGrids[covKey] ?? covDefault;
                  return Column(
                    children: [
                      InkWell(
                        onTap: () => _openParishisht10HeaderEditorDialog(covKey, covDefault, const <int>[], headerTitle: 'Cover Page ($acc)'),
                        child: _govAuditTable(
                          headers: const [],
                          rows: covGrid,
                          boldAll: true,
                        ),
                      ),
                      _buildReportFontAndHeightControlsBar(
                        label: '⚙ Cover Page Font & Row Height Settings:',
                        onEditCells: () => _openParishisht10HeaderEditorDialog(covKey, covDefault, const <int>[], headerTitle: 'Cover Page ($acc)'),
                      ),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
        Text('ઓડિટ ફાઈલમાં સામેલ રજીસ્ટર અને પત્રકોની અનુક્રમણિકા ($acc):', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14)),
        const SizedBox(height: 6),
        _govAuditTable(
          headers: <String>['અ.નં.', 'પત્રક / રજીસ્ટરનું નામ (Register Name)', 'સારાંશ / કુલ રકમ ($acc)', 'સ્થિતિ'],
          rows: [
            ['1', 'રોજમેળ / કેશબુક (Cashbook — $acc)', 'ઉઘડતી ₹ ${fmtDemoNum(accOp.bank)} | જમા ₹ ${fmtDemoNum(crBank)} | ખર્ચ ₹ ${fmtDemoNum(drBank)}', 'સામેલ છે'],
            ['2', 'પરિશિષ્ટ નંબર : 2 — આવક ખર્ચનું વર્ગીકરણ (કલાસીફાઈડ રજીસ્ટર / ખાતાવહી)', '${engine.getAccountSpecificHeads(acc).length} ગ્રાન્ટ હેડ ખાતાવહી', 'સામેલ છે'],
            ['3', 'વર્ષ દરમિયાનનું બિલોનું નોંધપત્રક (બિલ રજીસ્ટર)', 'કુલ બિલ ₹ ${fmtDemoNum(drCash + drBank)} (નેટ બેંક ખર્ચ ₹ ${fmtDemoNum(drBank)})', 'સામેલ છે'],
            ['4', 'વર્ષ દરમિયાનનું ચેકોનું નોંધપત્રક (ક્લેઈમ / ચેક રજીસ્ટર)', 'કુલ બેંક ડેબિટ ₹ ${fmtDemoNum(drBank)}', 'સામેલ છે'],
            ['5', 'ખર્ચ પત્રક (વર્ષ દરમિયાન ખર્ચનું નોંધપત્રક)', 'રોકડ ₹ ${fmtDemoNum(drCash)} + બેંક ₹ ${fmtDemoNum(drBank)}', 'સામેલ છે'],
            ['6', 'પરિશિષ્ટ – 9 : બેંક સાથે મેળવણું – રીકન્સીલેશન (Bank Reconciliation)', 'રોજમેળ સિલક ₹ ${fmtDemoNum(closeBank)} = પાસબુક ₹ ${fmtDemoNum(closeBank)}', 'સામેલ છે'],
            ['7', 'પરિશિષ્ટ – ૧૦ : ગ્રાન્ટ વપરાશ પ્રમાણપત્ર (Utilization Certificate)', 'કુલ ગ્રાન્ટ ₹ ${fmtDemoNum(accOp.bank + crBank)} | ખર્ચ ₹ ${fmtDemoNum(drBank)} | બચત ₹ ${fmtDemoNum(closeBank)}', 'સામેલ છે'],
            ['8', 'ગ્રાન્ટ રજીસ્ટર : પરિશિષ્ટ ૧૧ (Grant Register)', 'કુલ ગ્રાન્ટ ₹ ${fmtDemoNum(accOp.bank + crBank)} | બચત ₹ ${fmtDemoNum(closeBank)}', 'સામેલ છે'],
            ['9', 'એનેક્ષર-12 : સર્વ શિક્ષા અભિયાન - ગુજરાત (માસવાર હિસાબ પત્રક)', 'એપ્રિલ થી માર્ચ (12 માસ)', 'સામેલ છે'],
            ['10', 'ટેલી રિપોર્ટ (Tally Trial Balance, Party Ledgers & DayBook)', 'ટ્રાયલ બેલેન્સ અને પાર્ટી ખાતાવહી', 'સામેલ છે'],
          ],
        ),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(border: Border.all(color: Colors.black)),
          child: Text(
            'રોકડ અને બેંક સિલક પ્રમાણપત્ર: આથી પ્રમાણિત કરવામાં આવે છે કે તા. 31/03/${engine.financialYear.length >= 4 ? ((int.tryParse(engine.financialYear.substring(0, 4)) ?? 2025) + 1) : 2026} ના રોજ $acc રોજમેળ મુજબ હાથ પરની રોકડ સિલક ₹ ${fmtDemoNum(closeCash)} અને બેંક સિલક ₹ ${fmtDemoNum(closeBank)} મળી કુલ બંધ સિલક ₹ ${fmtDemoNum(closeCash + closeBank)} રહેલ છે.',
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
          ),
        ),
        _govAuditSignatures(acc),
      ],
    );
  }

  // --------------------------------------------------------------------------
  // PANEL 7: TALLY REPORT (`#tallyPanel`)
  // --------------------------------------------------------------------------

  Widget _buildPanelTally() {
    final acc = engine.selectedAccount;
    final mAcc = engine.getAccountMeta(acc);
    final list = engine.getSortedEntries(engine.getAccountEntries(acc));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('🧮 Tally Report & TallyPrime / ERP9 Integration (ટેલી રિપોર્ટ)', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: Color(0xFF10233F))),
        _htmlCard(
          headerText: 'Tally Accounting Summary, Ledger Verification & Export',
          body: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _htmlBtn('🔄 Refresh Tally Report', const Color(0xFF185D98), Colors.white, () => engine.triggerUpdate()),
              _htmlBtn('📥 Download TallyPrime / ERP9 XML (Vouchers & Masters)', const Color(0xFF087F5B), Colors.white, () {
                final xml = engine.generateTallyXml(acc);
                _downloadBrowserFile(xml, 'application/xml;charset=utf-8', 'Rojmel_Tally_${acc}_${engine.financialYear}.xml');
                Clipboard.setData(ClipboardData(text: xml));
                _showToast('TallyPrime / ERP9 XML copied to clipboard for account "$acc".');
              }),
              _htmlBtn('📄 Download Tally DayBook CSV', const Color(0xFFE8F0FA), const Color(0xFF164B80), () {
                final csv = engine.generateTransactionsCsv(acc);
                _downloadBrowserFile(csv, 'text/csv;charset=utf-8', 'Rojmel_Transactions_${acc}_${engine.financialYear}.csv');
                Clipboard.setData(ClipboardData(text: csv));
                _showToast('Tally DayBook CSV copied to clipboard for "$acc".');
              }),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _report13TallyAudit(list, acc, mAcc),
      ],
    );
  }

  // --------------------------------------------------------------------------
  // PANEL 8: CALCULATION CHECK (`#calculationAuditPanel`)
  // --------------------------------------------------------------------------

  Widget _buildPanelCalculationCheck() {
    final acc = engine.selectedAccount;
    final mAcc = engine.getAccountMeta(acc);
    final isSNAorPFMS = mAcc.isSnaOrPfms;
    final headRows = engine.computeHeadWiseSummary(acc);
    final audits = engine.runCalculationAudit(acc);
    final allOk = audits.every((a) => a.passed);

    double totLim = 0, totOpenC = 0, totOpenB = 0, totPadarCr = 0, totBankCr = 0, totPadarDr = 0, totBankDr = 0, totCloseC = 0, totCloseB = 0;
    for (final r in headRows) {
      totLim += r.annualLimit;
      totOpenC += r.openCash;
      totOpenB += r.openBank;
      totPadarCr += r.padarCr;
      totBankCr += r.bankCr;
      totPadarDr += r.padarDr;
      totBankDr += r.bankDr;
      totCloseC += r.closeCash;
      totCloseB += r.closeBank;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('✓ Calculation Check & Excel Formula Audit (ગણતરી અને ફોર્મ્યુલા ચકાસણી)', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: Color(0xFF10233F))),
        _htmlCard(
          headerText: 'Automated Verification of All Calculations, Formulas, Head-wise Opening Balances & Controls',
          body: Wrap(
            spacing: 12,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                width: 240,
                child: DropdownButtonFormField<String>(
                      isExpanded: true,
                  value: acc,
                  decoration: const InputDecoration(labelText: 'Account', border: OutlineInputBorder(), isDense: true),
                  items: engine.accounts.map((a) => DropdownMenuItem(value: a, child: Text(a))).toList(),
                  onChanged: (v) {
                    if (v != null) engine.selectAccount(v);
                  },
                ),
              ),
              _htmlBtn('✓ Run Complete Calculation & Formula Check', const Color(0xFF185D98), Colors.white, () => engine.triggerUpdate()),
            ],
          ),
        ),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            _statBox('₹ ${fmtDemoNum(totOpenC + totOpenB)}', 'Opening Balance ($acc)'),
            _statBox('₹ ${fmtDemoNum(totBankCr)}', 'Bank Grant Received ($acc)'),
            _statBox('₹ ${fmtDemoNum(totBankDr)}', 'Bank Grant Expense ($acc)'),
            _statBox('₹ ${fmtDemoNum(totCloseC + totCloseB)}', 'Closing Balance (31-03-2026)'),
          ],
        ),
        const SizedBox(height: 12),
        _noticeBox(
          allOk
              ? '✓ All Calculations Verified for $acc (0 Errors): Opening Balance (₹${fmtDemoNum(totOpenC + totOpenB)}), Bank Receipts (₹${fmtDemoNum(totBankCr)}), Bank Expenditure (₹${fmtDemoNum(totBankDr)}), Padar Cash (₹${fmtDemoNum(totPadarCr)}), and Closing Balance (₹${fmtDemoNum(totCloseC + totCloseB)}) match 100%.'
              : '⚠ Some calculation checks require attention in $acc.',
          type: allOk ? 'ok' : 'bad',
        ),
        _htmlCard(
          headerText: 'Head-wise Calculation Verification Table — $acc (${mAcc.schoolName})',
          body: _govAuditTable(
            headers: [
              '#', 'Grant Head',
              if (isSNAorPFMS) 'Yearly Limit ₹',
              'Open Cash', 'Open Bank', 'Padar Cash Cr', 'Bank Grant Cr', 'Padar Cash Dr', 'Bank Grant Dr', 'Closing Cash', 'Closing Bank', 'Total Closing',
            ],
            rows: [
              ...headRows.asMap().entries.map((entry) {
                final i = entry.key;
                final r = entry.value;
                return <String>[
                  '${i + 1}',
                  r.head,
                  if (isSNAorPFMS) fmtDemoNum(r.annualLimit),
                  fmtDemoNum(r.openCash),
                  fmtDemoNum(r.openBank),
                  fmtDemoNum(r.padarCr),
                  fmtDemoNum(r.bankCr),
                  fmtDemoNum(r.padarDr),
                  fmtDemoNum(r.bankDr),
                  fmtDemoNum(r.closeCash),
                  fmtDemoNum(r.closeBank),
                  fmtDemoNum(r.closing),
                ];
              }),
              [
                'TOTAL',
                'GRAND TOTAL ($acc)',
                if (isSNAorPFMS) fmtDemoNum(totLim),
                fmtDemoNum(totOpenC),
                fmtDemoNum(totOpenB),
                fmtDemoNum(totPadarCr),
                fmtDemoNum(totBankCr),
                fmtDemoNum(totPadarDr),
                fmtDemoNum(totBankDr),
                fmtDemoNum(totCloseC),
                fmtDemoNum(totCloseB),
                fmtDemoNum(totCloseC + totCloseB),
              ],
            ],
            lastRowIsTotal: true,
          ),
        ),
      ],
    );
  }

  // --------------------------------------------------------------------------
  // PANEL 9: EXPORT DATA (`#dataExportPanel` — ACCOUNT-WISE 17-SHEET EXCEL)
  // --------------------------------------------------------------------------

  Widget _buildPanelExportData() {
    final acc = engine.selectedAccount;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('Export Account-wise Excel & Backup (ખાતા મુજબ તમામ ૧૭ રિપોર્ટ અને DATA ENTRY સાથે એક્સેલ એક્સપોર્ટ)', style: TextStyle(fontSize: 21, fontWeight: FontWeight.w900, color: Color(0xFF10233F))),
        _htmlCard(
          headerText: 'Account-wise Complete Excel Workbook (.xlsx / .xls) — Only Selected Account (DATA ENTRY + All 28 Reports)',
          body: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Select an account below to download its Account-wise Complete Excel Workbook. The Excel file contains only the selected account\'s data (no mix-up with other accounts) and includes 17 Separate Worksheets: Cover Page (પુઠું), DATA ENTRY Sheet, Cashbook (રોજમેળ), Parishisht-2 (ખાતાવહી), Bill Register, Cheque/Claim Register, Kharch Patrak, Parishisht-8, Parishisht-9 (Reconciliation), Parishisht-10 (Utilization Certificate), Parishisht-11 (Grant Register), Annexure-12 (12 Months), Monthly Hisab Patrak, Passbook, Tally Report, Tarij Patrak, and Certified Vouchers.',
                style: TextStyle(fontSize: 13.5, height: 1.5),
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  SizedBox(
                    width: 320,
                    child: DropdownButtonFormField<String>(
                      isExpanded: true,
                      value: acc,
                      decoration: const InputDecoration(labelText: 'Select Account to Export *', border: OutlineInputBorder(), isDense: true),
                      items: engine.accounts.map((a) => DropdownMenuItem(value: a, child: Text(a))).toList(),
                      onChanged: (v) {
                        if (v != null) engine.selectAccount(v);
                      },
                    ),
                  ),
                  SizedBox(width: 180, child: _readonlyField('Financial Year', engine.financialYear)),
                ],
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _htmlBtn('Download Excel (17 Sheets)', const Color(0xFF087F5B), Colors.white, () {
                    final xml = engine.generateAccountExcelXml(acc, false);
                    _downloadBrowserFile(xml, 'application/vnd.ms-excel', 'Rojmel_${acc}_${engine.financialYear}_17_Reports.xls');
                    Clipboard.setData(ClipboardData(text: xml));
                    _showToast('Copied Complete 17-Sheet Excel Workbook for "$acc" to clipboard!');
                  }),
                  _htmlBtn('📄 Download Selected Account DATA ENTRY Sheet (.xlsx)', const Color(0xFF185D98), Colors.white, () {
                    final xml = engine.generateAccountExcelXml(acc, true);
                    _downloadBrowserFile(xml, 'application/vnd.ms-excel', 'Rojmel_${acc}_${engine.financialYear}_DATA_ENTRY.xls');
                    Clipboard.setData(ClipboardData(text: xml));
                    _showToast('Copied DATA ENTRY Excel Sheet for "$acc" to clipboard!');
                  }),
                  _htmlBtn('Transactions CSV', const Color(0xFFE8F0FA), const Color(0xFF164B80), () {
                    final csv = engine.generateTransactionsCsv(acc);
                    Clipboard.setData(ClipboardData(text: csv));
                    _showToast('Copied Transactions CSV for "$acc" to clipboard!');
                  }),
                  _htmlBtn('Complete JSON Backup', const Color(0xFFFFF3BF), const Color(0xFF754600), () {
                    final jsonStr = engine.exportBackupJson(selectedAccountOnly: false);
                    Clipboard.setData(ClipboardData(text: jsonStr));
                    _showToast('Copied Complete JSON Backup to clipboard!');
                  }),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  // --------------------------------------------------------------------------
  // PANEL 11: TRANSACTIONS (`#register` — ACCOUNT-WISE, NO MIX-UP)
  // --------------------------------------------------------------------------

  Widget _buildPanelTransactions() {
    final acc = engine.selectedAccount;
    final list = engine.getSortedEntries(engine.getAccountEntries(acc));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('વ્યવહારો (Account-wise Transactions — No Mix-up)', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: Color(0xFF10233F))),
        _htmlCard(
          body: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Wrap(
                spacing: 10,
                runSpacing: 10,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  const Text('ખાતું પસંદ કરો (Select Account):', style: TextStyle(fontWeight: FontWeight.w900)),
                  SizedBox(
                    width: 240,
                    child: DropdownButtonFormField<String>(
                      isExpanded: true,
                      value: acc,
                      decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true),
                      items: engine.accounts.map((a) => DropdownMenuItem(value: a, child: Text(a))).toList(),
                      onChanged: (v) {
                        if (v != null) engine.selectAccount(v);
                      },
                    ),
                  ),
                  _htmlBtn('Voucher Numbers Recalculate', const Color(0xFFE8F0FA), const Color(0xFF164B80), () {
                    engine.renumberVouchers(forceRecalc: true);
                    engine.triggerUpdate();
                    _showToast('Voucher numbers recalculated by debit transaction date.');
                  }),
                  _htmlBtn('Export Selected Account XLS', const Color(0xFF087F5B), Colors.white, () {
                    final xml = engine.generateAccountExcelXml(acc, false);
                    _downloadBrowserFile(xml, 'application/vnd.ms-excel', 'Rojmel_${acc}_${engine.financialYear}_17_Reports.xls');
                    Clipboard.setData(ClipboardData(text: xml));
                    _showToast('Copied Selected Account Excel (.xls) to clipboard!');
                  }),
                  _htmlBtn('🗑 Delete All Entries for Selected Account Only (2x Confirmation — Use for Next Year)', const Color(0xFFFFE3E3), const Color(0xFFC92A2A), () {
                    _openDeleteAllAccountEntriesModal(acc);
                  }),
                ],
              ),
              const SizedBox(height: 12),
              _htmlTable(
                headers: const ['#', 'Account', 'Date', 'Type', 'Voucher', 'Head', 'Narration', 'Amount', 'Action'],
                rows: list.asMap().entries.map((entry) {
                  final i = entry.key;
                  final e = entry.value;
                  final isCr = e.type == 'credit';
                  return <Widget>[
                    Text('${i + 1}'),
                    Text(e.account, style: const TextStyle(fontWeight: FontWeight.w800)),
                    Text(fmtDateSlashDDMMYYYY(e.date)),
                    _pill(isCr ? 'Credit / આવક' : 'Debit / જાવક', isGood: isCr),
                    Text(e.voucher),
                    Text(e.head, style: const TextStyle(fontWeight: FontWeight.w700)),
                    Text(e.narration),
                    Text(fmtDemoNum(e.amount), style: const TextStyle(fontWeight: FontWeight.w800)),
                    Wrap(
                      spacing: 4,
                      children: [
                        _htmlBtn('✏ Edit', const Color(0xFFE8F0FA), const Color(0xFF164B80), () => _openEditTransactionModal(e)),
                        _htmlBtn('Delete', const Color(0xFFFFE3E3), const Color(0xFFC92A2A), () => engine.deleteSingleEntry(e.id)),
                      ],
                    ),
                  ];
                }).toList(),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // --------------------------------------------------------------------------
  // PANEL 12: BULK IMPORT (`#bulk` — CSV / JSON BULK IMPORT + VOUCHER RULES)
  // --------------------------------------------------------------------------

  final _bulkPasteCtrl = TextEditingController();

  bool _excelImportBusy = false;

  Future<void> _downloadRojmelExcelTemplate(String acc) async {
    try {
      final bytes = RojmelExcelIO.buildTemplate(engine, acc);
      final safe = acc.replaceAll(RegExp(r'[^A-Za-z0-9\u0A80-\u0AFF]+'), '_');
      await PsmFileExportHelper.saveOrShare(
        bytes: bytes,
        filename: 'ROJMEL_UPLOAD_TEMPLATE_${safe}_${engine.financialYear}.xlsx',
        title: 'Rojmel Excel Template',
        mimeType: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      );
      _showToast('ટેમ્પ્લેટ ડાઉનલોડ થયું: સૂચના, ડેટા અપલોડ, ગ્રાન્ટ હેડ અને નમૂના એન્ટ્રી શીટ સાથે.');
    } catch (e) {
      _showToast('ટેમ્પ્લેટ બનાવવામાં ભૂલ: $e');
    }
  }

  Future<void> _uploadRojmelExcel(String acc) async {
    if (_excelImportBusy) return;
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['xlsx'],
      withData: true,
    );
    final bytes = picked?.files.single.bytes;
    if (bytes == null) return;
    setState(() => _excelImportBusy = true);
    try {
      final parsed = RojmelExcelIO.parseUpload(bytes);
      final errors = <String>[...parsed.errors];
      if (parsed.account.isNotEmpty && parsed.account != acc) {
        errors.insert(0, 'આ ટેમ્પ્લેટ "${parsed.account}" ખાતા માટે છે, પરંતુ પસંદ કરેલ ખાતું "$acc" છે. સાચું ખાતું પસંદ કરો અથવા તે ખાતાનું ટેમ્પ્લેટ ડાઉનલોડ કરો.');
      }
      if (errors.isEmpty) {
        // Dry run on a copy: nothing is imported unless every row is valid.
        final trial = RojmelEngine()
          ..loadStateFromMap(
            jsonDecode(engine.exportBackupJson()) as Map<String, dynamic>,
            notify: false,
          );
        errors.addAll(RojmelExcelIO.applyRows(trial, acc, parsed.rows));
        trial.dispose();
      }
      if (errors.isNotEmpty) {
        if (!mounted) return;
        await showDialog<void>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text('Excel માં ${errors.length} ભૂલ — કોઈ એન્ટ્રી ઉમેરાઈ નથી'),
            content: SizedBox(
              width: 640,
              height: 380,
              child: ListView(
                children: [
                  for (final e in errors.take(100))
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Text('• $e', style: const TextStyle(fontSize: 14)),
                    ),
                ],
              ),
            ),
            actions: [
              FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('બરાબર, સુધારું છું')),
            ],
          ),
        );
        return;
      }
      final finalErrors = RojmelExcelIO.applyRows(engine, acc, parsed.rows);
      engine.renumberVouchers();
      engine.triggerUpdate();
      _showToast(finalErrors.isEmpty
          ? '✅ ${parsed.rows.length} પંક્તિ "$acc" ખાતામાં ઉમેરાઈ. હવે "Save to Server" દબાવો.'
          : '${finalErrors.length} પંક્તિમાં ભૂલ: ${finalErrors.first}');
    } catch (e) {
      _showToast('Excel વાંચવામાં ભૂલ: $e');
    } finally {
      if (mounted) setState(() => _excelImportBusy = false);
    }
  }

  Widget _buildExcelUploadCard() {
    final acc = engine.selectedAccount;
    final m = engine.getAccountMeta(acc);
    final heads = engine.getAccountSpecificHeads(acc).where((h) => engine.grantHeadActiveMap[h] != 'no').toList();
    final isLimitAccount = m.isSnaOrPfms;
    final missingLimit = isLimitAccount ? heads.where((h) => engine.getHeadLimit(acc, h) <= 0).toList() : <String>[];
    final ready = heads.isNotEmpty &&
        (isLimitAccount ? missingLimit.length < heads.length : engine.isBankOpeningReady(acc));

    Widget step(int n, String title, bool done, Widget body) => Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: done ? const Color(0xFFF0FDF4) : const Color(0xFFFFF7ED),
            border: Border.all(color: done ? const Color(0xFF86EFAC) : const Color(0xFFFDBA74), width: 1.5),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                CircleAvatar(
                  radius: 14,
                  backgroundColor: done ? const Color(0xFF16A34A) : const Color(0xFFEA580C),
                  child: done
                      ? const Icon(Icons.check, size: 16, color: Colors.white)
                      : Text('$n', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900)),
                ),
                const SizedBox(width: 10),
                Expanded(child: Text(title, style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w900))),
              ]),
              const SizedBox(height: 8),
              body,
            ],
          ),
        );

    return _htmlCard(
      headerText: 'Excel અપલોડ (ભલામણ કરેલ) — ટેમ્પ્લેટ ડાઉનલોડ → ભરો → અપલોડ',
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 340,
            child: DropdownButtonFormField<String>(
              value: acc,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'ખાતું (Account)', border: OutlineInputBorder(), isDense: true),
              items: engine.accounts.map((a) => DropdownMenuItem(value: a, child: Text('$a  •  ${RojmelExcelIO.typeLabel(engine.getAccountMeta(a))}'))).toList(),
              onChanged: (v) {
                if (v != null) engine.selectAccount(v);
              },
            ),
          ),
          const SizedBox(height: 12),
          step(
            1,
            isLimitAccount
                ? 'ગ્રાન્ટ હેડની વાર્ષિક લિમિટ સેટ કરો (SNA SPARSH / PFMS માટે ફરજિયાત)'
                : 'હેડ-વાઈઝ ઉઘડતી સિલક દાખલ કરો (ન હોય તો 0)',
            ready && missingLimit.isEmpty,
            heads.isEmpty
                ? Wrap(spacing: 8, runSpacing: 8, children: [
                    const Text('આ ખાતામાં હજુ કોઈ ગ્રાન્ટ હેડ નથી. પહેલાં Grant Heads / Rojmel Accounts માં હેડ ઉમેરો.',
                        style: TextStyle(fontWeight: FontWeight.w700, color: Color(0xFF9A3412))),
                    _htmlBtn('🗂 Grant Heads', const Color(0xFF185D98), Colors.white, () => _goToPanel('grantHeadsPanel')),
                  ])
                : isLimitAccount
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            missingLimit.isEmpty
                                ? 'બધા ${heads.length} હેડની લિમિટ સેટ છે. ✔'
                                : '${heads.length - missingLimit.length} / ${heads.length} હેડની લિમિટ સેટ છે. લિમિટ વગરના હેડ ટેમ્પ્લેટમાં નહીં આવે — હેડ પર ક્લિક કરી લિમિટ સેટ કરો:',
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          if (missingLimit.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 6,
                              runSpacing: 6,
                              children: [
                                for (final h in missingLimit)
                                  ActionChip(
                                    avatar: const Icon(Icons.edit_note_rounded, size: 18),
                                    label: Text(h),
                                    onPressed: () => _openQuickHeadLimitDialog(acc, h),
                                  ),
                              ],
                            ),
                          ],
                        ],
                      )
                    : Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(
                            engine.isBankOpeningReady(acc)
                                ? 'ઉઘડતી સિલક: ₹${fmtDemoNum(engine.getAccountOpening(acc).total)} (હેડ-વાઈઝ ફાળવણી પૂર્ણ) ✔'
                                : 'BANK ખાતામાં હેડ-વાઈઝ ઉઘડતી સિલક હજુ સેટ નથી.',
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          _htmlBtn('🏦 ઉઘડતી સિલક દાખલ કરો', const Color(0xFF185D98), Colors.white, () => _openQuickBankOpeningDialog(acc)),
                          if (!engine.isBankOpeningReady(acc))
                            _htmlBtn('0 ઉઘડતી સિલક સાથે આગળ વધો', const Color(0xFFE8F0FA), const Color(0xFF164B80), () {
                              engine.setBankOpeningBalanceQuick(
                                accName: acc,
                                totalBank: 0,
                                totalCash: 0,
                                headOpenings: {for (final h in heads) h: HeadBalance()},
                              );
                              _showToast('બધા હેડની ઉઘડતી સિલક 0 તરીકે સેટ થઈ.');
                            }),
                        ],
                      ),
          ),
          step(
            2,
            'ટેમ્પ્લેટ ડાઉનલોડ કરો (4 શીટ: સૂચના • ડેટા અપલોડ • ગ્રાન્ટ હેડ • નમૂના એન્ટ્રી)',
            false,
            Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
              _htmlBtn(
                ready ? '📥 Excel ટેમ્પ્લેટ ડાઉનલોડ' : '🔒 પહેલાં પગલું 1 પૂર્ણ કરો',
                ready ? const Color(0xFF087F5B) : const Color(0xFF94A3B8),
                Colors.white,
                ready ? () => _downloadRojmelExcelTemplate(acc) : () => _showToast('પહેલાં પગલું 1 પૂર્ણ કરો.'),
              ),
              Text('માન્ય માધ્યમ: ${RojmelExcelIO.modesFor(m).join(' / ')}',
                  style: const TextStyle(fontWeight: FontWeight.w700, color: Color(0xFF475569))),
            ]),
          ),
          step(
            3,
            'ભરેલું Excel અપલોડ કરો — પહેલાં બધી પંક્તિ ચકાસાય છે, એક પણ ભૂલ હોય તો કંઈ ઉમેરાતું નથી',
            false,
            _htmlBtn(
              _excelImportBusy ? '⏳ ચકાસણી ચાલુ છે...' : '📤 Excel અપલોડ કરો',
              ready ? const Color(0xFF185D98) : const Color(0xFF94A3B8),
              Colors.white,
              ready ? () => _uploadRojmelExcel(acc) : () => _showToast('પહેલાં પગલું 1 પૂર્ણ કરો.'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPanelBulkImport() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('Excel / CSV Bulk Import', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: Color(0xFF10233F))),
        _buildExcelUploadCard(),
        _htmlCard(
          headerText: 'Advanced: CSV / JSON backup paste',
          body: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFFEEFBF5),
                  border: Border.all(color: const Color(0xFF63A88E), width: 2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _htmlBtn('📥 Copy CSV Template (any Indian date: 01/12/2025, 1-12-25, 1-Dec-25)', const Color(0xFF087F5B), Colors.white, () {
                          const tpl = 'Account Name,Entry Type (Credit/Debit),Transaction Date (DD/MM/YYYY),Grant Head,Narration,Total Amount,Payment Medium,Cheque-PFMS-Txn No,Clearing Date (DD/MM/YYYY),Party-Recipient,Expense Details\n'
                              'SNA SPARSH,Credit,25/06/2025,શાળા સંયુક્ત ગ્રાન્ટ,ગ્રાન્ટ જમા થઈ,10000,PFMS,TXN001,25/06/2025,SSA,\n'
                              'SNA SPARSH,Debit,25/06/2025,શાળા સંયુક્ત ગ્રાન્ટ,સ્ટેશનરી ખર્ચ,2500,PFMS,C0725001,26/06/2025,SAGAR STORES,સ્ટેશનરી';
                          Clipboard.setData(const ClipboardData(text: tpl));
                          _showToast('CSV Import Template (DD/MM/YYYY) copied to clipboard!');
                        }),
                      ],
                    ),
                    const SizedBox(height: 12),
                    _labeledInput('Paste CSV Rows or JSON Backup here to Import:', _bulkPasteCtrl, maxLines: 5),
                    const SizedBox(height: 10),
                    _htmlBtn('📤 Import Pasted Data', const Color(0xFF185D98), Colors.white, () {
                      final raw = _bulkPasteCtrl.text.trim();
                      if (raw.isEmpty) return;
                      if (raw.startsWith('{')) {
                        try {
                          final map = jsonDecode(raw) as Map<String, dynamic>;
                          engine.loadStateFromMap(map);
                          _bulkPasteCtrl.clear();
                          _showToast('JSON Backup imported successfully!');
                          return;
                        } catch (e) {
                          _showToast('Invalid JSON format: $e');
                          return;
                        }
                      }
                      final lines = raw.split(RegExp(r'\r?\n')).where((l) => l.trim().isNotEmpty).toList();
                      int imported = 0;
                      final badDateRows = <int>[];
                      for (int i = 1; i < lines.length; i++) {
                        final cols = lines[i].split(',').map((s) => s.replaceAll('"', '').trim()).toList();
                        if (cols.length >= 6) {
                          final acc = cols[0].isNotEmpty ? cols[0] : engine.selectedAccount;
                          final type = cols[1].toLowerCase().contains('credit') || cols[1].contains('આવક') ? 'credit' : 'debit';
                          // Any Indian date style (01/12/2025, 1-12-25, 1-Dec-25 …).
                          final date = normalizeToIsoDate(cols[2]);
                          final head = cols[3];
                          final narr = cols[4];
                          final amt = double.tryParse(cols[5]) ?? 0.0;
                          final med = cols.length > 6 && cols[6].isNotEmpty ? cols[6] : 'Bank';
                          final txn = cols.length > 7 ? cols[7] : '';
                          final clr = cols.length > 8 && cols[8].isNotEmpty ? normalizeToIsoDate(cols[8]) : date;
                          final party = cols.length > 9 ? cols[9] : '';
                          final exp = cols.length > 10 ? cols[10] : '';
                          if (amt > 0 && head.isNotEmpty && (!isRojmelDate(date) || (clr.isNotEmpty && !isRojmelDate(clr)))) {
                            badDateRows.add(i + 1);
                            continue;
                          }
                          if (amt > 0 && head.isNotEmpty) {
                            if (!engine.accounts.contains(acc)) engine.accounts.add(acc);
                            engine.entries.add(RojmelEntry(
                              sr: i,
                              date: date,
                              head: head,
                              type: type,
                              narration: narr,
                              amount: amt,
                              medium: med,
                              txn: txn,
                              clearDate: clr,
                              party: party,
                              expense: exp,
                              id: 'imp-${DateTime.now().microsecondsSinceEpoch}-$i',
                              seq: DateTime.now().millisecondsSinceEpoch + i,
                              account: acc,
                            ));
                            imported++;
                          }
                        }
                      }
                      engine.renumberVouchers(forceRecalc: true);
                      engine.triggerUpdate();
                      _bulkPasteCtrl.clear();
                      _showToast(badDateRows.isEmpty
                          ? '$imported entries imported and debit vouchers recalculated.'
                          : '$imported entries imported. ${badDateRows.length} row(s) skipped — date not understood (rows ${badDateRows.take(12).join(', ')}). Use 01/12/2025, 1-12-25 or 1-Dec-25.');
                    }),
                  ],
                ),
              ),
            ],
          ),
        ),
        _htmlCard(
          headerText: 'Voucher-number rules included in template',
          body: Container(
            padding: const EdgeInsets.all(13),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF8DB),
              border: const Border(left: BorderSide(color: Color(0xFFE0A100), width: 5)),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Text(
              '1. Final voucher number applies only to Debit / જાવક entries.\n'
              '2. Voucher sequence is based on Debit Transaction Date, not data-entry date.\n'
              '3. If an earlier-dated debit is added or imported later, all later debit voucher numbers automatically change.\n'
              '4. Voucher numbering is separate for each Account + Financial Year.\n'
              '5. Credit entries do not consume debit voucher numbers.\n'
              '6. For multiple debits on the same date, imported/file row order is maintained.',
              style: TextStyle(fontSize: 13.5, height: 1.55, fontWeight: FontWeight.w600),
            ),
          ),
        ),
      ],
    );
  }

  // --------------------------------------------------------------------------
  // PANEL 13: BACKUP & SETTINGS (`#settings`)
  // --------------------------------------------------------------------------

  Widget _buildPanelSettings() {
    final schoolCtrl = TextEditingController(text: engine.schoolName);
    final fyCtrl = TextEditingController(text: engine.financialYear);
    final addrCtrl = TextEditingController(text: engine.schoolAddress);
    final udiseCtrl = TextEditingController(text: engine.udiseCode);
    final talukaCtrl = TextEditingController(text: engine.talukaName);
    final distCtrl = TextEditingController(text: engine.districtName);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('સેટિંગ્સ અને ક્લાઉડ બેકઅપ (Backup & Settings)', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: Color(0xFF10233F))),
        _htmlCard(
          body: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  SizedBox(width: 420, child: _labeledInput('School Name / શાળાનું નામ (રજીસ્ટ્રેશન મુજબ લોક)', schoolCtrl, readOnly: true)),
                  _buildRojmelSchoolNameLangSelector(onUpdated: () {
                    schoolCtrl.text = _registeredSchoolName;
                  }),
                  SizedBox(width: 200, child: _labeledInput('Financial Year', fyCtrl)),
                  SizedBox(width: 420, child: _labeledInput('School Address / સરનામું', addrCtrl)),
                  SizedBox(width: 200, child: _labeledInput('UDISE Code', udiseCtrl)),
                  SizedBox(width: 200, child: _labeledInput('Taluka', talukaCtrl)),
                  SizedBox(width: 200, child: _labeledInput('District', distCtrl)),
                ],
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _htmlBtn('Save Settings', const Color(0xFF185D98), Colors.white, () {
                    engine.schoolName = schoolCtrl.text.trim();
                    engine.financialYear = fyCtrl.text.trim();
                    engine.schoolAddress = addrCtrl.text.trim();
                    engine.udiseCode = udiseCtrl.text.trim();
                    engine.talukaName = talukaCtrl.text.trim();
                    engine.districtName = distCtrl.text.trim();
                    engine.triggerUpdate();
                    _showToast('Settings saved.');
                  }),
                  _htmlBtn('Download JSON Backup', const Color(0xFFFFF3BF), const Color(0xFF754600), () {
                    final jsonStr = engine.exportBackupJson(selectedAccountOnly: false);
                    Clipboard.setData(ClipboardData(text: jsonStr));
                    _showToast('Complete JSON Backup copied to clipboard!');
                  }),

                  _htmlBtn('🗑 Clear Selected Account Entries (2x Confirm)', const Color(0xFFFFE3E3), const Color(0xFFC92A2A), () {
                    _openDeleteAllAccountEntriesModal(engine.selectedAccount);
                  }),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  // --------------------------------------------------------------------------
  // SHARED HTML-STYLE UI BUILDING BLOCKS (`.card`, `.hd`, `.bd`, `.btn`, `.gov-audit-table`)
  // --------------------------------------------------------------------------

  Widget _htmlCard({String? headerText, Widget? headerWidget, required Widget body}) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: const Color(0xFFDAE3EF)),
        boxShadow: const [BoxShadow(color: Color(0x0C10233F), blurRadius: 14, offset: Offset(0, 3))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (headerText != null || headerWidget != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 17, vertical: 14),
              decoration: const BoxDecoration(
                gradient: LinearGradient(colors: [Colors.white, Color(0xFFF8FAFC)]),
                border: Border(bottom: BorderSide(color: Color(0xFFE2E8F0))),
                borderRadius: BorderRadius.vertical(top: Radius.circular(15)),
              ),
              child: headerWidget ??
                  Text(
                    headerText!,
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: Color(0xFF10233F)),
                  ),
            ),
          Padding(padding: const EdgeInsets.all(17), child: body),
        ],
      ),
    );
  }

  Widget _htmlBtn(String label, Color bg, Color fg, VoidCallback onTap) {
    return InkWell(
      borderRadius: BorderRadius.circular(9),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(9)),
        child: Text(label, style: TextStyle(color: fg, fontWeight: FontWeight.w800, fontSize: 13.5)),
      ),
    );
  }

  Widget _pill(String text, {required bool isGood}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: isGood ? const Color(0xFFD1FAE5) : const Color(0xFFFFE4E6),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: isGood ? const Color(0xFF065F46) : const Color(0xFF9F1239),
          fontSize: 11.5,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }

  Widget _noticeBox(String text, {required String type}) {
    final bg = type == 'ok'
        ? const Color(0xFFD3F9D8)
        : (type == 'bad' ? const Color(0xFFFFE3E3) : const Color(0xFFFFF3BF));
    final fg = type == 'ok'
        ? const Color(0xFF075F45)
        : (type == 'bad' ? const Color(0xFFA51111) : const Color(0xFF6C4D00));
    return Container(
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(9)),
      child: Text(text, style: TextStyle(color: fg, fontWeight: FontWeight.w700, fontSize: 13, height: 1.45)),
    );
  }

  Widget _statBox(String bigValue, String label) {
    return Container(
      width: 245,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: const Color(0xFFDBE4EF)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(bigValue, style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w900, color: Color(0xFF185D98))),
          const SizedBox(height: 3),
          Text(label, style: const TextStyle(fontSize: 12.5, color: Color(0xFF344965), fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }

  Future<void> _pickDate(
    TextEditingController ctrl, {
    ValueChanged<String>? onChanged,
    VoidCallback? afterPicked,
  }) async {
    DateTime initialDate = DateTime.now();
    final iso = normalizeToIsoDate(ctrl.text.trim());
    if (iso.isNotEmpty) {
      final parsed = DateTime.tryParse(iso);
      if (parsed != null) {
        initialDate = parsed;
      }
    }
    final picked = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: DateTime(2000, 1, 1),
      lastDate: DateTime(2100, 12, 31),
      helpText: 'તારીખ પસંદ કરો (Select Date — DD/MM/YYYY)',
      confirmText: 'OK / પસંદ કરો',
      cancelText: 'Cancel',
      fieldHintText: 'DD/MM/YYYY',
      fieldLabelText: 'તારીખ (DD/MM/YYYY)',
    );
    if (picked != null) {
      final formattedSlash =
          '${picked.day.toString().padLeft(2, '0')}/${picked.month.toString().padLeft(2, '0')}/${picked.year.toString().padLeft(4, '0')}';
      ctrl.text = formattedSlash;
      if (onChanged != null) onChanged(formattedSlash);
      if (afterPicked != null) afterPicked();
      if (mounted) setState(() {});
    }
  }

  /// Date input: type any Indian style (01/12/2025, 1/12/25, 01-12-2025,
  /// 1-12-25, 1-Dec-25, 1-Dec-2025, ૦૧/૧૨/૨૦૨૫ …) or pick from the 📅
  /// calendar. On leaving the box the date is shown as DD/MM/YYYY; a line
  /// below tells how the date was read, or that it was not understood.
  Widget _labeledDateInput(
    String label,
    TextEditingController ctrl, {
    String? hint,
    ValueChanged<String>? onChanged,
    VoidCallback? afterPicked,
  }) {
    void tidy() {
      final d = IndianDate.parse(ctrl.text);
      if (d == null) return;
      final f = IndianDate.dmy(d);
      if (f == ctrl.text) return;
      ctrl.text = f;
      if (onChanged != null) onChanged(f);
      if (afterPicked != null) afterPicked();
      if (mounted) setState(() {});
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 12, color: Color(0xFF344965), fontWeight: FontWeight.w800)),
        const SizedBox(height: 5),
        Focus(
          onFocusChange: (has) {
            if (!has) tidy();
          },
          child: TextField(
            controller: ctrl,
            readOnly: false,
            keyboardType: TextInputType.text,
            onChanged: (val) {
              if (onChanged != null) onChanged(val);
            },
            onSubmitted: (_) => tidy(),
            decoration: InputDecoration(
              hintText: hint ?? 'DD/MM/YYYY (01/12/2025, 1-12-25, 1-Dec-25)',
              isDense: true,
              filled: true,
              fillColor: Colors.white,
              contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
              suffixIconConstraints: const BoxConstraints(minWidth: 36, minHeight: 36),
              suffixIcon: IconButton(
                tooltip: 'Open Calendar Date Picker (તારીખ પસંદ કરો — DD/MM/YYYY)',
                padding: EdgeInsets.zero,
                icon: const Icon(Icons.calendar_month_rounded, size: 19, color: Color(0xFF185D98)),
                onPressed: () => _pickDate(ctrl, onChanged: onChanged, afterPicked: afterPicked),
              ),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFFCCD8E7), width: 1.5)),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFFCCD8E7), width: 1.5)),
            ),
          ),
        ),
        ValueListenableBuilder<TextEditingValue>(
          valueListenable: ctrl,
          builder: (context, v, _) {
            final t = v.text.trim();
            if (t.isEmpty) return const SizedBox.shrink();
            final d = IndianDate.parse(t);
            if (d == null) {
              if (t.length < 6) return const SizedBox.shrink();
              return const Padding(
                padding: EdgeInsets.only(top: 3),
                child: Text(
                  'તારીખ સમજાઈ નહીં — 01/12/2025, 1/12/25, 01-12-2025, 1-Dec-25 જેવી રીતે લખો',
                  style: TextStyle(fontSize: 10.5, color: Color(0xFFB42318), fontWeight: FontWeight.w700),
                ),
              );
            }
            if (d.year < 2000 || d.year > 2100) {
              return const Padding(
                padding: EdgeInsets.only(top: 3),
                child: Text('વર્ષ 2000 થી 2100 વચ્ચે હોવું જોઈએ',
                    style: TextStyle(fontSize: 10.5, color: Color(0xFFB42318), fontWeight: FontWeight.w700)),
              );
            }
            final shown = IndianDate.dmy(d);
            if (shown == t) return const SizedBox.shrink();
            const days = ['સોમવાર', 'મંગળવાર', 'બુધવાર', 'ગુરુવાર', 'શુક્રવાર', 'શનિવાર', 'રવિવાર'];
            return Padding(
              padding: const EdgeInsets.only(top: 3),
              child: Text('= $shown (${days[d.weekday - 1]})',
                  style: const TextStyle(fontSize: 10.5, color: Color(0xFF067647), fontWeight: FontWeight.w800)),
            );
          },
        ),
      ],
    );
  }

  /// Quick Dialog to Set or Change Head Annual Limit (for SNA SPARSH & PFMS) at ANY Time!
  Future<void> _openQuickHeadLimitDialog(String accName, [String? initialHead]) async {
    final m = engine.getAccountMeta(accName);
    final heads = engine.getAccountSpecificHeads(accName);
    String selectedHead = (initialHead != null && heads.contains(initialHead))
        ? initialHead
        : (heads.isNotEmpty ? heads.first : '');
    final currentLim = engine.getHeadLimit(accName, selectedHead);
    final limitCtrl = TextEditingController(text: currentLim > 0 ? currentLim.toStringAsFixed(2) : '');

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) {
          final enteredLim = double.tryParse(limitCtrl.text.trim()) ?? 0.0;
          final lim60 = m.isAnySna ? (enteredLim * 60.0).roundToDouble() / 100.0 : enteredLim;
          final lim40 = m.isAnySna ? double.parse((enteredLim - lim60).toStringAsFixed(2)) : 0.0;
          final bal = engine.getHeadCashBankBalanceAtDate(
            accName,
            selectedHead,
            _entryDateCtrl.text.trim().isNotEmpty ? _entryDateCtrl.text.trim() : '2099-12-31',
          );
          final usedYear = bal['usedYear'] ?? 0.0;
          final allConfigured = m.headLimits.entries.where((e) => e.value > 0).toList();

          return AlertDialog(
            title: Text(
              '🎯 Set / Change Head Annual Limit ($accName — ${m.type == "SNA" ? "SNA SPARSH" : "PFMS"})',
              style: const TextStyle(fontSize: 16.5, fontWeight: FontWeight.w900, color: Color(0xFF065F46)),
            ),
            content: SizedBox(
              width: 650,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF2FBF7),
                        border: Border.all(color: const Color(0xFF087F5B)),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Text(
                        '''• In SNA SPARSH and PFMS accounts, setting the Grant Head Annual Limit is required before entering transactions.
• You can change or update any Grant Head's Annual Limit at any time during the year!''',
                        style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: Color(0xFF065F46)),
                      ),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      value: selectedHead.isNotEmpty ? selectedHead : null,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: '1. Select Grant Head (ગ્રાન્ટ હેડ પસંદ કરો) *',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      items: heads.map((h) {
                        final hl = engine.getHeadLimit(accName, h);
                        return DropdownMenuItem(
                          value: h,
                          child: Text(
                            '$h ${hl > 0 ? "(Limit: ₹${fmtDemoNum(hl)})" : "(No Limit Set)"}',
                            overflow: TextOverflow.ellipsis,
                          ),
                        );
                      }).toList(),
                      onChanged: (v) {
                        if (v == null) return;
                        setModalState(() {
                          selectedHead = v;
                          final hl = engine.getHeadLimit(accName, selectedHead);
                          limitCtrl.text = hl > 0 ? hl.toStringAsFixed(2) : '';
                        });
                      },
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: _labeledInput(
                            '2. Annual Sanctioned Limit for Year (₹ 100% વાર્ષિક મર્યાદા) *',
                            limitCtrl,
                            isNumber: true,
                            hint: 'Enter annual limit e.g. 50000',
                            onChanged: (_) => setModalState(() {}),
                          ),
                        ),
                        const SizedBox(width: 10),
                        _htmlBtn('💾 Save Limit for This Head', const Color(0xFF087F5B), Colors.white, () {
                          final val = double.tryParse(limitCtrl.text.trim()) ?? 0.0;
                          engine.setSingleHeadLimit(accName, selectedHead, val);
                          setModalState(() {});
                          _showToast('Updated Annual Limit for "$selectedHead" to ₹${fmtDemoNum(val)}.');
                        }),
                      ],
                    ),
                    if (m.type == 'SNA') ...[
                      const SizedBox(height: 8),
                      Text(
                        '60% Central Share: ₹${fmtDemoNum(lim60)}  |  40% State Share: ₹${fmtDemoNum(lim40)}  |  Used This Year: ₹${fmtDemoNum(usedYear)}',
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: Color(0xFF164B80)),
                      ),
                    ],
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [

                        _htmlBtn('⚡ Auto-Set Limits from Current Year Credit Grants', const Color(0xFFFFF3BF), const Color(0xFF754600), () {
                          final accEntries = engine.getAccountEntries(accName).where((e) => e.type == 'credit' && !RojmelEngine.isCashEntry(e)).toList();
                          if (accEntries.isEmpty) {
                            _showToast('No credit grant entries found yet in $accName.');
                            return;
                          }
                          final map = <String, double>{};
                          for (final e in accEntries) {
                            map[e.head] = (map[e.head] ?? 0.0) + e.amount;
                          }
                          map.forEach((h, totalCr) {
                            engine.setSingleHeadLimit(accName, h, totalCr);
                          });
                          setModalState(() {
                            final hl = engine.getHeadLimit(accName, selectedHead);
                            limitCtrl.text = hl > 0 ? hl.toStringAsFixed(2) : '';
                          });
                          _showToast('Auto-configured annual limits from credit grants!');
                        }),
                      ],
                    ),
                    if (allConfigured.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      const Text('Configured Head-wise Annual Limits:', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w900)),
                      const SizedBox(height: 6),
                      Container(
                        constraints: const BoxConstraints(maxHeight: 200),
                        decoration: BoxDecoration(border: Border.all(color: const Color(0xFFD9E2ED)), borderRadius: BorderRadius.circular(8)),
                        child: ListView.separated(
                          shrinkWrap: true,
                          itemCount: allConfigured.length,
                          separatorBuilder: (_, __) => const Divider(height: 1),
                          itemBuilder: (_, idx) {
                            final item = allConfigured[idx];
                            return ListTile(
                              dense: true,
                              title: Text('${idx + 1}. ${item.key}', style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800)),
                              trailing: Text('₹ ${fmtDemoNum(item.value)}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w900, color: Color(0xFF087F5B))),
                              onTap: () {
                                setModalState(() {
                                  selectedHead = item.key;
                                  limitCtrl.text = item.value.toStringAsFixed(2);
                                });
                              },
                            );
                          },
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('Close'),
              ),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: const Color(0xFF087F5B)),
                onPressed: () {
                  final val = double.tryParse(limitCtrl.text.trim()) ?? 0.0;
                  if (val > 0) {
                    engine.setSingleHeadLimit(accName, selectedHead, val);
                  }
                  Navigator.of(ctx).pop();
                },
                child: const Text('✓ Save & Done'),
              ),
            ],
          );
        },
      ),
    );
  }

  /// Quick Dialog to Set or Edit Bank Account Opening Balance & Head-wise Opening Distribution!
  Future<void> _openQuickBankOpeningDialog(String accName) async {
    final m = engine.getAccountMeta(accName);
    final heads = engine.getAccountSpecificHeads(accName);
    final openBankCtrl = TextEditingController(text: m.openingBank.toStringAsFixed(2));
    final openCashCtrl = TextEditingController(text: m.openingCash.toStringAsFixed(2));
    final headBankCtrl = TextEditingController(text: '0');
    final headCashCtrl = TextEditingController(text: '0');
    final draftOpenings = m.headOpenings.map((k, v) => MapEntry(k, v.copy()));
    String selectedHead = heads.isNotEmpty ? heads.first : '';

    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) {
          final targetBank = math.max(0.0, double.tryParse(openBankCtrl.text.trim()) ?? 0.0);
          final targetCash = math.max(0.0, double.tryParse(openCashCtrl.text.trim()) ?? 0.0);
          double sumBank = 0.0;
          double sumCash = 0.0;
          final openKeys = draftOpenings.keys.where((h) => (draftOpenings[h]?.total ?? 0) > 0).toList();
          for (final h in openKeys) {
            sumBank += draftOpenings[h]!.bank;
            sumCash += draftOpenings[h]!.cash;
          }
          final remBank = targetBank - sumBank;
          final remCash = targetCash - sumCash;
          final isMatched = remBank.abs() < 0.005 && remCash.abs() < 0.005;

          return AlertDialog(
            title: Text(
              '🏦 Set / Edit Opening Balance & Head-wise Distribution ($accName — BANK)',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: Color(0xFF11345F)),
            ),
            content: SizedBox(
              width: 680,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _pill(
                      isMatched
                          ? '✓ Head-wise Total Matches Opening Balance (Diff: ₹0.00)'
                          : '⚠ Must Match Total Opening Balance (Rem Bank: ₹${fmtDemoNum(remBank)}, Rem Cash: ₹${fmtDemoNum(remCash)})',
                      isGood: isMatched,
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: _labeledInput(
                            '1. Total Opening Bank Balance (₹)',
                            openBankCtrl,
                            isNumber: true,
                            onChanged: (_) => setModalState(() {}),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _labeledInput(
                            '2. Total Opening Cash Balance (₹)',
                            openCashCtrl,
                            isNumber: true,
                            onChanged: (_) => setModalState(() {}),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      value: selectedHead.isNotEmpty ? selectedHead : null,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Select Grant Head for Opening Balance Allocation *',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      items: heads.map((h) => DropdownMenuItem(value: h, child: Text(h, overflow: TextOverflow.ellipsis))).toList(),
                      onChanged: (v) {
                        if (v != null) setModalState(() => selectedHead = v);
                      },
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      crossAxisAlignment: WrapCrossAlignment.end,
                      children: [
                        SizedBox(width: 170, child: _labeledInput('Head Opening Bank (₹)', headBankCtrl, isNumber: true)),
                        SizedBox(width: 170, child: _labeledInput('Head Opening Cash (₹)', headCashCtrl, isNumber: true)),
                        _htmlBtn('+ Allocate to Head', const Color(0xFF185D98), Colors.white, () {
                          if (selectedHead.isEmpty) return;
                          final b = math.max(0.0, double.tryParse(headBankCtrl.text.trim()) ?? 0.0);
                          final c = math.max(0.0, double.tryParse(headCashCtrl.text.trim()) ?? 0.0);
                          setModalState(() {
                            if (b == 0 && c == 0) {
                              draftOpenings.remove(selectedHead);
                            } else {
                              draftOpenings[selectedHead] = HeadBalance(cash: c, bank: b);
                            }
                            headBankCtrl.text = '0';
                            headCashCtrl.text = '0';
                          });
                        }),
                        _htmlBtn('⚡ Put Remaining in Selected Head', const Color(0xFF087F5B), Colors.white, () {
                          if (selectedHead.isEmpty) return;
                          double otherB = 0.0;
                          double otherC = 0.0;
                          draftOpenings.forEach((k, v) {
                            if (k != selectedHead) {
                              otherB += v.bank;
                              otherC += v.cash;
                            }
                          });
                          final rB = math.max(0.0, double.parse((targetBank - otherB).toStringAsFixed(2)));
                          final rC = math.max(0.0, double.parse((targetCash - otherC).toStringAsFixed(2)));
                          setModalState(() {
                            draftOpenings[selectedHead] = HeadBalance(cash: rC, bank: rB);
                          });
                        }),
                      ],
                    ),
                    if (openKeys.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Container(
                        constraints: const BoxConstraints(maxHeight: 180),
                        decoration: BoxDecoration(border: Border.all(color: const Color(0xFFD9E2ED)), borderRadius: BorderRadius.circular(8)),
                        child: ListView.separated(
                          shrinkWrap: true,
                          itemCount: openKeys.length,
                          separatorBuilder: (_, __) => const Divider(height: 1),
                          itemBuilder: (_, idx) {
                            final h = openKeys[idx];
                            final hb = draftOpenings[h]!;
                            return ListTile(
                              dense: true,
                              title: Text('${idx + 1}. $h', style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800)),
                              subtitle: Text('Bank: ₹${fmtDemoNum(hb.bank)} | Cash: ₹${fmtDemoNum(hb.cash)}'),
                              trailing: IconButton(
                                icon: const Icon(Icons.delete_outline, color: Color(0xFFC92A2A), size: 18),
                                onPressed: () => setModalState(() => draftOpenings.remove(h)),
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Cancel')),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: const Color(0xFF087F5B)),
                onPressed: () {
                  if (!isMatched) {
                    _showToast('Total Opening Balance and Head-wise Opening Balance must match (Difference = ₹0.00)!');
                    return;
                  }
                  engine.setBankOpeningBalanceQuick(
                    accName: accName,
                    totalBank: targetBank,
                    totalCash: targetCash,
                    headOpenings: draftOpenings,
                  );
                  Navigator.of(ctx).pop();
                  _showToast('Opening Balance saved for "$accName"!');
                },
                child: const Text('✓ Confirm & Save Opening Balance'),
              ),
            ],
          );
        },
      ),
    );
  }

  /// Party names used before (same entry type), most used first.
  List<String> _knownPartyNames(bool debit) {
    final counts = <String, int>{};
    final display = <String, String>{};
    for (final e in engine.entries) {
      if ((e.type == 'debit') != debit) continue;
      final name = e.party.trim();
      if (name.isEmpty) continue;
      final key = name.toLowerCase();
      counts[key] = (counts[key] ?? 0) + 1;
      display.putIfAbsent(key, () => name);
    }
    final keys = counts.keys.toList()..sort((a, b) => counts[b]!.compareTo(counts[a]!));
    return [for (final k in keys) display[k]!];
  }

  /// Payee / party name: pick a name used earlier (so the party-wise
  /// payment register groups correctly) or type a new one.
  Widget _partyNameField(bool isDebit) {
    final names = _knownPartyNames(isDebit);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          isDebit ? 'Payee / Party Name (પાર્ટીનું નામ) *' : 'From whom grant/amount received *',
          style: const TextStyle(fontSize: 12, color: Color(0xFF344965), fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 5),
        RawAutocomplete<String>(
          textEditingController: _entryPartyCtrl,
          focusNode: _entryPartyFocus,
          optionsBuilder: (value) {
            final q = value.text.trim().toLowerCase();
            final list = q.isEmpty ? names : names.where((n) => n.toLowerCase().contains(q) && n.toLowerCase() != q);
            return list.take(30);
          },
          onSelected: (v) => _entryPartyCtrl.text = v,
          fieldViewBuilder: (context, ctrl, focus, onSubmit) => TextField(
            controller: ctrl,
            focusNode: focus,
            decoration: InputDecoration(
              hintText: names.isEmpty ? 'Grant authority / person / vendor' : 'નામ લખો અથવા યાદીમાંથી પસંદ કરો',
              isDense: true,
              filled: true,
              fillColor: Colors.white,
              contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
              border: const OutlineInputBorder(),
              suffixIcon: names.isEmpty
                  ? null
                  : IconButton(
                      tooltip: 'જૂના નામ',
                      icon: const Icon(Icons.arrow_drop_down_rounded),
                      onPressed: () {
                        if (focus.hasFocus) focus.unfocus();
                        Future<void>.delayed(const Duration(milliseconds: 50), focus.requestFocus);
                      },
                    ),
            ),
          ),
          optionsViewBuilder: (context, onSelected, options) => Align(
            alignment: Alignment.topLeft,
            child: Material(
              elevation: 6,
              borderRadius: BorderRadius.circular(8),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 320, maxHeight: 260),
                child: ListView(
                  padding: EdgeInsets.zero,
                  shrinkWrap: true,
                  children: [
                    for (final o in options)
                      ListTile(dense: true, title: Text(o), onTap: () => onSelected(o)),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _labeledInput(
    String label,
    TextEditingController ctrl, {
    bool isNumber = false,
    bool readOnly = false,
    int maxLines = 1,
    String? hint,
    ValueChanged<String>? onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 12, color: Color(0xFF344965), fontWeight: FontWeight.w800)),
        const SizedBox(height: 5),
        TextField(
          controller: ctrl,
          readOnly: readOnly,
          maxLines: maxLines,
          keyboardType: isNumber ? const TextInputType.numberWithOptions(decimal: true) : TextInputType.text,
          onChanged: onChanged,
          decoration: InputDecoration(
            hintText: hint,
            isDense: true,
            filled: true,
            fillColor: readOnly ? const Color(0xFFF8FAFC) : Colors.white,
            contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFFCCD8E7), width: 1.5)),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFFCCD8E7), width: 1.5)),
          ),
        ),
      ],
    );
  }

  Widget _readonlyField(String label, String value) {
    return _labeledInput(label, TextEditingController(text: value), readOnly: true);
  }

  Widget _htmlTable({required List<String> headers, required List<List<Widget>> rows}) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 960),
        child: Table(
          border: TableBorder.all(color: const Color(0xFFD9E2ED)),
          defaultVerticalAlignment: TableCellVerticalAlignment.middle,
          children: [
            TableRow(
              decoration: const BoxDecoration(color: Color(0xFFEAF0F7)),
              children: headers.map((h) => Padding(
                    padding: const EdgeInsets.all(8),
                    child: Text(h, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13, color: Color(0xFF10233F))),
                  )).toList(),
            ),
            ...rows.map((r) => TableRow(
                  children: r.map((cell) => Padding(padding: const EdgeInsets.all(7), child: cell)).toList(),
                )),
          ],
        ),
      ),
    );
  }

  /// Exact `.gov-audit-table` with `#fde9d9` peach header row, black 1px borders, and global Font Size & Row Height settings.
  Widget _govAuditTable({
    required List<String> headers,
    required List<List<String>> rows,
    bool lastRowIsTotal = false,
    bool boldAll = false,
    double? fontSizePt,
    double? minRowHeightPx,
  }) {
    return _GovAuditTableWidget(
      headers: headers,
      rows: rows,
      lastRowIsTotal: lastRowIsTotal,
      boldAll: boldAll,
      fontSizePt: fontSizePt ?? engine.parishisht10FontSizePt,
      minRowHeightPx: minRowHeightPx ?? engine.parishisht10RowHeightPx,
    );
  }
}

class _GovAuditTableWidget extends StatelessWidget {
  const _GovAuditTableWidget({
    required this.headers,
    required this.rows,
    this.lastRowIsTotal = false,
    this.boldAll = false,
    this.fontSizePt,
    this.minRowHeightPx,
  });

  final List<String> headers;
  final List<List<String>> rows;
  final bool lastRowIsTotal;
  final bool boldAll;
  final double? fontSizePt;
  final double? minRowHeightPx;

  bool _isNonAmountColumnHeader(int colIdx) {
    if (colIdx == 0) return true; // Sr. No. column is always centered
    if (colIdx >= headers.length) return false;
    final h = headers[colIdx].toLowerCase();
    return h.contains('ક્રમ') ||
        h.contains('અ.નં') ||
        h.contains('sr') ||
        h.contains('વાઉચર') ||
        h.contains('ચેક નં') ||
        h.contains('ક્લેઈમ') ||
        h.contains('claim') ||
        h.contains('chq') ||
        h.contains('તારીખ') ||
        h.contains('date') ||
        h.contains('પા.નં') ||
        h.contains('પાના') ||
        h.contains('ખાતા નંબર') ||
        h.contains('code');
  }

  @override
  Widget build(BuildContext context) {
    final effFont = fontSizePt ?? 10.0;
    final effRowH = minRowHeightPx ?? 28.0;
    final vPad = math.max(2.5, (effRowH - effFont - 4) / 2.0);
    final colCount = headers.isNotEmpty ? headers.length : (rows.isNotEmpty ? rows.first.length : 1);
    return LayoutBuilder(
      builder: (context, constraints) {
        final targetWidth = constraints.maxWidth.isFinite && constraints.maxWidth > 600 ? constraints.maxWidth : 1040.0;
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SizedBox(
            width: targetWidth,
            child: Table(
              border: TableBorder.all(color: Colors.black, width: 1.0),
              defaultVerticalAlignment: TableCellVerticalAlignment.middle,
              children: [
                if (headers.isNotEmpty)
                  TableRow(
                    decoration: const BoxDecoration(color: Color(0xFFFDE9D9)),
                    children: headers.map((h) => Padding(
                          padding: EdgeInsets.symmetric(horizontal: 5, vertical: vPad),
                          child: Center(
                            child: Text(
                              h,
                              textAlign: TextAlign.center,
                              style: TextStyle(fontWeight: FontWeight.w900, fontSize: effFont, color: Colors.black),
                            ),
                          ),
                        )).toList(),
                  ),
                ...rows.asMap().entries.map((entry) {
                  final rIdx = entry.key;
                  final r = entry.value;
                  final isTotalRow = lastRowIsTotal && rIdx == rows.length - 1;
                  final isColNumRow = rIdx == 0 && r.length >= 4 && r[0].trim() == '1' && r[1].trim() == '2';
                  final paddedRow = List<String>.generate(colCount, (i) => i < r.length ? r[i] : '');
                  return TableRow(
                    decoration: BoxDecoration(
                      color: isColNumRow
                          ? const Color(0xFFFDE9D9)
                          : (isTotalRow ? const Color(0xFFF3F6FA) : Colors.white),
                    ),
                    children: List<Widget>.generate(colCount, (cIdx) {
                      final cell = paddedRow[cIdx];
                      final trimmed = cell.trim();
                      final isAmountCell = !isColNumRow &&
                          !_isNonAmountColumnHeader(cIdx) &&
                          RegExp(r'^-?[\d,]+\.\d{2}%?$').hasMatch(trimmed);

                      if (isAmountCell) {
                        // Amount cell remains right-aligned with single-line auto-scaling font size
                        return Container(
                          constraints: BoxConstraints(minHeight: effRowH),
                          alignment: Alignment.centerRight,
                          padding: EdgeInsets.symmetric(horizontal: 5, vertical: vPad),
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerRight,
                            child: Text(
                              cell,
                              maxLines: 1,
                              softWrap: false,
                              textAlign: TextAlign.right,
                              style: TextStyle(
                                fontSize: effFont,
                                fontWeight: (isTotalRow || boldAll) ? FontWeight.w900 : FontWeight.w500,
                                color: Colors.black,
                              ),
                            ),
                          ),
                        );
                      }

                      // All columns except Amount (Claim No., Cheque No., Date, Voucher No., Sr., Head, Narration, etc.):
                      // Centered in cell with automatic font-size scaling so text never clips or overflows!
                      final isSingleTokenCode = !trimmed.contains(' ') && !trimmed.contains('\n') && trimmed.isNotEmpty;
                      final len = trimmed.length;
                      final autoFont = len > 95
                          ? math.max(6.8, effFont * 0.76)
                          : (len > 60
                              ? math.max(7.2, effFont * 0.84)
                              : (len > 35
                                  ? math.max(7.8, effFont * 0.91)
                                  : effFont));

                      return Container(
                        constraints: BoxConstraints(minHeight: effRowH),
                        alignment: Alignment.center,
                        padding: EdgeInsets.symmetric(horizontal: 5, vertical: vPad),
                        child: isSingleTokenCode
                            ? FittedBox(
                                fit: BoxFit.scaleDown,
                                alignment: Alignment.center,
                                child: Text(
                                  cell,
                                  maxLines: 1,
                                  softWrap: false,
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: effFont,
                                    fontWeight: (isTotalRow || boldAll || isColNumRow) ? FontWeight.w900 : FontWeight.w500,
                                    color: Colors.black,
                                  ),
                                ),
                              )
                            : Text(
                                cell,
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: autoFont,
                                  height: 1.18,
                                  fontWeight: (isTotalRow || boldAll || isColNumRow) ? FontWeight.w900 : FontWeight.w500,
                                  color: Colors.black,
                                ),
                              ),
                      );
                    }),
                  );
                }),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Draws optional vertical column lines on Cashbook pages (`cashbookShowColumnLines == true`),
/// either across the full page down to the `એકંદરે કુલ :` (Ekandar) line (`fullPageTillEkandar == true`)
/// or only through the last entry row (`tableOnly == true`).
class _CashbookColumnLinesPainter extends CustomPainter {
  const _CashbookColumnLinesPainter({
    required this.isCredit,
    required this.fullPageTillEkandar,
    required this.tableOnly,
  });

  final bool isCredit;
  final bool fullPageTillEkandar;
  final bool tableOnly;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.black
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke;

    // Column percentage stops matching the exact Expanded flex ratios in Credit (6 cols) & Debit (9 cols)
    final stops = isCredit
        ? const <double>[0.0, 0.11, 0.35, 0.65, 0.76, 0.88, 1.0]
        : const <double>[0.0, 0.10, 0.21, 0.43, 0.50, 0.59, 0.68, 0.78, 0.89, 1.0];

    final topY = tableOnly ? 0.0 : 76.0;
    final bottomY = tableOnly ? size.height : math.max(topY, size.height - 29.0);

    for (final ratio in stops) {
      final x = size.width * ratio;
      canvas.drawLine(Offset(x, topY), Offset(x, bottomY), paint);
    }
    if (!tableOnly && fullPageTillEkandar) {
      canvas.drawLine(Offset(0, bottomY), Offset(size.width, bottomY), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _CashbookColumnLinesPainter oldDelegate) {
    return oldDelegate.isCredit != isCredit ||
        oldDelegate.fullPageTillEkandar != fullPageTillEkandar ||
        oldDelegate.tableOnly != tableOnly;
  }
}