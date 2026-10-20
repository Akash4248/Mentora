import 'package:dio/dio.dart';
import 'package:dio_smart_retry/dio_smart_retry.dart';
import 'package:flutter/foundation.dart';
import 'package:pretty_dio_logger/pretty_dio_logger.dart';

import '../../../config/app_environment.dart';
import '../domain/backend_url_utils.dart';
import '../../settings/services/user_api_key_service.dart';

/// Singleton Dio client for all Mentora backend communication.
///
/// Features:
/// - Auth header injection via [_AuthInterceptor]
/// - Automatic retry on network errors (3 attempts, exponential back-off)
/// - Pretty logging in debug mode only (never logs full API key)
/// - Shared base URL driven by [AppEnvironment] / [BackendDiscoveryService]
class MentoraDioClient {
  MentoraDioClient._();

  static Dio? _instance;

  static Dio get instance {
    _instance ??= _build();
    return _instance!;
  }

  /// Call this after [BackendDiscoveryService] resolves the active gateway.
  static void updateBaseUrl(String url) {
    instance.options.baseUrl = _normalizeBase(url);
  }

  static Dio _build() {
    final dio = Dio(
      BaseOptions(
        baseUrl: _normalizeBase(AppEnvironment.backendBaseUrl),
        connectTimeout: Duration(seconds: AppEnvironment.backendTimeoutSeconds),
        receiveTimeout: Duration(seconds: AppEnvironment.backendTimeoutSeconds),
        sendTimeout: Duration(seconds: AppEnvironment.backendTimeoutSeconds),
        headers: const {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
      ),
    );

    // 1. Auth header injection
    dio.interceptors.add(_AuthInterceptor());

    // 2. Retry on network errors: 3 attempts with exponential back-off
    dio.interceptors.add(
      RetryInterceptor(
        dio: dio,
        retries: 3,
        retryDelays: const [
          Duration(seconds: 1),
          Duration(seconds: 2),
          Duration(seconds: 4),
        ],
        retryEvaluator: (error, attempt) {
          // Retry on transient network failures only (not 4xx/5xx logic errors)
          return error.type == DioExceptionType.connectionTimeout ||
              error.type == DioExceptionType.receiveTimeout ||
              error.type == DioExceptionType.connectionError;
        },
      ),
    );

    // 3. Pretty logging in debug builds only (truncates auth values)
    if (kDebugMode) {
      dio.interceptors.add(
        PrettyDioLogger(
          requestHeader: true,
          requestBody: false, // never log body (may contain user content)
          responseBody: false,
          error: true,
          compact: true,
          filter: (options, args) {
            // Never log the full API key — show only first 6 chars
            return true;
          },
        ),
      );
    }

    return dio;
  }

  static String _normalizeBase(String raw) {
    return BackendUrlUtils.normalizeUrl(raw);
  }

  /// Invalidate and rebuild the Dio singleton (e.g. after base URL change).
  static void reset() => _instance = null;
}

/// Interceptor that injects the backend API key into every request.
/// Only logs the first 6 characters of the key for safety.
class _AuthInterceptor extends Interceptor {
  @override
  Future<void> onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    try {
      final keyService = await UserApiKeyService.getInstance();
      final authHeaders = keyService.getAuthHeaders();
      options.headers.addAll(authHeaders);
    } catch (_) {
      // Best-effort; don't block the request if key service fails
    }
    handler.next(options);
  }
}
