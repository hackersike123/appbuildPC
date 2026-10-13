import 'package:flutter/material.dart';

import 'config/ai_config.dart';
import 'services/lm_studio_service.dart';

class AITestPage extends StatefulWidget {
  const AITestPage({super.key});

  @override
  State<AITestPage> createState() => _AITestPageState();
}

class _AITestPageState extends State<AITestPage> {
  final promptController = TextEditingController(
    text: 'Hãy giới thiệu khả năng của bạn bằng tiếng Việt.',
  );
  final ai = LMStudioService();
  String result = 'Chưa kết nối';
  String? modelId;
  bool loading = false;

  Future<void> connect() async {
    setState(() {
      loading = true;
      result = 'Đang kết nối...';
    });
    try {
      final models = await ai.getModels();
      if (models.isEmpty) {
        throw const LMStudioException('Không tìm thấy mô hình AI.');
      }
      setState(() {
        modelId = models.first;
        result = 'Kết nối thành công!\nModel: $modelId';
      });
    } catch (error) {
      setState(() => result = 'Lỗi kết nối:\n$error');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> askAI() async {
    if (modelId == null) await connect();
    if (!mounted || modelId == null) return;
    setState(() {
      loading = true;
      result = 'AI đang xử lý...';
    });
    try {
      final answer = await ai.chat(
        modelId: modelId!,
        prompt: promptController.text.trim(),
      );
      setState(() => result = answer);
    } catch (error) {
      setState(() => result = 'Lỗi AI:\n$error');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  void dispose() {
    promptController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Kiểm tra LM Studio')),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          'Endpoint: ${AIConfig.baseUrl}',
          style: const TextStyle(color: Colors.grey),
        ),
        const SizedBox(height: 12),
        ElevatedButton(
          onPressed: loading ? null : connect,
          child: const Text('1. Kiểm tra kết nối và model'),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: promptController,
          maxLines: 4,
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            labelText: 'Câu hỏi AI',
          ),
        ),
        const SizedBox(height: 12),
        ElevatedButton(
          onPressed: loading ? null : askAI,
          child: const Text('2. Gửi câu hỏi'),
        ),
        if (loading) const LinearProgressIndicator(),
        const SizedBox(height: 16),
        SelectableText(result),
      ],
    ),
  );
}
