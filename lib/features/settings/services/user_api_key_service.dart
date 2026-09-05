import 'package:shared_preferences/shared_preferences.dart';

enum CloudLlmProvider {
  gemini('Google Gemini 1.5 Pro', 'gemini'),
  openai('OpenAI GPT-4o', 'openai'),
  anthropic('Anthropic Claude 3.5', 'anthropic'),
  groq('Groq LLaMA 3', 'groq');

  final String displayName;
  final String providerId;

  const CloudLlmProvider(this.displayName, this.providerId);

  static CloudLlmProvider fromId(String id) {
    return CloudLlmProvider.values.firstWhere(
      (e) => e.providerId == id,
      orElse: () => CloudLlmProvider.gemini,
    );
  }
}

class UserApiKeyService {
  static const String _keyHybridMode = 'mentora_hybrid_mode_enabled';
  static const String _keyPiHubMode = 'mentora_pihub_mode_enabled';
  static const String _keyCloudProvider = 'mentora_cloud_llm_provider';
  static const String _keyApiKey = 'mentora_user_cloud_api_key';
  static const String _keyGgufModel = 'mentora_active_gguf_model';
  static const String _keyCustomServerUrl = 'mentora_custom_server_url';

  static UserApiKeyService? _instance;
  final SharedPreferences _prefs;

  UserApiKeyService._(this._prefs);

  static Future<UserApiKeyService> getInstance() async {
    if (_instance == null) {
      final prefs = await SharedPreferences.getInstance();
      _instance = UserApiKeyService._(prefs);
    }
    return _instance!;
  }

  bool get isHybridModeEnabled => _prefs.getBool(_keyHybridMode) ?? true;

  Future<void> setHybridModeEnabled(bool enabled) async {
    await _prefs.setBool(_keyHybridMode, enabled);
  }

  bool get isPiHubModeEnabled => _prefs.getBool(_keyPiHubMode) ?? false;

  Future<void> setPiHubModeEnabled(bool enabled) async {
    await _prefs.setBool(_keyPiHubMode, enabled);
  }

  String get customServerUrl => _prefs.getString(_keyCustomServerUrl) ?? 'http://127.0.0.1:8000';

  Future<void> setCustomServerUrl(String url) async {
    await _prefs.setString(_keyCustomServerUrl, url.trim());
  }

  CloudLlmProvider get activeProvider {
    final providerId = _prefs.getString(_keyCloudProvider) ?? 'gemini';
    return CloudLlmProvider.fromId(providerId);
  }

  Future<void> setCloudProvider(CloudLlmProvider provider) async {
    await _prefs.setString(_keyCloudProvider, provider.providerId);
  }

  String get apiKey => _prefs.getString(_keyApiKey) ?? '';

  Future<void> setApiKey(String key) async {
    await _prefs.setString(_keyApiKey, key.trim());
  }

  String get ggufModelName => _prefs.getString(_keyGgufModel) ?? 'Gemma 3n 2B (Q4_K_M)';

  Future<void> setGgufModelName(String modelName) async {
    await _prefs.setString(_keyGgufModel, modelName);
  }

  Map<String, String> getAuthHeaders() {
    final headers = <String, String>{};
    if (isHybridModeEnabled && apiKey.isNotEmpty) {
      headers['X-User-LLM-Key'] = apiKey;
      headers['X-User-LLM-Provider'] = activeProvider.providerId;
    } else {
      headers['X-User-LLM-Provider'] = 'offline';
    }
    return headers;
  }
}
