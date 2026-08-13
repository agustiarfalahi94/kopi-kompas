import '../data/brew_schema.dart';
import '../models/brew_entry.dart';

/// What the log is currently showing.
///
/// A plain value object rather than state inside a screen, so the matching
/// rules can be tested without pumping a widget, and so Home and the full log
/// can share one definition of what "matching" means.
class LogFilter {
  const LogFilter({this.query = '', this.methodId, this.minRating});

  /// Free text. Matched against origin, roaster, notes, the method's own name,
  /// every stored choice, and the original words you typed.
  ///
  /// Searching `rawInputText` matters more than it looks: it is often the only
  /// place a detail like "pakai gula aren" survives, because no field holds it.
  final String query;

  /// One method, chosen from the picker. Null means every method.
  final String? methodId;

  /// Minimum stars. Null includes unrated brews; a value excludes them, since
  /// unrated is not the same as bad and must not count as zero.
  final int? minRating;

  bool get isActive =>
      query.trim().isNotEmpty || methodId != null || minRating != null;

  LogFilter copyWith({
    String? query,
    String? methodId,
    int? minRating,
    bool clearMethod = false,
    bool clearRating = false,
  }) => LogFilter(
    query: query ?? this.query,
    methodId: clearMethod ? null : (methodId ?? this.methodId),
    minRating: clearRating ? null : (minRating ?? this.minRating),
  );

  /// Everything about an entry that is worth searching, as one lowercase blob.
  ///
  /// Ids are expanded to their labels first, so "Kalita Wave" finds an entry
  /// whose database actually says `kalitaWave` — nobody searches in camelCase.
  static String _haystack(BrewEntry e, BrewSchema schema) {
    final parts = <String?>[
      e.beanOrigin,
      e.roaster,
      e.notes,
      e.rawInputText,
      e.grinder,
      e.grindSetting,
      e.brewMethod,
      // Guarded: an entry saved under a method that a later schema dropped
      // must still be findable rather than crashing the search.
      if (schema.methodIds.contains(e.brewMethod))
        schema.method(e.brewMethod).label,
      for (final v in [e.process, e.roastLevel, e.waterType, e.grindSize])
        if (v != null) schema.valueLabel(v),
      for (final v in e.methodData.values)
        if (v is String) schema.valueLabel(v),
    ];
    return parts.whereType<String>().join(' ').toLowerCase();
  }

  bool matches(BrewEntry e, BrewSchema schema) {
    if (methodId != null && e.brewMethod != methodId) return false;
    if (minRating != null && (e.myRating ?? 0) < minRating!) return false;

    final q = query.trim().toLowerCase();
    if (q.isEmpty) return true;

    final haystack = _haystack(e, schema);
    // Every word must appear, so "gayo tubruk" narrows the way a second word
    // is expected to. An OR would widen it, which is the opposite of search.
    return q.split(RegExp(r'\s+')).every(haystack.contains);
  }

  List<BrewEntry> apply(List<BrewEntry> entries, BrewSchema schema) => [
    for (final e in entries)
      if (matches(e, schema)) e,
  ];
}
