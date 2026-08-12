import 'dart:convert';
import 'dart:math';

enum ScoreStatus { scored, notApplicable, pending, failed }

ScoreStatus _statusFrom(String raw) => ScoreStatus.values.firstWhere(
  (s) => s.name == raw,
  orElse: () => ScoreStatus.failed,
);

/// A v4 uuid from `Random.secure`, so no package is needed for the one place
/// the app generates ids.
String newUuid() {
  final r = Random.secure();
  final b = List<int>.generate(16, (_) => r.nextInt(256));
  b[6] = (b[6] & 0x0f) | 0x40;
  b[8] = (b[8] & 0x3f) | 0x80;
  final h = b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
  return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}'
      '-${h.substring(16, 20)}-${h.substring(20)}';
}

class BrewEntry {
  const BrewEntry({
    required this.id,
    required this.brewMethod,
    required this.brewDate,
    required this.rawInputText,
    required this.methodData,
    required this.scoreStatus,
    required this.createdAt,
    required this.updatedAt,
    this.beanOrigin,
    this.roastLevel,
    this.doseGrams,
    this.grindSize,
    this.notes,
    this.overallScore,
    this.scoreReasons = const [],
    this.scoreRubric,
    this.scoreModel,
    this.scoredAt,
    this.deletedAt,
  });

  final String id;
  final String brewMethod;
  final String? beanOrigin;
  final String? roastLevel;
  final double? doseGrams;
  final String? grindSize;
  final DateTime brewDate;
  final String? notes;
  final String rawInputText;
  final Map<String, Object?> methodData;
  final int? overallScore;
  final List<String> scoreReasons;
  final ScoreStatus scoreStatus;

  /// The rubric version and model that produced [overallScore].
  ///
  /// Not bookkeeping for its own sake: an AI score is only comparable to
  /// another score from the same rubric and model, and without this pairing
  /// the history degrades without ever looking wrong.
  final String? scoreRubric;
  final String? scoreModel;
  final DateTime? scoredAt;

  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;

  Map<String, Object?> toRow() => {
    'id': id,
    'brewMethod': brewMethod,
    'beanOrigin': beanOrigin,
    'roastLevel': roastLevel,
    'doseGrams': doseGrams,
    'grindSize': grindSize,
    // Local wall-clock time, deliberately, with no zone suffix.
    //
    // A shot pulled at 00:30 belongs to the day the brewer was awake for, and
    // hasBrewOn buckets on the first ten characters of this string. Storing
    // the instant in UTC would file that shot under the previous day for
    // anyone east of Greenwich.
    //
    // Dart's DateTime cannot carry an offset — it is either UTC or
    // device-local — so a UTC value is converted rather than trusted. This is
    // why the design's "ISO-8601 with offset" is not what actually ships.
    'brewDate': (brewDate.isUtc ? brewDate.toLocal() : brewDate)
        .toIso8601String(),
    'notes': notes,
    'rawInputText': rawInputText,
    'methodData': jsonEncode(methodData),
    'overallScore': overallScore,
    'scoreReasons': jsonEncode(scoreReasons),
    'scoreStatus': scoreStatus.name,
    'scoreRubric': scoreRubric,
    'scoreModel': scoreModel,
    'scoredAt': scoredAt?.toIso8601String(),
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
    'deletedAt': deletedAt?.toIso8601String(),
  };

  factory BrewEntry.fromRow(Map<String, Object?> row) => BrewEntry(
    id: row['id'] as String,
    brewMethod: row['brewMethod'] as String,
    beanOrigin: row['beanOrigin'] as String?,
    roastLevel: row['roastLevel'] as String?,
    doseGrams: (row['doseGrams'] as num?)?.toDouble(),
    grindSize: row['grindSize'] as String?,
    brewDate: DateTime.parse(row['brewDate'] as String),
    notes: row['notes'] as String?,
    rawInputText: row['rawInputText'] as String,
    methodData:
        (jsonDecode(row['methodData'] as String? ?? '{}')
                as Map<String, dynamic>)
            .cast<String, Object?>(),
    overallScore: (row['overallScore'] as num?)?.toInt(),
    scoreReasons: (jsonDecode(row['scoreReasons'] as String? ?? '[]') as List)
        .cast<String>(),
    scoreStatus: _statusFrom(row['scoreStatus'] as String),
    scoreRubric: row['scoreRubric'] as String?,
    scoreModel: row['scoreModel'] as String?,
    scoredAt: _date(row['scoredAt']),
    createdAt: DateTime.parse(row['createdAt'] as String),
    updatedAt: DateTime.parse(row['updatedAt'] as String),
    deletedAt: _date(row['deletedAt']),
  );

  static DateTime? _date(Object? v) =>
      v == null ? null : DateTime.parse(v as String);

  /// Note that the score fields are **not** `?? this.x`: a failed re-score
  /// has to be able to clear a stale number rather than keep it.
  BrewEntry copyWith({
    String? brewMethod,
    String? beanOrigin,
    String? roastLevel,
    double? doseGrams,
    String? grindSize,
    DateTime? brewDate,
    String? notes,
    Map<String, Object?>? methodData,
    int? overallScore,
    List<String>? scoreReasons,
    ScoreStatus? scoreStatus,
    String? scoreRubric,
    String? scoreModel,
    DateTime? scoredAt,
    DateTime? updatedAt,
    DateTime? deletedAt,
  }) => BrewEntry(
    id: id,
    brewMethod: brewMethod ?? this.brewMethod,
    beanOrigin: beanOrigin ?? this.beanOrigin,
    roastLevel: roastLevel ?? this.roastLevel,
    doseGrams: doseGrams ?? this.doseGrams,
    grindSize: grindSize ?? this.grindSize,
    brewDate: brewDate ?? this.brewDate,
    notes: notes ?? this.notes,
    rawInputText: rawInputText,
    methodData: methodData ?? this.methodData,
    overallScore: overallScore,
    scoreReasons: scoreReasons ?? this.scoreReasons,
    scoreStatus: scoreStatus ?? this.scoreStatus,
    scoreRubric: scoreRubric,
    scoreModel: scoreModel,
    scoredAt: scoredAt,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    deletedAt: deletedAt ?? this.deletedAt,
  );
}
