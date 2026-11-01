import '../core/survero.dart';

/// Puente para apps que ya tienen su propio servicio de analítica (SDK-012): se llama desde ese servicio y
/// reenvía a Survero sin tocar cada llamada de la app.
///
/// ```dart
/// final survero = SurveroSink(deny: {'debug_tap'});
/// void _log(String name, Map<String, Object?> params) {
///   firebase.logEvent(name: name, parameters: params);
///   survero.log(name, params);
/// }
/// ```
///
/// Las claves que en Survero son columnas (platform, app_version, locale, user_id…) se quitan de props:
/// el SDK ya las estampa en cada evento.
class SurveroSink {
  /// Si no es null, solo se reenvían estos nombres.
  final Set<String>? allow;
  final Set<String> deny;

  /// Renombrado opcional (nombres de la app → nombres en Survero).
  final String Function(String name)? rename;

  const SurveroSink({this.allow, this.deny = const {}, this.rename});

  void log(String name, [Map<String, Object?>? params]) {
    if (deny.contains(name)) return;
    if (allow != null && !allow!.contains(name)) return;
    Survero.track(rename?.call(name) ?? name, params);
  }
}
