import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:survero/src/core/survero_client.dart';
import 'package:survero/src/events/event_queue.dart';
import 'package:survero/src/events/identity_store.dart';
import 'package:survero/src/events/session_tracker.dart';
import 'package:survero/src/events/survero_event.dart';
import 'package:survero/src/events/tracker.dart';
import 'package:survero/src/surveys/eligible_survey.dart';
import 'package:survero/src/surveys/local_caps.dart';
import 'package:survero/src/surveys/survero_surveys.dart';

const surveyJson = {
  'id': '11111111-1111-4111-8111-111111111111',
  'slug': 'sean-ellis',
  'type': 'single_choice',
  'trigger_event': 'story_completed',
  'locale': 'es',
  'copy': {
    'question': '¿Cómo te sentirías?',
    'options': [
      {'key': 'very', 'label': 'Muy decepcionado'},
      {'key': 'not', 'label': 'Nada'},
    ],
  },
  'scale': null,
  'style': {'primaryColor': '#E30B5C', 'borderRadius': 16},
};

class FakeApi {
  final calls = <String, List<http.Request>>{};
  Map<String, dynamic> eligible = {'survey': surveyJson, 'reason': 'shown', 'evaluated': []};
  bool offline = false;

  late final client = MockClient((request) async {
    if (offline) throw http.ClientException('offline');
    final path = request.url.path.replaceFirst('/api/v1', '');
    calls.putIfAbsent(path, () => []).add(request);
    if (path == '/sdk/surveys/triggers') return http.Response(jsonEncode({'triggers': ['story_completed']}), 200);
    if (path == '/sdk/surveys/eligible') return http.Response(jsonEncode(eligible), 200);
    return http.Response('{}', path.endsWith('/response') ? 201 : 200);
  });

  List<Map<String, dynamic>> bodies(String path) =>
      (calls[path] ?? []).map((r) => jsonDecode(r.body) as Map<String, dynamic>).toList();
  List<Map<String, dynamic>> get events => [for (final b in bodies('/sdk/events')) ...(b['events'] as List).cast()];
  List<Map<String, dynamic>> named(String name) => events.where((e) => e['event_name'] == name).toList();
}

void main() {
  late FakeApi api;
  late Tracker tracker;
  late SurveroSurveys surveys;
  late DateTime now;
  final navigatorKey = GlobalKey<NavigatorState>();

  Future<void> setup(WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    api = FakeApi();
    now = DateTime.utc(2026, 11, 1, 12);
    final client = SurveroClient(apiKey: 'pk_live_test', baseUrl: 'https://api.test/api/v1', httpClient: api.client, now: () => now);
    tracker = Tracker(
      client: client,
      identity: IdentityStore(),
      session: SessionTracker(),
      queue: EventQueue(now: () => now),
      context: const EventContext(platform: 'ios', sdkVersion: 'flutter/0.4.0', appVersion: '2.4.1', locale: 'es-CO', country: 'CO'),
      now: () => now,
    );
    await tracker.start(flushInterval: null);
    surveys = SurveroSurveys.internal();
    surveys.bind(tracker: tracker, client: client, context: tracker.context, caps: LocalCaps(now: () => now));
    surveys.attach(navigatorKey);
    await tester.pumpWidget(MaterialApp(navigatorKey: navigatorKey, home: const Scaffold(body: SizedBox())));
    await tester.pump();
  }

  testWidgets('track del evento disparador abre la hoja sola; responder envía respuesta, exposición y eventos', (tester) async {
    await setup(tester);
    await tracker.track('story_completed', {'story': 'a'});
    await tester.pumpAndSettle();

    expect(find.text('¿Cómo te sentirías?'), findsOneWidget);
    final query = api.calls['/sdk/surveys/eligible']!.single.url.queryParameters;
    expect(query, containsPair('trigger', 'story_completed'));
    expect(query, containsPair('locale', 'es-CO'));
    expect(query['types'], 'single_choice,star,nps,emoji,free_text');
    expect(jsonDecode(query['props']!), {'story': 'a'});

    await tester.tap(find.text('Muy decepcionado'));
    await tester.pumpAndSettle();
    expect(find.text('¿Cómo te sentirías?'), findsNothing);
    await tracker.flush();

    final response = api.bodies('/sdk/surveys/11111111-1111-4111-8111-111111111111/response').single;
    expect(response, containsPair('answer_key', 'very'));
    expect(response, containsPair('trigger_event', 'story_completed'));
    expect(response['device_id'], tracker.identity.deviceId);
    expect(api.bodies('/sdk/surveys/11111111-1111-4111-8111-111111111111/exposure').single['outcome'], 'shown');
    expect(api.named(r'$survey_gate_evaluated').single['props'], {'survey': 'sean-ellis', 'trigger': 'story_completed', 'reason': 'shown'});
    expect(api.named(r'$survey_shown'), hasLength(1));
    expect(api.named(r'$survey_answered').single['props'], containsPair('answer_key', 'very'));
  });

  testWidgets('cap local: tras una impresión, 7 días sin preguntar al servidor; respondida → nunca', (tester) async {
    await setup(tester);
    final first = surveys.show('sean-ellis');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Nada'));
    await tester.pumpAndSettle();
    expect(await first, isA<SurveyAnswered>());

    await surveys.show('sean-ellis');
    await tracker.flush();
    expect(api.calls['/sdk/surveys/eligible'], hasLength(1));
    expect(api.named(r'$survey_gate_evaluated').last['props']['reason'], 'cooldown');

    now = now.add(const Duration(days: 8));
    await surveys.show('sean-ellis');
    await tracker.flush();
    expect(api.named(r'$survey_gate_evaluated').last['props']['reason'], 'answered');
  });

  testWidgets('descartar dos veces → dismissed_max local', (tester) async {
    await setup(tester);
    for (var i = 0; i < 2; i++) {
      final shown = surveys.show('sean-ellis');
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.close_rounded));
      await tester.pumpAndSettle();
      expect(await shown, isA<SurveyDismissed>());
      await tracker.flush(); // antes de avanzar 8 días: la cola purga lo que tenga más de 7
      now = now.add(const Duration(days: 8));
    }
    await surveys.show('sean-ellis');
    await tracker.flush();
    expect(api.named(r'$survey_dismissed'), hasLength(2));
    expect(api.named(r'$survey_gate_evaluated').last['props']['reason'], 'dismissed_max');
    expect(api.bodies('/sdk/surveys/11111111-1111-4111-8111-111111111111/exposure').where((b) => b['outcome'] == 'dismissed'), hasLength(2));
  });

  testWidgets('la razón del servidor se emite tal cual cuando no hay encuesta', (tester) async {
    await setup(tester);
    api.eligible = {
      'survey': null,
      'reason': 'not_eligible',
      'evaluated': [
        {'slug': 'sean-ellis', 'reason': 'not_eligible'},
      ],
    };
    final outcome = await surveys.onTrigger('story_completed');
    await tracker.flush();
    expect(outcome, isNull);
    expect(api.named(r'$survey_gate_evaluated').single['props'], {'survey': 'sean-ellis', 'trigger': 'story_completed', 'reason': 'not_eligible'});
  });

  testWidgets('kill switch y sin red: no rompe y emite la razón', (tester) async {
    await setup(tester);
    surveys.enabled(false);
    expect(await surveys.show('sean-ellis'), isNull);
    surveys.enabled(true);
    api.offline = true;
    expect(await surveys.show('sean-ellis'), isNull);
    api.offline = false;
    await tracker.flush();
    expect(api.named(r'$survey_gate_evaluated').map((e) => e['props']['reason']), ['disabled', 'offline']);
  });

  testWidgets('headless: el renderer propio recibe la encuesta localizada y el SDK sigue contando', (tester) async {
    await setup(tester);
    EligibleSurvey? received;
    surveys.renderer((context, survey) async {
      received = survey;
      return const SurveyOutcome.answered(SurveyAnswer(answerKey: 'not', freeText: 'custom UI'));
    });
    final outcome = await surveys.show('sean-ellis');
    await tracker.flush();
    expect(received!.question, '¿Cómo te sentirías?');
    expect(find.byType(BottomSheet), findsNothing);
    expect(outcome, isA<SurveyAnswered>());
    expect(api.bodies('/sdk/surveys/11111111-1111-4111-8111-111111111111/response').single['free_text'], 'custom UI');
    expect(api.named(r'$survey_answered').single['props'], containsPair('has_text', 1));
  });

  testWidgets('tipo que este SDK no conoce: el servidor responde sdk_too_old y no se pinta nada', (tester) async {
    await setup(tester);
    api.eligible = {'survey': null, 'reason': 'sdk_too_old', 'evaluated': [{'slug': 'matrix', 'reason': 'sdk_too_old'}]};
    expect(await surveys.show('matrix'), isNull);
    await tracker.flush();
    expect(api.named(r'$survey_gate_evaluated').single['props']['reason'], 'sdk_too_old');
  });
}
