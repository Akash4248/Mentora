import 'package:flutter_test/flutter_test.dart';
import 'package:mentora/features/experiment/guided_runtime/engine/task_progress_tracker.dart';

void main() {
  test('Mission progress uses completed tasks over total tasks', () {
    final progress = TaskProgressTracker().progress(
      completedTasks: 3,
      totalTasks: 5,
    );

    expect(progress, 0.6);
  });
}
