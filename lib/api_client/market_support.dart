part of '../api_client.dart';

extension ApiClientMarketEndpoints on ApiClient {
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
}
