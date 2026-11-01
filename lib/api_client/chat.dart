part of '../api_client.dart';

extension ApiClientChatEndpoints on ApiClient {
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
