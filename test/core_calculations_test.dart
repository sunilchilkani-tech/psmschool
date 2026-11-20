import 'package:flutter_test/flutter_test.dart';
import 'package:pmshri_attendance/models/models.dart';
import 'package:pmshri_attendance/screens/supabase_rojmel_screen.dart';
import 'package:pmshri_attendance/services/attendance_lifecycle.dart';

void main() {
  group('AttendanceLifecycle rules', () {
    test('June admission appears in June; July admission starts in August', () {
      expect(
        AttendanceLifecycle.includeInMonthlyRegister(
          registerMonth: DateTime(2026, 6, 1),
          enrolledOn: DateTime(2026, 6, 15),
        ),
        isTrue,
      );
      expect(
        AttendanceLifecycle.includeInMonthlyRegister(
          registerMonth: DateTime(2026, 7, 1),
          enrolledOn: DateTime(2026, 7, 5),
        ),
        isFalse,
      );
      expect(
        AttendanceLifecycle.includeInMonthlyRegister(
          registerMonth: DateTime(2026, 8, 1),
          enrolledOn: DateTime(2026, 7, 5),
        ),
        isTrue,
      );
    });

    test('Leaving student stays in leaving month through leaving_date only', () {
      final win = AttendanceLifecycle.calculationWindow(
        registerMonth: DateTime(2026, 9, 1),
        enrolledOn: DateTime(2026, 6, 10),
        leftOn: DateTime(2026, 9, 12),
      );
      expect(win, isNotNull);
      expect(win!.start, DateTime(2026, 9, 1));
      expect(win.end, DateTime(2026, 9, 12));
      expect(
        AttendanceLifecycle.includeInMonthlyRegister(
          registerMonth: DateTime(2026, 10, 1),
          enrolledOn: DateTime(2026, 6, 10),
          leftOn: DateTime(2026, 9, 12),
        ),
        isFalse,
      );
    });

    test('Percentage handles zero open days safely', () {
      expect(AttendanceLifecycle.percentage(presentDays: 0, eligibleOpenDays: 0), 0);
      expect(AttendanceLifecycle.percentage(presentDays: 15, eligibleOpenDays: 20), 75.0);
    });
  });

  group('Result calculation models', () {
    test('SubjectMarks handles split, satrantAbsent, and directTotal', () {
      const normal = SubjectMarks(patrakA: 32, satrant: 36, swaAdhyayan: 18);
      expect(normal.total, 86);

      const absent = SubjectMarks(
        patrakA: 32,
        satrant: 36,
        swaAdhyayan: 18,
        satrantAbsent: true,
      );
      expect(absent.total, 50);

      const direct = SubjectMarks(directTotal: 78, directMode: true);
      expect(direct.usesDirectTotal, isTrue);
      expect(direct.total, 78);
    });

    test('generateRandom40Sentences sums to exact target', () {
      final list = generateRandom40Sentences(320, 10);
      expect(list.length, 40);
      expect(list.fold<int>(0, (a, b) => a + b), 320);
      expect(list.every((v) => v >= 0 && v <= 10), isTrue);
    });

    test('ResultStudentRow.vvAvgBothSem rounds and respects studiedInSem2', () {
      final active = ResultStudentRow(
        sheetRow: 2,
        roll: '1',
        name: 'Test Student',
        gr: '101',
        dd: '01',
        mm: '01',
        yyyy: '2015',
        category: 'OBC',
        presentDays: 100,
        sem1: {},
        sem2: {},
        vv1: 301,
        vv2: 302,
        studiedInSem2: true,
      );
      expect(active.vvAvgBothSem, 302);

      final leftInSem2 = ResultStudentRow(
        sheetRow: 3,
        roll: '2',
        name: 'Left Student',
        gr: '102',
        dd: '01',
        mm: '01',
        yyyy: '2015',
        category: 'OBC',
        presentDays: 100,
        sem1: {},
        sem2: {},
        vv1: 300,
        vv2: 0,
        studiedInSem2: false,
      );
      expect(leftInSem2.vvAvgBothSem, 300);
    });
  });

  group('RojmelEngine calculations & FY carry-forward', () {
    test('BANK account balances, audit checks, and FY carry-forward', () {
      final engine = RojmelEngine();
      engine.initializeEmptySchool(
        registeredSchoolName: 'Test Primary School',
        registeredUdiseCode: '24100100101',
      );
      engine.setBankOpeningBalanceQuick(
        accName: 'SMCE',
        totalBank: 10000.0,
        totalCash: 500.0,
        headOpenings: {'Composite Grant': HeadBalance(cash: 500.0, bank: 10000.0)},
      );

      final crErr = engine.addTransactionV06(
        account: 'SMCE',
        head: 'Composite Grant',
        date: '10/06/2025',
        type: 'credit',
        rawNarration: 'Grant received',
        expenseShort: '',
        amount: 5000.0,
        medium: 'Bank',
        party: 'SSA',
      );
      expect(crErr, isNull);

      final drErr = engine.addTransactionV06(
        account: 'SMCE',
        head: 'Composite Grant',
        date: '15/06/2025',
        type: 'debit',
        rawNarration: 'Stationery purchase',
        expenseShort: 'Stationery',
        amount: 3000.0,
        medium: 'Bank',
        party: 'ABC Traders',
        txn: 'CHQ001',
        clearDate: '16/06/2025',
      );
      expect(drErr, isNull);

      final audit = engine.runCalculationAudit('SMCE');
      expect(audit.every((item) => item.passed), isTrue);

      engine.deleteAccountAllEntries(
        'SMCE',
        carryForwardClosingAsOpening: true,
        nextFinancialYear: '2026-27',
      );
      final nextOpen = engine.getAccountOpening('SMCE');
      expect(nextOpen.bank, 12000.0);
      expect(nextOpen.cash, 500.0);
    });

    test('SNA_PURE 60:40 split integrity and fresh FY limit preservation', () {
      final engine = RojmelEngine();
      engine.initializeEmptySchool(
        registeredSchoolName: 'Test Primary School',
        registeredUdiseCode: '24100100101',
      );
      engine.setSingleHeadLimit('SNA SPARSH', 'Composite Grant', 50000.0);

      final crErr = engine.addTransactionV06(
        account: 'SNA SPARSH',
        head: 'Composite Grant',
        date: '10/07/2025',
        type: 'credit',
        rawNarration: 'Grant credited',
        expenseShort: '',
        amount: 10000.0,
        medium: 'SNA SPARSH',
        party: 'SSA',
      );
      expect(crErr, isNull);

      final drErr = engine.addTransactionV06(
        account: 'SNA SPARSH',
        head: 'Composite Grant',
        date: '12/07/2025',
        type: 'debit',
        rawNarration: 'Lab equipment',
        expenseShort: 'Lab',
        amount: 10000.0,
        medium: 'SNA SPARSH',
        party: 'Science Mart',
        sna60Claim: 'CLM60',
        sna60Date: '13/07/2025',
        sna40Claim: 'CLM40',
        sna40Date: '13/07/2025',
      );
      expect(drErr, isNull);

      final audit = engine.runCalculationAudit('SNA SPARSH');
      expect(audit.every((item) => item.passed), isTrue);

      // SNA SPARSH starts next FY with 0 opening balance and same annual head limit
      engine.deleteAccountAllEntries(
        'SNA SPARSH',
        carryForwardClosingAsOpening: false,
        nextFinancialYear: '2026-27',
      );
      expect(engine.getAccountOpening('SNA SPARSH').total, 0.0);
      expect(engine.getHeadLimit('SNA SPARSH', 'Composite Grant'), 50000.0);
    });

    test('SNA SPARSH rapid multi-head entries produce sequential non-duplicate vouchers and support Admin split edit', () {
      final engine = RojmelEngine();
      engine.initializeEmptySchool(
        registeredSchoolName: 'Test School',
        registeredUdiseCode: '24100100101',
      );
      engine.setSingleHeadLimit('SNA SPARSH', 'Music', 100000.0);
      engine.setSingleHeadLimit('SNA SPARSH', 'Computer', 100000.0);

      for (final item in [
        ('Music', 'Ketan', 16000.0, 'C1', 'C2'),
        ('Music', 'Ketan', 15238.0, 'C3', 'C4'),
        ('Computer', 'Sejal', 16000.0, 'C1', 'C2'),
        ('Computer', 'Sejal', 16000.0, 'C3', 'C4'),
      ]) {
        expect(
          engine.addTransactionV06(
            account: 'SNA SPARSH',
            head: item.$1,
            date: '10/12/2025',
            type: 'credit',
            rawNarration: 'Grant',
            expenseShort: '',
            amount: item.$3,
            medium: 'SNA SPARSH',
            party: 'SSA',
          ),
          isNull,
        );
        expect(
          engine.addTransactionV06(
            account: 'SNA SPARSH',
            head: item.$1,
            date: '10/12/2025',
            type: 'debit',
            rawNarration: 'Payment',
            expenseShort: 'Salary',
            amount: item.$3,
            medium: 'SNA SPARSH',
            party: item.$2,
            sna60Claim: item.$4,
            sna60Date: '29/12/2025',
            sna40Claim: item.$5,
            sna40Date: '29/12/2025',
          ),
          isNull,
        );
      }

      final debits = engine.getSortedEntries(engine.getAccountEntries('SNA SPARSH')).where((e) => e.type == 'debit').toList();
      expect(debits.map((e) => e.voucher).toList(), ['1', '1', '2', '2', '3', '3', '4', '4']);
      expect(debits.map((e) => e.id).toSet().length, 8);

      // Admin splits Voucher 1's 40% leg into separate Voucher 2 -> next continues 3, 4, 5
      final leg40 = debits[1].copy()
        ..voucher = '2'
        ..manualVoucher = '2'
        ..splitGroup = '';
      expect(engine.updateEntry(leg40), isNull);
      final afterSplit = engine.getSortedEntries(engine.getAccountEntries('SNA SPARSH')).where((e) => e.type == 'debit').toList();
      expect(afterSplit.map((e) => e.voucher).toList(), ['1', '2', '3', '3', '4', '4', '5', '5']);
    });

    test('Freeze Audited FY carries forward BANK balances and preserves SNA limits at 0 opening', () {
      final engine = RojmelEngine();
      engine.initializeEmptySchool(
        registeredSchoolName: 'Test School',
        registeredUdiseCode: '24100100101',
      );
      engine.setBankOpeningBalanceQuick(
        accName: 'SMCE',
        totalBank: 4000.0,
        totalCash: 200.0,
        headOpenings: {'General': HeadBalance(cash: 200.0, bank: 4000.0)},
      );
      expect(
        engine.addTransactionV06(
          account: 'SMCE',
          head: 'General',
          date: '10/06/2025',
          type: 'debit',
          rawNarration: 'Books',
          expenseShort: 'Books',
          amount: 1000.0,
          medium: 'Bank',
          party: 'Store',
          txn: 'CHQ1',
          clearDate: '12/06/2025',
        ),
        isNull,
      );
      final snap = engine.buildFrozenFyArchiveSnapshot('SMCE', targetFy: '2025-26');
      expect((snap['totals'] as Map)['closeBank'], 3000.0);
      engine.applyFyCarryForwardAfterArchive('SMCE', frozenFy: '2025-26', nextFinancialYear: '2026-27');
      expect(engine.getAccountOpening('SMCE').bank, 3000.0);
      expect(engine.getAccountOpening('SMCE').cash, 200.0);
      expect(engine.isAccountFyLocked('SMCE', '2025-26'), isTrue);
      expect(
        engine.addTransactionV06(
          account: 'SMCE',
          head: 'General',
          date: '15/06/2025',
          type: 'credit',
          rawNarration: 'Blocked',
          expenseShort: '',
          amount: 500.0,
          medium: 'Bank',
          party: 'SSA',
        ),
        isNotNull,
      );

      // SNA SPARSH freeze: 0 opening, same annual limits preserved
      engine.setSingleHeadLimit('SNA SPARSH', 'TLM', 15000.0);
      engine.applyFyCarryForwardAfterArchive('SNA SPARSH', frozenFy: '2025-26', nextFinancialYear: '2026-27');
      expect(engine.getAccountOpening('SNA SPARSH').total, 0.0);
      expect(engine.getHeadLimit('SNA SPARSH', 'TLM'), 15000.0);
    });
  });
}