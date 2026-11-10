import 'package:flutter/foundation.dart';

/// Names: snake_case ≤ 40, or a reserved SDK event (`$...`). Same as the server.
final eventNamePattern = RegExp(r'^[a-z][a-z0-9_]{0,39}$');
final traitKeyPattern = RegExp(r'^[a-z][a-z0-9_]{0,39}$');

/// Keys the SDK sets itself or that are columns on the server: inside props the server would reject the event.
const reservedPropKeys = {
  'platform', 'app_version', 'sdk_version', 'country', 'country_ip', 'locale', 'user_id', 'device_id',
  'session_id', 'source', 'environment', 'event_id', 'event_name', 'client_ts', 'server_ts', 'project_id',
  'identity',
};

/// Reserved keys already warned about: once per key.
final _warnedReserved = <String>{};

/// JSON-ready props: booleans → 0/1 (principle 9), dates → ISO, maps/lists recursively,
/// the rest with toString(). Reserved keys are removed (they are columns; the server would reject the event) and
/// a warning is printed once per key: before, `source` disappeared without anyone noticing.
Map<String, Object?> sanitizeProps(Map<String, Object?>? props) {
  if (props == null) return const {};
  final out = <String, Object?>{};
  props.forEach((key, value) {
    if (reservedPropKeys.contains(key)) {
      if (_warnedReserved.add(key)) {
        debugPrint('Survero: prop "$key" is reserved and was dropped (the SDK sets it, or it is a column). '
            'Rename it. Reserved: ${reservedPropKeys.join(', ')}');
      }
      return;
    }
    if (key.isEmpty || key.length > 64) return;
    final clean = _sanitizeValue(value);
    if (clean != _drop) out[key] = clean;
  });
  return out;
}

const _drop = Object();

Object? _sanitizeValue(Object? value) {
  if (value == null || value is String || value is int) return value;
  if (value is bool) return value ? 1 : 0;
  if (value is double) return value.isFinite ? value : _drop;
  if (value is num) return value;
  if (value is DateTime) return value.toUtc().toIso8601String();
  if (value is Enum) return value.name;
  if (value is Map) {
    return {
      for (final entry in value.entries)
        if (_sanitizeValue(entry.value) != _drop) '${entry.key}': _sanitizeValue(entry.value),
    };
  }
  if (value is Iterable) return value.map(_sanitizeValue).where((v) => v != _drop).toList();
  return value.toString();
}
