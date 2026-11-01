import 'dart:convert';

/// Un evento tal como lo registra el SDK (y lo reciben los sinks de [Survero.addSink]).
class SurveroEvent {
  final String eventId;
  final String name;
  final Map<String, Object?> props;
  final DateTime clientTs;
  final String deviceId;
  final String? userId;
  final String? sessionId;

  const SurveroEvent({
    required this.eventId,
    required this.name,
    required this.props,
    required this.clientTs,
    required this.deviceId,
    this.userId,
    this.sessionId,
  });

  /// Cuerpo de un evento de `POST /sdk/events` con el contexto del dispositivo estampado como columnas.
  Map<String, Object?> toJson(EventContext context) => {
        'event_id': eventId,
        'event_name': name,
        'device_id': deviceId,
        'user_id': ?userId,
        'session_id': ?sessionId,
        'props': props,
        'client_ts': clientTs.toUtc().toIso8601String(),
        'app_version': ?context.appVersion,
        'platform': context.platform,
        'sdk_version': context.sdkVersion,
        'country': ?context.country,
        'locale': ?context.locale,
      };

  Map<String, Object?> toStorage() => {
        'event_id': eventId,
        'event_name': name,
        'props': props,
        'client_ts': clientTs.toUtc().toIso8601String(),
        'device_id': deviceId,
        'user_id': ?userId,
        'session_id': ?sessionId,
      };

  factory SurveroEvent.fromStorage(Map<String, Object?> json) => SurveroEvent(
        eventId: json['event_id'] as String,
        name: json['event_name'] as String,
        props: Map<String, Object?>.from(json['props'] as Map? ?? const {}),
        clientTs: DateTime.parse(json['client_ts'] as String),
        deviceId: json['device_id'] as String,
        userId: json['user_id'] as String?,
        sessionId: json['session_id'] as String?,
      );

  @override
  String toString() => 'SurveroEvent($name ${jsonEncode(props)})';
}

/// Dimensiones de corte que el SDK estampa en cada evento (columnas en el servidor, nunca props).
class EventContext {
  final String platform;
  final String sdkVersion;
  final String? appVersion;
  final String? locale;
  final String? country;

  const EventContext({
    required this.platform,
    required this.sdkVersion,
    this.appVersion,
    this.locale,
    this.country,
  });

  /// `es_CO` / `es-CO` → país `CO`. Es la región del locale, no geo por IP.
  static String? countryFromLocale(String? locale) {
    if (locale == null) return null;
    final parts = locale.split(RegExp('[_-]'));
    for (final part in parts.skip(1)) {
      if (RegExp(r'^[A-Za-z]{2}$').hasMatch(part)) return part.toUpperCase();
    }
    return null;
  }
}
