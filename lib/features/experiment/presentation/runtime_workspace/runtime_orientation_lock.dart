import 'package:flutter/services.dart';

class RuntimeOrientationLock {
  const RuntimeOrientationLock._();

  static int _lockCount = 0;

  static Future<void> lockLandscape() {
    _lockCount++;
    return SystemChrome.setPreferredOrientations(const [
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
  }

  static Future<void> restore() {
    if (_lockCount > 0) {
      _lockCount--;
    }
    if (_lockCount == 0) {
      return SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    }
    return Future.value();
  }
}
