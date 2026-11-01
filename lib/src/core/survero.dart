import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../models/models.dart';
import '../ui/star_rating_modal.dart';
import '../utils/device_info_collector.dart';
import 'survero_client.dart';

/// Main entry point for the Survero SDK.
///
/// ```dart
/// // Initialize once in main.dart
/// // Use the project PUBLIC key (pk_). Secret keys (sk_) never go in an app.
/// await Survero.init(apiKey: 'pk_live_xxxxxxxxxxxx');
///
/// // Show a survey anywhere
/// Survero.show(
///   context: context,
///   surveyId: 'survey_abc123',
///   onComplete: (response) => print('Rating: ${response.rating}'),
///   onDismiss: () => print('Dismissed'),
/// );
/// ```
class Survero {
  static SurveroClient? _client;
  static String? _sessionId;
  static String? _appVersion;
  static const String sdkVersion = '0.2.0';

  Survero._();

  /// Initialize the SDK. Call once at app startup.
  static Future<void> init({
    required String apiKey,
    String? baseUrl,
    String? appVersion,
  }) async {
    if (apiKey.startsWith('sk_')) {
      // Fail-soft: no se lanza, pero el servidor rechaza las sk_ en /sdk/* y la clave quedaría expuesta.
      debugPrint(
        'Survero: you passed a SECRET key (sk_). Apps must use the project PUBLIC key (pk_): '
        'secret keys can be extracted from the app and the API rejects them on SDK routes.',
      );
    }
    _client = SurveroClient(
      apiKey: apiKey,
      baseUrl: baseUrl ?? 'https://api.survero.com/api/v1',
    );
    _sessionId = const Uuid().v4();
    _appVersion = appVersion ?? 'unknown';

    // Try to flush any offline responses from previous sessions
    await _client!.flushOfflineQueue();
  }

  /// Show a survey modal.
  static Future<void> show({
    required BuildContext context,
    required String surveyId,
    void Function(SurveroResponse response)? onComplete,
    VoidCallback? onDismiss,
  }) async {
    assert(_client != null, 'Survero.init() must be called before Survero.show()');

    final client = _client!;

    // Fetch survey config
    final SurveyConfig config;
    try {
      config = await client.getSurveyConfig(surveyId);
    } catch (e) {
      debugPrint('Survero: Failed to load survey config: $e');
      return;
    }

    if (!config.isActive) {
      debugPrint('Survero: Survey $surveyId is not active');
      return;
    }

    if (!context.mounted) return;

    // Collect device info
    final deviceInfo = await DeviceInfoCollector.collect();

    if (!context.mounted) return;

    // Show the modal
    final result = await showModalBottomSheet<SurveroResponse>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => StarRatingModal(config: config),
    );

    if (result != null) {
      // Submit response
      final payload = buildResponsePayload(
        surveyId: surveyId,
        response: result,
        device: deviceInfo,
        appVersion: _appVersion,
        sdkVersion: sdkVersion,
        sessionId: _sessionId,
      );

      try {
        await client.submitResponse(payload);
      } catch (e) {
        debugPrint('Survero: Failed to submit response: $e');
      }

      onComplete?.call(result);
    } else {
      onDismiss?.call();
    }
  }

  /// Clear cached survey configs.
  static Future<void> clearCache() async {
    // SharedPreferences keys are cleared individually by SurveroClient
    debugPrint('Survero: Cache cleared');
  }

  /// Dispose the SDK client.
  static void dispose() {
    _client?.dispose();
    _client = null;
    _sessionId = null;
  }
}

/// Cuerpo de `POST /sdk/responses` (contrato snake_case del API).
@visibleForTesting
Map<String, dynamic> buildResponsePayload({
  required String surveyId,
  required SurveroResponse response,
  required DeviceMetadata device,
  String? appVersion,
  required String sdkVersion,
  String? sessionId,
}) {
  final comment = response.comment?.trim();
  return {
    'survey_id': surveyId,
    'rating': response.rating,
    if (comment != null && comment.isNotEmpty) 'comment': comment,
    'device_os': device.deviceOs,
    'device_model': device.deviceModel,
    'app_version': ?appVersion,
    'sdk_version': sdkVersion,
    'locale': device.locale,
    'session_id': ?sessionId,
  };
}
