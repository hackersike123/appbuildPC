import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'config/ai_config.dart';

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
  final productPowerByName = <String, int>{};
  final productRecommendedPsuByName = <String, int>{};
  final productPriceSourceByName = <String, String>{};
  http.Client Function() _clientFactory = () => http.Client();

  @visibleForTesting
  void setClientFactoryForTesting(http.Client Function() factory) {
    _clientFactory = factory;
  }

  String get baseUrl {
    const configuredUrl = String.fromEnvironment('API_BASE_URL');
    if (configuredUrl.isNotEmpty) return configuredUrl;
    if (kIsWeb) return 'http://localhost:3000';
    return 'http://localhost:3000';
  }

  Future<dynamic> _request(
    String method,
    String path, {
    Map<String, dynamic>? body,
    bool auth = false,
    Duration? timeout = const Duration(seconds: 30),
  }) async {
    final headers = <String, String>{'content-type': 'application/json'};
    if (auth && token != null) {
      headers['authorization'] = 'Bearer $token';
    }
    if (baseUrl.contains('ngrok')) {
      headers['ngrok-skip-browser-warning'] = 'true';
    }
    final request = http.Request(method, Uri.parse('$baseUrl$path'))
      ..headers.addAll(headers);
    if (body != null) request.body = jsonEncode(body);
    final client = _clientFactory();
    try {
      final response = timeout == null
          ? await client.send(request)
          : await client.send(request).timeout(timeout);
      final text = timeout == null
          ? await response.stream.bytesToString()
          : await response.stream.bytesToString().timeout(timeout);
      dynamic data;
      if (text.isNotEmpty) {
        try {
          data = jsonDecode(text);
        } on FormatException {
          throw ApiException(
            'API trả về dữ liệu không hợp lệ (HTTP ${response.statusCode}). '
            'Hãy kiểm tra URL backend và đường hầm ngrok.',
            statusCode: response.statusCode,
          );
        }
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        final message = data is Map
            ? data['message'] ?? data['error']
            : 'API request failed';
        throw ApiException(message.toString(), statusCode: response.statusCode);
      }
      return data;
    } finally {
      client.close();
    }
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

  Future<void> changePassword(
    String currentPassword,
    String newPassword,
  ) async {
    await _request(
      'POST',
      '/api/v1/auth/change-password',
      auth: true,
      body: {'currentPassword': currentPassword, 'newPassword': newPassword},
    );
  }

  Future<Map<String, dynamic>> me() async {
    final data = await _request('GET', '/api/v1/auth/me', auth: true);
    currentUser = Map<String, dynamic>.from(data as Map);
    return currentUser!;
  }

  Future<Map<String, dynamic>> updateProfile({
    String? name,
    String? areaId,
    String? avatarUrl,
    bool? pricePreference,
    bool? priceNotifications,
  }) async {
    final data = Map<String, dynamic>.from(
      await _request(
        'PUT',
        '/api/v1/auth/me',
        auth: true,
        body: {
          ...?name == null ? null : {'name': name},
          ...?areaId == null ? null : {'areaId': areaId},
          ...?avatarUrl == null ? null : {'avatarUrl': avatarUrl},
          ...?(pricePreference == null && priceNotifications == null)
              ? null
              : {
                  'preferences': {
                    ...?pricePreference == null
                        ? null
                        : {'pricePreference': pricePreference},
                    ...?priceNotifications == null
                        ? null
                        : {'priceNotifications': priceNotifications},
                  },
                },
        },
      ),
    );
    currentUser = data;
    return data;
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

  Future<List<Map<String, dynamic>>> priceAlerts() async {
    final data = await _request('GET', '/api/v1/price-alerts', auth: true);
    return (data as List)
        .map((item) => Map<String, dynamic>.from(item as Map))
        .toList();
  }

  Future<Map<String, dynamic>> createPriceAlert({
    required String productId,
    required int targetPrice,
    String? areaId,
  }) async {
    final data = await _request(
      'POST',
      '/api/v1/price-alerts',
      auth: true,
      body: {
        'productId': productId,
        'targetPrice': targetPrice,
        'areaId': areaId ?? currentUser?['areaId']?.toString() ?? 'hcm',
      },
    );
    return Map<String, dynamic>.from(data as Map);
  }

  Future<Map<String, dynamic>> updatePriceAlert({
    required String id,
    required String productId,
    required int targetPrice,
    required String areaId,
  }) async {
    final data = await _request(
      'PUT',
      '/api/v1/price-alerts/${Uri.encodeComponent(id)}',
      auth: true,
      body: {
        'productId': productId,
        'targetPrice': targetPrice,
        'areaId': areaId,
      },
    );
    return Map<String, dynamic>.from(data as Map);
  }

  Future<void> deletePriceAlert(String id) async {
    await _request(
      'DELETE',
      '/api/v1/price-alerts/${Uri.encodeComponent(id)}',
      auth: true,
    );
  }

  Future<List<Map<String, dynamic>>> products(
    String type, {
    String query = '',
    int? maxPrice,
    String? areaId,
  }) async {
    final params = <String, String>{
      'type': type,
      'areaId': areaId ?? currentUser?['areaId']?.toString() ?? 'hcm',
    };
    if (query.trim().isNotEmpty) params['q'] = query.trim();
    if (maxPrice != null) params['maxPrice'] = '$maxPrice';
    final data = await _request(
      'GET',
      '/api/v1/products?${params.entries.map((e) => '${Uri.encodeQueryComponent(e.key)}=${Uri.encodeQueryComponent(e.value)}').join('&')}',
    );
    return (data as List)
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
  }

  Future<Map<String, dynamic>> compareProducts(
    List<String> productIds, {
    String? areaId,
  }) async {
    if (productIds.length < 2 || productIds.length > 3) {
      throw ApiException('Cần chọn từ 2 đến 3 sản phẩm để so sánh.');
    }
    final data = await _request(
      'GET',
      '/api/v1/compare?productIds=${productIds.map(Uri.encodeQueryComponent).join(',')}&areaId=${Uri.encodeQueryComponent(areaId ?? currentUser?['areaId']?.toString() ?? 'hcm')}',
    );
    return Map<String, dynamic>.from(data as Map);
  }

  Future<List<Map<String, dynamic>>> areas() async {
    final data = await _request('GET', '/api/v1/areas');
    return (data as List)
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
  }

  Future<Map<String, dynamic>> resolveLocation({
    String? areaId,
    double? lat,
    double? lng,
  }) async {
    return Map<String, dynamic>.from(
      await _request(
        'POST',
        '/api/v1/location/resolve',
        body: {
          ...?areaId == null ? null : {'areaId': areaId},
          ...?lat == null ? null : {'lat': lat},
          ...?lng == null ? null : {'lng': lng},
        },
      ),
    );
  }

  Future<Map<String, dynamic>> marketSummary(String areaId) async {
    return Map<String, dynamic>.from(
      await _request(
        'GET',
        '/api/v1/market/summary?areaId=${Uri.encodeQueryComponent(areaId)}',
        auth: token != null,
      ),
    );
  }

  // Build generation uses SQL first; LM Studio is the API-side AI fallback.
  Future<Map<String, dynamic>> generateBuildSuggestion({
    required int budget,
    required String purpose,
    required String areaId,
    Map<String, String> pinnedComponents = const {},
    Duration timeout = const Duration(minutes: 2),
  }) async {
    return Map<String, dynamic>.from(
      await _request(
        'POST',
        '/api/v1/ai/generate-build',
        body: {
          'budget': budget,
          'purpose': purpose,
          'areaId': areaId,
          'pinnedComponents': pinnedComponents,
        },
        auth: true,
        timeout: timeout,
      ),
    );
  }

  Future<Map<String, dynamic>> createBuild({
    String name = 'Build mới',
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
    String? productId, {
    int? expectedVersion,
  }) async {
    if (buildId == null) await createBuild();
    final data = Map<String, dynamic>.from(
      await _request(
        'PUT',
        '/api/v1/builds/$buildId/components/${Uri.encodeComponent(type)}',
        auth: true,
        body: {
          'productId': productId,
          ...?expectedVersion == null
              ? null
              : {'expectedVersion': expectedVersion},
        },
      ),
    );
    buildId = data['id'] as String? ?? buildId;
    return data;
  }

  Future<Map<String, dynamic>> updateBuild(
    String id, {
    String? name,
    int? budget,
    String? areaId,
    int? expectedVersion,
  }) async {
    final body = <String, dynamic>{};
    if (name != null) body['name'] = name;
    if (budget != null) body['budget'] = budget;
    if (areaId != null) body['areaId'] = areaId;
    if (expectedVersion != null) body['expectedVersion'] = expectedVersion;
    final data = Map<String, dynamic>.from(
      await _request('PUT', '/api/v1/builds/$id', auth: true, body: body),
    );
    buildId = data['id'] as String? ?? buildId;
    return data;
  }

  Future<Map<String, dynamic>> duplicateBuild(String id, {String? name}) async {
    final data = Map<String, dynamic>.from(
      await _request(
        'POST',
        '/api/v1/builds/$id/duplicate',
        auth: true,
        body: {
          ...?name == null ? null : {'name': name},
        },
      ),
    );
    return data;
  }

  Future<Map<String, dynamic>> checkBuild(
    Map<String, String> components,
  ) async {
    final data = await _request(
      'POST',
      '/api/v1/compatibility/check',
      auth: true,
      body: {
        'components': components,
        'areaId': currentUser?['areaId']?.toString() ?? 'hcm',
      },
    );
    return Map<String, dynamic>.from(data);
  }

  Future<Map<String, dynamic>> createConversation({
    String? initialMessage,
  }) async {
    return Map<String, dynamic>.from(
      await _request(
        'POST',
        '/api/v1/conversations',
        auth: true,
        body: {
          ...?initialMessage == null || initialMessage.trim().isEmpty
              ? null
              : {'initialMessage': initialMessage.trim()},
        },
      ),
    );
  }

  Future<void> deleteConversation(String conversationId) async {
    await _request(
      'DELETE',
      '/api/v1/conversations/${Uri.encodeComponent(conversationId)}',
      auth: true,
    );
  }

  Future<Map<String, dynamic>> createScan({
    required List<String> candidateProductIds,
    Map<String, double> confidenceByProduct = const {},
  }) async {
    final data = await _request(
      'POST',
      '/api/v1/scans',
      auth: true,
      body: {
        'candidateProductIds': candidateProductIds,
        'confidenceByProduct': confidenceByProduct,
      },
    );
    return Map<String, dynamic>.from(data as Map);
  }

  Future<Map<String, dynamic>> analyzeProductImage({
    required Uint8List imageBytes,
    required String imageMimeType,
  }) async {
    final data = await _request(
      'POST',
      '/api/v1/ai/scan',
      auth: true,
      timeout: const Duration(minutes: 13),
      body: {
        'imageMimeType': imageMimeType,
        'imageBase64': base64Encode(imageBytes),
      },
    );
    return Map<String, dynamic>.from(data as Map);
  }

  Future<List<Map<String, dynamic>>> scans() async {
    final data = await _request('GET', '/api/v1/scans', auth: true);
    return (data as List)
        .map((item) => Map<String, dynamic>.from(item as Map))
        .toList();
  }

  Future<Map<String, dynamic>> scanDetails(String scanId) async {
    final data = await _request(
      'GET',
      '/api/v1/scans/${Uri.encodeComponent(scanId)}',
      auth: true,
    );
    return Map<String, dynamic>.from(data as Map);
  }

  Future<void> deleteScan(String scanId) async {
    await _request(
      'DELETE',
      '/api/v1/scans/${Uri.encodeComponent(scanId)}',
      auth: true,
    );
  }

  Future<Map<String, dynamic>> confirmScan(
    String scanId,
    String productId,
  ) async {
    final data = await _request(
      'POST',
      '/api/v1/scans/${Uri.encodeComponent(scanId)}/confirm',
      auth: true,
      body: {'productId': productId},
    );
    return Map<String, dynamic>.from(data as Map);
  }

  Future<Map<String, dynamic>> priceHistory(
    String productId, {
    String? areaId,
    String period = 'day',
  }) async {
    final resolvedAreaId =
        areaId ?? currentUser?['areaId']?.toString() ?? 'hcm';
    final data = await _request(
      'GET',
      '/api/v1/prices?productId=${Uri.encodeQueryComponent(productId)}&areaId=${Uri.encodeQueryComponent(resolvedAreaId)}&period=${Uri.encodeQueryComponent(period)}',
    );
    return Map<String, dynamic>.from(data as Map);
  }

  Future<List<Map<String, dynamic>>> faq({String query = ''}) async {
    final data = await _request(
      'GET',
      '/api/v1/faq?q=${Uri.encodeQueryComponent(query)}',
      auth: true,
    );
    return (data as List)
        .map((item) => Map<String, dynamic>.from(item as Map))
        .toList();
  }

  Future<Map<String, dynamic>> submitSupportRequest({
    required String message,
    String topic = 'general',
    String? contactEmail,
  }) async {
    final data = await _request(
      'POST',
      '/api/v1/support-requests',
      auth: true,
      body: {
        'message': message,
        'topic': topic,
        ...?contactEmail == null ? null : {'contactEmail': contactEmail},
      },
    );
    return Map<String, dynamic>.from(data as Map);
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
        timeout: const Duration(minutes: 11),
        body: {'message': message},
      ),
    );
  }

  Future<String> sendLmStudioMessage(
    String message, {
    List<Map<String, String>> history = const [],
    Duration timeout = const Duration(minutes: 5),
  }) async {
    if (!AIConfig.enabled) {
      throw ApiException('LM Studio đang bị tắt trong cấu hình ứng dụng.');
    }
    final messages = <Map<String, String>>[
      {
        'role': 'system',
        'content': 'Bạn là BuildMate AI, trợ lý tư vấn linh kiện PC. Trả lời bằng tiếng Việt, ngắn gọn và không bịa giá nếu không có dữ liệu.',
      },
      ...history.take(10),
      {'role': 'user', 'content': message},
    ];
    final text = await _request(
      'POST',
      '/api/v1/ai/chat',
      auth: true,
      body: {'messages': messages},
      timeout: timeout,
    );
    if (text is! Map ||
        text['choices'] is! List ||
        (text['choices'] as List).isEmpty) {
      throw ApiException('LM Studio không trả về nội dung trả lời hợp lệ.');
    }
    final content = (text['choices'][0] as Map)['message'];
    if (content is! Map || content['content'] is! String) {
      throw ApiException('LM Studio không trả về message content.');
    }
    return content['content'] as String;
  }
}
