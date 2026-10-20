import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../../../core/theme/idp_theme.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../application/content_pack_archive_service.dart';
import '../application/content_pack_policy_service.dart';
import '../application/content_pack_sync_service.dart';
import '../data/local/content_pack_repository.dart';
import '../domain/content_pack_models.dart';
import '../../network/data/backend_api_service.dart';
import '../../network/domain/backend_config.dart';
import '../../network/domain/endpoint_builder.dart';
import '../../network/domain/runtime_backend_url.dart';
import '../../shared/application/offline_error_taxonomy.dart';
import '../../../config/app_environment.dart';

class ContentPackInstallerScreen extends StatefulWidget {
  const ContentPackInstallerScreen({super.key});

  @override
  State<ContentPackInstallerScreen> createState() => _ContentPackInstallerScreenState();
}

class _ContentPackInstallerScreenState extends State<ContentPackInstallerScreen> {
  static const String _catalogUrlPreferenceKey = 'content_pack_catalog_url';

  final ContentPackRepository _repository = ContentPackRepository();
  final ContentPackArchiveService _archiveService = ContentPackArchiveService();
  final ContentPackPolicyService _policyService = const ContentPackPolicyService();
  final ContentPackSyncService _syncService = const ContentPackSyncService();
  final TextEditingController _urlController = TextEditingController();
  final TextEditingController _catalogUrlController = TextEditingController();
  late final BackendApiService _backendService = BackendApiService(config: BackendConfig.fromEnvironment() ?? BackendConfig(baseUrl: 'http://localhost', apiKey: ''));

  bool _loading = true;
  bool _installing = false;
  bool _checkingCatalog = false;
  bool _discoveringCatalogs = false;
  bool _bootstrappingCatalog = false;
  bool _checkingHealth = false;
  bool _installingCatalogQueue = false;
  String? _error;
  ContentPackReadinessReport? _readiness;
  ContentPackSyncPlan? _syncPlan;
  HotspotHealthReport? _healthReport;
  List<String> _discoveredCatalogUrls = const <String>[];
  List<ContentPackCatalogEntry> _packs = const <ContentPackCatalogEntry>[];

  @override
  void initState() {
    super.initState();
    // Live gateway catalog via EndpointBuilder - eliminates hardcoded probe 404.
    // Gateway route: GET /packs/catalog (via nginx, no hardcoded IP/port).
    _catalogUrlController.text = EndpointBuilder.fromEnvironment().packsCatalog;
    // Fallback to RuntimeBackendUrl if env baseUrl empty at boot (rare).
    if (_catalogUrlController.text.isEmpty || _catalogUrlController.text == '/packs/catalog') {
      final runtimeUrl = RuntimeBackendUrl().current;
      if (runtimeUrl.isNotEmpty) {
        _catalogUrlController.text = '$runtimeUrl/packs/catalog';
      }
    }
    _restoreCatalogUrlPreference();
    _refreshPacks();
    _bootstrapCatalogUrl();
  }

  @override
  void dispose() {
    _urlController.dispose();
    _catalogUrlController.dispose();
    super.dispose();
  }

  Future<void> _refreshPacks() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final manifests = await _repository.listInstalledPacks();
      final entries = <ContentPackCatalogEntry>[];
      for (final manifest in manifests) {
        entries.add(await _repository.buildCatalogEntry(manifest.packId));
      }

      if (!mounted) {
        return;
      }
      setState(() {
        _packs = entries;
        _readiness = _policyService.evaluate(installedPacks: manifests);
        if (_syncPlan != null) {
          _syncPlan = _syncService.buildPlan(
            snapshot: _syncPlan!.snapshot,
            installedPacks: manifests,
          );
        }
        _loading = false;
      });
    } catch (e) {
      if (!mounted) {
        return;
      }
      final details = OfflineErrorTaxonomy.fromError(
        e,
        context: OfflineErrorContext.contentImport,
        fallbackMessage: 'Failed to load packs.',
      );
      setState(() {
        _loading = false;
        _error = details.formatForUi();
      });
    }
  }

  Future<void> _checkRaspberryCatalog() async {
    final catalogUrl = _normalizedCatalogUrl();
    if (catalogUrl.isEmpty) {
      setState(() {
        _error = 'Enter Raspberry server catalog URL first.';
      });
      return;
    }

    final parsed = Uri.tryParse(catalogUrl);
    if (parsed == null || (parsed.scheme != 'http' && parsed.scheme != 'https')) {
      setState(() {
        _error = 'Catalog URL must start with http:// or https://';
      });
      return;
    }

    setState(() {
      _checkingCatalog = true;
      _error = null;
    });

    try {
      final snapshot = await _syncService.fetchCatalog(catalogUrl);
      final installed = await _repository.listInstalledPacks();
      final plan = _syncService.buildPlan(
        snapshot: snapshot,
        installedPacks: installed,
      );

      if (!mounted) {
        return;
      }
      await _saveCatalogUrlPreference(catalogUrl);
      setState(() {
        _syncPlan = plan;
      });
    } catch (e) {
      if (!mounted) {
        return;
      }
      final details = OfflineErrorTaxonomy.fromError(
        e,
        context: OfflineErrorContext.catalogSync,
        fallbackMessage: 'Catalog sync failed.',
      );
      setState(() {
        _error = details.formatForUi();
      });
    } finally {
      if (mounted) {
        setState(() {
          _checkingCatalog = false;
        });
      }
    }
  }

  Future<void> _checkBackendCatalog() async {
    setState(() {
      _checkingCatalog = true;
      _error = null;
    });

    try {
      final snapshot = await _syncService.fetchCatalogFromBackend(_backendService);
      final installed = await _repository.listInstalledPacks();
      final plan = _syncService.buildPlan(
        snapshot: snapshot,
        installedPacks: installed,
      );

      if (!mounted) {
        return;
      }
      setState(() {
        _syncPlan = plan;
      });
    } catch (e) {
      if (!mounted) {
        return;
      }
      final details = OfflineErrorTaxonomy.fromError(
        e,
        context: OfflineErrorContext.catalogSync,
        fallbackMessage: 'Backend catalog sync failed.',
      );
      setState(() {
        _error = details.formatForUi();
      });
    } finally {
      if (mounted) {
        setState(() {
          _checkingCatalog = false;
        });
      }
    }
  }

  Future<void> _discoverCatalogServers() async {
    setState(() {
      _discoveringCatalogs = true;
      _error = null;
    });

    try {
      final found = await _syncService.discoverCatalogUrls();
      if (!mounted) {
        return;
      }
      setState(() {
        _discoveredCatalogUrls = found;
        if (found.isNotEmpty) {
          _catalogUrlController.text = found.first;
        }
      });
      if (found.isNotEmpty) {
        await _saveCatalogUrlPreference(found.first);
      }
      if (!mounted) {
        return;
      }
      if (found.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No catalog server auto-discovered. Enter URL manually.')),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Discovered ${found.length} reachable catalog URL(s).')),
        );
      }
    } catch (e) {
      if (!mounted) {
        return;
      }
      final details = OfflineErrorTaxonomy.fromError(
        e,
        context: OfflineErrorContext.catalogDiscovery,
        fallbackMessage: 'Catalog discovery failed.',
      );
      setState(() {
        _error = details.formatForUi();
      });
    } finally {
      if (mounted) {
        setState(() {
          _discoveringCatalogs = false;
        });
      }
    }
  }

  Future<void> _bootstrapCatalogUrl() async {
    if (_bootstrappingCatalog) {
      return;
    }

    setState(() {
      _bootstrappingCatalog = true;
    });

    try {
      final current = _normalizedCatalogUrl();
      final reachableCurrent = await _syncService.isCatalogUrlReachable(current);
      if (reachableCurrent) {
        await _saveCatalogUrlPreference(current);
        return;
      }

      final discovered = await _syncService.discoverCatalogUrls();
      if (!mounted) {
        return;
      }
      if (discovered.isNotEmpty) {
        setState(() {
          _discoveredCatalogUrls = discovered;
          _catalogUrlController.text = discovered.first;
        });
        await _saveCatalogUrlPreference(discovered.first);
      }
    } catch (_) {
      // Ignore bootstrap errors. Manual entry/discovery still works.
    } finally {
      if (mounted) {
        setState(() {
          _bootstrappingCatalog = false;
        });
      }
    }
  }

  Future<void> _installMissingRequiredFromCatalog() async {
    final plan = _syncPlan;
    if (plan == null) {
      setState(() {
        _error = 'Check Raspberry catalog first.';
      });
      return;
    }
    if (plan.requiredInstallQueue.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No required downloads pending from catalog.')),
      );
      return;
    }

    setState(() {
      _installingCatalogQueue = true;
      _error = null;
    });

    var installedCount = 0;
    var skippedCount = 0;
    var failedCount = 0;
    final failureMessages = <String>[];

    for (final remote in plan.requiredInstallQueue) {
      try {
        String downloadedPath;
        if (remote.archiveUrl.toString().startsWith(AppEnvironment.backendBaseUrl)) {
          final tempDir = await getTemporaryDirectory();
          final ext = remote.archiveUrl.path.toLowerCase().endsWith('.zip') ? '.zip' : '.otpack';
          final tempPath = p.join(
            tempDir.path,
            'catalog_pack_${DateTime.now().millisecondsSinceEpoch}$ext',
          );
          downloadedPath = await _backendService.downloadPack(remote.packId, tempPath);
        } else {
          downloadedPath = await _downloadPackArchive(remote.archiveUrl);
        }
        await _archiveService.importPackArchive(
          downloadedPath,
          remotePackOverride: remote,
        );
        installedCount += 1;
      } on PackVersionConflictException catch (e) {
        skippedCount += 1;
        failureMessages.add('Skipped ${remote.packId}: $e');
      } catch (e) {
        failedCount += 1;
        failureMessages.add('Failed ${remote.packId}: $e');
      }
    }

    await _refreshPacks();
    await _checkRaspberryCatalog();

    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Catalog install complete: installed $installedCount, skipped $skippedCount, failed $failedCount.',
        ),
      ),
    );

    if (failureMessages.isNotEmpty) {
      setState(() {
        _error = failureMessages.take(3).join('\n');
      });
    }

    setState(() {
      _installingCatalogQueue = false;
    });
  }

  Future<void> _runHotspotHealthCheck() async {
    final catalogUrl = _normalizedCatalogUrl();
    if (catalogUrl.isEmpty) {
      setState(() {
        _error = 'Enter catalog URL first for health check.';
      });
      return;
    }

    final parsed = Uri.tryParse(catalogUrl);
    if (parsed == null || (parsed.scheme != 'http' && parsed.scheme != 'https')) {
      setState(() {
        _error = 'Catalog URL must start with http:// or https://';
      });
      return;
    }

    setState(() {
      _checkingHealth = true;
      _error = null;
    });

    try {
      final report = await _syncService.runHotspotHealthCheck(
        catalogUrl: catalogUrl,
        remainingQueue: _syncPlan?.requiredInstallQueue ?? const <RemoteContentPack>[],
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _healthReport = report;
      });
    } catch (e) {
      if (!mounted) {
        return;
      }
      final details = OfflineErrorTaxonomy.fromError(
        e,
        context: OfflineErrorContext.catalogHealthCheck,
        fallbackMessage: 'Hotspot health check failed.',
      );
      setState(() {
        _error = details.formatForUi();
      });
    } finally {
      if (mounted) {
        setState(() {
          _checkingHealth = false;
        });
      }
    }
  }

  Future<String> _downloadPackArchive(Uri archiveUrl) async {
    final tempDir = await getTemporaryDirectory();
    final ext = archiveUrl.path.toLowerCase().endsWith('.zip') ? '.zip' : '.otpack';
    final tempPath = p.join(
      tempDir.path,
      'catalog_pack_${DateTime.now().millisecondsSinceEpoch}$ext',
    );
    final file = File(tempPath);

    final client = HttpClient();
    try {
      final request = await client.getUrl(archiveUrl);
      final response = await request.close();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception('Pack download failed with HTTP ${response.statusCode}');
      }
      await response.pipe(file.openWrite());
      return file.path;
    } finally {
      client.close(force: true);
    }
  }

  String _normalizedCatalogUrl() {
    var value = _catalogUrlController.text.trim();
    if (value.startsWith('tp://')) {
      value = 'h$value';
    }
    if (!value.contains('://') && value.contains('.')) {
      value = 'http://$value';
    }
    if (value.endsWith('/')) {
      value = value.substring(0, value.length - 1);
    }
    if (value.toLowerCase().endsWith('/packs/catalog') ||
        value.toLowerCase().endsWith('/packs') ||
        value.toLowerCase().endsWith('/catalog.json')) {
      return value;
    }
    value = '$value/packs/catalog';
    if (_catalogUrlController.text != value) {
      _catalogUrlController.text = value;
    }
    return value;
  }

  Future<void> _restoreCatalogUrlPreference() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final value = prefs.getString(_catalogUrlPreferenceKey);
      if (value == null || value.trim().isEmpty) {
        return;
      }
      if (!mounted) {
        return;
      }
      setState(() {
        _catalogUrlController.text = value.trim();
      });
      await _bootstrapCatalogUrl();
    } catch (_) {
      // Ignore preference read failures and keep defaults.
    }
  }

  Future<void> _saveCatalogUrlPreference(String value) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_catalogUrlPreferenceKey, value.trim());
    } catch (_) {
      // Ignore preference write failures.
    }
  }

  Future<void> _installFromFile() async {
    if (_installing) {
      return;
    }

    final picked = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const <String>['otpack', 'zip'],
      allowMultiple: false,
    );
    final filePath = picked?.files.single.path;
    if (filePath == null || filePath.trim().isEmpty) {
      return;
    }

    await _installArchive(filePath.trim(), sourceLabel: 'local file');
  }

  Future<void> _installFromUrl() async {
    if (_installing) {
      return;
    }

    final raw = _urlController.text.trim();
    if (raw.isEmpty) {
      setState(() {
        _error = 'Provide a pack URL ending with .otpack or .zip';
      });
      return;
    }

    Uri? uri;
    try {
      uri = Uri.parse(raw);
    } catch (_) {
      setState(() {
        _error = 'Invalid URL format.';
      });
      return;
    }

    if (uri.scheme != 'http' && uri.scheme != 'https') {
      setState(() {
        _error = 'Only http/https URLs are supported.';
      });
      return;
    }

    setState(() {
      _installing = true;
      _error = null;
    });

    try {
      final tempDir = await getTemporaryDirectory();
      final ext = raw.toLowerCase().endsWith('.zip') ? '.zip' : '.otpack';
      final tempPath = p.join(
        tempDir.path,
        'pack_${DateTime.now().millisecondsSinceEpoch}$ext',
      );
      final target = File(tempPath);

      final client = HttpClient();
      try {
        final request = await client.getUrl(uri);
        final response = await request.close();
        if (response.statusCode < 200 || response.statusCode >= 300) {
          throw Exception('Download failed with HTTP ${response.statusCode}');
        }
        await response.pipe(target.openWrite());
      } finally {
        client.close(force: true);
      }

      if (!mounted) {
        return;
      }

      setState(() {
        _installing = false;
      });
      await _installArchive(tempPath, sourceLabel: 'URL');
    } catch (e) {
      if (!mounted) {
        return;
      }
      final details = OfflineErrorTaxonomy.fromError(
        e,
        context: OfflineErrorContext.contentImport,
        fallbackMessage: 'Failed to download pack.',
      );
      setState(() {
        _installing = false;
        _error = details.formatForUi();
      });
    }
  }

  Future<void> _installArchive(String archivePath, {required String sourceLabel}) async {
    setState(() {
      _installing = true;
      _error = null;
    });

    try {
      final result = await _archiveService.importPackArchive(archivePath);
      await _refreshPacks();

      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Installed ${result.packId} (${result.itemCount} items) from $sourceLabel.',
          ),
        ),
      );
    } on PackVersionConflictException catch (conflict) {
      final forceReplace = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('Version Conflict'),
          content: Text(
            'Installed version: v${conflict.installedVersion}\n'
            'Incoming version: v${conflict.incomingVersion}\n\n'
            'Only newer packs are installed by default. Replace anyway?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Force Replace'),
            ),
          ],
        ),
      );

      if (forceReplace == true) {
        final forceResult = await _archiveService.importPackArchive(
          archivePath,
          allowReplaceSameOrOlder: true,
        );
        await _refreshPacks();
        if (!mounted) {
          return;
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Force replaced ${forceResult.packId} with v${conflict.incomingVersion}.',
            ),
          ),
        );
      }
    } catch (e) {
      if (!mounted) {
        return;
      }
      final details = OfflineErrorTaxonomy.fromError(
        e,
        context: OfflineErrorContext.contentImport,
        fallbackMessage: 'Pack installation failed.',
      );
      setState(() {
        _error = details.formatForUi();
      });
    } finally {
      if (mounted) {
        setState(() {
          _installing = false;
        });
      }
    }
  }

  Future<void> _removePack(ContentPackCatalogEntry entry) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Remove Pack'),
        content: Text('Remove ${entry.manifest.title} from this device?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );

    if (confirm != true) {
      return;
    }

    try {
      final rootPath = entry.manifest.rootPath;
      final rootDir = Directory(rootPath);
      if (await rootDir.exists()) {
        // Imported packs are extracted under .../incoming_x/content. Remove parent folder.
        final parent = rootDir.parent;
        if (p.basename(rootDir.path) == 'content' && await parent.exists()) {
          await parent.delete(recursive: true);
        } else {
          await rootDir.delete(recursive: true);
        }
      }

      await _repository.deletePack(entry.manifest.packId);
      await _refreshPacks();

      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Removed ${entry.manifest.title}')),
      );
    } catch (e) {
      if (!mounted) {
        return;
      }
      final details = OfflineErrorTaxonomy.fromError(
        e,
        context: OfflineErrorContext.contentImport,
        fallbackMessage: 'Failed to remove pack.',
      );
      setState(() {
        _error = details.formatForUi();
      });
    }
  }

  List<String> _statusLabelsForPack(ContentPackCatalogEntry entry) {
    final labels = <String>['Installed'];
    final readiness = _readiness;
    if (readiness == null) {
      return labels;
    }

    final supportsMandatoryRule = readiness.statuses.any(
      (status) =>
          status.rule.mandatory &&
          status.matchingPacks.any((pack) => pack.packId == entry.manifest.packId),
    );

    if (supportsMandatoryRule) {
      labels.add('Required Coverage');
    } else {
      labels.add('Optional');
    }

    if (entry.manifest.status.trim().toLowerCase() != 'installed') {
      labels.add(entry.manifest.status);
    }

    return labels;
  }

  @override
  @override
  Widget build(BuildContext context) {
    // Total installed packs size
    int totalInstalledBytes = 0;
    for (final pack in _packs) {
      totalInstalledBytes += pack.manifest.contentSizeBytes;
    }
    // Dummy system data size for the UI meter (7.3 GB as in design)
    const int mockSystemDataBytes = 7838315315; 
    const int mockTotalSpaceBytes = 68719476736; // 64 GB

    return Scaffold(
      backgroundColor: IDPColors.background,
      appBar: AppBar(
        backgroundColor: IDPColors.surface.withValues(alpha: 0.8),
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        title: Text(
          'OfflineTutor',
          style: TextStyle(
            fontFamily: IDPTypography.headlineFontFamily,
            fontSize: 28,
            fontWeight: FontWeight.w700,
            color: IDPColors.primary,
          ),
        ),
        leading: const Icon(
          Icons.signal_wifi_off_rounded,
          color: IDPColors.primary,
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.notifications_outlined, color: IDPColors.onSurfaceVariant),
            onPressed: () {},
          ),
          Padding(
            padding: const EdgeInsets.only(right: 16.0, left: 8.0),
            child: CircleAvatar(
              radius: 18,
              backgroundColor: IDPColors.surfaceContainerHighest,
              child: const Icon(Icons.person, color: IDPColors.onSurfaceVariant, size: 20),
            ),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: () async {
                await _refreshPacks();
              },
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
                children: [
                  // Hero Section: Storage & Sync
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final isWide = constraints.maxWidth > 600;
                      return Flex(
                        direction: isWide ? Axis.horizontal : Axis.vertical,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // Storage Meter Card
                          Expanded(
                            flex: isWide ? 2 : 0,
                            child: Container(
                              padding: const EdgeInsets.all(24),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.7),
                                borderRadius: BorderRadius.circular(24),
                                border: Border.all(color: Colors.white.withValues(alpha: 0.3)),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.05),
                                    blurRadius: 10,
                                    offset: const Offset(0, 4),
                                  ),
                                ],
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            'INTERNAL STORAGE',
                                            style: IDPTypography.labelMd.copyWith(
                                              color: IDPColors.onSurfaceVariant,
                                              letterSpacing: 1.2,
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          RichText(
                                            text: TextSpan(
                                              style: IDPTypography.headlineLgMobile.copyWith(
                                                color: IDPColors.onSurface,
                                              ),
                                              children: [
                                                TextSpan(text: '${_formatSize(totalInstalledBytes)} '),
                                                TextSpan(
                                                  text: '/ ${_formatSize(mockTotalSpaceBytes)} used',
                                                  style: IDPTypography.bodyMd.copyWith(
                                                    color: IDPColors.onSurfaceVariant,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ),
                                      Row(
                                        children: [
                                          const Icon(Icons.offline_pin, color: IDPColors.secondary, size: 18),
                                          const SizedBox(width: 4),
                                          Text(
                                            'Safe Offline',
                                            style: IDPTypography.labelMd.copyWith(color: IDPColors.secondary),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 16),
                                  // Progress Bar
                                  Container(
                                    height: 16,
                                    width: double.infinity,
                                    decoration: BoxDecoration(
                                      color: IDPColors.surfaceContainerHighest,
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: LayoutBuilder(
                                      builder: (context, boxConstraints) {
                                        final installedPct = totalInstalledBytes / mockTotalSpaceBytes;
                                        final sysPct = mockSystemDataBytes / mockTotalSpaceBytes;
                                        return Row(
                                          children: [
                                            Container(
                                              width: boxConstraints.maxWidth * installedPct,
                                              decoration: BoxDecoration(
                                                color: IDPColors.primary,
                                                borderRadius: const BorderRadius.horizontal(left: Radius.circular(8)),
                                                boxShadow: [
                                                  BoxShadow(
                                                    color: IDPColors.primary.withValues(alpha: 0.2),
                                                    blurRadius: 10,
                                                  ),
                                                ],
                                              ),
                                            ),
                                            Container(
                                              width: boxConstraints.maxWidth * sysPct,
                                              decoration: const BoxDecoration(
                                                color: IDPColors.secondary,
                                                borderRadius: BorderRadius.horizontal(right: Radius.circular(8)),
                                              ),
                                            ),
                                          ],
                                        );
                                      },
                                    ),
                                  ),
                                  const SizedBox(height: 16),
                                  Row(
                                    children: [
                                      Row(
                                        children: [
                                          Container(width: 10, height: 10, decoration: const BoxDecoration(color: IDPColors.primary, shape: BoxShape.circle)),
                                          const SizedBox(width: 8),
                                          Text('Installed Packs (${_formatSize(totalInstalledBytes)})', style: IDPTypography.caption.copyWith(color: IDPColors.onSurfaceVariant)),
                                        ],
                                      ),
                                      const SizedBox(width: 24),
                                      Row(
                                        children: [
                                          Container(width: 10, height: 10, decoration: const BoxDecoration(color: IDPColors.secondary, shape: BoxShape.circle)),
                                          const SizedBox(width: 8),
                                          Text('System Data (${_formatSize(mockSystemDataBytes)})', style: IDPTypography.caption.copyWith(color: IDPColors.onSurfaceVariant)),
                                        ],
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                          if (isWide) const SizedBox(width: 24) else const SizedBox(height: 24),
                          // Sync All Action
                          Expanded(
                            flex: isWide ? 1 : 0,
                            child: Container(
                              padding: const EdgeInsets.all(24),
                              decoration: BoxDecoration(
                                color: IDPColors.primaryContainer,
                                borderRadius: BorderRadius.circular(24),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.1),
                                    blurRadius: 10,
                                    offset: const Offset(0, 4),
                                  ),
                                ],
                              ),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.cloud_done, size: 48, color: IDPColors.onPrimaryContainer.withValues(alpha: 0.6)),
                                  const SizedBox(height: 16),
                                  Text('Stay Updated', style: IDPTypography.titleMd.copyWith(color: IDPColors.onPrimaryContainer, fontWeight: FontWeight.bold)),
                                  const SizedBox(height: 4),
                                  Text(
                                    _syncPlan != null && _syncPlan!.updatableCount > 0
                                        ? '${_syncPlan!.updatableCount} updates pending for your courses.'
                                        : 'Your offline courses are ready.',
                                    style: IDPTypography.caption.copyWith(color: IDPColors.onPrimaryContainer.withValues(alpha: 0.9)),
                                    textAlign: TextAlign.center,
                                  ),
                                  const SizedBox(height: 16),
                                  SizedBox(
                                    width: double.infinity,
                                    child: ElevatedButton.icon(
                                      onPressed: (_checkingCatalog || _installingCatalogQueue) ? null : () async {
                                        await _checkBackendCatalog();
                                        if (mounted && _syncPlan != null) {
                                          _installMissingRequiredFromCatalog();
                                        }
                                      },
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: IDPColors.primary,
                                        foregroundColor: IDPColors.onPrimary,
                                        padding: const EdgeInsets.symmetric(vertical: 16),
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
                                      ),
                                      icon: (_checkingCatalog || _installingCatalogQueue)
                                          ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                                          : const Icon(Icons.cloud_sync, size: 20),
                                      label: Text((_checkingCatalog || _installingCatalogQueue) ? 'Syncing...' : 'Sync All', style: IDPTypography.labelMd),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      );
                    }
                  ),
                  const SizedBox(height: 48),
                  
                  // Installed Packs Section
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Installed Packs', style: IDPTypography.headlineLgMobile.copyWith(color: IDPColors.onSurface)),
                      // Manage All could show the older debug controls
                      TextButton(
                        onPressed: () {
                          // Toggle advanced settings visibility, maybe via dialog for now
                          _showAdvancedSettingsDialog(context);
                        },
                        child: Text('Manage All', style: IDPTypography.labelMd.copyWith(color: IDPColors.primary)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  if (_packs.isEmpty)
                    Container(
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.7),
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(color: Colors.white.withValues(alpha: 0.3)),
                      ),
                      child: const Center(child: Text('No packs installed yet.')),
                    )
                  else
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final isWide = constraints.maxWidth > 600;
                        return GridView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: isWide ? 2 : 1,
                            mainAxisSpacing: 24,
                            crossAxisSpacing: 24,
                            mainAxisExtent: 140,
                          ),
                          itemCount: _packs.length,
                          itemBuilder: (context, index) {
                            final entry = _packs[index];
                            final hasUpdate = _syncPlan?.entries.any((e) => e.installed?.packId == entry.manifest.packId && e.hasUpdate) ?? false;
                            
                            return Container(
                              padding: const EdgeInsets.all(24),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.7),
                                borderRadius: BorderRadius.circular(24),
                                border: Border.all(color: Colors.white.withValues(alpha: 0.3)),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.05),
                                    blurRadius: 10,
                                    offset: const Offset(0, 4),
                                  ),
                                ],
                              ),
                              child: Row(
                                children: [
                                  // Thumbnail (placeholder with icon)
                                  Container(
                                    width: 96,
                                    height: 96,
                                    decoration: BoxDecoration(
                                      color: IDPColors.surfaceContainerLowest,
                                      borderRadius: BorderRadius.circular(16),
                                    ),
                                    child: Icon(Icons.school_rounded, size: 48, color: IDPColors.primary.withValues(alpha: 0.5)),
                                  ),
                                  const SizedBox(width: 24),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Row(
                                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    entry.manifest.title,
                                                    style: IDPTypography.titleMd.copyWith(color: IDPColors.onSurface),
                                                    maxLines: 1,
                                                    overflow: TextOverflow.ellipsis,
                                                  ),
                                                  const SizedBox(height: 4),
                                                  Text(
                                                    '${_formatSize(entry.manifest.contentSizeBytes)} • v${entry.manifest.version}',
                                                    style: IDPTypography.caption.copyWith(color: IDPColors.onSurfaceVariant),
                                                  ),
                                                ],
                                              ),
                                            ),
                                            if (hasUpdate)
                                              Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                                decoration: BoxDecoration(
                                                  color: IDPColors.errorLight,
                                                  borderRadius: BorderRadius.circular(999),
                                                ),
                                                child: Row(
                                                  mainAxisSize: MainAxisSize.min,
                                                  children: [
                                                    Icon(Icons.new_releases, color: IDPColors.error, size: 14),
                                                    const SizedBox(width: 4),
                                                    Text('UPDATE', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: IDPColors.error)),
                                                  ],
                                                ),
                                              )
                                            else
                                              const Icon(Icons.check_circle, color: IDPColors.secondary, size: 24),
                                          ],
                                        ),
                                        const Spacer(),
                                        Row(
                                          children: [
                                            if (hasUpdate)
                                              TextButton.icon(
                                                onPressed: _installing ? null : () {
                                                  // Find the remote pack and install
                                                  final remote = _syncPlan?.entries.firstWhere((e) => e.installed?.packId == entry.manifest.packId).remote;
                                                  if (remote != null) {
                                                    setState(() {
                                                      _urlController.text = remote.archiveUrl.toString();
                                                    });
                                                    _installFromUrl();
                                                  }
                                                },
                                                icon: const Icon(Icons.download_for_offline, size: 18),
                                                label: const Text('Update'),
                                                style: TextButton.styleFrom(
                                                  foregroundColor: IDPColors.primary,
                                                  textStyle: IDPTypography.labelMd,
                                                  padding: EdgeInsets.zero,
                                                  minimumSize: Size.zero,
                                                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                                ),
                                              )
                                            else
                                              TextButton.icon(
                                                onPressed: () {},
                                                icon: const Icon(Icons.play_lesson, size: 18),
                                                label: const Text('Open Course'),
                                                style: TextButton.styleFrom(
                                                  foregroundColor: IDPColors.primary,
                                                  textStyle: IDPTypography.labelMd,
                                                  padding: EdgeInsets.zero,
                                                  minimumSize: Size.zero,
                                                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                                ),
                                              ),
                                            const SizedBox(width: 24),
                                            TextButton.icon(
                                              onPressed: _installing ? null : () => _removePack(entry),
                                              icon: const Icon(Icons.delete_outline, size: 18),
                                              label: const Text('Remove'),
                                              style: TextButton.styleFrom(
                                                foregroundColor: IDPColors.onSurfaceVariant,
                                                textStyle: IDPTypography.labelMd,
                                                padding: EdgeInsets.zero,
                                                minimumSize: Size.zero,
                                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        );
                      }
                    ),
                    
                  const SizedBox(height: 48),
                  
                  // Available Packs Section
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Available Packs', style: IDPTypography.headlineLgMobile.copyWith(color: IDPColors.onSurface)),
                    ],
                  ),
                  const SizedBox(height: 24),
                  if (_syncPlan == null || _syncPlan!.entries.where((e) => !e.isInstalled).isEmpty)
                    Container(
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.7),
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(color: Colors.white.withValues(alpha: 0.3)),
                      ),
                      child: Center(
                        child: Text(
                          _syncPlan == null ? 'Sync to check for available packs.' : 'No new packs available.',
                          style: IDPTypography.bodyMd.copyWith(color: IDPColors.onSurfaceVariant),
                        ),
                      ),
                    )
                  else
                    ListView.separated(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: _syncPlan!.entries.where((e) => !e.isInstalled).length,
                      separatorBuilder: (context, index) => const SizedBox(height: 16),
                      itemBuilder: (context, index) {
                        final availableEntries = _syncPlan!.entries.where((e) => !e.isInstalled).toList();
                        final entry = availableEntries[index].remote;
                        return Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: IDPColors.surfaceContainerLowest,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: Colors.transparent),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 64,
                                height: 64,
                                decoration: BoxDecoration(
                                  color: IDPColors.primaryContainer.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Icon(Icons.menu_book, size: 32, color: IDPColors.primary),
                              ),
                              const SizedBox(width: 24),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(entry.title, style: IDPTypography.labelMd.copyWith(color: IDPColors.onSurface)),
                                    const SizedBox(height: 4),
                                    Text('${entry.subject} • Grades ${entry.gradeMin}-${entry.gradeMax}', style: IDPTypography.caption.copyWith(color: IDPColors.onSurfaceVariant)),
                                  ],
                                ),
                              ),
                              OutlinedButton.icon(
                                onPressed: _installing ? null : () {
                                  setState(() {
                                    _urlController.text = entry.archiveUrl.toString();
                                  });
                                  _installFromUrl();
                                },
                                style: OutlinedButton.styleFrom(
                                  side: const BorderSide(color: IDPColors.primary, width: 2),
                                  foregroundColor: IDPColors.primary,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
                                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                ),
                                icon: const Icon(Icons.download, size: 18),
                                label: const Text('Get Pack'),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                ],
              ),
            ),
    );
  }

  void _showAdvancedSettingsDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Advanced Settings'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Raspberry Pi Catalog URL', style: IDPTypography.labelMd),
              const SizedBox(height: 8),
              TextField(
                controller: _catalogUrlController,
                decoration: const InputDecoration(border: OutlineInputBorder()),
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton(
                    onPressed: _discoverCatalogServers,
                    child: const Text('Auto-Discover'),
                  ),
                  OutlinedButton(
                    onPressed: _checkRaspberryCatalog,
                    child: const Text('Check RP Catalog'),
                  ),
                  OutlinedButton(
                    onPressed: _checkBackendCatalog,
                    child: const Text('Check Cloud API'),
                  ),
                  OutlinedButton(
                    onPressed: _runHotspotHealthCheck,
                    child: const Text('Health Check'),
                  ),
                  OutlinedButton(
                    onPressed: _installFromFile,
                    child: const Text('Install from File'),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text('Manual Install URL', style: IDPTypography.labelMd),
              const SizedBox(height: 8),
              TextField(
                controller: _urlController,
                decoration: const InputDecoration(border: OutlineInputBorder()),
              ),
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: () {
                  Navigator.pop(context);
                  _installFromUrl();
                },
                child: const Text('Install from URL'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }
}

String _formatSize(int sizeBytes) {
  if (sizeBytes <= 0) {
    return '0 B';
  }
  final kb = sizeBytes / 1024;
  if (kb < 1024) {
    return '${kb.toStringAsFixed(1)} KB';
  }
  final mb = kb / 1024;
  if (mb < 1024) {
    return '${mb.toStringAsFixed(1)} MB';
  }
  final gb = mb / 1024;
  return '${gb.toStringAsFixed(2)} GB';
}

String _formatDurationSeconds(int seconds) {
  if (seconds <= 0) {
    return '0s';
  }
  final hours = seconds ~/ 3600;
  final minutes = (seconds % 3600) ~/ 60;
  final secs = seconds % 60;
  if (hours > 0) {
    return '${hours}h ${minutes}m';
  }
  if (minutes > 0) {
    return '${minutes}m ${secs}s';
  }
  return '${secs}s';
}
