import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:survero/src/core/survero.dart';
import 'package:survero/src/core/survero_client.dart';
import 'package:survero/src/models/survero_response.dart';
import 'package:survero/src/utils/device_info_collector.dart';

const _surveyId = '8b0f3c1e-2d4a-4b6c-9e8f-0a1b2c3d4e5f';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('buildResponsePayload', () {
    test('usa el contrato snake_case del API', () {
      final payload = buildResponsePayload(
        surveyId: _surveyId,
        response: const SurveroResponse(rating: 4, comment: '  Muy bien  '),
        device: const DeviceMetadata(deviceOs: 'ios 18.1', deviceModel: 'iPhone16,1', locale: 'es_CO'),
        appVersion: '2.4.0',
        sdkVersion: '0.2.0',
        sessionId: 's-1',
      );
      expect(payload, {
        'survey_id': _surveyId,
        'rating': 4,
        'comment': 'Muy bien',
        'device_os': 'ios 18.1',
        'device_model': 'iPhone16,1',
        'app_version': '2.4.0',
        'sdk_version': '0.2.0',
        'locale': 'es_CO',
        'session_id': 's-1',
      });
    });

    test('omite el comentario vacío', () {
      final payload = buildResponsePayload(
        surveyId: _surveyId,
        response: const SurveroResponse(rating: 2, comment: '   '),
        device: const DeviceMetadata(deviceOs: 'web', deviceModel: 'chrome', locale: 'en'),
        sdkVersion: '0.2.0',
      );
      expect(payload.containsKey('comment'), isFalse);
      expect(payload.containsKey('app_version'), isFalse);
    });
  });

  group('SurveroClient: flujo show → submit', () {
    test('pide la configuración con la clave pública y la cachea', () async {
      var calls = 0;
      final client = SurveroClient(
        apiKey: 'pk_live_test',
        baseUrl: 'https://api.test/api/v1',
        httpClient: MockClient((request) async {
          calls++;
          expect(request.url.toString(), 'https://api.test/api/v1/sdk/surveys/$_surveyId');
          expect(request.headers['X-Survero-Key'], 'pk_live_test');
          return http.Response(
            jsonEncode({'id': _surveyId, 'title': 'Hola', 'type': 'star_rating', 'is_active': true}),
            200,
          );
        }),
      );

      final config = await client.getSurveyConfig(_surveyId);
      expect(config.title, 'Hola');
      await client.getSurveyConfig(_surveyId);
      expect(calls, 1, reason: 'la segunda lectura sale de la caché');
    });

    test('envía la respuesta y no la encola si el servidor la acepta', () async {
      Map<String, dynamic>? sent;
      final client = SurveroClient(
        apiKey: 'pk_live_test',
        baseUrl: 'https://api.test/api/v1',
        httpClient: MockClient((request) async {
          sent = jsonDecode(request.body) as Map<String, dynamic>;
          return http.Response('{"id":"r1","status":"submitted"}', 201);
        }),
      );
      await client.submitResponse({'survey_id': _surveyId, 'rating': 5});
      expect(sent, {'survey_id': _surveyId, 'rating': 5});
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getStringList('survero_offline_queue'), isNull);
    });

    test('sin red: encola y reenvía al hacer flush', () async {
      var online = false;
      final received = <String>[];
      final client = SurveroClient(
        apiKey: 'pk_live_test',
        baseUrl: 'https://api.test/api/v1',
        httpClient: MockClient((request) async {
          if (!online) throw http.ClientException('offline');
          received.add(request.body);
          return http.Response('{}', 201);
        }),
      );

      await client.submitResponse({'survey_id': _surveyId, 'rating': 3});
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getStringList('survero_offline_queue'), hasLength(1));

      online = true;
      await client.flushOfflineQueue();
      expect(received, hasLength(1));
      expect(prefs.getStringList('survero_offline_queue'), isEmpty);
    });

    test('un 4xx del servidor se informa y no se encola (reintentarlo no lo arregla)', () async {
      final client = SurveroClient(
        apiKey: 'sk_live_wrong',
        baseUrl: 'https://api.test/api/v1',
        httpClient: MockClient((_) async => http.Response('{"message":"Use pk_"}', 401)),
      );
      await expectLater(
        client.submitResponse({'survey_id': _surveyId, 'rating': 3}),
        throwsA(isA<SurveroException>().having((e) => e.statusCode, 'statusCode', 401)),
      );
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getStringList('survero_offline_queue'), isNull);
    });
  });
}
