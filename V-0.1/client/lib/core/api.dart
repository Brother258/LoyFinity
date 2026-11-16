import 'package:dio/dio.dart';

typedef AccessTokenRefreshHandler = Future<String?> Function();

class ApiClient {
  ApiClient() : dio = Dio(BaseOptions(
    baseUrl: const String.fromEnvironment('API_BASE_URL', defaultValue: 'http://10.0.2.2:8082'),
    connectTimeout: const Duration(seconds: 8),
    receiveTimeout: const Duration(seconds: 12),
    sendTimeout: const Duration(seconds: 12),
    headers: {'Accept': 'application/json', 'Content-Type': 'application/json'},
  )) {
    dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) {
        final token = accessToken;
        if (token != null && token.isNotEmpty) options.headers['Authorization'] = 'Bearer $token';
        handler.next(options);
      },
      onError: (error, handler) async {
        final options = error.requestOptions;
        final isRefreshRequest = options.path.endsWith('/auth/refresh');
        final alreadyRetried = options.extra['loyfinityRetried'] == true;
        if (error.response?.statusCode != 401 || isRefreshRequest || alreadyRetried || _refreshHandler == null) {
          handler.next(error);
          return;
        }
        try {
          final newToken = await _refreshHandler!();
          if (newToken == null || newToken.isEmpty) {
            handler.next(error);
            return;
          }
          options.extra['loyfinityRetried'] = true;
          options.headers['Authorization'] = 'Bearer $newToken';
          final response = await dio.fetch<dynamic>(options);
          handler.resolve(response);
        } catch (_) {
          handler.next(error);
        }
      },
    ));
  }

  final Dio dio;
  String? accessToken;
  AccessTokenRefreshHandler? _refreshHandler;

  void setRefreshHandler(AccessTokenRefreshHandler handler) {
    _refreshHandler = handler;
  }

  Future<Map<String, dynamic>> get(String path, {Map<String, dynamic>? query}) async {
    final response = await dio.get<dynamic>(_apiPath(path), queryParameters: query);
    return _map(response.data);
  }

  Future<Map<String, dynamic>> post(String path, {Object? data}) async {
    final response = await dio.post<dynamic>(_apiPath(path), data: data ?? <String, dynamic>{});
    return _map(response.data);
  }

  Future<Map<String, dynamic>> patch(String path, {Object? data}) async {
    final response = await dio.patch<dynamic>(_apiPath(path), data: data ?? <String, dynamic>{});
    return _map(response.data);
  }

  Future<void> delete(String path) async {
    await dio.delete<dynamic>(_apiPath(path));
  }

  String _apiPath(String path) => '/v1${path.startsWith('/') ? path : '/$path'}';

  Map<String, dynamic> _map(dynamic data) {
    if (data is Map<String, dynamic>) return data;
    if (data is Map) return data.map((key, value) => MapEntry(key.toString(), value));
    return <String, dynamic>{};
  }

  String messageFrom(Object error) {
    if (error is DioException) {
      final data = error.response?.data;
      if (data is Map && data['message'] is String) return data['message'] as String;
      if (error.type == DioExceptionType.connectionTimeout || error.type == DioExceptionType.connectionError) {
        return 'Could not connect. Check your internet connection and try again.';
      }
      if (error.response?.statusCode == 401) return 'Your session expired. Please sign in again.';
      return 'Something went wrong. Please try again.';
    }
    return 'Something went wrong. Please try again.';
  }
}
