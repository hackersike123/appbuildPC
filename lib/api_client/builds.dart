part of '../api_client.dart';

extension ApiClientBuildEndpoints on ApiClient {
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
}
