import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

import '../domain/learner_profile.dart';
import '../domain/learning_evidence.dart';
import '../domain/session_ledger.dart';

/// Central manager orchestrating Mentora's three-tier memory architecture.
///
/// Tier 1: User-correctable stable profile (persisted in SharedPreferences).
/// Tier 2: In-session state and concept ledger (in-memory per session).
/// Tier 3: Compact, attributable learning evidence (bounded to <= 5 items).
class ThreeTierMemoryManager {
  ThreeTierMemoryManager({SharedPreferences? preferences})
      : _prefsFuture = preferences != null ? Future.value(preferences) : SharedPreferences.getInstance();

  final Future<SharedPreferences> _prefsFuture;

  static const String _kProfileKey = 'mentora_learner_profile_v1';
  static const String _kEvidenceKey = 'mentora_learning_evidence_v1';
  static const int _maxEvidenceItems = 5;

  LearnerProfile? _cachedProfile;
  final Map<String, SessionLedger> _activeLedgers = {};
  List<LearningEvidence>? _cachedEvidence;

  // --------------------------------------------------------------------------
  // Tier 1: Learner Profile
  // --------------------------------------------------------------------------

  Future<LearnerProfile> getProfile({int defaultGrade = 9}) async {
    if (_cachedProfile != null) return _cachedProfile!;
    try {
      final prefs = await _prefsFuture;
      final raw = prefs.getString(_kProfileKey);
      if (raw != null && raw.isNotEmpty) {
        _cachedProfile = LearnerProfile.fromJson(jsonDecode(raw) as Map<String, dynamic>);
        return _cachedProfile!;
      }
    } catch (_) {}

    _cachedProfile = LearnerProfile.defaultProfile(grade: defaultGrade);
    return _cachedProfile!;
  }

  Future<void> updateProfile(LearnerProfile profile) async {
    _cachedProfile = profile;
    try {
      final prefs = await _prefsFuture;
      await prefs.setString(_kProfileKey, jsonEncode(profile.toJson()));
    } catch (_) {}
  }

  Future<void> resetProfile({int defaultGrade = 9}) async {
    _cachedProfile = LearnerProfile.defaultProfile(grade: defaultGrade);
    try {
      final prefs = await _prefsFuture;
      await prefs.remove(_kProfileKey);
    } catch (_) {}
  }

  // --------------------------------------------------------------------------
  // Tier 2: Session Ledger
  // --------------------------------------------------------------------------

  SessionLedger getOrCreateLedger({
    required String sessionId,
    required String topic,
    required int grade,
  }) {
    return _activeLedgers.putIfAbsent(
      sessionId,
      () => SessionLedger(
        sessionId: sessionId,
        topic: topic,
        grade: grade,
        startedAt: DateTime.now(),
        lastActivityAt: DateTime.now(),
      ),
    );
  }

  void recordSessionQuestion(String sessionId, String question, {String topic = 'General', int grade = 9}) {
    final ledger = getOrCreateLedger(sessionId: sessionId, topic: topic, grade: grade);
    ledger.recordQuestion(question);
  }

  void recordSessionConcept(String sessionId, String concept, {String topic = 'General', int grade = 9}) {
    final ledger = getOrCreateLedger(sessionId: sessionId, topic: topic, grade: grade);
    ledger.recordConcept(concept);
  }

  void recordSessionTool(String sessionId, String toolName, {String? formula, String topic = 'General', int grade = 9}) {
    final ledger = getOrCreateLedger(sessionId: sessionId, topic: topic, grade: grade);
    ledger.recordTool(toolName, formula: formula);
  }

  // --------------------------------------------------------------------------
  // Tier 3: Learning Evidence
  // --------------------------------------------------------------------------

  Future<List<LearningEvidence>> getEvidence({String? topicFilter}) async {
    if (_cachedEvidence == null) {
      try {
        final prefs = await _prefsFuture;
        final raw = prefs.getString(_kEvidenceKey);
        if (raw != null && raw.isNotEmpty) {
          final list = jsonDecode(raw) as List;
          _cachedEvidence = list
              .map((e) => LearningEvidence.fromJson(e as Map<String, dynamic>))
              .toList();
        } else {
          _cachedEvidence = [];
        }
      } catch (_) {
        _cachedEvidence = [];
      }
    }

    if (topicFilter == null || topicFilter.trim().isEmpty) {
      return List.unmodifiable(_cachedEvidence!);
    }

    final lowerTopic = topicFilter.toLowerCase().trim();
    return _cachedEvidence!
        .where((e) => e.topic.toLowerCase().contains(lowerTopic) ||
            lowerTopic.contains(e.topic.toLowerCase()))
        .toList(growable: false);
  }

  Future<void> addEvidence(LearningEvidence evidence) async {
    final current = (await getEvidence()).toList();
    // Prevent duplicate exact observation
    current.removeWhere((e) => e.id == evidence.id || (e.concept == evidence.concept && e.observation == evidence.observation));
    current.add(evidence);

    // Enforce strict upper bound of 5 items
    if (current.length > _maxEvidenceItems) {
      current.removeRange(0, current.length - _maxEvidenceItems);
    }

    _cachedEvidence = current;
    try {
      final prefs = await _prefsFuture;
      await prefs.setString(
        _kEvidenceKey,
        jsonEncode(current.map((e) => e.toJson()).toList()),
      );
    } catch (_) {}
  }

  Future<void> removeEvidence(String id) async {
    final current = (await getEvidence()).toList();
    current.removeWhere((e) => e.id == id);
    _cachedEvidence = current;
    try {
      final prefs = await _prefsFuture;
      await prefs.setString(
        _kEvidenceKey,
        jsonEncode(current.map((e) => e.toJson()).toList()),
      );
    } catch (_) {}
  }

  Future<void> clearEvidence() async {
    _cachedEvidence = [];
    try {
      final prefs = await _prefsFuture;
      await prefs.remove(_kEvidenceKey);
    } catch (_) {}
  }

  // --------------------------------------------------------------------------
  // Prompt Serialization (Compact & Bounded)
  // --------------------------------------------------------------------------

  /// Formats relevant memory context for the tutor prompt, keeping it <= 200 tokens.
  Future<String> formatMemoryForPrompt({
    required String topic,
    String? sessionId,
  }) async {
    final buffer = StringBuffer();
    final profile = await getProfile();

    if (profile.explanationStyle != 'balanced') {
      buffer.writeln('- Learner preference: ${profile.explanationStyle} explanations');
    }
    if (profile.interests.isNotEmpty) {
      buffer.writeln('- Learner interests for analogies: ${profile.interests.join(", ")}');
    }

    if (sessionId != null && _activeLedgers.containsKey(sessionId)) {
      final ledger = _activeLedgers[sessionId]!;
      if (ledger.keyConceptsTouched.isNotEmpty) {
        buffer.writeln('- Concepts explored this session: ${ledger.keyConceptsTouched.join(", ")}');
      }
      if (ledger.lastFormulaEvaluated != null) {
        buffer.writeln('- Recent formula computed: ${ledger.lastFormulaEvaluated}');
      }
    }

    final evidence = await getEvidence(topicFilter: topic);
    if (evidence.isNotEmpty) {
      final recent = evidence.length > 2 ? evidence.sublist(evidence.length - 2) : evidence;
      for (final item in recent) {
        final label = item.sourceType == EvidenceSourceType.directStudentStatement
            ? 'Student stated'
            : 'Observed note';
        final status = item.isMastery ? 'mastered' : 'struggles with';
        buffer.writeln('- $label: $status "${item.concept}" (${item.observation})');
      }
    }

    final text = buffer.toString().trim();
    if (text.isEmpty) return '';
    return '\n\nLearner Context & Session Memory:\n$text\n';
  }
}
