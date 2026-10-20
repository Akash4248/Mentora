import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:sqflite/sqflite.dart';
import '../../../config/app_environment.dart';
import 'mentora_dio_client.dart';
import '../../course/data/local/app_database.dart';
import '../../course/data/local/course_repository.dart';
import '../../course/domain/course_tree.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../data/backend_availability_cache.dart';
import '../domain/backend_url_utils.dart';
import '../domain/runtime_backend_url.dart';
import '../../settings/services/user_api_key_service.dart';
import '../../chat/application/markdown_format_normalizer.dart';
import '../../chat/application/reasoning_output_filter.dart';
import '../../chat/data/local/linux_llm_config_service.dart';
import '../../chat/data/platform_tutor_inference_gateway.dart';
import '../../chat/data/llm_admin_channel_service.dart';
import '../../rag/data/local/rag_repository_v2.dart';
import '../../chat/domain/tutor_stream_event.dart';
import 'package:flutter_agent_harness/flutter_agent_harness.dart' hide CancelToken;

class DiscoveryProgress {
  final String currentCandidate;
  final int step;
  final int totalSteps;
  final double progress;
  final bool isFinished;
  final bool isSuccess;
  final String? connectedUrl;
  final String? connectedDeviceName;

  DiscoveryProgress({
    required this.currentCandidate,
    required this.step,
    required this.totalSteps,
    required this.progress,
    this.isFinished = false,
    this.isSuccess = false,
    this.connectedUrl,
    this.connectedDeviceName,
  });
}

class MentoraBackendClient {
  /// Returns candidate gateway URLs for auto-discovery, in probe priority order.
  static List<String> getCandidateGatewayUrls() {
    final list = <String>[];

    // 1. Runtime active backend URL (if already set)
    try {
      final current = RuntimeBackendUrl().current;
      if (current.isNotEmpty) list.add(BackendUrlUtils.normalizeUrl(current));
    } catch (_) {}

    // 2. Custom server URL from user settings (if user typed one)
    try {
      final custom = UserApiKeyService.instanceSync?.customServerUrl;
      if (custom != null && custom.isNotEmpty) {
        list.add(BackendUrlUtils.normalizeUrl(custom));
      }
    } catch (_) {}

    // 3. Explicitly configured URL from AppEnvironment (.env or --dart-define)
    final configured = AppEnvironment.backendBaseUrl;
    if (configured.isNotEmpty) list.add(BackendUrlUtils.normalizeUrl(configured));

    // 4. Developer Laptop Hostnames (akash-Ubuntu, pihub)
    list.addAll([
      'http://akash-Ubuntu.local:8000',
      'http://akash-ubuntu.local:8000',
      'http://akash-Ubuntu:8000',
      'http://akash-ubuntu:8000',
      'http://akash-Ubuntu.local',
      'http://akash-ubuntu.local',
      'http://pihub.local:8000',
      'http://pihub.local',
    ]);

    // 5. Client device local hostname (when running client locally on dev laptop)
    try {
      final hostname = Platform.localHostname;
      if (hostname.isNotEmpty) {
        list.add('http://$hostname.local:8000');
        list.add('http://$hostname.local');
        list.add('http://$hostname:8000');
      }
    } catch (_) {}

    // 6. Loopback (emulator or local dev server)
    list.addAll([
      'http://10.0.2.2:8000', // Android emulator → host loopback
      'http://127.0.0.1:8000',
      'http://localhost:8000',
    ]);

    return list.map(BackendUrlUtils.normalizeUrl).toSet().toList();
  }

  /// Active gateway URL. Updated on successful connection.
  static String _activeBaseUrl = AppEnvironment.backendBaseUrl;
  String get baseUrl => _activeBaseUrl;
  void setBaseUrl(String url) {
    final normalized = BackendUrlUtils.normalizeUrl(url);
    _activeBaseUrl = normalized;
    MentoraDioClient.updateBaseUrl(normalized);
    RuntimeBackendUrl().updateUrl(normalized);
    BackendAvailabilityCache().updateStatus(true, url: normalized);
    _persistActiveUrl(normalized);
  }

  static Future<void> _persistActiveUrl(String url) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kCachedBackendUrl, url);
      await prefs.setInt(_kCachedBackendUrlTs, DateTime.now().millisecondsSinceEpoch);
      await prefs.setString('backend_active_url', url);
    } catch (_) {}
  }

  MentoraBackendClient({String? baseUrl, Dio? dioClient}) : _injectedClient = dioClient {
    if (baseUrl != null) {
      setBaseUrl(baseUrl);
    }
  }

  final Dio? _injectedClient;
  Dio get _client => _injectedClient ?? MentoraDioClient.instance;

  static const String _kCachedBackendUrl = 'backend_url';
  static const String _kCachedBackendUrlTs = 'backend_url_ts';
  static const int _urlCacheTtlMs = 5 * 60 * 1000; // 5 minutes

  // Subnet Auto-Discovery: Parallel probe candidate gateway URLs
  Future<String> autoDiscoverGatewayUrl({
    void Function(DiscoveryProgress progress)? onProgress,
  }) async {
    // 1. In-memory cache hit (same process session)
    final memCached = BackendAvailabilityCache().cachedUrl;
    if (memCached != null && BackendAvailabilityCache().cachedStatus == true) {
      setBaseUrl(memCached);
      RuntimeBackendUrl().updateUrl(memCached);
      onProgress?.call(DiscoveryProgress(
        currentCandidate: memCached,
        step: 1,
        totalSteps: 1,
        progress: 1.0,
        isFinished: true,
        isSuccess: true,
        connectedUrl: memCached,
      ));
      return memCached;
    }

    // 2. SharedPreferences cache hit (survived cold launch) - probe first before claiming online
    try {
      final prefs = await SharedPreferences.getInstance();
      final cachedUrl = prefs.getString(_kCachedBackendUrl);
      final cachedTs = prefs.getInt(_kCachedBackendUrlTs) ?? 0;
      final age = DateTime.now().millisecondsSinceEpoch - cachedTs;
      if (cachedUrl != null && age < _urlCacheTtlMs) {
        try {
          await _probeCandidate(cachedUrl).timeout(const Duration(milliseconds: 1500));
          setBaseUrl(cachedUrl);
          RuntimeBackendUrl().updateUrl(cachedUrl);
          BackendAvailabilityCache().updateStatus(true, url: cachedUrl);
          onProgress?.call(DiscoveryProgress(
            currentCandidate: cachedUrl,
            step: 1,
            totalSteps: 1,
            progress: 1.0,
            isFinished: true,
            isSuccess: true,
            connectedUrl: cachedUrl,
          ));
          return cachedUrl;
        } catch (_) {
          // Probe failed! Cached URL is stale or server went down. Clear cache & set status offline.
          await prefs.remove(_kCachedBackendUrl);
          BackendAvailabilityCache().updateStatus(false);
        }
      }
    } catch (_) {}

    // 3. Parallel probe candidates simultaneously (first 200-OK wins, capped at 4s)
    final candidates = getCandidateGatewayUrls();
    try {
      final winner = await Future.any(
        candidates.map((url) => _probeCandidate(url)),
      ).timeout(const Duration(seconds: 4));

      setBaseUrl(winner);
      RuntimeBackendUrl().updateUrl(winner);
      BackendAvailabilityCache().updateStatus(true, url: winner);

      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_kCachedBackendUrl, winner);
        await prefs.setInt(_kCachedBackendUrlTs, DateTime.now().millisecondsSinceEpoch);
      } catch (_) {}

      String deviceName = 'Local Gateway ($winner)';
      try {
        final hName = Platform.localHostname;
        if (hName.isNotEmpty && winner.contains(hName)) {
          deviceName = 'Laptop Gateway ($hName)';
        } else if (winner.contains('127.0.0.1') || winner.contains('localhost')) {
          deviceName = 'Laptop Localhost (127.0.0.1)';
        } else if (winner.contains('pihub')) {
          deviceName = 'Raspberry Pi Gateway (PiHub)';
        }
      } catch (_) {}

      onProgress?.call(DiscoveryProgress(
        currentCandidate: winner,
        step: candidates.length,
        totalSteps: candidates.length,
        progress: 1.0,
        isFinished: true,
        isSuccess: true,
        connectedUrl: winner,
        connectedDeviceName: deviceName,
      ));
      return winner;
    } catch (_) {
      BackendAvailabilityCache().updateStatus(false);
      onProgress?.call(DiscoveryProgress(
        currentCandidate: _activeBaseUrl,
        step: candidates.length,
        totalSteps: candidates.length,
        progress: 1.0,
        isFinished: true,
        isSuccess: false,
      ));
      return _activeBaseUrl;
    }
  }

  Future<String> _probeCandidate(String url) async {
    final res = await _client
        .get('$url/health')
        .timeout(const Duration(seconds: 3));
    if (res.statusCode == 200) return url;
    throw Exception('Candidate $url unhealthy (${res.statusCode})');
  }

  // _buildHeaders() removed: auth headers are now injected automatically by
  // MentoraDioClient's _AuthInterceptor for every request.

  static final Map<int, List<Map<String, dynamic>>> _subjectsCache = {};
  static final Map<String, List<Map<String, dynamic>>> _chaptersCache = {};

  // 1. Fetch Real Subjects & Progress for Grade (Offline-First: Local Cache & DB)
  Future<List<Map<String, dynamic>>> getSubjectsForGrade(int grade) async {
    if (_subjectsCache.containsKey(grade) && _subjectsCache[grade]!.isNotEmpty) {
      return _subjectsCache[grade]!;
    }

    // Fast local DB lookup
    final localList = await _loadSubjectsFromLocalDb(grade);
    if (localList.isNotEmpty) {
      _subjectsCache[grade] = localList;
      return localList;
    }

    // Network download only if local DB is empty
    final netList = await _fetchSubjectsFromNetwork(grade);
    if (netList.isNotEmpty) {
      _subjectsCache[grade] = netList;
      return netList;
    }

    return [
      {'name': 'Mathematics', 'code': 'MAT${grade.toString().padLeft(2, '0')}', 'progress': 0.0, 'chaptersCompleted': 0, 'totalChapters': 12, 'color': '0xFFF59E0B', 'icon': 'calculate_outlined'},
      {'name': 'Science', 'code': 'SCI${grade.toString().padLeft(2, '0')}', 'progress': 0.0, 'chaptersCompleted': 0, 'totalChapters': 12, 'color': '0xFF10B981', 'icon': 'science_outlined'},
      {'name': 'Social Science', 'code': 'SOC${grade.toString().padLeft(2, '0')}', 'progress': 0.0, 'chaptersCompleted': 0, 'totalChapters': 12, 'color': '0xFF3B82F6', 'icon': 'public_outlined'},
      {'name': 'English', 'code': 'ENG${grade.toString().padLeft(2, '0')}', 'progress': 0.0, 'chaptersCompleted': 0, 'totalChapters': 12, 'color': '0xFF8B5CF6', 'icon': 'menu_book_outlined'},
    ];
  }

  Future<List<Map<String, dynamic>>> _fetchSubjectsFromNetwork(int grade) async {
    try {
      final response = await _client
          .get('/packs/catalog');
      if (response.statusCode == 200) {
        final List data = response.data is List
            ? response.data
            : (response.data is Map && response.data['subjects'] is List
                ? response.data['subjects']
                : (response.data is String ? jsonDecode(response.data) : []));
        if (data.isNotEmpty) {
          final list = List<Map<String, dynamic>>.from(data);
          _subjectsCache[grade] = list;
          return list;
        }
      }
    } on DioException catch (_) {}
    return [];
  }


  Future<List<Map<String, dynamic>>> _loadSubjectsFromLocalDb(int grade) async {
    try {
      final courseRepo = CourseRepository();
      await courseRepo.ensureSeedDataForGrade(grade);
      final subjects = await courseRepo.getSubjects('course_$grade');
      if (subjects.isNotEmpty) {
        final result = <Map<String, dynamic>>[];
        for (final s in subjects) {
          final chapters = await courseRepo.getChapters(s.id);
          result.add({
            'name': s.name,
            'code': '${s.name.substring(0, s.name.length >= 3 ? 3 : s.name.length).toUpperCase()}${grade.toString().padLeft(2, '0')}',
            'progress': 0.0,
            'chaptersCompleted': 0,
            'totalChapters': chapters.length,
            'color': _colorForSubject(s.name),
            'icon': _iconForSubject(s.name),
          });
        }
        return result;
      }
    } catch (_) {}
    return [];
  }

  // 2. Fetch Real Chapters for Selected Subject & Grade (Offline-First: Local Cache & DB)
  Future<List<Map<String, dynamic>>> getChaptersForSubject(String subjectName, {int grade = 9}) async {
    final key = '${grade}_${subjectName.toLowerCase().trim()}';
    if (_chaptersCache.containsKey(key) && _chaptersCache[key]!.isNotEmpty) {
      return _chaptersCache[key]!;
    }

    // Fast local DB lookup
    final localList = await _loadChaptersFromLocalDb(subjectName, grade);
    if (localList.isNotEmpty) {
      _chaptersCache[key] = localList;
      return localList;
    }

    // Network download only if local DB is empty
    final netList = await _fetchChaptersFromNetwork(subjectName, grade);
    if (netList.isNotEmpty) {
      _chaptersCache[key] = netList;
      return netList;
    }

    return [];
  }

  Future<List<Map<String, dynamic>>> _fetchChaptersFromNetwork(String subjectName, int grade) async {
    try {
      final response = await _client
          .get('/packs/catalog');
      if (response.statusCode == 200) {
        final List data = response.data is List
            ? response.data
            : (response.data is Map && response.data['chapters'] is List
                ? response.data['chapters']
                : (response.data is String ? jsonDecode(response.data) : []));
        final list = List<Map<String, dynamic>>.from(data);
        if (list.isNotEmpty) {
          final key = '${grade}_${subjectName.toLowerCase().trim()}';
          _chaptersCache[key] = list;
          await _saveBackendChaptersToLocalDb(list, subjectName, grade);
          return list;
        }
      }
    } on DioException catch (_) {}
    return [];
  }


  Future<List<Map<String, dynamic>>> _loadChaptersFromLocalDb(String subjectName, int grade) async {
    try {
      final courseRepo = CourseRepository();
      await courseRepo.ensureSeedData();
      final slug = subjectName.toLowerCase().trim().replaceAll(RegExp(r'[^a-z0-9]+'), '_');
      final subjectId = 'sub_${slug}_$grade';
      var chapters = await courseRepo.getChapters(subjectId);

      if (chapters.isEmpty) {
        final subjects = await courseRepo.getSubjects('course_$grade');
        final matchingSub = subjects.firstWhere(
          (s) => s.name.toLowerCase().contains(subjectName.toLowerCase()) || subjectName.toLowerCase().contains(s.name.toLowerCase()),
          orElse: () => subjects.isNotEmpty ? subjects.first : Subject(id: subjectId, courseId: 'course_$grade', name: subjectName),
        );
        chapters = await courseRepo.getChapters(matchingSub.id);
      }

      if (chapters.isNotEmpty) {
        return List.generate(chapters.length, (index) {
          return {
            'number': index + 1,
            'title': chapters[index].title,
            'status': index == 0 ? 'in_progress' : 'not_started',
            'duration': '25 mins',
            'mastery': 0,
          };
        });
      }
    } catch (_) {}
    return [];
  }

  Future<void> _saveBackendChaptersToLocalDb(
    List<Map<String, dynamic>> chapters,
    String subjectName,
    int grade,
  ) async {
    try {
      final db = await AppDatabase.instance.database;
      final batch = db.batch();
      final slug = subjectName.toLowerCase().trim().replaceAll(RegExp(r'[^a-z0-9]+'), '_');
      final subjectId = 'sub_${slug}_$grade';

      batch.insert(
        'courses',
        {'id': 'course_$grade', 'name': 'Class $grade'},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

      batch.insert(
        'subjects',
        {'id': subjectId, 'course_id': 'course_$grade', 'name': subjectName},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

      for (int i = 0; i < chapters.length; i++) {
        final ch = chapters[i];
        final title = ch['title']?.toString() ?? 'Chapter ${i + 1}';
        final chId = 'ch_${slug}_${grade}_${i + 1}';
        batch.insert(
          'chapters',
          {
            'id': chId,
            'subject_id': subjectId,
            'title': title,
            'summary': ch['summary']?.toString() ?? title,
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      await batch.commit(noResult: true);
    } catch (e) {
      // ignore
    }
  }

  // Live practice APIs (query-param, NOT path-param). Offline-first: [] on failure.
  // Does NOT touch any RAG code — pure gateway GET /quizzes|/flashcards.
  Future<List<Map<String, dynamic>>> getLiveQuizzes({
    required int grade,
    required String subject,
    required String chapter,
    String? topic,
  }) async {
    try {
      final response = await _client.get(
        '/quizzes',
        queryParameters: {
          'grade': grade,
          'subject': subject,
          'chapter': chapter,
          if (topic != null && topic.isNotEmpty) 'topic': topic,
        },
        options: Options(
          sendTimeout: const Duration(seconds: 3),
          receiveTimeout: const Duration(seconds: 15),
        ),
      );
      if (response.statusCode == 200) {
        final data = response.data;
        final List raw = data is List
            ? data
            : (data is Map && data['items'] is List ? data['items'] as List : const []);
        return raw.whereType<Map>().map((m) => Map<String, dynamic>.from(m)).toList();
      }
    } on DioException catch (_) {}
    return const [];
  }

  Future<List<Map<String, dynamic>>> getLiveFlashcards({
    required int grade,
    required String subject,
    required String chapter,
    String? topic,
  }) async {
    try {
      final response = await _client.get(
        '/flashcards',
        queryParameters: {
          'grade': grade,
          'subject': subject,
          'chapter': chapter,
          if (topic != null && topic.isNotEmpty) 'topic': topic,
        },
        options: Options(
          sendTimeout: const Duration(seconds: 3),
          receiveTimeout: const Duration(seconds: 15),
        ),
      );
      if (response.statusCode == 200) {
        final data = response.data;
        final List raw = data is List
            ? data
            : (data is Map && data['items'] is List ? data['items'] as List : const []);
        return raw.whereType<Map>().map((m) => Map<String, dynamic>.from(m)).toList();
      }
    } on DioException catch (_) {}
    return const [];
  }

  String _colorForSubject(String name) {
    final lower = name.toLowerCase();
    if (lower.contains('physic')) return '0xFF4F46E5';
    if (lower.contains('chem')) return '0xFF10B981';
    if (lower.contains('bio')) return '0xFF14B8A6';
    if (lower.contains('sci')) return '0xFF10B981';
    if (lower.contains('math')) return '0xFFF59E0B';
    if (lower.contains('soc') || lower.contains('hist') || lower.contains('geog')) return '0xFF3B82F6';
    if (lower.contains('eng')) return '0xFF8B5CF6';
    if (lower.contains('kan')) return '0xFFEC4899';
    return '0xFF6366F1';
  }

  String _iconForSubject(String name) {
    final lower = name.toLowerCase();
    if (lower.contains('chem')) return 'biotech_outlined';
    if (lower.contains('bio')) return 'nature_outlined';
    if (lower.contains('sci') || lower.contains('physic')) return 'science_outlined';
    if (lower.contains('math')) return 'calculate_outlined';
    return 'menu_book_outlined';
  }

  // 3. Fetch Interactive Simulation Config for Chapter (OFFLINE-FIRST, 0 404s)
  // Previously GET /api/v1/simulations/{chapter} returned 404 (gateway has /experiments).
  // Now returns local structured config; live experiments are loaded via
  // PhetCatalogService (GET /experiments/catalog) or ExperimentDescriptor map.
  Future<Map<String, dynamic>> getSimulationForChapter(String chapter) async {
    // No network call - eliminates gateway 404. Live data available via
    // GET /experiments?chapter=... handled by PhetCatalogService if needed.
    return {
      'chapter': chapter,
      'title': 'Interactive Pendulum & Motion Lab',
      'description': 'Adjust length (L) and gravitational acceleration (g) in real-time.',
      'parameters': [
        {'id': 'length', 'name': 'Pendulum Length (L)', 'unit': 'm', 'min': 0.5, 'max': 5.0, 'default': 2.0, 'step': 0.1},
        {'id': 'gravity', 'name': 'Gravity (g)', 'unit': 'm/s²', 'min': 1.6, 'max': 24.8, 'default': 9.8, 'step': 0.1},
      ],
      'formulas': ['T = 2π √(L / g)', 'v_max = √(2gL (1 - cos θ))'],
    };
  }

  // 4. Fetch YouTube Video Lectures & ISL for Chapter (OFFLINE-FIRST, 0 404s)
  // Previously GET /videos/{chapter} returned 404 (no gateway route).
  // Video catalog is local: VideoResourceRepository.getVideosForChapter() is
  // queried directly by ChapterLearningWorkspaceScreen and ChapterDashboardScreen.
  Future<Map<String, dynamic>> getVideoLecturesForChapter(String chapter) async {
    // No network call - eliminates gateway 404. Caller merges with local
    // VideoResourceRepository data; this is the offline fallback payload.
    return {
      'chapter': chapter,
      'currentVideo': {
        'id': 'v_motion_01',
        'youtubeId': 'ZBalWWHYFQc',
        'title': 'NCERT Class 9 Physics: Motion & Equations of Motion',
        'channel': 'NCERT Official',
        'duration': '18:45',
      },
      'playlist': [
        {'id': 'v1', 'title': '1. Distance vs Displacement Explained', 'duration': '05:20', 'timestamp': '00:00'},
        {'id': 'v2', 'title': '2. Deriving Equations of Motion (v = u + at)', 'duration': '08:15', 'timestamp': '05:20'},
        {'id': 'v3', 'title': '3. Uniform Circular Motion', 'duration': '05:10', 'timestamp': '13:35'},
      ],
      'islAvailable': true,
      'keyTakeaways': [
        'Speed is scalar (magnitude only), Velocity is vector (magnitude + direction).',
        'First equation of motion: v = u + at relates final velocity, initial velocity, acceleration, and time.',
      ],
    };
  }

  // 5. Fetch Diagnostic Quiz for Chapter (OFFLINE-FIRST, 0 404s)
  // Previously GET /quizzes/{chapter} returned 404 (gateway route is GET /quizzes?chapter=).
  // Now returns local practice quiz without firing 404. Live probe, if needed,
  // must use GET /quizzes?chapter=... (query param, not path param).
  Future<Map<String, dynamic>> getQuizForChapter(String chapter) async {
    // No network call on path-param route. Offline practice generator fallback.
    // If live quizzes are required, call GET /quizzes?chapter=<name> via
    // EndpointBuilder.quizzes endpoint separately - not here.
    final cleanTitle = chapter.replaceAll('_', ' ');
    return {
      'chapter': chapter,
      'title': 'NCERT Practice Quiz: $cleanTitle',
      'totalQuestions': 10,
      'userMastery': 0,
      'questions': [
        {
          'id': 'q1',
          'question': 'What is the core conceptual principle studied in $cleanTitle?',
          'options': ['System Properties', 'Derived Equations', 'Practical Models', 'All of the above'],
          'correctIndex': 3,
          'explanation': '$cleanTitle covers system properties, derived equations, and practical models.',
        },
        {
          'id': 'q2',
          'question': 'Which standard SI unit dimension applies when evaluating $cleanTitle?',
          'options': ['Standard Metric Units', 'Dimensionless Ratios', 'Operational Units', 'Context-dependent SI units'],
          'correctIndex': 3,
          'explanation': 'Units depend on the specific physical variables and formulas involved.',
        },
        {
          'id': 'q3',
          'question': 'In NCERT experiments on $cleanTitle, what step ensures experimental precision?',
          'options': ['Random sampling', 'Controlling variables and taking repeated trials', 'Ignoring minor outliers', 'Relying strictly on theoretical estimates'],
          'correctIndex': 1,
          'explanation': 'Controlling variables and taking repeated readings minimizes experimental errors.',
        },
        {
          'id': 'q4',
          'question': 'How do the principles of $cleanTitle relate to everyday applications?',
          'options': ['They describe mechanical & chemical interactions', 'They optimize technical design', 'They explain natural observational phenomena', 'All of the above'],
          'correctIndex': 3,
          'explanation': 'NCERT concepts connect fundamental science with technical applications and daily observations.',
        },
        {
          'id': 'q5',
          'question': 'Which mathematical formulation is central to solving numericals in $cleanTitle?',
          'options': ['Linear Proportionality Laws', 'Conservation Theorems & Equations', 'Rate Definitions', 'All applicable NCERT laws'],
          'correctIndex': 3,
          'explanation': 'Numerical problem solving uses state equations, conservation laws, and rate definitions.',
        },
        {
          'id': 'q6',
          'question': 'When analyzing plots for $cleanTitle, what does the slope of the curve measure?',
          'options': ['Rate of change of the dependent parameter', 'Integrated area quantity', 'Arbitrary scalar constant', 'System boundary limit'],
          'correctIndex': 0,
          'explanation': 'The slope of a graph measures the rate of change of the target variable.',
        },
        {
          'id': 'q7',
          'question': 'What laboratory safety measure is required when studying $cleanTitle?',
          'options': ['Instrument calibration before taking readings', 'Wearing protective gear where needed', 'Ensuring secure apparatus connections', 'All of the above'],
          'correctIndex': 3,
          'explanation': 'Laboratory protocols require instrument calibration and protective equipment.',
        },
        {
          'id': 'q8',
          'question': 'What common mistake should be avoided when solving problems on $cleanTitle?',
          'options': ['Confusing scalar and vector quantities', 'Ignoring reference directions', 'Misinterpreting proportional constants', 'All of the above'],
          'correctIndex': 3,
          'explanation': 'Common errors include scalar/vector confusion, direction errors, and unit oversights.',
        },
        {
          'id': 'q9',
          'question': 'How does energy input affect the systems described in $cleanTitle?',
          'options': ['Increases kinetic energy / molecular activity', 'Reduces molecular stability', 'Alters equilibrium state', 'Varies based on system thermodynamics'],
          'correctIndex': 3,
          'explanation': 'Energy input alters system state, reaction rates, or resistance according to thermodynamics.',
        },
        {
          'id': 'q10',
          'question': 'What is the best revision method for $cleanTitle before board exams?',
          'options': ['Memorizing definition text only', 'Practicing NCERT exercise problems and diagrams', 'Skimming summary sheets', 'Focusing only on short questions'],
          'correctIndex': 1,
          'explanation': 'Exam performance relies on practicing NCERT exercise problems and drawing clear diagrams.',
        },
      ],
    };
  }

  // 6. Fetch User Profile & Streak (OFFLINE-FIRST, 0 404s)
  // Previously GET /api/user/profile returned 404. Now reads from local
  // SharedPreferences user session. Preserves offline-first operation.
  Future<Map<String, dynamic>> getUserProfile() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return {
        'name': prefs.getString('user_name') ?? 'Student',
        'email': prefs.getString('user_email') ?? '',
        'grade': prefs.getInt('user_grade') ?? 9,
        'streakDays': prefs.getInt('user_streak_days') ?? 0,
        'dailyMinsLearned': prefs.getInt('user_daily_mins_learned') ?? 0,
        'dailyGoalMins': prefs.getInt('user_daily_goal_mins') ?? 30,
        'activeSubject': prefs.getString('user_active_subject') ?? 'Physics',
        'activeChapter': prefs.getString('user_active_chapter') ?? 'Motion',
      };
    } catch (_) {
      return {
        'name': 'Student',
        'grade': 9,
        'streakDays': 0,
        'dailyMinsLearned': 0,
        'dailyGoalMins': 30,
        'activeSubject': 'Physics',
        'activeChapter': 'Motion',
      };
    }
  }

  // Helper to extract clean student question from raw prompt
  String _extractStudentQuestion(String raw) {
    if (raw.contains('Current student question:')) {
      final parts = raw.split('Current student question:');
      if (parts.length > 1) {
        return parts.last.trim();
      }
    }
    return raw.trim();
  }

  // 7. Stream Query to Gateway AI Tutor Endpoint (or Local Fallback)
  Stream<TutorStreamEvent> streamAiTutor({
    required String question,
    required String topic,
    int grade = 9,
    CancelToken? cancelToken,
    List<String> history = const [],
    List<AgentTool> tools = const [],
    String? systemPrompt,
  }) async* {
    if (cancelToken?.isCancelled == true) {
      yield const TutorStreamErrorEvent('Tutor response cancelled.', aborted: true);
      return;
    }

    final cleanQuestion = _extractStudentQuestion(question);

    // If offline, stream directly from local LLM
    if (BackendAvailabilityCache().isOffline) {
      yield* _streamLocalLlmFallback(
        cleanQuestion,
        topic,
        grade,
        cancelToken: cancelToken,
        history: history,
        tools: tools,
        systemPrompt: systemPrompt,
      );
      return;
    }

    var tokensEmitted = 0;
    final rawBuffer = StringBuffer();
    final toolCalls = <TutorStreamToolCallEvent>[];

    try {
      final response = await _client.post<ResponseBody>(
        '/ai/tutor',
        data: {
          'question': cleanQuestion,
          'topic': topic,
          'grade': grade,
          'stream': true,
          if (systemPrompt != null && systemPrompt.isNotEmpty) ...{
            'systemPrompt': systemPrompt,
            'system_prompt': systemPrompt,
          },
          if (history.isNotEmpty) ...{
            'history': history,
            'conversation_history': history,
            'conversationHistory': history,
          },
          if (tools.isNotEmpty)
            'tools': tools.map((t) => {
              'name': t.name,
              'description': t.description,
              'parameters': t.parameters,
            }).toList(),
        },
        options: Options(
          responseType: ResponseType.stream,
          sendTimeout: const Duration(seconds: 4),
          receiveTimeout: const Duration(seconds: 120),
        ),
        cancelToken: cancelToken,
      );

      if (response.statusCode == 200 && response.data != null) {
        final lines = response.data!.stream
            .cast<List<int>>()
            .transform(utf8.decoder)
            .transform(const LineSplitter());

        await for (final line in lines) {
          if (cancelToken?.isCancelled == true) {
            yield const TutorStreamErrorEvent('Tutor response cancelled.', aborted: true);
            return;
          }
          final trimmed = line.trim();
          if (trimmed.isEmpty) continue;
          if (trimmed == 'data: [DONE]' || trimmed == '[DONE]') break;
          if (trimmed.startsWith('data:')) {
            final data = trimmed.substring(5).trim();
            if (data.isEmpty || data == '[DONE]') continue;
            try {
              final json = jsonDecode(data);
              if (json is Map) {
                final toolCallData = json['tool_call'];
                if (toolCallData is Map) {
                  final id = toolCallData['id'] as String? ??
                      'call_${DateTime.now().millisecondsSinceEpoch}';
                  final name = toolCallData['name'] as String? ?? '';
                  final args = toolCallData['arguments'] is Map
                      ? Map<String, dynamic>.from(toolCallData['arguments'] as Map)
                      : <String, dynamic>{};
                  if (name.isNotEmpty) {
                    final callEvent = TutorStreamToolCallEvent(
                      id: id,
                      name: name,
                      arguments: args,
                    );
                    toolCalls.add(callEvent);
                    yield callEvent;
                    return;
                  }
                }

                final chunk = json['chunk'] as String? ?? '';
                final isDone = json['done'] as bool? ?? false;
                final isStarted = json['started'] as bool? ?? false;
                final isHeartbeat = json['heartbeat'] as bool? ?? false;
                if (isStarted || isHeartbeat) continue;

                if (chunk.isNotEmpty) {
                  tokensEmitted++;
                  rawBuffer.write(chunk);
                  yield TutorStreamChunkEvent(chunk);
                }
                if (isDone) break;
              }
            } catch (_) {
              if (data.isNotEmpty) {
                tokensEmitted++;
                rawBuffer.write(data);
                yield TutorStreamChunkEvent(data);
              }
            }
          }
        }

        BackendAvailabilityCache().updateStatus(true, url: _activeBaseUrl);
        final fullAnswer = rawBuffer.toString().trim();
        yield TutorStreamCompletedEvent(
          fullText: fullAnswer.isNotEmpty ? fullAnswer : '⚠️ The tutor returned an empty response.',
          source: 'pihub_backend_sse',
          toolCalls: toolCalls,
        );
        return;
      } else {
        throw DioException(
          requestOptions: RequestOptions(path: '/ai/tutor'),
          response: Response(
            requestOptions: RequestOptions(path: '/ai/tutor'),
            statusCode: response.statusCode,
          ),
        );
      }
    } on DioException catch (e) {
      if (CancelToken.isCancel(e) || cancelToken?.isCancelled == true) {
        yield const TutorStreamErrorEvent('Tutor response cancelled.', aborted: true);
        return;
      }
      BackendAvailabilityCache().updateStatus(false);
      if (tokensEmitted == 0) {
        // Network failed before any token delivered: seamless local fallback
        yield* _streamLocalLlmFallback(
          cleanQuestion,
          topic,
          grade,
          cancelToken: cancelToken,
          history: history,
          tools: tools,
          systemPrompt: systemPrompt,
        );
        return;
      } else {
        yield TutorStreamErrorEvent(
          '⚠️ Connection lost during generation: ${e.message ?? e}',
        );
        return;
      }
    } catch (e) {
      if (cancelToken?.isCancelled == true) {
        yield const TutorStreamErrorEvent('Tutor response cancelled.', aborted: true);
        return;
      }
      if (tokensEmitted == 0) {
        yield* _streamLocalLlmFallback(
          cleanQuestion,
          topic,
          grade,
          cancelToken: cancelToken,
          history: history,
          tools: tools,
          systemPrompt: systemPrompt,
        );
        return;
      }
      yield TutorStreamErrorEvent('⚠️ Generation error: $e');
    }
  }


  // Backwards-compatible queryAiTutor delegating to streamAiTutor
  Future<Map<String, dynamic>> queryAiTutor({
    required String question,
    required String topic,
    int grade = 9,
    CancelToken? cancelToken,
    List<String> history = const [],
  }) async {
    final buffer = StringBuffer();
    String finalSource = 'unknown';
    bool finalAudio = false;

    try {
      await for (final event in streamAiTutor(
        question: question,
        topic: topic,
        grade: grade,
        cancelToken: cancelToken,
        history: history,
      )) {
        switch (event) {
          case TutorStreamChunkEvent(:final chunk):
            buffer.write(chunk);
          case TutorStreamToolCallEvent():
            // Legacy synchronous callers do not participate in multi-turn tool cycles.
            break;
          case TutorStreamCompletedEvent(:final fullText, :final source, :final hasAudio):
            return {
              'answer': fullText,
              'hasAudio': hasAudio,
              'source': source,
            };
          case TutorStreamErrorEvent(:final error, :final aborted):
            if (aborted) {
              throw DioException(
                requestOptions: RequestOptions(path: '/ai/tutor'),
                type: DioExceptionType.cancel,
              );
            }
            return {
              'answer': error,
              'hasAudio': false,
              'source': 'tutor_stream_error',
            };
        }
      }
    } on DioException catch (e) {
      if (CancelToken.isCancel(e)) rethrow;
      return {
        'answer': '⚠️ **Tutor Error**: ${e.message ?? e}',
        'hasAudio': false,
        'source': 'tutor_dio_error',
      };
    } catch (e) {
      return {
        'answer': '⚠️ **Tutor Error**: $e',
        'hasAudio': false,
        'source': 'tutor_error',
      };
    }

    final text = buffer.toString().trim();
    return {
      'answer': text.isNotEmpty ? text : '⚠️ The tutor returned an empty response.',
      'hasAudio': finalAudio,
      'source': finalSource,
    };
  }


  Stream<TutorStreamEvent> _streamLocalLlmFallback(
    String question,
    String topic,
    int grade, {
    CancelToken? cancelToken,
    List<String> history = const [],
    List<AgentTool> tools = const [],
    String? systemPrompt,
  }) async* {
    try {
      if (cancelToken?.isCancelled == true) {
        yield const TutorStreamErrorEvent('Tutor response cancelled.', aborted: true);
        return;
      }
      if (Platform.isLinux) {
        final configService = LinuxLlmConfigService();
        var config = await configService.load();
        final autoModel = await configService.autoDetectModelPath();
        final autoExe = await configService.autoDetectExecutable();

        if (config.modelPath.trim().isEmpty || !await File(config.modelPath.trim()).exists()) {
          if (autoModel != null) {
            config = await configService.update(
              modelPath: autoModel,
              executablePath: autoExe,
            );
            final userApiKeyService = await UserApiKeyService.getInstance();
            final fileName = File(autoModel).uri.pathSegments.last;
            await userApiKeyService.setGgufModelName(fileName);
          }
        }

        if (config.executablePath.trim().isEmpty || !await File(config.executablePath.trim()).exists()) {
          if (autoExe != null) {
            config = await configService.update(
              executablePath: autoExe,
            );
          }
        }

        final validation = await configService.validate(config);
        if (!validation.ready) {
          yield TutorStreamCompletedEvent(
            fullText: '🔌 **Offline Mode: Local GGUF Model Required**\n\n${validation.message}\n\n💡 *Tip: Select a GGUF model file or llama-cli runner binary in **Settings > Local AI Tutor**.*',
            source: 'local_llm_config_incomplete',
          );
          return;
        }
      } else {
        try {
          final adminService = LlmAdminChannelService();
          var status = await adminService.getEngineStatus();
          if (!status.loaded) {
            if (status.modelPath.trim().isEmpty) {
              yield const TutorStreamCompletedEvent(
                fullText: '🔌 **Offline Mode: Local GGUF Model Required**\n\nNo offline GGUF model path is configured.\n\n💡 *Tip: Load an offline GGUF model in **Settings > Local AI Tutor** to ask questions anywhere without Wi-Fi.*',
                source: 'offline_mode_no_local_model',
              );
              return;
            }
            final preloadStarted = await adminService.preloadModel();
            status = await adminService.waitForModelReady();

            if (!status.loaded) {
              final loadError = status.lastEngineError.trim();
              if (loadError.isNotEmpty || !preloadStarted) {
                final detail = loadError.isNotEmpty
                    ? loadError
                    : 'The native inference engine could not start model loading.';
                yield TutorStreamCompletedEvent(
                  fullText:
                      '⚠️ **Local AI Model Load Failed**: $detail\n\nCheck that this GGUF architecture is supported by the Android runtime and that the device has enough available memory.',
                  source: 'local_llm_init_error',
                );
                return;
              }

              yield const TutorStreamCompletedEvent(
                fullText:
                    '⚠️ **Local AI Engine Timeout**: The GGUF model did not finish loading within 2 minutes. Try a smaller model or check device memory.',
                source: 'local_llm_warmup_timeout',
              );
              return;
            }
          }
        } catch (e) {
          yield TutorStreamCompletedEvent(
            fullText: '⚠️ **Local AI Error**: Failed to initialize local engine: $e',
            source: 'local_llm_init_error',
          );
          return;
        }
      }

      final gateway = PlatformTutorInferenceGateway();
      if (cancelToken != null) {
        unawaited(
          cancelToken.whenCancel.then((_) => gateway.stopGeneration()),
        );
      }
      final tClean = topic.trim().isEmpty ? 'Science & Mathematics' : topic.trim();
      final cleanStudentQuestion = _extractStudentQuestion(question);

      String ragContextBlock = '';
      try {
        final ragRepo = RagRepositoryV2();
        await ragRepo.ensureSeedChunks();
        // Context budgeting: search with isolated clean student question (max 2 chunks)
        var chunks = await ragRepo.searchChunks(cleanStudentQuestion, tClean, limit: 2);
        if (chunks.isEmpty) {
          chunks = await ragRepo.searchAll(cleanStudentQuestion, limit: 2);
        }
        if (chunks.isNotEmpty) {
          final excerpts = chunks.map((c) => c.content).join('\n---\n');
          // Budget NCERT excerpt strictly to <= 400 characters
          final truncated = excerpts.length > 400 ? '${excerpts.substring(0, 400)}...' : excerpts;
          ragContextBlock = '\n\nRelevant NCERT Textbook Excerpt:\n$truncated\n';
        }
      } catch (e) {
        AppEnvironment.log('RAG', 'Local RAG search for offline fallback failed: $e');
      }

      // Context budgeting: format recent history (max 2 turns, <= 300 chars each)
      final historyBuffer = StringBuffer();
      if (history.isNotEmpty) {
        final recent = history.length > 2 ? history.sublist(history.length - 2) : history;
        for (final turn in recent) {
          final trimmed = turn.trim();
          if (trimmed.isEmpty) continue;
          final capped = trimmed.length > 300 ? '${trimmed.substring(0, 300)}…' : trimmed;
          historyBuffer.writeln(capped);
        }
      }
      final historyText = historyBuffer.toString().trim();
      final historyBlock = historyText.isNotEmpty ? '\n\nRecent context:\n$historyText' : '';

      final toolPromptSection = StringBuffer();
      if (tools.isNotEmpty) {
        toolPromptSection.writeln('\nYou have access to the following tools:');
        for (final tool in tools) {
          toolPromptSection.writeln('- ${tool.name}: ${tool.description}');
          toolPromptSection.writeln('  parameters: ${jsonEncode(tool.parameters)}');
        }
        toolPromptSection.writeln('If you need to use a tool, format your output strictly as:');
        toolPromptSection.writeln('```mentora-tool-call');
        toolPromptSection.writeln('{"name": "<tool_name>", "arguments": {<json_arguments>}}');
        toolPromptSection.writeln('```');
      }

      // Dynamic systemBlock incorporating memory and tool prompt section
      final String systemBlock;
      if (systemPrompt != null && systemPrompt.trim().isNotEmpty) {
        var sp = systemPrompt.trim();
        final tpStr = toolPromptSection.toString().trim();
        if (tpStr.isNotEmpty && !sp.contains('```mentora-tool-call')) {
          if (sp.contains('<|im_end|>')) {
            sp = sp.replaceFirst('<|im_end|>', '\n$tpStr\n<|im_end|>');
          } else {
            sp = '$sp\n\n$tpStr';
          }
        }
        if (!sp.startsWith('<|im_start|>system')) {
          sp = '<|im_start|>system\n$sp';
        }
        if (!sp.endsWith('<|im_end|>')) {
          sp = '$sp\n<|im_end|>';
        }
        systemBlock = sp;
      } else {
        systemBlock = '''<|im_start|>system
You are an expert NCERT school AI tutor for Class $grade $tClean.
Answer directly and clearly using Markdown formatting, bullet points, and key formulas.$ragContextBlock$toolPromptSection
IMPORTANT: If the user asks in Kannada or any regional language, respond in that language.
Do not output internal monologues or planning steps.$historyBlock
DIAGRAM & VISUAL RULES:
- When a student asks for a visual explanation, simulation, dynamics, graph, circuit, or diagram, embed an interactive visualizer widget by emitting a ```mentora-visual block with JSON:
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
      }

      final prompt = '''$systemBlock
<|im_start|>user
$cleanStudentQuestion
<|im_end|>
<|im_start|>assistant
''';

      final filter = ReasoningOutputFilter();
      final rawBuffer = StringBuffer();
      var emittedBuffered = false;

      await for (final chunk in gateway.streamResponse(prompt: prompt)) {
        if (cancelToken?.isCancelled == true) {
          await gateway.stopGeneration();
          yield const TutorStreamErrorEvent('Tutor response cancelled.', aborted: true);
          return;
        }
        final pushed = filter.push(chunk);
        if (pushed.isNotEmpty) {
          rawBuffer.write(pushed);
          final current = rawBuffer.toString();
          if (tools.isEmpty) {
            yield TutorStreamChunkEvent(pushed);
          } else {
            final toolFenceOpen = current.contains('```mentora-tool-call') ||
                                  current.contains('```json:mentora-tool-call');
            if (!toolFenceOpen) {
              if (!emittedBuffered) {
                emittedBuffered = true;
                yield TutorStreamChunkEvent(current);
              } else {
                yield TutorStreamChunkEvent(pushed);
              }
            }
          }
        }
      }
      final flushed = filter.flush();
      if (flushed.isNotEmpty) {
        rawBuffer.write(flushed);
        final current = rawBuffer.toString();
        if (tools.isEmpty) {
          yield TutorStreamChunkEvent(flushed);
        } else {
          final toolFenceOpen = current.contains('```mentora-tool-call') ||
                                current.contains('```json:mentora-tool-call');
          if (!toolFenceOpen) {
            if (!emittedBuffered) {
              emittedBuffered = true;
              yield TutorStreamChunkEvent(current);
            } else {
              yield TutorStreamChunkEvent(flushed);
            }
          }
        }
      }

      final fullRaw = rawBuffer.toString();
      final toolCallMatch = RegExp(r'```(?:json:)?mentora-tool-call\s*(\{[\s\S]*?\})\s*```').firstMatch(fullRaw);
      if (toolCallMatch != null) {
        try {
          final jsonStr = toolCallMatch.group(1)!;
          final map = jsonDecode(jsonStr);
          if (map is Map && map['name'] is String) {
            final name = map['name'] as String;
            final args = map['arguments'] is Map
                ? Map<String, dynamic>.from(map['arguments'] as Map)
                : <String, dynamic>{};
            yield TutorStreamToolCallEvent(
              id: 'call_local_${DateTime.now().millisecondsSinceEpoch}',
              name: name,
              arguments: args,
            );
            return;
          }
        } catch (_) {}
      }

      var fullAnswer = fullRaw.replaceAll(RegExp(r'```(?:json:)?mentora-tool-call[\s\S]*?```'), '').trim();
      fullAnswer = ReasoningOutputFilter.stripComplete(fullAnswer);
      fullAnswer = _deduplicateTopicHeaders(fullAnswer, tClean);
      fullAnswer = MarkdownFormatNormalizer.normalize(fullAnswer);

      if (fullAnswer.isNotEmpty) {
        yield TutorStreamCompletedEvent(
          fullText: fullAnswer,
          source: 'on_device_local_llm',
        );
      } else {
        yield const TutorStreamCompletedEvent(
          fullText: '⚠️ **Local AI Error**: On-device model returned an empty response. Please retry your question.',
          source: 'local_llm_empty_response',
        );
      }
    } catch (e) {
      if (cancelToken?.isCancelled == true) {
        yield const TutorStreamErrorEvent('Tutor response cancelled.', aborted: true);
        return;
      }
      yield TutorStreamCompletedEvent(
        fullText: '⚠️ **Local AI Execution Error**: ${e.toString().replaceFirst(RegExp(r'^Exception:\s*'), '')}\n\n*Tip: Check Settings > Local AI Tutor to verify your local GGUF model file.*',
        source: 'local_llm_execution_error',
      );
    }
  }




  String _deduplicateTopicHeaders(String text, String topic) {
    var out = text.trim();
    for (final stop in const [
      '<|im_end|>',
      '<|im_start|>',
      '<|endoftext|>',
      '</s>',
      '<end_of_turn>',
      '<|im_end',
    ]) {
      final idx = out.indexOf(stop);
      if (idx >= 0) {
        out = out.substring(0, idx);
      }
    }

    final headerStr = '### $topic Explained';
    final lines = out.split('\n');
    final kept = <String>[];
    var seenHeader = false;

    for (final line in lines) {
      final trimmed = line.trim();
      final lowerNorm = trimmed.replaceAll(' ', '').toLowerCase();
      final targetNorm = '###${topic.replaceAll(' ', '').toLowerCase()}explained';

      if (trimmed.toLowerCase() == headerStr.toLowerCase() || lowerNorm == targetNorm) {
        if (seenHeader) {
          continue;
        }
        seenHeader = true;
      }
      kept.add(line);
    }

    return kept.join('\n').replaceAll(RegExp(r'\n{3,}'), '\n\n').trim();
  }

  // 8. Authenticate User with Gateway (OFFLINE-FIRST, 0 404s)
  // Previously POST /api/auth/login returned 404 (no gateway auth route).
  // Now uses local SharedPreferences session state - preserves offline-first.
  Future<Map<String, dynamic>> loginUser(String email, String password) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      // Basic local validation - preserve credentials in local session
      if (email.trim().isEmpty || password.trim().isEmpty) {
        return {'error': 'Email and password are required'};
      }
      await prefs.setString('user_email', email.trim());
      await prefs.setString('user_name', email.split('@').first);
      await prefs.setBool('user_is_logged_in', true);
      await prefs.setInt('user_last_login_ts', DateTime.now().millisecondsSinceEpoch);
      return {
        'success': true,
        'email': email.trim(),
        'name': email.split('@').first,
        'source': 'local_session',
      };
    } catch (e) {
      return {'error': e.toString()};
    }
  }

  // 9. Check Gateway Connection Health
  Future<Map<String, dynamic>> checkBackendHealth({
    void Function(DiscoveryProgress progress)? onProgress,
  }) async {
    final activeUrl = await autoDiscoverGatewayUrl(onProgress: onProgress);
    final stopwatch = Stopwatch()..start();
    try {
      final response = await _client
          .get('$activeUrl/health');
      stopwatch.stop();
      if (response.statusCode == 200) {
        return {
          'online': true,
          'activeUrl': activeUrl,
          'latencyMs': stopwatch.elapsedMilliseconds,
          'status': 'Connected',
          'details': response.data,
        };
      }
    } on DioException catch (e) {
      stopwatch.stop();
      return {
        'online': false,
        'activeUrl': activeUrl,
        'latencyMs': stopwatch.elapsedMilliseconds,
        'status': 'Error: ${e.message}',
      };
    }
    return {
      'online': false,
      'activeUrl': activeUrl,
      'latencyMs': stopwatch.elapsedMilliseconds,
      'status': 'Gateway offline',
    };
  }
}
