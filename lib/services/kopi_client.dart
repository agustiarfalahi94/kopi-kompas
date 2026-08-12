import 'dart:convert';
import 'dart:io';

import '../models/brew_entry.dart';
import '../strings.dart' show AppStrings;

/// The deployed Worker. A URL, not a secret — the Gemini key never leaves
/// Cloudflare, so shipping this inside the APK gives nothing away.
const kopiEndpointDefault = 'https://kopi-kompas.inkpebble.workers.dev';

const _endpointFromEnv = String.fromEnvironment(
  'KOPI_ENDPOINT',
  defaultValue: kopiEndpointDefault,
);

/// Why a call failed.
///
/// A typed enum rather than an exception, because the UI has to behave
/// differently for each: "retry in a minute" is not "this method is not
/// scored" is not "you are offline".
enum KopiError { network, rateLimited, notScored, badRequest, upstream }

sealed class ParseResult {
  const ParseResult();
}

class ParseOk extends ParseResult {
  const ParseOk(this.brewMethod, this.core, this.methodData);
  final String brewMethod;
  final Map<String, Object?> core;
  final Map<String, Object?> methodData;
}

class ParseFailed extends ParseResult {
  const ParseFailed(this.kind, this.detail);
  final KopiError kind;
  final String detail;
}

sealed class ScoreResult {
  const ScoreResult();
}

class ScoreOk extends ScoreResult {
  const ScoreOk(this.score, this.reasons, this.rubric, this.model);
  final int score;
  final List<String> reasons;
  final String rubric;
  final String model;
}

class ScoreFailed extends ScoreResult {
  const ScoreFailed(this.kind, this.detail);
  final KopiError kind;
  final String detail;
}

class KopiClient {
  KopiClient({String? endpoint, HttpClient? http, required this.installId})
    : _endpoint = endpoint ?? _endpointFromEnv,
      _http = http ?? HttpClient();

  final String _endpoint;
  final HttpClient _http;
  final String installId;

  static const _timeout = Duration(seconds: 45);

  /// Defaults to the language the app is in, so an Indonesian brew gets the
  /// Worker's Indonesian prompt and Indonesian reasons back.
  Future<ParseResult> parse(String text, {String? locale}) async {
    final r = await _post('/parse', {
      'text': text,
      'locale': locale ?? AppStrings.language,
      'installId': installId,
    });
    return switch (r) {
      _Err(:final kind, :final detail) => ParseFailed(kind, detail),
      _Ok(:final body) => _toParseOk(body),
    };
  }

  ParseResult _toParseOk(Map<String, Object?> body) {
    final method = body['brewMethod'];
    if (method is! String) {
      return const ParseFailed(KopiError.upstream, 'no brewMethod');
    }

    final core = <String, Object?>{};
    for (final e in body.entries) {
      if (e.key != 'brewMethod' && e.key != 'methodData') {
        core[e.key] = e.value;
      }
    }

    final md = body['methodData'];
    return ParseOk(
      method,
      core,
      md is Map ? md.cast<String, Object?>() : const {},
    );
  }

  Future<ScoreResult> score(BrewEntry entry, {String? locale}) async {
    final r = await _post('/score', {
      'entry': {
        'brewMethod': entry.brewMethod,
        'beanOrigin': entry.beanOrigin,
        'roastLevel': entry.roastLevel,
        'doseGrams': entry.doseGrams,
        'grindSize': entry.grindSize,
        'notes': entry.notes,
        'methodData': entry.methodData,
      },
      'locale': locale ?? AppStrings.language,
      'installId': installId,
    });
    return switch (r) {
      _Err(:final kind, :final detail) => ScoreFailed(kind, detail),
      _Ok(:final body) => _toScoreOk(body),
    };
  }

  ScoreResult _toScoreOk(Map<String, Object?> body) {
    final score = body['score'];
    // The Worker already bounds this. Checked again because a score is
    // written to the database and shown as fact; two comparisons are cheaper
    // than trusting a number end to end.
    if (score is! int || score < 0 || score > 100) {
      return const ScoreFailed(KopiError.upstream, 'score out of range');
    }
    return ScoreOk(
      score,
      ((body['reasons'] as List?) ?? const []).whereType<String>().toList(),
      body['rubric'] as String? ?? 'unknown',
      body['model'] as String? ?? 'unknown',
    );
  }

  Future<_Response> _post(String path, Map<String, Object?> payload) async {
    try {
      final req = await _http
          .postUrl(Uri.parse('$_endpoint$path'))
          .timeout(_timeout);
      req.headers.contentType = ContentType.json;
      req.write(jsonEncode(payload));
      final res = await req.close().timeout(_timeout);
      final text = await utf8.decoder.bind(res).join();

      if (res.statusCode != 200) {
        return _Err(switch (res.statusCode) {
          429 => KopiError.rateLimited,
          422 => KopiError.notScored,
          400 => KopiError.badRequest,
          _ => KopiError.upstream,
        }, text);
      }

      final decoded = jsonDecode(text);
      if (decoded is! Map) {
        return const _Err(KopiError.upstream, 'response was not an object');
      }
      return _Ok(decoded.cast<String, Object?>());
    } catch (e) {
      return _Err(KopiError.network, '$e');
    }
  }
}

sealed class _Response {
  const _Response();
}

class _Ok extends _Response {
  const _Ok(this.body);
  final Map<String, Object?> body;
}

class _Err extends _Response {
  const _Err(this.kind, this.detail);
  final KopiError kind;
  final String detail;
}
