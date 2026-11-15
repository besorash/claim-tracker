/// Minimal Google Gemini REST client (generateContent with function calling)
/// plus where the API key lives. Plain dart:io HTTPS like the Sheets sync —
/// no extra dependency.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// A request that could not be answered. [code] picks the message shown.
class GeminiException implements Exception {
  const GeminiException(this.code, [this.detail = '']);

  /// One of: invalid-key, rate-limit, model-not-found, network, bad-response,
  /// http.
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
  }) : _transport = transport ?? httpTransport;

  final String apiKey;
  final String model;
  final GeminiTransport _transport;

  static const String _base =
      'https://generativelanguage.googleapis.com/v1beta/models';

  /// One generateContent call. Returns the raw response JSON.
  Future<Map<String, Object?>> generate(Map<String, Object?> body) =>
      _transport(
        'POST',
        Uri.parse('$_base/${Uri.encodeComponent(model)}:generateContent'),
        apiKey,
        body,
      );

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
      final HttpClientResponse res = await req.close().timeout(
        const Duration(seconds: 60),
      );
      final String text = await res
          .transform(utf8.decoder)
          .join()
          .timeout(const Duration(seconds: 60));
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
        _ => GeminiException('http', '${res.statusCode} $message'.trim()),
      };
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
