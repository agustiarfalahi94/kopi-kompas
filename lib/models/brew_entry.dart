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
    this.roaster,
    this.process,
    this.roastLevel,
    this.roastDate,
    this.doseGrams,
    this.grinder,
    this.grindSetting,
    this.grindSize,
    this.waterType,
    this.notes,
    this.myRating,
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
  final String? roaster;
  final String? process;
  final String? roastLevel;
  final DateTime? roastDate;
  final double? doseGrams;
  final String? grinder;
  final String? grindSetting;
  final String? grindSize;
  final String? waterType;
  final DateTime brewDate;
  final String? notes;

  /// What the brewer thought of it, 1-5, asked on the score reveal.
  ///
  /// The only check the app will ever have on whether the rubric matches a
  /// real palate. Null means unrated, which is a genuine state and must never
  /// be stored as zero — that would read as "hated it" in every average.
  final int? myRating;
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
    'roaster': roaster,
    'process': process,
    'roastLevel': roastLevel,
    'roastDate': roastDate?.toIso8601String().substring(0, 10),
    'doseGrams': doseGrams,
    'grinder': grinder,
    'grindSetting': grindSetting,
    'grindSize': grindSize,
    'waterType': waterType,
    'myRating': myRating,
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
    roaster: row['roaster'] as String?,
    process: row['process'] as String?,
    roastLevel: row['roastLevel'] as String?,
    roastDate: _date(row['roastDate']),
    doseGrams: (row['doseGrams'] as num?)?.toDouble(),
    grinder: row['grinder'] as String?,
    grindSetting: row['grindSetting'] as String?,
    grindSize: row['grindSize'] as String?,
    waterType: row['waterType'] as String?,
    myRating: (row['myRating'] as num?)?.toInt(),
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

  /// Score fields are preserved like everything else. Dropping a number and
  /// its provenance is possible but must be asked for, with [clearScore] —
  /// they used to null by default, which meant rating a brew silently erased
  /// what it scored.
  BrewEntry copyWith({
    bool clearScore = false,
    String? brewMethod,
    String? beanOrigin,
    String? roaster,
    String? process,
    String? roastLevel,
    DateTime? roastDate,
    double? doseGrams,
    String? grinder,
    String? grindSetting,
    String? grindSize,
    String? waterType,
    DateTime? brewDate,
    String? notes,
    int? myRating,
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
    roaster: roaster ?? this.roaster,
    process: process ?? this.process,
    roastLevel: roastLevel ?? this.roastLevel,
    roastDate: roastDate ?? this.roastDate,
    doseGrams: doseGrams ?? this.doseGrams,
    grinder: grinder ?? this.grinder,
    grindSetting: grindSetting ?? this.grindSetting,
    grindSize: grindSize ?? this.grindSize,
    waterType: waterType ?? this.waterType,
    brewDate: brewDate ?? this.brewDate,
    notes: notes ?? this.notes,
    myRating: myRating ?? this.myRating,
    rawInputText: rawInputText,
    methodData: methodData ?? this.methodData,
    overallScore: clearScore ? null : (overallScore ?? this.overallScore),
    scoreReasons: clearScore ? const [] : (scoreReasons ?? this.scoreReasons),
    scoreStatus: scoreStatus ?? this.scoreStatus,
    scoreRubric: clearScore ? null : (scoreRubric ?? this.scoreRubric),
    scoreModel: clearScore ? null : (scoreModel ?? this.scoreModel),
    scoredAt: clearScore ? null : (scoredAt ?? this.scoredAt),
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    deletedAt: deletedAt ?? this.deletedAt,
  );
}
