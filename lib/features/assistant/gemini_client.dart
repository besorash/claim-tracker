/// Minimal Google Gemini REST client (generateContent with function calling)
/// plus where the API key lives. Plain dart:io HTTPS like the Sheets sync —
/// no extra dependency.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// A request that could not be answered. [code] picks the message shown.
class GeminiException implements Exception {
  const GeminiException(this.code, [this.detail = '']);

  /// One of: invalid-key, rate-limit, overloaded, timeout, model-not-found,
  /// network, bad-response, http.
  final String code;
  final String detail;

  @override
  String toString() => detail.isEmpty ? code : '$code: $detail';
}

/// Sends one JSON request and returns the decoded answer. Swapped in tests.
typedef GeminiTransport = Future<Map<String, Object?>> Function(
  String method,
  Uri url,
  String apiKey,
  Map<String, Object?>? body,
);

class GeminiClient {
  GeminiClient({
    required this.apiKey,
    required this.model,
    GeminiTransport? transport,
    this.onModelSwitched,
    this.hedgeAfter = const Duration(seconds: 6),
  }) : _transport = transport ?? httpTransport,
       activeModel = model;

  final String apiKey;
  final String model;
  final GeminiTransport _transport;

  /// A healthy answer takes 1-5 s. When a model has not answered by then,
  /// the same request also goes to the next model and the first answer wins.
  final Duration hedgeAfter;

  /// The model answering now: [model], or a fallback after it was busy. Kept
  /// for the rest of the session so one conversation stays on one model.
  String activeModel;

  /// Called when a fallback model answered, so it can be remembered and the
  /// next session starts on it instead of the busy one.
  final void Function(String model)? onModelSwitched;

  static const Duration _timeout = Duration(seconds: 20);

  static const String _base =
      'https://generativelanguage.googleapis.com/v1beta/models';

  /// One generateContent call. Returns the raw response JSON.
  ///
  /// At busy times Google's free tier refuses (503 high demand, 429 quota)
  /// or simply never answers, model by model. So: a refusal moves to the
  /// next model at once, and a model that is slow to answer gets the next
  /// one raced against it after [hedgeAfter]; the first answer wins and that
  /// model is kept. Models are [activeModel], then [pickFallbacks].
  Future<Map<String, Object?>> generate(Map<String, Object?> body) {
    final Completer<Map<String, Object?>> done =
        Completer<Map<String, Object?>>();
    final List<String> queue = <String>[activeModel];
    final List<String> tried = <String>[]; // shown under the final error
    bool listed = false;
    int next = 0;
    int running = 0;
    GeminiException? lastBusy;

    Future<void> launch() async {
      if (done.isCompleted) return;
      if (next >= queue.length && !listed) {
        listed = true;
        for (final String m in await _fallbackModels()) {
          if (!queue.contains(m)) queue.add(m);
        }
        if (done.isCompleted) return;
      }
      if (next >= queue.length) {
        if (running == 0) {
          done.completeError(
            GeminiException(lastBusy?.code ?? 'overloaded', tried.join(' · ')),
          );
        }
        return;
      }
      final String m = queue[next++];
      running++;
      final Timer hedge = Timer(hedgeAfter, launch);
      bool failedBusy = false;
      try {
        final Map<String, Object?> res = await _generateWith(m, body);
        if (!done.isCompleted) {
          if (m != activeModel) {
            activeModel = m;
            onModelSwitched?.call(m);
          }
          done.complete(res);
        }
      } on GeminiException catch (e) {
        tried.add('$m: ${e.code}');
        if (_isBusy(e)) {
          lastBusy = e;
          failedBusy = true;
        } else if (!done.isCompleted) {
          done.completeError(e);
        }
      } on Object catch (e) {
        if (!done.isCompleted) {
          done.completeError(GeminiException('http', '$e'));
        }
      } finally {
        hedge.cancel();
        running--;
      }
      if (failedBusy) await launch();
    }

    launch();
    return done.future;
  }

  Future<Map<String, Object?>> _generateWith(
    String name,
    Map<String, Object?> body,
  ) => _transport(
    'POST',
    Uri.parse('$_base/${Uri.encodeComponent(name)}:generateContent'),
    apiKey,
    body,
  );

  static bool _isBusy(GeminiException e) =>
      e.code == 'overloaded' || e.code == 'rate-limit' || e.code == 'timeout';

  List<String>? _fallbacks;

  /// Stable Flash models (`gemini-<version>-flash` / `-flash-lite`) this key
  /// can call (see [pickFallbacks]); never the busy one. Read
  /// from Google's model list so it keeps working as models change.
  Future<List<String>> _fallbackModels() async {
    if (_fallbacks == null) {
      List<String> names = const <String>[];
      try {
        final Map<String, Object?> list = await _transport(
          'GET',
          Uri.parse('$_base?pageSize=200'),
          apiKey,
          null,
        );
        names = pickFallbacks(list);
      } on GeminiException {
        names = const <String>[];
      }
      _fallbacks = names;
    }
    return <String>[
      for (final String n in _fallbacks!)
        if (n != activeModel && n != model) n,
    ];
  }

  /// From a models.list answer: stable Flash / Flash-Lite models that
  /// support generateContent, newest first, Flash and Lite alternating.
  static List<String> pickFallbacks(Map<String, Object?> list) {
    final RegExp stable = RegExp(r'^gemini-(\d+(?:\.\d+)?)-flash(-lite)?$');
    final List<(double, bool, String)> found = <(double, bool, String)>[];
    for (final Object? m
        in (list['models'] as List<Object?>?) ?? const <Object?>[]) {
      if (m is! Map<String, Object?>) continue;
      final String name = '${m['name'] ?? ''}'.replaceFirst('models/', '');
      final List<Object?> methods =
          (m['supportedGenerationMethods'] as List<Object?>?) ??
          const <Object?>[];
      final RegExpMatch? match = stable.firstMatch(name);
      if (match == null || !methods.contains('generateContent')) continue;
      found.add((double.parse(match[1]!), match[2] != null, name));
    }
    // Newest first, alternating Flash and Flash-Lite: when the newest Flash
    // models are swamped, a Lite model (lighter, more free quota) is always
    // one step away.
    found.sort((a, b) => b.$1.compareTo(a.$1));
    final List<String> flash = <String>[
      for (final (_, bool lite, String n) in found)
        if (!lite) n,
    ];
    final List<String> lite = <String>[
      for (final (_, bool l, String n) in found)
        if (l) n,
    ];
    final List<String> out = <String>[];
    for (int i = 0; i < flash.length || i < lite.length; i++) {
      if (i < flash.length) out.add(flash[i]);
      if (i < lite.length) out.add(lite[i]);
    }
    return out.take(6).toList();
  }

  /// Cheap check that the key works and the model exists.
  Future<void> ping() => _transport(
    'GET',
    Uri.parse('$_base/${Uri.encodeComponent(model)}'),
    apiKey,
    null,
  );

  static Future<Map<String, Object?>> httpTransport(
    String method,
    Uri url,
    String apiKey,
    Map<String, Object?>? body,
  ) async {
    final HttpClient client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 20);
    try {
      final HttpClientRequest req = await client.openUrl(method, url);
      // Header, not query string: the key never lands in URLs or logs.
      req.headers.set('x-goog-api-key', apiKey);
      if (body != null) {
        req.headers.contentType = ContentType.json;
        req.add(utf8.encode(jsonEncode(body)));
      }
      // A healthy answer takes seconds; a busy model can hang. Give up on
      // this one and let generate() try another model.
      final HttpClientResponse res = await req.close().timeout(_timeout);
      final String text = await res
          .transform(utf8.decoder)
          .join()
          .timeout(_timeout);
      Object? decoded;
      try {
        decoded = text.isEmpty ? <String, Object?>{} : jsonDecode(text);
      } on FormatException {
        decoded = null;
      }
      final Map<String, Object?> json = decoded is Map<String, Object?>
          ? decoded
          : <String, Object?>{};
      if (res.statusCode == 200) {
        if (decoded is! Map<String, Object?>) {
          throw const GeminiException('bad-response');
        }
        return json;
      }
      final Map<String, Object?> error =
          (json['error'] as Map<String, Object?>?) ?? const <String, Object?>{};
      final String message = '${error['message'] ?? ''}';
      throw switch (res.statusCode) {
        400 when message.toLowerCase().contains('api key') => GeminiException(
          'invalid-key',
          message,
        ),
        401 || 403 => GeminiException('invalid-key', message),
        404 => GeminiException('model-not-found', message),
        429 => GeminiException('rate-limit', message),
        500 || 502 || 503 || 504 => GeminiException('overloaded', message),
        _ => GeminiException('http', '${res.statusCode} $message'.trim()),
      };
    } on TimeoutException {
      throw const GeminiException('timeout');
    } on SocketException catch (e) {
      throw GeminiException('network', e.message);
    } on HandshakeException catch (e) {
      throw GeminiException('network', e.message);
    } on HttpException catch (e) {
      throw GeminiException('network', e.message);
    } finally {
      client.close();
    }
  }
}

/// Where the assistant's key and model name are kept. The key goes to the
/// OS keystore (Keychain / Android Keystore), never the SQLite database, so
/// it is not copied into backups or CSV exports.
abstract class AssistantKeyStore {
  Future<String?> readKey();
  Future<void> writeKey(String key);
  Future<void> deleteKey();
  Future<String?> readModel();
  Future<void> writeModel(String model);
}

class SecureAssistantKeyStore implements AssistantKeyStore {
  const SecureAssistantKeyStore();

  static const FlutterSecureStorage _storage = FlutterSecureStorage();
  static const String _keyName = 'assistant_gemini_api_key';
  static const String _modelName = 'assistant_gemini_model';

  @override
  Future<String?> readKey() => _storage.read(key: _keyName);

  @override
  Future<void> writeKey(String key) =>
      _storage.write(key: _keyName, value: key);

  @override
  Future<void> deleteKey() => _storage.delete(key: _keyName);

  @override
  Future<String?> readModel() => _storage.read(key: _modelName);

  @override
  Future<void> writeModel(String model) =>
      _storage.write(key: _modelName, value: model);
}

/// In-memory store for tests.
class MemoryAssistantKeyStore implements AssistantKeyStore {
  MemoryAssistantKeyStore({this.key, this.model});

  String? key;
  String? model;

  @override
  Future<String?> readKey() async => key;

  @override
  Future<void> writeKey(String value) async => key = value;

  @override
  Future<void> deleteKey() async => key = null;

  @override
  Future<String?> readModel() async => model;

  @override
  Future<void> writeModel(String value) async => model = value;
}
