// ignore_for_file: prefer_initializing_formals

import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter_agent_harness/flutter_agent_harness.dart';

import '../../rag/data/local/rag_repository_v2.dart';
import '../domain/built_tutor_context.dart';
import '../domain/capability_registry.dart';
import '../domain/context_budget_report.dart';
import '../domain/grounding_chunk.dart';
import 'deterministic_fast_path_router.dart';
import 'follow_up_action_generator.dart';
import 'teaching_strategy_selector.dart';
import 'three_tier_memory_manager.dart';

typedef RagRetriever = Future<List<GroundingChunk>> Function(
  String query,
  String topic, {
  int limit,
});

/// Orchestrator responsible for constructing a bounded, grounded, and budgeted
/// tutor context package for an incoming turn.
class ContextBuilder {
  ContextBuilder({
    DeterministicFastPathRouter? router,
    CapabilityRegistry? registry,
    ThreeTierMemoryManager? memoryManager,
    TeachingStrategySelector? strategySelector,
    FollowUpActionGenerator? followUpGenerator,
    RagRetriever? ragRetriever,
    int maxContextLimit = 2048,
    int reservedOutputTokens = 1024,
  })  : _router = router ?? const DeterministicFastPathRouter(),
        _registry = registry ?? CapabilityRegistry(),
        _memoryManager = memoryManager ?? ThreeTierMemoryManager(),
        _strategySelector = strategySelector ?? const TeachingStrategySelector(),
        _followUpGenerator = followUpGenerator ?? const FollowUpActionGenerator(),
        _ragRetriever = ragRetriever ?? _defaultRagRetriever,
        _maxContextLimit = maxContextLimit,
        _reservedOutputTokens = reservedOutputTokens;

  final DeterministicFastPathRouter _router;
  final CapabilityRegistry _registry;
  final ThreeTierMemoryManager _memoryManager;
  final TeachingStrategySelector _strategySelector;
  final FollowUpActionGenerator _followUpGenerator;
  final RagRetriever _ragRetriever;
  final int _maxContextLimit;
  final int _reservedOutputTokens;

  DeterministicFastPathRouter get router => _router;
  CapabilityRegistry get registry => _registry;
  ThreeTierMemoryManager get memoryManager => _memoryManager;
  TeachingStrategySelector get strategySelector => _strategySelector;
  FollowUpActionGenerator get followUpGenerator => _followUpGenerator;

  /// Default RAG retrieval querying local NCERT chunks from [RagRepositoryV2].
  static Future<List<GroundingChunk>> _defaultRagRetriever(
    String query,
    String topic, {
    int limit = 2,
  }) async {
    try {
      final repo = RagRepositoryV2();
      await repo.ensureSeedChunks();
      var chunks = await repo.searchChunks(query, topic, limit: limit);
      if (chunks.isEmpty) {
        chunks = await repo.searchAll(query, limit: limit);
      }
      return chunks
          .map(
            (c) => GroundingChunk(
              id: c.id,
              chapterId: c.chapterId,
              sourceTitle: c.sourceTitle,
              content: c.content,
              tokenCount: c.tokenCount,
            ),
          )
          .toList(growable: false);
    } catch (_) {
      return const [];
    }
  }

  /// Builds a fully resolved, bounded [BuiltTutorContext] for a student query.
  Future<BuiltTutorContext> build({
    required String question,
    required String topic,
    required int grade,
    String? sessionId,
    List<String> rawHistory = const [],
  }) async {
    final cleanQuestion = _extractCleanQuestion(question);
    final tClean = topic.trim().isEmpty ? 'Science & Mathematics' : topic.trim();

    // 1. Fast-path intent routing
    final decision = _router.route(
      question: cleanQuestion,
      topic: tClean,
      grade: grade,
    );

    // 2. Select adaptive teaching strategy
    final strategy = _strategySelector.selectStrategy(
      question: cleanQuestion,
      topic: tClean,
      route: decision.route,
    );
    final strategyDirective = _strategySelector.instructionForStrategy(strategy);

    // 3. Generate context-sensitive follow-up actions
    final followUpActions = _followUpGenerator.generateFollowUps(
      question: cleanQuestion,
      topic: tClean,
      strategy: strategy,
    );

    // 4. Resolve capability tools allowlisted for this request
    final selectedTools = decision.selectedCapabilityIds.isNotEmpty
        ? _registry.resolveTools(
            ids: decision.selectedCapabilityIds,
            maxTools: 4,
          )
        : const <AgentTool>[];

    // 5. Grounding: Fetch local curriculum chunks
    final groundingChunks = await _ragRetriever(cleanQuestion, tClean, limit: 2);
    final ragBlock = _formatRagBlock(groundingChunks);

    // 6. Memory: Fetch Profile, Ledger, and Evidence
    final profile = await _memoryManager.getProfile(defaultGrade: grade);
    final ledger = sessionId != null
        ? _memoryManager.getOrCreateLedger(
            sessionId: sessionId,
            topic: tClean,
            grade: grade,
          )
        : null;
    final evidence = await _memoryManager.getEvidence(topicFilter: tClean);
    final memoryBlock = await _memoryManager.formatMemoryForPrompt(
      topic: tClean,
      sessionId: sessionId,
    );

    // 7. Bounded recent dialogue turns (max 2 turns, <= 300 chars each)
    final recentTurns = _formatRecentTurns(rawHistory);
    final historyBlock = recentTurns.isNotEmpty
        ? '\n\nRecent context:\n${recentTurns.join('\n')}'
        : '';

    // 8. Base system prompt formatting
    final systemPrompt = '''<|im_start|>system
You are an expert NCERT school AI tutor for Class $grade $tClean.
$strategyDirective
Answer directly and clearly using Markdown formatting, bullet points, and key formulas.$ragBlock$memoryBlock
IMPORTANT: If the user asks in Kannada or any regional language, respond in that language.
Do not output internal monologues or planning steps.$historyBlock
DIAGRAM & VISUAL RULES:
- When a student asks for a visual explanation, simulation, dynamics, graph, circuit, or diagram, call the show_visualization tool OR embed an interactive visualizer widget by emitting a ```mentora-visual block with JSON:
```mentora-visual
{"type": "motion.trajectory", "scenario": "projectile", "inputs": {"launch_velocity_mps": 20.0, "launch_angle_deg": 45.0}, "title": "Projectile Motion"}
```
Supported types:
1. "motion.trajectory" (scenarios: "projectile", "vertical_toss"; inputs: launch_velocity_mps, launch_angle_deg)
2. "circuit.schematic" (scenarios: "simple_circuit", "series_circuit", "parallel_circuit"; inputs: voltage, resistances)
3. "optics.ray_diagram" (scenarios: "concave_mirror", "convex_mirror", "convex_lens", "concave_lens"; inputs: focal_length_cm, object_distance_cm)
4. "geometry.construction" (scenarios: "right_triangle", "circle_tangents"; inputs: base, height, radius, distance)

- Never use Mermaid diagrams (```mermaid) to flowchart answering steps, prompt instructions, lesson outlines, or tool summaries.
- Mermaid diagrams are ONLY for actual domain scientific concepts (e.g. food webs, life cycles, state machines). Nodes must contain subject matter facts only.
- Never output prompt instructions or meta-labels (such as 'Real-world analogy:', 'Conceptual observation:', or tool names) as diagram nodes or section headings.
<|im_end|>''';

    // 9. Token accounting and budget report (~4 chars per token)
    final systemTokens = _estimateTokens(systemPrompt);
    final memoryTokens = _estimateTokens(memoryBlock);
    final ragTokens = _estimateTokens(ragBlock);
    final historyTokens = _estimateTokens(historyBlock);
    final questionTokens = _estimateTokens(cleanQuestion);

    var toolSchemaTokens = 0;
    if (selectedTools.isNotEmpty) {
      final toolSchemasJson = jsonEncode(
        selectedTools.map((t) => {
          'name': t.name,
          'description': t.description,
          'parameters': t.parameters,
        }).toList(),
      );
      toolSchemaTokens = _estimateTokens(toolSchemasJson);
    }

    final totalInputTokens = systemTokens + questionTokens + toolSchemaTokens;

    final budgetReport = ContextBudgetReport(
      estimatedInputTokens: totalInputTokens,
      systemTokens: systemTokens,
      memoryTokens: memoryTokens,
      ragTokens: ragTokens,
      historyTokens: historyTokens,
      questionTokens: questionTokens,
      toolSchemaTokens: toolSchemaTokens,
      reservedOutputTokens: _reservedOutputTokens,
      maxContextLimit: _maxContextLimit,
    );

    return BuiltTutorContext(
      systemPrompt: systemPrompt,
      cleanQuestion: cleanQuestion,
      recentTurns: recentTurns,
      groundingChunks: groundingChunks,
      learnerProfile: profile,
      sessionLedger: ledger,
      evidence: evidence,
      selectedTools: selectedTools,
      decision: decision,
      strategy: strategy,
      followUpActions: followUpActions,
      budgetReport: budgetReport,
    );
  }

  String _formatRagBlock(List<GroundingChunk> chunks) {
    if (chunks.isEmpty) return '';
    final buffer = StringBuffer();
    for (final chunk in chunks) {
      buffer.writeln('${chunk.citation}:');
      final text = chunk.content.trim();
      final capped = text.length > 400 ? '${text.substring(0, 400)}…' : text;
      buffer.writeln(capped);
      buffer.writeln('---');
    }
    final content = buffer.toString().trim();
    if (content.isEmpty) return '';
    return '\n\nRelevant NCERT Textbook Excerpt:\n$content\n';
  }

  List<String> _formatRecentTurns(List<String> rawHistory) {
    if (rawHistory.isEmpty) return const [];
    final recent = rawHistory.length > 2
        ? rawHistory.sublist(rawHistory.length - 2)
        : rawHistory;

    final formatted = <String>[];
    for (final turn in recent) {
      final trimmed = turn.trim();
      if (trimmed.isEmpty) continue;
      final capped = trimmed.length > 300 ? '${trimmed.substring(0, 300)}…' : trimmed;
      formatted.add(capped);
    }
    return formatted;
  }

  String _extractCleanQuestion(String raw) {
    if (raw.contains('Current student question:')) {
      final parts = raw.split('Current student question:');
      if (parts.length > 1) {
        return parts.last.trim();
      }
    }
    return raw.trim();
  }

  int _estimateTokens(String text) {
    if (text.isEmpty) return 0;
    return math.max(1, (text.length / 4.0).ceil());
  }
}
