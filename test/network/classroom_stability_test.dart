import 'package:flutter_test/flutter_test.dart';

import 'package:mentora/features/network/application/classroom_presence_coordinator.dart';
import 'package:mentora/features/network/application/multi_device_recovery_manager.dart';
import 'package:mentora/features/network/application/sync_queue_balancer.dart';

void main() {
  test('classroom presence tracks devices', () {
    final presence = ClassroomPresenceCoordinator();
    presence.markPresent('device-1');
    presence.markPresent('device-2');

    expect(presence.snapshot().length, 2);
  });

  test('multi device recovery remembers devices', () {
    final recovery = MultiDeviceRecoveryManager();
    recovery.recover('device-a');
    recovery.recover('device-a');

    expect(recovery.snapshot().length, 1);
  });

  test('sync queue balancer reduces work across peers', () {
    final balancer = SyncQueueBalancer();

    expect(balancer.balance(10, 2), 5);
    expect(balancer.balance(5, 0), 5);
  });
}
