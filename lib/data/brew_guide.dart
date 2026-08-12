import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

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
    required this.grind,
  });

  final TargetRange ratio;
  final TargetRange time;
  final TargetRange temp;
  final String grind;

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
      grind: j['grind'] as String,
    );
  }
}

class BrewFault {
  const BrewFault(this.symptom, this.cause);
  final String symptom;
  final String cause;
}

class GearTier {
  const GearTier(this.tier, this.what);
  final String tier;
  final String what;
}

class BrewGuide {
  const BrewGuide({
    required this.methodId,
    required this.what,
    required this.steps,
    required this.faults,
    required this.gear,
    required this.notes,
  });

  final String methodId;
  final String what;
  final List<String> steps;
  final List<BrewFault> faults;
  final List<GearTier> gear;
  final List<String> notes;
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
      guides[id] = BrewGuide(
        methodId: id,
        what: g['what'] as String,
        steps: (g['steps'] as List).cast<String>(),
        faults: [
          for (final f in g['faults'] as List)
            BrewFault(
              (f as Map<String, dynamic>)['symptom'] as String,
              f['cause'] as String,
            ),
        ],
        gear: [
          for (final t in g['gear'] as List)
            GearTier(
              (t as Map<String, dynamic>)['tier'] as String,
              t['what'] as String,
            ),
        ],
        notes: (g['notes'] as List).cast<String>(),
      );
    });
    return BrewGuides._(guides);
  }
}
