import 'package:flutter/foundation.dart';

class SimulationClock extends ChangeNotifier {
  double _elapsedTime = 0.0;
  bool _isRunning = false;

  double get elapsedTime => _elapsedTime;
  bool get isRunning => _isRunning;
  bool get isPaused => !_isRunning;

  void tick(double dt) {
    if (_isRunning) {
      _elapsedTime += dt;
      notifyListeners();
    }
  }

  void start() {
    _isRunning = true;
    notifyListeners();
  }

  void pause() {
    _isRunning = false;
    notifyListeners();
  }

  void reset() {
    _elapsedTime = 0.0;
    _isRunning = false;
    notifyListeners();
  }

  void restore({required double elapsedTime, bool running = false}) {
    _elapsedTime = elapsedTime < 0 ? 0 : elapsedTime;
    _isRunning = running;
    notifyListeners();
  }
}
