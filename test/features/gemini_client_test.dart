/// Gemini client speed and resilience: refusals move on at once, a model
/// that does not answer gets the next one raced against it, the first answer
/// wins and that model is kept.
library;

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:claim_tracker/features/assistant/gemini_client.dart';

const Map<String, Object?> _ok = <String, Object?>{'candidates': <Object?>[]};

Map<String, Object?> _models(List<String> names) => <String, Object?>{
  'models': <Object?>[
    for (final String n in names)
      <String, Object?>{
        'name': 'models/$n',
        'supportedGenerationMethods': <Object?>['generateContent'],
      },
  ],
};

/// Fake Google: [refuse] models answer [refusal]; [hang] models never answer.
class _FakeGoogle {
  _FakeGoogle({
    required this.listed,
    this.refuse = const <String>{},
    this.hang = const <String>{},
    this.refusal = 'overloaded',
  });

  final List<String> listed;
  final Set<String> refuse;
  final Set<String> hang;
  final String refusal;
  final List<String> calls = <String>[];

  Future<Map<String, Object?>> call(
    String method,
    Uri url,
    String key,
    Map<String, Object?>? body,
  ) {
    final String path = url.path.split('/').last;
    calls.add(path);
    if (method == 'GET') {
      return Future<Map<String, Object?>>.value(_models(listed));
    }
    final String model = path.split(':').first;
    if (hang.contains(model)) return Completer<Map<String, Object?>>().future;
    if (refuse.contains(model)) {
      return Future<Map<String, Object?>>.error(GeminiException(refusal));
    }
    return Future<Map<String, Object?>>.value(_ok);
  }
}

GeminiClient _client(_FakeGoogle g, {List<String>? saved}) => GeminiClient(
  apiKey: 'k',
  model: 'gemini-flash-latest',
  transport: g.call,
  onModelSwitched: saved?.add,
  hedgeAfter: const Duration(milliseconds: 50),
);

void main() {
  test('a healthy model answers with a single call', () async {
    final _FakeGoogle g = _FakeGoogle(listed: const <String>[]);
    expect(await _client(g).generate(<String, Object?>{}), _ok);
    expect(g.calls, <String>['gemini-flash-latest:generateContent']);
  });

  test('a refusal moves on at once and the winner is saved', () async {
    final _FakeGoogle g = _FakeGoogle(
      listed: const <String>['gemini-3.6-flash'],
      refuse: <String>{'gemini-flash-latest'},
      refusal: 'rate-limit',
    );
    final List<String> saved = <String>[];
    final GeminiClient c = _client(g, saved: saved);
    expect(await c.generate(<String, Object?>{}), _ok);
    expect(g.calls, <String>[
      'gemini-flash-latest:generateContent',
      'models',
      'gemini-3.6-flash:generateContent',
    ]);
    expect(saved, <String>['gemini-3.6-flash']);

    // Next message goes straight to the model that worked.
    g.calls.clear();
    await c.generate(<String, Object?>{});
    expect(g.calls, <String>['gemini-3.6-flash:generateContent']);
  });

  test('a model that never answers is raced and loses', () async {
    final _FakeGoogle g = _FakeGoogle(
      listed: const <String>['gemini-3.8-flash', 'gemini-3.5-flash-lite'],
      hang: <String>{'gemini-flash-latest', 'gemini-3.8-flash'},
    );
    final GeminiClient c = _client(g);
    final Stopwatch sw = Stopwatch()..start();
    expect(await c.generate(<String, Object?>{}), _ok);
    expect(sw.elapsed, lessThan(const Duration(seconds: 2)));
    expect(c.activeModel, 'gemini-3.5-flash-lite');
  });

  test('everything refusing ends as one error listing what was tried', () async {
    final _FakeGoogle g = _FakeGoogle(
      listed: const <String>['gemini-3.6-flash'],
      refuse: <String>{'gemini-flash-latest', 'gemini-3.6-flash'},
    );
    await expectLater(
      _client(g).generate(<String, Object?>{}),
      throwsA(
        isA<GeminiException>()
            .having((GeminiException e) => e.code, 'code', 'overloaded')
            .having(
              (GeminiException e) => e.detail,
              'detail',
              'gemini-flash-latest: overloaded · gemini-3.6-flash: overloaded',
            ),
      ),
    );
  });

  test('a rejected key stops at once, no fallbacks', () async {
    final _FakeGoogle g = _FakeGoogle(
      listed: const <String>['gemini-3.6-flash'],
      refuse: <String>{'gemini-flash-latest'},
      refusal: 'invalid-key',
    );
    await expectLater(
      _client(g).generate(<String, Object?>{}),
      throwsA(
        isA<GeminiException>().having(
          (GeminiException e) => e.code,
          'code',
          'invalid-key',
        ),
      ),
    );
    expect(g.calls, <String>['gemini-flash-latest:generateContent']);
  });

  test('fallback list: stable only, newest first, Flash/Lite alternating', () {
    expect(
      GeminiClient.pickFallbacks(
        _models(const <String>[
          'gemini-2.5-flash',
          'gemini-flash-latest',
          'gemini-flash-lite-latest',
          'gemini-2.5-flash-lite',
          'gemini-3-flash-preview',
          'gemini-3.1-flash-lite',
          'gemini-3.1-flash-image',
          'gemini-3.5-flash',
          'gemini-3.5-flash-lite',
          'gemini-3.6-flash',
          'gemini-3.7-flash',
          'gemini-3.8-flash',
          'gemini-3.8-flash-tts',
        ]),
      ),
      <String>[
        'gemini-3.8-flash',
        'gemini-3.5-flash-lite',
        'gemini-3.7-flash',
        'gemini-3.1-flash-lite',
        'gemini-3.6-flash',
        'gemini-2.5-flash-lite',
      ],
    );
  });
}
