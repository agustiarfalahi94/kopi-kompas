import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kopi_kompas/data/brew_schema.dart';
import 'package:kopi_kompas/data/guide_photo.dart';

late BrewSchema schema;
late GuidePhotos photos;
late String creditsDoc;

/// Licences we may ship. ShareAlike is allowed and NonCommercial is not:
/// including a work in an app distributes a collection, which does not put
/// the app under the work's licence, but NC and ND would genuinely bind it.
const _allowed = ['CC0', 'Public domain', 'CC BY'];

void main() {
  setUpAll(() {
    schema = BrewSchema.parse(
      File('schema/brew_schema.json').readAsStringSync(),
    );
    photos = GuidePhotos.parse(
      File('assets/guide_credits.json').readAsStringSync(),
    );
    creditsDoc = File('ASSET_CREDITS.md').readAsStringSync();
  });

  test('every photo file on disk has a credit', () {
    // The direction that matters most: an image can reach the screen, and an
    // image on screen without its author named is a licence breach.
    for (final f in Directory('assets/guides').listSync().whereType<File>()) {
      final method = f.uri.pathSegments.last.replaceAll('.jpg', '');
      expect(
        photos.forMethod(method),
        isNotNull,
        reason: '$method.jpg ships with no attribution',
      );
    }
  });

  test('every credit has a file', () {
    for (final p in photos.all) {
      expect(File(p.asset).existsSync(), isTrue, reason: '${p.asset} missing');
    }
  });

  test('every credited photo belongs to a real method', () {
    for (final p in photos.all) {
      expect(schema.methodIds, contains(p.method), reason: p.method);
    }
  });

  test('every credit names an author and a licence', () {
    for (final p in photos.all) {
      expect(p.author, isNotEmpty, reason: p.method);
      expect(p.author, isNot('Unknown'), reason: '${p.method} lost its author');
      expect(p.licence, isNotEmpty, reason: p.method);
      expect(p.source, startsWith('http'), reason: p.method);
      // No HTML survived the scrape into something a user reads.
      expect(p.author, isNot(contains('<')), reason: p.method);
    }
  });

  test('no licence forbids what this app does with the image', () {
    for (final p in photos.all) {
      expect(
        _allowed.any(p.licence.startsWith),
        isTrue,
        reason: '${p.method}: ${p.licence} is not an allowed licence',
      );
      // ND forbids the resize; NC forbids shipping in anything commercial.
      expect(p.licence, isNot(contains('-ND')), reason: p.method);
      expect(p.licence, isNot(contains('NC')), reason: p.method);
    }
  });

  test('ASSET_CREDITS.md lists exactly what ships', () {
    for (final p in photos.all) {
      expect(
        creditsDoc,
        contains(p.method),
        reason: '${p.method} undocumented',
      );
      expect(creditsDoc, contains(p.author), reason: '${p.author} uncredited');
    }
  });

  test('the methods without a photo are named, not silently missing', () {
    // Absence is a decision — Commons has nothing usable for these three —
    // and a decision nobody wrote down looks like an oversight later.
    for (final id in ['coldBrew', 'kopiSaring', 'kopiTalua']) {
      expect(photos.forMethod(id), isNull, reason: '$id gained a photo');
      expect(creditsDoc, contains(id), reason: '$id absence undocumented');
    }
  });

  test('the whole set stays small enough to ship', () {
    // 16.5 MB of that APK is Flutter's own runtime. Photographs are the one
    // part that grows without limit if nobody is watching.
    final bytes = Directory('assets/guides')
        .listSync()
        .whereType<File>()
        .fold<int>(0, (sum, f) => sum + f.lengthSync());
    expect(bytes, lessThan(3 * 1024 * 1024), reason: '${bytes ~/ 1024} KB');
  });
}
