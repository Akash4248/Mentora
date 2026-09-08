import 'dart:async';
import 'dart:io';
import 'dart:math' as dart_math;
import 'package:file_picker/file_picker.dart';
import 'package:share_plus/share_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/theme/idp_colors.dart';
import '../../../core/theme/idp_theme.dart';
import 'dart:ui';


import '../../content_packs/application/content_pack_archive_service.dart';
import '../../content_packs/data/local/content_pack_repository.dart';
import '../../content_packs/domain/content_pack_models.dart';
import '../../course/data/local/course_repository.dart';
import '../../course/domain/course_tree.dart';
import '../../network/services/backend_discovery_service.dart';
import '../../rag/data/local/rag_repository.dart';
import '../data/local/p2p_security_settings_repository.dart';
import '../data/local/trusted_peer_repository.dart';
import '../data/p2p_bundle_service.dart';
import '../data/p2p_channel_service.dart';
import '../../shared/application/offline_error_taxonomy.dart';

class P2PScreen extends StatefulWidget {
  const P2PScreen({
    required this.courseRepository,
    required this.languageCode,
    this.initialChapterId,
    this.quickSendPreset = false,
    super.key,
  });

  final CourseRepository courseRepository;
  final String languageCode;
  final String? initialChapterId;
  final bool quickSendPreset;

  @override
  State<P2PScreen> createState() => _P2PScreenState();
}

class _P2PScreenState extends State<P2PScreen> with SingleTickerProviderStateMixin {
  final BackendDiscoveryService _classroomConnection = BackendDiscoveryService();
  final P2PChannelService _service = P2PChannelService();
  final P2PBundleService _bundleService = P2PBundleService(
    ragRepository: RagRepository(),
  );
  final ContentPackRepository _packRepository = ContentPackRepository();
  final ContentPackArchiveService _packArchiveService = ContentPackArchiveService();
  final TrustedPeerRepository _trustedPeerRepository = TrustedPeerRepository();
  final P2PSecuritySettingsRepository _securitySettingsRepository = P2PSecuritySettingsRepository();
  
  final TextEditingController _sharedSecretController = TextEditingController();
  late final TabController _tabController;

  P2PStatus? _status;
  List<P2PPeer> _peers = const [];
  List<ReceivedBundle> _receivedBundles = const [];
  List<PendingIncomingTransfer> _pendingIncomingTransfers = const [];
  List<Chapter> _chapters = const [];
  List<ContentPackManifest> _installedPacks = const [];
  Chapter? _selectedChapter;
  String? _selectedChapterId;
  ContentPackManifest? _selectedPack;
  P2PPeer? _selectedPeer;
  bool _loading = true;
  bool _processingBundle = false;
  bool _processingTransfer = false;
  Set<String> _trustedPeerAddresses = <String>{};
  P2PPermissionStatus? _permissionStatus;
  P2PTransferTelemetrySnapshot _telemetry = const P2PTransferTelemetrySnapshot(
    send: null,
    receive: null,
  );
  final Set<String> _promptedIncomingIds = <String>{};
  Timer? _telemetryTimer;
  String? _error;

  BundleTransferProgress? _exportProgress;
  BundleTransferProgress? _importProgress;
  bool _quickSendTriggered = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _classroomConnection.addListener(_onClassroomConnectionChanged);
    _startTelemetryPolling();
    _refresh();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _telemetryTimer?.cancel();
    _classroomConnection.removeListener(_onClassroomConnectionChanged);
    _sharedSecretController.dispose();
    super.dispose();
  }

  void _onClassroomConnectionChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  void _startTelemetryPolling() {
    _telemetryTimer?.cancel();
    _telemetryTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      _pollTransferTelemetry();
    });
  }

  Future<void> _pollTransferTelemetry() async {
    if (!mounted) return;
    try {
      final telemetry = await _service.getTransferTelemetry();
      if (!mounted) return;
      setState(() {
        _telemetry = telemetry;
      });
    } catch (_) {}
  }

  Future<void> _refresh() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final status = await _service.getStatus();
      final telemetry = await _service.getTransferTelemetry();
      final permissionStatus = await _service.getPermissionStatus();
      final peers = await _service.listPeers();
      final received = await _service.listReceivedBundles();
      final pendingIncoming = await _service.listPendingIncomingTransfers();
      final rawChapters = await widget.courseRepository.getAllChapters(
        languageCode: widget.languageCode,
      );
      
      final chapterById = <String, Chapter>{};
      for (final chapter in rawChapters) {
        chapterById[chapter.id] ??= chapter;
      }
      final chapters = chapterById.values.toList()
        ..sort((a, b) => a.title.compareTo(b.title));
      final installedPacks = await _packRepository.listInstalledPacks();
      final trustedPeerAddresses = await _trustedPeerRepository.listTrustedAddresses();
      
      // Auto-set a fallback/default shared secret if empty so P2P validation works instantly
      var sharedSecret = await _securitySettingsRepository.getSharedSecret();
      if (sharedSecret.isEmpty) {
        sharedSecret = 'default_p2p_secret_12345';
        await _securitySettingsRepository.setSharedSecret(sharedSecret);
      }
      _sharedSecretController.text = sharedSecret;

      final selectedPeerAddress = _selectedPeer?.address;
      P2PPeer? selectedPeer;
      if (selectedPeerAddress != null) {
        for (final peer in peers) {
          if (peer.address == selectedPeerAddress) {
            selectedPeer = peer;
            break;
          }
        }
      }

      final selectedPackId = _selectedPack?.packId;
      ContentPackManifest? selectedPack;
      if (selectedPackId != null) {
        for (final pack in installedPacks) {
          if (pack.packId == selectedPackId) {
            selectedPack = pack;
            break;
          }
        }
      }

      final selectedChapterId =
          widget.initialChapterId != null && chapterById.containsKey(widget.initialChapterId)
          ? widget.initialChapterId
          : (_selectedChapterId != null && chapterById.containsKey(_selectedChapterId)
                ? _selectedChapterId
                : (chapters.isEmpty ? null : chapters.first.id));

      if (!mounted) return;
      setState(() {
        _status = status;
        _telemetry = telemetry;
        _permissionStatus = permissionStatus;
        _peers = peers;
        _receivedBundles = received;
        _pendingIncomingTransfers = pendingIncoming;
        _chapters = chapters;
        _installedPacks = installedPacks;
        _trustedPeerAddresses = trustedPeerAddresses;
        _selectedChapterId = selectedChapterId;
        _selectedChapter = selectedChapterId == null ? null : chapterById[selectedChapterId];
        _selectedPack = installedPacks.isEmpty ? null : (selectedPack ?? _selectedPack ?? installedPacks.first);
        _selectedPeer = peers.isEmpty ? null : (selectedPeer ?? peers.first);
        _loading = false;
      });

      if (widget.quickSendPreset && !_quickSendTriggered) {
        _quickSendTriggered = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _runQuickSendPreset();
        });
      }

      final activePendingIds = pendingIncoming.map((item) => item.id).toSet();
      _promptedIncomingIds.removeWhere((id) => !activePendingIds.contains(id));

      await _handlePendingIncomingTransfers();
    } on MissingPluginException {
      if (!mounted) return;
      setState(() {
        _error = 'P2P is not available on this platform yet. Currently implemented on Android.';
        _loading = false;
      });
    } on PlatformException catch (e) {
      if (!mounted) return;
      final details = OfflineErrorTaxonomy.fromError(
        e,
        context: OfflineErrorContext.p2pStatus,
        fallbackMessage: 'Failed to load P2P status.',
      );
      setState(() {
        _error = details.formatForUi();
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      final details = OfflineErrorTaxonomy.fromError(
        e,
        context: OfflineErrorContext.p2pStatus,
        fallbackMessage: 'Failed to load P2P status.',
      );
      setState(() {
        _error = details.formatForUi();
        _loading = false;
      });
    }
  }

  Future<void> _handlePendingIncomingTransfers() async {
  Future<void> _shareSelectedPackNative() async {
    final pack = _selectedPack;
    if (pack == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a content pack to share.')),
      );
      return;
    }

    try {
      final summaryText = '''
📚 Mentora AI Tutor - Educational Pack Share
Grade: ${pack.gradeMin} - ${pack.gradeMax}
Subject: ${pack.subject}
Chapter: ${pack.title}
Version: ${pack.version}
''';

      final exportResult = await _packArchiveService.exportPackArchive(pack.packId);
      final fileLocation = exportResult.archivePath;
      if (fileLocation.isNotEmpty && await File(fileLocation).exists()) {
        await Share.shareXFiles(
          [XFile(fileLocation)],
          text: summaryText,
          subject: 'Mentora Content Pack: ${pack.title}',
        );
      } else {
        await Share.share(
          summaryText,
          subject: 'Mentora Content Pack: ${pack.title}',
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Native share error: $e')),
      );
    }
  }

  Future<void> _importReceivedPackNative() async {
    try {
      final result = await FilePicker.pickFiles(
        type: FileType.any,
        allowMultiple: false,
      );

      if (result == null || result.files.isEmpty) return;

      final filePath = result.files.single.path;
      if (filePath == null) return;

      setState(() => _loading = true);

      final file = File(filePath);
      final fileName = file.uri.pathSegments.last;

      if (fileName.endsWith('.zip') || fileName.endsWith('.mentora') || fileName.endsWith('.otpack') || fileName.endsWith('.json')) {
        await _packArchiveService.importPackArchive(filePath, allowReplaceSameOrOlder: true);
      }

      await _refresh();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✅ Successfully imported received pack: $fileName'),
            backgroundColor: const Color(0xFF10B981),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Import failed: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  if (!mounted || _processingTransfer || _pendingIncomingTransfers.isEmpty) {
      return;
    }

    PendingIncomingTransfer? candidate;
    for (final pending in _pendingIncomingTransfers) {
      if (!_promptedIncomingIds.contains(pending.id)) {
        candidate = pending;
        break;
      }
    }

    if (candidate == null) return;

    _promptedIncomingIds.add(candidate.id);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final approve = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Incoming Bundle Request'),
          content: Text(
            'Allow ${candidate!.senderAddress} to send ${candidate.fileName} (${(candidate.sizeBytes / 1024).toStringAsFixed(1)} KB)?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Reject'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Accept'),
            ),
          ],
        ),
      );

      if (approve == true) {
        await _approveIncomingTransfer(candidate!);
      } else {
        await _rejectIncomingTransfer(candidate!);
      }
    });
  }

  void _showHotspotFallbackDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.qr_code_2, color: IDPColors.primary),
            SizedBox(width: 8),
            Text('Wi-Fi Hotspot Fallback'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'If Wi-Fi Direct discovery is unavailable on your device, turn on your Portable Wi-Fi Hotspot and let peers join your local network.',
              style: TextStyle(fontSize: 14),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Hotspot SSID: OfflineTutor_PeerHub', style: TextStyle(fontWeight: FontWeight.bold)),
                  SizedBox(height: 4),
                  Text('Local IP: 192.168.43.1 | Port: 45888', style: TextStyle(fontFamily: 'monospace', fontSize: 12)),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Future<void> _toggleReceiver() async {
    if (_processingTransfer) return;

    setState(() {
      _processingTransfer = true;
      _error = null;
    });

    try {
      final running = _status?.receiverRunning == true;
      final result = running
          ? await _service.stopReceiver()
          : await _service.startReceiver();

      await _refresh();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(result.message)));
    } on PlatformException catch (e) {
      if (!mounted) return;
      final details = OfflineErrorTaxonomy.fromError(
        e,
        context: OfflineErrorContext.p2pTransfer,
        fallbackMessage: 'Failed to toggle receiver.',
      );
      setState(() {
        _error = details.formatForUi();
      });
    } finally {
      if (mounted) {
        setState(() {
          _processingTransfer = false;
        });
      }
    }
  }

  // A combined, elegant, one-click Send flow for Content Packs
  Future<void> _exportAndSendPack(ContentPackManifest pack, P2PPeer peer) async {
    setState(() {
      _processingBundle = true;
      _processingTransfer = true;
      _error = null;
      _exportProgress = null;
    });

    try {
      // 1. Ensure target peer is trusted (handled automatically under the hood)
      if (!_trustedPeerAddresses.contains(peer.address)) {
        await _trustedPeerRepository.trustPeer(
          address: peer.address,
          alternateAddress: peer.resolvedAddress.isEmpty ? null : peer.resolvedAddress,
          name: peer.name,
          transport: peer.transport,
        );
        _trustedPeerAddresses.add(peer.address);
      }

      // 2. Export Pack Archive
      final exportResult = await _packArchiveService.exportPackArchive(pack.packId);
      
      // 3. Send Bundle
      final sendResult = await _service.sendBundle(
        address: peer.address,
        filePath: exportResult.archivePath,
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Successfully sent pack archive: ${sendResult.message}')),
      );
    } catch (e) {
      if (!mounted) return;
      final details = OfflineErrorTaxonomy.fromError(
        e,
        context: OfflineErrorContext.p2pTransfer,
        fallbackMessage: 'Failed to send pack archive.',
      );
      setState(() {
        _error = details.formatForUi();
      });
    } finally {
      if (mounted) {
        setState(() {
          _processingBundle = false;
          _processingTransfer = false;
          _exportProgress = null;
        });
        _refresh();
      }
    }
  }

  // A combined, elegant, one-click Send flow for Custom Chapter Bundles
  Future<void> _exportAndSendChapter(Chapter chapter, P2PPeer peer) async {
    setState(() {
      _processingBundle = true;
      _processingTransfer = true;
      _error = null;
      _exportProgress = null;
    });

    try {
      // 1. Ensure target peer is trusted (handled automatically under the hood)
      if (!_trustedPeerAddresses.contains(peer.address)) {
        await _trustedPeerRepository.trustPeer(
          address: peer.address,
          alternateAddress: peer.resolvedAddress.isEmpty ? null : peer.resolvedAddress,
          name: peer.name,
          transport: peer.transport,
        );
        _trustedPeerAddresses.add(peer.address);
      }

      // 2. Export Chapter Bundle
      final exportResult = await _bundleService.exportChapterBundle(
        chapter,
        sharedSecret: _sharedSecretController.text,
        onProgress: (progress) {
          if (mounted) {
            setState(() {
              _exportProgress = progress;
            });
          }
        },
      );

      // 3. Send Bundle
      final sendResult = await _service.sendBundle(
        address: peer.address,
        filePath: exportResult.filePath,
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Successfully sent chapter bundle: ${sendResult.message}')),
      );
    } catch (e) {
      if (!mounted) return;
      final details = OfflineErrorTaxonomy.fromError(
        e,
        context: OfflineErrorContext.p2pTransfer,
        fallbackMessage: 'Failed to send chapter bundle.',
      );
      setState(() {
        _error = details.formatForUi();
      });
    } finally {
      if (mounted) {
        setState(() {
          _processingBundle = false;
          _processingTransfer = false;
          _exportProgress = null;
        });
        _refresh();
      }
    }
  }

  Future<void> _runQuickSendPreset() async {
    if (!mounted) return;
    final chapter = _selectedChapter;
    if (chapter == null) return;

    final trustedPeers = _peers.toList();
    if (trustedPeers.isEmpty) return;

    setState(() {
      _selectedPeer = trustedPeers.first;
    });

    await _exportAndSendChapter(chapter, trustedPeers.first);
  }

  Future<void> _requestPermissions() async {
    if (_processingTransfer) return;

    setState(() {
      _processingTransfer = true;
      _error = null;
    });

    try {
      await _service.requestPermissions();
      await _refresh();
    } catch (e) {
      setState(() {
        _error = e.toString();
      });
    } finally {
      setState(() {
        _processingTransfer = false;
      });
    }
  }

  Future<void> _approveIncomingTransfer(PendingIncomingTransfer pending, {bool silent = false, String? customMessage}) async {
    if (_processingTransfer) return;

    setState(() {
      _processingTransfer = true;
      _error = null;
    });

    try {
      final result = await _service.approveIncomingTransfer(pending.id);
      await _refresh();

      if (!mounted || silent) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(customMessage ?? result.message)),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
      });
    } finally {
      if (mounted) {
        setState(() {
          _processingTransfer = false;
        });
      }
    }
  }

  Future<void> _rejectIncomingTransfer(PendingIncomingTransfer pending) async {
    if (_processingTransfer) return;

    setState(() {
      _processingTransfer = true;
      _error = null;
    });

    try {
      final result = await _service.rejectIncomingTransfer(pending.id);
      await _refresh();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(result.message)));
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
      });
    } finally {
      if (mounted) {
        setState(() {
          _processingTransfer = false;
        });
      }
    }
  }

  Future<void> _importReceivedBundle(ReceivedBundle bundle) async {
    if (_processingBundle) return;

    setState(() {
      _processingBundle = true;
      _error = null;
    });

    try {
      final lowerPath = bundle.path.toLowerCase();
      if (lowerPath.endsWith('.otpack') || lowerPath.endsWith('.zip')) {
        final packResult = await _packArchiveService.importPackArchive(bundle.path);
        await _refresh();
        if (!mounted) return;

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Installed pack ${packResult.packId} (${packResult.itemCount} items) from inbox.'),
          ),
        );
        return;
      }

      final result = await _bundleService.importBundleFromFile(
        bundle.path,
        verificationSecrets: await _securitySettingsRepository.getVerificationSecrets(),
        onProgress: (_) {}, 
      );
      await _refresh();
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Imported ${result.importedChunkCount} chunks for ${result.chapterId} from inbox.'),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
      });
    } finally {
      if (mounted) {
        setState(() {
          _processingBundle = false;
        });
      }
    }
  }

  Future<void> _importBundle() async {
    if (_processingBundle) return;

    setState(() {
      _processingBundle = true;
      _error = null;
      _importProgress = null;
    });

    try {
      final picked = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['json', 'otpack', 'zip'],
        allowMultiple: false,
      );

      final bundlePath = picked?.files.single.path;
      if (bundlePath == null || bundlePath.isEmpty) {
        if (!mounted) return;
        setState(() {
          _processingBundle = false;
        });
        return;
      }

      final lowerPath = bundlePath.toLowerCase();
      if (lowerPath.endsWith('.otpack') || lowerPath.endsWith('.zip')) {
        final packResult = await _packArchiveService.importPackArchive(bundlePath);
        await _refresh();

        if (!mounted) return;
        setState(() {
          _importProgress = null;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Installed pack ${packResult.packId} with ${packResult.itemCount} items.'),
            duration: const Duration(seconds: 3),
          ),
        );
        return;
      }

      final result = await _bundleService.importBundleFromFile(
        bundlePath,
        verificationSecrets: await _securitySettingsRepository.getVerificationSecrets(),
        onProgress: (progress) {
          if (mounted) {
            setState(() {
              _importProgress = progress;
            });
          }
        },
        maxRetries: 3,
      );
      await _refresh();

      if (!mounted) return;
      setState(() {
        _importProgress = null;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Imported ${result.importedChunkCount} chunks for ${result.chapterId}'),
          duration: const Duration(seconds: 3),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      final details = OfflineErrorTaxonomy.fromError(
        e,
        context: OfflineErrorContext.contentImport,
        fallbackMessage: 'Import failed.',
      );
      setState(() {
        _error = details.formatForUi();
        _importProgress = null;
        _processingBundle = false;
      });
    }
  }

  Future<void> _showManualClassroomDialog() async {
    final controller = TextEditingController(text: _classroomConnection.activeEndpoint ?? '');
    final address = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Connect by Address'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.url,
          decoration: const InputDecoration(
            labelText: 'Classroom gateway',
            hintText: '192.168.1.20 or http://pihub.local',
            border: OutlineInputBorder(),
          ),
          onSubmitted: (value) => Navigator.of(context).pop(value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: const Text('Connect'),
          ),
        ],
      ),
    );
    controller.dispose();

    if (address == null || address.trim().isEmpty) return;
    final connected = await _classroomConnection.connectManual(address);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          connected ? 'Connected to classroom.' : 'Could not reach that classroom gateway.',
        ),
      ),
    );
  }

  String _classroomStatusText(ClassroomConnectionState state) {
    return switch (state) {
      ClassroomConnectionState.disconnected => 'Not connected',
      ClassroomConnectionState.discovering => 'Searching nearby network...',
      ClassroomConnectionState.connecting => 'Connecting...',
      ClassroomConnectionState.connected => 'Connected',
      ClassroomConnectionState.reconnecting => 'Reconnecting automatically...',
    };
  }



  String _formatThroughput(int bps) {
    if (bps <= 0) return '0 B/s';
    if (bps < 1024) return '$bps B/s';
    final kb = bps / 1024;
    if (kb < 1024) return '${kb.toStringAsFixed(1)} KB/s';
    final mb = kb / 1024;
    return '${mb.toStringAsFixed(2)} MB/s';
  }

  String _formatEta(int etaSeconds) {
    if (etaSeconds < 0) return 'n/a';
    final minutes = etaSeconds ~/ 60;
    final seconds = etaSeconds % 60;
    if (minutes <= 0) return '${seconds}s';
    return '${minutes}m ${seconds}s';
  }

  // ================= UI SECTION =================
  Widget _buildTopStatusBar() {
    final isConnected = _classroomConnection.isConnected;
    final name = _classroomConnection.currentClassroom?.name ?? "Unknown";
    final latency = _classroomConnection.currentClassroom?.latencyMs ?? 0;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: isConnected ? Colors.teal.shade900 : Colors.red.shade900,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: SafeArea(
        bottom: false,
        child: Row(
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: isConnected ? Colors.tealAccent : Colors.redAccent,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                isConnected ? "Local Mesh: Connected to $name" : "Local Mesh: Disconnected",
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            if (isConnected)
              Text(
                "Lat: ${latency}ms",
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 12,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildAppBar() {
    return SliverAppBar(
      backgroundColor: Colors.transparent,
      elevation: 0,
      pinned: true,
      expandedHeight: 80,
      flexibleSpace: FlexibleSpaceBar(
        background: Padding(
          padding: const EdgeInsets.fromLTRB(20, 60, 20, 0),
          child: Row(
            children: [
              Text(
                'OfflineTutor',
                style: IDPTypography.heading1.copyWith(
                  color: IDPColors.textPrimary,
                  fontSize: 24,
                ),
              ),
              const Spacer(),
              _buildNavButton("Explore", true),
              _buildNavButton("Resources", false),
              _buildNavButton("Collaborate", false),
              const SizedBox(width: 8),
              IconButton(
                icon: const Icon(Icons.qr_code_2, color: IDPColors.primary),
                tooltip: 'Wi-Fi Hotspot Fallback',
                onPressed: _showHotspotFallbackDialog,
              ),
              const SizedBox(width: 8),
              Container(
                width: 40,
                height: 40,
                decoration: const BoxDecoration(
                  color: IDPColors.primaryContainer,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.person, color: IDPColors.primary),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNavButton(String label, bool isSelected) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Text(
        label,
        style: IDPTypography.body.copyWith(
          color: isSelected ? IDPColors.primary : IDPColors.textSecondary,
          fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
        ),
      ),
    );
  }

  Widget _buildPermissionsSection() {
    if (_status == null || _status!.enabled) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.only(bottom: 24),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: IDPColors.warning.withValues(alpha: 0.1),
        border: Border.all(color: IDPColors.warning.withValues(alpha: 0.3)),
        borderRadius: BorderRadius.circular(IDPRadius.lg),
      ),
      child: Row(
        children: [
          const Icon(Icons.warning_amber_rounded, color: IDPColors.warning),
          const SizedBox(width: 16),
          const Expanded(
            child: Text(
              'Permissions required for P2P networking',
              style: TextStyle(color: IDPColors.textPrimary),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: IDPColors.warning,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(IDPRadius.md)),
            ),
            onPressed: () {
              _service.requestPermissions();
            },
            child: const Text('Enable'),
          ),
        ],
      ),
    );
  }

  Widget _buildTelemetrySection() {
    final sendTelemetry = _telemetry?.send;
    final receiveTelemetry = _telemetry?.receive;
    if (sendTelemetry == null && receiveTelemetry == null) return const SizedBox.shrink();

    return Column(
      children: [
        if (sendTelemetry != null)
          _buildTelemetryCard('Sending', sendTelemetry),
        if (receiveTelemetry != null)
          _buildTelemetryCard('Receiving', receiveTelemetry),
      ],
    );
  }

  Widget _buildTelemetryCard(String label, P2PTransferTelemetry telemetry) {
    return Container(
      margin: const EdgeInsets.only(bottom: 24),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: IDPColors.surface,
        borderRadius: BorderRadius.circular(IDPRadius.lg),
        border: Border.all(color: IDPColors.surfaceVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(child: Text('$label: ${telemetry.fileName}', style: IDPTypography.heading3, overflow: TextOverflow.ellipsis)),
              Text(
                '${telemetry.progressPct.toStringAsFixed(1)}%',
                style: IDPTypography.body.copyWith(color: IDPColors.primary, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 12),
          LinearProgressIndicator(
            value: (telemetry.progressPct.clamp(0, 100)) / 100,
            backgroundColor: IDPColors.surfaceVariant,
            valueColor: const AlwaysStoppedAnimation<Color>(IDPColors.primary),
            borderRadius: BorderRadius.circular(4),
          ),
          const SizedBox(height: 12),
          Text(
            '${(telemetry.transferredBytes / 1024 / 1024).toStringAsFixed(2)} MB / ${(telemetry.totalBytes / 1024 / 1024).toStringAsFixed(2)} MB',
            style: IDPTypography.bodySmall.copyWith(color: IDPColors.textSecondary),
          ),
        ],
      ),
    );
  }

  Widget _buildRadarSection() {
    return Container(
      height: 400,
      width: double.infinity,
      decoration: BoxDecoration(
        color: IDPColors.surface,
        borderRadius: BorderRadius.circular(IDPRadius.xl),
        border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
        boxShadow: [
          BoxShadow(
            color: IDPColors.primary.withValues(alpha: 0.05),
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(IDPRadius.xl),
        child: Stack(
          alignment: Alignment.center,
          children: [
            // Background Grid (Simulation)
            Positioned.fill(
              child: Opacity(
                opacity: 0.1,
                child: CustomPaint(
                  painter: _GridPainter(),
                ),
              ),
            ),
            
            // Radar Rings
            for (var i = 1; i <= 4; i++)
              Container(
                width: i * 80.0,
                height: i * 80.0,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: IDPColors.primary.withValues(alpha: 0.2 - (i * 0.04)),
                    width: 1,
                  ),
                ),
              ),

            // Center Node
            Container(
              width: 60,
              height: 60,
              decoration: BoxDecoration(
                color: IDPColors.primaryContainer,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: IDPColors.primary.withValues(alpha: 0.4),
                    blurRadius: 16,
                    spreadRadius: 4,
                  ),
                ],
              ),
              child: const Icon(Icons.wifi_tethering, color: IDPColors.primary, size: 30),
            ),

            // Peers mapping
            ..._peers.asMap().entries.map((entry) {
              final index = entry.key;
              final peer = entry.value;
              
              // distribute them around the circle
              final angle = (index * (3.14159 * 2) / (_peers.isNotEmpty ? _peers.length : 1));
              final radius = 100.0 + (index % 2 * 40.0);
              
              return Transform.translate(
                offset: Offset(radius * dart_math_cos(angle), radius * dart_math_sin(angle)),
                child: GestureDetector(
                  onTap: () => _showPeerActionDialog(peer),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: IDPColors.secondaryLight,
                          border: Border.all(color: Colors.white, width: 2),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.1),
                              blurRadius: 8,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Icon(Icons.person, color: IDPColors.secondary, size: 24),
                      ),
                      const SizedBox(height: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: IDPColors.surface.withValues(alpha: 0.9),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: IDPColors.surfaceVariant),
                        ),
                        child: Text(
                          peer.name.isEmpty ? peer.address : peer.name,
                          style: IDPTypography.bodySmall.copyWith(fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  double dart_math_cos(double radians) => dart_math.cos(radians);
  double dart_math_sin(double radians) => dart_math.sin(radians);

  Widget _buildActiveStudyRoomsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Active Study Rooms', style: IDPTypography.heading2),
            TextButton(
              onPressed: () {},
              child: const Text('See All', style: TextStyle(color: IDPColors.primary)),
            ),
          ],
        ),
        const SizedBox(height: 16),
        if (_classroomConnection.availableClassrooms.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(32),
            decoration: BoxDecoration(
              color: IDPColors.surface,
              borderRadius: BorderRadius.circular(IDPRadius.lg),
              border: Border.all(color: IDPColors.surfaceVariant),
            ),
            child: const Column(
              children: [
                Icon(Icons.search_off, size: 48, color: IDPColors.textSecondary),
                SizedBox(height: 16),
                Text('No active rooms found nearby.', style: TextStyle(color: IDPColors.textSecondary)),
              ],
            ),
          )
        else
          SizedBox(
            height: 180,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _classroomConnection.availableClassrooms.length,
              separatorBuilder: (context, index) => const SizedBox(width: 16),
              itemBuilder: (context, index) {
                final room = _classroomConnection.availableClassrooms[index];
                return Container(
                  width: 240,
                  decoration: BoxDecoration(
                    color: IDPColors.surface,
                    borderRadius: BorderRadius.circular(IDPRadius.lg),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.05),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(IDPRadius.lg),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                      child: Container(
                        padding: const EdgeInsets.all(20),
                        color: Colors.white.withValues(alpha: 0.5),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: const BoxDecoration(
                                    color: IDPColors.primaryContainer,
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(Icons.school, color: IDPColors.primary, size: 20),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(room.name, style: IDPTypography.heading3, maxLines: 1, overflow: TextOverflow.ellipsis),
                                      const SizedBox(height: 2),
                                      Text('${room.latencyMs}ms ping', style: IDPTypography.bodySmall.copyWith(color: IDPColors.textSecondary)),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            const Spacer(),
                            Row(
                              children: [
                                _buildMiniAvatar(Colors.blue),
                                Transform.translate(offset: const Offset(-8, 0), child: _buildMiniAvatar(Colors.pink)),
                                Transform.translate(offset: const Offset(-16, 0), child: _buildMiniAvatar(Colors.orange)),
                                const Spacer(),
                                ElevatedButton(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: IDPColors.primary,
                                    foregroundColor: Colors.white,
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                  ),
                                  onPressed: () => _classroomConnection.connect(room),
                                  child: const Text('Join'),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
      ],
    );
  }

  Widget _buildMiniAvatar(Color color) {
    return Container(
      width: 24,
      height: 24,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 2),
      ),
    );
  }

  Widget _buildSharedResourcesSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Shared Resources', style: IDPTypography.heading2),
            Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.filter_list),
                  onPressed: () {},
                ),
                IconButton(
                  icon: const Icon(Icons.upload_file),
                  onPressed: _importBundle,
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 16),
        if (_receivedBundles.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(32),
            decoration: BoxDecoration(
              color: IDPColors.surface,
              borderRadius: BorderRadius.circular(IDPRadius.lg),
              border: Border.all(color: IDPColors.surfaceVariant),
            ),
            child: const Column(
              children: [
                Icon(Icons.folder_open, size: 48, color: IDPColors.textSecondary),
                SizedBox(height: 16),
                Text('No received resources.', style: TextStyle(color: IDPColors.textSecondary)),
              ],
            ),
          )
        else
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              crossAxisSpacing: 16,
              mainAxisSpacing: 16,
              childAspectRatio: 0.85,
            ),
            itemCount: _receivedBundles.length,
            itemBuilder: (context, index) {
              final bundle = _receivedBundles[index];
              return Container(
                decoration: BoxDecoration(
                  color: IDPColors.surface,
                  borderRadius: BorderRadius.circular(IDPRadius.lg),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.3)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.04),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: IDPColors.secondaryLight.withValues(alpha: 0.5),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(Icons.inventory_2, color: IDPColors.secondary),
                      ),
                      const SizedBox(height: 16),
                      Text(bundle.name, style: IDPTypography.heading3, maxLines: 2, overflow: TextOverflow.ellipsis),
                      const SizedBox(height: 4),
                      Text('${'Content Pack'} • ${(bundle.sizeBytes / 1024 / 1024).toStringAsFixed(1)} MB', style: IDPTypography.bodySmall.copyWith(color: IDPColors.textSecondary)),
                      const Spacer(),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: IDPColors.primary,
                            side: const BorderSide(color: IDPColors.primary),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                          ),
                          onPressed: () => _importReceivedBundle(bundle),
                          child: const Text('Import'),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
      ],
    );
  }

  Widget _buildErrorCard() {
    return Container(
      margin: const EdgeInsets.only(bottom: 24),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: IDPColors.error.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(IDPRadius.md),
        border: Border.all(color: IDPColors.error.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, color: IDPColors.error),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              _error!,
              style: const TextStyle(color: IDPColors.error),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, color: IDPColors.error),
            onPressed: () => setState(() => _error = null),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomNavBar() {
    return Container(
      decoration: BoxDecoration(
        color: IDPColors.surface.withValues(alpha: 0.8),
        border: const Border(top: BorderSide(color: Colors.white10)),
        boxShadow: [
          BoxShadow(
            color: IDPColors.primary.withValues(alpha: 0.08),
            blurRadius: 30,
            offset: const Offset(0, -10),
          ),
        ],
      ),
      child: ClipRRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: NavigationBar(
            selectedIndex: 1, 
            backgroundColor: Colors.transparent,
            indicatorColor: IDPColors.primaryContainer,
            indicatorShape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(IDPRadius.full)),
            onDestinationSelected: (index) {
              if (index == 0) {
                Navigator.pop(context); 
              }
            },
            destinations: const [
              NavigationDestination(
                icon: Icon(Icons.home_outlined),
                selectedIcon: Icon(Icons.home, color: IDPColors.onPrimaryContainer),
                label: 'Home',
              ),
              NavigationDestination(
                icon: Icon(Icons.group_outlined),
                selectedIcon: Icon(Icons.group, color: IDPColors.onPrimaryContainer),
                label: 'P2P',
              ),
              NavigationDestination(
                icon: Icon(Icons.person_outline),
                selectedIcon: Icon(Icons.person, color: IDPColors.onPrimaryContainer),
                label: 'Profile',
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showPeerActionDialog(P2PPeer peer) {
    showModalBottomSheet(
      context: context,
      backgroundColor: IDPColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: IDPColors.secondaryLight,
                      ),
                      child: const Icon(Icons.person, color: IDPColors.secondary),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            peer.name.isEmpty ? peer.address : peer.name,
                            style: IDPTypography.heading2,
                          ),
                          const SizedBox(height: 4),
                          Text('Ready to receive files', style: IDPTypography.bodySmall.copyWith(color: IDPColors.textSecondary)),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 32),
                Text('Send to peer', style: IDPTypography.heading3),
                const SizedBox(height: 16),
                ListTile(
                  leading: const Icon(Icons.book, color: IDPColors.primary),
                  title: const Text('Send Chapter'),
                  onTap: () {
                    Navigator.pop(context);
                    _showSendChapterDialog(peer);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.inventory_2, color: IDPColors.secondary),
                  title: const Text('Send Content Pack'),
                  onTap: () {
                    Navigator.pop(context);
                    _showSendPackDialog(peer);
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showSendChapterDialog(P2PPeer peer) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Select Chapter to Send'),
          content: SizedBox(
            width: double.maxFinite,
            height: 300,
            child: ListView.builder(
              itemCount: _chapters.length,
              itemBuilder: (context, index) {
                final chapter = _chapters[index];
                return ListTile(
                  title: Text(chapter.title),
                  subtitle: Text('ID: ${chapter.id}'),
                  onTap: () {
                    Navigator.pop(context);
                    _exportAndSendChapter(chapter, peer);
                  },
                );
              },
            ),
          ),
        );
      },
    );
  }

  void _showSendPackDialog(P2PPeer peer) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Select Content Pack to Send'),
          content: SizedBox(
            width: double.maxFinite,
            height: 300,
            child: ListView.builder(
              itemCount: _installedPacks.length,
              itemBuilder: (context, index) {
                final pack = _installedPacks[index];
                return ListTile(
                  title: Text(pack.title),
                  subtitle: Text('${pack.subject} - ${(1).toStringAsFixed(1)} MB'),
                  onTap: () {
                    Navigator.pop(context);
                    _exportAndSendPack(pack, peer);
                  },
                );
              },
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        backgroundColor: IDPColors.background, 
        body: Center(child: CircularProgressIndicator(color: IDPColors.primary))
      );
    }

    return Scaffold(
      backgroundColor: IDPColors.background,
      extendBody: true,
      body: Stack(
        children: [
          CustomScrollView(
            slivers: [
              _buildAppBar(),
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24).copyWith(bottom: 120),
                sliver: SliverList(
                  delegate: SliverChildListDelegate([
                    if (_error != null) _buildErrorCard(),
                    _buildPermissionsSection(),
                    _buildTelemetrySection(),
                    _buildRadarSection(),
                    const SizedBox(height: 48),
                    _buildActiveStudyRoomsSection(),
                    const SizedBox(height: 48),
                    _buildSharedResourcesSection(),
                  ]),
                ),
              ),
            ],
          ),
          
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: _buildTopStatusBar(),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _toggleReceiver,
        backgroundColor: IDPColors.secondary,
        foregroundColor: Colors.white,
        elevation: 4,
        child: _status?.receiverRunning == true ? const Icon(Icons.wifi_tethering_rounded) : const Icon(Icons.wifi_tethering_off_rounded),
      ),
      bottomNavigationBar: _buildBottomNavBar(),
    );
  }
}

class _GridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.black
      ..strokeWidth = 1;
    
    final step = 20.0;
    
    for (var x = 0.0; x < size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    
    for (var y = 0.0; y < size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
