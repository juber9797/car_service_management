import 'package:dio/dio.dart';
import 'package:car_workshop/core/constants/app_constants.dart';
import 'package:car_workshop/core/storage/secure_storage.dart';

class ApiClient {
  ApiClient(this._storage) {
    _dio = Dio(BaseOptions(
      baseUrl:        AppConstants.baseUrl,
      connectTimeout: AppConstants.connectTimeout,
      receiveTimeout: AppConstants.receiveTimeout,
      headers:        {'Content-Type': 'application/json'},
    ));

    _dio.interceptors.addAll([
      _AuthInterceptor(_storage, _dio),
      LogInterceptor(requestBody: true, responseBody: true),
    ]);
  }

  late final Dio _dio;
  final SecureStorageService _storage;

  // ── Auth ─────────────────────────────────────────────────────────────────
  Future<Map<String, dynamic>> login({
    required String email,
    required String password,
    required String garageId,
  }) async {
    final res = await _dio.post<Map<String, dynamic>>(
      '/auth/login',
      data: {'email': email, 'password': password},
      options: Options(headers: {'x-garage-id': garageId}),
    );
    return (res.data!['data'] as Map<String, dynamic>);
  }

  // ── Job Cards ────────────────────────────────────────────────────────────
  Future<List<dynamic>> getJobCards({
    String? status,
    int page = 1,
    int limit = 50,
  }) async {
    final res = await _dio.get<Map<String, dynamic>>(
      '/job-cards',
      queryParameters: {
        if (status != null) 'status': status,
        'page': page,
        'limit': limit,
      },
    );
    final data = res.data!['data'] as Map<String, dynamic>;
    return data['data'] as List<dynamic>;
  }

  Future<Map<String, dynamic>> updateJobCard(
      String id, Map<String, dynamic> body) async {
    final res = await _dio.patch<Map<String, dynamic>>('/job-cards/$id', data: body);
    return res.data!['data'] as Map<String, dynamic>;
  }

  // ── Tasks ────────────────────────────────────────────────────────────────
  Future<List<dynamic>> getTasksForJobCard(String jobCardId) async {
    final res = await _dio.get<Map<String, dynamic>>(
      '/tasks',
      queryParameters: {'jobCardId': jobCardId},
    );
    return res.data!['data'] as List<dynamic>;
  }

  Future<Map<String, dynamic>> updateTaskStatus(
      String taskId, Map<String, dynamic> body) async {
    final res = await _dio.patch<Map<String, dynamic>>('/tasks/$taskId/status', data: body);
    return res.data!['data'] as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> createTask(Map<String, dynamic> body) async {
    final res = await _dio.post<Map<String, dynamic>>('/tasks', data: body);
    return res.data!['data'] as Map<String, dynamic>;
  }

  // ── Dashboard ────────────────────────────────────────────────────────────
  Future<Map<String, dynamic>> getDashboard() async {
    final res = await _dio.get<Map<String, dynamic>>('/dashboard');
    return res.data!['data'] as Map<String, dynamic>;
  }

  // ── Invoices ─────────────────────────────────────────────────────────────
  Future<Map<String, dynamic>> generateInvoice(Map<String, dynamic> body) async {
    final res = await _dio.post<Map<String, dynamic>>('/invoices', data: body);
    return res.data!['data'] as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> getInvoice(String id) async {
    final res = await _dio.get<Map<String, dynamic>>('/invoices/$id');
    return res.data!['data'] as Map<String, dynamic>;
  }

  // ── Sync ─────────────────────────────────────────────────────────────────
  Future<Map<String, dynamic>> pushSync(Map<String, dynamic> body) async {
    final res = await _dio.post<Map<String, dynamic>>('/sync/push', data: body);
    return res.data!['data'] as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> pullSync({String? since}) async {
    final res = await _dio.get<Map<String, dynamic>>(
      '/sync/pull',
      queryParameters: {
        if (since != null) 'since': since,
        'entityTypes': 'job_cards,tasks',
      },
    );
    return res.data!['data'] as Map<String, dynamic>;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Auth interceptor: attaches Bearer token + x-garage-id to every request
// ─────────────────────────────────────────────────────────────────────────────
class _AuthInterceptor extends Interceptor {
  _AuthInterceptor(this._storage, this._dio);

  final SecureStorageService _storage;
  final Dio _dio;

  @override
  Future<void> onRequest(
      RequestOptions options, RequestInterceptorHandler handler) async {
    final token    = await _storage.getAccessToken();
    final garageId = await _storage.getGarageId();

    if (token != null) {
      options.headers['Authorization'] = 'Bearer $token';
    }
    if (garageId != null) {
      options.headers['x-garage-id'] = garageId;
    }
    handler.next(options);
  }

  @override
  Future<void> onError(DioException err, ErrorInterceptorHandler handler) async {
    if (err.response?.statusCode == 401) {
      // Token expired — attempt refresh
      try {
        final refresh = await _storage.getRefreshToken();
        if (refresh == null) return handler.next(err);

        final res = await _dio.post<Map<String, dynamic>>(
          '/auth/refresh',
          data: {'refreshToken': refresh},
          options: Options(headers: {'Authorization': ''}), // skip auth interceptor
        );

        final tokens = res.data!['data'] as Map<String, dynamic>;
        await _storage.saveTokens(
          accessToken:  tokens['accessToken'] as String,
          refreshToken: tokens['refreshToken'] as String,
        );

        // Retry original request
        err.requestOptions.headers['Authorization'] =
            'Bearer ${tokens['accessToken']}';
        final retry = await _dio.fetch<dynamic>(err.requestOptions);
        return handler.resolve(retry);
      } catch (_) {
        await _storage.clearAll();
      }
    }
    handler.next(err);
  }
}
