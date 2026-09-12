import '../../../config/app_environment.dart';

/// Dynamically builds API endpoints from the nginx gateway base URL.
/// 
/// All endpoints are generated ONLY from BACKEND_BASE_URL.
/// No hardcoded ports (:8000, :8001, :8010, :8020, :6333).
/// 
/// Example:
/// ```dart
/// final endpoints = EndpointBuilder.fromEnvironment();
/// final chatUrl = endpoints.aiChat;  // http://10.28.73.193/ai/chat
/// final tutorUrl = endpoints.aiTutor;  // http://10.28.73.193/ai/tutor
/// final searchUrl = endpoints.ragSearch;  // http://10.28.73.193/rag/search
/// ```
class EndpointBuilder {
  final String baseUrl;

  EndpointBuilder({required this.baseUrl});

  /// Create endpoints from centralized environment configuration.
  static EndpointBuilder fromEnvironment() {
    final baseUrl = AppEnvironment.backendBaseUrl;
    AppEnvironment.log(
      'BACKEND',
      'Endpoint builder initialized with base URL: $baseUrl',
    );
    return EndpointBuilder(baseUrl: baseUrl);
  }

  // ===== AI Service Endpoints =====
  
  /// POST /ai/chat - General chat endpoint
  String get aiChat => '$baseUrl/ai/chat';

  /// POST /ai/tutor - Educational tutor endpoint
  String get aiTutor => '$baseUrl/ai/tutor';

  /// POST /ai/summarize - Summarization endpoint
  String get aiSummarize => '$baseUrl/ai/summarize';

  // ===== RAG Service Endpoints =====

  /// POST /rag/search - Semantic search endpoint
  String get ragSearch => '$baseUrl/rag/search';

  /// POST /rag/index - Indexing endpoint
  String get ragIndex => '$baseUrl/rag/index';

  /// POST /rag/query - RAG query endpoint
  String get ragQuery => '$baseUrl/rag/query';

  // ===== Health & Status Endpoints =====

  /// GET /health - Health check endpoint
  String get health => '$baseUrl/health';

  /// GET /health/detailed - Detailed health information
  String get healthDetailed => '$baseUrl/health/detailed';

  /// GET /status - Service status endpoint
  String get status => '$baseUrl/status';

  // ===== Content Management Endpoints =====

  /// POST /upload - File upload endpoint
  String get upload => '$baseUrl/upload';

  /// POST /ingest/directory - Batch directory ingestion endpoint
  String get ingestDirectory => '$baseUrl/ingest/directory';

  /// POST /ingest/validate - Validate ingest operation
  String get ingestValidate => '$baseUrl/ingest/validate';

  // ===== Educational Pack & Catalog Endpoints =====
  
  /// GET /packs/catalog - List available subjects & catalog
  String get catalogSubjects => '$baseUrl/packs/catalog';

  /// GET /packs/catalog - List available chapters & catalog
  String get catalogChapters => '$baseUrl/packs/catalog';

  /// GET /packs/list - List available educational packs
  String get packsList => '$baseUrl/packs';

  /// GET /packs/catalog - Educational pack catalog
  String get packsCatalog => '$baseUrl/packs/catalog';

  /// GET /packs/recommended - Recommended adjacent packs
  String get packsRecommended => '$baseUrl/packs/recommended';

  /// POST /packs/sync - Sync educational packs
  String get packsSync => '$baseUrl/packs/sync';

  /// GET /packs/download - Download educational pack
  String get packsDownload => '$baseUrl/packs';

  /// POST /packs/validate - Validate pack integrity
  String get packsValidate => '$baseUrl/packs/validate';

  // ===== Classroom Endpoints =====

  /// POST /classroom/register - Register device in classroom
  String get classroomRegister => '$baseUrl/classroom/register';

  /// GET /classroom/devices - List classroom devices
  String get classroomDevices => '$baseUrl/classroom/devices';

  /// POST /classroom/sync - Sync classroom state
  String get classroomSync => '$baseUrl/classroom/sync';

  // ===== Curriculum Endpoints =====

  /// GET /packs/catalog - List available grades
  String get curriculumGrades => '$baseUrl/packs/catalog';

  /// GET /packs/catalog - List subjects for grade
  String get curriculumSubjects => '$baseUrl/packs/catalog';

  /// GET /packs/catalog - List chapters for subject
  String get curriculumChapters => '$baseUrl/packs/catalog';

  /// GET /packs/catalog - List concepts for chapter
  String get curriculumConcepts => '$baseUrl/packs/catalog';

  /// GET /packs/catalog - Get detailed curriculum content
  String get curriculumContent => '$baseUrl/packs/catalog';


  // ===== Assessment Endpoints =====

  /// POST /assessment/quiz - Submit quiz responses
  String get assessmentQuiz => '$baseUrl/assessment/quiz';

  /// GET /assessment/results - Get assessment results
  String get assessmentResults => '$baseUrl/assessment/results';

  /// POST /assessment/flashcards - Get flashcard data
  String get assessmentFlashcards => '$baseUrl/assessment/flashcards';

  // ===== Progress Tracking Endpoints =====

  /// POST /progress/update - Update learner progress
  String get progressUpdate => '$baseUrl/progress/update';

  /// GET /progress/report - Get progress report
  String get progressReport => '$baseUrl/progress/report';

  /// POST /progress/sync - Sync progress with backend
  String get progressSync => '$baseUrl/progress/sync';

  // ===== Discovery & Metadata Endpoints =====

  /// GET /metadata/schema - Get API schema/metadata
  String get metadataSchema => '$baseUrl/metadata/schema';

  /// GET /config/public - Get public configuration
  String get configPublic => '$baseUrl/config/public';

  // ===== Offline-First Sync Endpoints =====

  /// POST /sync/delta - Get delta updates for offline sync
  String get syncDelta => '$baseUrl/sync/delta';

  /// POST /sync/validate - Validate local cache against server
  String get syncValidate => '$baseUrl/sync/validate';

  /// POST /sync/resolve - Resolve sync conflicts
  String get syncResolve => '$baseUrl/sync/resolve';

  @override
  String toString() => 'EndpointBuilder(baseUrl=$baseUrl)';
}
