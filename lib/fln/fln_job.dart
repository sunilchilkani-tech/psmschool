// Builds every page of an FLN print job: the question papers and the
// matching answer copy.

import 'fln_engine.dart';
import 'fln_layout.dart';

class FlnJob {
  FlnJob({
    required this.seed,
    required this.engine,
    required this.selected,
    required this.setCount,
    required this.shuffleWithinSection,
    required this.shuffleAll,
    required this.shuffleOptions,
    required List<FlnHeaderInfo> headers,
    required this.layout,
  }) : headers = <FlnHeaderInfo>[
          for (var i = 0; i < headers.length; i++)
            setCount == null ? headers[i] : headers[i].withSet(flnSetCode(i % setCount + 1)),
        ];

  /// Code that always regenerates the same papers.
  final int seed;
  final FlnEngineConfig engine;
  final Set<int> selected;

  /// null: every student gets a new paper (no paper number or set printed).
  /// 1..4: papers in sets — students take set A, B, C… in turn and every
  /// student of a set has exactly the same paper (set 1 = same for all).
  final int? setCount;
  final bool shuffleWithinSection;
  final bool shuffleAll;
  final bool shuffleOptions;

  /// One header per student / paper.
  final List<FlnHeaderInfo> headers;
  final FlnLayoutSettings layout;

  int get paperCount => headers.length;
  bool get inSets => setCount != null;

  /// Variant (distinct paper) used by paper [paperNo].
  int variantOf(int paperNo) => setCount == null ? paperNo : (paperNo - 1) % setCount! + 1;

  /// Distinct papers in the job (one per student, or one per set).
  int get variantCount => setCount == null ? paperCount : (setCount! < paperCount ? setCount! : paperCount);

  final Map<int, FlnPaper> _papers = <int, FlnPaper>{};
  final Map<int, List<FlnPreparedItem>> _prepared = <int, List<FlnPreparedItem>>{};

  List<FlnPreparedItem> prepared(int paperNo) {
    final v = variantOf(paperNo);
    return _prepared.putIfAbsent(v, () {
      final paper = _papers.putIfAbsent(v, () => FlnGenerator.generate(seed * 1009 + v, engine));
      return flnPrepare(
        items: flnExpandPaper(paper, engine, v),
        selected: selected,
        paperNo: v,
        salt: seed % 9973,
        shuffleWithinSection: shuffleWithinSection,
        shuffleAll: shuffleAll,
        shuffleOptions: shuffleOptions,
      );
    });
  }

  FlnHeaderInfo header(int paperNo) => headers[(paperNo - 1).clamp(0, headers.length - 1)];

  /// Student paper (no answers).
  List<FlnPageLayout> questionPages(int paperNo) =>
      FlnLayoutEngine(layout).layoutPaper(paperNo, prepared(paperNo), header(paperNo), shuffleAll: shuffleAll);

  /// Answer copy of paper [paperNo] ([generic] drops the student name, used
  /// for one copy per set).
  List<FlnPageLayout> answerPages(int paperNo, {bool generic = false}) {
    final h = generic ? header(paperNo).generic : header(paperNo);
    if (layout.answerFormat == 'key') {
      return FlnLayoutEngine(layout, answers: true).layoutKey(paperNo, prepared(paperNo), h);
    }
    return FlnLayoutEngine(layout, answers: true)
        .layoutPaper(paperNo, prepared(paperNo), h, shuffleAll: shuffleAll);
  }

  /// Every student paper, in print order.
  Future<List<FlnPageLayout>> questionPagesAll({void Function(double progress)? onProgress}) async {
    final out = <FlnPageLayout>[];
    for (var p = 1; p <= paperCount; p++) {
      out.addAll(questionPages(p));
      onProgress?.call(p / paperCount);
      if (p % 2 == 0) await Future<void>.delayed(Duration.zero);
    }
    return out;
  }

  /// The answer copy: one per student, or one per set.
  Future<List<FlnPageLayout>> answerPagesAll({void Function(double progress)? onProgress}) async {
    final out = <FlnPageLayout>[];
    final n = inSets ? variantCount : paperCount;
    for (var p = 1; p <= n; p++) {
      out.addAll(answerPages(p, generic: inSets));
      onProgress?.call(p / n);
      if (p % 2 == 0) await Future<void>.delayed(Duration.zero);
    }
    return out;
  }
}
