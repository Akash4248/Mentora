// ignore_for_file: avoid_print

import 'package:flutter/foundation.dart';
import '../repositories/ai_experiment_repository.dart';
import '../../data/repositories/experiment_manifest_repository.dart';
import '../../validation/manifest_sanitizer.dart';
import '../../../analytics/telemetry_service.dart';
import 'package:mentora/features/language/services/language_service.dart';

class AiGeneratorController extends ChangeNotifier {
  final AiExperimentRepository _aiRepository;
  final ExperimentManifestRepository _manifestRepository;

  AiGeneratorController({
    required AiExperimentRepository aiRepository,
    required ExperimentManifestRepository manifestRepository,
  })  : _aiRepository = aiRepository,
        _manifestRepository = manifestRepository;

  bool _isLoading = false;
  bool get isLoading => _isLoading;

  String? _error;
  String? get error => _error;

  Map<String, dynamic>? _generatedManifest;
  Map<String, dynamic>? get generatedManifest => _generatedManifest;

  Map<String, dynamic>? _explanation;
  Map<String, dynamic>? get explanation => _explanation;

  ManifestValidationResponse? _validationResult;
  ManifestValidationResponse? get validationResult => _validationResult;

  ManifestCompatibilityResponse? _compatibilityResult;
  ManifestCompatibilityResponse? get compatibilityResult => _compatibilityResult;

  Map<String, dynamic>? _executionPackage;
  Map<String, dynamic>? get executionPackage => _executionPackage;

  bool get canImport =>
      _generatedManifest != null &&
      _validationResult?.isValid == true &&
      _compatibilityResult?.supported == true &&
      _compatibilityResult?.migrationRequired == false;

  Future<void> generateExperiment(String prompt) async {
    final language = await _getLanguageCode();
    await _executeAiFlow(() => _aiRepository.generateExperiment(prompt, language: language));
  }

  Future<void> refineExperiment(String prompt) async {
    if (_generatedManifest == null) return;
    final language = await _getLanguageCode();
    await _executeAiFlow(() => _aiRepository.refineExperiment(_generatedManifest!, prompt, language: language));
  }

  Future<String> _getLanguageCode() async {
    try {
      final LanguageService service = LanguageService();
      final lang = await service.loadSavedLanguage();
      return lang.code;
    } catch (_) {
      return 'en';
    }
  }

  Future<void> _executeAiFlow(Future<AiGeneratedExperiment> Function() action) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final result = await action();
      _generatedManifest = ManifestSanitizer.sanitize(result.manifest);
      _explanation = result.explanation;

      TelemetryService().trackEvent('ai_experiment_generated');

      // Automatically validate
      _validationResult = await _manifestRepository.validate(_generatedManifest!);

      // Automatically check compatibility
      _compatibilityResult = await _manifestRepository.checkCompatibility(_generatedManifest!);

      // Automatically fetch execution preview
      final capabilities = {
        "accelerometer": true,
        "gyroscope": true,
        "gps": true,
        "camera": true,
      };
      _executionPackage = await _manifestRepository.getExecutionPackage(_generatedManifest!, capabilities);
    } catch (e) {
      _error = e.toString();
      print('AI Flow Error: $_error');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  void clear() {
    _generatedManifest = null;
    _explanation = null;
    _validationResult = null;
    _compatibilityResult = null;
    _executionPackage = null;
    _error = null;
    notifyListeners();
  }
}
