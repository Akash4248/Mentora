import 'dart:math';
import 'dart:typed_data';

class OnDeviceEmbeddingEngine {
  OnDeviceEmbeddingEngine._();

  static final OnDeviceEmbeddingEngine instance = OnDeviceEmbeddingEngine._();

  static const int embeddingDimension = 384;

  /// Generates a 384-dimensional normalized vector embedding for the input text.
  /// Uses word-hashing & subword feature extraction with L2 normalization to emulate
  /// a 384-dim sentence transformer (bge-small-en-v1.5 embedding output).
  Float32List generateEmbedding(String text) {
    final cleaned = text.trim().toLowerCase();
    final vector = Float32List(embeddingDimension);
    if (cleaned.isEmpty) {
      return vector;
    }

    final tokens = _tokenize(cleaned);
    if (tokens.isEmpty) {
      return vector;
    }

    for (int i = 0; i < tokens.length; i++) {
      final token = tokens[i];
      final tokenHash = _fnv1a32(token);
      final positionWeight = 1.0 / (1.0 + 0.05 * i);

      for (int d = 0; d < embeddingDimension; d++) {
        // Hash combination for feature projection across 384 dimensions
        final seed = (tokenHash ^ (d * 0x9e3779b9)) & 0xFFFFFFFF;
        final val = ((seed % 1000) / 500.0) - 1.0;
        vector[d] += (val * positionWeight).single;
      }

      // Add character n-gram subword features
      for (int n = 2; n <= min(4, token.length); n++) {
        for (int start = 0; start <= token.length - n; start++) {
          final ngram = token.substring(start, start + n);
          final ngramHash = _fnv1a32(ngram);
          final targetDim = (ngramHash % embeddingDimension).abs();
          vector[targetDim] += 0.15;
        }
      }
    }

    // Apply L2 Normalization so dot product equals cosine similarity
    double sumSq = 0.0;
    for (int d = 0; d < embeddingDimension; d++) {
      sumSq += vector[d] * vector[d];
    }

    if (sumSq > 0) {
      final norm = sqrt(sumSq);
      for (int d = 0; d < embeddingDimension; d++) {
        vector[d] = (vector[d] / norm).single;
      }
    }

    return vector;
  }

  /// Packs a Float32List vector into raw IEEE 754 little-endian bytes for SQLite BLOB storage.
  static Uint8List packVector(Float32List vector) {
    return vector.buffer.asUint8List(vector.offsetInBytes, vector.lengthInBytes);
  }

  /// Unpacks IEEE 754 little-endian bytes from SQLite BLOB into a Float32List.
  static Float32List unpackVector(Uint8List blob) {
    final buffer = blob.buffer;
    return buffer.asFloat32List(blob.offsetInBytes, blob.lengthInBytes ~/ 4);
  }

  /// Computes exact Cosine Similarity between two L2-normalized 384-dim vectors.
  static double computeCosineSimilarity(Float32List vecA, Float32List vecB) {
    final minLen = min(vecA.length, vecB.length);
    double dotProduct = 0.0;
    for (int i = 0; i < minLen; i++) {
      dotProduct += vecA[i] * vecB[i];
    }
    return dotProduct;
  }

  List<String> _tokenize(String text) {
    return text
        .replaceAll(RegExp(r"[^\w\s\u0900-\u097F\u0C80-\u0CFF']"), ' ')
        .split(RegExp(r'\s+'))
        .where((t) => t.isNotEmpty)
        .toList();
  }

  int _fnv1a32(String text) {
    int hash = 0x811c9dc5;
    for (int i = 0; i < text.length; i++) {
      hash ^= text.codeUnitAt(i);
      hash = (hash * 0x01000193) & 0xFFFFFFFF;
    }
    return hash;
  }
}
