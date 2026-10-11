import 'package:flutter_test/flutter_test.dart';
import 'package:mentora/features/experiment/investigation/comparison/trend_detector.dart';

void main() {
  test('TrendDetector identifies increasing values', () {
    const detector = TrendDetector();

    expect(detector.detect([1, 2, 3]), TrialTrend.increasing);
    expect(detector.detect([3, 2, 1]), TrialTrend.decreasing);
    expect(detector.detect([2, 2, 2]), TrialTrend.stable);
  });
}
