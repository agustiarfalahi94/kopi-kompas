import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The load-bearing facts about this project, checked against the files
/// rather than against anyone's memory.
///
/// Modelled on Tiny Tapsters' docs_test, which was added after a
/// documentation rewrite renamed the app to its checkout directory and was
/// published. Every claim here has a single source of truth in the repo.
void main() {
  final pubspec = File('pubspec.yaml').readAsStringSync();
  final gradle = File('android/app/build.gradle.kts').readAsStringSync();
  final schema =
      jsonDecode(File('schema/brew_schema.json').readAsStringSync())
          as Map<String, dynamic>;
  final methods = schema['methods'] as Map<String, dynamic>;
  final scored = methods.entries
      .where((e) => (e.value as Map)['scored'] == true)
      .map((e) => e.key)
      .toList();

  final docs = {
    'README.md': File('README.md'),
    'AGENTS.md': File('AGENTS.md'),
    'CLAUDE.md': File('CLAUDE.md'),
  };

  test('every document exists', () {
    docs.forEach((name, f) {
      expect(f.existsSync(), isTrue, reason: '$name is missing');
    });
  });

  test('the package id is the same everywhere', () {
    expect(gradle, contains('com.inkpebble.kopi_kompas'));
    docs.forEach((name, f) {
      expect(
        f.readAsStringSync(),
        contains('com.inkpebble.kopi_kompas'),
        reason: '$name does not name the package id',
      );
    });
  });

  test('the documented version matches pubspec', () {
    final version = RegExp(
      r'^version:\s*(\S+)',
      multiLine: true,
    ).firstMatch(pubspec)!.group(1)!;
    docs.forEach((name, f) {
      expect(
        f.readAsStringSync(),
        contains(version),
        reason: '$name does not carry version $version',
      );
    });
  });

  test('the documented method counts match the schema', () {
    expect(methods.length, 16);
    expect(scored.length, 6);
    for (final f in docs.values) {
      final text = f.readAsStringSync();
      expect(text, contains('${methods.length}'));
      expect(text, contains('${scored.length}'));
    }
  });

  test('no document claims the Gemini key ships in the app', () {
    // It is a Cloudflare Worker secret. A document saying otherwise would
    // send someone looking for it in the wrong place, or worse, put it there.
    final forbidden = RegExp(
      r'key (is|lives|ships).{0,30}(in the app|in the apk)',
      caseSensitive: false,
    );
    docs.forEach((name, f) {
      expect(
        forbidden.hasMatch(f.readAsStringSync()),
        isFalse,
        reason: '$name suggests the key ships in the app',
      );
    });
  });

  test('AGENTS.md and CLAUDE.md say the same things', () {
    // They are two files because two tools read them. They drift the moment
    // one is edited alone.
    for (final claim in [
      'com.inkpebble.kopi_kompas',
      './tool/check.sh',
      'develop',
    ]) {
      expect(docs['AGENTS.md']!.readAsStringSync(), contains(claim));
      expect(docs['CLAUDE.md']!.readAsStringSync(), contains(claim));
    }
  });

  // The master logo staying out of the APK is checked by icon_test.dart,
  // which inspects only the asset list — pubspec mentions the path in a
  // comment explaining why it is absent, so a whole-file search is wrong.
}
