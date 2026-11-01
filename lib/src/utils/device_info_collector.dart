import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';

class DeviceMetadata {
  final String deviceOs;
  final String deviceModel;

  /// Etiqueta BCP 47 del idioma del sistema (`es-CO`).
  final String locale;

  const DeviceMetadata({
    required this.deviceOs,
    required this.deviceModel,
    required this.locale,
  });
}

class DeviceInfoCollector {
  static final _plugin = DeviceInfoPlugin();

  /// Sin dart:io: funciona también en web.
  static String systemLocale() {
    try {
      return PlatformDispatcher.instance.locale.toLanguageTag();
    } catch (_) {
      return 'und';
    }
  }

  /// `ios`, `android`, `web`, `macos`, `windows`, `linux`… (columna platform de los eventos).
  static String platformName() => kIsWeb ? 'web' : defaultTargetPlatform.name.toLowerCase();

  static Future<DeviceMetadata> collect() async {
    final locale = systemLocale();
    try {
      if (kIsWeb) {
        final info = await _plugin.webBrowserInfo;
        return DeviceMetadata(deviceOs: 'web', deviceModel: info.browserName.name, locale: locale);
      }
      switch (defaultTargetPlatform) {
        case TargetPlatform.android:
          final info = await _plugin.androidInfo;
          return DeviceMetadata(
            deviceOs: 'android ${info.version.release}',
            deviceModel: '${info.manufacturer} ${info.model}',
            locale: locale,
          );
        case TargetPlatform.iOS:
          final info = await _plugin.iosInfo;
          return DeviceMetadata(deviceOs: 'ios ${info.systemVersion}', deviceModel: info.utsname.machine, locale: locale);
        default:
          break;
      }
    } catch (_) {
      // Sin info del dispositivo: se sigue con lo mínimo.
    }
    return DeviceMetadata(deviceOs: platformName(), deviceModel: 'unknown', locale: locale);
  }
}
