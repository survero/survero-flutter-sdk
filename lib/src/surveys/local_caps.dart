import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Caps locales (SDK-014): como mucho una impresión cada [cooldown] para el dispositivo, dos descartes de una
/// encuesta = nunca más, respondida = nunca más. El servidor tiene los suyos; estos evitan pedirle a la red algo
/// que ya se sabe que no se va a mostrar, y protegen si el servidor no responde.
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

  /// Razón para no mostrar nada antes de preguntar al servidor (solo el cooldown se sabe sin conocer la encuesta).
  Future<String?> blockBeforeServer() async {
    final last = (await _read())['last_shown_at'] as String?;
    if (last != null && _now().difference(DateTime.parse(last)) < cooldown) return 'cooldown';
    return null;
  }

  /// Razón para no mostrar una encuesta concreta.
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
