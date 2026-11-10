import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'survero_event.dart';

/// Persistent queue of events waiting to be sent (SDK-003): at most [maxSize] (the oldest are
/// dropped) and nothing older than [maxAge]. It survives app restarts.
class EventQueue {
  static const storageKey = 'survero_event_queue';

  final int maxSize;
  final Duration maxAge;
  final DateTime Function() _now;
  final List<SurveroEvent> _events = [];
  bool _loaded = false;

  EventQueue({this.maxSize = 100, this.maxAge = const Duration(days: 7), DateTime Function()? now})
      : _now = now ?? DateTime.now;

  int get length => _events.length;

  Future<void> _load() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      for (final raw in prefs.getStringList(storageKey) ?? const <String>[]) {
        try {
          _events.add(SurveroEvent.fromStorage(Map<String, Object?>.from(jsonDecode(raw) as Map)));
        } catch (_) {
          // entrada corrupta: se descarta
        }
      }
      _purge();
    } catch (_) {
      // sin almacenamiento: la cola vive solo en memoria
    }
  }

  void _purge() {
    final cutoff = _now().subtract(maxAge);
    _events.removeWhere((e) => e.clientTs.isBefore(cutoff));
    if (_events.length > maxSize) _events.removeRange(0, _events.length - maxSize);
  }

  Future<void> _save() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(storageKey, _events.map((e) => jsonEncode(e.toStorage())).toList());
    } catch (_) {}
  }

  Future<void> add(SurveroEvent event) async {
    await _load();
    _events.add(event);
    _purge();
    await _save();
  }

  /// The first [max] events, without removing them (they are removed with [remove] when the server confirms them).
  Future<List<SurveroEvent>> peek(int max) async {
    await _load();
    _purge();
    return List.unmodifiable(_events.take(max));
  }

  Future<void> remove(Iterable<String> eventIds) async {
    await _load();
    final ids = eventIds.toSet();
    _events.removeWhere((e) => ids.contains(e.eventId));
    await _save();
  }

  Future<void> clear() async {
    _events.clear();
    _loaded = true;
    await _save();
  }
}
