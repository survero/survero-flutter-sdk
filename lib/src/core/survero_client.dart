import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../models/survey_config.dart';

/// Resultado de enviar algo al API: si se confirmó, si hay que reintentar más tarde, o si se descarta.
enum SendOutcome {
  sent,

  /// Red caída, 5xx, 408 o 429: se reintenta.
  retry,

  /// Otro 4xx: reintentarlo no lo arregla (clave inválida, payload rechazado…).
  drop,
}

SendOutcome outcomeOf(int status) {
  if (status >= 200 && status < 300) return SendOutcome.sent;
  if (status == 408 || status == 429 || status >= 500) return SendOutcome.retry;
  return SendOutcome.drop;
}

class SurveroClient {
  final String apiKey;
  final String baseUrl;
  final http.Client _httpClient;
  final DateTime Function() _now;

  /// Vigencia de la caché de configuración antes de revalidar con ETag (SDK-002).
  final Duration configTtl;

  static const cachePrefix = 'survero_survey_cache_';
  static const queueKey = 'survero_offline_queue';
  static const maxQueuedResponses = 100;
  static const maxQueuedAge = Duration(days: 7);

  SurveroClient({
    required this.apiKey,
    this.baseUrl = 'https://api.survero.com/api/v1',
    http.Client? httpClient,
    this.configTtl = const Duration(hours: 1),
    DateTime Function()? now,
  })  : _httpClient = httpClient ?? http.Client(),
        _now = now ?? DateTime.now;

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        'X-Survero-Key': apiKey,
      };

  // ───────────────────────── Encuestas ─────────────────────────

  /// Configuración de una encuesta: caché fresca → sin red; caducada → revalida con If-None-Match (304 = sigue
  /// valiendo); sin red → la caché caducada antes que nada (fail-soft).
  Future<SurveyConfig> getSurveyConfig(String surveyId) async {
    final cached = await _readCache(surveyId);
    if (cached != null && _now().difference(cached.fetchedAt) < configTtl) {
      return SurveyConfig.fromJson(cached.body);
    }

    http.Response response;
    try {
      response = await _httpClient.get(
        Uri.parse('$baseUrl/sdk/surveys/$surveyId'),
        headers: {..._headers, if (cached?.etag != null) 'If-None-Match': cached!.etag!},
      );
    } catch (e) {
      if (cached != null) return SurveyConfig.fromJson(cached.body);
      rethrow;
    }

    if (response.statusCode == 304 && cached != null) {
      await _writeCache(surveyId, cached.body, cached.etag);
      return SurveyConfig.fromJson(cached.body);
    }
    if (response.statusCode != 200) {
      if (response.statusCode == 404) await _removeCache(surveyId); // ya no existe o se desactivó
      throw SurveroException('Failed to fetch survey config: ${response.statusCode}', statusCode: response.statusCode);
    }

    final json = jsonDecode(response.body) as Map<String, dynamic>;
    await _writeCache(surveyId, json, response.headers['etag']);
    return SurveyConfig.fromJson(json);
  }

  /// Borra todas las configuraciones cacheadas (SDK-001).
  Future<void> clearCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      for (final key in prefs.getKeys().where((k) => k.startsWith(cachePrefix)).toList()) {
        await prefs.remove(key);
      }
    } catch (_) {}
  }

  Future<_CachedConfig?> _readCache(String surveyId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('$cachePrefix$surveyId');
      if (raw == null) return null;
      final json = jsonDecode(raw) as Map<String, dynamic>;
      // Formato 0.1 (solo el cuerpo): se trata como caducado.
      if (!json.containsKey('body')) return _CachedConfig(json, null, DateTime.fromMillisecondsSinceEpoch(0));
      return _CachedConfig(
        Map<String, dynamic>.from(json['body'] as Map),
        json['etag'] as String?,
        DateTime.parse(json['fetched_at'] as String),
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> _writeCache(String surveyId, Map<String, dynamic> body, String? etag) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        '$cachePrefix$surveyId',
        jsonEncode({'body': body, 'etag': ?etag, 'fetched_at': _now().toUtc().toIso8601String()}),
      );
    } catch (_) {}
  }

  Future<void> _removeCache(String surveyId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('$cachePrefix$surveyId');
    } catch (_) {}
  }

  // ───────────────────────── Respuestas ─────────────────────────

  /// Envía una respuesta con Idempotency-Key. Sin red (o 5xx/429) se encola y se reintenta en
  /// [flushOfflineQueue] con la MISMA clave, así un reintento nunca duplica. Un 4xx se lanza.
  Future<void> submitResponse(Map<String, dynamic> payload) async {
    final idempotencyKey = const Uuid().v4();
    final outcome = await _postResponse(payload, idempotencyKey);
    if (outcome == SendOutcome.retry) {
      await _queueResponse(payload, idempotencyKey);
    }
  }

  Future<SendOutcome> _postResponse(Map<String, dynamic> payload, String idempotencyKey) async {
    try {
      final response = await _httpClient.post(
        Uri.parse('$baseUrl/sdk/responses'),
        headers: {..._headers, 'Idempotency-Key': idempotencyKey},
        body: jsonEncode(payload),
      );
      final outcome = outcomeOf(response.statusCode);
      if (outcome == SendOutcome.drop) {
        throw SurveroException('Failed to submit response: ${response.statusCode}', statusCode: response.statusCode);
      }
      return outcome;
    } on SurveroException {
      rethrow;
    } catch (_) {
      return SendOutcome.retry;
    }
  }

  /// Reintenta las respuestas encoladas (SDK-003: máximo 100, se purgan a los 7 días).
  Future<void> flushOfflineQueue() async {
    final prefs = await SharedPreferences.getInstance();
    final queue = _readQueue(prefs);
    if (queue.isEmpty) return;

    final remaining = <_QueuedResponse>[];
    for (final item in queue) {
      try {
        if (await _postResponse(item.payload, item.idempotencyKey) == SendOutcome.retry) remaining.add(item);
      } on SurveroException {
        // 4xx: se descarta
      }
    }
    await prefs.setStringList(queueKey, remaining.map((e) => e.encode()).toList());
  }

  List<_QueuedResponse> _readQueue(SharedPreferences prefs) {
    final cutoff = _now().subtract(maxQueuedAge);
    final items = <_QueuedResponse>[];
    for (final raw in prefs.getStringList(queueKey) ?? const <String>[]) {
      final item = _QueuedResponse.decode(raw, _now);
      if (item != null && item.queuedAt.isAfter(cutoff)) items.add(item);
    }
    return items;
  }

  Future<void> _queueResponse(Map<String, dynamic> payload, String idempotencyKey) async {
    final prefs = await SharedPreferences.getInstance();
    final queue = _readQueue(prefs)..add(_QueuedResponse(payload, idempotencyKey, _now()));
    final kept = queue.length > maxQueuedResponses ? queue.sublist(queue.length - maxQueuedResponses) : queue;
    await prefs.setStringList(queueKey, kept.map((e) => e.encode()).toList());
  }

  // ───────────────────────── Eventos e identidad ─────────────────────────

  /// `POST /sdk/events` con un lote ya serializado. El servidor deduplica por event_id.
  Future<SendOutcome> postEvents(List<Map<String, Object?>> events) =>
      _post('/sdk/events', {'events': events}, idempotencyKey: events.isEmpty ? null : events.first['event_id'] as String?);

  Future<SendOutcome> identify({required String deviceId, required String userId}) =>
      _post('/sdk/identify', {'device_id': deviceId, 'user_id': userId});

  Future<SendOutcome> setTraits({required String deviceId, String? userId, required Map<String, Object?> traits}) =>
      _post('/sdk/traits', {'device_id': deviceId, 'user_id': ?userId, 'traits': traits});

  Future<SendOutcome> _post(String path, Object body, {String? idempotencyKey}) async {
    try {
      final response = await _httpClient.post(
        Uri.parse('$baseUrl$path'),
        headers: {..._headers, 'Idempotency-Key': ?idempotencyKey},
        body: jsonEncode(body),
      );
      return outcomeOf(response.statusCode);
    } catch (_) {
      return SendOutcome.retry;
    }
  }

  void dispose() {
    _httpClient.close();
  }
}

class _CachedConfig {
  final Map<String, dynamic> body;
  final String? etag;
  final DateTime fetchedAt;
  const _CachedConfig(this.body, this.etag, this.fetchedAt);
}

class _QueuedResponse {
  final Map<String, dynamic> payload;
  final String idempotencyKey;
  final DateTime queuedAt;

  const _QueuedResponse(this.payload, this.idempotencyKey, this.queuedAt);

  String encode() => jsonEncode({
        'payload': payload,
        'idempotency_key': idempotencyKey,
        'queued_at': queuedAt.toUtc().toIso8601String(),
      });

  /// Acepta el formato 0.1 (solo el payload) y le asigna clave y fecha nuevas.
  static _QueuedResponse? decode(String raw, DateTime Function() now) {
    try {
      final json = Map<String, dynamic>.from(jsonDecode(raw) as Map);
      if (json.containsKey('payload')) {
        return _QueuedResponse(
          Map<String, dynamic>.from(json['payload'] as Map),
          json['idempotency_key'] as String,
          DateTime.parse(json['queued_at'] as String),
        );
      }
      return _QueuedResponse(json, const Uuid().v4(), now());
    } catch (_) {
      return null;
    }
  }
}

class SurveroException implements Exception {
  final String message;
  final int? statusCode;

  const SurveroException(this.message, {this.statusCode});

  @override
  String toString() => 'SurveroException: $message';
}
