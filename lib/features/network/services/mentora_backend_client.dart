import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:sqflite/sqflite.dart';
import '../../course/data/local/app_database.dart';
import '../../course/data/local/course_repository.dart';
import '../../course/domain/course_tree.dart';
import '../domain/runtime_backend_url.dart';
import '../../settings/services/user_api_key_service.dart';

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
  static List<String> getCandidateGatewayUrls() {
    final list = <String>[
      'http://10.35.98.193:8000',
      'http://10.0.2.2:8000',
      'http://akash-Ubuntu.local:8000',
      'http://akash-Ubuntu:8000',
      'http://akash-Ubuntu.local',
      'http://akash-Ubuntu',
    ];
    try {
      final hostname = Platform.localHostname;
      if (hostname.isNotEmpty) {
        list.add('http://$hostname.local:8000');
        list.add('http://$hostname:8000');
        list.add('http://$hostname.local');
        list.add('http://$hostname');
      }
    } catch (_) {}
    list.addAll([
      'http://10.35.98.193:8000',
      'http://10.0.2.2:8000',
      'http://127.0.0.1:8000',
      'http://pihub.local:8000',
      'http://pihub.local',
    ]);
    return list.toSet().toList();
  }

  static String _activeBaseUrl = 'http://10.35.98.193:8000';
  String get baseUrl => _activeBaseUrl;
  final http.Client _client;

  MentoraBackendClient({
    String? baseUrl,
    http.Client? client,
  }) : _client = client ?? http.Client() {
    if (baseUrl != null) {
      _activeBaseUrl = baseUrl;
    }
  }

  // Subnet Auto-Discovery: Probe candidate local IPs & Laptop hostname
  Future<String> autoDiscoverGatewayUrl({
    void Function(DiscoveryProgress progress)? onProgress,
  }) async {
    final candidates = getCandidateGatewayUrls();
    for (int i = 0; i < candidates.length; i++) {
      final candidate = candidates[i];
      final double progressVal = (i + 1) / candidates.length;
      onProgress?.call(DiscoveryProgress(
        currentCandidate: candidate,
        step: i + 1,
        totalSteps: candidates.length,
        progress: progressVal,
        isFinished: false,
        isSuccess: false,
      ));

      try {
        final res = await _client
            .get(Uri.parse('$candidate/health'))
            .timeout(const Duration(seconds: 2));
        if (res.statusCode == 200) {
          _activeBaseUrl = candidate;
          RuntimeBackendUrl().updateUrl(candidate);
          String deviceName = 'Local Subnet Gateway ($candidate)';
          try {
            final hName = Platform.localHostname;
            if (hName.isNotEmpty && candidate.contains(hName)) {
              deviceName = 'Laptop Gateway ($hName)';
            } else if (candidate.contains('127.0.0.1') || candidate.contains('localhost')) {
              deviceName = 'Laptop Localhost (127.0.0.1)';
            } else if (candidate.contains('pihub')) {
              deviceName = 'Raspberry Pi Gateway (PiHub)';
            }
          } catch (_) {}

          onProgress?.call(DiscoveryProgress(
            currentCandidate: candidate,
            step: i + 1,
            totalSteps: candidates.length,
            progress: 1.0,
            isFinished: true,
            isSuccess: true,
            connectedUrl: candidate,
            connectedDeviceName: deviceName,
          ));
          return candidate;
        }
      } catch (_) {}
    }

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

  Future<Map<String, String>> _buildHeaders() async {
    final keyService = await UserApiKeyService.getInstance();
    final headers = <String, String>{
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    };
    headers.addAll(keyService.getAuthHeaders());
    return headers;
  }

  // 1. Fetch Real Subjects & Progress for Grade
  Future<List<Map<String, dynamic>>> getSubjectsForGrade(int grade) async {
    try {
      final headers = await _buildHeaders();
      final response = await _client
          .get(Uri.parse('$_activeBaseUrl/catalog/subjects?grade=$grade'), headers: headers)
          .timeout(const Duration(seconds: 4));

      if (response.statusCode == 200) {
        final List data = jsonDecode(response.body);
        if (data.isNotEmpty) {
          return List<Map<String, dynamic>>.from(data);
        }
      }
    } catch (_) {
      await autoDiscoverGatewayUrl();
    }

    final courseRepo = CourseRepository();
    await courseRepo.ensureSeedData();
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

    return [
      {'name': 'Mathematics', 'code': 'MAT${grade.toString().padLeft(2, '0')}', 'progress': 0.0, 'chaptersCompleted': 0, 'totalChapters': 12, 'color': '0xFFF59E0B', 'icon': 'calculate_outlined'},
      {'name': 'Science', 'code': 'SCI${grade.toString().padLeft(2, '0')}', 'progress': 0.0, 'chaptersCompleted': 0, 'totalChapters': 12, 'color': '0xFF10B981', 'icon': 'science_outlined'},
      {'name': 'Social Science', 'code': 'SOC${grade.toString().padLeft(2, '0')}', 'progress': 0.0, 'chaptersCompleted': 0, 'totalChapters': 12, 'color': '0xFF3B82F6', 'icon': 'public_outlined'},
      {'name': 'English', 'code': 'ENG${grade.toString().padLeft(2, '0')}', 'progress': 0.0, 'chaptersCompleted': 0, 'totalChapters': 12, 'color': '0xFF8B5CF6', 'icon': 'menu_book_outlined'},
    ];
  }

  // 2. Fetch Real Chapters for Selected Subject & Grade
  Future<List<Map<String, dynamic>>> getChaptersForSubject(String subjectName, {int grade = 9}) async {
    try {
      final headers = await _buildHeaders();
      final response = await _client
          .get(Uri.parse('$_activeBaseUrl/catalog/chapters?subject=$subjectName&grade=$grade'), headers: headers)
          .timeout(const Duration(seconds: 4));

      if (response.statusCode == 200) {
        final List data = jsonDecode(response.body);
        final list = List<Map<String, dynamic>>.from(data);
        if (list.isNotEmpty) {
          await _saveBackendChaptersToLocalDb(list, subjectName, grade);
          return list;
        }
      }
    } catch (_) {
      await autoDiscoverGatewayUrl();
    }

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
      final headers = await _buildHeaders();
      final response = await _client
          .get(Uri.parse('$_activeBaseUrl/api/v1/simulations/$chapter'), headers: headers)
          .timeout(const Duration(seconds: 4));

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }
    } catch (_) {}

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
      final headers = await _buildHeaders();
      final response = await _client
          .get(Uri.parse('$_activeBaseUrl/videos/$chapter'), headers: headers)
          .timeout(const Duration(seconds: 4));

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }
    } catch (_) {}

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
      final headers = await _buildHeaders();
      final response = await _client
          .get(Uri.parse('$_activeBaseUrl/quizzes/$chapter'), headers: headers)
          .timeout(const Duration(seconds: 4));

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }
    } catch (_) {}

    return {
      'chapter': chapter,
      'title': 'Diagnostic Assessment: Motion & Velocity',
      'totalQuestions': 3,
      'userMastery': 0,
      'questions': [
        {
          'id': 'q1',
          'question': 'A car covers 100 meters in 5 seconds. What is its average speed?',
          'options': ['10 m/s', '20 m/s', '25 m/s', '50 m/s'],
          'correctIndex': 1,
          'explanation': 'Speed = Distance / Time = 100 m / 5 s = 20 m/s.',
        },
        {
          'id': 'q2',
          'question': 'Which of the following is a vector quantity?',
          'options': ['Distance', 'Speed', 'Velocity', 'Mass'],
          'correctIndex': 2,
          'explanation': 'Velocity has both magnitude and direction.',
        },
        {
          'id': 'q3',
          'question': 'An object starts from rest and accelerates at 2 m/s² for 4 seconds. What is its final velocity?',
          'options': ['4 m/s', '8 m/s', '12 m/s', '16 m/s'],
          'correctIndex': 1,
          'explanation': 'v = u + at => 0 + (2 * 4) = 8 m/s.',
        },
      ],
    };
  }

  // 6. Fetch User Profile & Streak
  Future<Map<String, dynamic>> getUserProfile() async {
    try {
      final headers = await _buildHeaders();
      final response = await _client
          .get(Uri.parse('$_activeBaseUrl/api/user/profile'), headers: headers)
          .timeout(const Duration(seconds: 4));

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }
    } catch (_) {}

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
    // Probe and auto-discover gateway URL before network request if default
    if (_activeBaseUrl == 'http://127.0.0.1:8000') {
      await autoDiscoverGatewayUrl();
    }

    try {
      final headers = await _buildHeaders();
      final payload = jsonEncode({
        'question': question,
        'topic': topic,
        'grade': grade,
      });

      final response = await _client
          .post(Uri.parse('$_activeBaseUrl/ai/tutor'), headers: headers, body: payload)
          .timeout(const Duration(seconds: 45));

      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        if (decoded is Map<String, dynamic> && decoded['answer'] != null) {
          return decoded;
        }
      } else if (response.statusCode == 504) {
        return {
          'answer': '⚠️ **Backend LLM Timeout**: The local Ollama AI model took longer than 90 seconds to generate on CPU. Please retry or ask a shorter query.',
          'hasAudio': false,
          'source': 'backend_timeout_error',
        };
      }
    } catch (e) {
      autoDiscoverGatewayUrl();
      return {
        'answer': '⚠️ **Backend Network Connection Error**: Could not connect to backend at $_activeBaseUrl. Please check your Wi-Fi or load an offline model (.gguf) in Settings.',
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

  // 8. Authenticate User with Gateway
  Future<Map<String, dynamic>> loginUser(String email, String password) async {
    final headers = {'Content-Type': 'application/json'};
    final response = await _client.post(
      Uri.parse('$_activeBaseUrl/api/auth/login'),
      headers: headers,
      body: jsonEncode({'email': email, 'password': password}),
    );
    return jsonDecode(response.body);
  }

  // 9. Check Gateway Connection Health
  Future<Map<String, dynamic>> checkBackendHealth({
    void Function(DiscoveryProgress progress)? onProgress,
  }) async {
    final activeUrl = await autoDiscoverGatewayUrl(onProgress: onProgress);
    final stopwatch = Stopwatch()..start();
    try {
      final response = await _client
          .get(Uri.parse('$activeUrl/health'))
          .timeout(const Duration(seconds: 4));
      stopwatch.stop();

      if (response.statusCode == 200) {
        return {
          'online': true,
          'activeUrl': activeUrl,
          'latencyMs': stopwatch.elapsedMilliseconds,
          'status': 'Connected',
          'details': jsonDecode(response.body),
        };
      }
    } catch (e) {
      stopwatch.stop();
      return {
        'online': false,
        'activeUrl': activeUrl,
        'latencyMs': stopwatch.elapsedMilliseconds,
        'status': 'Error: $e',
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
