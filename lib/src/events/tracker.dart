import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../core/survero_client.dart';
import 'event_queue.dart';
import 'identity_store.dart';
import 'props.dart';
import 'session_tracker.dart';
import 'survero_event.dart';

typedef SurveroEventListener = void Function(SurveroEvent event);

/// Núcleo de eventos del SDK (SDK-011): estampa identidad, sesión y contexto; encola; envía por lotes;
/// reintenta identify/traits pendientes; y reenvía cada evento a los sinks. Nunca lanza hacia la app.
class Tracker {
  static const pendingKey = 'survero_pending_ops';
  static const batchSize = 100;

  final SurveroClient client;
  final IdentityStore identity;
  final SessionTracker session;
  final EventQueue queue;
  final EventContext context;
  final DateTime Function() _now;

  /// false en builds debug salvo `enableInDebug`: los eventos se registran en log y sinks pero no se envían.
  final bool sendEnabled;
  final int flushAt;
  final List<SurveroEventListener> _sinks = [];
  Timer? _timer;
  Future<void>? _flushing;

  Tracker({
    required this.client,
    required this.identity,
    required this.session,
    required this.queue,
    required this.context,
    this.sendEnabled = true,
    this.flushAt = 20,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  /// Carga identidad y sesión, emite `$install` en la primera apertura y abre sesión.
  Future<void> start({Duration? flushInterval = const Duration(seconds: 15)}) async {
    await identity.load();
    await session.load();
    if (identity.isNewInstall) await _record(r'$install', const {});
    await _touchSession(_now());
    if (flushInterval != null) {
      _timer = Timer.periodic(flushInterval, (_) => flush());
    }
  }

  void addSink(SurveroEventListener sink) => _sinks.add(sink);
  void removeSink(SurveroEventListener sink) => _sinks.remove(sink);

  /// Registra un evento de la app. Nombres inválidos se descartan con un aviso en debug (no lanza).
  Future<void> track(String name, [Map<String, Object?>? props]) async {
    try {
      if (!eventNamePattern.hasMatch(name)) {
        debugPrint('Survero: ignored event "$name": names must be snake_case, ≤ 40 chars');
        return;
      }
      await _touchSession(_now());
      await _record(name, sanitizeProps(props));
      if (queue.length >= flushAt) unawaited(flush());
    } catch (e) {
      debugPrint('Survero: track failed: $e');
    }
  }

  Future<void> screen(String name, [Map<String, Object?>? props]) async {
    try {
      await _touchSession(_now());
      await _record(r'$screen', {...sanitizeProps(props), 'name': name});
    } catch (e) {
      debugPrint('Survero: screen failed: $e');
    }
  }

  /// Alias device → usuario (no reescribe eventos). Los eventos siguientes llevan el user_id.
  Future<void> identify(String userId) async {
    try {
      final id = userId.trim();
      if (id.isEmpty || id.length > 128) return;
      if (identity.userId == id) return;
      await identity.setUserId(id);
      await _sendOrKeep({'op': 'identify', 'device_id': identity.deviceId, 'user_id': id});
    } catch (e) {
      debugPrint('Survero: identify failed: $e');
    }
  }

  /// Cierre de sesión en la app: los eventos siguientes vuelven a ser anónimos (mismo device_id).
  Future<void> reset() async {
    try {
      await identity.setUserId(null);
    } catch (_) {}
  }

  /// Traits de la identidad actual (user_id si se conoce, si no el device). Valor null borra la clave.
  Future<void> setTraits(Map<String, Object?> traits) async {
    try {
      final clean = <String, Object?>{};
      traits.forEach((key, value) {
        if (!traitKeyPattern.hasMatch(key)) {
          debugPrint('Survero: ignored trait "$key": keys must be snake_case, ≤ 40 chars');
          return;
        }
        if (value == null || value is num || value is String) {
          clean[key] = value is String && value.length > 256 ? value.substring(0, 256) : value;
        } else if (value is bool) {
          clean[key] = value;
        } else {
          clean[key] = value.toString();
        }
      });
      if (clean.isEmpty) return;
      await _sendOrKeep({
        'op': 'traits',
        'device_id': identity.deviceId,
        'user_id': ?identity.userId,
        'traits': clean,
      });
    } catch (e) {
      debugPrint('Survero: setTraits failed: $e');
    }
  }

  /// Envía lo pendiente: operaciones de identidad primero (el alias antes que los eventos), luego eventos en
  /// lotes de 100. Llamadas concurrentes comparten el mismo envío.
  Future<void> flush() {
    return _flushing ??= _flush().whenComplete(() => _flushing = null);
  }

  Future<void> _flush() async {
    if (!sendEnabled) return;
    try {
      await _flushPendingOps();
      while (true) {
        final batch = await queue.peek(batchSize);
        if (batch.isEmpty) return;
        final outcome = await client.postEvents(batch.map((e) => e.toJson(context)).toList());
        if (outcome == SendOutcome.retry) return; // se reintenta en el próximo flush
        if (outcome == SendOutcome.drop) debugPrint('Survero: ${batch.length} event(s) rejected by the API');
        await queue.remove(batch.map((e) => e.eventId));
      }
    } catch (e) {
      debugPrint('Survero: flush failed: $e');
    }
  }

  /// La app pasa a segundo plano: se guarda la última actividad y se intenta enviar.
  Future<void> onBackground() async {
    try {
      await session.keepAlive(_now());
    } catch (_) {}
    await flush();
  }

  /// La app vuelve: si pasaron más de 30 min, se cierra la sesión anterior y se abre otra.
  Future<void> onForeground() => _touchSession(_now());

  void dispose() {
    _timer?.cancel();
    _timer = null;
  }

  // ── internos ──

  Future<void> _touchSession(DateTime now) async {
    final change = await session.touch(now);
    if (change == null) return;
    if (change.endedSessionId != null) {
      await _record(
        r'$session_ended',
        {if (change.endedDuration != null) 'duration_s': change.endedDuration!.inSeconds},
        sessionId: change.endedSessionId,
        at: change.endedAt,
      );
    }
    await _record(r'$session_started', const {}, sessionId: change.startedSessionId, at: now);
  }

  Future<void> _record(String name, Map<String, Object?> props, {String? sessionId, DateTime? at}) async {
    final event = SurveroEvent(
      eventId: const Uuid().v4(),
      name: name,
      props: props,
      clientTs: at ?? _now(),
      deviceId: identity.deviceId,
      userId: identity.userId,
      sessionId: sessionId ?? session.sessionId,
    );
    for (final sink in List.of(_sinks)) {
      try {
        sink(event);
      } catch (e) {
        debugPrint('Survero: sink failed: $e');
      }
    }
    if (!sendEnabled) {
      debugPrint('Survero (debug, not sent): $event');
      return;
    }
    await queue.add(event);
  }

  Future<void> _sendOrKeep(Map<String, Object?> op) async {
    if (!sendEnabled) {
      debugPrint('Survero (debug, not sent): ${op['op']}');
      return;
    }
    if (await _sendOp(op) == SendOutcome.retry) {
      final prefs = await SharedPreferences.getInstance();
      final pending = prefs.getStringList(pendingKey) ?? <String>[];
      pending.add(jsonEncode(op));
      await prefs.setStringList(pendingKey, pending.length > 50 ? pending.sublist(pending.length - 50) : pending);
    }
  }

  Future<SendOutcome> _sendOp(Map<String, Object?> op) {
    if (op['op'] == 'identify') {
      return client.identify(deviceId: op['device_id'] as String, userId: op['user_id'] as String);
    }
    return client.setTraits(
      deviceId: op['device_id'] as String,
      userId: op['user_id'] as String?,
      traits: Map<String, Object?>.from(op['traits'] as Map),
    );
  }

  Future<void> _flushPendingOps() async {
    final prefs = await SharedPreferences.getInstance();
    final pending = prefs.getStringList(pendingKey) ?? const <String>[];
    if (pending.isEmpty) return;
    final remaining = <String>[];
    for (final raw in pending) {
      try {
        final op = Map<String, Object?>.from(jsonDecode(raw) as Map);
        if (await _sendOp(op) == SendOutcome.retry) remaining.add(raw);
      } catch (_) {}
    }
    await prefs.setStringList(pendingKey, remaining);
  }
}
