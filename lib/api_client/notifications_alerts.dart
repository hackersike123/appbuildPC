part of '../api_client.dart';

extension ApiClientNotificationEndpoints on ApiClient {
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
}
