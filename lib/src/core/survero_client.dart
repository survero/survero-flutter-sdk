import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/survey_config.dart';

class SurveroClient {
  final String apiKey;
  final String baseUrl;
  final http.Client _httpClient;

  static const _cachePrefix = 'survero_survey_cache_';
  static const _queueKey = 'survero_offline_queue';

  SurveroClient({
    required this.apiKey,
    this.baseUrl = 'https://api.survero.com/api/v1',
    http.Client? httpClient,
  }) : _httpClient = httpClient ?? http.Client();

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        'X-Survero-Key': apiKey,
      };

  /// Fetch survey config from API, with local caching.
  Future<SurveyConfig> getSurveyConfig(String surveyId) async {
    // Try cache first
    final cached = await _getCachedConfig(surveyId);
    if (cached != null) return cached;

    // Fetch from API
    final response = await _httpClient.get(
      Uri.parse('$baseUrl/sdk/surveys/$surveyId'),
      headers: _headers,
    );

    if (response.statusCode != 200) {
      throw SurveroException(
        'Failed to fetch survey config: ${response.statusCode}',
        statusCode: response.statusCode,
      );
    }

    final json = jsonDecode(response.body) as Map<String, dynamic>;
    final config = SurveyConfig.fromJson(json);

    // Cache locally
    await _cacheConfig(surveyId, response.body);

    return config;
  }

  /// Submit a survey response.
  Future<void> submitResponse(Map<String, dynamic> payload) async {
    try {
      final response = await _httpClient.post(
        Uri.parse('$baseUrl/sdk/responses'),
        headers: _headers,
        body: jsonEncode(payload),
      );

      if (response.statusCode != 201 && response.statusCode != 200) {
        throw SurveroException(
          'Failed to submit response: ${response.statusCode}',
          statusCode: response.statusCode,
        );
      }
    } catch (e) {
      if (e is SurveroException) rethrow;
      // Network error — queue for later
      await _queueResponse(payload);
    }
  }

  /// Retry any queued offline responses.
  Future<void> flushOfflineQueue() async {
    final prefs = await SharedPreferences.getInstance();
    final queue = prefs.getStringList(_queueKey) ?? [];

    if (queue.isEmpty) return;

    final remaining = <String>[];
    for (final item in queue) {
      try {
        final payload = jsonDecode(item) as Map<String, dynamic>;
        final response = await _httpClient.post(
          Uri.parse('$baseUrl/sdk/responses'),
          headers: _headers,
          body: jsonEncode(payload),
        );
        if (response.statusCode != 200 && response.statusCode != 201) {
          remaining.add(item);
        }
      } catch (_) {
        remaining.add(item);
      }
    }

    await prefs.setStringList(_queueKey, remaining);
  }

  Future<SurveyConfig?> _getCachedConfig(String surveyId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cached = prefs.getString('$_cachePrefix$surveyId');
      if (cached == null) return null;

      final json = jsonDecode(cached) as Map<String, dynamic>;
      return SurveyConfig.fromJson(json);
    } catch (_) {
      return null;
    }
  }

  Future<void> _cacheConfig(String surveyId, String jsonString) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('$_cachePrefix$surveyId', jsonString);
  }

  Future<void> _queueResponse(Map<String, dynamic> payload) async {
    final prefs = await SharedPreferences.getInstance();
    final queue = prefs.getStringList(_queueKey) ?? [];
    queue.add(jsonEncode(payload));
    await prefs.setStringList(_queueKey, queue);
  }

  void dispose() {
    _httpClient.close();
  }
}

class SurveroException implements Exception {
  final String message;
  final int? statusCode;

  const SurveroException(this.message, {this.statusCode});

  @override
  String toString() => 'SurveroException: $message';
}
