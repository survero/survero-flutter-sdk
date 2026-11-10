import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

/// Session transition the tracker turns into events.
class SessionChange {
  /// Session that ended (for `$session_ended`), if any.
  final String? endedSessionId;
  final DateTime? endedAt;
  final Duration? endedDuration;

  /// Session that starts (for `$session_started`).
  final String startedSessionId;

  const SessionChange({
    required this.startedSessionId,
    this.endedSessionId,
    this.endedAt,
    this.endedDuration,
  });
}

/// Inactivity-based sessions (30 min by default, like Shadow English). Persisted: an app reopened after
/// 5 minutes stays in the same session even if the process died.
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

  /// Records activity at [now]. If there is no session or [timeout] passed since the last activity, opens a new one
  /// and returns the change (with the previous one closed at its last activity).
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

  /// Marks activity without opening a new session (when going to background).
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
