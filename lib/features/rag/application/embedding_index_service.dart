import '../data/local/embedding_index_repository.dart';
import '../data/local/rag_repository.dart';
import 'on_device_embedding_engine.dart';

class EmbeddingIndexProgress {
  const EmbeddingIndexProgress({
    required this.total,
    required this.processed,
    required this.indexed,
    required this.done,
  });

  final int total;
  final int processed;
  final int indexed;
  final bool done;
}

class EmbeddingIndexService {
  EmbeddingIndexService({
    required RagRepository ragRepository,
    required EmbeddingIndexRepository embeddingRepository,
  })  : _ragRepository = ragRepository,
        _embeddingRepository = embeddingRepository;

  final RagRepository _ragRepository;
  final EmbeddingIndexRepository _embeddingRepository;

  Stream<EmbeddingIndexProgress> indexChapter({
    required String chapterId,
    String modelName = 'bge-small-en-v1.5',
    int dimension = 384,
  }) async* {
    final chunks = await _ragRepository.getChunksForChapter(chapterId);
    final total = chunks.length;

    if (total == 0) {
      yield const EmbeddingIndexProgress(
        total: 0,
        processed: 0,
        indexed: 0,
        done: true,
      );
      return;
    }

    var processed = 0;
    var indexed = await _embeddingRepository.getIndexedCountForChapter(
      chapterId: chapterId,
    );

    yield EmbeddingIndexProgress(
      total: total,
      processed: processed,
      indexed: indexed,
      done: false,
    );

    for (final chunk in chunks) {
      final alreadyIndexed = await _embeddingRepository.isChunkIndexed(
        chunkId: chunk.id,
      );

      if (!alreadyIndexed) {
        // Generate 384-dimensional vector embedding for chunk content
        final floatVector = OnDeviceEmbeddingEngine.instance.generateEmbedding(chunk.content);
        final vectorBlob = OnDeviceEmbeddingEngine.packVector(floatVector);

        await _embeddingRepository.upsertEmbeddingMetadata(
          chunkId: chunk.id,
          modelName: modelName,
          dimension: dimension,
          vectorBlob: vectorBlob,
        );
      }

      processed += 1;
      indexed = await _embeddingRepository.getIndexedCountForChapter(
        chapterId: chapterId,
      );

      yield EmbeddingIndexProgress(
        total: total,
        processed: processed,
        indexed: indexed,
        done: processed >= total,
      );
    }
  }
}
