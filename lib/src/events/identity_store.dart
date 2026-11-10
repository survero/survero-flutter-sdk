import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

/// Persistent per-install `device_id` and the app's `user_id` (after [Survero.identify]).
class IdentityStore {
  static const deviceKey = 'survero_device_id';
  static const userKey = 'survero_user_id';

  late String deviceId;
  String? userId;

  /// true if the device_id was just created (first open after install → `$install`).
  bool isNewInstall = false;

  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final stored = prefs.getString(deviceKey);
      if (stored != null && stored.isNotEmpty) {
        deviceId = stored;
      } else {
        deviceId = const Uuid().v4();
        isNewInstall = true;
        await prefs.setString(deviceKey, deviceId);
      }
      userId = prefs.getString(userKey);
    } catch (_) {
      deviceId = const Uuid().v4();
      isNewInstall = true;
    }
  }

  Future<void> setUserId(String? value) async {
    userId = value;
    try {
      final prefs = await SharedPreferences.getInstance();
      if (value == null) {
        await prefs.remove(userKey);
      } else {
        await prefs.setString(userKey, value);
      }
    } catch (_) {}
  }
}
