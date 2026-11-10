import '../core/survero.dart';

/// Bridge for apps that already have their own analytics service (SDK-012): call it from that service and it
/// forwards to Survero without touching every call in the app.
///
/// ```dart
/// final survero = SurveroSink(deny: {'debug_tap'});
/// void _log(String name, Map<String, Object?> params) {
///   firebase.logEvent(name: name, parameters: params);
///   survero.log(name, params);
/// }
/// ```
///
/// Keys that are columns in Survero (platform, app_version, locale, user_id…) are removed from props:
/// the SDK already stamps them on every event.
class SurveroSink {
  /// If not null, only these names are forwarded.
  final Set<String>? allow;
  final Set<String> deny;

  /// Optional renaming (app names → Survero names).
  final String Function(String name)? rename;

  const SurveroSink({this.allow, this.deny = const {}, this.rename});

  void log(String name, [Map<String, Object?>? params]) {
    if (deny.contains(name)) return;
    if (allow != null && !allow!.contains(name)) return;
    Survero.track(rename?.call(name) ?? name, params);
  }
}
