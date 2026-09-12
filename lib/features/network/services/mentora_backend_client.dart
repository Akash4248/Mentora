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
import '../domain/runtime_backend_url.dart';
import '../../settings/services/user_api_key_service.dart';
import '../../chat/application/markdown_format_normalizer.dart';
import '../../chat/application/reasoning_output_filter.dart';
import '../../chat/data/local/linux_llm_config_service.dart';
import '../../chat/data/platform_tutor_inference_gateway.dart';
import '../../chat/data/llm_admin_channel_service.dart';

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
  ///
  /// Sources (in order of reliability):
  ///   1. AppEnvironment.backendBaseUrl (--dart-define or .env)
  ///   2. mDNS standard Pi hostname (pihub.local)
  ///   3. Current device hostname .local (for dev laptops running the server)
  ///   4. Loopback (for emulator / local server)
  ///
  /// All hardcoded developer machine IPs (10.35.98.193, akash-Ubuntu) have been
  /// removed. If you need to test against a specific IP, pass it via
  /// --dart-define=BACKEND_BASE_URL=http://<ip>:8000.
  static List<String> getCandidateGatewayUrls() {
    final list = <String>[];

    // 1. Explicitly configured URL (highest priority)
    final configured = AppEnvironment.backendBaseUrl;
    if (configured.isNotEmpty) list.add(configured);

    // 2. Standard Pi gateway hostnames
    list.addAll([
      'http://pihub.local:8000',
      'http://pihub.local',
    ]);

    // 3. Device hostname .local (developer running server on same laptop)
    try {
      final hostname = Platform.localHostname;
      if (hostname.isNotEmpty) {
        list.add('http://$hostname.local:8000');
        list.add('http://$hostname.local');
        list.add('http://$hostname:8000');
      }
    } catch (_) {}

    // 4. Loopback (emulator or local dev server)
    list.addAll([
      'http://10.0.2.2:8000', // Android emulator → host loopback
      'http://127.0.0.1:8000',
    ]);

    return list.toSet().toList();
  }

  /// Active gateway URL. Updated by [BackendDiscoveryService] on successful
  /// connection. Default is driven by [AppEnvironment] (--dart-define or .env),
  /// never a hardcoded developer IP.
  static String _activeBaseUrl = AppEnvironment.backendBaseUrl;
  String get baseUrl => _activeBaseUrl;
  void setBaseUrl(String url) {
    _activeBaseUrl = url;
    MentoraDioClient.updateBaseUrl(url);
  }

  MentoraBackendClient({String? baseUrl}) {
    if (baseUrl != null) {
      _activeBaseUrl = baseUrl;
      MentoraDioClient.updateBaseUrl(baseUrl);
    }
  }

  Dio get _client => MentoraDioClient.instance;

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
          .get('/catalog/subjects?grade=$grade');
      if (response.statusCode == 200) {
        final List data = response.data is List
            ? response.data
            : (response.data is String ? jsonDecode(response.data) : []);
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
          .get('/catalog/chapters?subject=$subjectName&grade=$grade');
      if (response.statusCode == 200) {
        final List data = response.data is List
            ? response.data
            : (response.data is String ? jsonDecode(response.data) : []);
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

  // 3. Fetch Interactive Simulation Config for Chapter
  Future<Map<String, dynamic>> getSimulationForChapter(String chapter) async {
    try {
      final response = await _client.get('/api/v1/simulations/$chapter');
      if (response.statusCode == 200) {
        return response.data is Map ? Map<String, dynamic>.from(response.data) : jsonDecode(response.data);
      }
    } on DioException catch (_) {}

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

  // 4. Fetch YouTube Video Lectures & ISL for Chapter
  Future<Map<String, dynamic>> getVideoLecturesForChapter(String chapter) async {
    try {
      final response = await _client.get('/videos/$chapter');
      if (response.statusCode == 200) {
        return response.data is Map ? Map<String, dynamic>.from(response.data) : jsonDecode(response.data);
      }
    } on DioException catch (_) {}

    return {
      'chapter': chapter,
      'currentVideo': {
        'id': 'v_motion_01',
        'youtubeId': 'tBmavvMwu68',
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

  // 5. Fetch Diagnostic Quiz for Chapter
  Future<Map<String, dynamic>> getQuizForChapter(String chapter) async {
    try {
      final response = await _client.get('/quizzes/$chapter');
      if (response.statusCode == 200) {
        return response.data is Map ? Map<String, dynamic>.from(response.data) : jsonDecode(response.data);
      }
    } on DioException catch (_) {}

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

  // 6. Fetch User Profile & Streak
  Future<Map<String, dynamic>> getUserProfile() async {
    try {
      final response = await _client.get('/api/user/profile');
      if (response.statusCode == 200) {
        return response.data is Map ? Map<String, dynamic>.from(response.data) : jsonDecode(response.data);
      }
    } on DioException catch (_) {}

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

  // 7. Send Query to Gateway AI Tutor Endpoint
  Future<Map<String, dynamic>> queryAiTutor({
    required String question,
    required String topic,
    int grade = 9,
  }) async {
    // Check global availability state: If offline or unverified, fallback immediately without network probing
    if (BackendAvailabilityCache().isOffline) {
      try {
        final localResult = await _tryLocalLlmFallback(question, topic, grade);
        if (localResult != null) {
          return localResult;
        }
      } catch (_) {}

      return {
        'answer': '🔌 **Offline Mode: PiHub Unreachable**\n\nUnable to reach backend server.\n\n💡 *Tip: Load an offline GGUF model in **Settings > Local AI Tutor** to ask questions anywhere without Wi-Fi.*',
        'hasAudio': false,
        'source': 'offline_mode_no_local_model',
      };
    }

    try {
      final response = await _client.post(
        '/ai/tutor',
        data: {'question': question, 'topic': topic, 'grade': grade},
        options: Options(
          sendTimeout: const Duration(seconds: 3),
          receiveTimeout: const Duration(seconds: 120),
        ),
      );

      if (response.statusCode == 200) {
        final decoded = response.data is Map ? Map<String, dynamic>.from(response.data) : jsonDecode(response.data);
        if (decoded['answer'] != null) {
          BackendAvailabilityCache().updateStatus(true, url: _activeBaseUrl);
          return decoded;
        }
      } else if (response.statusCode == 504) {
        return {
          'answer': '⚠️ **Backend LLM Timeout (504)**: Backend generation took longer than 120 seconds on CPU. Please retry or ask a shorter question.',
          'hasAudio': false,
          'source': 'backend_timeout_error',
        };
      } else {
        return {
          'answer': '⚠️ **Backend Error (${response.statusCode})**: Service returned status ${response.statusCode}',
          'hasAudio': false,
          'source': 'backend_http_error_${response.statusCode}',
        };
      }
    } on DioException catch (e) {
      BackendAvailabilityCache().updateStatus(false);
      try {
        final localResult = await _tryLocalLlmFallback(question, topic, grade);
        if (localResult != null) {
          return localResult;
        }
      } catch (_) {}

      final isNetworkHostError = e.toString().contains('Failed host lookup') || e.toString().contains('SocketException');
      final hostName = _activeBaseUrl.replaceAll('http://', '').replaceAll('https://', '');

      final friendlyMsg = isNetworkHostError
          ? '🔌 **Offline Mode: PiHub Unreachable**\n\nUnable to reach PiHub server at `$hostName`.\n\n💡 *Tip: Connect your phone to the PiHub Wi-Fi network, or load an offline GGUF model in **Settings > Local AI Tutor** to ask questions anywhere without Wi-Fi.*'
          : '⚠️ **Backend Service Error**: ${e.toString().replaceFirst(RegExp(r'^Exception:\s*'), '')}\n\n*Tip: Check Settings > Local AI Tutor to load an offline model.*';

      return {
        'answer': friendlyMsg,
        'hasAudio': false,
        'source': 'backend_connection_error',
      };
    }

    return {
      'answer': '⚠️ **Backend Error**: Service returned an unexpected response. Please try again.',
      'hasAudio': false,
      'source': 'unexpected_response_error',
    };
  }

  Future<Map<String, dynamic>?> _tryLocalLlmFallback(
    String question,
    String topic,
    int grade,
  ) async {
    try {
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
          return null;
        }
      } else {
        try {
          final adminService = LlmAdminChannelService();
          var status = await adminService.getEngineStatus();
          if (!status.loaded) {
            if (status.modelPath.trim().isEmpty) {
              return null;
            }
            // Preload GGUF model into memory if path exists but engine cold
            await adminService.preloadModel();

            // Wait up to 10s for Kotlin background thread in LlamaEngine to finish loading model
            final stopWatch = Stopwatch()..start();
            while (stopWatch.elapsedMilliseconds < 10000) {
              await Future.delayed(const Duration(milliseconds: 200));
              status = await adminService.getEngineStatus();
              if (status.loaded) break;
            }

            if (!status.loaded) {
              return null;
            }
          }
        } catch (_) {
          return null;
        }
      }

      final gateway = PlatformTutorInferenceGateway();
      final tClean = topic.trim().isEmpty ? 'Science & Mathematics' : topic.trim();
      final prompt = '''<|im_start|>system
You are an expert NCERT school AI tutor for Class $grade $tClean.
Answer the student's question directly and clearly using Markdown formatting, bullet points, and key formulas.
IMPORTANT: If the user asks in Kannada (e.g. "can u explain in kannada" or Kannada script) or any regional language, respond in that language.
Do not output internal monologues or planning steps.
<|im_end|>
<|im_start|>user
$question
<|im_end|>
<|im_start|>assistant
''';

      final filter = ReasoningOutputFilter();
      final rawBuffer = StringBuffer();

      await for (final chunk in gateway.streamResponse(prompt: prompt)) {
        final pushed = filter.push(chunk);
        if (pushed.isNotEmpty) {
          rawBuffer.write(pushed);
        }
      }
      final flushed = filter.flush();
      if (flushed.isNotEmpty) {
        rawBuffer.write(flushed);
      }

      var fullAnswer = ReasoningOutputFilter.stripComplete(rawBuffer.toString());
      fullAnswer = _deduplicateTopicHeaders(fullAnswer, tClean);
      fullAnswer = MarkdownFormatNormalizer.normalize(fullAnswer);

      if (fullAnswer.isNotEmpty) {
        final formattedAnswer = fullAnswer.startsWith('###')
            ? fullAnswer
            : '### $tClean Explained\n\n$fullAnswer';

        return {
          'answer': '📱 **[On-Device Local AI Tutor]**\n\n$formattedAnswer',
          'hasAudio': false,
          'source': 'on_device_local_llm',
        };
      }
    } catch (_) {
      // Ignore and fallback to network error message
    }
    return null;
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

  // 8. Authenticate User with Gateway
  Future<Map<String, dynamic>> loginUser(String email, String password) async {
    try {
      final response = await _client.post(
        '/api/auth/login',
        data: {'email': email, 'password': password},
      );
      return response.data is Map ? Map<String, dynamic>.from(response.data) : jsonDecode(response.data);
    } on DioException catch (e) {
      return {'error': e.message ?? 'Login failed'};
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

class OfflineSocraticEngine {
  static Map<String, dynamic> generateResponse({
    required String question,
    required String topic,
    int grade = 9,
  }) {
    final qClean = question.trim();
    final tClean = topic.isEmpty ? "General Science & Mathematics" : topic.trim();

    final standaloneGreeting = RegExp(
      r'^(hi|hello|hey|hii+|good\s*(morning|afternoon|evening)|how are you)[\s!.?]*$',
      caseSensitive: false,
    );
    if (standaloneGreeting.hasMatch(qClean)) {
      return {
        'answer': 'Hello! 👋 I am your NCERT Class $grade Socratic AI Tutor for **$tClean**.\n\nHow can I help you master **$tClean** today? Feel free to ask any question or concept from this chapter!',
        'formulas': <String>[],
        'hasAudio': true,
        'source': 'offline_socratic_greeting',
        'explainOptions': ['Explain Core Concepts', 'Show Example Problems', 'Real-World Applications'],
      };
    }

    String cleanQuery = qClean;
    final wrapperMatch = RegExp(r'^Explain\s*"(.*?)"\s*for\s*.*$', caseSensitive: false).firstMatch(qClean);
    if (wrapperMatch != null && wrapperMatch.group(1) != null) {
      cleanQuery = wrapperMatch.group(1)!;
    }

    final words = cleanQuery.split(' ').where((w) => w.length > 2 && !w.contains('"')).toList();
    final keyConcept = words.isNotEmpty ? words.first[0].toUpperCase() + words.first.substring(1) : "Concept";
    final queryContext = words.isNotEmpty ? words.take(5).join(' ') : cleanQuery;

    final answer = '''### NCERT Class $grade Socratic Explanation

**Topic**: $tClean
**Question**: *"$cleanQuery"*

#### Core Conceptual Analysis:
When investigating **"$cleanQuery"** in NCERT Grade $grade **$tClean**, we analyze how *$queryContext* operates based on fundamental principles.

1. **Core Definition & Principles**:
   - **$keyConcept**: Refers to the fundamental property and behavior of $cleanQuery within the context of $tClean.
   - In the Class $grade curriculum, students study how these parameters interact under standard physical, chemical, or mathematical conditions.

2. **Methodological Step-by-Step Breakdown**:
   - **Step 1 (Identify Parameters)**: Extract given values, boundary conditions, and standard SI units relevant to $cleanQuery.
   - **Step 2 (Apply Governing Laws)**: Use core equations and theoretical frameworks for $tClean to formulate an analytical solution.
   - **Step 3 (Synthesize & Validate)**: Confirm dimensional consistency, state boundary assumptions, and relate findings to real-world NCERT applications.

3. **Key Takeaway for Exams**:
   Clear mastery of **"$cleanQuery"** ensures a solid foundation for NCERT Grade $grade assessments, practical lab experiments, and advanced problem solving.''';

    return {
      'answer': answer,
      'formulas': [
        'Standard NCERT Equation for $tClean',
        'SI Units & Parameter Relationships ($keyConcept)'
      ],
      'hasAudio': true,
      'source': 'offline_socratic_generative_engine',
      'explainOptions': ['Real-World Analogy', 'Step-by-Step Math', 'Simpler Language', 'Visual Simulation'],
    };
  }
}
