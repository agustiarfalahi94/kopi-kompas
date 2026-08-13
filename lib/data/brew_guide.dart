import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

import '../strings.dart' show AppStrings;

/// A string carried in both languages, resolved when it is read.
///
/// Resolving at parse time would freeze the guides in whichever language
/// happened to be set when the file loaded. That is exactly the bug that
/// shipped once already, in a different shape: the headings switched to
/// Indonesian and the guide text stayed English.
class Localised {
  const Localised(this._values);
  final Map<String, String> _values;

  factory Localised.fromJson(Map<String, dynamic> j) =>
      Localised(j.map((k, v) => MapEntry(k, v as String)));

  String get text => _values[AppStrings.language] ?? _values['en']!;
  @override
  String toString() => text;
}

/// A range with a unit, rendered as "1.8–2.2" or "25–32 s".
class TargetRange {
  const TargetRange(this.low, this.high, [this.unit]);
  final num low;
  final num high;
  final String? unit;

  String get text {
    String n(num v) => v == v.roundToDouble() ? '${v.round()}' : '$v';
    return '${n(low)}–${n(high)}${unit == null ? '' : ' $unit'}';
  }
}

/// The numbers a method is judged against.
///
/// Read from `schema/brew_schema.json`, the same file the Worker builds its
/// rubric from. A guide that restated them would drift, and the app would end
/// up marking you down for following its own advice.
class BrewTargets {
  const BrewTargets({
    required this.ratio,
    required this.time,
    required this.temp,
    required Localised grind,
  }) : _grind = grind;

  final TargetRange ratio;
  final TargetRange time;
  final TargetRange temp;
  final Localised _grind;
  String get grind => _grind.text;

  factory BrewTargets.fromJson(Map<String, dynamic> j) {
    List<num> r(String k) => (j[k] as List).cast<num>();
    final secs = r('timeSeconds');
    // Hours read better than 43200 seconds for cold brew.
    final long = secs[1] >= 3600;
    return BrewTargets(
      ratio: TargetRange(r('ratio')[0], r('ratio')[1]),
      time: long
          ? TargetRange(secs[0] ~/ 3600, secs[1] ~/ 3600, 'h')
          : TargetRange(secs[0], secs[1], 's'),
      temp: TargetRange(r('tempC')[0], r('tempC')[1], '°C'),
      grind: Localised.fromJson(j['grind'] as Map<String, dynamic>),
    );
  }
}

class BrewFault {
  const BrewFault(this._symptom, this._cause);
  final Localised _symptom;
  final Localised _cause;
  String get symptom => _symptom.text;
  String get cause => _cause.text;
}

class GearTier {
  const GearTier(this._tier, this._what);
  final Localised _tier;
  final Localised _what;
  String get tier => _tier.text;
  String get what => _what.text;
}

class BrewGuide {
  const BrewGuide({
    required this.methodId,
    required Localised what,
    required List<Localised> steps,
    required this.faults,
    required this.gear,
    required List<Localised> notes,
  }) : _what = what,
       _steps = steps,
       _notes = notes;

  final String methodId;
  final Localised _what;
  final List<Localised> _steps;
  final List<BrewFault> faults;
  final List<GearTier> gear;
  final List<Localised> _notes;

  String get what => _what.text;
  List<String> get steps => [for (final s in _steps) s.text];
  List<String> get notes => [for (final n in _notes) n.text];
}

/// Every guide, keyed by method id.
class BrewGuides {
  BrewGuides._(this._byMethod);

  final Map<String, BrewGuide> _byMethod;

  BrewGuide? forMethod(String id) => _byMethod[id];
  bool get isEmpty => _byMethod.isEmpty;

  static Future<BrewGuides> load() async =>
      parse(await rootBundle.loadString('assets/guides.json'));

  static BrewGuides parse(String source) {
    final root = jsonDecode(source) as Map<String, dynamic>;
    final guides = <String, BrewGuide>{};
    (root['guides'] as Map<String, dynamic>).forEach((id, raw) {
      final g = raw as Map<String, dynamic>;
      Localised loc(Object? v) => Localised.fromJson(v as Map<String, dynamic>);

      guides[id] = BrewGuide(
        methodId: id,
        what: loc(g['what']),
        steps: [for (final s in g['steps'] as List) loc(s)],
        faults: [
          for (final f in g['faults'] as List)
            BrewFault(
              loc((f as Map<String, dynamic>)['symptom']),
              loc(f['cause']),
            ),
        ],
        gear: [
          for (final t in g['gear'] as List)
            GearTier(loc((t as Map<String, dynamic>)['tier']), loc(t['what'])),
        ],
        notes: [for (final n in g['notes'] as List) loc(n)],
      );
    });
    return BrewGuides._(guides);
  }
}
