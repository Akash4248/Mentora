import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:multicast_dns/multicast_dns.dart';
import 'package:network_info_plus/network_info_plus.dart';

import '../../../config/app_environment.dart';
import '../../network/data/backend_api_service.dart';
import '../../network/domain/runtime_backend_url.dart';
import '../domain/content_pack_models.dart';
import 'content_pack_policy_service.dart';

class RemoteContentPack {
  const RemoteContentPack({
    required this.packId,
    required this.title,
    required this.medium,
    required this.subject,
    this.chapter,
    required this.gradeMin,
    required this.gradeMax,
    required this.version,
    required this.archiveUrl,
  });

  final String packId;
  final String title;
  final String medium;
  final String subject;
  final String? chapter;
  final int gradeMin;
  final int gradeMax;
  final int version;
  final Uri archiveUrl;

  factory RemoteContentPack.fromMap(
    Map<String, dynamic> map, {
    required Uri catalogUri,
  }) {
    // Support both camelCase and snake_case keys from different backends
    final packId = (map['packId'] as String?
            ?? map['pack_id'] as String?
            ?? '')
        .trim();
    if (packId.isEmpty) {
      throw FormatException('Catalog pack entry missing packId/pack_id');
    }

    final rawArchive =
        (map['archiveUrl'] as String?
            ?? map['archive_url'] as String?
            ?? map['download_url'] as String?
            ?? '')
            .trim();
    if (rawArchive.isEmpty) {
      throw FormatException(
        'Catalog pack entry missing archiveUrl for $packId',
      );
    }

    final archiveUri = Uri.parse(rawArchive);

    // Parse version: can be int (1) or string ("1.0.0")
    int parsedVersion = 1;
    final rawVersion = map['version'];
    if (rawVersion is int) {
      parsedVersion = rawVersion;
    } else if (rawVersion is String) {
      final parts = rawVersion.split('.');
      if (parts.isNotEmpty) {
        parsedVersion = int.tryParse(parts.first) ?? 1;
      }
    }

    return RemoteContentPack(
      packId: packId,
      title: (map['title'] as String? ?? packId).trim(),
      medium: (map['medium'] as String? ?? 'Mixed').trim(),
      subject: (map['subject'] as String? ?? 'All Subjects').trim(),
      chapter: map['chapter'] as String?,
      gradeMin: int.tryParse(map['grade']?.toString() ?? '') ?? map['gradeMin'] as int? ?? map['grade_min'] as int? ?? 1,
      gradeMax: int.tryParse(map['grade']?.toString() ?? '') ?? map['gradeMax'] as int? ?? map['grade_max'] as int? ?? 12,
      version: parsedVersion,
      archiveUrl: archiveUri.hasScheme
          ? archiveUri
          : catalogUri.resolveUri(archiveUri),
    );
  }
}

class ContentPackCatalogSnapshot {
  const ContentPackCatalogSnapshot({
    required this.catalogUri,
    required this.fetchedAt,
    required this.packs,
  });

  final Uri catalogUri;
  final int fetchedAt;
  final List<RemoteContentPack> packs;
}

class RemotePackSyncEntry {
  const RemotePackSyncEntry({
    required this.remote,
    required this.installed,
    required this.matchesMandatoryRule,
  });

  final RemoteContentPack remote;
  final ContentPackManifest? installed;
  final bool matchesMandatoryRule;

  bool get isInstalled => installed != null;

  bool get hasUpdate =>
      installed != null && remote.version > installed!.version;
}

class ContentPackSyncPlan {
  const ContentPackSyncPlan({
    required this.snapshot,
    required this.entries,
    required this.missingRequiredRules,
    required this.requiredInstallQueue,
  });

  final ContentPackCatalogSnapshot snapshot;
  final List<RemotePackSyncEntry> entries;
  final List<RequiredContentPackRule> missingRequiredRules;
  final List<RemoteContentPack> requiredInstallQueue;

  int get availableCount => entries.length;

  int get updatableCount => entries.where((entry) => entry.hasUpdate).length;

  int get missingRequiredCount => missingRequiredRules.length;
}

class GatewayHealthStatus {
  const GatewayHealthStatus({
    required this.host,
    required this.port,
    required this.tcpReachable,
    required this.catalogReachable,
    this.pingMs,
  });

  final String host;
  final int port;
  final bool tcpReachable;
  final bool catalogReachable;
  final int? pingMs;
}

class HotspotHealthReport {
  const HotspotHealthReport({
    required this.connectedSsid,
    required this.gatewayStatuses,
    required this.selectedCatalogReachable,
    required this.remainingBytes,
    required this.estimatedSeconds,
  });

  final String connectedSsid;
  final List<GatewayHealthStatus> gatewayStatuses;
  final bool selectedCatalogReachable;
  final int remainingBytes;
  final int estimatedSeconds;
}

class ContentPackSyncService {
  const ContentPackSyncService({ContentPackPolicyService? policyService})
    : _policyService = policyService ?? const ContentPackPolicyService();

  final ContentPackPolicyService _policyService;

  Future<List<String>> discoverCatalogUrls({
    List<String>? preferredHosts,
    List<int>? preferredPorts,
    List<String>? serviceTypes,
  }) async {
    AppEnvironment.log('SYNC', 'Discovering content catalog URLs');

    final hosts = <String>[
      ...(preferredHosts ??
          const <String>[
            'school-content.local',
            'schoolcontent.local',
            'raspberrypi.local',
            '192.168.50.1',
            '192.168.1.10',
            '192.168.0.10',
          ]),
    ];
    final ports = preferredPorts ?? const <int>[8080, 8000, 5000];
    final mdnsServiceTypes =
        serviceTypes ??
        const <String>['_schoolcontent._tcp.local', '_http._tcp.local'];

    final discovered = <String>{};

    // Add configured content pipeline URL as primary source
    try {
      final configuredUrl = AppEnvironment.contentPipelineUrl;
      if (configuredUrl.isNotEmpty) {
        final catalogUrl = '$configuredUrl/catalog.json';
        discovered.add(catalogUrl);
        AppEnvironment.log('SYNC', 'Added configured catalog: $catalogUrl');
      }
    } catch (e) {
      AppEnvironment.log('SYNC', 'Failed to add configured catalog URL: $e');
    }

    // Probe hotspot/LAN gateway candidates first.
    final inferredHosts = await _inferGatewayHosts();
    hosts.addAll(inferredHosts);

    // mDNS can fail on some Android runtimes due to socket reusePort limitations.
    if (!Platform.isAndroid) {
      final mdnsClient = MDnsClient();
      try {
        await mdnsClient.start();
        for (final serviceType in mdnsServiceTypes) {
          final ptrs = await _collectWithin<PtrResourceRecord>(
            mdnsClient.lookup<PtrResourceRecord>(
              ResourceRecordQuery.serverPointer(serviceType),
            ),
            const Duration(milliseconds: 1800),
          );

          for (final ptr in ptrs) {
            final services = await _collectWithin<SrvResourceRecord>(
              mdnsClient.lookup<SrvResourceRecord>(
                ResourceRecordQuery.service(ptr.domainName),
              ),
              const Duration(milliseconds: 1200),
            );

            for (final service in services) {
              final aRecords = await _collectWithin<IPAddressResourceRecord>(
                mdnsClient.lookup<IPAddressResourceRecord>(
                  ResourceRecordQuery.addressIPv4(service.target),
                ),
                const Duration(milliseconds: 800),
              );

              for (final address in aRecords) {
                discovered.add(
                  'http://${address.address.address}:${service.port}/catalog.json',
                );
              }

              discovered.add(
                'http://${service.target}:${service.port}/catalog.json',
              );
            }
          }
        }
      } catch (_) {
        // Ignore mDNS failures and continue with host probing fallback.
      } finally {
        mdnsClient.stop();
      }
    }

    final client = HttpClient();
    client.connectionTimeout = const Duration(milliseconds: 800);

    try {
      final reachable = <String>{...discovered};
      for (final host in hosts) {
        for (final port in ports) {
          final uri = Uri.parse('http://$host:$port/catalog.json');
          final isReachable = await _isCatalogReachable(client, uri);
          if (isReachable) {
            reachable.add(uri.toString());
          }
        }
      }

      final subnetMatches = await _scanSurroundingSubnetCatalogs(client, ports);
      reachable.addAll(subnetMatches);

      final sorted = reachable.toList()..sort();
      return sorted;
    } finally {
      client.close(force: true);
    }
  }

  Future<ContentPackCatalogSnapshot> fetchCatalog(String catalogUrl) async {
    final uri = Uri.parse(catalogUrl.trim());
    if (!uri.hasScheme || (uri.scheme != 'http' && uri.scheme != 'https')) {
      throw const FormatException('Catalog URL must use http or https.');
    }

    AppEnvironment.log('SYNC', 'Fetching catalog from: $catalogUrl');

    final client = HttpClient();
    try {
      final request = await client.getUrl(uri);
      final response = await request.close();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        AppEnvironment.log(
          'SYNC',
          'Catalog fetch failed with HTTP ${response.statusCode}',
        );
        throw HttpException(
          'Catalog fetch failed with HTTP ${response.statusCode}',
          uri: uri,
        );
      }

      final raw = await utf8.decodeStream(response);
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      final list = decoded['packs'] as List<dynamic>?;
      if (list == null) {
        throw const FormatException(
          'Catalog JSON must include a packs[] array.',
        );
      }

      // Keep only the highest version for each pack id.
      final byId = <String, RemoteContentPack>{};
      for (final item in list) {
        if (item is! Map<String, dynamic>) {
          continue;
        }
        final remote = RemoteContentPack.fromMap(item, catalogUri: uri);
        final existing = byId[remote.packId];
        if (existing == null || remote.version > existing.version) {
          byId[remote.packId] = remote;
        }
      }

      final packs = byId.values.toList()
        ..sort(
          (a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()),
        );

      AppEnvironment.log(
        'SYNC',
        'Catalog fetched successfully: ${packs.length} packs',
      );

      return ContentPackCatalogSnapshot(
        catalogUri: uri,
        fetchedAt: DateTime.now().millisecondsSinceEpoch,
        packs: packs,
      );
    } finally {
      client.close(force: true);
    }
  }

  Future<ContentPackCatalogSnapshot> fetchCatalogFromBackend(
    BackendApiService backendService,
  ) async {
    AppEnvironment.log('SYNC', 'Fetching catalog from backend API');
    final response = await backendService.listPacks();
    if (response.isFailure) {
      throw HttpException(
        'Failed to fetch packs from backend: ${response.message}',
      );
    }

    final rawPacks = response.data ?? <dynamic>[];
    final byId = <String, RemoteContentPack>{};

    final catalogUri = Uri.parse('${RuntimeBackendUrl().current}/packs');

    for (final item in rawPacks) {
      if (item is! Map<String, dynamic>) continue;

      if (item.containsKey('download_url') &&
          !item.containsKey('archive_url') &&
          !item.containsKey('archiveUrl')) {
        item['archive_url'] = item['download_url'];
      }
      if (!item.containsKey('archive_url') && item.containsKey('pack_id')) {
        item['archive_url'] =
            '${RuntimeBackendUrl().current}/packs/${item['pack_id']}/download';
      }

      try {
        final remote = RemoteContentPack.fromMap(item, catalogUri: catalogUri);
        final existing = byId[remote.packId];
        if (existing == null || remote.version > existing.version) {
          byId[remote.packId] = remote;
        }
      } catch (_) {
        // Skip malformed entries
      }
    }

    final packs = byId.values.toList()
      ..sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));

    AppEnvironment.log(
      'SYNC',
      'Backend catalog fetched successfully: ${packs.length} packs',
    );

    return ContentPackCatalogSnapshot(
      catalogUri: catalogUri,
      fetchedAt: DateTime.now().millisecondsSinceEpoch,
      packs: packs,
    );
  }

  Future<bool> isCatalogUrlReachable(String catalogUrl) async {
    Uri? uri;
    try {
      uri = Uri.parse(catalogUrl.trim());
    } catch (_) {
      AppEnvironment.log('SYNC', 'Failed to parse catalog URL: $catalogUrl');
      return false;
    }
    if (!uri.hasScheme || (uri.scheme != 'http' && uri.scheme != 'https')) {
      AppEnvironment.log('SYNC', 'Invalid catalog URL scheme: $catalogUrl');
      return false;
    }

    AppEnvironment.log('SYNC', 'Checking if catalog is reachable: $catalogUrl');

    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 2);
    try {
      final isReachable = await _isCatalogReachable(client, uri);
      if (isReachable) {
        AppEnvironment.log('SYNC', 'Catalog is reachable');
      } else {
        AppEnvironment.log('SYNC', 'Catalog is not reachable');
      }
      return isReachable;
    } finally {
      client.close(force: true);
    }
  }

  Future<HotspotHealthReport> runHotspotHealthCheck({
    required String catalogUrl,
    required List<RemoteContentPack> remainingQueue,
  }) async {
    final parsedCatalog = Uri.parse(catalogUrl.trim());
    final catalogPort = parsedCatalog.hasPort ? parsedCatalog.port : 8080;

    final ssid = await _readConnectedSsid();
    final hosts = <String>{
      if (parsedCatalog.host.isNotEmpty) parsedCatalog.host,
      ...await _inferGatewayHosts(),
    };

    final statuses = <GatewayHealthStatus>[];
    for (final host in hosts.take(24)) {
      final status = await _checkGatewayHost(host, catalogPort);
      statuses.add(status);
    }
    statuses.sort((a, b) {
      if (a.catalogReachable != b.catalogReachable) {
        return a.catalogReachable ? -1 : 1;
      }
      final ap = a.pingMs ?? 99999;
      final bp = b.pingMs ?? 99999;
      return ap.compareTo(bp);
    });

    final selectedClient = HttpClient();
    selectedClient.connectionTimeout = const Duration(seconds: 2);
    final selectedReachable = await _isCatalogReachable(
      selectedClient,
      parsedCatalog,
    );
    selectedClient.close(force: true);
    final remainingBytes = await _sumRemainingBytes(remainingQueue);
    final estimatedSeconds = _estimateSeconds(remainingBytes, statuses);

    return HotspotHealthReport(
      connectedSsid: ssid,
      gatewayStatuses: statuses,
      selectedCatalogReachable: selectedReachable,
      remainingBytes: remainingBytes,
      estimatedSeconds: estimatedSeconds,
    );
  }

  ContentPackSyncPlan buildPlan({
    required ContentPackCatalogSnapshot snapshot,
    required List<ContentPackManifest> installedPacks,
  }) {
    final installedById = <String, ContentPackManifest>{
      for (final pack in installedPacks) pack.packId: pack,
    };

    final readiness = _policyService.evaluate(installedPacks: installedPacks);
    final mandatoryRules = _policyService.defaultSchoolRules
        .where((rule) => rule.mandatory)
        .toList(growable: false);

    final entries = snapshot.packs
        .map(
          (remote) => RemotePackSyncEntry(
            remote: remote,
            installed: installedById[remote.packId],
            matchesMandatoryRule: mandatoryRules.any(
              (rule) => _matchesRule(remote, rule),
            ),
          ),
        )
        .toList(growable: false);

    final missingRules = readiness.missingRequiredStatuses
        .map((status) => status.rule)
        .toList(growable: false);

    final queue = <RemoteContentPack>[];
    final queuedIds = <String>{};

    for (final entry in entries) {
      if (!entry.matchesMandatoryRule) {
        continue;
      }
      if (entry.isInstalled && !entry.hasUpdate) {
        continue;
      }
      if (queuedIds.add(entry.remote.packId)) {
        queue.add(entry.remote);
      }
    }

    return ContentPackSyncPlan(
      snapshot: snapshot,
      entries: entries,
      missingRequiredRules: missingRules,
      requiredInstallQueue: queue,
    );
  }

  bool _matchesRule(RemoteContentPack pack, RequiredContentPackRule rule) {
    final packSubject = _normalizeSubject(pack.subject);
    final ruleSubject = _normalizeSubject(rule.subject);
    final subjectMatch =
        packSubject == 'all subjects' || packSubject == ruleSubject;

    final packMedium = pack.medium.trim().toLowerCase();
    final ruleMedium = rule.medium.trim().toLowerCase();
    final mediumMatch = packMedium == 'mixed' || packMedium == ruleMedium;

    final gradeMatch =
        !(pack.gradeMax < rule.gradeMin || pack.gradeMin > rule.gradeMax);

    return subjectMatch &&
        mediumMatch &&
        gradeMatch &&
        pack.version >= rule.minVersion;
  }

  String _normalizeSubject(String subject) {
    final lower = subject.trim().toLowerCase().replaceAll('_', ' ');
    if (lower == 'maths' || lower == 'mathematics') {
      return 'maths';
    }
    if (lower == 'science') {
      return 'science';
    }
    if (lower == 'english') {
      return 'english';
    }
    if (lower == 'kannada') {
      return 'kannada';
    }
    if (lower == 'social science' || lower == 'socialscience') {
      return 'social science';
    }
    if (lower == 'all subjects') {
      return 'all subjects';
    }
    return lower;
  }

  Future<bool> _isCatalogReachable(HttpClient client, Uri uri) async {
    try {
      final request = await client.getUrl(uri);
      final response = await request.close();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return false;
      }
      final body = await utf8.decodeStream(response);
      final decoded = jsonDecode(body);
      return decoded is Map<String, dynamic> &&
          decoded['packs'] is List<dynamic>;
    } catch (_) {
      return false;
    }
  }

  Future<String> _readConnectedSsid() async {
    try {
      final info = NetworkInfo();
      final raw = await info.getWifiName();
      if (raw == null || raw.trim().isEmpty) {
        return 'Unavailable';
      }
      return raw.replaceAll('"', '').trim();
    } catch (_) {
      return 'Unavailable';
    }
  }

  Future<List<String>> _inferGatewayHosts() async {
    final hosts = <String>{'192.168.50.1'};
    try {
      final interfaces = await NetworkInterface.list(
        includeLoopback: false,
        type: InternetAddressType.IPv4,
      );
      for (final iface in interfaces) {
        for (final address in iface.addresses) {
          final ip = address.address;
          if (!_isPrivateIpv4(ip)) {
            continue;
          }
          final parts = ip.split('.');
          if (parts.length != 4) {
            continue;
          }
          final prefix = '${parts[0]}.${parts[1]}.${parts[2]}';
          hosts.add('$prefix.1');
          hosts.add('$prefix.254');
          hosts.add('$prefix.10');
        }
      }
    } catch (_) {
      // Ignore and keep fallback gateway list.
    }
    return hosts.toList()..sort();
  }

  Future<List<String>> _scanSurroundingSubnetCatalogs(
    HttpClient client,
    List<int> ports,
  ) async {
    final prefixes = <String>{};
    try {
      final interfaces = await NetworkInterface.list(
        includeLoopback: false,
        type: InternetAddressType.IPv4,
      );
      for (final iface in interfaces) {
        for (final address in iface.addresses) {
          final ip = address.address;
          if (!_isPrivateIpv4(ip)) {
            continue;
          }
          final parts = ip.split('.');
          if (parts.length != 4) {
            continue;
          }
          prefixes.add('${parts[0]}.${parts[1]}.${parts[2]}');
        }
      }
    } catch (_) {
      return const <String>[];
    }

    if (prefixes.isEmpty) {
      return const <String>[];
    }

    final found = <String>{};
    final priorityOctets = <int>[
      1,
      10,
      20,
      30,
      40,
      50,
      100,
      150,
      193,
      200,
      220,
      254,
    ];

    Future<void> probe(String prefix, int port, int octet) async {
      if (octet < 1 || octet > 254) {
        return;
      }
      final uri = Uri.parse('http://$prefix.$octet:$port/catalog.json');
      final ok = await _isCatalogReachable(client, uri);
      if (ok) {
        found.add(uri.toString());
      }
    }

    for (final prefix in prefixes) {
      for (final port in ports) {
        // Fast lane for common gateway/server IPs.
        for (final octet in priorityOctets) {
          await probe(prefix, port, octet);
        }

        // If fast lane missed, sample the subnet at 8-IP intervals.
        if (!found.any((url) => url.contains('$prefix.'))) {
          final sampleOctets = <int>[];
          for (var octet = 2; octet <= 254; octet += 8) {
            sampleOctets.add(octet);
          }
          for (var i = 0; i < sampleOctets.length; i += 24) {
            final chunk = sampleOctets.sublist(
              i,
              (i + 24) > sampleOctets.length ? sampleOctets.length : (i + 24),
            );
            await Future.wait(chunk.map((octet) => probe(prefix, port, octet)));
          }
        }
      }
    }

    return found.toList()..sort();
  }

  bool _isPrivateIpv4(String ip) {
    final parts = ip.split('.');
    if (parts.length != 4) {
      return false;
    }
    final a = int.tryParse(parts[0]) ?? -1;
    final b = int.tryParse(parts[1]) ?? -1;
    if (a == 10) {
      return true;
    }
    if (a == 172 && b >= 16 && b <= 31) {
      return true;
    }
    if (a == 192 && b == 168) {
      return true;
    }
    return false;
  }

  Future<GatewayHealthStatus> _checkGatewayHost(String host, int port) async {
    final sw = Stopwatch()..start();
    var tcpReachable = false;
    try {
      final socket = await Socket.connect(
        host,
        port,
        timeout: const Duration(milliseconds: 900),
      );
      socket.destroy();
      tcpReachable = true;
    } catch (_) {
      tcpReachable = false;
    }
    sw.stop();
    final pingMs = tcpReachable ? sw.elapsedMilliseconds : null;

    final client = HttpClient();
    client.connectionTimeout = const Duration(milliseconds: 900);
    final catalogUri = Uri.parse('http://$host:$port/catalog.json');
    final catalogReachable = await _isCatalogReachable(client, catalogUri);
    client.close(force: true);

    return GatewayHealthStatus(
      host: host,
      port: port,
      tcpReachable: tcpReachable,
      catalogReachable: catalogReachable,
      pingMs: pingMs,
    );
  }

  Future<int> _sumRemainingBytes(List<RemoteContentPack> queue) async {
    var total = 0;
    for (final pack in queue) {
      final size = await _readContentLength(pack.archiveUrl);
      if (size > 0) {
        total += size;
      }
    }
    return total;
  }

  Future<int> _readContentLength(Uri uri) async {
    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 2);
    try {
      final req = await client.headUrl(uri);
      final res = await req.close();
      final header = res.headers.value(HttpHeaders.contentLengthHeader);
      return int.tryParse(header ?? '') ?? -1;
    } catch (_) {
      return -1;
    } finally {
      client.close(force: true);
    }
  }

  int _estimateSeconds(int remainingBytes, List<GatewayHealthStatus> statuses) {
    if (remainingBytes <= 0) {
      return 0;
    }

    final bestPing = statuses
        .where((s) => s.catalogReachable && s.pingMs != null)
        .map((s) => s.pingMs!)
        .fold<int?>(null, (best, v) => best == null || v < best ? v : best);

    int bytesPerSecond;
    if (bestPing == null) {
      bytesPerSecond = 3 * 1024 * 1024;
    } else if (bestPing <= 20) {
      bytesPerSecond = 12 * 1024 * 1024;
    } else if (bestPing <= 60) {
      bytesPerSecond = 7 * 1024 * 1024;
    } else {
      bytesPerSecond = 3 * 1024 * 1024;
    }

    return (remainingBytes / bytesPerSecond).ceil();
  }

  Future<List<T>> _collectWithin<T>(Stream<T> stream, Duration timeout) async {
    final records = <T>[];
    final done = Completer<void>();

    late final StreamSubscription<T> sub;
    sub = stream.listen(
      records.add,
      onError: (_) {
        if (!done.isCompleted) {
          done.complete();
        }
      },
      onDone: () {
        if (!done.isCompleted) {
          done.complete();
        }
      },
      cancelOnError: false,
    );

    await Future.any<void>(<Future<void>>[
      done.future,
      Future<void>.delayed(timeout),
    ]);
    await sub.cancel();
    return records;
  }
}
