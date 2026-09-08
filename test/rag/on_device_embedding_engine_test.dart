import 'package:flutter_test/flutter_test.dart';
import 'package:offline_tutor_app/features/rag/application/on_device_embedding_engine.dart';

void main() {
  group('OnDeviceEmbeddingEngine Tests', () {
    test('generateEmbedding produces 384-dim normalized vector', () {
      final engine = OnDeviceEmbeddingEngine.instance;
      final vec = engine.generateEmbedding('binomial theorem expansion formula');
      expect(vec.length, 384);

      // Check L2 normalization (sum of squares should equal ~1.0)
      double sumSq = 0.0;
      for (final v in vec) {
        sumSq += v * v;
      }
      expect(sumSq, closeTo(1.0, 0.05));
    });

    test('packVector and unpackVector preserve float values accurately', () {
      final engine = OnDeviceEmbeddingEngine.instance;
      final original = engine.generateEmbedding('quadratic equations and roots');
      final packed = OnDeviceEmbeddingEngine.packVector(original);
      final unpacked = OnDeviceEmbeddingEngine.unpackVector(packed);

      expect(unpacked.length, original.length);
      for (int i = 0; i < original.length; i++) {
        expect(unpacked[i], closeTo(original[i], 0.0001));
      }
    });

    test('computeCosineSimilarity returns 1.0 for identical vectors', () {
      final engine = OnDeviceEmbeddingEngine.instance;
      final vecA = engine.generateEmbedding('photosynthesis in green plants');
      final vecB = engine.generateEmbedding('photosynthesis in green plants');
      final sim = OnDeviceEmbeddingEngine.computeCosineSimilarity(vecA, vecB);
      expect(sim, closeTo(1.0, 0.01));
    });

    test('computeCosineSimilarity produces higher score for semantically related sentences', () {
      final engine = OnDeviceEmbeddingEngine.instance;
      final query = engine.generateEmbedding('newton second law of motion force');
      final related = engine.generateEmbedding('force acceleration newton second law');
      final unrelated = engine.generateEmbedding('organic chemistry alkanes structure');

      final simRelated = OnDeviceEmbeddingEngine.computeCosineSimilarity(query, related);
      final simUnrelated = OnDeviceEmbeddingEngine.computeCosineSimilarity(query, unrelated);

      expect(simRelated > simUnrelated, true);
    });
  });
}
