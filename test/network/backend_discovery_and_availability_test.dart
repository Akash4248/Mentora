import 'package:flutter_test/flutter_test.dart';
import 'package:offline_tutor_app/features/network/data/backend_availability_cache.dart';
import 'package:offline_tutor_app/features/network/services/mentora_backend_client.dart';

void main() {
  setUp(() {
    BackendAvailabilityCache().clear();
  });

  test('BackendAvailabilityCache defaults to offline and notifies listeners on change', () async {
    final cache = BackendAvailabilityCache();
    expect(cache.isOnline, false);
    expect(cache.isOffline, true);

    final emitted = <bool>[];
    final sub = cache.statusStream.listen(emitted.add);

    cache.updateStatus(true, url: 'http://127.0.0.1:8000');
    expect(cache.isOnline, true);
    expect(cache.isOffline, false);
    expect(cache.cachedUrl, 'http://127.0.0.1:8000');

    cache.updateStatus(false);
    expect(cache.isOnline, false);
    expect(cache.isOffline, true);

    await Future<void>.delayed(Duration.zero);
    expect(emitted, [true, false]);
    await sub.cancel();
  });

  test('queryAiTutor instantly routes to local LLM when BackendAvailabilityCache is offline', () async {
    final cache = BackendAvailabilityCache();
    cache.updateStatus(false);

    final client = MentoraBackendClient();
    final result = await client.queryAiTutor(
      question: 'What is force?',
      topic: 'Motion',
      grade: 9,
    );

    expect(result['answer'], contains('On-Device Local AI Tutor'));
    expect(result['source'], 'on_device_local_llm');
  });
}
