part of '../api_client.dart';

extension ApiClientAiEndpoints on ApiClient {
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
}
