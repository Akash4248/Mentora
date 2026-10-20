// ignore_for_file: prefer_initializing_formals

import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

import '../domain/visual_intent.dart';

/// Persists approved visual artifacts alongside session messages so that
/// trajectory canvases, step cards, and simulation launchers survive application
/// restarts and page reloads without re-derivation drift.
final class VisualArtifactStore {
  VisualArtifactStore({SharedPreferences? preferences})
      : _preferences = preferences;

  SharedPreferences? _preferences;

  Future<SharedPreferences> _getPrefs() async {
    final existing = _preferences;
    if (existing != null) return existing;
    final prefs = await SharedPreferences.getInstance();
    _preferences = prefs;
    return prefs;
  }

  String _key(String sessionId, int messageIndex) =>
      'mentora_artifacts_${sessionId}_$messageIndex';

  /// Saves a list of validated [VisualIntent] artifacts for a specific message turn.
  Future<void> saveArtifacts({
    required String sessionId,
    required int messageIndex,
    required List<VisualIntent> artifacts,
  }) async {
    if (artifacts.isEmpty) return;
    final prefs = await _getPrefs();
    final jsonList = artifacts.map((a) => a.toJson()).toList();
    final raw = jsonEncode(jsonList);
    await prefs.setString(_key(sessionId, messageIndex), raw);
  }

  /// Retrieves persisted [VisualIntent] artifacts for a given message turn.
  Future<List<VisualIntent>> getArtifacts({
    required String sessionId,
    required int messageIndex,
  }) async {
    final prefs = await _getPrefs();
    final raw = prefs.getString(_key(sessionId, messageIndex));
    if (raw == null || raw.trim().isEmpty) return const [];

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];

      final results = <VisualIntent>[];
      for (final item in decoded) {
        final intent = VisualIntent.tryParse(item);
        if (intent != null) {
          results.add(intent);
        }
      }
      return results;
    } catch (_) {
      return const [];
    }
  }

  /// Clears all visual artifacts associated with a session.
  Future<void> clearSession(String sessionId) async {
    final prefs = await _getPrefs();
    final prefix = 'mentora_artifacts_${sessionId}_';
    final keysToRemove = prefs.getKeys().where((k) => k.startsWith(prefix)).toList();
    for (final key in keysToRemove) {
      await prefs.remove(key);
    }
  }
}
