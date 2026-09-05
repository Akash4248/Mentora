import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/user_api_key_service.dart';
import '../../network/services/mentora_backend_client.dart';

class MentoraSettingsScreen extends StatefulWidget {
  const MentoraSettingsScreen({Key? key}) : super(key: key);

  @override
  State<MentoraSettingsScreen> createState() => _MentoraSettingsScreenState();
}

class _MentoraSettingsScreenState extends State<MentoraSettingsScreen> {
  UserApiKeyService? _keyService;
  bool _isLoading = true;
  bool _isHybridMode = true;
  bool _isPiHubMode = false;
  CloudLlmProvider _selectedProvider = CloudLlmProvider.gemini;
  late TextEditingController _apiKeyController;
  late TextEditingController _serverUrlController;
  bool _obscureKey = true;
  String _ggufModel = 'Gemma 3n 2B (Q4_K_M)';

  @override
  void initState() {
    super.initState();
    _apiKeyController = TextEditingController();
    _serverUrlController = TextEditingController();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final service = await UserApiKeyService.getInstance();
    setState(() {
      _keyService = service;
      _isHybridMode = service.isHybridModeEnabled;
      _isPiHubMode = service.isPiHubModeEnabled;
      _selectedProvider = service.activeProvider;
      _apiKeyController.text = service.apiKey;
      _serverUrlController.text = service.customServerUrl;
      _ggufModel = service.ggufModelName;
      _isLoading = false;
    });
  }

  Future<void> _saveApiKey() async {
    if (_keyService == null) return;
    await _keyService!.setApiKey(_apiKeyController.text);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('API Key saved securely on device.'),
          backgroundColor: Color(0xFF4F46E5),
        ),
      );
    }
  }

  Future<void> _pasteFromClipboard() async {
    final data = await Clipboard.getData('text/plain');
    if (data != null && data.text != null) {
      setState(() {
        _apiKeyController.text = data.text!.trim();
      });
      await _saveApiKey();
    }
  }

  @override
  void dispose() {
    _apiKeyController.dispose();
    _serverUrlController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const primaryIndigo = Color(0xFF4F46E5);
    const slateBg = Color(0xFFF8FAFC);
    const cardBg = Color(0xFFFFFFFF);
    const borderColor = Color(0xFFE2E8F0);

    return Scaffold(
      backgroundColor: slateBg,
      appBar: AppBar(
        backgroundColor: cardBg,
        elevation: 0.5,
        title: const Text(
          'Settings & AI Engine',
          style: TextStyle(color: Color(0xFF0F172A), fontWeight: FontWeight.bold, fontSize: 18),
        ),
        iconTheme: const IconThemeData(color: Color(0xFF0F172A)),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: primaryIndigo))
          : ListView(
              padding: const EdgeInsets.all(16.0),
              children: [
                // SECTION 1: AI INFERENCE ENGINE
                _buildSectionHeader('AI INFERENCE ENGINE'),
                const SizedBox(height: 8),
                Card(
                  elevation: 0,
                  color: cardBg,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: const BorderSide(color: borderColor),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _isHybridMode ? 'Hybrid Cloud Mode' : '100% Offline GGUF Mode',
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  _isHybridMode
                                      ? 'Routes to Cloud API when online, GGUF when offline'
                                      : 'Runs fully on-device with zero network requests',
                                  style: const TextStyle(color: Color(0xFF64748B), fontSize: 12),
                                ),
                              ],
                            ),
                            Switch(
                              value: _isHybridMode,
                              activeColor: primaryIndigo,
                              onChanged: (val) async {
                                setState(() {
                                  _isHybridMode = val;
                                });
                                await _keyService?.setHybridModeEnabled(val);
                              },
                            ),
                          ],
                        ),
                        if (_isHybridMode) ...[
                          const Divider(height: 24, color: borderColor),
                          const Text(
                            'Cloud Provider',
                            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                          ),
                          const SizedBox(height: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            decoration: BoxDecoration(
                              color: slateBg,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: borderColor),
                            ),
                            child: DropdownButtonHideUnderline(
                              child: DropdownButton<CloudLlmProvider>(
                                value: _selectedProvider,
                                isExpanded: true,
                                items: CloudLlmProvider.values.map((provider) {
                                  return DropdownMenuItem<CloudLlmProvider>(
                                    value: provider,
                                    child: Text(provider.displayName),
                                  );
                                }).toList(),
                                onChanged: (newVal) async {
                                  if (newVal != null) {
                                    setState(() {
                                      _selectedProvider = newVal;
                                    });
                                    await _keyService?.setCloudProvider(newVal);
                                  }
                                },
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                          const Text(
                            'User Cloud API Key',
                            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                          ),
                          const SizedBox(height: 6),
                          TextField(
                            controller: _apiKeyController,
                            obscureText: _obscureKey,
                            onChanged: (val) => _saveApiKey(),
                            decoration: InputDecoration(
                              hintText: 'Enter API Key (e.g. AIzaSy...)',
                              filled: true,
                              fillColor: slateBg,
                              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide: const BorderSide(color: borderColor),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide: const BorderSide(color: primaryIndigo),
                              ),
                              suffixIcon: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    icon: Icon(_obscureKey ? Icons.visibility_off : Icons.visibility, size: 20),
                                    onPressed: () {
                                      setState(() {
                                        _obscureKey = !_obscureKey;
                                      });
                                    },
                                  ),
                                  TextButton(
                                    onPressed: _pasteFromClipboard,
                                    child: const Text('Paste', style: TextStyle(color: primaryIndigo, fontWeight: FontWeight.bold)),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: const [
                              Icon(Icons.lock_outline, size: 14, color: Color(0xFF64748B)),
                              SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  'Stored locally in device Keychain. Free offline mode active when empty.',
                                  style: TextStyle(color: Color(0xFF64748B), fontSize: 11),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),

                // SECTION 2: OFFLINE GGUF WEIGHTS
                _buildSectionHeader('OFFLINE GGUF WEIGHTS'),
                const SizedBox(height: 8),
                Card(
                  elevation: 0,
                  color: cardBg,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: const BorderSide(color: borderColor),
                  ),
                  child: ListTile(
                    leading: const Icon(Icons.memory, color: primaryIndigo),
                    title: Text(
                      _ggufModel,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                    subtitle: const Text('Resident RAM Footprint: ~1.3 GB (llama.cpp ARM64)'),
                    trailing: const Icon(Icons.check_circle, color: Color(0xFF10B981), size: 20),
                  ),
                ),
                const SizedBox(height: 20),

                // SECTION 3: BACKEND GATEWAY CONNECTION
                _buildSectionHeader('BACKEND GATEWAY CONNECTION'),
                const SizedBox(height: 8),
                Card(
                  elevation: 0,
                  color: cardBg,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: const BorderSide(color: borderColor),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _isPiHubMode ? 'PiHub Local Discovery (LAN)' : 'Cloud / Custom Internet Backend',
                                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    _isPiHubMode
                                        ? 'Auto-discovers Raspberry Pi gateway on local subnet (127.0.0.1, 10.0.2.2, pihub.local)'
                                        : 'Connects directly over internet to configured URL',
                                    style: const TextStyle(color: Color(0xFF64748B), fontSize: 12),
                                  ),
                                ],
                              ),
                            ),
                            Switch(
                              value: _isPiHubMode,
                              activeColor: primaryIndigo,
                              onChanged: (val) async {
                                setState(() {
                                  _isPiHubMode = val;
                                });
                                await _keyService?.setPiHubModeEnabled(val);
                              },
                            ),
                          ],
                        ),
                        const Divider(height: 24, color: borderColor),
                        if (!_isPiHubMode) ...[
                          const Text(
                            'Internet Backend URL (from .env / settings)',
                            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                          ),
                          const SizedBox(height: 6),
                          TextField(
                            controller: _serverUrlController,
                            onChanged: (val) async {
                              await _keyService?.setCustomServerUrl(val);
                            },
                            decoration: InputDecoration(
                              hintText: 'https://api.mentora.app or http://127.0.0.1:8000',
                              filled: true,
                              fillColor: slateBg,
                              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide: const BorderSide(color: borderColor),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide: const BorderSide(color: primaryIndigo),
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                        ],
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Text(
                                _isPiHubMode
                                    ? 'Search Mode: Local LAN Subnet Probing'
                                    : 'Active URL: ${_serverUrlController.text}',
                                style: const TextStyle(color: Color(0xFF64748B), fontSize: 12, overflow: TextOverflow.ellipsis),
                              ),
                            ),
                            const SizedBox(width: 8),
                            ElevatedButton.icon(
                              onPressed: () async {
                                final client = MentoraBackendClient();
                                final res = await client.checkBackendHealth();
                                if (mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(res['online']
                                          ? '✅ Gateway Connected! (${res['latencyMs']} ms)\nURL: ${res['gateway']}'
                                          : '❌ Connection Failed: ${res['status']}'),
                                      backgroundColor: res['online'] ? const Color(0xFF10B981) : const Color(0xFFEF4444),
                                    ),
                                  );
                                }
                              },
                              icon: const Icon(Icons.bolt, size: 16, color: Colors.white),
                              label: const Text('Test Connection', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
                              style: ElevatedButton.styleFrom(backgroundColor: primaryIndigo),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),

                // SECTION 4: APP INFO & LICENSE
                _buildSectionHeader('APP INFO & LICENSE'),
                const SizedBox(height: 8),
                Card(
                  elevation: 0,
                  color: cardBg,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: const BorderSide(color: borderColor),
                  ),
                  child: const ListTile(
                    leading: Icon(Icons.gavel_outlined, color: Color(0xFF64748B)),
                    title: Text('Apache License 2.0', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                    subtitle: Text('Mentora Open Source Project (Grades 5-12 NCERT)'),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Text(
      title,
      style: const TextStyle(
        color: Color(0xFF64748B),
        fontSize: 12,
        fontWeight: FontWeight.bold,
        letterSpacing: 1.0,
      ),
    );
  }
}
