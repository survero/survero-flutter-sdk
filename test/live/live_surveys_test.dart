// Encuestas v2 contra un API real. Se salta si no hay SURVERO_LIVE_KEY.
//   SURVERO_LIVE_KEY=pk_live_… flutter test test/live/live_surveys_test.dart
// Requiere en el proyecto una encuesta activa single_choice con trigger_event story_completed y la regla
// event_count(story_completed) ≥ 3, con una opción "very".
@Tags(['live'])
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:survero/src/core/survero_client.dart';
import 'package:survero/src/events/event_queue.dart';
import 'package:survero/src/events/identity_store.dart';
import 'package:survero/src/events/session_tracker.dart';
import 'package:survero/src/events/survero_event.dart';
import 'package:survero/src/events/tracker.dart';
import 'package:survero/src/surveys/eligible_survey.dart';
import 'package:survero/src/surveys/survero_surveys.dart';

void main() {
  final key = Platform.environment['SURVERO_LIVE_KEY'];
  final url = Platform.environment['SURVERO_LIVE_URL'] ?? 'http://localhost:4000/api/v1';

  test('2 historias → no elegible; 3 → la puerta la abre; respuesta registrada; luego answered', () async {
    SharedPreferences.setMockInitialValues({});
    final client = SurveroClient(apiKey: key!, baseUrl: url, httpClient: http.Client());
    final tracker = Tracker(
      client: client,
      identity: IdentityStore(),
      session: SessionTracker(),
      queue: EventQueue(),
      context: const EventContext(platform: 'ios', sdkVersion: 'flutter/0.4.0', appVersion: '2.4.1', locale: 'es-CO', country: 'CO'),
    );
    await tracker.start(flushInterval: null);
    final surveys = SurveroSurveys.internal()..bind(tracker: tracker, client: client, context: tracker.context);
    EligibleSurvey? seen;
    surveys.renderer((context, survey) async {
      seen = survey;
      return const SurveyOutcome.answered(SurveyAnswer(answerKey: 'very', freeText: 'live'));
    });
    final context = _FakeContext();

    for (var i = 0; i < 2; i++) {
      await tracker.track('story_completed');
    }
    expect(await surveys.onTrigger('story_completed', context: context), isNull);

    // Sin flush manual: la puerta envía la cola antes de preguntar, así cuenta el tercer evento.
    await tracker.track('story_completed');
    final outcome = await surveys.onTrigger('story_completed', context: context);
    expect(outcome, isA<SurveyAnswered>());
    expect(seen!.locale, 'es');
    await tracker.flush();

    // ignore: avoid_print
    print('device_id=${tracker.identity.deviceId}');
  }, skip: key == null ? 'SURVERO_LIVE_KEY no definida' : false);
}

/// BuildContext mínimo: con renderer headless el SDK solo comprueba `mounted`.
class _FakeContext extends Fake implements BuildContext {
  @override
  bool get mounted => true;
}
