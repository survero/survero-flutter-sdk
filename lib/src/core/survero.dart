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
/// await Survero.init(apiKey: 'sk_live_xxxxxxxxxxxx');
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
  static const String sdkVersion = '0.1.0';

  Survero._();

  /// Initialize the SDK. Call once at app startup.
  static Future<void> init({
    required String apiKey,
    String? baseUrl,
    String? appVersion,
  }) async {
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
      final payload = {
        'surveyId': surveyId,
        'rating': result.rating,
        if (result.comment != null && result.comment!.isNotEmpty)
          'comment': result.comment,
        'deviceOs': deviceInfo.deviceOs,
        'deviceModel': deviceInfo.deviceModel,
        'appVersion': _appVersion,
        'sdkVersion': sdkVersion,
        'locale': deviceInfo.locale,
        'sessionId': _sessionId,
      };

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
