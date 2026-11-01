import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'config/ai_config.dart';

part 'api_client/auth.dart';
part 'api_client/notifications_alerts.dart';
part 'api_client/catalog.dart';
part 'api_client/builds.dart';
part 'api_client/ai_scans.dart';
part 'api_client/market_support.dart';
part 'api_client/chat.dart';

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
}
