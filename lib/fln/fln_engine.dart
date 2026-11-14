// FLN 130-question paper engine (native Dart port of the HTML generator).
//
// Every rule of the original generator is kept (digit patterns, zero
// positions, carry / borrow levels, exact division, word problems and the
// Q130 formula). Fixes over the HTML version:
// - 3A / 3B now always have three distractors (the HTML left one empty).
// - WP2 can no longer produce a subtrahend larger than the minuend.
// - Options are always distinct, never negative and never equal to the answer.
// - An empty selection is reported instead of silently printing all 130.
// - Papers are reproducible from a set code (seed), so the answer key can be
//   printed again later for the same papers.

import 'dart:math' as math;

import 'fln_data.dart';

// ---------------------------------------------------------------------------
// Gujarati helpers
// ---------------------------------------------------------------------------

const List<String> _gujDigits = <String>['૦', '૧', '૨', '૩', '૪', '૫', '૬', '૭', '૮', '૯'];

String flnGujDigits(Object value) => '$value'.replaceAllMapped(
      RegExp('[0-9]'),
      (m) => _gujDigits[int.parse(m.group(0)!)],
    );

String flnNumberToGujaratiWords(int number) {
  final n = number.abs();
  if (n == 0) return 'શૂન્ય';
  final parts = <String>[];
  final crore = n ~/ 10000000;
  final lakh = (n % 10000000) ~/ 100000;
  final thousand = (n % 100000) ~/ 1000;
  final hundred = (n % 1000) ~/ 100;
  final lastTwo = n % 100;
  if (crore > 0 && crore <= 99) parts.add('${kFlnGujWords1to99[crore]} કરોડ');
  if (lakh > 0) parts.add('${kFlnGujWords1to99[lakh]} લાખ');
  if (thousand > 0) parts.add('${kFlnGujWords1to99[thousand]} હજાર');
  if (hundred > 0) parts.add(kFlnGujHundreds[hundred]);
  if (lastTwo > 0) parts.add(kFlnGujWords1to99[lastTwo]);
  return parts.join(' ').replaceAll(RegExp(r'\s+'), ' ').trim();
}

FlnSectionMeta flnSectionOf(String sec) =>
    kFlnSections.firstWhere((m) => m.sec == sec, orElse: () => kFlnSections.first);

// ---------------------------------------------------------------------------
// Engine configuration (the HTML "Rule Settings" tab)
// ---------------------------------------------------------------------------

class FlnEngineConfig {
  const FlnEngineConfig({
    this.strictCarry = true,
    this.finalProfile = true,
    this.q130Additive = true,
  });

  /// Enforce the level-by-level carry / borrow rules (Q60–Q104).
  final bool strictCarry;

  /// true = QUESTION final.xlsx digit profile (1-digit to 4-digit),
  /// false = 3000_FLN profile (2-digit to 5-digit).
  final bool finalProfile;

  /// true = ((n1-n2)-(n1-n2)/n3) × (1+n4) + n5 (QUESTION final.xlsx),
  /// false = ((n1-n2)-(n1-n2)/n3) × n4 + n5.
  final bool q130Additive;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'strictCarry': strictCarry,
        'finalProfile': finalProfile,
        'q130Additive': q130Additive,
      };

  factory FlnEngineConfig.fromJson(Map<String, dynamic> j) => FlnEngineConfig(
        strictCarry: j['strictCarry'] != false,
        finalProfile: j['finalProfile'] != false,
        q130Additive: j['q130Additive'] != false,
      );
}

// ---------------------------------------------------------------------------
// Random numbers
// ---------------------------------------------------------------------------

class _Rng {
  _Rng(int seed) : _r = math.Random(seed);
  final math.Random _r;
  int randInt(int min, int max) => max <= min ? min : min + _r.nextInt(max - min + 1);
  double next() => _r.nextDouble();
}

/// 32-bit integer multiply that gives the same result on the VM and the web.
int _imul(int a, int b) {
  final ah = (a >> 16) & 0xffff;
  final al = a & 0xffff;
  final bh = (b >> 16) & 0xffff;
  final bl = b & 0xffff;
  return (al * bl + ((((ah * bl + al * bh) & 0xffff) << 16) & 0xffffffff)) & 0xffffffff;
}

/// Mulberry32 step: deterministic value in [0, 1) for a seed.
double flnSeededRand(int seed) {
  var t = (seed + 0x6D2B79F5) & 0xffffffff;
  t = _imul(t ^ (t >> 15), t | 1);
  t = (t ^ ((t + _imul(t ^ (t >> 7), t | 61)) & 0xffffffff)) & 0xffffffff;
  return ((t ^ (t >> 14)) & 0xffffffff) / 4294967296.0;
}

int flnSeededRandInt(int seed, int min, int max) =>
    min + (flnSeededRand(seed) * (max - min + 1)).floor();

List<T> flnSeededShuffle<T>(List<T> items, int seedBase) {
  final copy = List<T>.of(items);
  for (var i = copy.length - 1; i > 0; i--) {
    final j = flnSeededRandInt(seedBase + i * 97, 0, i);
    final t = copy[i];
    copy[i] = copy[j];
    copy[j] = t;
  }
  return copy;
}

// ---------------------------------------------------------------------------
// Number helpers
// ---------------------------------------------------------------------------

bool _hasZero(int n) => '${n.abs()}'.contains('0');
bool _noZero(int n) => !_hasZero(n);

int _numberWithExactZeros(_Rng r, int d, List<int> zeroPositions) {
  if (d == 1) return r.randInt(1, 9);
  final digits = List<int>.filled(d, 0);
  final zeros = zeroPositions.toSet();
  for (var posFromUnits = 0; posFromUnits < d; posFromUnits++) {
    digits[d - 1 - posFromUnits] = zeros.contains(posFromUnits) ? 0 : r.randInt(1, 9);
  }
  return int.parse(digits.join());
}

int _numberNoZero(_Rng r, int d) => _numberWithExactZeros(r, d, const <int>[]);

int _numberRequireZero(_Rng r, int d) {
  if (d <= 1) return r.randInt(1, 9);
  final digits = <int>[for (var i = 0; i < d; i++) r.randInt(1, 9)];
  final numZeros = d >= 4 && r.next() < 0.25 ? 2 : 1;
  for (var z = 0; z < numZeros; z++) {
    digits[r.randInt(1, d - 1)] = 0;
  }
  return int.parse(digits.join());
}

const int _maxAttempts = 4000;

class _GenFailure implements Exception {
  _GenFailure(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Keeps numbers unique inside one paper (per question family).
class _Pool {
  final q1 = <int>{};
  final q2 = <int>{};
  final q3 = <int>{};
  final add = <int>{};
  final sub = <int>{};
  final mulMultipliers = <int>{};
  final mulNumbers = <int>{};
  final divDivisors = <int>{};
  final divNumbers = <int>{};

  bool acquireAll(List<(Set<int>, int)> requests) {
    final taken = <(Set<int>, int)>[];
    for (final req in requests) {
      if (req.$1.contains(req.$2)) {
        for (final t in taken) {
          t.$1.remove(t.$2);
        }
        return false;
      }
      req.$1.add(req.$2);
      taken.add(req);
    }
    return true;
  }

  bool acquireTwoQ3(int a, int b) {
    if (a < 10 && b < 10) return true;
    return acquireAll(<(Set<int>, int)>[(q3, a), (q3, b)]);
  }

  bool acquireThreeQ3(int a, int b, int c) {
    if (a < 10 && c < 10) return true;
    return acquireAll(<(Set<int>, int)>[(q3, a), (q3, b), (q3, c)]);
  }
}

// ---------------------------------------------------------------------------
// One generated paper (raw numbers, like the QUESTIONS sheet row)
// ---------------------------------------------------------------------------

class FlnPaper {
  FlnPaper({
    required this.q1a,
    required this.q1b,
    required this.q2a,
    required this.q2b,
    required this.placeValue,
    required this.q3a,
    required this.q3b,
    required this.q3c,
    required this.q3d,
    required this.q3e,
    required this.addition,
    required this.subtraction,
    required this.multiplication,
    required this.division,
    required this.puzzles,
  });

  final List<int> q1a;
  final List<int> q1b;
  final List<String> q2a;
  final List<String> q2b;
  final String placeValue;
  final List<String> q3a;
  final List<String> q3b;
  final List<String> q3c;
  final List<int> q3d;
  final List<int> q3e;
  final List<int> addition;
  final List<int> subtraction;
  final List<int> multiplication;
  final List<int> division;
  final List<int> puzzles;
}

const List<List<int>> _q1aZeroPos = <List<int>>[
  <int>[], <int>[], <int>[], <int>[0, 1], <int>[1, 2], <int>[2, 3], <int>[3, 4], <int>[4, 5],
];
const List<List<int>> _q1bZeroPos = <List<int>>[
  <int>[], <int>[], <int>[], <int>[0], <int>[1], <int>[2], <int>[3], <int>[5],
];

class FlnGenerator {
  FlnGenerator._(this._r, this._cfg);
  final _Rng _r;
  final FlnEngineConfig _cfg;
  final _Pool _pool = _Pool();

  /// Generates one paper. Retries internally when a random draw runs out of
  /// unique numbers (very rare).
  static FlnPaper generate(int seed, FlnEngineConfig cfg) {
    Object? last;
    for (var attempt = 0; attempt < 250; attempt++) {
      try {
        return FlnGenerator._(_Rng(seed * 7 + attempt * 104729), cfg)._paper();
      } on _GenFailure catch (e) {
        last = e;
      }
    }
    throw StateError('FLN paper could not be generated: $last');
  }

  FlnPaper _paper() {
    final q1a = <int>[];
    final q1b = <int>[];
    for (var d = 1; d <= 8; d++) {
      q1a.add(_unique(() => _numberWithExactZeros(_r, d, _q1aZeroPos[d - 1]), _pool.q1, 'Q1A'));
    }
    for (var d = 1; d <= 8; d++) {
      q1b.add(_unique(() => _numberWithExactZeros(_r, d, _q1bZeroPos[d - 1]), _pool.q1, 'Q1B'));
    }
    final fin = _cfg.finalProfile;
    final q2aPat = fin
        ? const <(int, List<int>)>[(1, <int>[]), (2, <int>[]), (3, <int>[]), (3, <int>[0]), (3, <int>[1])]
        : const <(int, List<int>)>[(2, <int>[]), (3, <int>[]), (3, <int>[0]), (4, <int>[]), (4, <int>[1])];
    final q2bPat = fin
        ? const <(int, List<int>)>[(1, <int>[]), (2, <int>[]), (3, <int>[1]), (4, <int>[2]), (4, <int>[])]
        : const <(int, List<int>)>[(2, <int>[]), (3, <int>[]), (3, <int>[0, 1]), (4, <int>[]), (4, <int>[0, 1])];
    final q2a = _q2Side(q2aPat);
    final q2b = _q2Side(q2bPat);
    final digits = <int>[1, 2, 3, 4, 5, 6, 7, 8, 9];
    for (var i = digits.length - 1; i > 0; i--) {
      final j = _r.randInt(0, i);
      final t = digits[i];
      digits[i] = digits[j];
      digits[j] = t;
    }
    final placeValue = digits.take(8).join();

    final q3a = _q3AbSide(isB: false);
    final q3b = _q3AbSide(isB: true);
    final q3c = _q3c();
    final q3d = _q3de(before: true);
    final q3e = _q3de(before: false);

    return FlnPaper(
      q1a: q1a,
      q1b: q1b,
      q2a: q2a,
      q2b: q2b,
      placeValue: placeValue,
      q3a: q3a,
      q3b: q3b,
      q3c: q3c,
      q3d: q3d,
      q3e: q3e,
      addition: _addition(),
      subtraction: _subtraction(),
      multiplication: _multiplication(),
      division: _division(),
      puzzles: _puzzles(),
    );
  }

  int _unique(int Function() draw, Set<int> pool, String label) {
    for (var a = 0; a < _maxAttempts; a++) {
      final n = draw();
      if (pool.add(n)) return n;
    }
    throw _GenFailure('Could not generate $label');
  }

  List<String> _q2Side(List<(int, List<int>)> pattern) {
    final subs = <String>[];
    for (final p in pattern) {
      final nums = <int>[];
      for (var i = 0; i < 5; i++) {
        var ok = false;
        for (var a = 0; a < _maxAttempts; a++) {
          final n = _numberWithExactZeros(_r, p.$1, p.$2);
          if (nums.contains(n)) continue;
          if (p.$1 == 1 || _pool.q2.add(n)) {
            nums.add(n);
            ok = true;
            break;
          }
        }
        if (!ok) throw _GenFailure('Could not generate Q2 d=${p.$1}');
      }
      subs.add(nums.join(', '));
    }
    return subs;
  }

  List<String> _q3AbSide({required bool isB}) {
    final pat = _cfg.finalProfile
        ? (isB
            ? const <(int, List<int>)>[(1, <int>[]), (2, <int>[]), (3, <int>[1]), (4, <int>[2]), (4, <int>[])]
            : const <(int, List<int>)>[(1, <int>[]), (2, <int>[]), (3, <int>[]), (4, <int>[]), (4, <int>[0])])
        : const <(int, List<int>)>[(2, <int>[]), (3, <int>[]), (3, <int>[]), (4, <int>[]), (5, <int>[])];
    final subs = <String>[];
    for (final p in pat) {
      final nums = <int>[];
      for (var a = 0; a < _maxAttempts && nums.length < 3; a++) {
        final v = _numberWithExactZeros(_r, p.$1, p.$2);
        if (nums.contains(v)) continue;
        if (p.$1 == 1 || _pool.q3.add(v)) nums.add(v);
      }
      if (nums.length < 3) throw _GenFailure('Could not generate Q3AB d=${p.$1}');
      subs.add(nums.join(', '));
    }
    return subs;
  }

  List<String> _q3c() {
    final out = <String>[];
    void tryAdd(int Function() leftDraw, {bool checkNoZero = false}) {
      for (var a = 0; a < _maxAttempts; a++) {
        final l = leftDraw();
        if (checkNoZero && !(_noZero(l) && _noZero(l + 1) && _noZero(l + 2))) continue;
        if (_pool.acquireThreeQ3(l, l + 1, l + 2)) {
          out.add('$l ___ ${l + 2}');
          return;
        }
      }
      throw _GenFailure('Could not generate Q3C');
    }

    if (_cfg.finalProfile) {
      final left1 = _r.randInt(1, 7);
      out.add('$left1 ___ ${left1 + 2}');
      tryAdd(() => _r.randInt(1, 9) * 10 + _r.randInt(2, 8) - 1, checkNoZero: true);
      tryAdd(() => _r.randInt(1, 8) * 10 + 9);
      tryAdd(() => _r.randInt(1, 9) * 100 + _r.randInt(1, 9) * 10);
      tryAdd(() => _r.randInt(1, 9) * 100 + _r.randInt(1, 8) * 10 + 8);
    } else {
      tryAdd(() => _r.randInt(1, 9) * 10 + _r.randInt(2, 8) - 1, checkNoZero: true);
      tryAdd(() => _r.randInt(1, 8) * 10 + 9);
      tryAdd(() => _r.randInt(1, 9) * 100 + _r.randInt(0, 9) * 10 + _r.randInt(2, 8) - 1);
      tryAdd(() => _r.randInt(1, 9) * 100 + _r.randInt(0, 9) * 10);
      tryAdd(() => _r.randInt(1, 9) * 1000 + _r.randInt(0, 9) * 100 + _r.randInt(0, 9) * 10 + _r.randInt(2, 8) - 1);
    }
    return out;
  }

  List<int> _q3de({required bool before}) {
    final r = _r;
    final List<int Function()> gens;
    if (_cfg.finalProfile) {
      gens = before
          ? <int Function()>[
              () => r.randInt(2, 9),
              () => r.randInt(1, 9) * 10 + r.randInt(2, 9),
              () => r.randInt(1, 9) * 10 + 2,
              () => r.randInt(1, 9) * 100 + r.randInt(1, 9) * 10 + r.randInt(2, 9),
              () => r.randInt(1, 9) * 100 + r.randInt(1, 9) * 10 + 1,
            ]
          : <int Function()>[
              () => r.randInt(1, 8),
              () => r.randInt(1, 9) * 10 + r.randInt(1, 8),
              () => r.randInt(1, 9) * 10 + 9,
              () => r.randInt(1, 9) * 100 + r.randInt(1, 9) * 10 + 8,
              () => r.randInt(1, 9) * 100 + r.randInt(1, 9) * 10 + r.randInt(1, 7),
            ];
    } else {
      gens = before
          ? <int Function()>[
              () => r.randInt(1, 9) * 10 + r.randInt(2, 9),
              () => r.randInt(1, 9) * 10,
              () => r.randInt(1, 9) * 100 + r.randInt(0, 9) * 10 + r.randInt(2, 9),
              () => r.randInt(1, 9) * 100 + r.randInt(0, 9) * 10 + 1,
              () => r.randInt(1, 9) * 1000 + r.randInt(0, 9) * 100 + r.randInt(0, 9) * 10 + r.randInt(2, 9),
            ]
          : <int Function()>[
              () => r.randInt(1, 9) * 10 + r.randInt(1, 8),
              () => r.randInt(1, 9) * 10 + 9,
              () => r.randInt(1, 9) * 100 + r.randInt(0, 9) * 10 + r.randInt(1, 8),
              () => r.randInt(1, 9) * 100 + r.randInt(0, 9) * 10,
              () => r.randInt(1, 9) * 1000 + r.randInt(0, 9) * 100 + r.randInt(0, 9) * 10 + r.randInt(1, 8),
            ];
    }
    final nums = <int>[];
    for (var i = 0; i < 5; i++) {
      var ok = false;
      for (var a = 0; a < _maxAttempts; a++) {
        final given = gens[i]();
        final ans = before ? given - 1 : given + 1;
        if (_pool.acquireTwoQ3(given, ans)) {
          nums.add(given);
          ok = true;
          break;
        }
      }
      if (!ok) throw _GenFailure('Q3${before ? 'D' : 'E'}_${i + 1} failed');
    }
    return nums;
  }

  bool _addRule(int level, int a, int b) {
    if (!_cfg.strictCarry) return true;
    final u1 = a % 10, u2 = b % 10;
    final t1 = (a ~/ 10) % 10, t2 = (b ~/ 10) % 10;
    final h1 = (a ~/ 100) % 10, h2 = (b ~/ 100) % 10;
    final uC = (u1 + u2) >= 10 ? 1 : 0;
    final tC = (t1 + t2 + uC) >= 10 ? 1 : 0;
    final hC = (h1 + h2 + tC) >= 10 ? 1 : 0;
    switch (level) {
      case 0:
        return a + b < 10;
      case 1:
        return a + b > 10;
      case 2:
        return uC == 0 && tC == 0;
      case 3:
        return uC == 1 && tC == 0;
      case 4:
        return uC == 0 && tC == 1;
      case 5:
        return uC == 1 && tC == 1;
      case 6:
        return uC == 0 && tC == 0 && hC == 0;
      case 7:
      case 8:
        return tC == 1 || uC == 1;
      case 9:
        return hC == 1 || tC == 1;
      default:
        return true;
    }
  }

  static const List<int> _addDigits = <int>[1, 1, 2, 2, 2, 2, 3, 3, 3, 3, 4, 4];

  List<int> _addition() {
    final flat = <int>[];
    for (var i = 0; i < 12; i++) {
      final d = _addDigits[i];
      final needZero = i >= 10;
      var ok = false;
      for (var a = 0; a < _maxAttempts; a++) {
        final n1 = needZero ? _numberRequireZero(_r, d) : _numberNoZero(_r, d);
        final n2 = needZero ? _numberRequireZero(_r, d) : _numberNoZero(_r, d);
        if (n1 == n2 || !_addRule(i, n1, n2)) continue;
        if (_pool.acquireAll(<(Set<int>, int)>[(_pool.add, n1), (_pool.add, n2)])) {
          flat.addAll(<int>[n1, n2]);
          ok = true;
          break;
        }
      }
      if (!ok) throw _GenFailure('Addition L${i + 1} failed');
    }
    for (final spec in const <(int, int)>[(5, 3), (6, 3)]) {
      var ok = false;
      for (var a = 0; a < _maxAttempts; a++) {
        final nums = <int>[for (var k = 0; k < spec.$2; k++) _numberRequireZero(_r, spec.$1)];
        if (nums.toSet().length != spec.$2) continue;
        if (_pool.acquireAll(<(Set<int>, int)>[for (final n in nums) (_pool.add, n)])) {
          flat.addAll(nums);
          ok = true;
          break;
        }
      }
      if (!ok) throw _GenFailure('Addition L13/14 failed');
    }
    var ok = false;
    for (var a = 0; a < _maxAttempts; a++) {
      final nums = <int>[for (final d in const <int>[3, 4, 5, 6]) _numberRequireZero(_r, d)];
      if (nums.toSet().length != 4) continue;
      if (_pool.acquireAll(<(Set<int>, int)>[for (final n in nums) (_pool.add, n)])) {
        flat.addAll(nums);
        ok = true;
        break;
      }
    }
    if (!ok) throw _GenFailure('Addition L15 failed');
    return flat;
  }

  bool _subRule(int level, int big, int small) {
    if (!_cfg.strictCarry) return true;
    final u1 = big % 10, u2 = small % 10;
    final t1 = (big ~/ 10) % 10, t2 = (small ~/ 10) % 10;
    final h1 = (big ~/ 100) % 10, h2 = (small ~/ 100) % 10;
    final uB = u1 < u2;
    final tB = (t1 - (uB ? 1 : 0)) < t2;
    switch (level) {
      case 0:
        return big > small;
      case 1:
        return !uB;
      case 2:
        return uB;
      case 3:
        return !uB && !tB && h1 >= h2;
      case 4:
        return uB && !tB && h1 >= h2;
      case 5:
        return !uB && tB;
      case 6:
        return uB && tB;
      case 7:
        final s1 = '$big', s2 = '$small';
        if (s1.length < 4 || s2.length < 4) return false;
        for (var k = 0; k < 4; k++) {
          if (int.parse(s1[k]) < int.parse(s2[k])) return false;
        }
        return true;
      case 8:
      case 9:
        return uB || tB;
      default:
        return true;
    }
  }

  static const List<int> _subDigits = <int>[1, 2, 2, 3, 3, 3, 3, 4, 4, 4, 5, 5, 5, 6, 6];

  List<int> _subtraction() {
    final flat = <int>[];
    for (var i = 0; i < 15; i++) {
      final d = _subDigits[i];
      final needZero = i >= 10;
      var ok = false;
      for (var a = 0; a < _maxAttempts; a++) {
        final x = needZero ? _numberRequireZero(_r, d) : _numberNoZero(_r, d);
        final y = needZero ? _numberRequireZero(_r, d) : _numberNoZero(_r, d);
        if (x == y) continue;
        final big = math.max(x, y), small = math.min(x, y);
        if (!_subRule(i, big, small)) continue;
        if (_pool.acquireAll(<(Set<int>, int)>[(_pool.sub, big), (_pool.sub, small)])) {
          flat.addAll(<int>[big, small]);
          ok = true;
          break;
        }
      }
      if (!ok) throw _GenFailure('Subtraction L${i + 1} failed');
    }
    return flat;
  }

  static const List<(int, String)> _mulLevels = <(int, String)>[
    (1, 'small'), (1, 'small'),
    (2, 'small'), (2, 'small'), (2, 'small'),
    (3, 'small'), (3, 'small'),
    (2, 'd2'), (2, 'd2'),
    (3, 'd2'), (3, 'd2'),
    (4, 'small'), (4, 'd2'),
    (3, 'd3'), (4, 'd3'),
  ];

  bool _mulRule(int level, int mc, int mult) {
    if (!_cfg.strictCarry) return true;
    final u = mc % 10, t = (mc ~/ 10) % 10, h = (mc ~/ 100) % 10;
    switch (level) {
      case 0:
        return mc * mult <= 10;
      case 1:
        return mc * mult > 10;
      case 2:
        return u * mult < 10 && t * mult < 10;
      case 3:
      case 4:
      case 6:
        return u * mult >= 10;
      case 5:
        return u * mult < 10 && t * mult < 10 && h * mult < 10;
      default:
        return true;
    }
  }

  List<int> _multiplication() {
    final byLevel = List<List<int>?>.filled(15, null);
    for (final i in const <int>[0, 2, 5, 1, 3, 4, 6, 11, 7, 8, 9, 10, 12, 13, 14]) {
      final lvl = _mulLevels[i];
      final needZero = i >= 13;
      var ok = false;
      for (var a = 0; a < _maxAttempts; a++) {
        final mc = needZero ? _numberRequireZero(_r, lvl.$1) : _numberNoZero(_r, lvl.$1);
        final mult = lvl.$2 == 'small'
            ? _r.randInt(2, 9)
            : (lvl.$2 == 'd2' ? _numberNoZero(_r, 2) : _numberNoZero(_r, 3));
        if (mc == mult || !_mulRule(i, mc, mult)) continue;
        if (_pool.acquireAll(<(Set<int>, int)>[(_pool.mulMultipliers, mult), (_pool.mulNumbers, mc)])) {
          byLevel[i] = <int>[mc, mult];
          ok = true;
          break;
        }
      }
      if (!ok) throw _GenFailure('Multiplication L${i + 1} failed');
    }
    return <int>[for (final pair in byLevel) ...pair!];
  }

  static const List<int> _divDigits = <int>[1, 1, 2, 2, 2, 3, 3, 4, 4, 4, 4, 4, 5, 5, 5];

  List<int> _division() {
    final flat = <int>[];
    for (var i = 0; i < 15; i++) {
      final dd = _divDigits[i];
      final lowD = i < 5 ? 2 : 11;
      final highD = i < 5 ? 9 : 19;
      final needZero = i >= 9;
      final low = math.pow(10, dd - 1).toInt();
      final high = math.pow(10, dd).toInt() - 1;
      var ok = false;
      for (var a = 0; a < _maxAttempts; a++) {
        final divisor = _r.randInt(lowD, highD);
        final qLow = math.max(1, (low / divisor).ceil());
        final qHigh = high ~/ divisor;
        if (qHigh < qLow) continue;
        final dividend = divisor * _r.randInt(qLow, qHigh);
        if ('$dividend'.length != dd) continue;
        if (needZero ? !_hasZero(dividend) : !_noZero(dividend)) continue;
        if (i < 5 ||
            _pool.acquireAll(<(Set<int>, int)>[(_pool.divDivisors, divisor), (_pool.divNumbers, dividend)])) {
          flat.addAll(<int>[dividend, divisor]);
          ok = true;
          break;
        }
      }
      if (!ok) {
        final divisor = _r.randInt(lowD, highD);
        final qLow = math.max(1, (low / divisor).ceil());
        final qHigh = math.max(qLow, high ~/ divisor);
        flat.addAll(<int>[divisor * _r.randInt(qLow, qHigh), divisor]);
      }
    }
    return flat;
  }

  int _hard() => _r.randInt(105, 999);

  List<int> _puzzles() {
    final r = _r;
    final out = <int>[];
    // WP1 (Q120)
    out.addAll(<int>[_hard(), _hard()]);
    // WP2 (Q121): the minuend always leaves room for a 3-digit subtrahend.
    final a2 = r.randInt(130, 999);
    out.addAll(<int>[a2, r.randInt(100, a2 - 15)]);
    // WP3 (Q122)
    out.addAll(<int>[r.randInt(2, 9), r.randInt(2, 9)]);
    // WP4 (Q123)
    final d4 = r.randInt(2, 9);
    out.addAll(<int>[d4 * r.randInt(12, 99), d4]);
    // WP5 (Q124)
    out.addAll(<int>[_hard(), _hard(), r.randInt(15, 299)]);
    // WP6 (Q125)
    final b6 = r.randInt(100, 350), c6 = r.randInt(100, 350);
    out.addAll(<int>[b6 + c6 + r.randInt(25, 280), b6, c6]);
    // WP7 (Q126)
    var done = false;
    for (var att = 0; att < _maxAttempts && !done; att++) {
      final a = r.randInt(2, 9), m = r.randInt(2, 9), prod = a * m;
      final divs = <int>[for (var d = 2; d <= 9; d++) if (prod % d == 0 && d != a && d != m) d];
      if (divs.isEmpty) continue;
      out.addAll(<int>[a, m, divs[r.randInt(0, divs.length - 1)]]);
      done = true;
    }
    if (!done) out.addAll(const <int>[6, 3, 2]);
    // WP8 (Q127)
    final a8 = _hard(), b8 = _hard();
    out.addAll(<int>[a8, b8, r.randInt(100, a8 + b8 - 25)]);
    // WP9 (Q128)
    final n91 = _hard(), n92 = _hard();
    out.addAll(<int>[n91, n92, r.randInt(100, n91 + n92 - 25), r.randInt(2, 9)]);
    // WP10 (Q129)
    done = false;
    for (var att = 0; att < _maxAttempts && !done; att++) {
      final n1 = _hard(), n2 = _hard();
      final n3 = r.randInt(100, n1 + n2 - 20);
      final n4 = r.randInt(2, 9);
      final total = (n1 + n2 - n3) * n4;
      final divs = <int>[for (var d = 2; d <= 9; d++) if (total % d == 0) d];
      if (divs.isEmpty) continue;
      out.addAll(<int>[n1, n2, n3, n4, divs[r.randInt(0, divs.length - 1)]]);
      done = true;
    }
    if (!done) out.addAll(const <int>[242, 323, 515, 2, 4]);
    // WP11 (Q130)
    final n3 = r.randInt(2, 9);
    final diff = n3 * r.randInt(12, 95);
    final n2 = r.randInt(110, 550);
    out.addAll(<int>[n2 + diff, n2, n3, r.randInt(2, 9), r.randInt(25, 650)]);
    return out;
  }
}

// ---------------------------------------------------------------------------
// 130 expanded questions with answers and three distractors
// ---------------------------------------------------------------------------

class FlnItem {
  FlnItem({
    required this.qNo,
    required this.sec,
    required this.code,
    required this.prompt,
    required this.questionVal,
    required this.answer,
    required this.distractors,
    this.steps = const <String>[],
  });

  final int qNo;
  final String sec;
  final String code;

  /// Text printed in the question card (instruction already in the banner).
  final String prompt;

  /// Short form used in the answer key.
  final String questionVal;
  final String answer;
  final List<String> distractors;

  /// Worked steps (whole numbers only) shown in the answer copy.
  final List<String> steps;
}

List<int> _distinctInts(int ans, List<int> opts, {int min = 0}) {
  final seen = <int>{ans};
  final out = <int>[];
  for (var i = 0; i < opts.length; i++) {
    var c = math.max(min, opts[i]);
    var step = i + 1;
    while (seen.contains(c)) {
      c += step;
      step++;
    }
    seen.add(c);
    out.add(c);
  }
  return out;
}

List<int> _distractors1A(int dIdx, int n, int seed) {
  if (dIdx == 0) return <int>[n < 9 ? n + 1 : 6, n <= 7 ? n + 2 : 5, n > 1 ? n - 1 : 4];
  if (dIdx == 1) return <int>[n <= 89 ? n + 10 : n - 15, n >= 20 ? n - 10 : n + 15, n <= 94 ? n + 5 : n - 25];
  if (dIdx == 2) {
    final delta = flnSeededRandInt(seed, 15, 30);
    return <int>[
      n >= 110 ? n - 10 : n + 15,
      n <= 989 ? n + 10 : n - 15,
      n > 969 ? n - delta : (n < 130 ? n + delta : n - delta),
    ];
  }
  final step = math.pow(10, dIdx - 1).toInt();
  final maxVal = math.pow(10, dIdx + 1).toInt() - 1;
  final lowVal = math.pow(10, dIdx).toInt();
  return <int>[
    n <= maxVal - step ? n + step : n - (step * 1.5).floor(),
    n >= lowVal + step ? n - step : n + (step * 1.5).floor(),
    n <= maxVal - step * 5 ? n + step * 5 : n - (step * 2.5).floor(),
  ];
}

List<int> _distractors1B(int dIdx, int n) {
  if (dIdx == 0) return <int>[n < 9 ? n + 1 : 6, n > 1 ? n - 1 : 4, n <= 7 ? n + 2 : 5];
  if (dIdx == 1) return <int>[n >= 20 ? n - 10 : n + 15, n <= 94 ? n + 5 : n - 25, n <= 89 ? n + 10 : n - 15];
  if (dIdx == 2) return <int>[n <= 989 ? n + 10 : n - 15, n >= 110 ? n - 10 : n + 15, n <= 949 ? n + 50 : n - 25];
  return _distractors1A(dIdx, n, 0);
}

int _reversedDigits(int n) => int.parse('$n'.split('').reversed.join());

List<int> _listOf(String s) =>
    s.split(',').map((x) => int.tryParse(x.trim()) ?? 0).toList();

/// Expands a paper into the 130 printable questions.
List<FlnItem> flnExpandPaper(FlnPaper paper, FlnEngineConfig cfg, int paperNo) {
  final items = <FlnItem>[];
  final pSeed = paperNo * 1000;
  String s(Object v) => '$v';

  // Q1–Q8: number → Gujarati words
  for (var i = 0; i < 8; i++) {
    final qNo = i + 1;
    final num = paper.q1a[i];
    final ans = flnNumberToGujaratiWords(num);
    final ds = _distinctInts(num, _distractors1A(i, num, pSeed + qNo), min: 1);
    final opts = <String>[];
    for (final d in ds) {
      var w = flnNumberToGujaratiWords(d);
      if (w == ans || opts.contains(w)) w = flnNumberToGujaratiWords(d + 2);
      opts.add(w);
    }
    items.add(FlnItem(qNo: qNo, sec: '1A', code: '1A${i + 1}', prompt: s(num), questionVal: s(num), answer: ans, distractors: opts));
  }

  // Q9–Q16: Gujarati words → number
  for (var i = 0; i < 8; i++) {
    final qNo = 9 + i;
    final num = paper.q1b[i];
    final words = flnNumberToGujaratiWords(num);
    final ds = _distinctInts(num, _distractors1B(i, num), min: 1);
    items.add(FlnItem(qNo: qNo, sec: '1B', code: '1B${i + 1}', prompt: words, questionVal: words, answer: s(num), distractors: ds.map(s).toList()));
  }

  // Q17–Q21 ascending, Q22–Q26 descending
  for (var i = 0; i < 5; i++) {
    final list = paper.q2a[i];
    final v = _listOf(list)..sort();
    items.add(FlnItem(
      qNo: 17 + i,
      sec: '2A',
      code: '2A${i + 1}',
      prompt: list,
      questionVal: list,
      answer: v.join(', '),
      distractors: <String>[
        <int>[v[0], v[1], v[2], v[4], v[3]].join(', '),
        <int>[v[0], v[2], v[1], v[3], v[4]].join(', '),
        <int>[v[4], v[1], v[2], v[3], v[0]].join(', '),
      ],
    ));
  }
  for (var i = 0; i < 5; i++) {
    final list = paper.q2b[i];
    final l = _listOf(list)..sort((a, b) => b.compareTo(a));
    items.add(FlnItem(
      qNo: 22 + i,
      sec: '2B',
      code: '2B${i + 1}',
      prompt: list,
      questionVal: list,
      answer: l.join(', '),
      distractors: <String>[
        <int>[l[4], l[1], l[2], l[3], l[0]].join(', '),
        <int>[l[0], l[2], l[1], l[3], l[4]].join(', '),
        <int>[l[0], l[1], l[2], l[4], l[3]].join(', '),
      ],
    ));
  }

  // Q27–Q34 place value
  const pvMult = <List<int>>[
    <int>[1, 1000, 100000],
    <int>[100000, 100, 1],
    <int>[10, 1, 1000000],
    <int>[1, 1000000, 1000],
    <int>[10000, 1, 100],
    <int>[1000, 10000, 1],
    <int>[1, 100, 10000],
    <int>[10, 100, 1000],
  ];
  final pv = paper.placeValue;
  for (var i = 0; i < 8; i++) {
    final digit = int.parse(pv[i]);
    final ans = digit * math.pow(10, 7 - i).toInt();
    items.add(FlnItem(
      qNo: 27 + i,
      sec: '2C',
      code: '2C${i + 1}',
      prompt: 'સંખ્યા $pv માં અંક $digit ની સ્થાનકિંમત',
      questionVal: '$pv (અંક $digit)',
      answer: s(ans),
      distractors: _distinctInts(ans, <int>[for (final m in pvMult[i]) digit * m], min: 1).map(s).toList(),
    ));
  }

  // Q35–Q39 biggest, Q40–Q44 smallest (third distractor added)
  for (var i = 0; i < 5; i++) {
    final list = paper.q3a[i];
    final d = _listOf(list)..sort((a, b) => b.compareTo(a));
    final rev = _reversedDigits(d[0]);
    final third = (rev != d[0] && !d.contains(rev)) ? rev : d[0] + 1;
    items.add(FlnItem(
      qNo: 35 + i,
      sec: '3A',
      code: '3A${i + 1}',
      prompt: list,
      questionVal: list,
      answer: s(d[0]),
      distractors: _distinctInts(d[0], <int>[d[2], d[1], third], min: 1).map(s).toList(),
    ));
  }
  for (var i = 0; i < 5; i++) {
    final list = paper.q3b[i];
    final d = _listOf(list)..sort((a, b) => b.compareTo(a));
    final rev = _reversedDigits(d[2]);
    final third = (rev != d[2] && !d.contains(rev)) ? rev : d[2] + 1;
    items.add(FlnItem(
      qNo: 40 + i,
      sec: '3B',
      code: '3B${i + 1}',
      prompt: list,
      questionVal: list,
      answer: s(d[2]),
      distractors: _distinctInts(d[2], <int>[d[1], d[0], third], min: 1).map(s).toList(),
    ));
  }

  // Q45–Q49 middle number
  for (var i = 0; i < 5; i++) {
    final pat = paper.q3c[i];
    final left = int.tryParse(pat.split('_').first.trim()) ?? 1;
    final ans = left + 1;
    items.add(FlnItem(
      qNo: 45 + i,
      sec: '3C',
      code: '3C${i + 1}',
      prompt: pat,
      questionVal: pat,
      answer: s(ans),
      distractors: _distinctInts(ans, <int>[left + 3, left - 1, i == 0 ? 5 : left - 2], min: 1).map(s).toList(),
    ));
  }

  // Q50–Q54 just before, Q55–Q59 just after
  for (var i = 0; i < 5; i++) {
    final num = paper.q3d[i];
    items.add(FlnItem(
      qNo: 50 + i,
      sec: '3D',
      code: '3D${i + 1}',
      prompt: '___ $num',
      questionVal: '___ $num',
      answer: s(num - 1),
      distractors: _distinctInts(num - 1, <int>[num + 1, num - 2, num + 2]).map(s).toList(),
    ));
  }
  for (var i = 0; i < 5; i++) {
    final num = paper.q3e[i];
    items.add(FlnItem(
      qNo: 55 + i,
      sec: '3E',
      code: '3E${i + 1}',
      prompt: '$num ___',
      questionVal: '$num ___',
      answer: s(num + 1),
      distractors: _distinctInts(num + 1, <int>[num - 1, num + 2, num - 2]).map(s).toList(),
    ));
  }

  // Q60–Q74 addition
  var addIdx = 0;
  for (var l = 1; l <= 15; l++) {
    final qNo = 59 + l;
    final count = l <= 12 ? 2 : (l <= 14 ? 3 : 4);
    final ops = paper.addition.sublist(addIdx, addIdx + count);
    addIdx += count;
    final sum = ops.fold<int>(0, (a, b) => a + b);
    int o1, o2, o3;
    if (l == 1) {
      o1 = sum < 9 ? sum + 1 : sum - 1;
      o2 = sum <= 7 ? sum + 2 : sum - 2;
      o3 = sum == 9 ? 6 : sum - 1;
    } else if (l == 2) {
      o1 = sum < 20 ? sum + 1 : sum - 1;
      o2 = sum <= 18 ? sum + 2 : sum - 2;
      o3 = sum == 10 ? 13 : (sum == 20 ? 17 : sum - 1);
    } else if (l == 3) {
      o1 = sum - 2 >= 0 ? sum - 2 : sum + 3;
      o2 = sum + 2;
      o3 = sum - 1 >= 0 ? sum - 1 : sum + 4;
    } else if (l <= 6) {
      o1 = sum - flnSeededRandInt(pSeed + qNo * 3, 1, 10);
      o2 = sum - flnSeededRandInt(pSeed + qNo * 5, 11, 20);
      o3 = sum + flnSeededRandInt(pSeed + qNo * 7, 1, 20);
    } else if (l <= 9) {
      o1 = sum - flnSeededRandInt(pSeed + qNo * 3, 1, 20);
      o2 = sum - flnSeededRandInt(pSeed + qNo * 5, 21, 40);
      o3 = sum + flnSeededRandInt(pSeed + qNo * 7, 1, 50);
    } else {
      o1 = sum - flnSeededRandInt(pSeed + qNo * 3, 100, 200);
      o2 = sum - flnSeededRandInt(pSeed + qNo * 5, 201, 400);
      o3 = sum + flnSeededRandInt(pSeed + qNo * 7, 51, 500);
    }
    final q = ops.join(' + ');
    items.add(FlnItem(
      qNo: qNo,
      sec: 'ADD',
      code: 'ADD$l',
      prompt: '$q = ______',
      questionVal: q,
      answer: s(sum),
      distractors: _distinctInts(sum, <int>[o1, o2, o3], min: 1).map(s).toList(),
    ));
  }

  // Q75–Q89 subtraction
  for (var l = 1; l <= 15; l++) {
    final qNo = 74 + l;
    final m = paper.subtraction[(l - 1) * 2];
    final sb = paper.subtraction[(l - 1) * 2 + 1];
    final ans = m - sb;
    int o1, o2, o3;
    final small = ans - 9 < 1;
    if (l <= 2) {
      final r1 = flnSeededRandInt(pSeed + qNo * 3, 1, 2);
      final r2 = flnSeededRandInt(pSeed + qNo * 5, 3, 4);
      final r3 = flnSeededRandInt(pSeed + qNo * 7, 5, 6);
      o1 = small ? ans + r1 : ans - r1;
      o2 = small ? ans + r2 : ans - r2;
      o3 = small ? ans + r3 : ans - r3;
    } else if (l <= 4) {
      final r1 = flnSeededRandInt(pSeed + qNo * 3, 1, 2);
      final r2 = flnSeededRandInt(pSeed + qNo * 5, 3, 4);
      final r3 = flnSeededRandInt(pSeed + qNo * 7, 5, 6);
      o1 = small ? math.max(0, ans - r1) : ans + r1;
      o2 = small ? ans + r2 : ans - r2;
      o3 = small ? ans + r3 : ans - r3;
    } else if (l <= 8) {
      final r1 = flnSeededRandInt(pSeed + qNo * 3, 11, 15);
      final r2 = flnSeededRandInt(pSeed + qNo * 5, 1, 5);
      final r3 = flnSeededRandInt(pSeed + qNo * 7, 6, 10);
      o1 = small ? math.max(0, ans - r1) : ans + r1;
      o2 = small ? ans + r2 : ans - r2;
      o3 = small ? ans + r3 : ans - r3;
    } else if (l == 9) {
      final r2 = flnSeededRandInt(pSeed + qNo * 5, 1, 9);
      o1 = small ? math.max(0, ans - 10) : ans + 10;
      o2 = small ? ans + r2 : ans - r2;
      o3 = small ? ans + 10 : ans - 10;
    } else {
      final p10 = math.pow(10, math.max(1, '$ans'.length - 1)).toInt();
      o1 = ans + p10;
      o2 = ans - p10 >= 0 ? ans - p10 : ans + p10 * 2;
      final pct = flnSeededRandInt(pSeed + qNo * 7, 12, 45);
      final delta = math.max(5, (ans * pct / 100).round());
      o3 = ans - delta >= 0 ? ans - delta : ans + delta;
    }
    final q = '$m − $sb';
    items.add(FlnItem(
      qNo: qNo,
      sec: 'SUB',
      code: 'SUB$l',
      prompt: '$q = ______',
      questionVal: q,
      answer: s(ans),
      distractors: _distinctInts(ans, <int>[o1, o2, o3]).map(s).toList(),
    ));
  }

  // Q90–Q104 multiplication
  for (var l = 1; l <= 15; l++) {
    final qNo = 89 + l;
    final m1 = paper.multiplication[(l - 1) * 2];
    final m2 = paper.multiplication[(l - 1) * 2 + 1];
    final ans = m1 * m2;
    int o1, o2, o3;
    if (l <= 2) {
      o1 = ans - flnSeededRandInt(pSeed + qNo * 3, 1, 4);
      o2 = ans + flnSeededRandInt(pSeed + qNo * 5, 1, 5);
      o3 = ans - 1;
    } else if (l <= 6) {
      o1 = ans - flnSeededRandInt(pSeed + qNo * 3, 10, 20);
      o2 = ans + flnSeededRandInt(pSeed + qNo * 5, 10, 50);
      o3 = ans + flnSeededRandInt(pSeed + qNo * 7, 1, 9);
    } else if (l <= 9) {
      o1 = ans - flnSeededRandInt(pSeed + qNo * 3, 10, 100);
      o2 = ans + flnSeededRandInt(pSeed + qNo * 5, 51, 100);
      o3 = ans + flnSeededRandInt(pSeed + qNo * 7, 10, 50);
    } else if (l <= 13) {
      o1 = ans - flnSeededRandInt(pSeed + qNo * 3, 100, 1000);
      o2 = ans + flnSeededRandInt(pSeed + qNo * 5, 510, 1000);
      o3 = ans + flnSeededRandInt(pSeed + qNo * 7, 100, 500);
    } else {
      o1 = ans - flnSeededRandInt(pSeed + qNo * 3, 100, 10000);
      o2 = ans + flnSeededRandInt(pSeed + qNo * 5, 5100, 10000);
      o3 = ans + flnSeededRandInt(pSeed + qNo * 7, 1000, 5000);
    }
    final q = '$m1 × $m2';
    items.add(FlnItem(
      qNo: qNo,
      sec: 'MUL',
      code: 'MUL$l',
      prompt: '$q = ______',
      questionVal: q,
      answer: s(ans),
      distractors: _distinctInts(ans, <int>[o1, o2, o3], min: 1).map(s).toList(),
    ));
  }

  // Q105–Q119 division
  for (var l = 1; l <= 15; l++) {
    final qNo = 104 + l;
    final dv = paper.division[(l - 1) * 2];
    final dr = paper.division[(l - 1) * 2 + 1];
    final ans = dv ~/ dr;
    int o1, o2, o3;
    if (l <= 2) {
      o1 = ans + 1;
      o2 = dv + dr;
      o3 = dr + ans;
    } else if (l <= 5) {
      o1 = ans + 1;
      o2 = dv - dr;
      o3 = dr + ans;
    } else if (l <= 8) {
      o1 = ans + 10;
      o2 = ans - flnSeededRandInt(pSeed + qNo * 5, 1, 5);
      o3 = dr + ans;
    } else {
      o1 = ans + 10;
      o2 = ans - flnSeededRandInt(pSeed + qNo * 5, 4, 11);
      o3 = dr + ans;
    }
    final q = '$dv ÷ $dr';
    items.add(FlnItem(
      qNo: qNo,
      sec: 'DIV',
      code: 'DIV$l',
      prompt: '$q = ______',
      questionVal: q,
      answer: s(ans),
      distractors: _distinctInts(ans, <int>[o1, o2, o3], min: 1).map(s).toList(),
    ));
  }

  // Q120–Q130 word problems
  final p = paper.puzzles;
  final wps = <(int, String, List<Object>, int, List<String>)>[
    (120, 'WP1', <Object>[p[0], p[1]], p[0] + p[1], <String>['${p[0]} + ${p[1]} = ${p[0] + p[1]}']),
    (121, 'WP2', <Object>[p[2], p[3]], p[2] - p[3], <String>['${p[2]} − ${p[3]} = ${p[2] - p[3]}']),
    (122, 'WP3', <Object>[p[4], p[5]], p[4] * p[5], <String>['${p[4]} × ${p[5]} = ${p[4] * p[5]}']),
    (123, 'WP4', <Object>[p[6], p[7]], p[6] ~/ p[7], <String>['${p[6]} ÷ ${p[7]} = ${p[6] ~/ p[7]}']),
    (124, 'WP5', <Object>[p[8], p[9], p[10]], p[8] + p[9] + p[10], <String>[
      '${p[8]} + ${p[9]} = ${p[8] + p[9]}',
      '${p[8] + p[9]} + ${p[10]} = ${p[8] + p[9] + p[10]}',
    ]),
    (125, 'WP6', <Object>[p[11], p[12], p[13]], p[11] - p[12] - p[13], <String>[
      '${p[11]} − ${p[12]} = ${p[11] - p[12]}',
      '${p[11] - p[12]} − ${p[13]} = ${p[11] - p[12] - p[13]}',
    ]),
    (126, 'WP7', <Object>[p[14], p[15], p[16]], (p[14] * p[15]) ~/ p[16], <String>[
      '${p[14]} × ${p[15]} = ${p[14] * p[15]}',
      '${p[14] * p[15]} ÷ ${p[16]} = ${(p[14] * p[15]) ~/ p[16]}',
    ]),
    (127, 'WP8', <Object>[p[17], p[18], p[19]], p[17] + p[18] - p[19], <String>[
      '${p[17]} + ${p[18]} = ${p[17] + p[18]}',
      '${p[17] + p[18]} − ${p[19]} = ${p[17] + p[18] - p[19]}',
    ]),
    (128, 'WP9', <Object>[p[20], p[21], p[22], p[23]], (p[20] + p[21] - p[22]) * p[23], <String>[
      '${p[20]} + ${p[21]} = ${p[20] + p[21]}',
      '${p[20] + p[21]} − ${p[22]} = ${p[20] + p[21] - p[22]}',
      '${p[20] + p[21] - p[22]} × ${p[23]} = ${(p[20] + p[21] - p[22]) * p[23]}',
    ]),
    (129, 'WP10', <Object>[p[24], p[25], p[26], p[27], p[28]], ((p[24] + p[25] - p[26]) * p[27]) ~/ p[28], <String>[
      '${p[24]} + ${p[25]} = ${p[24] + p[25]}',
      '${p[24] + p[25]} − ${p[26]} = ${p[24] + p[25] - p[26]}',
      '${p[24] + p[25] - p[26]} × ${p[27]} = ${(p[24] + p[25] - p[26]) * p[27]}',
      '${(p[24] + p[25] - p[26]) * p[27]} ÷ ${p[28]} = ${((p[24] + p[25] - p[26]) * p[27]) ~/ p[28]}',
    ]),
  ];
  {
    final n1 = p[29], n2 = p[30], n3 = p[31], n4 = p[32], n5 = p[33];
    final diff = n1 - n2;
    final part = diff ~/ n3;
    final rem = diff - part;
    final gift = rem * n4;
    final ans = cfg.q130Additive ? rem + gift + n5 : gift + n5;
    wps.add((130, 'WP11', <Object>[n1, n2, kFlnGujOrdinals[n3] ?? '$n3મા', n4, n5], ans, <String>[
      '$n1 − $n2 = $diff',
      '$diff ÷ $n3 = $part',
      '$diff − $part = $rem',
      '$rem × $n4 = $gift',
      if (cfg.q130Additive) '$rem + $gift = ${rem + gift}',
      '${cfg.q130Additive ? rem + gift : gift} + $n5 = $ans',
    ]));
  }
  for (final wp in wps) {
    var text = kFlnSpecs[wp.$1 - 1].inst;
    for (var i = 0; i < wp.$3.length; i++) {
      text = text.replaceAll(RegExp('\\{n${i + 1}\\s*\\}'), '${wp.$3[i]}');
    }
    final ans = wp.$4;
    items.add(FlnItem(
      qNo: wp.$1,
      sec: 'WP',
      code: wp.$2,
      prompt: text,
      questionVal: text,
      answer: s(ans),
      distractors: _distinctInts(ans, <int>[
        ans + 10,
        ans - flnSeededRandInt(pSeed + wp.$1 * 5, 4, 9),
        ans + flnSeededRandInt(pSeed + wp.$1 * 7, 12, 20),
      ], min: 1)
          .map(s)
          .toList(),
      steps: wp.$5,
    ));
  }
  return items;
}

// ---------------------------------------------------------------------------
// Prepared (ordered, lettered) questions for one printed paper
// ---------------------------------------------------------------------------

class FlnChoice {
  const FlnChoice(this.letter, this.text, this.correct);
  final String letter;
  final String text;
  final bool correct;
}

class FlnPreparedItem {
  FlnPreparedItem(this.item, this.displayNo, this.choices, this.correctLetter);
  final FlnItem item;
  final int displayNo;
  final List<FlnChoice> choices;
  final String correctLetter;
}

/// Orders the selected questions of a paper and letters the options.
List<FlnPreparedItem> flnPrepare({
  required List<FlnItem> items,
  required Set<int> selected,
  required int paperNo,
  required int salt,
  required bool shuffleWithinSection,
  required bool shuffleAll,
  required bool shuffleOptions,
}) {
  final filtered = items.where((it) => selected.contains(it.qNo)).toList();
  final paperSeed = paperNo * 7919 + salt * 131;
  List<FlnItem> ordered;
  if (shuffleAll) {
    ordered = flnSeededShuffle(filtered, paperSeed + 503);
  } else if (shuffleWithinSection) {
    ordered = <FlnItem>[];
    for (final m in kFlnSections) {
      final secItems = filtered.where((it) => it.sec == m.sec).toList();
      ordered.addAll(flnSeededShuffle(secItems, paperSeed + m.qStart * 37));
    }
  } else {
    ordered = filtered;
  }
  const letters = <String>['A', 'B', 'C', 'D'];
  final out = <FlnPreparedItem>[];
  for (var idx = 0; idx < ordered.length; idx++) {
    final it = ordered[idx];
    var raw = <(String, bool)>[
      (it.answer, true),
      for (final d in it.distractors) (d, false),
    ];
    if (shuffleOptions) raw = flnSeededShuffle(raw, paperSeed + it.qNo * 41 + idx * 19);
    var correct = 'A';
    final choices = <FlnChoice>[];
    for (var c = 0; c < raw.length; c++) {
      final letter = c < letters.length ? letters[c] : '${c + 1}';
      if (raw[c].$2) correct = letter;
      choices.add(FlnChoice(letter, raw[c].$1, raw[c].$2));
    }
    out.add(FlnPreparedItem(it, idx + 1, choices, correct));
  }
  return out;
}

/// Set code shown on a paper (A..Z, then AA..).
String flnSetCode(int paperNo) {
  var n = paperNo - 1;
  var code = '';
  do {
    code = String.fromCharCode(65 + n % 26) + code;
    n = n ~/ 26 - 1;
  } while (n >= 0);
  return code;
}

/// Smart selection presets from the HTML question picker.
Set<int> flnPreset(String key, int seed) {
  final r = math.Random(seed);
  final out = <int>{};
  List<int> pick(FlnSectionMeta m, int n) {
    final pool = <int>[for (var q = m.qStart; q <= m.qEnd; q++) q]..shuffle(r);
    return pool.take(math.min(n, pool.length)).toList();
  }

  switch (key) {
    case 'balanced15':
      for (final m in kFlnSections) {
        out.addAll(pick(m, 1));
      }
    case 'balanced30':
      for (final m in kFlnSections) {
        out.addAll(pick(m, 2));
      }
    case 'balanced50':
      for (final m in kFlnSections) {
        out.addAll(pick(m, const <String>{'ADD', 'SUB', 'MUL', 'DIV', 'WP'}.contains(m.sec) ? 4 : 3));
      }
    case 'num_only':
      out.addAll(<int>[for (var q = 1; q <= 59; q++) q]);
    case 'ops_only':
      out.addAll(<int>[for (var q = 60; q <= 119; q++) q]);
    case 'wp_only':
      out.addAll(<int>[for (var q = 120; q <= 130; q++) q]);
    default:
      out.addAll(<int>[for (var q = 1; q <= 130; q++) q]);
  }
  return out;
}

/// Parses "1-5, 9, 60-65" into question numbers (1..130).
Set<int> flnParseRange(String text) {
  final out = <int>{};
  for (final part in text.split(RegExp(r'[,\s]+'))) {
    final t = part.trim();
    if (t.isEmpty) continue;
    final m = RegExp(r'^(\d+)\s*[-–]\s*(\d+)$').firstMatch(t);
    if (m != null) {
      var a = int.parse(m.group(1)!);
      var b = int.parse(m.group(2)!);
      if (a > b) {
        final x = a;
        a = b;
        b = x;
      }
      for (var q = a; q <= b; q++) {
        if (q >= 1 && q <= 130) out.add(q);
      }
    } else {
      final q = int.tryParse(t);
      if (q != null && q >= 1 && q <= 130) out.add(q);
    }
  }
  return out;
}
