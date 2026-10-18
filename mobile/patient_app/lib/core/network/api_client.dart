import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config/app_config.dart';
import '../errors/failures.dart';

class ApiClient {
  final http.Client client;
  final String? Function()? tokenProvider;

  ApiClient({
    http.Client? client,
    this.tokenProvider,
  }) : client = client ?? http.Client();

  Map<String, String> _buildHeaders([Map<String, String>? extra]) {
    final headers = <String, String>{
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    };
    final token = tokenProvider?.call();
    if (token != null && token.isNotEmpty) {
      headers['Authorization'] = 'Bearer $token';
    }
    if (extra != null) {
      headers.addAll(extra);
    }
    return headers;
  }

  Uri _buildUri(String path, [Map<String, dynamic>? queryParams]) {
    final base = AppConfig.apiBaseUrl;
    final url = path.startsWith('http') ? path : '$base$path';
    final parsed = Uri.parse(url);
    if (queryParams != null && queryParams.isNotEmpty) {
      final query = Map<String, dynamic>.from(parsed.queryParameters);
      queryParams.forEach((key, value) {
        if (value != null) {
          query[key] = value.toString();
        }
      });
      return parsed.replace(queryParameters: query);
    }
    return parsed;
  }

  dynamic _handleResponse(http.Response response) {
    if (response.statusCode == 204) {
      return null;
    }

    dynamic decoded;
    try {
      decoded = jsonDecode(utf8.decode(response.bodyBytes));
    } catch (_) {
      throw ApiException(
        statusCode: response.statusCode,
        code: 'INVALID_JSON',
        message: 'Invalid response from server (${response.statusCode})',
      );
    }

    if (response.statusCode >= 200 && response.statusCode < 300) {
      if (decoded is Map<String, dynamic> && decoded.containsKey('data')) {
        return decoded['data'];
      }
      return decoded;
    }

    // Error envelope: { "success": false, "error": { "code": "...", "message": "...", "details": [] } }
    if (decoded is Map<String, dynamic> && decoded['error'] is Map<String, dynamic>) {
      final err = decoded['error'] as Map<String, dynamic>;
      throw ApiException(
        statusCode: response.statusCode,
        code: err['code']?.toString() ?? 'API_ERROR',
        message: err['message']?.toString() ?? 'An unexpected error occurred',
        details: err['details'],
      );
    }

    throw ApiException(
      statusCode: response.statusCode,
      code: 'API_ERROR',
      message: 'Request failed with status ${response.statusCode}',
    );
  }

  Future<dynamic> get(
    String path, {
    Map<String, dynamic>? queryParams,
    Map<String, String>? headers,
  }) async {
    final uri = _buildUri(path, queryParams);
    try {
      final response = await client
          .get(uri, headers: _buildHeaders(headers))
          .timeout(const Duration(seconds: 15));
      return _handleResponse(response);
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiException(
        statusCode: 0,
        code: 'NETWORK_ERROR',
        message: 'Could not connect to server: ${e.toString()}',
      );
    }
  }

  Future<dynamic> post(
    String path,
    dynamic body, {
    Map<String, String>? headers,
  }) async {
    final uri = _buildUri(path);
    try {
      final response = await client
          .post(
            uri,
            headers: _buildHeaders(headers),
            body: jsonEncode(body ?? {}),
          )
          .timeout(const Duration(seconds: 15));
      return _handleResponse(response);
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiException(
        statusCode: 0,
        code: 'NETWORK_ERROR',
        message: 'Could not connect to server: ${e.toString()}',
      );
    }
  }

  Future<dynamic> put(
    String path,
    dynamic body, {
    Map<String, String>? headers,
  }) async {
    final uri = _buildUri(path);
    try {
      final response = await client
          .put(
            uri,
            headers: _buildHeaders(headers),
            body: jsonEncode(body ?? {}),
          )
          .timeout(const Duration(seconds: 15));
      return _handleResponse(response);
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiException(
        statusCode: 0,
        code: 'NETWORK_ERROR',
        message: 'Could not connect to server: ${e.toString()}',
      );
    }
  }

  Future<dynamic> patch(String path, dynamic body) async {
    final uri = _buildUri(path);
    try {
      final response = await client
          .patch(
            uri,
            headers: _buildHeaders(),
            body: jsonEncode(body ?? {}),
          )
          .timeout(const Duration(seconds: 15));
      return _handleResponse(response);
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiException(
        statusCode: 0,
        code: 'NETWORK_ERROR',
        message: 'Could not connect to server: ${e.toString()}',
      );
    }
  }

  Future<dynamic> delete(String path, [dynamic body]) async {
    final uri = _buildUri(path);
    try {
      final response = await client
          .delete(
            uri,
            headers: _buildHeaders(),
            body: body != null ? jsonEncode(body) : null,
          )
          .timeout(const Duration(seconds: 15));
      return _handleResponse(response);
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiException(
        statusCode: 0,
        code: 'NETWORK_ERROR',
        message: 'Could not connect to server: ${e.toString()}',
      );
    }
  }
}
