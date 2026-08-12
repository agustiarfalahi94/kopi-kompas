import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kopi_kompas/models/brew_entry.dart';
import 'package:kopi_kompas/services/kopi_client.dart';

late HttpServer server;
late List<Map<String, dynamic>> received;
late int status;
late Object body;

Future<void> startServer() async {
  received = [];
  status = 200;
  body = <String, Object?>{};
  server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((req) async {
    received.add({
      'path': req.uri.path,
      'body': jsonDecode(await utf8.decoder.bind(req).join()),
    });
    req.response.statusCode = status;
    req.response.headers.contentType = ContentType.json;
    req.response.write(jsonEncode(body));
    await req.response.close();
  });
}

KopiClient client() => KopiClient(
  endpoint: 'http://${server.address.host}:${server.port}',
  installId: 'install-test',
);

BrewEntry espresso() => BrewEntry(
  id: 'a',
  brewMethod: 'espresso',
  brewDate: DateTime(2026, 8, 12, 7),
  rawInputText: 'x',
  methodData: const {'yieldGrams': 36},
  scoreStatus: ScoreStatus.pending,
  createdAt: DateTime(2026, 8, 12, 7),
  updatedAt: DateTime(2026, 8, 12, 7),
);

void main() {
  setUp(startServer);
  tearDown(() => server.close(force: true));

  test('parse sends text, locale and installId', () async {
    body = {'brewMethod': 'espresso', 'methodData': <String, Object?>{}};
    await client().parse('18g in 36g out');
    expect(received.single['path'], '/parse');
    expect(received.single['body']['text'], '18g in 36g out');
    expect(received.single['body']['locale'], 'en');
    expect(received.single['body']['installId'], 'install-test');
  });

  test('parse returns the method and its data', () async {
    body = {
      'brewMethod': 'espresso',
      'doseGrams': 18,
      'methodData': {'yieldGrams': 36, 'puckPrepWdt': false},
    };
    final r = await client().parse('x') as ParseOk;
    expect(r.brewMethod, 'espresso');
    expect(r.core['doseGrams'], 18);
    expect(r.methodData['yieldGrams'], 36);
    // false is an answer, not an absence — the rubric deducts for it.
    expect(r.methodData['puckPrepWdt'], false);
  });

  test('parse maps 429 to rateLimited', () async {
    status = 429;
    body = {'error': 'daily limit reached'};
    final r = await client().parse('x') as ParseFailed;
    expect(r.kind, KopiError.rateLimited);
  });

  test('parse maps 502 to upstream', () async {
    status = 502;
    body = {'error': 'gemini unreachable'};
    expect((await client().parse('x') as ParseFailed).kind, KopiError.upstream);
  });

  test('parse maps an unreachable server to network', () async {
    // Build the client while the port is still bound, then take the server
    // away — reading server.address after close() throws.
    final c = client();
    await server.close(force: true);
    expect((await c.parse('x') as ParseFailed).kind, KopiError.network);
  });

  test('parse maps a non-object body to a failure', () async {
    body = 'not json at all';
    expect(await client().parse('x'), isA<ParseFailed>());
  });

  test('parse rejects a response with no brewMethod', () async {
    body = {'doseGrams': 18};
    expect(await client().parse('x'), isA<ParseFailed>());
  });

  test('score returns the number, reasons, rubric and model', () async {
    body = {
      'score': 88,
      'reasons': ['Ratio on target'],
      'rubric': 'r1',
      'model': 'gemini-3.5-flash',
    };
    final r = await client().score(espresso()) as ScoreOk;
    expect(r.score, 88);
    expect(r.reasons, ['Ratio on target']);
    expect(r.rubric, 'r1');
    expect(r.model, 'gemini-3.5-flash');
  });

  test('score posts the whole entry, including methodData', () async {
    body = {'score': 1, 'reasons': <String>[], 'rubric': 'r1', 'model': 'm'};
    await client().score(espresso());
    final sent = received.single['body']['entry'];
    expect(sent['brewMethod'], 'espresso');
    expect(sent['methodData']['yieldGrams'], 36);
  });

  test('score maps 422 to notScored', () async {
    status = 422;
    body = {'error': 'kopiJoss is not scored'};
    expect(
      (await client().score(espresso()) as ScoreFailed).kind,
      KopiError.notScored,
    );
  });

  test(
    'score rejects a number outside 0-100 rather than trusting it',
    () async {
      // The Worker bounds this too. Checked again because a score is written to
      // the database and shown as fact.
      body = {
        'score': 140,
        'reasons': <String>[],
        'rubric': 'r1',
        'model': 'm',
      };
      expect(await client().score(espresso()), isA<ScoreFailed>());
    },
  );
}
