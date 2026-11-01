part of '../main.dart';

class MarketChangesScreen extends StatelessWidget {
  const MarketChangesScreen({
    super.key,
    required this.areaName,
    required this.items,
  });
  final String areaName;
  final List<Map<String, dynamic>> items;

  @override
  Widget build(BuildContext context) {
    final changed = items
        .where((item) => (parseApiNumber(item['trend']) ?? 0) != 0)
        .toList();
    return Shell(
      title: 'Biến động giá',
      subtitle: areaName,
      back: true,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(18, 8, 18, 20),
        children: [
          const InfoTile(
            icon: Icons.trending_up,
            text: 'Linh kiện có thay đổi giá trong khu vực hiện tại.',
          ),
          const SizedBox(height: 12),
          ...changed.map(
            (item) => CardBox(
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(item['name']?.toString() ?? 'Linh kiện'),
                subtitle: Text(
                  'Giá trước: ${_money(item['previousPrice'])}\nGiá hiện tại: ${_money(item['price'])}',
                ),
                trailing: Text(
                  '${(parseApiNumber(item['trend']) ?? 0).toStringAsFixed(2)}%',
                  style: TextStyle(
                    color: (parseApiNumber(item['trend']) ?? 0) < 0
                        ? mint
                        : Colors.orange,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  static String _money(dynamic value) =>
      '${(parseApiNumber(value) ?? 0).toStringAsFixed(0)}đ';
}

class CompareProductsScreen extends StatefulWidget {
  const CompareProductsScreen({super.key, this.initialProductIds = const []});
  final List<String> initialProductIds;
  @override
  State<CompareProductsScreen> createState() => _CompareProductsScreenState();
}

class _CompareProductsScreenState extends State<CompareProductsScreen> {
  late Future<List<Map<String, dynamic>>> productsFuture;
  final selected = <String>{};
  Map<String, dynamic>? result;
  String query = '';
  String typeFilter = 'Tất cả';
  Timer? _searchDebounce;
  String get areaId =>
      ApiClient.instance.currentUser?['areaId']?.toString() ?? 'hcm';

  @override
  void initState() {
    super.initState();
    selected.addAll(widget.initialProductIds.take(3));
    productsFuture = ApiClient.instance.products('');
  }

  Future<void> _compare() async {
    if (selected.length < 2 || selected.length > 3) {
      showMessage(context, 'Hãy chọn từ 2 đến 3 linh kiện để so sánh.');
      return;
    }
    try {
      final response = await ApiClient.instance.compareProducts(
        selected.toList(),
        areaId: areaId,
      );
      if (mounted) setState(() => result = response);
    } catch (error) {
      if (mounted) showMessage(context, 'Không thể so giá: $error');
    }
  }

  void _compareFromButton() {
    if (selected.length < 2 || selected.length > 3) {
      showMessage(context, 'Chọn thêm ít nhất một linh kiện để so sánh.');
      return;
    }
    _compare();
  }

  void _setQuery(String value) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 250), () {
      if (mounted) setState(() => query = value.trim().toLowerCase());
    });
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Shell(
    title: 'So giá linh kiện',
    subtitle: 'Chọn từ 2 đến 3 linh kiện • SQL $areaId',
    back: true,
    bottomNavigationBar: SafeArea(
      minimum: const EdgeInsets.fromLTRB(18, 8, 18, 12),
      child: PrimaryButton(
        text: result == null
            ? 'So sánh giá (${selected.length}/2–3)'
            : 'Cập nhật so sánh (${selected.length})',
        onPressed: _compareFromButton,
      ),
    ),
    child: FutureBuilder<List<Map<String, dynamic>>>(
      future: productsFuture,
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator(color: mint));
        }
        final products = snapshot.data!;
        final visible = products.where((item) {
          final type = item['type']?.toString() ?? '';
          final name = item['name']?.toString().toLowerCase() ?? '';
          return (typeFilter == 'Tất cả' || type == typeFilter) &&
              matchesCatalogSearch(name, query);
        }).toList();
        final types =
            products.map((item) => item['type'].toString()).toSet().toList()
              ..sort();
        types.insert(0, 'Tất cả');
        return CustomScrollView(
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(18, 8, 18, 8),
              sliver: SliverList(
                delegate: SliverChildListDelegate([
                  const InfoTile(
                    icon: Icons.compare_arrows,
                    text: 'So sánh giá hiện tại, thông số và lịch sử. Giá ước tính được đánh dấu; chỉ giá khu vực có lịch sử biến động.',
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    onChanged: _setQuery,
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.search),
                      hintText: 'Tìm tên linh kiện',
                    ),
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    initialValue: typeFilter,
                    decoration: const InputDecoration(
                      labelText: 'Loại linh kiện',
                    ),
                    items: types
                        .map(
                          (type) =>
                              DropdownMenuItem(value: type, child: Text(type)),
                        )
                        .toList(),
                    onChanged: (value) =>
                        setState(() => typeFilter = value ?? 'Tất cả'),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${visible.length} / ${products.length} linh kiện từ SQL',
                  ),
                  if (result != null) ...[
                    const SizedBox(height: 12),
                    const Text(
                      'SO SÁNH GIÁ',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    ...((result!['products'] as List? ?? const []).map(
                      (item) => ComparedProductCard(
                        product: Map<String, dynamic>.from(item as Map),
                        areaId: areaId,
                      ),
                    )),
                  ],
                ]),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 18),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate((context, index) {
                  final item = visible[index];
                  final id = item['id'].toString();
                  final price = parseApiNumber(item['price']) ?? 0;
                  final hasPrice = price > 0;
                  final isEstimate = item['priceSource'] == 'catalog_estimate';
                  return CheckboxListTile(
                    value: selected.contains(id),
                    onChanged: !hasPrice
                        ? null
                        : (checked) {
                            setState(() {
                              result = null;
                              if (checked == true && selected.length < 3) {
                                selected.add(id);
                              } else if (checked != true) {
                                selected.remove(id);
                              }
                            });
                          },
                    title: Text(item['name'].toString()),
                    subtitle: Text(
                      '${item['type']} • ${!hasPrice ? 'Chưa có giá SQL' : '${isEstimate ? '≈ ' : ''}${formatVnd(price)}${isEstimate ? ' · ước tính' : ''}'}',
                    ),
                  );
                }, childCount: visible.length),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(18, 8, 18, 20),
              sliver: SliverList(
                delegate: SliverChildListDelegate([const SizedBox(height: 8)]),
              ),
            ),
          ],
        );
      },
    ),
  );
}

class ComparedProductCard extends StatefulWidget {
  const ComparedProductCard({
    super.key,
    required this.product,
    required this.areaId,
  });
  final Map<String, dynamic> product;
  final String areaId;

  @override
  State<ComparedProductCard> createState() => _ComparedProductCardState();
}

class _ComparedProductCardState extends State<ComparedProductCard> {
  String period = 'day';
  late Future<Map<String, dynamic>> history;

  @override
  void initState() {
    super.initState();
    history = _loadHistory();
  }

  Future<Map<String, dynamic>> _loadHistory() =>
      ApiClient.instance.priceHistory(
        widget.product['id'].toString(),
        areaId: widget.areaId,
        period: period,
      );

  void _setPeriod(String value) {
    setState(() {
      period = value;
      history = _loadHistory();
    });
  }

  Future<void> _setPriceAlert() async {
    final controller = TextEditingController(
      text: (parseApiNumber(widget.product['price']) ?? 0).round().toString(),
    );
    final targetPrice = await showDialog<int>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Theo dõi giá linh kiện'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'Thông báo khi giá xuống dưới (VNĐ)',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Hủy'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(
              dialogContext,
              int.tryParse(controller.text.replaceAll(RegExp(r'[^0-9]'), '')),
            ),
            child: const Text('Lưu cảnh báo'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (targetPrice == null || targetPrice <= 0) return;
    try {
      await ApiClient.instance.createPriceAlert(
        productId: widget.product['id'].toString(),
        targetPrice: targetPrice,
        areaId: widget.areaId,
      );
      if (mounted) showDemoMessage(context, 'Đã lưu cảnh báo giá trên SQL.');
    } catch (error) {
      if (mounted) showDemoMessage(context, 'Không lưu được cảnh báo: $error');
    }
  }

  @override
  Widget build(BuildContext context) {
    final isMarketPrice = widget.product['priceSource'] == 'market';
    return CardBox(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.product['name'].toString(),
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          Text(
            '${widget.product['type']} • ${isMarketPrice ? 'Giá khu vực SQL ${widget.areaId}' : 'Giá ước tính trong catalog SQL'}',
            style: TextStyle(
              color: isMarketPrice ? muted : Colors.orange,
              fontSize: 11,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            formatVnd(widget.product['price']),
            style: TextStyle(
              color: isMarketPrice ? mint : Colors.orange,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              _specChip('Socket', widget.product['socket']),
              _specChip('RAM', widget.product['ram']),
              _specChip('Form', widget.product['form']),
              _specChip(
                'Điện',
                widget.product['power'] == null
                    ? widget.product['watts']
                    : '${widget.product['power']}W',
              ),
              _specChip(
                'Dài',
                widget.product['length'] == null
                    ? widget.product['gpuLength']
                    : '${widget.product['length']}mm',
              ),
            ],
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: isMarketPrice ? _setPriceAlert : null,
              icon: const Icon(Icons.notifications_active_outlined, size: 16),
              label: Text(
                isMarketPrice ? 'Theo dõi giá SQL' : 'Chưa có giá thị trường',
              ),
            ),
          ),
          const SizedBox(height: 8),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'day', label: Text('Ngày')),
              ButtonSegment(value: 'month', label: Text('Tháng')),
              ButtonSegment(value: 'year', label: Text('Năm')),
            ],
            selected: {period},
            onSelectionChanged: (value) => _setPeriod(value.first),
            showSelectedIcon: false,
          ),
          const SizedBox(height: 8),
          FutureBuilder<Map<String, dynamic>>(
            future: history,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const SizedBox(
                  height: 110,
                  child: Center(child: CircularProgressIndicator(color: mint)),
                );
              }
              if (snapshot.hasError) {
                return Text(
                  'Không tải được lịch sử giá: ${snapshot.error}',
                  style: const TextStyle(color: Colors.amber, fontSize: 11),
                );
              }
              final data = snapshot.data!;
              final points = (data['history'] as List? ?? const [])
                  .map((item) => Map<String, dynamic>.from(item as Map))
                  .toList();
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    data['priceSource'] == 'market'
                        ? 'Hiện tại ${formatVnd(data['price'])} • trước ${formatVnd(data['previousPrice'])} • ${parseApiNumber(data['changePercent'])?.toStringAsFixed(2) ?? '0.00'}%'
                        : 'Giá ước tính ${formatVnd(data['price'])} • chưa có giá khu vực SQL.',
                    style: TextStyle(
                      fontSize: 11,
                      color: data['priceSource'] == 'market'
                          ? null
                          : Colors.orange,
                    ),
                  ),
                  const SizedBox(height: 4),
                  SizedBox(
                    height: 110,
                    width: double.infinity,
                    child: CustomPaint(painter: _PriceChartPainter(points)),
                  ),
                  Text(
                    points.length < 2
                        ? data['priceSource'] != 'market'
                              ? 'Chưa có lịch sử giá thị trường để vẽ xu hướng.'
                              : 'SQL có ${points.length} mốc giá; cần thêm lịch sử để vẽ xu hướng.'
                        : '${points.length} mốc giá ${period == 'day'
                              ? 'theo ngày'
                              : period == 'month'
                              ? 'theo tháng'
                              : 'theo năm'}',
                    style: const TextStyle(color: muted, fontSize: 10),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _specChip(String label, dynamic value) {
    if (value == null || value.toString().isEmpty) {
      return const SizedBox.shrink();
    }
    return Chip(
      label: Text('$label: $value', style: const TextStyle(fontSize: 10)),
      visualDensity: VisualDensity.compact,
    );
  }
}

class _PriceChartPainter extends CustomPainter {
  const _PriceChartPainter(this.points);
  final List<Map<String, dynamic>> points;

  @override
  void paint(Canvas canvas, Size size) {
    final grid = Paint()
      ..color = stroke
      ..strokeWidth = 1;
    for (var line = 1; line <= 3; line++) {
      final y = size.height * line / 4;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }
    final values = points
        .map((point) => parseApiNumber(point['price']) ?? 0)
        .toList();
    if (values.isEmpty) return;
    final minValue = values.reduce((a, b) => a < b ? a : b);
    final maxValue = values.reduce((a, b) => a > b ? a : b);
    final spread = (maxValue - minValue).abs();
    final path = Path();
    final linePaint = Paint()
      ..color = mint
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5;
    for (var index = 0; index < values.length; index++) {
      final x = values.length == 1
          ? size.width / 2
          : size.width * index / (values.length - 1);
      final normalized = spread == 0 ? .5 : (values[index] - minValue) / spread;
      final y = size.height - 10 - normalized * (size.height - 20);
      if (index == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
      canvas.drawCircle(Offset(x, y), 3.5, Paint()..color = mint);
    }
    canvas.drawPath(path, linePaint);
  }

  @override
  bool shouldRepaint(covariant _PriceChartPainter oldDelegate) =>
      oldDelegate.points != points;
}
