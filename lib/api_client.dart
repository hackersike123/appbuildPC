import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class ApiException implements Exception {
  ApiException(this.message, {this.statusCode});
  final String message;
  final int? statusCode;
  @override
  String toString() => message;
}

class ApiClient {
  ApiClient._();
  static final instance = ApiClient._();
  String? token;
  Map<String, dynamic>? currentUser;
  String? buildId;
  final productIdsByName = <String, String>{};

  String get baseUrl {
    const configuredUrl = String.fromEnvironment('API_BASE_URL');
    if (configuredUrl.isNotEmpty) return configuredUrl;
    if (kIsWeb) return 'http://localhost:3000';
    if (defaultTargetPlatform == TargetPlatform.android) {
      return 'http://10.0.2.2:3000';
    }
    return 'http://localhost:3000';
  }

  Future<dynamic> _request(
    String method,
    String path, {
    Map<String, dynamic>? body,
    bool auth = false,
  }) async {
    final headers = <String, String>{'content-type': 'application/json'};
    if (auth && token != null) {
      headers['authorization'] = 'Bearer ${token!}';
    }
    final request = http.Request(method, Uri.parse('$baseUrl$path'))
      ..headers.addAll(headers);
    if (body != null) request.body = jsonEncode(body);
    final response = await http.Client()
        .send(request)
        .timeout(const Duration(seconds: 8));
    final text = await response.stream.bytesToString();
    final data = text.isEmpty ? null : jsonDecode(text);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final message = data is Map
          ? data['message'] ?? data['error']
          : 'API request failed';
      throw ApiException(message.toString(), statusCode: response.statusCode);
    }
    return data;
  }

  Future<Map<String, dynamic>> login(String email, String password) async {
    final data = Map<String, dynamic>.from(
      await _request(
        'POST',
        '/api/v1/auth/login',
        body: {'email': email, 'password': password},
      ),
    );
    token = data['accessToken'] as String?;
    currentUser = data['user'] is Map
        ? Map<String, dynamic>.from(data['user'] as Map)
        : null;
    return data;
  }

  Future<Map<String, dynamic>> register(
    String name,
    String email,
    String password, {
    String areaId = 'hcm',
  }) async {
    return Map<String, dynamic>.from(
      await _request(
        'POST',
        '/api/v1/auth/register',
        body: {
          'name': name,
          'email': email,
          'password': password,
          'areaId': areaId,
        },
      ),
    );
  }

  Future<Map<String, dynamic>> forgotPassword(String email) async {
    return Map<String, dynamic>.from(
      await _request(
        'POST',
        '/api/v1/auth/forgot-password',
        body: {'email': email},
      ),
    );
  }

  Future<Map<String, dynamic>> resetPassword(
    String token,
    String password,
  ) async {
    return Map<String, dynamic>.from(
      await _request(
        'POST',
        '/api/v1/auth/reset-password',
        body: {'token': token, 'password': password},
      ),
    );
  }

  Future<Map<String, dynamic>> me() async {
    final data = await _request('GET', '/api/v1/auth/me', auth: true);
    currentUser = Map<String, dynamic>.from(data as Map);
    return currentUser!;
  }

  void logout() {
    token = null;
    currentUser = null;
    buildId = null;
  }

  Future<List<Map<String, dynamic>>> notifications() async {
    final data = await _request('GET', '/api/v1/notifications', auth: true);
    return (data as List)
        .map((item) => Map<String, dynamic>.from(item as Map))
        .toList();
  }

  Future<void> markNotificationsRead() async {
    await _request('POST', '/api/v1/notifications/read', auth: true);
  }

  Future<List<Map<String, dynamic>>> products(String type) async {
    final data = await _request(
      'GET',
      '/api/v1/products?type=${Uri.encodeQueryComponent(type)}',
    );
    return (data as List)
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
  }

  Future<List<Map<String, dynamic>>> areas() async {
    final data = await _request('GET', '/api/v1/areas');
    return (data as List)
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
  }

  Future<Map<String, dynamic>> resolveLocation({String? areaId}) async {
    return Map<String, dynamic>.from(
      await _request(
        'POST',
        '/api/v1/location/resolve',
        body: areaId == null ? {} : {'areaId': areaId},
      ),
    );
  }

  Future<Map<String, dynamic>> marketSummary(String areaId) async {
    return Map<String, dynamic>.from(
      await _request('GET', '/api/v1/market/summary?areaId=$areaId'),
    );
  }

  Future<Map<String, dynamic>> createBuild({
    String name = 'Gaming 20 triệu',
    int budget = 20000000,
    String areaId = 'hcm',
  }) async {
    final data = Map<String, dynamic>.from(
      await _request(
        'POST',
        '/api/v1/builds',
        auth: true,
        body: {'name': name, 'budget': budget, 'areaId': areaId},
      ),
    );
    buildId = data['id'] as String?;
    return data;
  }

  Future<List<Map<String, dynamic>>> builds() async {
    final data = await _request('GET', '/api/v1/builds', auth: true);
    return (data as List)
        .map((item) => Map<String, dynamic>.from(item as Map))
        .toList();
  }

  Future<Map<String, dynamic>> getBuild(String id) async {
    return Map<String, dynamic>.from(
      await _request('GET', '/api/v1/builds/$id', auth: true),
    );
  }

  Future<void> deleteBuild(String id) async {
    await _request('DELETE', '/api/v1/builds/$id', auth: true);
    if (buildId == id) buildId = null;
  }

  Future<Map<String, dynamic>> updateComponent(
    String type,
    String? productId,
  ) async {
    if (buildId == null) await createBuild();
    final data = Map<String, dynamic>.from(await _request(
      'PUT',
      '/api/v1/builds/$buildId/components/${Uri.encodeComponent(type)}',
      auth: true,
      body: {'productId': productId},
    ));
    buildId = data['id'] as String? ?? buildId;
    return data;
  }

  Future<Map<String, dynamic>> updateBuild(
    String id, {
    String? name,
    int? budget,
    String? areaId,
  }) async {
    final body = <String, dynamic>{};
    if (name != null) body['name'] = name;
    if (budget != null) body['budget'] = budget;
    if (areaId != null) body['areaId'] = areaId;
    final data = Map<String, dynamic>.from(
      await _request(
        'PUT',
        '/api/v1/builds/$id',
        auth: true,
        body: body,
      ),
    );
    buildId = data['id'] as String? ?? buildId;
    return data;
  }

  Future<Map<String, dynamic>> checkBuild(
    Map<String, String> components,
  ) async {
    final data = await _request(
      'POST',
      '/api/v1/compatibility/check',
      auth: true,
      body: {'components': components},
    );
    return Map<String, dynamic>.from(data);
  }

  Future<Map<String, dynamic>> createConversation() async {
    return Map<String, dynamic>.from(
      await _request('POST', '/api/v1/conversations', auth: true),
    );
  }

  Future<Map<String, dynamic>> sendMessage(
    String conversationId,
    String message,
  ) async {
    return Map<String, dynamic>.from(
      await _request(
        'POST',
        '/api/v1/conversations/$conversationId/messages',
        auth: true,
        body: {'message': message},
      ),
    );
  }
}
