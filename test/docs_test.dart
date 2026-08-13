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

  test('the two agent files have not drifted apart', () {
    // They differ only in their own title and in which file they point at.
    // Everything else must be byte-identical, because the drift that matters
    // is a rule added to one and forgotten in the other.
    List<String> body(String name) => docs[name]!
        .readAsLinesSync()
        .skip(1)
        .map((l) => l.replaceAll('AGENTS.md', 'X').replaceAll('CLAUDE.md', 'X'))
        .toList();
    expect(body('CLAUDE.md'), body('AGENTS.md'));
  });

  test('the Worker README names the rubric version that ships', () {
    // A document illustrating the versioning rule with a version that is two
    // behind teaches the rule and misstates the fact.
    final version = RegExp(
      r"RUBRIC_VERSION = '(\w+)'",
    ).firstMatch(File('worker/src/prompts.ts').readAsStringSync())!.group(1)!;
    expect(
      File('worker/README.md').readAsStringSync(),
      contains(version),
      reason: 'worker/README.md does not mention $version',
    );
  });

  test('the spec agrees with the schema about how many are unscored', () {
    final unscored = methods.length - scored.length;
    const words = {10: 'ten', 9: 'nine', 8: 'eight', 5: 'five'};
    expect(
      File(
        'docs/superpowers/specs/2026-08-12-kopi-kompas-design.md',
      ).readAsStringSync(),
      contains('${words[unscored]} unscored'),
      reason: 'the spec does not say "${words[unscored]} unscored"',
    );
  });

  test('the spec does not call a shipped feature out of scope', () {
    // Accounts and photographs were both listed as out of scope for v1 and
    // both shipped. A scope list that contradicts the app is worse than none.
    final spec = File(
      'docs/superpowers/specs/2026-08-12-kopi-kompas-design.md',
    ).readAsStringSync();
    final stillOut = spec
        .split('Still out of scope:')[1]
        .split('Shipped after this was written')[0];
    for (final shipped in ['cloud sync', 'accounts', 'photos of the cup']) {
      expect(
        stillOut.toLowerCase(),
        isNot(contains(shipped)),
        reason: '"$shipped" ships but the spec calls it out of scope',
      );
    }
  });

  test('the credits document lists exactly what the app credits', () {
    final credited =
        (jsonDecode(File('assets/guide_credits.json').readAsStringSync())
                as List)
            .cast<Map<String, dynamic>>();
    final doc = File('ASSET_CREDITS.md').readAsStringSync();
    expect(
      doc,
      contains('${credited.length} photographs'),
      reason: 'ASSET_CREDITS.md does not say ${credited.length} photographs',
    );
    for (final c in credited) {
      expect(doc, contains(c['author'] as String), reason: '${c['method']}');
    }
  });

  test('the README describes the features that actually ship', () {
    // It sat a whole phase behind: no sign-in, no backup, no guides, no
    // search, while all four were in the app.
    final readme = File('README.md').readAsStringSync().toLowerCase();
    for (final feature in [
      'sign-in',
      'backup',
      'guide',
      'search and filter',
      'reminder',
    ]) {
      expect(readme, contains(feature), reason: 'README omits $feature');
    }
  });

  // The master logo staying out of the APK is checked by icon_test.dart,
  // which inspects only the asset list — pubspec mentions the path in a
  // comment explaining why it is absent, so a whole-file search is wrong.
}
