import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:survero/src/core/survero_client.dart';
import 'package:survero/src/events/event_queue.dart';
import 'package:survero/src/events/identity_store.dart';
import 'package:survero/src/events/props.dart';
import 'package:survero/src/events/session_tracker.dart';
import 'package:survero/src/events/survero_event.dart';
import 'package:survero/src/events/tracker.dart';

/// Servidor falso: guarda lo recibido por ruta y responde con [status] (o lanza si [offline]).
class FakeApi {
  final requests = <String, List<Map<String, dynamic>>>{};
  final headers = <String, List<Map<String, String>>>{};
  int status = 202;
  bool offline = false;

  late final client = MockClient((request) async {
    if (offline) throw http.ClientException('offline');
    final path = request.url.path.replaceFirst('/api/v1', '');
    requests.putIfAbsent(path, () => []).add(jsonDecode(request.body) as Map<String, dynamic>);
    headers.putIfAbsent(path, () => []).add(request.headers);
    return http.Response('{}', status);
  });

  List<Map<String, dynamic>> get events =>
      [for (final body in requests['/sdk/events'] ?? []) ...(body['events'] as List).cast<Map<String, dynamic>>()];
  List<String> get names => events.map((e) => e['event_name'] as String).toList();
}

void main() {
  late FakeApi api;
  late DateTime now;
  late Tracker tracker;

  Tracker build({bool sendEnabled = true}) => Tracker(
        client: SurveroClient(apiKey: 'pk_live_test', baseUrl: 'https://api.test/api/v1', httpClient: api.client),
        identity: IdentityStore(),
        session: SessionTracker(),
        queue: EventQueue(now: () => now),
        context: const EventContext(platform: 'ios', sdkVersion: 'flutter/0.3.0', appVersion: '2.4.0', locale: 'es-CO', country: 'CO'),
        sendEnabled: sendEnabled,
        now: () => now,
      );

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    api = FakeApi();
    now = DateTime.utc(2026, 11, 1, 10);
    tracker = build();
    await tracker.start(flushInterval: null);
  });

  test(r'primera apertura: $install y $session_started con contexto como campos, no props', () async {
    await tracker.track('story_completed', {'story': 'abc', 'premium': true, 'platform': 'x'});
    await tracker.flush();

    expect(api.names, [r'$install', r'$session_started', 'story_completed']);
    final story = api.events.last;
    expect(story['props'], {'story': 'abc', 'premium': 1});
    expect(story, containsPair('platform', 'ios'));
    expect(story, containsPair('app_version', '2.4.0'));
    expect(story, containsPair('country', 'CO'));
    expect(story['device_id'], isNotEmpty);
    expect(story['session_id'], api.events[1]['session_id']);
    expect(api.headers['/sdk/events']!.first['X-Survero-Key'], 'pk_live_test');
  });

  test('device_id persiste entre arranques y no repite \$install', () async {
    await tracker.flush();
    final device = api.events.first['device_id'];
    tracker.dispose();

    final again = build();
    await again.start(flushInterval: null);
    await again.track('app_open');
    await again.flush();
    expect(api.names.where((n) => n == r'$install'), hasLength(1));
    expect(api.events.last['device_id'], device);
  });

  test(r'sesión: 30 min de inactividad cierran la anterior con su duración y abren otra', () async {
    now = now.add(const Duration(minutes: 10));
    await tracker.track('a');
    now = now.add(const Duration(minutes: 29));
    await tracker.track('b'); // misma sesión
    now = now.add(const Duration(minutes: 31));
    await tracker.track('c'); // sesión nueva
    await tracker.flush();

    expect(api.names, [r'$install', r'$session_started', 'a', 'b', r'$session_ended', r'$session_started', 'c']);
    final ended = api.events[4];
    expect(ended['props'], {'duration_s': 39 * 60});
    expect(ended['session_id'], api.events[1]['session_id']);
    expect(ended['client_ts'], DateTime.utc(2026, 11, 1, 10, 39).toIso8601String());
    expect(api.events[6]['session_id'], api.events[5]['session_id']);
    expect(api.events[6]['session_id'], isNot(api.events[1]['session_id']));
  });

  test('segundo plano no abre sesión, solo marca actividad', () async {
    now = now.add(const Duration(minutes: 40));
    await tracker.onBackground();
    now = now.add(const Duration(minutes: 5));
    await tracker.onForeground();
    await tracker.flush();
    expect(api.names.where((n) => n == r'$session_started'), hasLength(1));
  });

  test('nombres inválidos se ignoran sin lanzar', () async {
    await tracker.track('StoryCompleted');
    await tracker.track(r'$fake');
    await tracker.track('a' * 41);
    await tracker.flush();
    expect(api.names, [r'$install', r'$session_started']);
  });

  test('sin red: los eventos esperan en la cola y salen en el siguiente flush', () async {
    api.offline = true;
    await tracker.track('a');
    await tracker.flush();
    expect(api.events, isEmpty);

    api.offline = false;
    await tracker.flush();
    expect(api.names, [r'$install', r'$session_started', 'a']);
  });

  test('un 4xx descarta el lote (reintentarlo no lo arregla); un 5xx lo conserva', () async {
    api.status = 500;
    await tracker.flush();
    expect(api.requests['/sdk/events'], hasLength(1));
    api.status = 401;
    await tracker.flush();
    api.status = 202;
    await tracker.flush();
    expect(api.requests['/sdk/events'], hasLength(2), reason: 'tras el 401 no queda nada que enviar');
  });

  test('la cola guarda como mucho 100 eventos y purga los de más de 7 días', () async {
    api.offline = true;
    for (var i = 0; i < 120; i++) {
      await tracker.track('e$i');
    }
    final queue = EventQueue(now: () => now);
    expect((await queue.peek(1000)).length, 100);
    expect((await queue.peek(1)).single.name, 'e20');

    now = now.add(const Duration(days: 8));
    expect(await EventQueue(now: () => now).peek(1000), isEmpty);
  });

  test('identify: alias al API y user_id en los eventos siguientes; reset vuelve a anónimo', () async {
    await tracker.identify('user-1');
    await tracker.track('after_login');
    await tracker.reset();
    await tracker.track('after_logout');
    await tracker.flush();

    expect(api.requests['/sdk/identify']!.single, {'device_id': api.events.first['device_id'], 'user_id': 'user-1'});
    final byName = {for (final e in api.events) e['event_name']: e};
    expect(byName['after_login']!['user_id'], 'user-1');
    expect(byName['after_logout']!.containsKey('user_id'), isFalse);
  });

  test('identify y traits sin red quedan pendientes y salen antes que los eventos', () async {
    api.offline = true;
    await tracker.identify('user-2');
    await tracker.setTraits({'plan': 'free', 'Bad Key': 1, 'trial': true});
    api.offline = false;
    await tracker.flush();
    expect(api.requests['/sdk/identify'], hasLength(1));
    expect(api.requests['/sdk/traits']!.single['traits'], {'plan': 'free', 'trial': true});
    expect(api.requests['/sdk/traits']!.single['user_id'], 'user-2');
  });

  test('sinks reciben cada evento; un sink que falla no rompe nada', () async {
    final seen = <String>[];
    tracker.addSink((_) => throw StateError('boom'));
    tracker.addSink((e) => seen.add(e.name));
    await tracker.track('purchase', {'amount': 9.99});
    expect(seen, ['purchase']);
  });

  test('modo debug: no envía nada pero los sinks siguen recibiendo', () async {
    SharedPreferences.setMockInitialValues({});
    final debug = build(sendEnabled: false);
    final seen = <String>[];
    await debug.start(flushInterval: null);
    debug.addSink((e) => seen.add(e.name));
    await debug.track('a');
    await debug.identify('u');
    await debug.flush();
    expect(api.requests, isEmpty);
    expect(seen, ['a']);
  });

  group('sanitizeProps', () {
    test('booleanos 0/1, fechas ISO, anidados, reservadas fuera, no finitos fuera', () {
      expect(
        sanitizeProps({
          'ok': true,
          'at': DateTime.utc(2026, 1, 2),
          'nested': {'flag': false, 'n': double.nan},
          'list': [true, 1],
          'locale': 'es',
          'bad': double.infinity,
        }),
        {
          'ok': 1,
          'at': '2026-01-02T00:00:00.000Z',
          'nested': {'flag': 0},
          'list': [1, 1],
        },
      );
    });
  });

  test('EventContext.countryFromLocale', () {
    expect(EventContext.countryFromLocale('es-CO'), 'CO');
    expect(EventContext.countryFromLocale('es_co'), 'CO');
    expect(EventContext.countryFromLocale('zh-Hant-TW'), 'TW');
    expect(EventContext.countryFromLocale('en'), isNull);
  });
}
