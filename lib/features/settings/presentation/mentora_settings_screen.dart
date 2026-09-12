import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/user_api_key_service.dart';
import '../../network/services/mentora_backend_client.dart';
import '../../network/domain/backend_url_utils.dart';
import '../../home/presentation/mentora_home_screen.dart';
import 'model_selection_screen.dart';
import 'manage_content_screen.dart';

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
  int _selectedGrade = 9;
  CloudLlmProvider _selectedProvider = CloudLlmProvider.gemini;
  late TextEditingController _apiKeyController;
  late TextEditingController _serverUrlController;
  bool _obscureKey = true;
  String _ggufModel = 'Gemma 3n 2B (Q4_K_M)';

  bool _isDiscovering = false;
  DiscoveryProgress? _discoveryProgress;
  String? _connectedDeviceName;
  String? _connectedUrl;
  int? _latencyMs;

  @override
  void initState() {
    super.initState();
    _apiKeyController = TextEditingController();
    _serverUrlController = TextEditingController();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final service = await UserApiKeyService.getInstance();
    final prefs = await SharedPreferences.getInstance();
    final savedGrade = prefs.getInt('selected_grade') ?? 9;

    setState(() {
      _keyService = service;
      _isHybridMode = service.isHybridModeEnabled;
      _isPiHubMode = service.isPiHubModeEnabled;
      _selectedProvider = service.activeProvider;
      _apiKeyController.text = service.apiKey;
      _serverUrlController.text = service.customServerUrl;
      _ggufModel = service.ggufModelName;
      _selectedGrade = savedGrade;
      _isLoading = false;
    });
  }

  Future<void> _runBackendDiscovery() async {
    setState(() {
      _isDiscovering = true;
      _discoveryProgress = null;
      _connectedDeviceName = null;
      _connectedUrl = null;
      _latencyMs = null;
    });

    final client = MentoraBackendClient();
    final res = await client.checkBackendHealth(
      onProgress: (progress) {
        if (mounted) {
          setState(() {
            _discoveryProgress = progress;
            if (progress.isSuccess) {
              _connectedUrl = progress.connectedUrl;
              _connectedDeviceName = progress.connectedDeviceName;
            }
          });
        }
      },
    );

    if (mounted) {
      setState(() {
        _isDiscovering = false;
        _latencyMs = res['online'] ? res['latencyMs'] : null;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(res['online']
              ? '✅ Connected: ${res['activeUrl']} (${res['latencyMs']} ms)'
              : '❌ Backend Discovery Failed: ${res['status']}'),
          backgroundColor: res['online'] ? const Color(0xFF10B981) : const Color(0xFFEF4444),
        ),
      );
    }
  }

  Future<void> _saveAndProbeCustomUrl([String? inputUrl]) async {
    final raw = inputUrl ?? _serverUrlController.text;
    if (raw.trim().isEmpty) return;

    final normalized = BackendUrlUtils.normalizeUrl(raw);
    _serverUrlController.text = normalized;
    await _keyService?.setCustomServerUrl(normalized);

    setState(() {
      _isDiscovering = true;
      _connectedUrl = null;
      _connectedDeviceName = null;
      _latencyMs = null;
    });

    final res = await BackendUrlUtils.probeUrl(normalized);
    final bool isOnline = res['success'] == true;
    final int? latency = res['latencyMs'];

    if (isOnline) {
      MentoraBackendClient().setBaseUrl(normalized);
    }

    if (mounted) {
      setState(() {
        _isDiscovering = false;
        _latencyMs = isOnline ? latency : null;
        _connectedUrl = isOnline ? normalized : null;
        _connectedDeviceName = isOnline ? 'Manual Backend Gateway ($normalized)' : null;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(isOnline
              ? '✅ Connected to backend: $normalized (${latency ?? 0} ms)'
              : '❌ Unreachable: $normalized — verify IP & backend server status'),
          backgroundColor: isOnline ? const Color(0xFF10B981) : const Color(0xFFEF4444),
        ),
      );
    }
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
        actions: [
          IconButton(
            icon: const Icon(Icons.home_rounded, color: primaryIndigo),
            tooltip: 'Home Dashboard',
            onPressed: () {
              Navigator.pushAndRemoveUntil(
                context,
                MaterialPageRoute(builder: (_) => const MentoraHomeScreen(initialTabIndex: 0)),
                (route) => false,
              );
            },
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: primaryIndigo))
          : ListView(
              padding: const EdgeInsets.all(16.0),
              children: [
                // SECTION 0: GRADE & CONTENT PACK MANAGEMENT
                _buildSectionHeader('GRADE & CONTENT PACK MANAGEMENT'),
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
                                  const Text(
                                    'Active Student Grade',
                                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    'Currently configured for Grade $_selectedGrade NCERT',
                                    style: const TextStyle(color: Color(0xFF64748B), fontSize: 12),
                                  ),
                                ],
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10),
                              decoration: BoxDecoration(
                                color: const Color(0xFFEEF2FF),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: const Color(0xFFC7D2FE)),
                              ),
                              child: DropdownButtonHideUnderline(
                                child: Builder(
                                  builder: (context) {
                                    final availableGrades = List.generate(12, (i) => i + 1);
                                    final currentGrade = availableGrades.contains(_selectedGrade)
                                        ? _selectedGrade
                                        : 9;
                                    return DropdownButton<int>(
                                      value: currentGrade,
                                      icon: const Icon(Icons.arrow_drop_down, color: primaryIndigo),
                                      style: const TextStyle(color: primaryIndigo, fontWeight: FontWeight.bold, fontSize: 14),
                                      items: availableGrades.map((grade) {
                                        return DropdownMenuItem<int>(
                                          value: grade,
                                          child: Text('Grade $grade - NCERT'),
                                        );
                                      }).toList(),
                                      onChanged: (val) async {
                                        if (val != null) {
                                          setState(() => _selectedGrade = val);
                                          final prefs = await SharedPreferences.getInstance();
                                          await prefs.setInt('selected_grade', val);
                                        }
                                      },
                                    );
                                  },
                                ),
                              ),
                            ),
                          ],
                        ),
                        const Divider(height: 24, color: borderColor),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(builder: (context) => const ManageContentScreen()),
                                  );
                                },
                                icon: const Icon(Icons.cloud_download_outlined, color: primaryIndigo),
                                label: const Text('Download & Manage Grade Packs'),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: primaryIndigo,
                                  side: const BorderSide(color: primaryIndigo),
                                  padding: const EdgeInsets.symmetric(vertical: 12),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),

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
                            Expanded(
                              child: Column(
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
                            ),
                            const SizedBox(width: 8),
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
                                    _isPiHubMode ? 'PiHub Local Discovery (LAN & Hostname)' : 'Cloud / Custom Internet Backend',
                                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    _isPiHubMode
                                        ? 'Auto-discovers Raspberry Pi / Laptop hostname gateway on local LAN'
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
                                _runBackendDiscovery();
                              },
                            ),
                          ],
                        ),
                        const Divider(height: 24, color: borderColor),
                        const Text(
                          'Backend Gateway URL / Laptop Host IP',
                          style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'Enter your laptop IP (e.g. 10.35.98.193 or akash-Ubuntu:8000)',
                          style: TextStyle(color: Color(0xFF64748B), fontSize: 12),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _serverUrlController,
                                onSubmitted: (val) => _saveAndProbeCustomUrl(val),
                                decoration: InputDecoration(
                                  hintText: 'http://10.35.98.193:8000 or akash-Ubuntu:8000',
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
                            ),
                            const SizedBox(width: 8),
                            ElevatedButton(
                              onPressed: () => _saveAndProbeCustomUrl(),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: primaryIndigo,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              ),
                              child: const Text('Connect', style: TextStyle(fontWeight: FontWeight.bold)),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),

                        // DISCOVERY PROGRESS BAR & STATUS CARD
                        if (_isDiscovering || _discoveryProgress != null) ...[
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: slateBg,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: borderColor),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Expanded(
                                      child: Text(
                                        _isDiscovering
                                            ? 'Probing Subnet (${_discoveryProgress?.step ?? 0}/${_discoveryProgress?.totalSteps ?? 1})'
                                            : (_connectedUrl != null ? '✅ Connected Device Found' : '❌ Device Not Found'),
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 13,
                                          color: _isDiscovering
                                              ? primaryIndigo
                                              : (_connectedUrl != null ? const Color(0xFF10B981) : const Color(0xFFEF4444)),
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    if (_latencyMs != null) ...[
                                      const SizedBox(width: 8),
                                      Text(
                                        '$_latencyMs ms',
                                        style: const TextStyle(fontSize: 12, color: Color(0xFF64748B), fontWeight: FontWeight.w600),
                                      ),
                                    ],
                                  ],
                                ),
                                const SizedBox(height: 8),
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(4),
                                  child: LinearProgressIndicator(
                                    value: _isDiscovering ? (_discoveryProgress?.progress ?? 0.0) : 1.0,
                                    backgroundColor: const Color(0xFFE2E8F0),
                                    valueColor: AlwaysStoppedAnimation<Color>(
                                      _isDiscovering
                                          ? primaryIndigo
                                          : (_connectedUrl != null ? const Color(0xFF10B981) : const Color(0xFFEF4444)),
                                    ),
                                    minHeight: 6,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  _isDiscovering
                                      ? 'Testing candidate: ${_discoveryProgress?.currentCandidate ?? ""}'
                                      : (_connectedDeviceName ?? _connectedUrl ?? 'Offline'),
                                  style: const TextStyle(fontSize: 12, color: Color(0xFF475569)),
                                ),
                              ],
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
                                    ? 'Probing Laptop Host & Subnet IPs...'
                                    : 'Active URL: ${_serverUrlController.text}',
                                style: const TextStyle(color: Color(0xFF64748B), fontSize: 12, overflow: TextOverflow.ellipsis),
                              ),
                            ),
                            const SizedBox(width: 8),
                            ElevatedButton.icon(
                              onPressed: _isDiscovering ? null : _runBackendDiscovery,
                              icon: Icon(_isDiscovering ? Icons.sync : Icons.bolt, size: 16, color: Colors.white),
                              label: Text(
                                _isDiscovering ? 'Discovering...' : 'Test Connection',
                                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                              ),
                              style: ElevatedButton.styleFrom(backgroundColor: primaryIndigo),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),

                // SECTION 4: OFFLINE AI MODELS & SELECTION
                _buildSectionHeader('OFFLINE AI MODELS & SELECTION (.GGUF)'),
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
                    title: const Text('Local .gguf Model Selection', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                    subtitle: Text('Active Model: $_ggufModel\nTap to pick a local .gguf model file or download Qwen2.5 GGUF.'),
                    trailing: const Icon(Icons.chevron_right, color: Color(0xFF64748B)),
                    onTap: () async {
                      await Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const ModelSelectionScreen()),
                      );
                      _loadSettings();
                    },
                  ),
                ),
                const SizedBox(height: 20),

                // SECTION 5: APP INFO & LICENSE
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
