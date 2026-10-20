import 'dart:math';

import '../../content_packs/data/local/content_pack_repository.dart';
import '../../network/data/backend_availability_cache.dart';
import '../../network/services/mentora_backend_client.dart';

/// Single question-loading path for every quiz UI (workspace tab,
/// [QuizPlayerScreen], practice hub).
///
/// Order: installed pack `quizzes.json` → live `GET /quizzes?...` (online
/// only) → offline mock generator. Always returns normalized maps:
/// `{question, options: List<String>, correctIndex: int, explanation}`.
class QuizQuestionLoader {
  static Future<List<Map<String, dynamic>>> load({
    required int grade,
    required String subject,
    required String chapterTitle,
  }) async {
    // 1. Installed pack content.
    try {
      final installed = await ContentPackRepository().findQuizQuestionsForChapter(
        chapterTitle: chapterTitle,
        subject: subject,
        grade: grade,
      );
      final normalized =
          installed.map(normalize).where((q) => (q['question'] as String).isNotEmpty).toList();
      if (normalized.isNotEmpty) return normalized;
    } catch (_) {}

    // 2. Live backend (query-param route; offline returns [] without 404s).
    if (!BackendAvailabilityCache().isOffline) {
      try {
        final live = await MentoraBackendClient().getLiveQuizzes(
          grade: grade,
          subject: subject,
          chapter: chapterTitle,
        );
        final normalized =
            live.map(normalize).where((q) => (q['question'] as String).isNotEmpty).toList();
        if (normalized.isNotEmpty) return normalized;
      } catch (_) {}
    }

    // 3. Offline mock generator (templated, clearly offline).
    try {
      final mock = await MentoraBackendClient().getQuizForChapter(chapterTitle);
      final questions = (mock['questions'] as List? ?? [])
          .whereType<Map>()
          .map((m) => Map<String, dynamic>.from(m))
          .map(normalize)
          .where((q) => (q['question'] as String).isNotEmpty)
          .toList();
      return questions;
    } catch (_) {
      return const [];
    }
  }

  /// Normalize the pack/live/mock shapes into one quiz map.
  static Map<String, dynamic> normalize(Map<String, dynamic> raw) {
    final question = (raw['question'] ?? '').toString();
    var options = List<String>.from(
      (raw['options'] as List? ?? const []).map((o) => o.toString()),
    );
    final correctStr = (raw['correct_answer'] ?? raw['answer'] ?? '').toString();
    var correctIndex = (raw['correctIndex'] as num?)?.toInt() ?? options.indexOf(correctStr);
    if (options.length < 4) {
      options = [
        ...options,
        ...const ['None of the above', 'All of the above', 'Not applicable']
            .where((filler) => !options.contains(filler)),
      ];
    }
    if (options.length > 4) options = options.sublist(0, 4);
    if (correctIndex < 0 || correctIndex >= options.length) correctIndex = 0;
    final explanation = (raw['explanation'] as String?)?.trim().isNotEmpty == true
        ? raw['explanation'] as String
        : correctStr.isNotEmpty
            ? correctStr
            : question;
    return {
      'question': question,
      'options': options,
      'correctIndex': correctIndex,
      'explanation': explanation,
    };
  }

  /// Shuffle options in place (Fisher-Yates via [Random]).
  static Map<String, dynamic> withShuffledOptions(Map<String, dynamic> q, [Random? random]) {
    final rng = random ?? Random();
    final options = List<String>.from(q['options'] as List? ?? []);
    final correct = (options.isNotEmpty &&
            (q['correctIndex'] as int? ?? 0) < options.length)
        ? options[q['correctIndex'] as int? ?? 0]
        : '';
    options.shuffle(rng);
    return {
      ...q,
      'options': options,
      'correctIndex': options.indexOf(correct).clamp(0, options.length - 1),
    };
  }
}
