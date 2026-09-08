import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/platform_tutor_inference_gateway.dart';
import '../data/tutor_inference_gateway.dart';
import '../../rag/data/local/rag_repository.dart';
import '../data/local/chat_session_repository.dart';
import '../data/local/chat_memory_policy_repository.dart';

final tutorInferenceGatewayProvider = Provider<TutorInferenceGateway>((ref) {
  return PlatformTutorInferenceGateway();
});

final ragRepositoryProvider = Provider<RagRepository>((ref) {
  return RagRepository();
});

final chatSessionRepositoryProvider = Provider<ChatSessionRepository>((ref) {
  return ChatSessionRepository();
});

final chatMemoryPolicyRepositoryProvider = Provider<ChatMemoryPolicyRepository>((ref) {
  return ChatMemoryPolicyRepository();
});
