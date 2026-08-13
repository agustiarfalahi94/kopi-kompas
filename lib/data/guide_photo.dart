import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

/// A photograph shipped with a guide, and the attribution it requires.
///
/// The credit travels with the image rather than living in a separate list,
/// because attribution is a licence condition: an image that reaches the
/// screen without its author named is a licence breach, and the only reliable
/// way to prevent that is to make it impossible to have one without the other.
class GuidePhoto {
  const GuidePhoto({
    required this.method,
    required this.title,
    required this.author,
    required this.licence,
    required this.source,
  });

  final String method;
  final String title;
  final String author;
  final String licence;
  final String source;

  String get asset => 'assets/guides/$method.jpg';

  /// The one-line credit shown under the photo. Author and licence are the
  /// two parts every CC licence requires; the title and link are in Settings.
  String get shortCredit => '$author · $licence';

  factory GuidePhoto.fromJson(Map<String, dynamic> j) => GuidePhoto(
    method: j['method'] as String,
    title: j['title'] as String,
    author: j['author'] as String,
    licence: j['licence'] as String,
    source: j['source'] as String,
  );
}

/// Every guide photograph, keyed by method.
///
/// Deliberately incomplete: cold brew, kopi saring and kopi talua have no
/// usable image on Commons, and a guide shows no photograph rather than the
/// wrong drink. Callers must handle a null.
class GuidePhotos {
  const GuidePhotos(this._byMethod);

  final Map<String, GuidePhoto> _byMethod;

  GuidePhoto? forMethod(String method) => _byMethod[method];
  List<GuidePhoto> get all => _byMethod.values.toList();

  static Future<GuidePhotos> load() async =>
      parse(await rootBundle.loadString('assets/guide_credits.json'));

  static GuidePhotos parse(String source) {
    final list = (jsonDecode(source) as List)
        .map((e) => GuidePhoto.fromJson(e as Map<String, dynamic>))
        .toList();
    return GuidePhotos({for (final p in list) p.method: p});
  }
}
