import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Local caps (SDK-014): at most one impression every [cooldown] for the device, two dismissals of a
/// survey = never again, answered = never again. The server has its own; these avoid asking the network for something
/// that is already known not to be shown, and protect when the server does not respond.
class LocalCaps {
  static const storageKey = 'survero_survey_caps';

  final Duration cooldown;
  final int maxDismissals;
  final DateTime Function() _now;

  LocalCaps({this.cooldown = const Duration(days: 7), this.maxDismissals = 2, DateTime Function()? now})
      : _now = now ?? DateTime.now;

  Future<Map<String, dynamic>> _read() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(storageKey);
      if (raw != null) return Map<String, dynamic>.from(jsonDecode(raw) as Map);
    } catch (_) {}
    return {'dismissed': <String, dynamic>{}, 'answered': <dynamic>[]};
  }

  Future<void> _write(Map<String, dynamic> data) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(storageKey, jsonEncode(data));
    } catch (_) {}
  }

  /// Reason to show nothing before asking the server (only the cooldown is known without knowing the survey).
  Future<String?> blockBeforeServer() async {
    final last = (await _read())['last_shown_at'] as String?;
    if (last != null && _now().difference(DateTime.parse(last)) < cooldown) return 'cooldown';
    return null;
  }

  /// Reason not to show a specific survey.
  Future<String?> blockSurvey(String slug) async {
    final data = await _read();
    if ((data['answered'] as List).contains(slug)) return 'answered';
    if (((data['dismissed'] as Map)[slug] as int? ?? 0) >= maxDismissals) return 'dismissed_max';
    final last = data['last_shown_at'] as String?;
    if (last != null && _now().difference(DateTime.parse(last)) < cooldown) return 'cooldown';
    return null;
  }

  Future<void> recordShown() async {
    final data = await _read();
    data['last_shown_at'] = _now().toUtc().toIso8601String();
    await _write(data);
  }

  Future<void> recordDismissed(String slug) async {
    final data = await _read();
    final dismissed = Map<String, dynamic>.from(data['dismissed'] as Map);
    dismissed[slug] = (dismissed[slug] as int? ?? 0) + 1;
    data['dismissed'] = dismissed;
    await _write(data);
  }

  Future<void> recordAnswered(String slug) async {
    final data = await _read();
    data['answered'] = {...(data['answered'] as List).cast<String>(), slug}.toList();
    await _write(data);
  }

  Future<void> clear() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(storageKey);
    } catch (_) {}
  }
}
