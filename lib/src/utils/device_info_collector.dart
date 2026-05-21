import 'dart:io';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';

class DeviceMetadata {
  final String deviceOs;
  final String deviceModel;
  final String locale;

  const DeviceMetadata({
    required this.deviceOs,
    required this.deviceModel,
    required this.locale,
  });

  Map<String, String> toJson() => {
        'deviceOs': deviceOs,
        'deviceModel': deviceModel,
        'locale': locale,
      };
}

class DeviceInfoCollector {
  static final _plugin = DeviceInfoPlugin();

  static Future<DeviceMetadata> collect() async {
    try {
      if (kIsWeb) {
        final info = await _plugin.webBrowserInfo;
        return DeviceMetadata(
          deviceOs: 'web',
          deviceModel: info.browserName.name,
          locale: Platform.localeName,
        );
      } else if (Platform.isAndroid) {
        final info = await _plugin.androidInfo;
        return DeviceMetadata(
          deviceOs: 'android ${info.version.release}',
          deviceModel: '${info.manufacturer} ${info.model}',
          locale: Platform.localeName,
        );
      } else if (Platform.isIOS) {
        final info = await _plugin.iosInfo;
        return DeviceMetadata(
          deviceOs: 'ios ${info.systemVersion}',
          deviceModel: info.utsname.machine,
          locale: Platform.localeName,
        );
      }
    } catch (_) {
      // Fallback if device info collection fails
    }

    return DeviceMetadata(
      deviceOs: Platform.operatingSystem,
      deviceModel: 'unknown',
      locale: Platform.localeName,
    );
  }
}
