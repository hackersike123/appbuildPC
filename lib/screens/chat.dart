part of '../main.dart';

class ChatTab extends StatefulWidget {
  const ChatTab({
    super.key,
    this.initialPrompt,
    this.initialPinnedComponents = const {},
    this.responseTimeout = const Duration(minutes: 11),
    this.onOpenBuild,
  });
  final String? initialPrompt;
  final Map<String, String> initialPinnedComponents;
  final Duration responseTimeout;
  final VoidCallback? onOpenBuild;
  @override
  State<ChatTab> createState() => _ChatTabState();
}

class _ChatTabState extends State<ChatTab> {
  final question = TextEditingController();
  final messages = <Map<String, String>>[];
  String? conversationId;
  late Future<void> conversationReady;
  bool sending = false;
  String? sendError;

  @override
  void initState() {
    super.initState();
    if (widget.initialPrompt != null && widget.initialPrompt!.isNotEmpty) {
      messages.add({'role': 'assistant', 'text': widget.initialPrompt!});
    }
    conversationReady = _startConversation();
  }

  Future<void> _startConversation() async {
    if (ApiClient.instance.token == null) return;
    try {
      final conversation = await ApiClient.instance.createConversation(
        initialMessage: widget.initialPrompt,
      );
      if (mounted) {
        setState(() => conversationId = conversation['id'] as String?);
      }
    } catch (_) {
      // Sending still works through the stateless AI endpoint if SQL history
      // cannot be created for this conversation.
    }
  }

  Future<void> _clearConversation() async {
    await conversationReady;
    final currentConversationId = conversationId;
    if (currentConversationId != null) {
      try {
        await ApiClient.instance.deleteConversation(currentConversationId);
      } catch (error) {
        if (mounted) {
          setState(() => sendError = 'Không thể xóa cuộc trò chuyện: $error');
        }
        return;
      }
    }
    if (!mounted) return;
    setState(() {
      conversationId = null;
      messages.clear();
      sendError = null;
    });
    conversationReady = _startConversation();
    await conversationReady;
  }

  @override
  void dispose() {
    question.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Shell(
    title: 'BuildMate AI',
    subtitle: '● Trực tuyến • hiểu giá địa phương',
    action: TextButton(
      onPressed: sending ? null : _clearConversation,
      child: const Text('Xóa', style: TextStyle(color: mint)),
    ),
    child: SafeArea(
      child: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(18, 8, 18, 8),
              children: [
                if (messages.isEmpty)
                  const ChatBubble(
                    text:
                        'Chào bạn! Hãy hỏi về linh kiện, giá hoặc tương thích.',
                    dark: true,
                  ),
                Wrap(
                  spacing: 6,
                  children: [
                    _SuggestionChip(
                      text: 'GPU dưới 10 triệu',
                      onTap: sending
                          ? null
                          : () => _useSuggestion('GPU dưới 10 triệu'),
                    ),
                    _SuggestionChip(
                      text: 'Build gaming 20 triệu',
                      onTap: sending
                          ? null
                          : () => _useSuggestion('Build gaming 20 triệu'),
                    ),
                    _SuggestionChip(
                      text: 'So sánh hàng cũ/mới',
                      onTap: sending
                          ? null
                          : () => _useSuggestion('So sánh hàng cũ/mới'),
                    ),
                  ],
                ),
                ...messages.map(
                  (message) => ChatBubble(
                    text: message['text']!,
                    dark: message['role'] == 'assistant',
                  ),
                ),
                if (sending)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                        SizedBox(width: 10),
                        Text('Đang chờ BuildMate trả lời…'),
                      ],
                    ),
                  ),
                if (sendError != null)
                  CardBox(
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            sendError!,
                            style: const TextStyle(color: Colors.amber),
                          ),
                        ),
                        TextButton.icon(
                          onPressed: sending ? null : _retryLastMessage,
                          icon: const Icon(Icons.refresh),
                          label: const Text('Thử lại'),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 6, 18, 10),
            child: TextField(
              controller: question,
              enabled: !sending,
              onSubmitted: (_) => _send(context),
              decoration: InputDecoration(
                hintText: 'Hỏi về linh kiện, giá, tương thích...',
                suffixIcon: IconButton(
                  onPressed: sending ? null : () => _send(context),
                  icon: Container(
                    padding: const EdgeInsets.all(7),
                    decoration: BoxDecoration(
                      color: mint,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.arrow_forward, color: bg),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    ),
  );

  Future<void> _send(BuildContext context) async {
    if (sending) return;
    final text = question.text.trim();
    if (text.isEmpty) {
      showDemoMessage(context, 'Hãy nhập câu hỏi trước khi gửi.');
      return;
    }
    question.clear();
    setState(() {
      messages.add({'role': 'user', 'text': text});
      sendError = null;
      sending = true;
    });
    await _processRequest(text);
  }

  Future<void> _retryLastMessage() async {
    if (sending || messages.isEmpty || messages.last['role'] != 'user') return;
    setState(() {
      sendError = null;
      sending = true;
    });
    await _processRequest(messages.last['text']!);
  }

  Future<void> _processRequest(String text) async {
    if (_isBuildRequest(text)) {
      try {
        await _createBuildFromChat(text);
      } catch (error) {
        if (mounted) {
          setState(() => sendError = 'Không tạo được build từ SQL: $error');
        }
      } finally {
        if (mounted) setState(() => sending = false);
      }
      return;
    }
    await _requestAnswer(text);
  }

  Future<void> _requestAnswer(String text) async {
    try {
      if (ApiClient.instance.token != null) {
        await conversationReady;
        if (conversationId == null) {
          conversationReady = _startConversation();
          await conversationReady;
        }
        if (conversationId == null) {
          throw ApiException(
            'Không tạo được hội thoại trong SQL. Kiểm tra kết nối rồi thử lại.',
          );
        }
      }
      final String answer;
      if (conversationId != null) {
        final response = await ApiClient.instance.sendMessage(
          conversationId!,
          text,
        );
        final choices = response['choices'];
        final firstChoice = choices is List && choices.isNotEmpty
            ? choices.first
            : null;
        final message = firstChoice is Map ? firstChoice['message'] : null;
        final content = message is Map ? message['content'] : null;
        if (content is! String || content.trim().isEmpty) {
          throw ApiException('BuildMate không trả về nội dung hợp lệ.');
        }
        answer = content;
      } else {
        answer = await ApiClient.instance.sendLmStudioMessage(
          text,
          history: messages
              .take(messages.length - 1)
              .map(
                (message) => {
                  'role': message['role']!,
                  'content': message['text']!,
                },
              )
              .toList(),
          timeout: widget.responseTimeout,
        );
      }
      if (mounted) {
        setState(() => messages.add({'role': 'assistant', 'text': answer}));
      }
      if (_isBuildRequest(text) && mounted) {
        try {
          await _createBuildFromChat(text);
        } catch (error) {
          if (mounted) {
            showDemoMessage(context, 'Chưa tạo được cấu hình: $error');
          }
        }
      }
    } catch (error) {
      if (mounted) {
        setState(() => sendError = 'Không nhận được phản hồi: $error');
      }
    } finally {
      if (mounted) setState(() => sending = false);
    }
  }

  bool _isBuildRequest(String text) {
    final normalized = text.toLowerCase();
    final explicitBuildPhrases = <String>[
      'build pc gaming',
      'build gaming',
      'build game',
      'build theo',
      'build với',
      'build voi',
      'build từ',
      'build tu',
      'build dựa',
      'build dua',
      'build cho',
      'build giúp',
      'build giup',
      'build cấu hình',
      'build cau hinh',
      'build một bộ',
      'build mot bo',
      'build bộ pc',
      'build bo pc',
      'build dàn pc',
      'build dan pc',
      'build máy',
      'build may',
      'tạo build',
      'tao build',
      'lên cấu hình',
      'len cau hinh',
      'tạo cấu hình',
      'tao cau hinh',
      'dựng pc',
      'dung pc',
      'dựng cấu hình',
      'dung cau hinh',
      'lắp pc',
      'lap pc',
      'lắp ráp pc',
      'lap rap pc',
      'làm cấu hình',
      'lam cau hinh',
      'tạo bộ pc',
      'tao bo pc',
      'tạo dàn pc',
      'tao dan pc',
      'cho tôi build',
      'cho toi build',
      'giúp tôi build',
      'giup toi build',
      'muốn build',
      'muon build',
      'cần build',
      'can build',
    ];
    if (explicitBuildPhrases.any(normalized.contains)) return true;
    final compactBuildCommand = RegExp(
      r'^\s*(?:(?:hãy|hay)\s+)?build\s+(?:(?:pc|máy tính|may tinh)\s+)?(?:rtx\s*)?\d{3,4}\b',
    );
    return compactBuildCommand.hasMatch(normalized) ||
        RegExp(r'^\s*build\s+(?:nó|no|card này|card nay|cấu hình|cau hinh)\b')
            .hasMatch(normalized);
  }

  Future<void> _createBuildFromChat(String prompt) async {
    if (!mounted) return;
    final areaId =
        ApiClient.instance.currentUser?['areaId']?.toString() ?? 'hcm';
    final contextText = messages
        .map((message) => message['text'] ?? '')
        .join('\n');
    final pinnedComponents = await _findPinnedComponents(
      '$contextText\n$prompt',
      areaId,
      prompt: prompt,
      preferred: widget.initialPinnedComponents,
    );
    final userRequestText = messages
        .where((message) => message['role'] == 'user')
        .map((message) => message['text'] ?? '')
        .join('\n');
    final budget = _requestedBudget(userRequestText);
    var proposalBudget = budget;
    Map<String, dynamic> proposal;
    try {
      proposal = await ApiClient.instance.generateBuildSuggestion(
        budget: proposalBudget,
        purpose: prompt,
        areaId: areaId,
        pinnedComponents: pinnedComponents,
      );
    } on ApiException catch (error) {
      final budgetRejected =
          error.statusCode == 422 &&
          (error.message.toLowerCase().contains('ngân sách') ||
              error.message.toLowerCase().contains('cấu hình tương thích'));
      if (!budgetRejected) rethrow;
      proposalBudget = (((budget * 1.25) / 1000000).ceil() * 1000000).toInt();
      if (proposalBudget <= budget) proposalBudget = budget + 5000000;
      proposal = await ApiClient.instance.generateBuildSuggestion(
        budget: proposalBudget,
        purpose: prompt,
        areaId: areaId,
        pinnedComponents: pinnedComponents,
      );
    }
    if (!mounted) return;
    final components = proposal['components'] is Map
        ? Map<String, dynamic>.from(proposal['components'] as Map)
        : <String, dynamic>{};
    final componentDetails = proposal['componentDetails'] is Map
        ? Map<String, dynamic>.from(proposal['componentDetails'] as Map)
        : <String, dynamic>{};
    if (components.isEmpty) {
      showDemoMessage(
        context,
        'AI chưa đề xuất được linh kiện cho cấu hình này.',
      );
      return;
    }
    final action = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Cấu hình AI đề xuất'),
        content: SizedBox(
          width: double.maxFinite,
          height: 410,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${proposal['name'] ?? 'BuildMate'} • ${components.length}/8 linh kiện',
                ),
                if (proposalBudget > budget) ...[
                  const SizedBox(height: 4),
                  Text(
                    'Ngân sách ${formatVnd(budget)} chưa đủ cho linh kiện đã chọn; đây là phương án gần nhất trong mức ${formatVnd(proposalBudget)}.',
                    style: const TextStyle(color: Colors.amber),
                  ),
                ],
                if (parseApiNumber(proposal['totalPrice']) != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    '${proposal['priceEstimate'] == true ? 'Tạm tính' : 'Tổng giá SQL'}: ${formatVnd(parseApiNumber(proposal['totalPrice'])!.round())}',
                    style: const TextStyle(
                      color: mint,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
                const SizedBox(height: 10),
                ...components.entries.map(
                  (entry) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Text(
                      _proposalComponentLine(
                        entry.key.toString(),
                        entry.value,
                        componentDetails,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Lưu vào tài khoản SQL để mở và chỉnh sửa trong tab Build?',
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, 'skip'),
            child: const Text('Để sau'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, 'save'),
            child: const Text('Lưu build'),
          ),
        ],
      ),
    );
    if (action != 'save' || !mounted) return;
    final previousBuildId = ApiClient.instance.buildId;
    String? createdBuildId;
    try {
      final created = await ApiClient.instance.createBuild(
        name: proposal['name']?.toString() ?? 'BuildMate AI',
        budget: (parseApiNumber(proposal['budget']) ?? budget).round(),
        areaId: areaId,
      );
      createdBuildId = created['id']?.toString();
      if (createdBuildId == null) {
        throw ApiException('SQL không trả mã build mới.');
      }
      ApiClient.instance.buildId = createdBuildId;
      for (final entry in components.entries) {
        final id = _proposalComponentId(entry.value);
        if (id.isNotEmpty) {
          await ApiClient.instance.updateComponent(entry.key, id);
        }
      }
      ApiClient.instance.buildId = previousBuildId;
      if (!mounted) return;
      showDemoMessage(context, 'Đã lưu cấu hình vào SQL. Đang mở tab Build.');
      widget.onOpenBuild?.call();
    } catch (error) {
      if (createdBuildId != null) {
        try {
          await ApiClient.instance.deleteBuild(createdBuildId);
        } catch (_) {}
      }
      if (mounted) showDemoMessage(context, 'Không lưu được cấu hình: $error');
    } finally {
      ApiClient.instance.buildId = previousBuildId;
    }
  }

  String _proposalComponentId(dynamic value) => value is Map
      ? (value['id'] ?? value['productId'] ?? '').toString()
      : value?.toString() ?? '';

  String _proposalComponentName(dynamic value) => value is Map
      ? (value['name'] ?? value['productName'] ?? value['id'] ?? 'Chưa có tên')
            .toString()
      : value?.toString() ?? 'Chưa có dữ liệu';

  String _proposalComponentLine(
    String type,
    dynamic value,
    Map<String, dynamic> componentDetails,
  ) {
    final detail = componentDetails[type];
    final name = _proposalComponentName(detail ?? value);
    final price = detail is Map ? parseApiNumber(detail['price']) : null;
    return price == null
        ? '$type: $name'
        : '$type: $name • ${formatVnd(price.round())}';
  }

  int _requestedBudget(String text) {
    final matches = RegExp(
      r'(\d+(?:[.,]\d+)?)\s*(?:triệu|trieu|tr|m)\b',
      caseSensitive: false,
    ).allMatches(text).toList();
    if (matches.isEmpty) return 40000000;
    final match = matches.last;
    final amount = double.tryParse(match.group(1)!.replaceAll(',', '.'));
    if (amount == null || amount <= 0) return 40000000;
    return (amount * 1000000).round().clamp(5000000, 2000000000).toInt();
  }

  Future<Map<String, String>> _findPinnedComponents(
    String contextText,
    String areaId, {
    String prompt = '',
    Map<String, String> preferred = const {},
  }) async {
    final validPreferred = Map<String, String>.from(preferred)
      ..removeWhere((type, id) => type.isEmpty || id.isEmpty);
    final userText = messages
        .where((message) => message['role'] == 'user')
        .map((message) => message['text'] ?? '')
        .join('\n')
        .toLowerCase();
    final latestRequest = prompt.trim().isNotEmpty ? prompt : userText;
    final explicitGpuPattern = RegExp(
      r'\b(?:nvidia\s*)?(?:geforce\s*)?rtx\s*(\d{4})(?:\s*(ti|super))?\b',
      caseSensitive: false,
    );
    final modelPattern = RegExp(
      r'\b(\d{4})(?:\s*(ti|super))?\b',
      caseSensitive: false,
    );
    final explicitPromptModel =
        explicitGpuPattern.firstMatch(prompt) ??
        (() {
          final promptSeriesMatches = modelPattern.allMatches(prompt).toList();
          return promptSeriesMatches.length == 1
              ? promptSeriesMatches.single
              : null;
        })();
    if (explicitPromptModel == null && validPreferred.isNotEmpty) {
      return validPreferred;
    }
    if (validPreferred.isNotEmpty && explicitPromptModel != null) {
      final preferredModel = explicitGpuPattern.firstMatch(contextText);
      if (preferredModel != null &&
          preferredModel.group(1) == explicitPromptModel.group(1) &&
          (preferredModel.group(2) ?? '').toLowerCase() ==
              (explicitPromptModel.group(2) ?? '').toLowerCase()) {
        return validPreferred;
      }
    }
    Match? modelMatch =
        explicitPromptModel ?? explicitGpuPattern.firstMatch(latestRequest);
    if (modelMatch == null) {
      final bareMatches = modelPattern.allMatches(latestRequest).toList();
      if (bareMatches.length == 1) modelMatch = bareMatches.single;
    }
    if (modelMatch == null && latestRequest != contextText) {
      final priorExplicitMatches = explicitGpuPattern
          .allMatches(contextText)
          .toList();
      if (priorExplicitMatches.isNotEmpty) {
        modelMatch = priorExplicitMatches.last;
      }
      if (modelMatch == null) {
        final priorBareMatches = modelPattern.allMatches(contextText).toList();
        if (priorBareMatches.length == 1) modelMatch = priorBareMatches.single;
      }
    }
    if (modelMatch == null) return const {};
    final series = modelMatch.group(1)!;
    final suffix = (modelMatch.group(2) ?? '').toLowerCase();
    final products = await ApiClient.instance.products(
      'GPU',
      query: series,
      areaId: areaId,
    );
    if (products.isEmpty) return const {};
    final requestText = latestRequest.toLowerCase();
    final asksTi = suffix == 'ti';
    final asksSuper = suffix == 'super';
    final requestedBrand = RegExp(
      r'\b(msi|asus|gigabyte|zotac|palit|galax|gainward|inno3d|pny|evga)\b',
      caseSensitive: false,
    ).firstMatch(requestText)?.group(1)?.toLowerCase();
    final candidates = products.where((item) {
      final name = item['name']?.toString().toLowerCase() ?? '';
      final isRtx = name.contains('rtx') || name.contains('geforce');
      final isTi = RegExp(r'\bti\b').hasMatch(name);
      final isSuper = name.contains('super');
      return isRtx &&
          name.contains(series) &&
          isTi == asksTi &&
          isSuper == asksSuper;
    }).toList();
    if (candidates.isEmpty) return const {};
    candidates.sort((a, b) {
      final an = a['name']?.toString().toLowerCase() ?? '';
      final bn = b['name']?.toString().toLowerCase() ?? '';
      final aBrand = requestedBrand == null
          ? 0
          : (an.contains(requestedBrand) ? 0 : 1);
      final bBrand = requestedBrand == null
          ? 0
          : (bn.contains(requestedBrand) ? 0 : 1);
      if (aBrand != bBrand) return aBrand.compareTo(bBrand);
      final aPrice = parseApiNumber(a['price']) ?? double.maxFinite;
      final bPrice = parseApiNumber(b['price']) ?? double.maxFinite;
      return aPrice.compareTo(bPrice);
    });
    final productId = candidates.first['id']?.toString();
    return productId == null ? const {} : {'GPU': productId};
  }

  void _useSuggestion(String value) {
    question
      ..text = value
      ..selection = TextSelection.collapsed(offset: value.length);
  }
}

class _SuggestionChip extends StatelessWidget {
  const _SuggestionChip({required this.text, required this.onTap});
  final String text;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => ActionChip(
    label: Text(text),
    onPressed: onTap,
    labelStyle: const TextStyle(color: mint, fontSize: 11),
    backgroundColor: greenPanel,
    side: BorderSide.none,
  );
}
