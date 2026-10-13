import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../config/ai_config.dart';

class LMStudioException implements Exception {
  const LMStudioException(this.message);
  final String message;

  @override
  String toString() => message;
}

class LMStudioService {
  LMStudioService({String? baseUrl, String? apiToken})
    : baseUrl = (baseUrl ?? AIConfig.baseUrl).replaceAll(RegExp(r'/$'), ''),
      apiToken = apiToken ?? AIConfig.apiKey;

  final String baseUrl;
  final String apiToken;

  Map<String, String> get headers => {
    'content-type': 'application/json',
    if (apiToken.isNotEmpty) 'authorization': 'Bearer $apiToken',
  };

  Future<List<String>> getModels() async {
    final response = await http
        .get(Uri.parse('$baseUrl/models'), headers: headers)
        .timeout(const Duration(seconds: 15));
    final data = _decode(response);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw LMStudioException(
        'LM Studio HTTP ${response.statusCode}: ${_errorMessage(data)}',
      );
    }
    final models = data is Map ? data['data'] : null;
    if (models is! List) {
      throw const LMStudioException(
        'LM Studio không trả về danh sách model hợp lệ.',
      );
    }
    return models
        .whereType<Map>()
        .map((model) => model['id']?.toString() ?? '')
        .where((id) => id.isNotEmpty)
        .toList();
  }

  Future<String> chat({
    required String modelId,
    required String prompt,
    Uint8List? imageBytes,
    String imageMimeType = 'image/jpeg',
  }) async {
    final content = <Map<String, dynamic>>[
      {'type': 'text', 'text': prompt},
    ];
    if (imageBytes != null) {
      content.add({
        'type': 'image_url',
        'image_url': <String, String>{
          'url': 'data:$imageMimeType;base64,${base64Encode(imageBytes)}',
        },
      });
    }

    final response = await http
        .post(
          Uri.parse('$baseUrl/chat/completions'),
          headers: headers,
          body: jsonEncode({
            'model': modelId,
            'messages': [
              {
                'role': 'user',
                'content': imageBytes == null ? prompt : content,
              },
            ],
            'temperature': 0.2,
            'max_tokens': 1200,
            'stream': false,
          }),
        )
        .timeout(const Duration(minutes: 5));
    final data = _decode(response);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw LMStudioException(
        'LM Studio HTTP ${response.statusCode}: ${_errorMessage(data)}',
      );
    }
    final choices = data is Map ? data['choices'] : null;
    final message = choices is List && choices.isNotEmpty
        ? choices.first is Map
              ? choices.first['message']
              : null
        : null;
    final answer = message is Map ? message['content'] : null;
    if (answer is! String || answer.trim().isEmpty) {
      throw const LMStudioException(
        'LM Studio không trả về nội dung trả lời hợp lệ.',
      );
    }
    return answer;
  }

  dynamic _decode(http.Response response) {
    if (response.bodyBytes.isEmpty) return null;
    try {
      return jsonDecode(utf8.decode(response.bodyBytes));
    } on FormatException {
      return response.body;
    }
  }

  String _errorMessage(dynamic data) {
    if (data is Map && data['error'] is Map) {
      return (data['error']['message'] ?? data['error']['type']).toString();
    }
    return data?.toString() ?? 'Phản hồi trống';
  }
}
