/// Device/user-facing choices for formatted attendance reports.
/// These are presentation preferences only; they never change stored attendance data.
class ReportPreferences {
  const ReportPreferences({
    this.boys = true,
    this.girls = true,
    this.total = true,
    this.sc = true,
    this.st = true,
    this.obc = true,
    this.other = true,
    this.categoryTotal = true,
    this.breakfastMode = 'same_as_present',
  });

  final bool boys;
  final bool girls;
  final bool total;
  final bool sc;
  final bool st;
  final bool obc;
  final bool other;
  final bool categoryTotal;
  /// total | gender | same_as_present
  final String breakfastMode;

  ReportPreferences copyWith({
    bool? boys,
    bool? girls,
    bool? total,
    bool? sc,
    bool? st,
    bool? obc,
    bool? other,
    bool? categoryTotal,
    String? breakfastMode,
  }) => ReportPreferences(
    boys: boys ?? this.boys,
    girls: girls ?? this.girls,
    total: total ?? this.total,
    sc: sc ?? this.sc,
    st: st ?? this.st,
    obc: obc ?? this.obc,
    other: other ?? this.other,
    categoryTotal: categoryTotal ?? this.categoryTotal,
    breakfastMode: breakfastMode ?? this.breakfastMode,
  ).ensuringValidColumns();

  /// Prevents a print/report preference from hiding every gender column.
  ReportPreferences ensuringValidColumns() {
    if (boys || girls || total) return this;
    return copyWith(boys: true);
  }

  Map<String, dynamic> toJson() => {
    'gender_columns': {'boys': boys, 'girls': girls, 'total': total},
    'category_rows': {
      'SC': sc,
      'ST': st,
      'OBC': obc,
      'OTHER': other,
      'TOTAL': categoryTotal,
    },
    'breakfast_mode': breakfastMode,
  };

  factory ReportPreferences.fromJson(Map<String, dynamic> json) {
    final genders = (json['gender_columns'] as Map?)?.cast<String, dynamic>() ?? {};
    final categories = (json['category_rows'] as Map?)?.cast<String, dynamic>() ?? {};
    final mode = '${json['breakfast_mode'] ?? 'same_as_present'}';
    return ReportPreferences(
      boys: genders['boys'] is bool ? genders['boys'] as bool : true,
      girls: genders['girls'] is bool ? genders['girls'] as bool : true,
      total: genders['total'] is bool ? genders['total'] as bool : true,
      sc: categories['SC'] is bool ? categories['SC'] as bool : true,
      st: categories['ST'] is bool ? categories['ST'] as bool : true,
      obc: categories['OBC'] is bool ? categories['OBC'] as bool : true,
      other: categories['OTHER'] is bool ? categories['OTHER'] as bool : true,
      categoryTotal: categories['TOTAL'] is bool ? categories['TOTAL'] as bool : true,
      breakfastMode: const {'total', 'gender', 'same_as_present'}.contains(mode)
          ? mode
          : 'same_as_present',
    ).ensuringValidColumns();
  }

}

