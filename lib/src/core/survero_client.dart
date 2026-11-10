import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../models/survey_config.dart';

/// Result of sending something to the API: confirmed, retry later, or dropped.
enum SendOutcome {
  sent,

  /// Network down, 5xx, 408 or 429: retried.
  retry,

  /// Any other 4xx: retrying will not fix it (invalid key, rejected payload…).
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

  /// How long the config cache is valid before revalidating with ETag (SDK-002).
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

  /// A survey's configuration: fresh cache → no network; expired → revalidates with If-None-Match (304 = still
  /// valid); no network → the expired cache rather than nothing (fail-soft).
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

  /// Deletes all cached configurations (SDK-001).
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

  /// Sends a response with an Idempotency-Key. With no network (or 5xx/429) it is queued and retried in
  /// [flushOfflineQueue] with the SAME key, so a retry never duplicates. A 4xx throws.
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

  /// Retries the queued responses (SDK-003: at most 100, purged after 7 days).
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

  /// `POST /sdk/events` with an already serialized batch. The server deduplicates by event_id.
  Future<SendOutcome> postEvents(List<Map<String, Object?>> events) =>
      _post('/sdk/events', {'events': events}, idempotencyKey: events.isEmpty ? null : events.first['event_id'] as String?);

  Future<SendOutcome> identify({required String deviceId, required String userId}) =>
      _post('/sdk/identify', {'device_id': deviceId, 'user_id': userId});

  Future<SendOutcome> setTraits({required String deviceId, String? userId, required Map<String, Object?> traits}) =>
      _post('/sdk/traits', {'device_id': deviceId, 'user_id': ?userId, 'traits': traits});

  // ───────────────────────── Encuestas v2 ─────────────────────────

  static const triggersKey = 'survero_survey_triggers';

  /// Events that can trigger a survey (1 h cache + ETag). No network: the last known list.
  Future<Set<String>> getTriggers() async {
    Map<String, dynamic>? cached;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(triggersKey);
      if (raw != null) cached = Map<String, dynamic>.from(jsonDecode(raw) as Map);
    } catch (_) {}
    Set<String> fromCache() => {...((cached?['triggers'] as List?) ?? const []).cast<String>()};

    if (cached != null && _now().difference(DateTime.parse(cached['fetched_at'] as String)) < configTtl) {
      return fromCache();
    }
    try {
      final response = await _httpClient.get(
        Uri.parse('$baseUrl/sdk/surveys/triggers'),
        headers: {..._headers, if (cached?['etag'] != null) 'If-None-Match': cached!['etag'] as String},
      );
      List<dynamic>? triggers;
      if (response.statusCode == 304 && cached != null) {
        triggers = cached['triggers'] as List;
      } else if (response.statusCode == 200) {
        triggers = (jsonDecode(response.body) as Map)['triggers'] as List;
      } else {
        return fromCache();
      }
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        triggersKey,
        jsonEncode({
          'triggers': triggers,
          'etag': ?response.headers['etag'] ?? cached?['etag'],
          'fetched_at': _now().toUtc().toIso8601String(),
        }),
      );
      return {...triggers.cast<String>()};
    } catch (_) {
      return fromCache();
    }
  }

  /// The server gate. Returns the JSON (`survey`, `reason`), or null with no network / on error.
  Future<Map<String, dynamic>?> eligible(Map<String, String> query) async {
    try {
      final response = await _httpClient.get(
        Uri.parse('$baseUrl/sdk/surveys/eligible').replace(queryParameters: query),
        headers: _headers,
      );
      if (response.statusCode != 200) return null;
      return Map<String, dynamic>.from(jsonDecode(response.body) as Map);
    } catch (_) {
      return null;
    }
  }

  Future<SendOutcome> postExposure(String surveyId, Map<String, Object?> body) =>
      _post('/sdk/surveys/$surveyId/exposure', body);

  Future<SendOutcome> postSurveyResponse(String surveyId, Map<String, Object?> body) =>
      _post('/sdk/surveys/$surveyId/response', body);

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

  /// Accepts the 0.1 format (payload only) and assigns it a new key and date.
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
