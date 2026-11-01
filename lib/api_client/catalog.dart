part of '../api_client.dart';

extension ApiClientCatalogEndpoints on ApiClient {
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
}
