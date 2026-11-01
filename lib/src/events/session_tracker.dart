import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

/// Transición de sesión que el tracker convierte en eventos.
class SessionChange {
  /// Sesión que terminó (para `$session_ended`), si la había.
  final String? endedSessionId;
  final DateTime? endedAt;
  final Duration? endedDuration;

  /// Sesión que empieza (para `$session_started`).
  final String startedSessionId;

  const SessionChange({
    required this.startedSessionId,
    this.endedSessionId,
    this.endedAt,
    this.endedDuration,
  });
}

/// Sesiones por inactividad (por defecto 30 min, como Shadow English). Persistida: una app que se reabre a los
/// 5 minutos sigue en la misma sesión aunque el proceso haya muerto.
class SessionTracker {
  static const _idKey = 'survero_session_id';
  static const _startKey = 'survero_session_start';
  static const _lastKey = 'survero_session_last';

  final Duration timeout;
  String? _id;
  DateTime? _start;
  DateTime? _last;

  SessionTracker({this.timeout = const Duration(minutes: 30)});

  String? get sessionId => _id;

  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _id = prefs.getString(_idKey);
      final start = prefs.getString(_startKey);
      final last = prefs.getString(_lastKey);
      _start = start == null ? null : DateTime.tryParse(start);
      _last = last == null ? null : DateTime.tryParse(last);
      if (_start == null || _last == null) _id = null;
    } catch (_) {}
  }

  /// Registra actividad en [now]. Si no hay sesión o pasó [timeout] desde la última actividad, abre una nueva
  /// y devuelve el cambio (con la anterior cerrada en su última actividad).
  Future<SessionChange?> touch(DateTime now) async {
    SessionChange? change;
    if (_id == null || _last == null || now.difference(_last!) > timeout) {
      final previousId = _id;
      final previousStart = _start;
      final previousLast = _last;
      _id = const Uuid().v4();
      _start = now;
      change = SessionChange(
        startedSessionId: _id!,
        endedSessionId: previousId,
        endedAt: previousLast,
        endedDuration: previousId != null && previousStart != null && previousLast != null
            ? previousLast.difference(previousStart)
            : null,
      );
    }
    _last = now;
    await _save();
    return change;
  }

  /// Marca actividad sin abrir sesión nueva (al pasar a segundo plano).
  Future<void> keepAlive(DateTime now) async {
    if (_id == null) return;
    _last = now;
    await _save();
  }

  Future<void> _save() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_idKey, _id!);
      await prefs.setString(_startKey, _start!.toUtc().toIso8601String());
      await prefs.setString(_lastKey, _last!.toUtc().toIso8601String());
    } catch (_) {}
  }
}
