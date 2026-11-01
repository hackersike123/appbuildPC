part of '../main.dart';

class ScannerScreen extends StatefulWidget {
  const ScannerScreen({super.key, this.initialAnalysis, this.onOpenBuild});
  final String? initialAnalysis;
  final VoidCallback? onOpenBuild;
  @override
  State<ScannerScreen> createState() => _ScannerScreenState();
}

class _ScannerScreenState extends State<ScannerScreen> {
  bool scanned = false;
  XFile? selectedImage;
  String? analysis;
  bool analyzing = false;
  bool loadingHistory = false;
  List<Map<String, dynamic>> scanHistory = const [];

  @override
  void initState() {
    super.initState();
    analysis = widget.initialAnalysis;
    scanned = analysis != null;
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    if (ApiClient.instance.token == null) return;
    setState(() => loadingHistory = true);
    try {
      final result = await ApiClient.instance.scans();
      if (mounted) setState(() => scanHistory = result);
    } catch (error) {
      if (mounted) {
        showDemoMessage(context, 'Không tải được lịch sử quét: $error');
      }
    } finally {
      if (mounted) setState(() => loadingHistory = false);
    }
  }

  Future<void> _pickAndAnalyze(ImageSource source) async {
    if (source == ImageSource.camera &&
        !await requestCameraPermission(context)) {
      return;
    }
    final image = await ImagePicker().pickImage(
      source: source,
      imageQuality: 70,
      maxWidth: 1024,
    );
    if (image == null || !mounted) return;
    if (ApiClient.instance.token == null) {
      showDemoMessage(context, 'Đăng nhập để lưu lịch sử quét vào tài khoản.');
      return;
    }
    setState(() {
      selectedImage = image;
      analysis = null;
      analyzing = true;
      scanned = true;
    });
    try {
      final bytes = await image.readAsBytes();
      if (bytes.length > 4_000_000) {
        throw ApiException(
          'Ảnh còn quá lớn. Hãy chụp lại gần hơn hoặc chọn ảnh nhỏ hơn 4 MB.',
        );
      }
      final scan = await ApiClient.instance.analyzeProductImage(
        imageBytes: bytes,
        imageMimeType: image.name.toLowerCase().endsWith('.png')
            ? 'image/png'
            : image.name.toLowerCase().endsWith('.webp')
            ? 'image/webp'
            : 'image/jpeg',
      );
      final answer =
          scan['analysis']?.toString() ?? 'AI chưa nhận diện được sản phẩm.';
      final product = scan['product'] is Map
          ? Map<String, dynamic>.from(scan['product'] as Map)
          : null;
      final candidateProducts = scan['candidateProducts'] is List
          ? (scan['candidateProducts'] as List)
                .whereType<Map>()
                .map((item) => Map<String, dynamic>.from(item))
                .toList()
          : <Map<String, dynamic>>[];
      Map<String, dynamic>? selectedProduct = product;
      if (mounted) {
        setState(() => analysis = answer);
        await _loadHistory();
        if (selectedProduct != null) {
          await _offerGeneratedBuild(scan, selectedProduct);
        } else if (candidateProducts.isNotEmpty) {
          selectedProduct = await _chooseScanCandidate(candidateProducts);
          if (selectedProduct != null) {
            await _offerGeneratedBuild(scan, selectedProduct);
          }
        }
        if (!mounted) return;
        // Keep a clean scanner route underneath consultation, while history stays in SQL.
        setState(() {
          selectedImage = null;
          analysis = null;
          scanned = false;
        });
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ChatTab(
              initialPrompt: answer,
              initialPinnedComponents: selectedProduct == null
                  ? const {}
                  : {
                      selectedProduct['type']?.toString() ?? 'GPU':
                          selectedProduct['id']?.toString() ?? '',
                    },
              onOpenBuild: widget.onOpenBuild,
            ),
          ),
        );
      }
    } catch (error) {
      if (mounted) setState(() => analysis = 'Không thể phân tích ảnh: $error');
    } finally {
      if (mounted) setState(() => analyzing = false);
    }
  }

  Future<Map<String, dynamic>?> _chooseScanCandidate(
    List<Map<String, dynamic>> candidates,
  ) => showDialog<Map<String, dynamic>>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('AI tìm được sản phẩm gần giống'),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Ảnh chưa đủ rõ để xác nhận SKU. Chọn một mẫu trong catalog SQL để xem cấu hình build tương tự:',
              ),
              const SizedBox(height: 8),
              ...candidates.map(
                (item) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(item['name']?.toString() ?? 'Sản phẩm SQL'),
                  subtitle: Text(
                    '${item['type'] ?? 'Linh kiện'} • ${formatVnd(parseApiNumber(item['price'])?.round() ?? 0)}',
                  ),
                  trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                  onTap: () => Navigator.pop(dialogContext, item),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: const Text('Bỏ qua'),
        ),
      ],
    ),
  );

  Future<void> _offerGeneratedBuild(
    Map<String, dynamic> scan,
    Map<String, dynamic> product,
  ) async {
    final type = product['type']?.toString() ?? '';
    final productId = product['id']?.toString() ?? '';
    if (type.isEmpty || productId.isEmpty) return;
    final areaId =
        ApiClient.instance.currentUser?['areaId']?.toString() ?? 'hcm';
    Map<String, dynamic> proposal;
    try {
      proposal = await ApiClient.instance.generateBuildSuggestion(
        budget: 40000000,
        purpose: 'Build PC có linh kiện ${product['name']}',
        areaId: areaId,
        pinnedComponents: {type: productId},
      );
    } catch (_) {
      if (mounted) {
        showDemoMessage(
          context,
          'Chưa tạo được cấu hình từ catalog SQL. Hãy kiểm tra kết nối rồi thử lại; chưa có build nào được lưu.',
        );
      }
      return;
    }
    if (!mounted) return;
    final components = proposal['components'] is Map
        ? Map<String, dynamic>.from(proposal['components'] as Map)
        : <String, dynamic>{type: productId};
    final save = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Tạo cấu hình từ sản phẩm quét?'),
        content: Text(
          'Đã nhận diện ${product['name']}. Tạo cấu hình nháp gồm ${components.length}/8 linh kiện và lưu vào tài khoản SQL?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Bỏ qua'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Lưu vào tài khoản'),
          ),
        ],
      ),
    );
    if (save != true || !mounted) return;
    final previousBuildId = ApiClient.instance.buildId;
    String? createdBuildId;
    try {
      final created = await ApiClient.instance.createBuild(
        name: proposal['name']?.toString() ?? 'Build nháp từ sản phẩm quét',
        budget: (parseApiNumber(proposal['budget']) ?? 40000000).round(),
        areaId: areaId,
      );
      final newBuildId = created['id']?.toString();
      if (newBuildId == null) {
        throw ApiException('SQL không trả mã cấu hình mới.');
      }
      createdBuildId = newBuildId;
      ApiClient.instance.buildId = newBuildId;
      for (final entry in components.entries) {
        final componentId = entry.value?.toString() ?? '';
        if (componentId.isNotEmpty) {
          await ApiClient.instance.updateComponent(entry.key, componentId);
        }
      }
      await ApiClient.instance.confirmScan(scan['id'].toString(), productId);
      if (mounted) {
        showDemoMessage(
          context,
          'Đã lưu build ${components.length}/8 linh kiện vào SQL.',
        );
      }
      await _loadHistory();
    } catch (error) {
      if (createdBuildId != null) {
        try {
          await ApiClient.instance.deleteBuild(createdBuildId);
        } catch (_) {}
      }
      if (mounted) {
        showDemoMessage(context, 'Không lưu được build vào SQL: $error');
      }
    } finally {
      ApiClient.instance.buildId = previousBuildId;
    }
  }

  Future<void> _showScanHistory() => showModalBottomSheet<void>(
    context: context,
    backgroundColor: panel,
    builder: (sheetContext) => SafeArea(
      child: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.all(18),
        children: [
          const Text(
            'Lịch sử quét đã lưu',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          if (loadingHistory)
            const Center(child: CircularProgressIndicator(color: mint))
          else if (scanHistory.isEmpty)
            const Text(
              'Chưa có lịch sử trong tài khoản SQL.',
              style: TextStyle(color: muted),
            )
          else
            ...scanHistory.map(
              (result) => CardBox(
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.qr_code_scanner, color: mint),
                  title: Text(
                    result['productName']?.toString() ?? 'Chưa nhận diện được',
                  ),
                  subtitle: Text(
                    '${result['productType'] ?? result['status']} • ${result['createdAt'] ?? ''}\n${result['analysis'] ?? ''}',
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: IconButton(
                    tooltip: 'Xóa lịch sử',
                    onPressed: () => _deleteScan(result),
                    icon: const Icon(
                      Icons.delete_outline,
                      color: Colors.redAccent,
                    ),
                  ),
                  onTap: () => _showScanDetails(result),
                ),
              ),
            ),
        ],
      ),
    ),
  );

  Future<void> _showScanDetails(Map<String, dynamic> scan) async {
    try {
      final details = await ApiClient.instance.scanDetails(
        scan['id'].toString(),
      );
      if (!mounted) return;
      final imageData = details['imageData']?.toString();
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(
            details['product']?['name']?.toString() ??
                scan['productName']?.toString() ??
                'Kết quả quét',
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (imageData != null && imageData.isNotEmpty)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.memory(
                      base64Decode(imageData),
                      fit: BoxFit.contain,
                    ),
                  ),
                const SizedBox(height: 10),
                SelectableText(
                  details['analysis']?.toString() ??
                      'Không có phân tích lưu trong SQL.',
                ),
                const SizedBox(height: 8),
                Text(
                  'Thời gian: ${details['createdAt'] ?? ''}',
                  style: const TextStyle(color: muted, fontSize: 11),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Đóng'),
            ),
          ],
        ),
      );
    } catch (error) {
      if (mounted) {
        showDemoMessage(context, 'Không mở được chi tiết lịch sử: $error');
      }
    }
  }

  Future<void> _deleteScan(Map<String, dynamic> scan) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Xóa lịch sử quét?'),
        content: const Text(
          'Ảnh và kết quả lưu trong tài khoản SQL sẽ bị xóa.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Hủy'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Xóa'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await ApiClient.instance.deleteScan(scan['id'].toString());
      await _loadHistory();
    } catch (error) {
      if (mounted) showDemoMessage(context, 'Không xóa được lịch sử: $error');
    }
  }

  @override
  Widget build(BuildContext context) => Shell(
    title: 'Nhận diện linh kiện',
    subtitle: 'Đưa sản phẩm hoặc hộp vào khung',
    back: true,
    action: TextButton(
      onPressed: _showScanHistory,
      child: const Text('Lịch sử', style: TextStyle(color: mint)),
    ),
    child: SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(18, 8, 18, 20),
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: Stack(
              children: [
                selectedImage == null
                    ? Image.asset(
                        'assets/figma/scan.jpg',
                        height: 500,
                        width: double.infinity,
                        fit: BoxFit.cover,
                      )
                    : FutureBuilder(
                        future: selectedImage!.readAsBytes(),
                        builder: (context, snapshot) => snapshot.hasData
                            ? Image.memory(
                                snapshot.data!,
                                height: 500,
                                width: double.infinity,
                                fit: BoxFit.cover,
                              )
                            : const SizedBox(
                                height: 500,
                                child: Center(
                                  child: CircularProgressIndicator(),
                                ),
                              ),
                      ),
                Positioned.fill(
                  child: Container(
                    decoration: BoxDecoration(
                      border: Border.all(color: mint, width: 2),
                      borderRadius: BorderRadius.circular(18),
                    ),
                  ),
                ),
                Positioned(
                  top: 14,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: Tag(
                      analyzing
                          ? 'AI ĐANG PHÂN TÍCH'
                          : analysis != null
                          ? 'ĐÃ PHÂN TÍCH'
                          : scanned
                          ? 'ẢNH ĐÃ CHỌN'
                          : 'SẴN SÀNG QUÉT',
                    ),
                  ),
                ),
                Positioned(
                  left: 14,
                  right: 14,
                  bottom: 15,
                  child: Text(
                    analysis != null || scanned
                        ? 'SẴN SÀNG PHÂN TÍCH ẢNH'
                        : 'SẴN SÀNG QUÉT\nĐưa linh kiện vào khung',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (analysis != null) ...[
            const SizedBox(height: 12),
            CardBox(
              child: SelectableText(
                analysis!,
                style: const TextStyle(fontSize: 13, height: 1.45),
              ),
            ),
          ],
          const SizedBox(height: 18),
          Center(
            child: InkWell(
              borderRadius: BorderRadius.circular(40),
              onTap: analyzing
                  ? null
                  : () => _pickAndAnalyze(ImageSource.camera),
              child: CircleAvatar(
                radius: 34,
                backgroundColor: mint,
                child: analyzing
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(color: bg),
                      )
                    : const Icon(Icons.camera_alt, color: bg, size: 28),
              ),
            ),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: analyzing
                ? null
                : () => _pickAndAnalyze(ImageSource.gallery),
            icon: const Icon(Icons.photo_library_outlined),
            label: const Text('Chọn ảnh từ thư viện để phân tích'),
          ),
          const SizedBox(height: 10),
          const Center(
            child: Text(
              'Chụp hoặc chọn ảnh • LM Studio Vision sẽ phân tích',
              style: TextStyle(color: muted),
            ),
          ),
        ],
      ),
    ),
  );
}
