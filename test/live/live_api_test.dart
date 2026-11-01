// Prueba contra un API real. Se salta si no hay SURVERO_LIVE_KEY.
//   SURVERO_LIVE_KEY=pk_live_… SURVERO_LIVE_URL=http://localhost:4000/api/v1 flutter test test/live
@Tags(['live'])
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:survero/src/core/survero_client.dart';
import 'package:survero/src/events/event_queue.dart';
import 'package:survero/src/events/identity_store.dart';
import 'package:survero/src/events/session_tracker.dart';
import 'package:survero/src/events/survero_event.dart';
import 'package:survero/src/events/tracker.dart';

void main() {
  final key = Platform.environment['SURVERO_LIVE_KEY'];
  final url = Platform.environment['SURVERO_LIVE_URL'] ?? 'http://localhost:4000/api/v1';

  test('track → identify → traits → flush contra el API', () async {
    SharedPreferences.setMockInitialValues({});
    final client = SurveroClient(apiKey: key!, baseUrl: url, httpClient: http.Client());
    final tracker = Tracker(
      client: client,
      identity: IdentityStore(),
      session: SessionTracker(),
      queue: EventQueue(),
      context: const EventContext(platform: 'ios', sdkVersion: 'flutter/0.3.0', appVersion: '9.9.9-live', locale: 'es-CO', country: 'CO'),
    );
    await tracker.start(flushInterval: null);
    await tracker.track('live_check', {'premium': true, 'duration': 3});
    await tracker.identify('live-user');
    await tracker.setTraits({'plan': 'premium'});
    await tracker.flush();

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getStringList(EventQueue.storageKey), isEmpty, reason: 'todo confirmado por el API');
    expect(prefs.getStringList(Tracker.pendingKey) ?? const [], isEmpty);
    // Para la verificación en Postgres:
    // ignore: avoid_print
    print('device_id=${tracker.identity.deviceId}');
  }, skip: key == null ? 'SURVERO_LIVE_KEY no definida' : false);
}
