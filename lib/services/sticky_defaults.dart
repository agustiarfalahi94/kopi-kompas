import '../data/brew_schema.dart';
import '../models/brew_entry.dart';

/// The fields a new form should arrive already knowing, taken from the brews
/// already logged.
///
/// Three layers, most specific first: what this method recorded, then what
/// anything in its category recorded, then the core fields from anything at
/// all. So espresso to french press keeps the beans, the roaster and the
/// grinder and drops the machine — and a first-ever Kalita still inherits a
/// water temperature from months of V60.
///
/// [history] is newest-first, as `BrewDatabase.liveEntries()` returns it. A
/// value is taken from the newest entry that has one, which means a field you
/// did not mention today keeps yesterday's answer. It also means clearing a
/// field does not clear it for good: tomorrow the scan walks past the null
/// and finds the older value. That is deliberate — see section 3.1 of the
/// design — because pre-filling everything means a field only goes null when
/// somebody deliberately empties it.
///
/// This is a pure function on purpose. It replaced a SharedPreferences store,
/// which was a second copy of facts the database already held and could
/// disagree with it: an edit did not update it, a Firestore restore did not
/// populate it, and deleting a brew left its values behind.
Map<String, Object?> stickyFor(
  BrewSchema schema,
  String method,
  List<BrewEntry> history,
) {
  final spec = schema.method(method);
  final siblings = schema.categoryOf(method).methodIds.toSet();

  final found = <String, Object?>{};
  // putIfAbsent makes the first writer win, so the layers must run
  // most-specific first and each must run to completion before the next.
  void take(Map<String, Object?> from) {
    from.forEach((name, value) {
      if (value != null) found.putIfAbsent(name, () => value);
    });
  }

  for (final e in history) {
    if (e.brewMethod == method) take(e.methodData);
  }
  for (final e in history) {
    if (siblings.contains(e.brewMethod)) take(e.methodData);
  }
  take(rememberedCore(history));

  // Only what this method actually asks, and only values it can honestly
  // hold. hideCore is respected here so kopi tubruk keeps hiding the grinder
  // however many espresso shots precede it.
  final asked = <String, FieldSpec>{
    for (final f in schema.core)
      if (!spec.hideCore.contains(f.name)) f.name: f,
    for (final f in spec.fields) f.name: f,
  };

  final out = <String, Object?>{};
  found.forEach((name, value) {
    final field = asked[name];
    if (field != null && value != null && _fits(field, value)) {
      out[name] = value;
    }
  });
  return out;
}

/// The fields that carry to every method, whatever you brew next.
///
/// Settings shows these, and has no method to resolve against. Newest entry
/// with a value for a field wins.
Map<String, Object?> rememberedCore(List<BrewEntry> history) {
  final out = <String, Object?>{};
  for (final e in history) {
    _coreOf(e).forEach((name, value) {
      if (value != null) out.putIfAbsent(name, () => value);
    });
  }
  return out;
}

/// The core fields by name, as the form and the schema know them.
///
/// `notes` is deliberately absent: it is prose about one specific cup, and
/// carrying it forward staples yesterday's tasting note onto today's coffee.
///
/// `roastDate` is emitted as `YYYY-MM-DD` rather than a DateTime because that
/// is the shape a `FieldType.date` control renders and `buildEntry` accepts.
Map<String, Object?> _coreOf(BrewEntry e) => {
  'beanOrigin': e.beanOrigin,
  'roaster': e.roaster,
  'process': e.process,
  'roastLevel': e.roastLevel,
  'roastDate': e.roastDate?.toIso8601String().substring(0, 10),
  'doseGrams': e.doseGrams,
  'grinder': e.grinder,
  'grindSetting': e.grindSetting,
  'grindSize': e.grindSize,
  'waterType': e.waterType,
};

/// Whether a remembered value can honestly be offered for this field.
///
/// The load-bearing case is [FieldType.enumerated]. `brewer` exists on
/// coneDripper, flatBottomDripper and smartDripper with value lists that
/// share nothing at all, and the first two are in the same category — so the
/// category layer really will offer a V60 `brewer` to a Kalita form. The
/// dropdown would render blank, because `initialValue` already guards with
/// `f.values.contains`, and `BrewForm.initState` would then seed `_values`
/// from the field value regardless and save the invalid id behind an
/// empty-looking control.
bool _fits(FieldSpec f, Object value) => switch (f.type) {
  FieldType.enumerated => value is String && f.values.contains(value),
  FieldType.boolean => value is bool,
  FieldType.integer => value is int,
  FieldType.number => value is num,
  FieldType.string => value is String,
  FieldType.date => value is String && DateTime.tryParse(value) != null,
};
