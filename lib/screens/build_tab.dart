// ignore_for_file: use_build_context_synchronously

part of '../main.dart';

class BuildTab extends StatefulWidget {
  const BuildTab({super.key, this.initialBuild, this.loadLatest = true});
  final Map<String, dynamic>? initialBuild;
  final bool loadLatest;
  @override
  State<BuildTab> createState() => _BuildTabState();
}

class _BuildTabState extends State<BuildTab> {
  bool saved = false;
  bool loadingBuild = false;
  Map<String, dynamic>? loadedBuild;
  final selectedIds = <String, String>{};
  final powers = <String, int>{};
  final missingPriceTypes = <String>{};
  final estimatePriceTypes = <String>{};
  final selected = <String, String>{
    'CPU': 'Chọn CPU',
    'MAINBOARD': 'Chọn MAINBOARD',
    'GPU': 'Chọn GPU',
    'RAM': 'Chọn RAM',
    'SSD': 'Chọn SSD',
    'PSU': 'Chọn nguồn',
    'CASE': 'Chọn CASE',
    'TẢN NHIỆT': 'Chọn tản nhiệt',
  };
  final prices = <String, double>{};
  Timer? _compatibilityDebounce;
  Map<String, dynamic>? liveCompatibility;
  bool checkingCompatibility = false;
  bool get isComplete =>
      selected.values.every((value) => !value.startsWith('Chọn'));
  bool get canCheckCompatibility => selectedIds.length >= 2;
  Map<String, dynamic>? get _currentBuild => loadedBuild ?? widget.initialBuild;
  String get _buildTitle => _currentBuild?['name']?.toString() ?? 'Build mới';
  String get _buildSubtitle {
    final areaId = _currentBuild?['areaId']?.toString();
    const areas = {
      'hcm': 'TP. Hồ Chí Minh',
      'hanoi': 'Hà Nội',
      'danang': 'Đà Nẵng',
    };
    final area = areas[areaId] ?? 'Khu vực hiện tại';
    final selectedCount = selected.values
        .where((value) => !value.startsWith('Chọn'))
        .length;
    return '$selectedCount/8 linh kiện • $area';
  }

  @override
  void initState() {
    super.initState();
    final build = widget.initialBuild;
    if (build == null) {
      ApiClient.instance.buildId = null;
      if (widget.loadLatest) _loadLatestBuild();
      return;
    }
    _applyBuild(build);
  }

  Future<void> reloadLatestBuild() => _loadLatestBuild();

  Future<void> _loadLatestBuild() async {
    if (ApiClient.instance.token == null) return;
    setState(() => loadingBuild = true);
    try {
      final builds = await ApiClient.instance.builds();
      if (!mounted) return;
      if (builds.isEmpty) {
        ApiClient.instance.buildId = null;
        return;
      }
      _applyBuild(builds.first);
    } catch (error) {
      if (mounted) {
        showMessage(context, 'Không tải được cấu hình gần nhất: $error');
      }
    } finally {
      if (mounted) setState(() => loadingBuild = false);
    }
  }

  void _applyBuild(Map<String, dynamic> build) {
    loadedBuild = build;
    ApiClient.instance.buildId = build['id'] as String?;
    selectedIds.clear();
    powers.clear();
    prices.clear();
    selected.updateAll(
      (type, _) => type == 'PSU' ? 'Chọn nguồn' : 'Chọn $type',
    );
    missingPriceTypes.clear();
    estimatePriceTypes.clear();
    final components = build['components'];
    if (components is! Map) return;
    for (final entry in components.entries) {
      final type = entry.key.toString();
      final item = entry.value;
      if (item is Map) {
        selected[type] = item['name']?.toString() ?? selected[type]!;
        final itemPrice = parseApiNumber(item['price']) ?? 0;
        prices[type] = itemPrice / 1000000;
        if (itemPrice <= 0) {
          missingPriceTypes.add(type);
        } else if (item['priceSource'] != 'market') {
          estimatePriceTypes.add(type);
        }
        selectedIds[type] = item['id']?.toString() ?? '';
        powers[type] = (parseApiNumber(item['power']) ?? 0).toInt();
      }
    }
    if (mounted) setState(() {});
    if (selectedIds.length >= 2) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _scheduleCompatibilityCheck();
      });
    }
  }

  Future<void> _openCompatibilityDetails() async {
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => CompatibilityScreen(report: liveCompatibility),
      ),
    );
    if (changed == true) await _loadLatestBuild();
  }

  Future<void> _choose(String type) async {
    final result = await Navigator.push<Product>(
      context,
      MaterialPageRoute(
        builder: (_) => ProductListScreen(
          componentType: type,
          areaId:
              _currentBuild?['areaId']?.toString() ??
              ApiClient.instance.currentUser?['areaId']?.toString() ??
              'hcm',
          onSelected: (product) => Navigator.pop(context, product),
        ),
      ),
    );
    if (result != null) {
      final productId = result.id;
      setState(() {
        selected[type] = result.name;
        prices[type] = productPriceInMillions(result.price);
        missingPriceTypes.remove(type);
        if (result.priceSource == 'market') {
          estimatePriceTypes.remove(type);
        } else {
          estimatePriceTypes.add(type);
        }
        powers[type] = result.powerW;
        saved = false;
        if (productId.isNotEmpty) {
          selectedIds[type] = productId;
        }
      });
      if (ApiClient.instance.token == null) {
        if (mounted) {
          showDemoMessage(
            context,
            'Đã chọn tạm. Hãy đăng nhập để đồng bộ linh kiện vào tài khoản.',
          );
        }
        return;
      }
      if (productId.isEmpty) {
        if (mounted) {
          showDemoMessage(context, 'Sản phẩm chưa có mã API hợp lệ.');
        }
        return;
      }
      selectedIds[type] = productId;
      try {
        final updatedBuild = await ApiClient.instance.updateComponent(
          type,
          productId,
        );
        if (mounted) {
          setState(() => loadedBuild = updatedBuild);
          _scheduleCompatibilityCheck();
        }
      } catch (error) {
        if (mounted) {
          showDemoMessage(context, 'Chưa đồng bộ được linh kiện: $error');
        }
      }
    }
  }

  void _scheduleCompatibilityCheck() {
    _compatibilityDebounce?.cancel();
    if (selectedIds.length < 2 || ApiClient.instance.token == null) {
      setState(() {
        liveCompatibility = null;
        checkingCompatibility = false;
      });
      return;
    }
    setState(() {
      checkingCompatibility = true;
      liveCompatibility = null;
    });
    _compatibilityDebounce = Timer(const Duration(milliseconds: 450), () async {
      final selectedSnapshot = Map<String, String>.from(selectedIds);
      try {
        final report = await ApiClient.instance.checkBuild(selectedSnapshot);
        if (mounted && mapEquals(selectedSnapshot, selectedIds)) {
          setState(() {
            liveCompatibility = report;
            checkingCompatibility = false;
          });
        }
      } catch (error) {
        if (mounted) {
          setState(() {
            checkingCompatibility = false;
            liveCompatibility = {
              'status': 'error',
              'message': 'Chưa kiểm tra được: $error',
            };
          });
        }
      }
    });
  }

  @override
  void dispose() {
    _compatibilityDebounce?.cancel();
    super.dispose();
  }

  Future<void> _removeComponent(String type) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Xóa linh kiện?'),
        content: Text('Bạn muốn gỡ bỏ $type khỏi cấu hình này?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Hủy'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Xóa', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      if (ApiClient.instance.token == null ||
          ApiClient.instance.buildId == null) {
        if (mounted) {
          showDemoMessage(context, 'Hãy lưu cấu hình trước khi xóa linh kiện.');
        }
        return;
      }
      try {
        final updatedBuild = await ApiClient.instance.updateComponent(
          type,
          null,
        );
        if (!mounted) return;
        setState(() {
          selected[type] = 'Chọn $type';
          prices[type] = 0;
          missingPriceTypes.remove(type);
          estimatePriceTypes.remove(type);
          selectedIds.remove(type);
          loadedBuild = updatedBuild;
          saved = false;
        });
        _scheduleCompatibilityCheck();
        showDemoMessage(context, 'Đã gỡ bỏ $type khỏi cấu hình.');
      } catch (error) {
        if (mounted) {
          showDemoMessage(context, 'Lỗi khi xóa linh kiện: $error');
        }
      }
    }
  }

  Future<void> _deleteCurrentBuild() async {
    final id = _currentBuild?['id']?.toString();
    if (id == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Xóa cấu hình?'),
        content: const Text('Cấu hình này sẽ bị xóa khỏi tài khoản.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Hủy'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Xóa'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await ApiClient.instance.deleteBuild(id);
      if (mounted) {
        if (widget.initialBuild != null) {
          showDemoMessage(context, 'Đã xóa cấu hình.');
          Navigator.pop(context, true);
        } else {
          setState(() {
            loadedBuild = null;
            saved = false;
            selectedIds.clear();
            powers.clear();
            prices.clear();
            missingPriceTypes.clear();
            estimatePriceTypes.clear();
            selected.updateAll(
              (type, _) => type == 'PSU' ? 'Chọn nguồn' : 'Chọn $type',
            );
          });
          ApiClient.instance.buildId = null;
          showDemoMessage(context, 'Đã xóa cấu hình.');
        }
      }
    } catch (error) {
      if (mounted) showDemoMessage(context, 'Không thể xóa cấu hình: $error');
    }
  }

  String _total() {
    if (missingPriceTypes.isNotEmpty) return 'Thiếu giá SQL';
    final total = prices.values.fold<double>(0, (sum, value) => sum + value);
    final formatted = '${total.toStringAsFixed(2).replaceAll('.', ',')}tr';
    return estimatePriceTypes.isEmpty ? formatted : '$formatted*';
  }

  int get _estimatedPower =>
      selectedIds.keys.fold<int>(0, (sum, type) => sum + (powers[type] ?? 0));
  int get _recommendedPsu {
    if (selectedIds.isEmpty) return 0;
    final fromApi =
        parseApiNumber(_currentBuild?['recommendedPsu'])?.round() ?? 0;
    final gpu = selected['GPU'];
    final manufacturerMinimum =
        ApiClient.instance.productRecommendedPsuByName[gpu] ?? 0;
    final calculated = ((_estimatedPower * 1.3 + 100 + 49) / 50).floor() * 50;
    return math
        .max(450, math.max(fromApi, math.max(manufacturerMinimum, calculated)))
        .clamp(450, 2000)
        .toInt();
  }

  Future<void> _saveBuild() async {
    if (missingPriceTypes.isNotEmpty) {
      showDemoMessage(context, 'Hãy bổ sung giá SQL trước khi lưu build này.');
      return;
    }
    final selectedCount = selectedIds.values
        .where((productId) => productId.isNotEmpty)
        .length;
    if (selectedCount == 0) {
      showDemoMessage(context, 'Hãy chọn ít nhất một linh kiện trước khi lưu.');
      return;
    }
    if (ApiClient.instance.token == null) {
      showDemoMessage(context, 'Hãy đăng nhập để lưu cấu hình vào tài khoản.');
      return;
    }
    try {
      if (ApiClient.instance.buildId == null) {
        await ApiClient.instance.createBuild();
      }
      for (final entry in selectedIds.entries) {
        if (entry.value.isNotEmpty) {
          await ApiClient.instance.updateComponent(entry.key, entry.value);
        }
      }
      if (!mounted) return;
      setState(() => saved = true);
      showDemoMessage(
        context,
        selectedCount == selected.length
            ? 'Đã lưu đầy đủ cấu hình lên tài khoản.'
            : 'Đã lưu $selectedCount/8 linh kiện lên tài khoản.',
      );
    } catch (error) {
      if (mounted) showDemoMessage(context, 'Không thể lưu cấu hình: $error');
    }
  }

  @override
  Widget build(BuildContext context) => Shell(
    title: _buildTitle,
    subtitle: _buildSubtitle,
    action: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        TextButton.icon(
          onPressed: _saveBuild,
          icon: Icon(saved ? Icons.check : Icons.bookmark_border, color: mint),
          label: Text(
            saved ? 'Đã lưu' : 'Lưu',
            style: const TextStyle(color: mint),
          ),
        ),
        if (_currentBuild != null)
          IconButton(
            tooltip: 'Xóa cấu hình',
            onPressed: _deleteCurrentBuild,
            icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
          ),
      ],
    ),
    child: SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(18, 6, 18, 20),
        children: [
          ProgressLine(
            label: 'TIẾN ĐỘ BUILD',
            value: '${(selectedIds.length / selected.length * 100).round()}%',
            progress: selectedIds.length / 8,
          ),
          ProgressLine(
            label: 'TẢI ƯỚC TÍNH • PSU ĐỀ NGHỊ',
            value: selectedIds.isEmpty
                ? 'Chưa đủ dữ liệu'
                : '~${_estimatedPower}W tải • ≥${_recommendedPsu}W nguồn',
            progress: selectedIds.isEmpty || _recommendedPsu == 0
                ? 0
                : (_estimatedPower / _recommendedPsu)
                      .clamp(0.0, 1.0)
                      .toDouble(),
            amber: true,
          ),
          if (checkingCompatibility)
            const CardBox(
              child: Row(
                children: [
                  SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  SizedBox(width: 10),
                  Text('Đang kiểm tra tương thích…'),
                ],
              ),
            ),
          if (liveCompatibility != null)
            _LiveCompatibilitySummary(
              report: liveCompatibility!,
              onDetails: _openCompatibilityDetails,
            ),
          PCAssemblyPreview(installedTypes: selectedIds.keys.toSet()),
          ...selected.entries.map(
            (item) => ComponentRow(
              type: item.key,
              name: item.value,
              price: missingPriceTypes.contains(item.key)
                  ? 'Thiếu giá SQL'
                  : (prices[item.key] ?? 0) == 0
                  ? '–'
                  : estimatePriceTypes.contains(item.key)
                  ? '~${prices[item.key]!.toStringAsFixed(2).replaceAll('.', ',')}tr'
                  : '${prices[item.key]!.toStringAsFixed(2).replaceAll('.', ',')}tr',
              onTap: () => _choose(item.key),
              onDelete: item.value.startsWith('Chọn')
                  ? null
                  : () => _removeComponent(item.key),
            ),
          ),
          const SizedBox(height: 18),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Tag(
                selectedIds.length < 2
                    ? '⚠ CHỌN THÊM LINH KIỆN'
                    : isComplete
                    ? '✓ ĐỦ 8 LINH KIỆN'
                    : '✓ CÓ THỂ KIỂM TRA',
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  const Text(
                    'TẠM TÍNH',
                    style: TextStyle(color: muted, fontSize: 10),
                  ),
                  Text(
                    _total(),
                    style: const TextStyle(color: mint, fontSize: 21),
                  ),
                  if (missingPriceTypes.isNotEmpty ||
                      estimatePriceTypes.isNotEmpty)
                    Text(
                      missingPriceTypes.isNotEmpty
                          ? '${missingPriceTypes.length} món chưa có giá; tổng chưa hoàn chỉnh.'
                          : '* Giá ước tính, chưa phải giá thị trường.',
                      textAlign: TextAlign.end,
                      style: const TextStyle(color: Colors.orange, fontSize: 9),
                    ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          SecondaryButton(
            text: 'Kiểm tra tương thích',
            onPressed: () async {
              if (!canCheckCompatibility) {
                showDemoMessage(
                  context,
                  'Cần chọn ít nhất hai linh kiện để kiểm tra.',
                );
                return;
              }
              if (ApiClient.instance.token != null) {
                try {
                  final report = await ApiClient.instance.checkBuild(
                    selectedIds,
                  );
                  if (!mounted) return;
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => CompatibilityScreen(report: report),
                    ),
                  );
                  return;
                } catch (error) {
                  if (mounted) {
                    showDemoMessage(context, 'Không kiểm tra được: $error');
                  }
                  return;
                }
              }
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const CompatibilityScreen()),
              );
            },
          ),
        ],
      ),
    ),
  );
}
