import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../models/models.dart';
import '../ui/star_rating_modal.dart';
import '../utils/device_info_collector.dart';
import 'survero_client.dart';
import '../events/event_queue.dart';
import '../events/identity_store.dart';
import '../events/session_tracker.dart';
import '../events/survero_event.dart';
import '../events/tracker.dart';
import '../surveys/survero_surveys.dart';

/// SDK entry point.
///
/// ```dart
/// // Once, at startup. The project's PUBLIC key (pk_); never a secret key (sk_) in an app.
/// await Survero.init(apiKey: 'pk_live_xxxxxxxx', appVersion: '2.4.0');
///
/// Survero.track('story_completed', {'story': 'abc', 'duration': 42});
/// Survero.identify('user-123');            // on login
/// Survero.setTraits({'plan': 'premium'});
/// Survero.show(context: context, surveyId: '…');
/// ```
///
/// None of this throws into the app: an event or a survey never breaks the screen that triggered it.
class Survero {
  static SurveroClient? _client;
  static Tracker? _tracker;
  static _LifecycleObserver? _observer;
  static String? _appVersion;
  static const String sdkVersion = '0.4.1';

  /// Surveys v2: `Survero.surveys.show('sean-ellis')`, automatic triggering by event, theme and custom renderer.
  static final SurveroSurveys surveys = SurveroSurveys.internal();

  Survero._();

  static bool get isInitialized => _client != null;

  /// Initializes the SDK. Call it once at startup.
  ///
  /// - [userId]: if the app already knows the user (same as calling [identify]).
  /// - [enableInDebug]: in debug builds events are NOT sent (only log and sinks) unless this is true;
  ///   so QA reinstalls do not inflate the data. Surveys always work.
  static Future<void> init({
    required String apiKey,
    String? baseUrl,
    String? appVersion,
    String? userId,
    bool enableInDebug = false,
    Duration flushInterval = const Duration(seconds: 15),
  }) async {
    if (apiKey.startsWith('sk_')) {
      // Fail-soft: no se lanza, pero el servidor rechaza las sk_ en /sdk/* y la clave quedaría expuesta.
      debugPrint(
        'Survero: you passed a SECRET key (sk_). Apps must use the project PUBLIC key (pk_): '
        'secret keys can be extracted from the app and the API rejects them on SDK routes.',
      );
    }
    dispose();
    final client = SurveroClient(apiKey: apiKey, baseUrl: baseUrl ?? 'https://api.survero.com/api/v1');
    _client = client;
    _appVersion = appVersion;

    try {
      final device = await DeviceInfoCollector.collect();
      final tracker = Tracker(
        client: client,
        identity: IdentityStore(),
        session: SessionTracker(),
        queue: EventQueue(),
        context: EventContext(
          platform: DeviceInfoCollector.platformName(),
          sdkVersion: 'flutter/$sdkVersion',
          appVersion: appVersion,
          locale: device.locale,
          country: EventContext.countryFromLocale(device.locale),
        ),
        sendEnabled: !kDebugMode || enableInDebug,
      );
      _tracker = tracker;
      await tracker.start(flushInterval: flushInterval);
      surveys.bind(tracker: tracker, client: client, context: tracker.context);
      if (userId != null) await tracker.identify(userId);
      _observer = _LifecycleObserver(tracker);
      WidgetsBinding.instance.addObserver(_observer!);
      unawaited(tracker.flush());
    } catch (e) {
      debugPrint('Survero: event tracking unavailable: $e');
    }

    // Respuestas que no se pudieron enviar en sesiones anteriores.
    unawaited(client.flushOfflineQueue().catchError((Object e) => debugPrint('Survero: $e')));
  }

  /// Records an event. Name in snake_case (≤ 40). Booleans are sent as 0/1.
  static Future<void> track(String name, [Map<String, Object?>? props]) async =>
      _tracker?.track(name, props);

  /// Records a screen view (`$screen` event with `name`).
  static Future<void> screen(String name, [Map<String, Object?>? props]) async => _tracker?.screen(name, props);

  /// Links this device to an app user. It does not rewrite history: Survero resolves identity
  /// at read time, so what happened before login is attributed to the user.
  static Future<void> identify(String userId) async => _tracker?.identify(userId);

  /// Logout: subsequent events are anonymous again.
  static Future<void> reset() async => _tracker?.reset();

  /// User traits (or device traits, if there is no identify yet). `null` deletes the key.
  static Future<void> setTraits(Map<String, Object?> traits) async => _tracker?.setTraits(traits);

  static Future<void> setTrait(String key, Object? value) => setTraits({key: value});

  /// Sends pending data now (this also happens on its own every 15 s, at 20 events and when going to background).
  static Future<void> flush() async => _tracker?.flush();

  /// Forwards every event to another tool (e.g. Firebase Analytics).
  static void addSink(SurveroEventListener sink) => _tracker?.addSink(sink);

  static void removeSink(SurveroEventListener sink) => _tracker?.removeSink(sink);

  /// Star survey by id (0.1–0.3 API). For v2 surveys use [surveys]: `Survero.surveys.show(slug)`.
  @Deprecated('Use Survero.surveys.show(slug): it applies eligibility rules and caps')
  static Future<void> show({
    required BuildContext context,
    required String surveyId,
    void Function(SurveroResponse response)? onComplete,
    VoidCallback? onDismiss,
  }) async {
    final client = _client;
    if (client == null) {
      debugPrint('Survero: call Survero.init() before Survero.show()');
      return;
    }

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
    final deviceInfo = await DeviceInfoCollector.collect();
    if (!context.mounted) return;

    final result = await showModalBottomSheet<SurveroResponse>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => StarRatingModal(config: config),
    );

    if (result != null) {
      final payload = buildResponsePayload(
        surveyId: surveyId,
        response: result,
        device: deviceInfo,
        appVersion: _appVersion,
        sdkVersion: sdkVersion,
        sessionId: _tracker?.session.sessionId,
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

  /// Deletes the cached survey configurations.
  static Future<void> clearCache() async => _client?.clearCache();

  /// Releases the SDK (tests, project switch). Pending events stay on disk.
  static void dispose() {
    if (_observer != null) {
      WidgetsBinding.instance.removeObserver(_observer!);
      _observer = null;
    }
    surveys.unbind();
    _tracker?.dispose();
    _tracker = null;
    _client?.dispose();
    _client = null;
  }
}

class _LifecycleObserver with WidgetsBindingObserver {
  final Tracker tracker;
  _LifecycleObserver(this.tracker);

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        unawaited(tracker.onForeground());
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
      case AppLifecycleState.detached:
        unawaited(tracker.onBackground());
      case AppLifecycleState.inactive:
        break;
    }
  }
}

/// Body of `POST /sdk/responses` (the API's snake_case contract).
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
