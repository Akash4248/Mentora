import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
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
      'http://127.0.0.1:8000',
      'http://10.0.2.2:8000',
      'http://pihub.local:8000',
      'http://pihub.local',
    ]);
    return list.toSet().toList();
  }

  static String _activeBaseUrl = 'http://127.0.0.1:8000';
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

  // Subnet Auto-Discovery: Probe candidate local IPs & Laptop hostname only when PiHub mode is ON
  Future<String> autoDiscoverGatewayUrl({
    void Function(DiscoveryProgress progress)? onProgress,
  }) async {
    final keyService = await UserApiKeyService.getInstance();

    // If PiHub toggle is OFF, connect directly to cloud/internet URL without local subnet probing
    if (!keyService.isPiHubModeEnabled) {
      _activeBaseUrl = keyService.customServerUrl.isNotEmpty
          ? keyService.customServerUrl
          : 'http://127.0.0.1:8000';
      onProgress?.call(DiscoveryProgress(
        currentCandidate: _activeBaseUrl,
        step: 1,
        totalSteps: 1,
        progress: 1.0,
        isFinished: true,
        isSuccess: true,
        connectedUrl: _activeBaseUrl,
        connectedDeviceName: 'Cloud / Internet Gateway ($_activeBaseUrl)',
      ));
      return _activeBaseUrl;
    }

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
          .get(Uri.parse('$baseUrl/catalog/subjects?grade=$grade'), headers: headers)
          .timeout(const Duration(seconds: 4));

      if (response.statusCode == 200) {
        final List data = jsonDecode(response.body);
        return List<Map<String, dynamic>>.from(data);
      }
    } catch (_) {
      await autoDiscoverGatewayUrl();
    }

    return [
      {'name': 'Physics', 'code': 'PHY09', 'progress': 0.58, 'chaptersCompleted': 7, 'totalChapters': 12},
      {'name': 'Chemistry', 'code': 'CHE09', 'progress': 0.45, 'chaptersCompleted': 5, 'totalChapters': 11},
      {'name': 'Biology', 'code': 'BIO09', 'progress': 0.60, 'chaptersCompleted': 6, 'totalChapters': 10},
      {'name': 'Mathematics', 'code': 'MAT09', 'progress': 0.40, 'chaptersCompleted': 6, 'totalChapters': 15},
    ];
  }

  // 2. Fetch Real Chapters for Selected Subject
  Future<List<Map<String, dynamic>>> getChaptersForSubject(String subjectName) async {
    try {
      final headers = await _buildHeaders();
      final response = await _client
          .get(Uri.parse('$baseUrl/catalog/chapters?subject=$subjectName'), headers: headers)
          .timeout(const Duration(seconds: 4));

      if (response.statusCode == 200) {
        final List data = jsonDecode(response.body);
        return List<Map<String, dynamic>>.from(data);
      }
    } catch (_) {
      await autoDiscoverGatewayUrl();
    }

    return [
      {'number': 1, 'title': 'Motion', 'status': 'completed', 'duration': '25 mins', 'mastery': 92},
      {'number': 2, 'title': 'Force and Laws of Motion', 'status': 'in_progress', 'duration': '30 mins', 'mastery': 58},
      {'number': 3, 'title': 'Gravitation', 'status': 'locked', 'duration': '20 mins', 'mastery': 0},
      {'number': 4, 'title': 'Work and Energy', 'status': 'locked', 'duration': '35 mins', 'mastery': 0},
      {'number': 5, 'title': 'Sound', 'status': 'locked', 'duration': '25 mins', 'mastery': 0},
    ];
  }

  // 3. Fetch Interactive Simulation Config for Chapter
  Future<Map<String, dynamic>> getSimulationForChapter(String chapter) async {
    try {
      final headers = await _buildHeaders();
      final response = await _client
          .get(Uri.parse('$baseUrl/api/v1/simulations/$chapter'), headers: headers)
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
          .get(Uri.parse('$baseUrl/videos/$chapter'), headers: headers)
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
          .get(Uri.parse('$baseUrl/quizzes/$chapter'), headers: headers)
          .timeout(const Duration(seconds: 4));

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }
    } catch (_) {}

    return {
      'chapter': chapter,
      'title': 'Diagnostic Assessment: Motion & Velocity',
      'totalQuestions': 3,
      'userMastery': 85,
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
          .get(Uri.parse('$baseUrl/api/user/profile'), headers: headers)
          .timeout(const Duration(seconds: 4));

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      }
    } catch (_) {}

    return {
      'name': 'Rahul Sharma',
      'grade': 9,
      'streakDays': 5,
      'dailyMinsLearned': 24,
      'dailyGoalMins': 30,
      'activeSubject': 'Physics',
      'activeChapter': 'Motion',
    };
  }

class OfflineSocraticEngine {
  static Map<String, dynamic> generateResponse({
    required String question,
    required String topic,
    int grade = 9,
  }) {
    final qLower = question.toLowerCase();

    // 1. Motion / Kinematics / Speed / Velocity
    if (qLower.contains('speed') || qLower.contains('velocity') || qLower.contains('acceleration') || qLower.contains('motion')) {
      return {
        'answer': 'Great question about **$topic**!\n\n**Query**: *"$question"*\n\n### NCERT Class $grade Core Concepts:\n• **Speed ($s$)**: Scalar quantity representing distance travelled per unit time ($s = d/t$).\n• **Velocity ($v$)**: Vector quantity representing rate of displacement ($v = \\Delta x / t$).\n• **Acceleration ($a$)**: Rate of change of velocity ($a = \\frac{v - u}{t}$).\n\n### Kinematic Equations:\n1. $v = u + at$\n2. $s = ut + \\frac{1}{2}at^2$\n3. $v^2 = u^2 + 2as$',
        'formulas': ['v = u + at', 's = ut + ½at²', 'v² = u² + 2as'],
        'hasAudio': true,
        'source': 'offline_socratic_engine',
        'explainOptions': ['Real-World Analogy', 'Step-by-Step Math', 'Simpler Language', 'Visual Simulation'],
      };
    }

    // 2. Force & Laws of Motion
    if (qLower.contains('force') || qLower.contains('newton') || qLower.contains('inertia') || qLower.contains('friction') || qLower.contains('momentum')) {
      return {
        'answer': 'Excellent inquiry on **Force & Dynamics** (Grade $grade NCERT)!\n\n**Query**: *"$question"*\n\n### Newton\'s Laws of Motion:\n1. **First Law (Inertia)**: An object at rest or uniform motion stays in its state unless acted upon by an unbalanced force.\n2. **Second Law**: Force equals rate of change of momentum ($F = ma$).\n3. **Third Law**: For every action, there is an equal and opposite reaction ($F_{AB} = -F_{BA}$).',
        'formulas': ['F = ma', 'p = mv', 'F_{12} = -F_{21}'],
        'hasAudio': true,
        'source': 'offline_socratic_engine',
        'explainOptions': ['Real-World Analogy', 'Step-by-Step Math', 'Simpler Language', 'Visual Simulation'],
      };
    }

    // 3. Cell Biology
    if (qLower.contains('cell') || qLower.contains('mitochondria') || qLower.contains('nucleus') || qLower.contains('dna') || qLower.contains('plant') || qLower.contains('animal') || qLower.contains('organelle')) {
      return {
        'answer': 'Wonderful question in **Biology: Cell Structure** (Grade $grade NCERT)!\n\n**Query**: *"$question"*\n\n### Key Concepts:\n• **The Cell**: Fundamental structural and functional unit of all living organisms.\n• **Mitochondria**: Double-membrane organelle responsible for ATP synthesis via cellular respiration.\n• **Nucleus**: Controls cell growth and contains genetic instructions (DNA/RNA).\n• **Cell Wall & Chloroplasts**: Present in plant cells for structural rigidity and photosynthesis.',
        'formulas': ['C_6H_{12}O_6 + 6O_2 \\rightarrow 6CO_2 + 6H_2O + ATP'],
        'hasAudio': true,
        'source': 'offline_socratic_engine',
        'explainOptions': ['Real-World Analogy', 'Step-by-Step Math', 'Simpler Language', 'Visual Simulation'],
      };
    }

    // 4. Chemistry / Atomic Structure / Matter
    if (qLower.contains('atom') || qLower.contains('molecule') || qLower.contains('electron') || qLower.contains('proton') || qLower.contains('acid') || qLower.contains('base') || qLower.contains('element') || qLower.contains('reaction')) {
      return {
        'answer': 'Great question in **Chemistry** (Grade $grade NCERT)!\n\n**Query**: *"$question"*\n\n### Key Principles:\n• **Atomic Structure**: Subatomic particles consist of protons (+), neutrons (neutral), and orbiting electrons (-).\n• **Atomic Number ($Z$)**: Number of protons in nucleus.\n• **Mass Number ($A$)**: Total count of protons and neutrons ($A = Z + N$).\n• **Acids & Bases**: Acids donate $H^+$ ions (pH < 7); Bases accept $H^+$ or release $OH^-$ (pH > 7).',
        'formulas': ['A = Z + N', 'pH = -\\log_{10}[H^+]'],
        'hasAudio': true,
        'source': 'offline_socratic_engine',
        'explainOptions': ['Real-World Analogy', 'Step-by-Step Math', 'Simpler Language', 'Visual Simulation'],
      };
    }

    // 5. Mathematics
    if (qLower.contains('math') || qLower.contains('equation') || qLower.contains('triangle') || qLower.contains('quadratic') || qLower.contains('pythagoras') || qLower.contains('area') || qLower.contains('volume') || qLower.contains('fraction')) {
      return {
        'answer': 'Here is the step-by-step mathematical breakdown for **$topic** (Grade $grade NCERT):\n\n**Query**: *"$question"*\n\n### Core Theorems & Formulas:\n• **Pythagoras Theorem**: $a^2 + b^2 = c^2$ in right-angled triangles.\n• **Quadratic Formula**: $x = \\frac{-b \\pm \\sqrt{b^2 - 4ac}}{2a}$.\n• **Area Calculation**: $\\text{Area} = \\frac{1}{2} \\times \\text{base} \\times \\text{height}$.',
        'formulas': ['a² + b² = c²', 'x = (-b ± √(b² - 4ac)) / (2a)'],
        'hasAudio': true,
        'source': 'offline_socratic_engine',
        'explainOptions': ['Real-World Analogy', 'Step-by-Step Math', 'Simpler Language', 'Visual Simulation'],
      };
    }

    // 6. Generic NCERT Socratic Guidance
    return {
      'answer': 'Thanks for asking about **$topic** (Grade $grade NCERT)!\n\n**Question**: *"$question"*\n\n### NCERT Socratic Learning Path:\n• Let\'s analyze **"$question"** using fundamental principles of $topic.\n• **Step 1**: Identify given parameters, target variables, and physical units.\n• **Step 2**: Recall relevant formulas and laws from Class $grade NCERT textbook.\n• **Step 3**: Perform step-by-step algebraic substitution and verify dimensional consistency.',
      'formulas': ['NCERT Standard Formula Set'],
      'hasAudio': true,
      'source': 'offline_socratic_engine',
      'explainOptions': ['Real-World Analogy', 'Step-by-Step Math', 'Simpler Language', 'Visual Simulation'],
    };
  }
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
          .timeout(const Duration(seconds: 8));

      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        if (decoded is Map<String, dynamic> && decoded['answer'] != null) {
          return decoded;
        }
      }
    } catch (_) {
      // Auto-discover gateway in background for subsequent requests
      autoDiscoverGatewayUrl();
    }

    return OfflineSocraticEngine.generateResponse(
      question: question,
      topic: topic,
      grade: grade,
    );
  }

  // 8. Authenticate User with Gateway
  Future<Map<String, dynamic>> loginUser(String email, String password) async {
    final headers = {'Content-Type': 'application/json'};
    final response = await _client.post(
      Uri.parse('$baseUrl/api/auth/login'),
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
