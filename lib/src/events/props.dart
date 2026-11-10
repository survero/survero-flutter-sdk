import 'package:flutter/foundation.dart';

/// Nombres: snake_case ≤ 40, o un evento reservado del SDK (`$...`). Igual que el servidor.
final eventNamePattern = RegExp(r'^[a-z][a-z0-9_]{0,39}$');
final traitKeyPattern = RegExp(r'^[a-z][a-z0-9_]{0,39}$');

/// Claves que son columnas en el servidor: dentro de props el evento se rechazaría.
const reservedPropKeys = {
  'platform', 'app_version', 'sdk_version', 'country', 'country_ip', 'locale', 'user_id', 'device_id',
  'session_id', 'source', 'environment', 'event_id', 'event_name', 'client_ts', 'server_ts', 'project_id',
  'identity',
};

/// Reservadas ya avisadas: una vez por clave.
final _warnedReserved = <String>{};

/// Props listas para JSON: booleanos → 0/1 (principio 9), fechas → ISO, mapas/listas recursivos,
/// el resto con toString(). Las claves reservadas se quitan (son columnas; el servidor rechazaría el evento) y se
/// avisa una vez por clave: antes `source` desaparecía sin que nadie lo viera.
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
